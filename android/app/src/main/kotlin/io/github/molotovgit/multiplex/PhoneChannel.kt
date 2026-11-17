package io.github.molotovgit.multiplex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * What a link to a paired computer needs from the phone itself: ringing
 * out loud ("find my phone"), the battery level, and the notifications
 * (through [PhoneNotifications], once the user has allowed it).
 */
object PhoneChannel {
    private const val CHANNEL = "multiplex/phone"
    private const val NOTICES = "multiplex/phone/notifications"
    private const val RING_CHANNEL_ID = "ring"
    private const val RING_NOTIFICATION_ID = 4207
    const val ACTION_STOP_RING = "io.github.molotovgit.multiplex.STOP_RING"

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var ringtone: Ringtone? = null
    private val stopLater = Runnable { ringtone?.stop(); ringtone = null }

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "battery" -> result.success(battery(app))
                "ring" -> {
                    ring(app, call.argument<Int>("seconds") ?: 30)
                    result.success(null)
                }
                "stopRing" -> {
                    stopRing(app)
                    result.success(null)
                }
                "notificationAccess" -> result.success(hasNotificationAccess(app))
                "openNotificationAccess" -> {
                    try {
                        app.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } catch (_: Exception) {
                        // No such settings page on this device.
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, NOTICES).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
    }

    /** A notification the phone showed, for Flutter (which applies the rules). */
    fun post(notice: Map<String, String>) {
        main.post { sink?.success(notice) }
    }

    private fun hasNotificationAccess(context: Context): Boolean {
        val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: return false
        val mine = ComponentName(context, PhoneNotifications::class.java)
        return enabled.split(":").any { ComponentName.unflattenFromString(it) == mine }
    }

    private fun battery(context: Context): Map<String, Any> {
        val state = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = state?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = state?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val status = state?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        return mapOf("level" to (if (level < 0 || scale <= 0) -1 else level * 100 / scale), "charging" to charging)
    }

    /**
     * Rings like an alarm (so it sounds even when the phone is on silent)
     * until stopped from its notification, or after [seconds].
     */
    private fun ring(context: Context, seconds: Int) {
        stopRing(context)
        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: return
        val tone = RingtoneManager.getRingtone(context, sound) ?: return
        tone.audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) tone.isLooping = true
        try {
            tone.play()
        } catch (_: Exception) {
            return
        }
        ringtone = tone
        main.postDelayed(stopLater, seconds.coerceIn(5, 120) * 1000L)
        showRinging(context)
    }

    fun stopRing(context: Context) {
        main.removeCallbacks(stopLater)
        ringtone?.stop()
        ringtone = null
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(RING_NOTIFICATION_ID)
    }

    private fun showRinging(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(RING_CHANNEL_ID, "Find this phone", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "Shown while a paired computer is ringing this phone."
            channel.setSound(null, null)
            manager.createNotificationChannel(channel)
        }
        val stop = PendingIntent.getBroadcast(
            context, 0,
            Intent(context, StopRing::class.java).setAction(ACTION_STOP_RING),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, RING_CHANNEL_ID) else Notification.Builder(context)
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_connected)
            .setContentTitle("Your computer is looking for this phone")
            .setContentText("Tap to stop the ringing")
            .setContentIntent(stop)
            .setDeleteIntent(stop)
            .setAutoCancel(true)
            .build()
        try {
            manager.notify(RING_NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Notifications are off for the app; the ringing stops by itself.
        }
    }

    /** The ringing notification was tapped or swiped away. */
    class StopRing : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == ACTION_STOP_RING) stopRing(context)
        }
    }
}
