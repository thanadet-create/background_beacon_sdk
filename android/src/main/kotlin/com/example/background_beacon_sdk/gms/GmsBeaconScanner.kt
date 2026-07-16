package com.example.background_beacon_sdk.gms

import android.content.Context
import com.example.background_beacon_sdk.core.BleBeaconScanner

// Scanner สำหรับเครื่องที่มี Google services — BLE ล้วนจาก BleBeaconScanner
// แยก class ไว้เผื่อเสริม GMS geofence/location ในอนาคต
class GmsBeaconScanner(context: Context) : BleBeaconScanner(context)
