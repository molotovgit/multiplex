package io.github.molotovgit.multiplex

import android.app.Activity
import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.view.Surface
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Textures for the remote desktop's video.
 *
 * Flutter shows a texture; behind it is an Android Surface. We hand that
 * Surface to the Rust core ([nativeSetSurface]), whose hardware decoder
 * draws every picture straight onto it, so video never passes through
 * Dart or Java. When Android replaces the Surface (the app went to the
 * background and came back), the new one is handed over the same way and
 * the decoder rebuilds itself on it.
 */
object DesktopVideo {
    private const val CHANNEL = "multiplex/desktop_video"

    private val producers = HashMap<Long, TextureRegistry.SurfaceProducer>()
    private var wifiLock: WifiManager.WifiLock? = null

    init {
        // The same library Flutter already loaded; this only binds the
        // native method below to it.
        System.loadLibrary("multiplex_core")
    }

    @JvmStatic
    private external fun nativeSetSurface(texture: Long, surface: Surface?)

    /** Hands a Surface (or none) to the decoder registered under [id]. */
    fun setSurface(id: Long, surface: Surface?) = nativeSetSurface(id, surface)

    fun register(engine: FlutterEngine, activity: Activity) {
        engine.platformViewsController.registry.registerViewFactory(DesktopSurfaceFactory.VIEW_TYPE, DesktopSurfaceFactory())
        val registry = engine.renderer
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "create" -> {
                    val producer = registry.createSurfaceProducer()
                    val id = producer.id()
                    producer.setSize(call.argument<Int>("width") ?: 1280, call.argument<Int>("height") ?: 720)
                    producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                        override fun onSurfaceAvailable() {
                            hintFrameRate(producer.surface)
                            nativeSetSurface(id, producer.surface)
                            channel.invokeMethod("surfaceChanged", id)
                        }

                        override fun onSurfaceCleanup() {
                            nativeSetSurface(id, null)
                        }
                    })
                    producers[id] = producer
                    hintFrameRate(producer.surface)
                    nativeSetSurface(id, producer.surface)
                    result.success(id)
                }
                "setSize" -> {
                    val id = call.argument<Number>("id")?.toLong()
                    val producer = producers[id]
                    if (id != null && producer != null) {
                        producer.setSize(call.argument<Int>("width") ?: 1, call.argument<Int>("height") ?: 1)
                        // Resizing can swap the Surface underneath.
                        nativeSetSurface(id, producer.surface)
                    }
                    result.success(null)
                }
                "lowLatency" -> {
                    lowLatency(activity, call.argument<Boolean>("on") ?: false)
                    result.success(null)
                }
                "release" -> {
                    val id = call.argument<Number>("id")?.toLong()
                    if (id != null) {
                        nativeSetSurface(id, null)
                        producers.remove(id)?.release()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * While a desktop is open: keep Wi-Fi out of power saving (it otherwise
     * batches packets and adds 10-100 ms), and run the display at its
     * highest refresh rate so a new picture waits less for the screen.
     */
    private fun lowLatency(activity: Activity, on: Boolean) {
        if (on) {
            if (wifiLock == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                wifiLock = wifi?.createWifiLock(WifiManager.WIFI_MODE_FULL_LOW_LATENCY, "multiplex:desktop")?.apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) activity.display else @Suppress("DEPRECATION") activity.windowManager.defaultDisplay
            val current = display?.mode
            val fastest = display?.supportedModes
                ?.filter { current == null || (it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight) }
                ?.maxByOrNull { it.refreshRate }
            if (fastest != null) {
                activity.window.attributes = activity.window.attributes.apply { preferredDisplayModeId = fastest.modeId }
            }
        } else {
            wifiLock?.let { if (it.isHeld) it.release() }
            wifiLock = null
            activity.window.attributes = activity.window.attributes.apply { preferredDisplayModeId = 0 }
        }
    }

    /** Tells Android the video wants the fastest refresh the screen has. */
    private fun hintFrameRate(surface: Surface) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                surface.setFrameRate(120f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
            } catch (_: Exception) {
                // Only a hint; some surfaces refuse it.
            }
        }
    }
}
