package io.github.molotovgit.multiplex

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
import android.view.Surface
import kotlin.concurrent.thread

/**
 * An H.264 encoder that takes its pictures from a [surface] (the screen's
 * capture, a camera) and hands what it encodes to [out], piece by piece,
 * on its own thread. 30 pictures a second, a full picture every 2 seconds.
 *
 * [repeatStill]: when nothing changes on the surface, encode the last
 * picture again now and then, so whoever is watching is never without one
 * for long (a screen can stand still; a camera never does).
 */
class PictureEncoder(width: Int, height: Int, bitrate: Int, repeatStill: Boolean, private val out: (PictureEncoder, ByteArray) -> Unit) {
    private val codec: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    val surface: Surface
    @Volatile private var wanted = true

    init {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            setInteger(MediaFormat.KEY_PRIORITY, 0)
            // Each key picture carries what a player needs to start, so
            // one can join at any moment.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) setInteger(MediaFormat.KEY_PREPEND_HEADER_TO_SYNC_FRAMES, 1)
            if (repeatStill) setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 500_000L)
        }
        surface = try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val input = codec.createInputSurface()
            codec.start()
            input
        } catch (e: Exception) {
            codec.release()
            throw e
        }
    }

    /** Begins handing out pieces. */
    fun start() {
        thread(name = "multiplex-encoder") { drain() }
    }

    /** A new bitrate, a full picture now, or both. */
    fun adjust(bitrate: Int?, keyFrame: Boolean) {
        val change = Bundle()
        if (bitrate != null && bitrate > 0) change.putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bitrate)
        if (keyFrame) change.putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
        if (change.isEmpty || !wanted) return
        try {
            codec.setParameters(change)
        } catch (_: IllegalStateException) {
            // It has just stopped.
        }
    }

    /** No more pieces. The encoder is let go once its thread has noticed. */
    fun stop() {
        wanted = false
    }

    private fun drain() {
        val info = MediaCodec.BufferInfo()
        var lastPiece = System.nanoTime()
        while (wanted) {
            val index = try {
                codec.dequeueOutputBuffer(info, 20_000)
            } catch (_: IllegalStateException) {
                break
            }
            if (index < 0) {
                // Nothing for a while (a still screen). The computer takes
                // silence for the phone having gone, so say "still here"
                // in the stream's own terms: an empty access unit
                // delimiter, which a player skips.
                if (System.nanoTime() - lastPiece > 1_000_000_000L) {
                    out(this, STILL_HERE)
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
                    out(this, bytes)
                }
                codec.releaseOutputBuffer(index, false)
            } catch (_: IllegalStateException) {
                break
            }
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
        }
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

    companion object {
        /** An H.264 access unit delimiter: valid in the stream, and nothing to show. */
        private val STILL_HERE = byteArrayOf(0, 0, 0, 1, 9, 0xF0.toByte())
    }
}
