package com.example.background_beacon_sdk.core

// Central scanner interface — GMS/HMS implement this.
// BLE scanning uses the same standard API on both (see BleBeaconScanner);
// the interface exists in case future service layers diverge
// (geofence / location kit).
interface BeaconScanner {
    fun startMonitoring(regions: List<BeaconRegionData>, settings: ScanSettingsData)

    fun stopMonitoring()

    /** One-shot: scan until a beacon in the region is found or [timeoutMs] elapses — callback on main */
    fun detectBeacon(region: BeaconRegionData, timeoutMs: Long, callback: (Boolean) -> Unit)

    /** The listener is invoked from a binder thread — receivers must post to main themselves */
    fun setListener(listener: (BeaconEventData) -> Unit)
}
