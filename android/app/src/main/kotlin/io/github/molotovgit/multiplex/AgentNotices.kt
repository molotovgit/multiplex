package io.github.molotovgit.multiplex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Notifications about coding agents on paired computers: one began to
 * wait for an answer, or finished. The answer can be given in the
 * notification itself: a button per choice the agent offers, or a reply
 * typed there.
 *
 * An answer may approve a command on a computer, so its buttons work
 * only with the phone unlocked (Android asks first), which Android can
 * promise from version 12 on; older phones get the notification without
 * buttons, and a tap opens the agent in the app. What the agent asks is
 * shown on the lock screen only where the owner lets notifications show
 * their content there.
 *
 * An answer goes to Flutter, which keeps the links to the computers,
 * whether or not the app has a screen: it waits here until Flutter
 * collects it ("take"), and Flutter says how it went ("settle"). The
 * computer itself checks that the agent still asks what the answer was
 * given to.
 */
object AgentNotices {
    private const val CHANNEL = "multiplex/agents"

    /** An agent waits for the owner: shown on top of the screen, with its buttons, like a message. */
    private const val WAITING_CHANNEL_ID = "agents-waiting"

    /** An agent finished, or an answer could not be sent: in the list, without interrupting. */
    private const val DONE_CHANNEL_ID = "agents-done"
    private const val ID = 7
    const val ACTION_ANSWER = "io.github.molotovgit.multiplex.AGENT_ANSWER"
    const val ACTION_OPEN = "io.github.molotovgit.multiplex.AGENT_OPEN"
    const val EXTRA_TAG = "tag"
    const val EXTRA_DETAILS = "details"
    const val EXTRA_CHOICE = "choice"
    const val KEY_REPLY = "reply"

    /** How long Flutter has to say how an answer went. */
    private const val PATIENCE_MS = 25_000L

    /** Android shows three buttons at most. */
    private const val MOST_BUTTONS = 3

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    /** Answers given that Flutter has not collected yet. */
    private val given = mutableListOf<Map<String, String>>()

    /** By tag: the broadcasts kept open until their answer is settled. */
    private val open = mutableMapOf<String, BroadcastReceiver.PendingResult>()

    fun register(messenger: BinaryMessenger, app: Context) {
        channel = MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "post" -> {
                        post(app, call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                        result.success(null)
                    }
                    "withdraw" -> {
                        cancel(app, call.argument<String>("tag") ?: "")
                        result.success(null)
                    }
                    "take" -> result.success(take())
                    "settle" -> {
                        settle(
                            app,
                            call.argument<String>("tag") ?: "",
                            call.argument<Boolean>("ok") == true,
                            call.argument<String>("title") ?: "",
                            call.argument<String>("message") ?: "",
                            call.argument<String>("details") ?: "",
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun manager(app: Context): NotificationManager {
        val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val waiting = NotificationChannel(WAITING_CHANNEL_ID, "Agents waiting for you", NotificationManager.IMPORTANCE_HIGH)
            waiting.description = "When a coding agent on one of your computers waits for an answer. Shown on top of the screen, so it can be answered there."
            manager.createNotificationChannel(waiting)
            val done = NotificationChannel(DONE_CHANNEL_ID, "Agents that finished", NotificationManager.IMPORTANCE_DEFAULT)
            done.description = "When a coding agent on one of your computers finishes."
            manager.createNotificationChannel(done)
        }
        return manager
    }

    private fun builder(app: Context, waiting: Boolean): Notification.Builder = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> Notification.Builder(app, if (waiting) WAITING_CHANNEL_ID else DONE_CHANNEL_ID)
        // Before channels the notification itself says how much it may interrupt.
        else -> @Suppress("DEPRECATION") Notification.Builder(app).setPriority(if (waiting) Notification.PRIORITY_HIGH else Notification.PRIORITY_DEFAULT)
    }

    /** A tap on the notification opens that agent in the app. */
    private fun opens(app: Context, tag: String, details: String): PendingIntent {
        val intent = Intent(app, MainActivity::class.java)
            .setAction(ACTION_OPEN)
            // Told apart by this: extras alone do not make two intents differ.
            .setData(Uri.parse("multiplex-agent://open/" + Uri.encode(tag)))
            .putExtra(EXTRA_DETAILS, details)
            .putExtra(ConnectToken.EXTRA, ConnectToken.get(app))
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(app, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun answers(app: Context, tag: String, details: String, choice: String?): PendingIntent {
        val intent = Intent(app, AgentAnswerReceiver::class.java)
            .setAction(ACTION_ANSWER)
            .setData(Uri.parse("multiplex-agent://answer/" + Uri.encode(tag) + "/" + (choice ?: "reply")))
            .putExtra(EXTRA_TAG, tag)
            .putExtra(EXTRA_DETAILS, details)
        if (choice != null) intent.putExtra(EXTRA_CHOICE, choice)
        // Android writes the typed reply into the intent, so that one must
        // be changeable; a choice's is fixed.
        val change = if (choice == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(app, 0, intent, change or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun post(app: Context, args: Map<*, *>) {
        val tag = args["tag"] as? String ?: return
        val details = args["details"] as? String ?: ""
        val title = args["title"] as? String ?: ""
        val body = args["body"] as? String ?: ""
        val choices = (args["choices"] as? List<*>).orEmpty().mapNotNull { one ->
            val choice = one as? Map<*, *> ?: return@mapNotNull null
            val key = choice["key"] as? String ?: return@mapNotNull null
            val label = choice["label"] as? String ?: return@mapNotNull null
            key to label
        }
        val waiting = args["waiting"] == true
        val builder = builder(app, waiting)
            .setSmallIcon(R.drawable.ic_stat_connected)
            .setContentTitle(title)
            .setContentText(args["summary"] as? String ?: body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(opens(app, tag, details))
            .setAutoCancel(true)
            // On a locked screen only that an agent waits, unless the owner
            // lets notifications show what they say there.
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(builder(app, waiting).setSmallIcon(R.drawable.ic_stat_connected).setContentTitle(title).build())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            for ((key, label) in choices.take(MOST_BUTTONS)) {
                builder.addAction(Notification.Action.Builder(null, label, answers(app, tag, details, key)).setAuthenticationRequired(true).build())
            }
            if (args["reply"] == true) {
                val typed = RemoteInput.Builder(KEY_REPLY).setLabel(args["replyHint"] as? String ?: "").build()
                builder.addAction(Notification.Action.Builder(null, args["replyLabel"] as? String ?: "Reply", answers(app, tag, details, null)).addRemoteInput(typed).setAuthenticationRequired(true).build())
            }
        }
        show(app, tag, builder.build())
    }

    private fun show(app: Context, tag: String, notification: Notification) {
        try {
            manager(app).notify(tag, ID, notification)
        } catch (e: SecurityException) {
            // Notifications are turned off for the app.
        }
    }

    private fun cancel(app: Context, tag: String) {
        manager(app).cancel(tag, ID)
    }

    /** An answer was given in a notification; [kept] holds the broadcast open until it is settled. */
    fun answered(app: Context, tag: String, details: String, choice: String?, text: String?, kept: BroadcastReceiver.PendingResult) {
        val answer = mutableMapOf("tag" to tag, "details" to details)
        if (choice != null) answer["choice"] = choice
        if (text != null) answer["text"] = text
        synchronized(this) {
            given.add(answer)
            open.put(tag, kept)?.finish()
        }
        main.post { channel?.invokeMethod("changed", null) }
        // Flutter did not get to it (the app was not running and could not
        // connect in time): say so rather than leave the owner believing
        // the answer went.
        main.postDelayed({
            val waited = synchronized(this) { open[tag] === kept }
            if (waited) settle(app, tag, false, "Not sent", "Multiplex did not reach the computer in time. Open it to answer.", details)
        }, PATIENCE_MS)
    }

    @Synchronized
    private fun take(): List<Map<String, String>> {
        val all = given.toList()
        given.clear()
        return all
    }

    /** How an answer went: sent (the notification goes) or not (it says why, without buttons). */
    private fun settle(app: Context, tag: String, ok: Boolean, title: String, message: String, details: String) {
        synchronized(this) { open.remove(tag) }?.finish()
        if (ok) {
            cancel(app, tag)
            return
        }
        val notification = builder(app, false)
            .setSmallIcon(R.drawable.ic_stat_connected)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setContentIntent(opens(app, tag, details))
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .build()
        show(app, tag, notification)
    }
}

/** A button of an agent's notification was pressed, or a reply typed into it. */
class AgentAnswerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AgentNotices.ACTION_ANSWER) return
        val tag = intent.getStringExtra(AgentNotices.EXTRA_TAG) ?: return
        val details = intent.getStringExtra(AgentNotices.EXTRA_DETAILS) ?: return
        val choice = intent.getStringExtra(AgentNotices.EXTRA_CHOICE)
        val text = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(AgentNotices.KEY_REPLY)?.toString()?.trim()
        if (choice == null && text.isNullOrEmpty()) return
        val app = context.applicationContext
        // The app may not be running: it comes up without its screen, and
        // links the computers as it does when it starts with the phone.
        AppEngine.ensure(app)
        AgentNotices.answered(app, tag, details, choice, if (choice == null) text else null, goAsync())
    }
}
