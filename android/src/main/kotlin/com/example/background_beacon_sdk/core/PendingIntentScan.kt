package com.example.background_beacon_sdk.core

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.annotation.RequiresApi

/**
 * BLE scan แบบ PendingIntent (API 26+) — แยกเป็น object เพราะมีผู้ start
 * สองทาง: BleBeaconScanner (ตอน startMonitoring ปกติ) และ BootReceiver
 * (restart หลัง reboot โดยไม่มี engine/scanner instance)
 */
@RequiresApi(Build.VERSION_CODES.O)
@SuppressLint("MissingPermission") // Dart layer บังคับ requestPermissions ก่อน start
internal object PendingIntentScan {

    private const val REQUEST_CODE = 57112

    /** คืน false เมื่อ Bluetooth adapter ใช้ไม่ได้ — ผู้เรียกตัดสินเองว่า throw ไหม */
    fun start(context: Context, settings: ScanSettingsData): Boolean {
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
            .adapter ?: return false
        val scanner = adapter.bluetoothLeScanner ?: return false

        // reportDelay > 0 ต้องมี hardware batching — chip ที่ไม่รองรับจะเงียบ
        // ทั้งระบบโดยไม่มี error / fallback เป็น 0 = ปลุก receiver ราย
        // advertisement (เปลืองกว่าแต่ทำงาน)
        val reportDelayMs = if (adapter.isOffloadedScanBatchingSupported) {
            settings.scanIntervalMs.toLong()
        } else {
            0L
        }
        val scanSettings = android.bluetooth.le.ScanSettings.Builder()
            .setScanMode(android.bluetooth.le.ScanSettings.SCAN_MODE_LOW_POWER)
            // ให้ระบบ batch ผลแล้วปลุก receiver ทีเดียวตามรอบ scanIntervalMs
            // — จุดที่ setting นี้แปลงร่างเป็น "ความถี่การปลุก" แทน duty cycle
            .setReportDelay(reportDelayMs)
            .build()
        scanner.startScan(BeaconParser.scanFilters(), scanSettings, pendingIntent(context))
        return true
    }

    fun stop(context: Context) {
        bleScanner(context)?.stopScan(pendingIntent(context))
    }

    private fun pendingIntent(context: Context): PendingIntent {
        // ต้องสร้างเหมือนเดิมทุก field — stopScan จับคู่ PendingIntent ด้วย
        // requestCode + intent เดิม / FLAG_MUTABLE จำเป็น: ระบบยัดผล scan ใส่ extra
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
