package com.example.background_beacon_sdk.util

import android.content.Context
import android.content.pm.PackageManager
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability

// ตรวจว่า device เป็น GMS หรือ HMS — หัวใจของ "detect os เอง"
// ค่าที่คืนคือ wire contract กับ Dart PlatformDetector: "gms" | "hms"
object MobileServicesDetector {

    fun detect(context: Context): String {
        val gms = GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS
        if (gms) return "gms"

        // HMS Core ติดตั้งเป็น package "com.huawei.hwid" — เช็คผ่าน PackageManager
        // ตรง ๆ ไม่ต้องพึ่ง Huawei SDK/maven repo
        return try {
            context.packageManager.getPackageInfo("com.huawei.hwid", 0)
            "hms"
        } catch (e: PackageManager.NameNotFoundException) {
            "gms" // ไม่มีทั้งคู่ → เส้น gms (BLE scan ไม่ได้พึ่ง Google lib อยู่แล้ว)
        }
    }
}
