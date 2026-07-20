package com.example.background_beacon_sdk.hms

import android.content.Context
import com.example.background_beacon_sdk.core.BleBeaconScanner

// Scanner for Huawei (no GMS) — BLE scanning uses the same standard API as GMS.
// Future divergence: EMUI battery optimization is aggressive (protected apps
// handling), and any added geofencing goes through HMS Location Kit.
class HmsBeaconScanner(context: Context) : BleBeaconScanner(context)
