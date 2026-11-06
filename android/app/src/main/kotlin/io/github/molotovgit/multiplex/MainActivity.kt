package io.github.molotovgit.multiplex

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
 * terminal or the keychain is shown (FLAG_SECURE).
 */
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                else -> result.notImplemented()
            }
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
        super.onDestroy()
    }

    private companion object {
        const val SCREEN_CHANNEL = "multiplex/screen"
        const val SESSIONS_CHANNEL = "multiplex/sessions"
        const val PRIVACY_CHANNEL = "multiplex/privacy"
    }
}
