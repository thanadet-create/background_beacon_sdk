package com.example.background_beacon_sdk.core

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Restart PendingIntent scan หลัง reboot — scan ที่ register ไว้กับระบบ
 * หายหมดตอนเครื่องดับ ต่างจาก iOS ที่ region monitoring รอด reboot เอง
 *
 * Restart เฉพาะตัว scan: foreground service (widget สถานะ) start จาก boot
 * receiver ไม่ได้ (background restriction บน API 31+) — widget กลับมา
 * ตอน user เปิด app เอง ระหว่างนั้น detection วิ่งผ่าน headless ปกติ
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val settings = BeaconStore.loadSettings(context) ?: return
        if (!BeaconStore.hasActiveMonitoring(context)) return

        // แค่ re-register scan กับระบบ — ไม่ต้องปลุก engine ที่นี่
        // ผล scan แรกจะปลุก BeaconScanReceiver → headless path ตามปกติ
        // inside ค้างจากก่อน reboot ต้องล้าง — ไม่งั้น enter หลัง boot ไม่ fire
        BeaconStore.clearInsideState(context)
        PendingIntentScan.start(context, settings)
    }
}
