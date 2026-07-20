package com.example.background_beacon_sdk.core

import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanResult
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Destination of the PendingIntent BLE scan (API 26+) — the main background
 * mechanism. The OS scans continuously on our behalf and wakes this
 * receiver with batched results per the configured reportDelay
 * (see PendingIntentScan.start).
 *
 * Two paths depending on process state:
 * - main engine alive (app open / normal background) → hand off to
 *   [ScanSession]; the existing scanner processes it and events flow up
 *   the EventChannel as usual
 * - process freshly woken (app killed) → [HeadlessBeaconRunner] spins up a
 *   background engine and invokes the Dart callback the app registered
 */
class BeaconScanReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // An error code arrives instead of results when the system cancels
        // the scan (e.g. Bluetooth turned off). No channel back to Dart from
        // a receiver — log to logcat; a new scan must be started explicitly.
        if (intent.hasExtra(BluetoothLeScanner.EXTRA_ERROR_CODE)) {
            Log.w(
                "BeaconScanReceiver",
                "scan cancelled by system, errorCode=" +
                    intent.getIntExtra(BluetoothLeScanner.EXTRA_ERROR_CODE, -1),
            )
            return
        }

        val results: List<ScanResult> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(
                BluetoothLeScanner.EXTRA_LIST_SCAN_RESULT,
                ScanResult::class.java,
            )
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra(BluetoothLeScanner.EXTRA_LIST_SCAN_RESULT)
        } ?: return

        val inProcessHandler = ScanSession.resultHandler
        if (inProcessHandler != null) {
            inProcessHandler(results)
            return
        }

        // Headless: request extra time from the system (goAsync, up to ~10 s)
        // — first engine spin-up costs hundreds of ms; if onReceive returned
        // immediately the process could be reclaimed before events reach Dart.
        val pendingResult = goAsync()
        HeadlessBeaconRunner.dispatch(context, results) { pendingResult.finish() }
    }
}
