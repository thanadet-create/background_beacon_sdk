package com.example.background_beacon_sdk.core

/**
 * State machine เข้า/ออก region — derive จาก sighting ดิบ
 *
 * BLE ไม่มี event "ออกจากเขต" ตรง ๆ มีแต่ "เห็น advertisement" — exit จึงต้อง
 * อนุมานจากความเงียบ: ไม่เห็น beacon ใน region นานเกิน [exitTimeoutMs] ถือว่าออก
 * timeout ต้องยาวกว่ารอบ duty cycle เสมอ ไม่งั้นช่วงพัก scan จะกลายเป็น false exit
 * (ผู้สร้างเป็นคนรับผิดชอบ — ดู BleBeaconScanner.exitTimeoutMs)
 *
 * Thread contract: เรียกทุก method จาก main thread เท่านั้น (ไม่มี lock ข้างใน)
 */
class RegionStateTracker(private val exitTimeoutMs: Long) {

    /** identifier ของ region ที่ "อยู่ใน" ตอนนี้ → เวลาเห็นล่าสุด (epoch ms) */
    private val lastSeenAt = mutableMapOf<String, Long>()

    /**
     * บันทึกว่าเห็น beacon ใน region นี้ — คืน `true` เมื่อเพิ่งเปลี่ยนสถานะ
     * นอก→ใน (ผู้เรียกต้องยิง enterRegion event)
     */
    fun onSighting(regionIdentifier: String, nowMs: Long): Boolean {
        val wasInside = lastSeenAt.containsKey(regionIdentifier)
        lastSeenAt[regionIdentifier] = nowMs
        return !wasInside
    }

    /**
     * คืน identifier ของ region ที่เงียบเกิน timeout แล้วถอดออกจากสถานะ "ใน"
     * — ผู้เรียกต้องยิง exitRegion event ต่อตัว (beacons ว่างตาม wire contract)
     */
    fun checkExits(nowMs: Long): List<String> {
        val exited = lastSeenAt.filterValues { nowMs - it > exitTimeoutMs }.keys.toList()
        exited.forEach { lastSeenAt.remove(it) }
        return exited
    }

    /** region ที่อยู่สถานะ "ใน" ตอนนี้ — ใช้ทำ status text ของ notification */
    fun insideRegions(): Set<String> = lastSeenAt.keys.toSet()
}
