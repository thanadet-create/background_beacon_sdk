package com.example.background_beacon_sdk.util

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Runtime permissions for BLE scanning — two phases:
 *
 * 1. Foreground set (BLUETOOTH_SCAN / FINE_LOCATION) — normal dialog
 * 2. ACCESS_BACKGROUND_LOCATION (API 29+) — **must be requested separately
 *    after phase 1 passes** (the system forbids combining them in one
 *    dialog). Without it scan results are cut the moment the app goes
 *    background even though the scan keeps running.
 *    - API 29: the dialog offers "Allow all the time" directly
 *    - API 30+: the system routes to Settings; the user picks
 *      "Allow all the time" there
 *
 * Value returned to Dart = is the foreground set complete (scanning while
 * the app is open works immediately). Background is best effort — denial
 * only logs a warning, never blocks usage.
 *
 * Flow: [request] parks the result → system shows the dialog →
 * [onRequestPermissionsResult] advances to the next phase or answers the
 * result and clears. Must be added as a RequestPermissionsResultListener
 * via ActivityPluginBinding.
 */
class PermissionManager : PluginRegistry.RequestPermissionsResultListener {

    private var pendingResult: MethodChannel.Result? = null
    private var pendingActivity: Activity? = null

    fun request(activity: Activity, result: MethodChannel.Result) {
        // Answering the same result twice = crash — block re-entry while a dialog is pending
        if (pendingResult != null) {
            result.error(
                "PERMISSION_REQUEST_IN_PROGRESS",
                "Another permission request is in progress",
                null,
            )
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true) // before API 23 permissions were granted at install
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

    /** Phase 2 — request background location if missing, otherwise finish with success */
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

    // API 31+: BLUETOOTH_SCAN / ≤30: FINE_LOCATION (without it results are silently empty)
    // FINE_LOCATION is requested on 31+ too because neverForLocation isn't used (distance math)
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
                    // Foreground set complete so scanning with the app open
                    // works — warn that background scanning stays gated until
                    // the user grants "all the time".
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
