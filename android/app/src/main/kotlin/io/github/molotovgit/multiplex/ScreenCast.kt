package io.github.molotovgit.multiplex

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.view.Display
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/**
 * This phone's screen as a video stream, for a window on a paired
 * computer. Android asks the user each time before anything is captured,
 * and shows that the screen is being shared while it is.
 *
 * The picture is encoded here (H.264, hardware) and handed to Flutter in
 * pieces, which sends them over the SSH connection. Nothing is stored.
 */
object ScreenCast {
    private const val CHANNEL = "multiplex/screencast"
    private const val FRAMES = "multiplex/screencast/frames"
    const val REQUEST = 4310

    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // True once the user allowed it and capturing has begun.
                "start" -> {
                    if (pending != null) {
                        result.success(false)
                    } else {
                        ScreenCastService.startWith(call.argument<Int>("bitrate"))
                        pending = result
                        val manager = activity.getSystemService(MediaProjectionManager::class.java)
                        try {
                            activity.startActivityForResult(manager.createScreenCaptureIntent(), REQUEST)
                        } catch (_: Exception) {
                            pending = null
                            result.success(false)
                        }
                    }
                }
                "stop" -> {
                    activity.stopService(Intent(activity, ScreenCastService::class.java))
                    result.success(null)
                }
                // The connection decides how good a picture it can carry.
                "adjust" -> {
                    ScreenCastService.adjust(call.argument<Int>("bitrate"), call.argument<Boolean>("keyFrame") == true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, FRAMES).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
    }

    /** The user answered Android's question (called by the activity). */
    fun onResult(activity: Activity, resultCode: Int, data: Intent?) {
        val result = pending ?: return
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(false)
            return
        }
        val intent = Intent(activity, ScreenCastService::class.java).putExtra("code", resultCode).putExtra("data", data)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) activity.startForegroundService(intent) else activity.startService(intent)
        result.success(true)
    }

    /** A piece of the stream; an empty one says it has ended. */
    fun piece(bytes: ByteArray) {
        main.post { sink?.success(bytes) }
    }
}

/** Captures and encodes while the screen is being shown on a computer. */
class ScreenCastService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var size = 0 to 0

    /** Counts encoders: only the newest one's pictures go out. */
    private val turn = Any()
    private var newest = 0

    private val turned = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) {}

        override fun onDisplayRemoved(displayId: Int) {}

        override fun onDisplayChanged(displayId: Int) {
            if (displayId == Display.DEFAULT_DISPLAY) fit()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android wants the notification up before the capture starts.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification())
        }
        val code = intent?.getIntExtra("code", 0) ?: 0
        val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra("data", Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra("data")
        }
        try {
            begin(code, data ?: throw IllegalStateException("no permission to capture"))
        } catch (_: Exception) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun begin(code: Int, data: Intent) {
        val manager = getSystemService(MediaProjectionManager::class.java)
        val projection = manager.getMediaProjection(code, data) ?: throw IllegalStateException("no capture")
        this.projection = projection
        // The user can stop sharing from Android's own controls.
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                stopSelf()
            }
        }, main)

        val (width, height, dpi) = screen()
        val (codec, surface) = encoder(width, height)
        display = projection.createVirtualDisplay("multiplex-screen", width, height, dpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, surface, null, null)
        size = width to height
        follow(codec, surface)
        getSystemService(DisplayManager::class.java).registerDisplayListener(turned, main)
    }

    /**
     * The phone was turned: the picture takes the screen's new shape. The
     * capture stays the same one (Android allows one per permission); it
     * is given a new size and a new encoder, which starts with a full
     * picture that tells the player the new size.
     */
    private fun fit() {
        val display = display ?: return
        val (width, height, dpi) = screen()
        if (width to height == size) return
        try {
            val (codec, surface) = encoder(width, height)
            display.resize(width, height, dpi)
            display.surface = surface
            size = width to height
            follow(codec, surface)
        } catch (_: Exception) {
            stopSelf()
        }
    }

    /** The screen as it is now, scaled for the picture, and its density. */
    private fun screen(): Triple<Int, Int, Int> {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY).getRealMetrics(metrics)
        val (width, height) = sized(metrics.widthPixels, metrics.heightPixels)
        return Triple(width, height, metrics.densityDpi)
    }

    /** A started encoder for this size, and the surface it takes the screen from. */
    private fun encoder(width: Int, height: Int): Pair<MediaCodec, Surface> {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            setInteger(MediaFormat.KEY_PRIORITY, 0)
            // Each key picture carries what a player needs to start, so the
            // window can open at any moment.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) setInteger(MediaFormat.KEY_PREPEND_HEADER_TO_SYNC_FRAMES, 1)
            // A still screen produces no pictures; repeat the last one now
            // and then so the window is never empty for long.
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 500_000L)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val surface = codec.createInputSurface()
            codec.start()
            return codec to surface
        } catch (e: Exception) {
            codec.release()
            throw e
        }
    }

    /** From now on this encoder's pictures go out; the one before it winds down. */
    private fun follow(codec: MediaCodec, surface: Surface) {
        val mine = synchronized(turn) { ++newest }
        live = codec
        thread(name = "multiplex-screencast") { drain(codec, surface, mine) }
    }

    /** Hands each encoded piece to Flutter as it comes out, then lets the encoder go. */
    private fun drain(codec: MediaCodec, surface: Surface, mine: Int) {
        val info = MediaCodec.BufferInfo()
        var lastPiece = System.nanoTime()
        while (synchronized(turn) { newest == mine }) {
            val index = try {
                codec.dequeueOutputBuffer(info, 20_000)
            } catch (_: IllegalStateException) {
                break
            }
            if (index < 0) {
                // A still screen may produce nothing for a while. The
                // computer takes silence for the phone having gone, so say
                // "still here" in the stream's own terms: an empty access
                // unit delimiter, which a player skips.
                if (System.nanoTime() - lastPiece > 1_000_000_000L) {
                    send(STILL_HERE, mine)
                    lastPiece = System.nanoTime()
                }
                continue
            }
            lastPiece = System.nanoTime()
            try {
                val buffer = codec.getOutputBuffer(index)
                if (buffer != null && info.size > 0) {
                    val bytes = ByteArray(info.size)
                    buffer.position(info.offset)
                    buffer.get(bytes)
                    send(bytes, mine)
                }
                codec.releaseOutputBuffer(index, false)
            } catch (_: IllegalStateException) {
                break
            }
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
        }
        if (live === codec) live = null
        try {
            codec.stop()
        } catch (_: Exception) {
        }
        try {
            codec.release()
            surface.release()
        } catch (_: Exception) {
        }
    }

    /** A piece goes out only while its encoder is the newest: never an old picture after a new one. */
    private fun send(bytes: ByteArray, mine: Int) {
        synchronized(turn) {
            if (newest == mine) ScreenCast.piece(bytes)
        }
    }

    override fun onDestroy() {
        // No encoder is the newest any more: each drain loop ends and lets its encoder go.
        synchronized(turn) { newest = -1 }
        live = null
        try {
            getSystemService(DisplayManager::class.java).unregisterDisplayListener(turned)
        } catch (_: Exception) {
        }
        try {
            display?.release()
        } catch (_: Exception) {
        }
        try {
            projection?.stop()
        } catch (_: Exception) {
        }
        display = null
        projection = null
        // An empty piece: the stream is over.
        ScreenCast.piece(ByteArray(0))
        super.onDestroy()
    }

    private fun notification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Showing this phone's screen", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Shown while this phone's screen is in a window on a paired computer."
            manager.createNotificationChannel(channel)
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        return builder
            .setSmallIcon(R.drawable.ic_stat_connected)
            .setContentTitle("This phone's screen is showing on your computer")
            .setContentText("Open Multiplex to stop")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "screencast"
        private const val NOTIFICATION_ID = 4311

        /** An H.264 access unit delimiter: valid in the stream, and nothing to show. */
        private val STILL_HERE = byteArrayOf(0, 0, 0, 1, 9, 0xF0.toByte())

        @Volatile private var live: MediaCodec? = null

        /** What the encoder is asked for, in bits per second. Kept across a turn of the phone. */
        @Volatile private var bitrate = 4_000_000

        /** A new capture starts at this bitrate (the app's core says which). */
        fun startWith(bitrate: Int?) {
            this.bitrate = bitrate?.takeIf { it > 0 } ?: 4_000_000
        }

        /** Changes the running encoder: a new bitrate, a full picture now, or both. */
        fun adjust(bitrate: Int?, keyFrame: Boolean) {
            if (bitrate != null && bitrate > 0) this.bitrate = bitrate
            val codec = live ?: return
            val change = Bundle()
            if (bitrate != null && bitrate > 0) change.putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bitrate)
            if (keyFrame) change.putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
            if (change.isEmpty) return
            try {
                codec.setParameters(change)
            } catch (_: IllegalStateException) {
                // It has just stopped.
            }
        }

        /** The screen scaled so its long side is at most 1600, in sizes an encoder takes. */
        fun sized(width: Int, height: Int): Pair<Int, Int> {
            val scale = minOf(1.0, 1600.0 / maxOf(width, height))
            fun even(v: Double) = (Math.round(v / 16.0) * 16).toInt().coerceAtLeast(16)
            return even(width * scale) to even(height * scale)
        }
    }
}
