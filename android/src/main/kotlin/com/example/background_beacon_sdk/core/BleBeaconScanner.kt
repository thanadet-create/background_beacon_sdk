package com.example.background_beacon_sdk.core

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Implementation กลางด้วย android.bluetooth.le — ใช้ได้ทั้ง GMS/HMS device
 * (การ scan ไม่ได้พึ่ง Google/Huawei lib)
 *
 * โหมด monitoring:
 * - API 26+ → PendingIntent scan เสมอ: OS scan ให้เอง รอด process kill
 *   ส่งผลเป็น batch ทุก ~`scanIntervalMs` เข้า [BeaconScanReceiver]
 * - API < 26 → duty cycle callback scan (scan `scanDurationMs` พักจนครบ
 *   `scanIntervalMs`) — ตายพร้อม process
 * - `foregroundServiceNotification = true` เพิ่ม foreground service ทับอีกชั้น:
 *   notification สถานะสด + พยุง process ไม่ให้โดนเก็บง่าย
 *
 * Event ที่ผลิต:
 * - enterRegion: ยิงทันทีที่เห็น beacon แรกของ region (latency สำคัญ)
 * - ranged: aggregate ต่อรอบ scan — หนึ่ง event ต่อ region ต่อรอบ
 *   (ไม่ยิงราย advertisement แล้ว — beacon 10Hz จะ flood stream)
 * - exitRegion: จาก [RegionStateTracker] เมื่อ region เงียบเกิน timeout
 *
 * Thread model: state ทุกตัวแตะจาก main thread เท่านั้น — ผล scan จาก
 * binder thread / receiver ถูก post เข้า [mainHandler] ก่อนเสมอ
 */
@SuppressLint("MissingPermission") // Dart layer บังคับ requestPermissions ก่อน start
open class BleBeaconScanner(private val context: Context) : BeaconScanner {

    private val mainHandler = Handler(Looper.getMainLooper())

    private var regions: List<BeaconRegionData> = emptyList()
    private var settings: ScanSettingsData? = null
    private var tracker: RegionStateTracker? = null
    private var listener: ((BeaconEventData) -> Unit)? = null
    private var scanning = false
    private var callbackScanActive = false
    private var pendingIntentScanActive = false

    /** sighting สะสมรอรอบ flush — key ราย beacon กันตัวซ้ำ, เก็บค่าอ่านล่าสุด */
    private val cycleSightings = LinkedHashMap<String, Pair<String, BeaconData>>()

    /** จำนวน beacon รอบ flush ล่าสุด — ใช้แต่งข้อความ notification */
    private var lastSeenBeaconCount = 0

    private val bleScanner
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
            .adapter?.bluetoothLeScanner

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            mainHandler.post { processResult(result) }
        }

        override fun onBatchScanResults(results: List<ScanResult>) {
            mainHandler.post { results.forEach(::processResult) }
        }
    }

    override fun setListener(listener: (BeaconEventData) -> Unit) {
        this.listener = listener
    }

    override fun startMonitoring(
        regions: List<BeaconRegionData>,
        settings: ScanSettingsData,
    ) {
        stopMonitoring() // contract ฝั่ง Dart: เรียกซ้ำ = แทนที่ชุดเดิมทั้งหมด
        this.regions = regions
        this.settings = settings
        tracker = RegionStateTracker(settings.exitTimeoutMs)
        scanning = true

        // persist ให้ headless mode (process โดน kill) กับ BootReceiver ใช้ต่อ
        BeaconStore.saveMonitoring(context, regions, settings)
        // session ใหม่ต้องเริ่ม state ว่าง — inside ค้างจาก headless รอบก่อน
        // (stopMonitoring ไม่ถูกเรียกตอนโดน kill) จะทำให้ enter ไม่ fire อีกเลย
        BeaconStore.clearInsideState(context)

        // เช็คตรงนี้ที่เดียว — ทางที่ throw ได้ต้องอยู่ใน startMonitoring เท่านั้น
        // (plugin มี try/catch → START_FAILED) cycle runnable ที่มาทีหลัง fail เงียบ
        if (bleScanner == null) {
            scanning = false
            throw IllegalStateException("Bluetooth adapter unavailable or disabled")
        }

        // FGS มีหน้าที่แค่โชว์สถานะ + พยุง process — ตัว scan ใช้ PendingIntent
        // เสมอ (API 26+) เพื่อรอด process kill: โดน kill แล้ว widget หาย
        // (start FGS จาก background โดน Android 12+ ห้าม) แต่ scan + headless
        // ยังทำงานต่อ widget กลับมาตอนเปิด app ใหม่
        if (settings.foregroundServiceNotification) {
            BeaconForegroundService.start(context)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startPendingIntentScan(settings)
        } else {
            startScanCycle()
        }

        mainHandler.postDelayed(exitCheckRunnable, EXIT_CHECK_MS)
    }

    override fun stopMonitoring() {
        if (!scanning) return
        scanning = false

        // ห้าม removeCallbacksAndMessages(null) — จะพา timeout ของ detectBeacon ตายด้วย
        mainHandler.removeCallbacks(startCycleRunnable)
        mainHandler.removeCallbacks(endCycleRunnable)
        mainHandler.removeCallbacks(exitCheckRunnable)

        if (callbackScanActive) {
            bleScanner?.stopScan(scanCallback)
            callbackScanActive = false
        }
        if (pendingIntentScanActive) {
            ScanSession.resultHandler = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PendingIntentScan.stop(context)
            }
            pendingIntentScanActive = false
        }
        BeaconForegroundService.stop(context) // no-op ถ้าไม่ได้ start
        BeaconStore.clearMonitoring(context)

        cycleSightings.clear()
        tracker = null
        settings = null
    }

    override fun detectBeacon(
        region: BeaconRegionData,
        timeoutMs: Long,
        callback: (Boolean) -> Unit,
    ) {
        val scanner = bleScanner ?: return mainHandler.post { callback(false) }.let { }

        // scan ชั่วคราวด้วย callback แยก — ไม่กระทบ scan หลักที่ monitor ค้างอยู่
        // ทุกการตัดสินใจ (เจอ/timeout) ถูก post เข้า main thread เพื่อกัน race
        // ระหว่าง binder thread กับ timeout — `done` ถูกอ่าน/เขียนบน main เท่านั้น
        var done = false
        lateinit var oneShot: ScanCallback
        oneShot = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val beacon = BeaconParser.parse(result) ?: return
                if (!region.matches(beacon.uuid, beacon.major, beacon.minor)) return
                mainHandler.post {
                    if (done) return@post
                    done = true
                    scanner.stopScan(oneShot)
                    callback(true)
                }
            }
        }

        scanner.startScan(BeaconParser.scanFilters(), lowLatency(), oneShot)
        mainHandler.postDelayed({
            if (done) return@postDelayed
            done = true
            scanner.stopScan(oneShot)
            callback(false)
        }, timeoutMs)
    }

    // ---- ทางเข้าผล scan (main thread เสมอ) ----

    private fun processResult(result: ScanResult) {
        if (!scanning) return // ผลค้างท่อหลัง stop — ทิ้ง
        val beacon = BeaconParser.parse(result) ?: return
        val region = regions.firstOrNull {
            it.matches(beacon.uuid, beacon.major, beacon.minor)
        } ?: return

        if (tracker?.onSighting(region.identifier, now()) == true) {
            emit(BeaconEventData("enterRegion", region.identifier, listOf(beacon)))
            updateServiceStatus()
        }
        if (settings?.rangingEnabled == true) {
            val key = "${beacon.uuid}/${beacon.major}/${beacon.minor}"
            cycleSightings[key] = region.identifier to beacon
        }
    }

    /** ยิง ranged หนึ่ง event ต่อ region จาก sighting ที่สะสมไว้ แล้วเริ่มรอบใหม่ */
    private fun flushRanged() {
        if (cycleSightings.isEmpty()) return
        lastSeenBeaconCount = cycleSightings.size
        cycleSightings.values
            .groupBy({ it.first }, { it.second })
            .forEach { (regionIdentifier, beacons) ->
                emit(BeaconEventData("ranged", regionIdentifier, beacons))
            }
        cycleSightings.clear()
        updateServiceStatus()
    }

    private fun emit(event: BeaconEventData) {
        listener?.invoke(event)
    }

    // ---- โหมด duty cycle (callback scan) ----

    private val startCycleRunnable = Runnable { startScanCycle() }
    private val endCycleRunnable = Runnable { endScanCycle() }

    private fun startScanCycle() {
        if (!scanning) return
        // Bluetooth โดนปิดกลางคัน — ข้ามรอบนี้แล้วลองใหม่ ห้าม throw:
        // ตรงนี้รันจาก Handler ไม่มีใคร catch (exception = app crash)
        val scanner = bleScanner ?: run {
            mainHandler.postDelayed(startCycleRunnable, settings!!.scanIntervalMs.toLong())
            return
        }
        scanner.startScan(BeaconParser.scanFilters(), lowLatency(), scanCallback)
        callbackScanActive = true
        mainHandler.postDelayed(endCycleRunnable, settings!!.scanDurationMs.toLong())
    }

    private fun endScanCycle() {
        if (!scanning) return
        flushRanged()
        val s = settings!!
        val pauseMs = (s.scanIntervalMs - s.scanDurationMs).toLong()
        if (pauseMs > 0) {
            bleScanner?.stopScan(scanCallback)
            callbackScanActive = false
            mainHandler.postDelayed(startCycleRunnable, pauseMs)
        } else {
            // duration ≥ interval = scan ต่อเนื่อง — ไม่ stop แค่ flush ตามรอบ
            mainHandler.postDelayed(endCycleRunnable, s.scanDurationMs.toLong())
        }
    }

    // ---- โหมด PendingIntent (API 26+) ----

    private fun startPendingIntentScan(settings: ScanSettingsData) {
        ScanSession.resultHandler = { results ->
            // receiver ปลุกมาบน main thread อยู่แล้ว แต่ contract เราคือ post เสมอ
            // — กัน implementation detail ของระบบเปลี่ยนแล้ว state พัง
            mainHandler.post {
                results.forEach(::processResult)
                flushRanged() // โหมดนี้ไม่มีรอบ scan ของตัวเอง — flush ต่อ batch
            }
        }

        if (!PendingIntentScan.start(context, settings)) {
            ScanSession.resultHandler = null
            throw IllegalStateException("Bluetooth adapter unavailable or disabled")
        }
        pendingIntentScanActive = true
    }

    // ---- exit detection (ทุกโหมด) ----

    private val exitCheckRunnable = object : Runnable {
        override fun run() {
            if (!scanning) return
            val exited = tracker?.checkExits(now()).orEmpty()
            exited.forEach { regionIdentifier ->
                emit(BeaconEventData("exitRegion", regionIdentifier, emptyList()))
            }
            if (exited.isNotEmpty()) {
                lastSeenBeaconCount = 0
                updateServiceStatus()
            }
            mainHandler.postDelayed(this, EXIT_CHECK_MS)
        }
    }

    /** สรุปสถานะขึ้น notification ของ foreground service (เฉพาะโหมดนั้น) */
    private fun updateServiceStatus() {
        if (settings?.foregroundServiceNotification != true) return
        val inside = tracker?.insideRegions().orEmpty()
        val text = if (inside.isEmpty()) {
            "กำลังหา beacon…"
        } else {
            "อยู่ในเขต ${inside.sorted().joinToString(", ")} · เห็น $lastSeenBeaconCount beacon"
        }
        BeaconForegroundService.update(context, text)
    }

    private fun now(): Long = System.currentTimeMillis()

    private fun lowLatency(): android.bluetooth.le.ScanSettings =
        android.bluetooth.le.ScanSettings.Builder()
            .setScanMode(android.bluetooth.le.ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

    private companion object {
        const val EXIT_CHECK_MS = 2_000L
    }
}
