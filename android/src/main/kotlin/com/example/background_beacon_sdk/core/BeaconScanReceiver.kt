package com.example.background_beacon_sdk.core

import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanResult
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * ปลายทางของ BLE scan แบบ PendingIntent (API 26+) — กลไก background หลัก
 * ระบบ scan ให้ต่อเนื่องระดับ OS แล้วปลุก receiver ส่งผลเป็น batch
 * ตาม reportDelay ที่ตั้งไว้ (ดู PendingIntentScan.start)
 *
 * สองทางออกตามสภาพ process:
 * - engine หลักยังอยู่ (app เปิด/background ปกติ) → ส่งเข้า [ScanSession]
 *   scanner เดิมประมวลผล event ไหลขึ้น EventChannel ตามปกติ
 * - process เพิ่งถูกปลุกใหม่ (app โดน kill) → [HeadlessBeaconRunner]
 *   สร้าง background engine แล้วเรียก Dart callback ที่ app ลงทะเบียนไว้
 */
class BeaconScanReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // error code มาแทนผล scan เมื่อระบบยกเลิก scan (เช่น Bluetooth ถูกปิด)
        // ไม่มีช่องรายงานกลับ Dart จาก receiver — log ให้เห็นใน logcat,
        // scan รอบใหม่ต้อง start ใหม่
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

        // headless: ขอ window เพิ่มจากระบบ (goAsync สูงสุด ~10 วิ) — สร้าง engine
        // ครั้งแรกกินเวลาหลายร้อย ms ถ้าปล่อย onReceive จบเลย process อาจโดน
        // เก็บก่อน event ถึง Dart
        val pendingResult = goAsync()
        HeadlessBeaconRunner.dispatch(context, results) { pendingResult.finish() }
    }
}
