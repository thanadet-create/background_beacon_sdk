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
 * Runs the app's Dart callback without UI — the event path when the app
 * has been killed.
 *
 * Flow: BeaconScanReceiver wakes (no engine) → runner creates a
 * FlutterEngine → runs `backgroundCallbackDispatcher` (Dart) via the
 * persisted callback handle → queues events until Dart sends
 * `backgroundReady` → flush.
 *
 * The engine is cached for the process lifetime — the next batch (every
 * ~scanIntervalMs) skips the spin-up cost (hundreds of ms). The OS reclaims
 * the process itself under memory pressure.
 *
 * The enter/exit state machine here persists in BeaconStore (separate from
 * in-process RegionStateTracker) — after process death state starts empty,
 * so beacons still in range get one repeat enter: accepted, noted in docs.
 *
 * Thread: everything on main (receiver + engine + channel callbacks already
 * live there) — no locks.
 */
internal object HeadlessBeaconRunner {

    private const val TAG = "HeadlessBeaconRunner"

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var dartReady = false

    /** Events arriving before Dart is ready — flushed on backgroundReady */
    private val queuedEvents = mutableListOf<Map<String, Any>>()

    /** goAsync windows waiting for their events to flush — all closed once the flush succeeds */
    private val pendingCompletions = mutableListOf<Completion>()

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Process a batch from the PendingIntent scan when no main engine exists.
     * [onComplete] is always invoked (done/error/timeout) — the receiver
     * uses it to close the goAsync window.
     */
    fun dispatch(context: Context, results: List<ScanResult>, onComplete: () -> Unit) {
        val completion = Completion(onComplete)
        // Hang guard: broken handle / unresponsive Dart — release the
        // receiver before the OS kills it.
        mainHandler.postDelayed({ completion.complete() }, COMPLETE_TIMEOUT_MS)

        val appContext = context.applicationContext
        val handles = BeaconStore.loadCallbackHandles(appContext)
        if (handles == null) {
            completion.complete() // app never registered — nothing to do
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
            completion.complete() // stale handle — queue already dropped
            return
        }

        // Close the window only when events actually flush (Dart ready) —
        // never here: the engine just spun up and dartReady is still false;
        // closing early kills the process before delivery.
        pendingCompletions.add(completion)
        flushIfReady()
    }

    /** Build enter/ranged/exit from the batch + persisted inside-state */
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

        // Per-beacon sightings (same dedupe key as in-process mode, latest reading kept)
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

        // Exit can only be checked when woken — with no beacon waking us,
        // exits hang until the next wake or the app opens (documented).
        insideState.filterValues { now - it > settings.exitTimeoutMs }.keys.forEach {
            insideState.remove(it)
            events.add(BeaconEventData("exitRegion", it, emptyList()))
        }

        BeaconStore.saveInsideState(context, insideState)
        return events
    }

    private fun ensureEngine(context: Context, dispatcherHandle: Long) {
        if (engine != null) return

        // The loader must come before lookupCallbackInformation — lookup
        // calls native into libflutter.so, which a freshly woken process has
        // not loaded yet (swap the order = UnsatisfiedLinkError → crash loop
        // → OS bans the wake-ups).
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(context)
        }
        loader.ensureInitializationComplete(context, null)

        val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle)
        if (callbackInfo == null) {
            // The app was rebuilt and the old handle points nowhere — wait
            // for the next register.
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

        // Close the goAsync window only after Dart has truly finished —
        // fire-and-forget then close = the process gets reclaimed before
        // Dart-side work (e.g. posting a notification) completes.
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

    /** Release windows with a short grace — covers Dart async work that wasn't awaited */
    private fun releaseCompletions() {
        if (pendingCompletions.isEmpty()) return
        val completions = pendingCompletions.toList()
        pendingCompletions.clear()
        mainHandler.postDelayed({ completions.forEach { it.complete() } }, RELEASE_GRACE_MS)
    }

    /** Guards onComplete from double invocation (normal path + timeout) — a repeated finish() crashes */
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
