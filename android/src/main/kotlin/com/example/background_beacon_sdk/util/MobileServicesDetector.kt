package com.example.background_beacon_sdk.util

import android.content.Context
import android.content.pm.PackageManager
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability

// Detects whether the device is GMS or HMS — the heart of platform auto-detect.
// Return values are the wire contract with Dart's PlatformDetector: "gms" | "hms"
object MobileServicesDetector {

    fun detect(context: Context): String {
        val gms = GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS
        if (gms) return "gms"

        // HMS Core installs as package "com.huawei.hwid" — check straight
        // through PackageManager, no Huawei SDK/maven repo needed.
        return try {
            context.packageManager.getPackageInfo("com.huawei.hwid", 0)
            "hms"
        } catch (e: PackageManager.NameNotFoundException) {
            "gms" // neither present → gms path (BLE scanning never needed Google libs anyway)
        }
    }
}
