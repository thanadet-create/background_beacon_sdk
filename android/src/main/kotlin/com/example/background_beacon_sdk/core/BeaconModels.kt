package com.example.background_beacon_sdk.core

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Data classes ฝั่ง Kotlin ที่ mirror models ฝั่ง Dart
// wire contract (ชื่อ key / format) ดู dartdoc ใน lib/src/models/ เป็น spec

data class BeaconRegionData(
    val identifier: String,
    /** null = wildcard จับทุก UUID (chip filter จับ iBeacon ทุกตัวอยู่แล้ว) */
    val uuid: String?,
    val major: Int?,
    val minor: Int?,
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): BeaconRegionData = BeaconRegionData(
            identifier = map["identifier"] as String,
            // Dart normalize เป็น lowercase อยู่แล้ว — lowercase ซ้ำกันพลาดฝั่งเดียวพอ
            uuid = (map["uuid"] as String?)?.lowercase(),
            major = (map["major"] as Number?)?.toInt(),
            minor = (map["minor"] as Number?)?.toInt(),
        )
    }

    /// uuid/major/minor เป็น null = wildcard จับทุกค่า
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
    /** iOS-only (location keep-alive) — Android รับไว้ตาม contract แต่ไม่ใช้ */
    val continuousRanging: Boolean = false,
) {
    /**
     * เงียบนานแค่ไหนถึงนับว่าออกจาก region — ต้องครอบรอบ scan ที่พลาดได้
     * อย่างน้อย 2 รอบเต็ม (beacon อาจหลุดรอบเดียวจากสัญญาณวูบ) และไม่ต่ำกว่า
     * 10 วิ กัน interval สั้น ๆ ทำ exit เด้งเข้า-ออกรัว
     * ใช้ทั้ง in-process (BleBeaconScanner) และ headless (HeadlessBeaconRunner)
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
            // safe-cast: key เพิ่มทีหลัง — persisted JSON เก่าไม่มี
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
    /** Bluetooth MAC ของตัวเครื่อง — debug/inventory เท่านั้น (iOS ไม่มีค่านี้) */
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
    // ต้องตรงชื่อ enum ฝั่ง Dart เป๊ะ: "enterRegion" | "exitRegion" | "ranged"
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

// local time ไม่มี timezone suffix — ตรงกับ DateTime.parse ฝั่ง Dart
// SimpleDateFormat ไม่ thread-safe จึงสร้างใหม่ต่อ call (ปริมาณ event ต่ำพอ)
internal fun iso8601(date: Date): String =
    SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).format(date)
