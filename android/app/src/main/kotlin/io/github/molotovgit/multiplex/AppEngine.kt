package io.github.molotovgit.multiplex

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * The app's one Flutter engine, made once per process and kept for as
 * long as the process lives. The screen ([MainActivity]) attaches to it
 * when there is one; without a screen it carries on, so the links to
 * paired computers survive the app being swiped away, and can start with
 * the phone ([StartReceiver]) before the app has been opened.
 *
 * What the app needs from Android whether or not it has a screen is
 * registered here, once. What only makes sense with a screen (a scanner,
 * a permission question, the window's flags) is registered by the
 * activity each time it attaches.
 */
object AppEngine {
    const val ID = "multiplex"
    private const val SESSIONS_CHANNEL = "multiplex/sessions"
    private const val WIDGET_CHANNEL = "multiplex/widget"
    private const val NETWORK_CHANNEL = "multiplex/network"
    private const val LIFE_CHANNEL = "multiplex/life"
    private const val PREFERENCES = "multiplex-start"
    private const val LINKS_KEY = "links"

    private val main = Handler(Looper.getMainLooper())
    private var life: MethodChannel? = null

    /** The screen, while there is one. */
    var activity = WeakReference<MainActivity>(null)

    /** The engine, started if this is the first call in this process. Main thread only. */
    fun ensure(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ID)?.let { return it }
        val app = context.applicationContext
        val engine = FlutterEngine(app)
        register(engine, app)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ID, engine)
        return engine
    }

    private fun register(engine: FlutterEngine, app: Context) {
        val messenger = engine.dartExecutor.binaryMessenger
        MethodChannel(messenger, SESSIONS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setOpenSessions" -> {
                    val count = call.argument<Int>("count") ?: 0
                    val summary = call.argument<String>("summary") ?: ""
                    if (count > 0) activity.get()?.askForNotificationsOnce()
                    SessionService.update(app, count, summary)
                    result.success(null)
                }
                "notifyDone" -> {
                    SessionService.notifyDone(app, call.argument<String>("title") ?: "", call.argument<String>("body") ?: "")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "setFavourites") {
                FavouritesWidget.save(app, call.argument<String>("json") ?: "[]")
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        PdfChannel.register(messenger)
        PhoneChannel.register(messenger, app)
        ShareTargets.register(messenger, app)
        SpeakerPlay.register(messenger, app)
        ClipPictures.register(messenger, app)
        watchNetwork(MethodChannel(messenger, NETWORK_CHANNEL), app)
        life = MethodChannel(messenger, LIFE_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    // Whether any paired computer is to be kept linked: decides
                    // if the app starts with the phone.
                    "setLinks" -> {
                        app.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit().putBoolean(LINKS_KEY, call.arguments == true).apply()
                        result.success(null)
                    }
                    "hasScreen" -> result.success(activity.get() != null)
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Whether the app has a reason to start with the phone. */
    fun wantsToStart(context: Context): Boolean = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getBoolean(LINKS_KEY, false)

    /** The user swiped the app away: Flutter closes what was only there for the screen. */
    fun taskRemoved() {
        main.post { life?.invokeMethod("taskRemoved", null) }
    }

    /**
     * Tells Flutter when a network becomes available (Wi-Fi and mobile
     * data swapped, or the signal came back), so dropped connections
     * reconnect at once instead of waiting for the next try.
     */
    private fun watchNetwork(channel: MethodChannel, app: Context) {
        val manager = app.getSystemService(ConnectivityManager::class.java) ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                main.post { channel.invokeMethod("networkAvailable", null) }
            }
        }
        try {
            manager.registerDefaultNetworkCallback(callback)
        } catch (e: RuntimeException) {
            // Too many callbacks registered: reconnecting falls back to its timer.
        }
    }
}
