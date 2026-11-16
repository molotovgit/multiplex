package io.github.molotovgit.multiplex

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

    init {
        // The same library Flutter already loaded; this only binds the
        // native method below to it.
        System.loadLibrary("multiplex_core")
    }

    @JvmStatic
    private external fun nativeSetSurface(texture: Long, surface: Surface?)

    fun register(engine: FlutterEngine) {
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
                            nativeSetSurface(id, producer.surface)
                            channel.invokeMethod("surfaceChanged", id)
                        }

                        override fun onSurfaceCleanup() {
                            nativeSetSurface(id, null)
                        }
                    })
                    producers[id] = producer
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
}
