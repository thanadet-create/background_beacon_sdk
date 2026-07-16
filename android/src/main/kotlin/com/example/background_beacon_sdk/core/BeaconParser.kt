package com.example.background_beacon_sdk.core

import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import java.util.Date
import kotlin.math.pow

/**
 * แปลง raw BLE advertisement → [BeaconData]
 *
 * iBeacon layout ใน manufacturer data ของ Apple (company ID 0x004C):
 * ```
 * [0]=0x02 [1]=0x15 | [2..17]=UUID | [18..19]=major | [20..21]=minor | [22]=txPower
 *  (prefix คงที่)                     (big endian)     (big endian)    (signed byte)
 * ```
 */
object BeaconParser {
    const val APPLE_MANUFACTURER_ID = 0x004C
    val IBEACON_PREFIX = byteArrayOf(0x02, 0x15)

    fun parse(result: ScanResult): BeaconData? {
        val data = result.scanRecord
            ?.getManufacturerSpecificData(APPLE_MANUFACTURER_ID)
            ?: return null
        if (data.size < 23 || data[0] != IBEACON_PREFIX[0] || data[1] != IBEACON_PREFIX[1]) {
            return null // manufacturer data ของ Apple แต่ไม่ใช่ iBeacon (เช่น AirPods)
        }

        // UUID 16 bytes → hex 8-4-4-4-12 lowercase (wire contract ฝั่ง Dart)
        val uuid = buildString {
            for (i in 2 until 18) {
                append("%02x".format(data[i]))
                if (i == 5 || i == 7 || i == 9 || i == 11) append('-')
            }
        }
        val major = ((data[18].toInt() and 0xFF) shl 8) or (data[19].toInt() and 0xFF)
        val minor = ((data[20].toInt() and 0xFF) shl 8) or (data[21].toInt() and 0xFF)
        val txPower = data[22].toInt() // sign-extended: 0xC5 → -59

        return BeaconData(
            uuid = uuid,
            major = major,
            minor = minor,
            rssi = result.rssi,
            txPower = txPower,
            distance = estimateDistance(result.rssi, txPower),
            lastSeen = Date(),
            // MAC จาก packet header — ตรงกับ sticker ข้างเครื่อง
            // (อ่านได้ด้วย BLUETOOTH_SCAN ไม่ต้องขอ CONNECT เพิ่ม)
            mac = result.device?.address,
        )
    }

    // log-distance path loss model, exponent 2.0 = ที่โล่ง — ค่าประมาณหยาบ
    private fun estimateDistance(rssi: Int, txPower: Int): Double =
        10.0.pow((txPower - rssi) / 20.0)

    /**
     * กรอง iBeacon ตั้งแต่ระดับ chip (ประหยัดแบต + จำเป็นสำหรับ PendingIntent scan)
     * mask 0x01,0x01 = เทียบเฉพาะ 2 bytes แรก (prefix 0x02 0x15)
     */
    fun scanFilters(): List<ScanFilter> = listOf(
        ScanFilter.Builder()
            .setManufacturerData(
                APPLE_MANUFACTURER_ID,
                IBEACON_PREFIX,
                byteArrayOf(0x01, 0x01),
            )
            .build()
    )
}
