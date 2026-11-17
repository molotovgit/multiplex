package io.github.molotovgit.multiplex

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/**
 * This phone's microphone as a sound stream, for a paired computer to
 * offer to its programs as a microphone. Android asks for the microphone
 * once; while it is in use a notification says so, and Android shows its
 * own microphone indicator.
 *
 * The sound is encoded here (AAC, 48 kHz, one channel, 64 kbit/s) and
 * handed to Flutter in pieces, each a frame with its ADTS header, which
 * sends them over the SSH connection. Nothing is stored.
 */
object MicCast {
    private const val CHANNEL = "multiplex/miccast"
    private const val FRAMES = "multiplex/miccast/frames"
    const val REQUEST = 4314

    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // True once the microphone may be used and recording has begun.
                "start" -> when {
                    pending != null -> result.success(false)
                    activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED -> result.success(launch(activity))
                    else -> {
                        pending = result
                        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST)
                    }
                }
                "stop" -> {
                    activity.stopService(Intent(activity, MicCastService::class.java))
                    result.success(null)
                }
                // Sound is not adjusted the way a picture is.
                "adjust" -> result.success(null)
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

    /** The user answered Android's question about the microphone (called by the activity). */
    fun onPermission(activity: Activity, grantResults: IntArray) {
        val result = pending ?: return
        pending = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        result.success(granted && launch(activity))
    }

    private fun launch(activity: Activity): Boolean {
        return try {
            val intent = Intent(activity, MicCastService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) activity.startForegroundService(intent) else activity.startService(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /** A piece of the stream; an empty one says it has ended. */
    fun piece(bytes: ByteArray) {
        main.post { sink?.success(bytes) }
    }

    /**
     * The seven bytes that go before each AAC frame in a stream (ADTS), so
     * a decoder can find the frames: AAC-LC, 48 kHz, one channel, and the
     * frame's length including these bytes.
     */
    fun adtsHeader(frameBytes: Int): ByteArray {
        val length = frameBytes + 7
        val profile = 2 // AAC-LC
        val rate = 3 // 48 kHz
        val channels = 1
        return byteArrayOf(
            0xFF.toByte(),
            0xF1.toByte(),
            (((profile - 1) shl 6) or (rate shl 2) or (channels shr 2)).toByte(),
            (((channels and 3) shl 6) or (length shr 11)).toByte(),
            ((length and 0x7FF) shr 3).toByte(),
            (((length and 7) shl 5) or 0x1F).toByte(),
            0xFC.toByte(),
        )
    }
}

/** Records and encodes while the microphone is lent to a computer. */
class MicCastService : Service() {
    @Volatile private var wanted = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android wants the notification up before the microphone opens.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIFICATION_ID, notification())
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            stopSelf()
        } else if (!wanted) {
            wanted = true
            thread(name = "multiplex-microphone") { record() }
        }
        return START_NOT_STICKY
    }

    @SuppressLint("MissingPermission")
    private fun record() {
        var recorder: AudioRecord? = null
        var codec: MediaCodec? = null
        try {
            val least = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            recorder = AudioRecord(MediaRecorder.AudioSource.MIC, RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(least, FRAME_BYTES * 4))
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, RATE, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, 64_000)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, FRAME_BYTES * 2)
            }
            codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            recorder.startRecording()

            val samples = ByteArray(FRAME_BYTES)
            val info = MediaCodec.BufferInfo()
            var frames = 0L
            while (wanted) {
                // One AAC frame's worth of sound at a time (about 21 ms).
                var have = 0
                while (have < FRAME_BYTES && wanted) {
                    val read = recorder.read(samples, have, FRAME_BYTES - have)
                    if (read <= 0) break
                    have += read
                }
                if (have < FRAME_BYTES) break
                val slot = codec.dequeueInputBuffer(50_000)
                if (slot >= 0) {
                    codec.getInputBuffer(slot)?.apply {
                        clear()
                        put(samples)
                    }
                    codec.queueInputBuffer(slot, 0, FRAME_BYTES, frames * 1_000_000L * 1024 / RATE, 0)
                    frames++
                }
                while (true) {
                    val out = codec.dequeueOutputBuffer(info, 0)
                    if (out < 0) break
                    val buffer = codec.getOutputBuffer(out)
                    // The encoder's own settings are in each frame's header already.
                    if (buffer != null && info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                        val frame = ByteArray(info.size + 7)
                        MicCast.adtsHeader(info.size).copyInto(frame)
                        buffer.position(info.offset)
                        buffer.get(frame, 7, info.size)
                        MicCast.piece(frame)
                    }
                    codec.releaseOutputBuffer(out, false)
                }
            }
        } catch (_: Exception) {
            // The microphone could not be had, or was taken away.
        } finally {
            try {
                recorder?.stop()
            } catch (_: Exception) {
            }
            recorder?.release()
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            codec?.release()
            // An empty piece: the stream is over.
            MicCast.piece(ByteArray(0))
            if (wanted) {
                wanted = false
                stopSelf()
            }
        }
    }

    override fun onDestroy() {
        wanted = false
        super.onDestroy()
    }

    private fun notification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "This phone's microphone on a computer", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Shown while a paired computer is using this phone's microphone."
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
            .setContentTitle("Your computer is using this phone's microphone")
            .setContentText("Open Multiplex to stop")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "miccast"
        private const val NOTIFICATION_ID = 4315
        private const val RATE = 48_000

        /** 1024 samples of 16 bits: what one AAC frame is made from. */
        private const val FRAME_BYTES = 2048
    }
}
