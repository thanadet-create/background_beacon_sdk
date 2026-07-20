package com.example.background_beacon_sdk.core

import android.bluetooth.le.ScanResult

/**
 * Bridge between [BeaconScanReceiver] (instantiated by the system, cannot
 * hold state) and the scanner currently monitoring — process-local singleton.
 *
 * Known limit: if the process was killed and the system wakes a fresh
 * receiver, the handler is null (no scanner/engine yet) → that batch is
 * dropped here. Delivering events to Dart from a dead process is the
 * headless engine's job.
 */
object ScanSession {
    @Volatile
    var resultHandler: ((List<ScanResult>) -> Unit)? = null
}
