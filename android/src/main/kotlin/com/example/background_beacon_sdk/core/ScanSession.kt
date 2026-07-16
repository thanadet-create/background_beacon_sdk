package com.example.background_beacon_sdk.core

import android.bluetooth.le.ScanResult

/**
 * สะพานระหว่าง [BeaconScanReceiver] (ระบบ instantiate เอง ถือ state ไม่ได้)
 * กับ scanner ตัวที่กำลัง monitor อยู่ — process-local singleton
 *
 * ข้อจำกัดที่ต้องรู้: ถ้า process โดน kill แล้วระบบปลุก receiver ขึ้นมาใหม่
 * handler จะเป็น null (scanner/engine ยังไม่เกิด) → ผล scan รอบนั้นถูกทิ้ง
 * การส่ง event เข้า Dart ตอน process ตายต้องใช้ headless engine — นอก scope ตอนนี้
 */
object ScanSession {
    @Volatile
    var resultHandler: ((List<ScanResult>) -> Unit)? = null
}
