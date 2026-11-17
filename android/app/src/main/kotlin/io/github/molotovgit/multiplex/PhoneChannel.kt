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
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telephony.SmsManager
import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import java.lang.ref.WeakReference
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
    private const val STATES = "multiplex/phone/state"
    private const val RING_CHANNEL_ID = "ring"
    private const val RING_NOTIFICATION_ID = 4207
    const val ACTION_STOP_RING = "io.github.molotovgit.multiplex.STOP_RING"

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var ringtone: Ringtone? = null

    // Calls and Do Not Disturb, told to Flutter as they change.
    private var stateSink: EventChannel.EventSink? = null
    private var modeListener: Any? = null
    private var quietReceiver: BroadcastReceiver? = null
    private var inCall = false
    private val stopLater = Runnable { ringtone?.stop(); ringtone = null }

    /** For Android's permission question, which needs a screen to show on. */
    private var activity = WeakReference<Activity>(null)

    private fun maySendSms(context: Context) = context.checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED

    /** Sends a text message. Null when Android took it; otherwise why not. */
    private fun sendSms(context: Context, to: String, text: String): String? {
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)) return "This device cannot send text messages."
        if (!maySendSms(context)) return "Android has not allowed Multiplex to send text messages."
        return try {
            val manager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            } ?: return "This device cannot send text messages."
            val parts = manager.divideMessage(text)
            if (parts.size > 1) manager.sendMultipartTextMessage(to, null, parts, null, null) else manager.sendTextMessage(to, null, text, null, null)
            null
        } catch (e: Exception) {
            e.message ?: "The message could not be sent."
        }
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        if (context is Activity) activity = WeakReference(context)
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
                "sendSms" -> {
                    val to = call.argument<String>("to").orEmpty()
                    val text = call.argument<String>("text").orEmpty()
                    result.success(if (to.isEmpty() || text.isEmpty()) "There was nothing to send." else sendSms(app, to, text))
                }
                "smsPermission" -> result.success(maySendSms(app))
                "requestSmsPermission" -> {
                    if (!maySendSms(app)) activity.get()?.requestPermissions(arrayOf(Manifest.permission.SEND_SMS), 4208)
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
        EventChannel(messenger, STATES).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                stateSink = events
                watchState(app)
            }

            override fun onCancel(arguments: Any?) {
                stateSink = null
                unwatchState(app)
            }
        })
    }

    private fun calling(mode: Int) =
        mode == AudioManager.MODE_RINGTONE || mode == AudioManager.MODE_IN_CALL || mode == AudioManager.MODE_IN_COMMUNICATION

    /**
     * Watches for calls (through the audio mode, which needs no permission
     * and also sees internet calls; Android 12 and later) and for Do Not
     * Disturb going on or off.
     */
    private fun watchState(context: Context) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        inCall = calling(audio.mode)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && modeListener == null) {
            val listener = AudioManager.OnModeChangedListener { mode ->
                val now = calling(mode)
                if (now != inCall) {
                    inCall = now
                    main.post { stateSink?.success(mapOf("call" to now)) }
                }
            }
            audio.addOnModeChangedListener(context.mainExecutor, listener)
            modeListener = listener
        }
        if (quietReceiver == null) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(c: Context, intent: Intent) {
                    val manager = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    val quiet = manager.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
                    main.post { stateSink?.success(mapOf("dnd" to quiet)) }
                }
            }
            val filter = IntentFilter(NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(receiver, filter)
            }
            quietReceiver = receiver
        }
    }

    private fun unwatchState(context: Context) {
        val listener = modeListener
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && listener is AudioManager.OnModeChangedListener) {
            (context.getSystemService(Context.AUDIO_SERVICE) as AudioManager).removeOnModeChangedListener(listener)
        }
        modeListener = null
        quietReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // Already gone.
            }
        }
        quietReceiver = null
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
