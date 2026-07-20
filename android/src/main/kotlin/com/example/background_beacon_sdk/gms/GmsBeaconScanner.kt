package com.example.background_beacon_sdk.gms

import android.content.Context
import com.example.background_beacon_sdk.core.BleBeaconScanner

// Scanner for devices with Google services — pure BLE from BleBeaconScanner.
// Separate class in case GMS geofence/location gets layered in later.
class GmsBeaconScanner(context: Context) : BleBeaconScanner(context)
