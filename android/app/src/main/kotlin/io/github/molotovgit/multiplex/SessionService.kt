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
import android.os.Handler
import android.os.IBinder
import android.os.Looper

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

    private val main = Handler(Looper.getMainLooper())

    /** Flutter has said how many connections are open since this started. */
    private var heard = false

    override fun onCreate() {
        super.onCreate()
        running = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Started with the phone, before the app was opened: bring the app
        // up without its screen, and give it a while to connect.
        if (intent?.getBooleanExtra(EXTRA_STARTING, false) == true) {
            foreground(buildNotification(0, "Connecting to your computers"))
            AppEngine.ensure(this)
            main.postDelayed({ if (!heard) show(0, "") }, STARTING_PATIENCE_MS)
            return START_NOT_STICKY
        }
        show(intent?.getIntExtra(EXTRA_COUNT, 0) ?: 0, intent?.getStringExtra(EXTRA_SUMMARY) ?: "")
        return START_NOT_STICKY
    }

    /** Shows how many connections are open, or stops when there are none. */
    fun show(count: Int, summary: String) {
        if (count <= 0) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        heard = true
        foreground(buildNotification(count, summary))
    }

    private fun foreground(notification: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: RuntimeException) {
            // Android did not allow it at this moment (the app is in the
            // background and has no leave to start this): nothing is kept
            // running that the user cannot see.
            stopSelf()
        }
    }

    /** The app was swiped away: what was only there for the screen closes; links stay. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        AppEngine.taskRemoved()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        if (running === this) running = null
        super.onDestroy()
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
        val title = when (count) {
            0 -> "Multiplex"
            1 -> "1 connection open"
            else -> "$count connections open"
        }
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
        private const val DONE_CHANNEL_ID = "done"
        private const val NOTIFICATION_ID = 1

        /** Each "done" notification gets its own id, so several can show. */
        private var nextDoneId = 100
        private const val EXTRA_COUNT = "count"
        private const val EXTRA_SUMMARY = "summary"

        /**
         * "Done on web: npm run build (1m 12s)": a long command finished
         * while its terminal was not on screen. A tap opens the app.
         */
        fun notifyDone(context: Context, title: String, body: String) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(DONE_CHANNEL_ID, "Finished commands", NotificationManager.IMPORTANCE_DEFAULT)
                channel.description = "When a long command ends while you are elsewhere."
                manager.createNotificationChannel(channel)
            }
            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, DONE_CHANNEL_ID)
            } else {
                Notification.Builder(context)
            }
            val notification = builder
                .setSmallIcon(R.drawable.ic_stat_connected)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
            try {
                manager.notify(nextDoneId++, notification)
            } catch (e: SecurityException) {
                // Notifications are turned off for the app.
            }
        }

        /** Starts, updates or (with count 0) stops the service. */
        private const val EXTRA_STARTING = "starting"

        /** How long a start with the phone may take to produce a connection. */
        private const val STARTING_PATIENCE_MS = 120_000L

        /** The service, while it runs. */
        @Volatile private var running: SessionService? = null

        fun update(context: Context, count: Int, summary: String) {
            // Already running: change what it shows, or stop it. No new start
            // is asked of Android, which refuses those to an app without a screen.
            running?.let {
                it.show(count, summary)
                return
            }
            if (count <= 0) return
            val intent = Intent(context, SessionService::class.java)
                .putExtra(EXTRA_COUNT, count)
                .putExtra(EXTRA_SUMMARY, summary)
            start(context, intent)
        }

        /** Starts the app without its screen, to link paired computers. */
        fun startForLinks(context: Context) {
            if (running != null) return
            start(context, Intent(context, SessionService::class.java).putExtra(EXTRA_STARTING, true))
        }

        private fun start(context: Context, intent: Intent) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
            } catch (e: RuntimeException) {
                // Android did not allow it now (the app is in the background):
                // the connections carry on for as long as the app is left alone.
            }
        }
    }
}
