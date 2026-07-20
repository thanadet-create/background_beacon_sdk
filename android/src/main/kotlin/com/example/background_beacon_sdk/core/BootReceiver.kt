package com.example.background_beacon_sdk.core

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Restarts the PendingIntent scan after reboot — scans registered with the
 * system are lost on power-off, unlike iOS where region monitoring survives
 * reboot by itself.
 *
 * Restarts only the scan: the foreground service (status widget) cannot be
 * started from a boot receiver (background restriction on API 31+) — the
 * widget returns when the user opens the app; meanwhile detection runs
 * through the normal headless path.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val settings = BeaconStore.loadSettings(context) ?: return
        if (!BeaconStore.hasActiveMonitoring(context)) return

        // Just re-register the scan with the system — no engine wake-up here.
        // The first scan result wakes BeaconScanReceiver → normal headless
        // path. Stale inside flags from before the reboot must be cleared —
        // otherwise enter never fires after boot.
        BeaconStore.clearInsideState(context)
        PendingIntentScan.start(context, settings)
    }
}
