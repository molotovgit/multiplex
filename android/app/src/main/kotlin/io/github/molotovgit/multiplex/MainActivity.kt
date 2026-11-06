package io.github.molotovgit.multiplex

import android.content.Intent
import android.os.Bundle
import android.net.ConnectivityManager
import android.net.Network
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's only screen. It is a FragmentActivity because the fingerprint
 * prompt (local_auth) needs one.
 *
 * It also answers small native calls from Flutter: keep the screen on
 * while a terminal is open, so long-running commands stay visible, and
 * hide the window from screenshots and the recent-apps preview while a
 * terminal or the keychain is shown (FLAG_SECURE). It also keeps the
 * open-connections notification and the home-screen widget's favourites
 * current, and passes on what other apps or the widget asked for (see
 * [IncomingIntents]).
 *
 * It also tells Flutter when a network becomes available (Wi-Fi and
 * mobile data swapped, or the signal came back), so dropped connections
 * reconnect at once instead of waiting for the next try.
 */
class MainActivity : FlutterFragmentActivity() {
    private var incomingChannel: MethodChannel? = null
    private val incoming = IncomingIntents(this) { runOnUiThread { incomingChannel?.invokeMethod("changed", null) } }
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A recreated activity already handled the intent that started it.
        if (savedInstanceState == null) incoming.read(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incoming.read(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        incomingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INCOMING_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "take") result.success(incoming.take()) else result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "setFavourites") {
                FavouritesWidget.save(this, call.argument<String>("json") ?: "[]")
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        PdfChannel.register(flutterEngine.dartExecutor.binaryMessenger)
        StorageChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenOn" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    if (on) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRIVACY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    if (on) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SESSIONS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setOpenSessions" -> {
                    val count = call.argument<Int>("count") ?: 0
                    val summary = call.argument<String>("summary") ?: ""
                    if (count > 0) askForNotificationsOnce()
                    SessionService.update(this, count, summary)
                    result.success(null)
                }
                "notifyDone" -> {
                    SessionService.notifyDone(this, call.argument<String>("title") ?: "", call.argument<String>("body") ?: "")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        watchNetwork(MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NETWORK_CHANNEL))
    }

    private fun watchNetwork(channel: MethodChannel) {
        val manager = getSystemService(ConnectivityManager::class.java) ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                runOnUiThread { channel.invokeMethod("networkAvailable", null) }
            }
        }
        try {
            manager.registerDefaultNetworkCallback(callback)
            networkCallback = callback
        } catch (e: RuntimeException) {
            // Without it, reconnects simply wait for their next try.
        }
    }

    /** Android 13+ hides the "connected" notification without this. */
    private fun askForNotificationsOnce() {
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    override fun onDestroy() {
        // The app is being closed for good: let the connections go too.
        if (isFinishing) SessionService.update(this, 0, "")
        networkCallback?.let { callback ->
            getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(callback)
        }
        networkCallback = null
        super.onDestroy()
    }

    private companion object {
        const val SCREEN_CHANNEL = "multiplex/screen"
        const val SESSIONS_CHANNEL = "multiplex/sessions"
        const val PRIVACY_CHANNEL = "multiplex/privacy"
        const val WIDGET_CHANNEL = "multiplex/widget"
        const val INCOMING_CHANNEL = "multiplex/incoming"
        const val NETWORK_CHANNEL = "multiplex/network"
    }
}
