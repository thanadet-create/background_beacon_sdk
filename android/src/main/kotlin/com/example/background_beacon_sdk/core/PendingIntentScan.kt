package com.example.background_beacon_sdk.core

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.annotation.RequiresApi

/**
 * PendingIntent BLE scan (API 26+) — a separate object because two callers
 * start it: BleBeaconScanner (normal startMonitoring) and BootReceiver
 * (restart after reboot with no engine/scanner instance).
 */
@RequiresApi(Build.VERSION_CODES.O)
@SuppressLint("MissingPermission") // Dart layer enforces requestPermissions before start
internal object PendingIntentScan {

    private const val REQUEST_CODE = 57112

    fun start(context: Context, settings: ScanSettingsData): Boolean {
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
            .adapter ?: return false
        val scanner = adapter.bluetoothLeScanner ?: return false

        val reportDelayMs = if (adapter.isOffloadedScanBatchingSupported) {
            settings.scanIntervalMs.toLong()
        } else {
            0L
        }
        val scanSettings = android.bluetooth.le.ScanSettings.Builder()
            .setScanMode(android.bluetooth.le.ScanSettings.SCAN_MODE_LOW_POWER)
            .setReportDelay(reportDelayMs)
            .build()
        scanner.startScan(BeaconParser.scanFilters(), scanSettings, pendingIntent(context))
        return true
    }

    fun stop(context: Context) {
        bleScanner(context)?.stopScan(pendingIntent(context))
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            Intent(context, BeaconScanReceiver::class.java),
            flags,
        )
    }

    private fun bleScanner(context: Context) =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
            .adapter?.bluetoothLeScanner
}
