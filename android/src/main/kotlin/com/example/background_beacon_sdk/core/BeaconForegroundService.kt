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
 * Foreground service for `foregroundServiceNotification = true` mode.
 *
 * The service does not scan — its only job is holding the persistent
 * notification so the process survives background restrictions, letting
 * BleBeaconScanner's scan callbacks (same process) run continuously with
 * uninterrupted ranging. If continuous ranging isn't needed, PendingIntent
 * mode (BeaconScanReceiver) is cheaper.
 *
 * The notification is a "live status" like a music app — the scanner calls
 * [update] to refresh the text (which region, how many beacons) in place.
 *
 * API 34+ requires foregroundServiceType in the manifest (`location`) —
 * the 2-arg startForeground picks the type up from the manifest.
 */
class BeaconForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, build(this, DEFAULT_TEXT))
        running = true
        // The system may restart a killed service, but scan state died with
        // the process — START_NOT_STICKY: let the app call startMonitoring
        // again itself rather than leaving a zombie service with a
        // notification and no scan.
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

        /** Is the service holding the notification — [update] before start would post a stray one */
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
         * Update the text on the same notification (one id = replace, not
         * stack) — safe to call often. IMPORTANCE_LOW means no sound or
         * re-alert; the user just sees the text change.
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
                    // IMPORTANCE_LOW: visible in the drawer, no sound/heads-up —
                    // this notification is an FGS requirement, not breaking news
                    NotificationManager.IMPORTANCE_LOW,
                )
                // idempotent — repeated calls are ignored by the system
                (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .createNotificationChannel(channel)
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }

            // The plugin ships no drawable — borrow the host app's icon
            return builder
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle("Beacon monitoring")
                .setContentText(text)
                .setOngoing(true)
                // Prevents flicker on frequent updates
                .setOnlyAlertOnce(true)
                .build()
        }
    }
}
