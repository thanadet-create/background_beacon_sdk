package com.example.background_beacon_sdk.core

// Interface กลางของ scanner — GMS/HMS implement ตัวนี้
// BLE scan ใช้ standard API เหมือนกันทั้งคู่ (ดู BleBeaconScanner)
// แยก interface ไว้เผื่อ service layer เสริมในอนาคตต่างกัน (geofence/location kit)
interface BeaconScanner {
    fun startMonitoring(regions: List<BeaconRegionData>, settings: ScanSettingsData)

    fun stopMonitoring()

    /** one-shot: scan จนเจอ beacon ใน region หรือครบ [timeoutMs] — callback บน main thread */
    fun detectBeacon(region: BeaconRegionData, timeoutMs: Long, callback: (Boolean) -> Unit)

    /** listener ถูกเรียกจาก binder thread — ฝั่งรับต้อง post ขึ้น main thread เอง */
    fun setListener(listener: (BeaconEventData) -> Unit)
}
