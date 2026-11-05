package io.github.molotovgit.multiplex

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's only screen. It is a FragmentActivity because the fingerprint
 * prompt (local_auth) needs one.
 *
 * It also answers one small native call from Flutter: keep the screen on
 * while a terminal is open, so long-running commands stay visible.
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
    }

    private companion object {
        const val SCREEN_CHANNEL = "multiplex/screen"
    }
}
