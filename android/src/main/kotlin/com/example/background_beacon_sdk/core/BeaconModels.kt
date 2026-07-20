package com.example.background_beacon_sdk.core

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Kotlin data classes mirroring the Dart models.
// For the wire contract (key names / formats) the dartdoc in lib/src/models/ is the spec.

data class BeaconRegionData(
    val identifier: String,
    /** null = wildcard matching every UUID (the chip filter already catches all iBeacons) */
    val uuid: String?,
    val major: Int?,
    val minor: Int?,
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): BeaconRegionData = BeaconRegionData(
            identifier = map["identifier"] as String,
            // Dart already normalizes to lowercase — lowercasing again guards one-sided slips
            uuid = (map["uuid"] as String?)?.lowercase(),
            major = (map["major"] as Number?)?.toInt(),
            minor = (map["minor"] as Number?)?.toInt(),
        )
    }

    /// null uuid/major/minor = wildcard matching any value
    fun matches(uuid: String, major: Int, minor: Int): Boolean =
        (this.uuid == null || this.uuid == uuid) &&
            (this.major == null || this.major == major) &&
            (this.minor == null || this.minor == minor)
}

data class ScanSettingsData(
    val scanIntervalMs: Int,
    val scanDurationMs: Int,
    val foregroundServiceNotification: Boolean,
    val beaconLayout: String,
    val rangingEnabled: Boolean,
    /** iOS-only (location keep-alive) — Android accepts it per contract but never uses it */
    val continuousRanging: Boolean = false,
) {
    /**
     * How long a region stays silent before it counts as exited — must cover
     * at least 2 full missed scan cycles (a beacon can drop one cycle on a
     * signal dip) and never below 10 s so short intervals can't make exit
     * flap. Used by both in-process (BleBeaconScanner) and headless
     * (HeadlessBeaconRunner).
     */
    val exitTimeoutMs: Long
        get() = maxOf(10_000L, scanIntervalMs * 2L + scanDurationMs)

    companion object {
        fun fromMap(map: Map<String, Any?>): ScanSettingsData = ScanSettingsData(
            scanIntervalMs = (map["scanIntervalMs"] as Number).toInt(),
            scanDurationMs = (map["scanDurationMs"] as Number).toInt(),
            foregroundServiceNotification = map["foregroundServiceNotification"] as Boolean,
            beaconLayout = map["beaconLayout"] as String,
            rangingEnabled = map["rangingEnabled"] as Boolean,
            // safe-cast: key added later — older persisted JSON lacks it
            continuousRanging = (map["continuousRanging"] as? Boolean) ?: false,
        )
    }
}

data class BeaconData(
    val uuid: String,
    val major: Int,
    val minor: Int,
    val rssi: Int,
    val txPower: Int,
    val distance: Double,
    val lastSeen: Date,
    /** The device's Bluetooth MAC — debug/inventory only (absent on iOS) */
    val mac: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "uuid" to uuid,
        "major" to major,
        "minor" to minor,
        "rssi" to rssi,
        "txPower" to txPower,
        "distance" to distance,
        "lastSeen" to iso8601(lastSeen),
        "mac" to mac,
    )
}

data class BeaconEventData(
    // Must match the Dart enum names exactly: "enterRegion" | "exitRegion" | "ranged"
    val type: String,
    val region: String,
    val beacons: List<BeaconData>,
    val timestamp: Date = Date(),
) {
    fun toMap(): Map<String, Any> = mapOf(
        "type" to type,
        "region" to region,
        "beacons" to beacons.map { it.toMap() },
        "timestamp" to iso8601(timestamp),
    )
}

// Local time without timezone suffix — matches DateTime.parse on Dart.
// SimpleDateFormat is not thread-safe, so create per call (event volume is low enough).
internal fun iso8601(date: Date): String =
    SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).format(date)
