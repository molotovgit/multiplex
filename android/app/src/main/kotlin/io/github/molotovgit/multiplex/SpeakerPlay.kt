package io.github.molotovgit.multiplex

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import kotlin.concurrent.thread
import kotlin.math.sqrt

/**
 * This phone as a loudspeaker for a paired computer: plays the AAC frames
 * the app hands over (48 kHz, two channels), as media, so they come out
 * of whatever the phone's media sound comes out of.
 *
 * It plays what is current. Frames that pile up (the network delivered a
 * clump after a pause) are thrown away rather than played late.
 */
object SpeakerPlay {
    private const val CHANNEL = "multiplex/speaker"

    /** More frames than this waiting (about a third of a second) is too late. */
    private const val LATE_FRAMES = 16

    private var player: Player? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    player?.stop()
                    player = try {
                        Player(app)
                    } catch (_: Exception) {
                        null
                    }
                    result.success(player != null)
                }
                "feed" -> {
                    (call.arguments as? ByteArray)?.let { player?.feed(it) }
                    result.success(null)
                }
                "stop" -> {
                    player?.stop()
                    player = null
                    result.success(null)
                }
                // For the log: frames played and thrown away, and how loud the last ones were.
                "stats" -> result.success(player?.stats())
                else -> result.notImplemented()
            }
        }
    }

    private class Player(context: Context) {
        private val frames = LinkedBlockingQueue<ByteArray>()
        private val played = AtomicLong()
        private val dropped = AtomicLong()
        @Volatile private var level = 0
        @Volatile private var wanted = true
        private val audio = context.getSystemService(AudioManager::class.java)
        private val track: AudioTrack
        private val codec: MediaCodec
        private var focus: AudioFocusRequest? = null
        private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()

        init {
            val format = AudioFormat.Builder().setSampleRate(RATE).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build()
            val least = AudioTrack.getMinBufferSize(RATE, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
            // A tenth of a second of room: enough to play evenly, little enough to stay current.
            val builder = AudioTrack.Builder().setAudioAttributes(attributes).setAudioFormat(format).setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(maxOf(least, RATE * 4 / 10))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            track = builder.build()
            codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            try {
                val stream = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, RATE, 2)
                // What an AAC decoder has to be told first: AAC-LC, 48 kHz, two channels.
                stream.setByteBuffer("csd-0", ByteBuffer.wrap(byteArrayOf(0x11, 0x90.toByte())))
                codec.configure(stream, null, null, 0)
                codec.start()
            } catch (e: Exception) {
                codec.release()
                track.release()
                throw e
            }
            // Other media makes way while the computer's sound plays; during a call it is silent.
            val listener = AudioManager.OnAudioFocusChangeListener { change ->
                try {
                    track.setVolume(if (change == AudioManager.AUDIOFOCUS_GAIN) 1f else 0f)
                } catch (_: Exception) {
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).setAudioAttributes(attributes).setOnAudioFocusChangeListener(listener).build().also { audio.requestAudioFocus(it) }
            }
            track.play()
            thread(name = "multiplex-speaker") { play() }
        }

        fun feed(frame: ByteArray) {
            if (frames.size > LATE_FRAMES) {
                dropped.addAndGet(frames.size.toLong())
                frames.clear()
            }
            frames.offer(frame)
        }

        fun stats(): Map<String, Any> = mapOf("played" to played.get(), "dropped" to dropped.get(), "level" to level, "waiting" to frames.size)

        fun stop() {
            wanted = false
        }

        private fun play() {
            val info = MediaCodec.BufferInfo()
            var count = 0L
            try {
                while (wanted) {
                    val frame = frames.poll(100, TimeUnit.MILLISECONDS) ?: continue
                    val slot = codec.dequeueInputBuffer(20_000)
                    if (slot < 0) {
                        dropped.incrementAndGet()
                        continue
                    }
                    codec.getInputBuffer(slot)?.apply {
                        clear()
                        put(frame)
                    }
                    codec.queueInputBuffer(slot, 0, frame.size, count * 1_000_000L * 1024 / RATE, 0)
                    count++
                    while (true) {
                        val out = codec.dequeueOutputBuffer(info, 0)
                        if (out < 0) break
                        val sound = codec.getOutputBuffer(out)
                        if (sound != null && info.size > 0) {
                            sound.position(info.offset)
                            sound.limit(info.offset + info.size)
                            level = loudness(sound)
                            track.write(sound, info.size, AudioTrack.WRITE_BLOCKING)
                            played.incrementAndGet()
                        }
                        codec.releaseOutputBuffer(out, false)
                    }
                }
            } catch (_: Exception) {
                // The decoder or the output gave up: stop quietly.
            } finally {
                try {
                    track.pause()
                    track.flush()
                } catch (_: Exception) {
                }
                track.release()
                try {
                    codec.stop()
                } catch (_: Exception) {
                }
                codec.release()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) focus?.let { audio.abandonAudioFocusRequest(it) }
            }
        }

        /** How loud this piece is (root mean square of its samples, 0 to 32768), from every 16th sample. */
        private fun loudness(sound: ByteBuffer): Int {
            val samples = sound.duplicate().order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer()
            var sum = 0.0
            var n = 0
            var i = 0
            while (i < samples.limit()) {
                val s = samples.get(i).toDouble()
                sum += s * s
                n++
                i += 16
            }
            return if (n == 0) 0 else sqrt(sum / n).toInt()
        }

        companion object {
            private const val RATE = 48_000
        }
    }
}
