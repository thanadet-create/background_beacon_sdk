package com.example.background_beacon_sdk.util

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * จัดการ runtime permission สำหรับ BLE scan — สองจังหวะ:
 *
 * 1. ชุด foreground (BLUETOOTH_SCAN / FINE_LOCATION) — dialog ปกติ
 * 2. ACCESS_BACKGROUND_LOCATION (API 29+) — **ต้องขอแยกหลังชุดแรกผ่านแล้ว**
 *    (ระบบห้ามขอรวม dialog เดียว) ไม่มีตัวนี้ = ผล scan โดนตัดทันทีที่ app
 *    ลง background ทั้งที่ scan ยังวิ่งอยู่
 *    - API 29: dialog มีตัวเลือก "ตลอดเวลา" ให้เลย
 *    - API 30+: ระบบพาไปหน้า Settings ให้ user เลือก "Allow all the time" เอง
 *
 * ค่าที่คืน Dart = ชุด foreground ครบไหม (scan ตอนเปิด app ใช้ได้ทันที)
 * background เป็น best effort — โดนปฏิเสธแค่ log เตือน ไม่ block การใช้งาน
 *
 * Flow: [request] เก็บ result ค้างไว้ → ระบบโชว์ dialog →
 * [onRequestPermissionsResult] ไล่จังหวะถัดไปหรือตอบ result แล้วเคลียร์
 * ต้องถูก add เป็น RequestPermissionsResultListener ผ่าน ActivityPluginBinding
 */
class PermissionManager : PluginRegistry.RequestPermissionsResultListener {

    private var pendingResult: MethodChannel.Result? = null
    private var pendingActivity: Activity? = null

    fun request(activity: Activity, result: MethodChannel.Result) {
        // ตอบ result เดิมซ้ำ = crash — กันเรียกซ้อนตอนมี dialog ค้าง
        if (pendingResult != null) {
            result.error(
                "PERMISSION_REQUEST_IN_PROGRESS",
                "Another permission request is in progress",
                null,
            )
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true) // ก่อน API 23 permission ให้ตอนติดตั้งแล้ว
            return
        }

        val missing = foregroundPermissions().filter {
            activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            requestBackgroundOrFinish(activity, result)
            return
        }

        pendingResult = result
        pendingActivity = activity
        activity.requestPermissions(missing.toTypedArray(), FOREGROUND_REQUEST_CODE)
    }

    /** จังหวะ 2 — ขอ background location ถ้ายังไม่มี ไม่งั้นจบด้วย success */
    private fun requestBackgroundOrFinish(activity: Activity, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            activity.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        pendingResult = result
        pendingActivity = activity
        activity.requestPermissions(
            arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
            BACKGROUND_REQUEST_CODE,
        )
    }

    // API 31+: BLUETOOTH_SCAN / ≤30: FINE_LOCATION (ไม่มีแล้วผล scan ว่างเงียบ ๆ)
    // ขอ FINE_LOCATION บน 31+ ด้วยเพราะไม่ได้ใช้ neverForLocation (คำนวณ distance)
    private fun foregroundPermissions(): List<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.ACCESS_FINE_LOCATION,
            )
        } else {
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        when (requestCode) {
            FOREGROUND_REQUEST_CODE -> {
                val result = pendingResult ?: return true
                val activity = pendingActivity
                pendingResult = null
                pendingActivity = null

                val granted = grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                if (!granted || activity == null) {
                    result.success(granted)
                } else {
                    requestBackgroundOrFinish(activity, result)
                }
                return true
            }

            BACKGROUND_REQUEST_CODE -> {
                val result = pendingResult ?: return true
                pendingResult = null
                pendingActivity = null

                val granted = grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                if (!granted) {
                    // foreground ครบแล้ว scan ตอนเปิด app ใช้ได้ — เตือนไว้ว่า
                    // background scan จะโดน gate จนกว่า user จะให้ "ตลอดเวลา"
                    Log.w(
                        "PermissionManager",
                        "ACCESS_BACKGROUND_LOCATION denied — " +
                            "scan results will stop while app is in background",
                    )
                }
                result.success(true)
                return true
            }

            else -> return false
        }
    }

    private companion object {
        const val FOREGROUND_REQUEST_CODE = 57110
        const val BACKGROUND_REQUEST_CODE = 57113
    }
}
