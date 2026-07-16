package com.example.background_beacon_sdk.core

import android.bluetooth.le.ScanResult
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation

/**
 * รัน Dart callback ของ app โดยไม่มี UI — ทางเดินของ event ตอน app โดน kill
 *
 * Flow: BeaconScanReceiver ถูกปลุก (ไม่มี engine) → runner สร้าง FlutterEngine
 * → รัน `backgroundCallbackDispatcher` (Dart) ผ่าน callback handle ที่
 * persist ไว้ → queue event รอจน Dart ส่ง `backgroundReady` → flush
 *
 * Engine ถูก cache ไว้ตลอดอายุ process — batch ถัดไป (ทุก ~scanIntervalMs)
 * ไม่ต้องจ่ายค่า spin-up ใหม่ (หลายร้อย ms) OS จะเก็บ process เองเมื่อ RAM ตึง
 *
 * State machine enter/exit ที่นี่ persist ใน BeaconStore (คนละชุดกับ
 * RegionStateTracker ของ in-process mode) — หลัง process ตาย state เริ่มว่าง
 * beacon ที่ยังอยู่ในเขตจะได้ enter ซ้ำหนึ่งครั้ง: ยอมรับ, จดใน README
 *
 * Thread: ทุกอย่างบน main thread (receiver + engine + channel callback
 * อยู่ main อยู่แล้ว) — ไม่มี lock
 */
internal object HeadlessBeaconRunner {

    private const val TAG = "HeadlessBeaconRunner"

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var dartReady = false

    /** event ที่มาก่อน Dart พร้อม — flush ตอน backgroundReady */
    private val queuedEvents = mutableListOf<Map<String, Any>>()

    /** goAsync window ที่รอ event ของตัวเอง flush — ปิดพร้อมกันตอน flush สำเร็จ */
    private val pendingCompletions = mutableListOf<Completion>()

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * ประมวลผล batch จาก PendingIntent scan ในโหมดไม่มี engine หลัก
     * [onComplete] ถูกเรียกเสมอ (งานเสร็จ/ผิดพลาด/timeout) — receiver ใช้ปิด
     * goAsync window
     */
    fun dispatch(context: Context, results: List<ScanResult>, onComplete: () -> Unit) {
        val completion = Completion(onComplete)
        // เพดานกันค้าง: handle เสีย/Dart ไม่ตอบ — ปล่อย receiver จบก่อน OS ฆ่า
        mainHandler.postDelayed({ completion.complete() }, COMPLETE_TIMEOUT_MS)

        val appContext = context.applicationContext
        val handles = BeaconStore.loadCallbackHandles(appContext)
        if (handles == null) {
            completion.complete() // app ไม่เคย register — ไม่มีอะไรให้ทำ
            return
        }

        val events = buildEvents(appContext, results)
        if (events.isEmpty()) {
            completion.complete()
            return
        }

        val callbackHandle = handles.second
        events.forEach { event ->
            queuedEvents.add(
                mapOf("callbackHandle" to callbackHandle, "event" to event.toMap()))
        }

        ensureEngine(appContext, dispatcherHandle = handles.first)
        if (engine == null) {
            completion.complete() // handle เสีย — queue ถูกทิ้งแล้ว
            return
        }

        // ปิด window เมื่อ event ถูก flush จริง (Dart ready) — ห้ามปิดตรงนี้:
        // engine เพิ่ง spin-up dartReady ยัง false, ปิดก่อน = process ตายก่อนส่ง
        pendingCompletions.add(completion)
        flushIfReady()
    }

    /** สร้าง enter/ranged/exit จาก batch + inside-state ที่ persist ไว้ */
    private fun buildEvents(
        context: Context,
        results: List<ScanResult>,
    ): List<BeaconEventData> {
        val regions = BeaconStore.loadRegions(context)
        val settings = BeaconStore.loadSettings(context)
        if (regions.isEmpty() || settings == null) return emptyList()

        val insideState = BeaconStore.loadInsideState(context)
        val now = System.currentTimeMillis()
        val events = mutableListOf<BeaconEventData>()

        // sighting ราย beacon (dedupe key เดียวกับ in-process mode เก็บค่าอ่านล่าสุด)
        val sightings = LinkedHashMap<String, Pair<String, BeaconData>>()
        results.forEach { result ->
            val beacon = BeaconParser.parse(result) ?: return@forEach
            val region = regions.firstOrNull {
                it.matches(beacon.uuid, beacon.major, beacon.minor)
            } ?: return@forEach

            if (!insideState.containsKey(region.identifier)) {
                events.add(BeaconEventData("enterRegion", region.identifier, listOf(beacon)))
            }
            insideState[region.identifier] = now
            sightings["${beacon.uuid}/${beacon.major}/${beacon.minor}"] =
                region.identifier to beacon
        }

        if (settings.rangingEnabled) {
            sightings.values
                .groupBy({ it.first }, { it.second })
                .forEach { (identifier, beacons) ->
                    events.add(BeaconEventData("ranged", identifier, beacons))
                }
        }

        // exit เช็คได้เฉพาะตอนถูกปลุก — ถ้าไม่มี beacon ไหนปลุกเลย exit จะค้าง
        // จนกว่า process ถูกปลุกครั้งถัดไปหรือ app เปิด (จดใน README)
        insideState.filterValues { now - it > settings.exitTimeoutMs }.keys.forEach {
            insideState.remove(it)
            events.add(BeaconEventData("exitRegion", it, emptyList()))
        }

        BeaconStore.saveInsideState(context, insideState)
        return events
    }

    private fun ensureEngine(context: Context, dispatcherHandle: Long) {
        if (engine != null) return

        // loader ต้องมาก่อน lookupCallbackInformation — ตัว lookup เรียก native
        // เข้า libflutter.so ซึ่ง process ที่เพิ่งถูกปลุกยังไม่ได้ load
        // (สลับลำดับ = UnsatisfiedLinkError → crash loop → OS แบนการปลุก)
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(context)
        }
        loader.ensureInitializationComplete(context, null)

        val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle)
        if (callbackInfo == null) {
            // app ถูก build ใหม่แล้ว handle เก่าชี้มั่ว — ต้องรอ register รอบใหม่
            Log.w(TAG, "stale dispatcher handle; dropping ${queuedEvents.size} event(s)")
            queuedEvents.clear()
            return
        }

        val created = FlutterEngine(context)
        channel = MethodChannel(
            created.dartExecutor.binaryMessenger,
            "background_beacon_sdk/background",
        ).also { ch ->
            ch.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                if (call.method == "backgroundReady") {
                    dartReady = true
                    flushIfReady()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }

        created.dartExecutor.executeDartCallback(
            DartExecutor.DartCallback(context.assets, loader.findAppBundlePath(), callbackInfo))
        engine = created
    }

    private fun flushIfReady() {
        val ch = channel ?: return
        if (!dartReady) return
        if (queuedEvents.isEmpty()) {
            releaseCompletions()
            return
        }

        val events = queuedEvents.toList()
        queuedEvents.clear()

        // ปิด goAsync window หลัง Dart ประมวลผล "เสร็จจริง" เท่านั้น —
        // fire-and-forget แล้วปิดเลย = process โดนเก็บก่อนงานฝั่ง Dart
        // (เช่นโพสต์ notification) จะจบ
        var remaining = events.size
        val ack = {
            remaining--
            if (remaining == 0) releaseCompletions()
        }
        events.forEach { event ->
            ch.invokeMethod("onBeaconEvent", event, object : MethodChannel.Result {
                override fun success(result: Any?) = ack()
                override fun error(code: String, message: String?, details: Any?) = ack()
                override fun notImplemented() = ack()
            })
        }
    }

    /** ปล่อย window พร้อม grace สั้น ๆ — เผื่องาน async ฝั่ง Dart ที่ไม่ได้ await */
    private fun releaseCompletions() {
        if (pendingCompletions.isEmpty()) return
        val completions = pendingCompletions.toList()
        pendingCompletions.clear()
        mainHandler.postDelayed({ completions.forEach { it.complete() } }, RELEASE_GRACE_MS)
    }

    /** กัน onComplete ถูกเรียกซ้ำ (ทางปกติ + timeout) — finish() ซ้ำ = crash */
    private class Completion(private val run: () -> Unit) {
        private var done = false
        fun complete() {
            if (done) return
            done = true
            run()
        }
    }

    private const val COMPLETE_TIMEOUT_MS = 8_000L
    private const val RELEASE_GRACE_MS = 1_500L
}
