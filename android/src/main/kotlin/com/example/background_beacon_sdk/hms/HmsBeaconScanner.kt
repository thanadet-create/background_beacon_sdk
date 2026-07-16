package com.example.background_beacon_sdk.hms

import android.content.Context
import com.example.background_beacon_sdk.core.BleBeaconScanner

// Scanner สำหรับ Huawei (ไม่มี GMS) — BLE scan ใช้ standard API เหมือน GMS
// จุดต่างในอนาคต: EMUI battery optimization ดุ ต้อง handle protected apps
// และถ้าใช้ geofence เสริม → HMS Location Kit
class HmsBeaconScanner(context: Context) : BleBeaconScanner(context)
