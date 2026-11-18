package io.github.molotovgit.multiplex

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

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

    override fun onCreate(savedInstanceState: Bundle?) {
        // The engine outlives this screen (see AppEngine): made here if the
        // app was not already running without one.
        AppEngine.ensure(this)
        AppEngine.activity = WeakReference(this)
        PhoneChannel.attach(this)
        super.onCreate(savedInstanceState)
        // A recreated activity already handled the intent that started it.
        if (savedInstanceState == null) incoming.read(intent)
    }

    override fun getCachedEngineId(): String = AppEngine.ID

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
        DesktopVideo.register(flutterEngine, this)
        PairChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
        ScreenCast.register(flutterEngine.dartExecutor.binaryMessenger, this)
        CameraCast.register(flutterEngine.dartExecutor.binaryMessenger, this)
        MicCast.register(flutterEngine.dartExecutor.binaryMessenger, this)
        TextScan.register(flutterEngine.dartExecutor.binaryMessenger, this)
        StorageChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
        UpdateChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
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
    }

    /** Android 13+ hides the "connected" notification without this. */
    fun askForNotificationsOnce() {
        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    @Deprecated("Android's own way of answering the screen-capture question")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == ScreenCast.REQUEST) ScreenCast.onResult(this, resultCode, data)
        if (requestCode == TextScan.REQUEST) TextScan.onResult(this, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CameraCast.REQUEST) CameraCast.onPermission(this, grantResults)
        if (requestCode == MicCast.REQUEST) MicCast.onPermission(this, grantResults)
    }

    override fun onDestroy() {
        // The engine and its connections carry on without this screen. What
        // stays open when the app is swiped away is Flutter's to decide
        // (see AppEngine.taskRemoved).
        if (AppEngine.activity.get() === this) {
            AppEngine.activity = WeakReference(null)
            PhoneChannel.attach(null)
        }
        incomingChannel = null
        super.onDestroy()
    }

    private companion object {
        const val SCREEN_CHANNEL = "multiplex/screen"
        const val PRIVACY_CHANNEL = "multiplex/privacy"
        const val INCOMING_CHANNEL = "multiplex/incoming"
    }
}
