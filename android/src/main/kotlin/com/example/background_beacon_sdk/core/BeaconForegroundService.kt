package com.example.background_beacon_sdk.core

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * Foreground service สำหรับโหมด `foregroundServiceNotification = true`
 *
 * ตัว service ไม่ scan เอง — หน้าที่เดียวคือถือ notification ค้างไว้ให้ process
 * รอด background restriction เพื่อให้ callback scan ของ BleBeaconScanner
 * (ที่รันใน process เดียวกัน) ทำงานต่อเนื่องได้ ranging ไม่ขาด
 * ถ้าไม่ต้อง ranging ต่อเนื่อง ใช้โหมด PendingIntent (BeaconScanReceiver) ประหยัดกว่า
 *
 * Notification เป็น "live status" แบบ app เพลง — scanner เรียก [update]
 * อัปเดตข้อความสด (อยู่เขตไหน เห็นกี่ beacon) บนกล่องเดิม
 *
 * API 34+ บังคับประกาศ foregroundServiceType ใน manifest (`location`) —
 * startForeground แบบ 2 arg จะใช้ type จาก manifest ให้เอง
 */
class BeaconForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, build(this, DEFAULT_TEXT))
        running = true
        // ระบบ kill แล้ว restart service ได้ แต่ scan state ตายไปกับ process —
        // START_NOT_STICKY: ให้ app เป็นคน startMonitoring ใหม่เอง ไม่ปล่อย
        // service ซอมบี้ที่มี notification แต่ไม่มี scan
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_ID = "background_beacon_sdk"
        private const val NOTIFICATION_ID = 57111
        private const val DEFAULT_TEXT = "กำลังหา beacon…"

        /** service ถืออยู่ไหม — [update] ก่อน start จะกลายเป็น notification หลงทาง */
        @Volatile
        private var running = false

        fun start(context: Context) {
            val intent = Intent(context, BeaconForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            running = false
            context.stopService(Intent(context, BeaconForegroundService::class.java))
        }

        /**
         * อัปเดตข้อความบนกล่องเดิม (id เดียว = แทนที่ ไม่กอง) — เรียกถี่ได้
         * IMPORTANCE_LOW ไม่มีเสียง/ไม่เด้งซ้ำ user เห็นแค่ข้อความเปลี่ยน
         */
        fun update(context: Context, text: String) {
            if (!running) return
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(NOTIFICATION_ID, build(context, text))
        }

        private fun build(context: Context, text: String): Notification {
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Beacon scanning",
                    // IMPORTANCE_LOW: โชว์ใน drawer แต่ไม่มีเสียง/เด้ง — กล่องนี้
                    // เป็นข้อบังคับของ foreground service ไม่ใช่ข่าวด่วน
                    NotificationManager.IMPORTANCE_LOW,
                )
                // idempotent — เรียกซ้ำระบบ ignore
                (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .createNotificationChannel(channel)
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }

            // plugin ไม่มี drawable ของตัวเอง — ยืม icon ของ app ที่ฝังเราไป
            return builder
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle("Beacon monitoring")
                .setContentText(text)
                .setOngoing(true)
                // กันกระพริบตอน update ถี่ ๆ
                .setOnlyAlertOnce(true)
                .build()
        }
    }
}
