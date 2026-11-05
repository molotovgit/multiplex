package io.github.molotovgit.multiplex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps Multiplex running while SSH connections are open.
 *
 * Android (and especially Samsung's battery manager) freezes apps in the
 * background, which would cut every connection. A foreground service with
 * a small "connected" notification tells the system the app is doing work
 * the user asked for. It starts when the first connection opens and stops
 * when the last one closes.
 */
class SessionService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val count = intent?.getIntExtra(EXTRA_COUNT, 0) ?: 0
        val summary = intent?.getStringExtra(EXTRA_SUMMARY) ?: ""
        if (count <= 0) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val notification = buildNotification(count, summary)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(count: Int, summary: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Open connections", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Shown while SSH connections are open, so they keep running in the background."
            manager.createNotificationChannel(channel)
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val title = if (count == 1) "1 connection open" else "$count connections open"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        return builder
            .setSmallIcon(R.drawable.ic_stat_connected)
            .setContentTitle(title)
            .setContentText(summary)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "connections"
        private const val NOTIFICATION_ID = 1
        private const val EXTRA_COUNT = "count"
        private const val EXTRA_SUMMARY = "summary"

        /** Starts, updates or (with count 0) stops the service. */
        fun update(context: Context, count: Int, summary: String) {
            val intent = Intent(context, SessionService::class.java)
                .putExtra(EXTRA_COUNT, count)
                .putExtra(EXTRA_SUMMARY, summary)
            if (count > 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
