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
 * Core implementation on android.bluetooth.le — works on both GMS/HMS
 * devices (scanning does not depend on Google/Huawei libs).
 *
 * Monitoring modes:
 * - API 26+ → always PendingIntent scan: the OS scans on our behalf,
 *   survives process kill, delivers batches every ~`scanIntervalMs` to
 *   [BeaconScanReceiver]
 * - API < 26 → duty-cycle callback scan (scan for `scanDurationMs`, rest
 *   until `scanIntervalMs` elapses) — dies with the process
 * - `foregroundServiceNotification = true` layers a foreground service on
 *   top: live status notification + keeps the process from easy reclaim
 *
 * Events produced:
 * - enterRegion: fired the moment the region's first beacon is seen
 *   (latency matters)
 * - ranged: aggregated per scan cycle — one event per region per cycle
 *   (never per advertisement — a 10 Hz beacon would flood the stream)
 * - exitRegion: from [RegionStateTracker] once a region stays silent past
 *   the timeout
 *
 * Thread model: all state is touched from the main thread only — scan
 * results from binder threads / the receiver are always posted through
 * [mainHandler] first.
 */
@SuppressLint("MissingPermission") // Dart layer enforces requestPermissions before start
open class BleBeaconScanner(private val context: Context) : BeaconScanner {

    private val mainHandler = Handler(Looper.getMainLooper())

    private var regions: List<BeaconRegionData> = emptyList()
    private var settings: ScanSettingsData? = null
    private var tracker: RegionStateTracker? = null
    private var listener: ((BeaconEventData) -> Unit)? = null
    private var scanning = false
    private var callbackScanActive = false
    private var pendingIntentScanActive = false

    /** Sightings accumulated for the next flush — keyed per beacon to dedupe, latest reading kept */
    private val cycleSightings = LinkedHashMap<String, Pair<String, BeaconData>>()

    /** Beacon count from the last flush — used to word the notification */
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
        stopMonitoring() // Dart-side contract: calling again replaces the entire previous set
        this.regions = regions
        this.settings = settings
        tracker = RegionStateTracker(settings.exitTimeoutMs)
        scanning = true

        // Persist for headless mode (process killed) and BootReceiver to reuse
        BeaconStore.saveMonitoring(context, regions, settings)
        // A new session must start with clean state — stale inside flags from
        // a previous headless run (stopMonitoring is never called on kill)
        // would keep enter from ever firing again.
        BeaconStore.clearInsideState(context)

        // Check here and only here — throwing paths must stay inside
        // startMonitoring (the plugin has try/catch → START_FAILED); cycle
        // runnables that come later fail silently.
        if (bleScanner == null) {
            scanning = false
            throw IllegalStateException("Bluetooth adapter unavailable or disabled")
        }

        // The FGS only shows status + props up the process — scanning always
        // goes through PendingIntent (API 26+) to survive kill: after a kill
        // the widget disappears (Android 12+ forbids starting an FGS from
        // background) but scan + headless keep working; the widget returns
        // when the app reopens.
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

        // Never removeCallbacksAndMessages(null) — it would kill detectBeacon's timeout too
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
        BeaconForegroundService.stop(context) // no-op if never started
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

        // Temporary scan with its own callback — never touches the main
        // monitoring scan. Every decision (found/timeout) is posted to the
        // main thread to prevent a binder-thread vs timeout race — `done`
        // is read/written on main only.
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

    // ---- scan result entry point (always main thread) ----

    private fun processResult(result: ScanResult) {
        if (!scanning) return // stale result in the pipe after stop — drop
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

    /** Emit one ranged event per region from accumulated sightings, then start a new cycle */
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

    // ---- duty cycle mode (callback scan) ----

    private val startCycleRunnable = Runnable { startScanCycle() }
    private val endCycleRunnable = Runnable { endScanCycle() }

    private fun startScanCycle() {
        if (!scanning) return
        // Bluetooth turned off mid-flight — skip this cycle and retry, never
        // throw: this runs from a Handler with no one catching
        // (exception = app crash)
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
            // duration ≥ interval = continuous scan — never stop, just flush per cycle
            mainHandler.postDelayed(endCycleRunnable, s.scanDurationMs.toLong())
        }
    }

    // ---- PendingIntent mode (API 26+) ----

    private fun startPendingIntentScan(settings: ScanSettingsData) {
        ScanSession.resultHandler = { results ->
            // The receiver already wakes on the main thread, but our contract
            // is to always post — so a system implementation-detail change
            // can't corrupt state.
            mainHandler.post {
                results.forEach(::processResult)
                flushRanged() // this mode has no scan cycle of its own — flush per batch
            }
        }

        if (!PendingIntentScan.start(context, settings)) {
            ScanSession.resultHandler = null
            throw IllegalStateException("Bluetooth adapter unavailable or disabled")
        }
        pendingIntentScanActive = true
    }

    // ---- exit detection (all modes) ----

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

    /** Summarize status onto the foreground service notification (that mode only) */
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
