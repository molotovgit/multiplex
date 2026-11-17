package io.github.molotovgit.multiplex

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.concurrent.thread

/**
 * Taking a picture of a page, for a paired computer to read the text in.
 *
 * The picture is taken with Google's page scanner (it finds the page's
 * edges and straightens it; it runs in Google Play services, so this app
 * needs no camera permission for it). The picture is handed to Flutter
 * as a JPEG of a size that keeps text sharp without being slow to send.
 */
object TextScan {
    private const val CHANNEL = "multiplex/textscan"
    const val REQUEST = 4316

    /** The picture's longer side is brought down to this many pixels. */
    private const val LONG_SIDE = 2400

    private var pending: MethodChannel.Result? = null

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // The picture as JPEG bytes, or null when the user backed out.
                "scan" -> {
                    if (pending != null) {
                        result.success(null)
                    } else {
                        pending = result
                        val options = GmsDocumentScannerOptions.Builder()
                            .setGalleryImportAllowed(true)
                            .setPageLimit(1)
                            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
                            .build()
                        GmsDocumentScanning.getClient(options).getStartScanIntent(activity)
                            .addOnSuccessListener { sender ->
                                try {
                                    activity.startIntentSenderForResult(sender, REQUEST, null, 0, 0, 0)
                                } catch (e: Exception) {
                                    pending = null
                                    result.error("unavailable", e.message, null)
                                }
                            }
                            .addOnFailureListener { e ->
                                pending = null
                                result.error("unavailable", e.message, null)
                            }
                    }
                }
                // A picture file (one that was shared to the app), made ready the same way.
                "shrink" -> {
                    val path = call.arguments as? String
                    if (path == null) {
                        result.success(null)
                    } else {
                        deliver(activity, Uri.fromFile(File(path)), result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** The scanner finished or was left (called by the activity). */
    fun onResult(activity: Activity, resultCode: Int, data: Intent?) {
        val result = pending ?: return
        pending = null
        val page = if (resultCode == Activity.RESULT_OK) GmsDocumentScanningResult.fromActivityResultIntent(data)?.pages?.firstOrNull()?.imageUri else null
        if (page == null) {
            result.success(null)
        } else {
            deliver(activity, page, result)
        }
    }

    private fun deliver(activity: Activity, picture: Uri, result: MethodChannel.Result) {
        thread(name = "multiplex-textscan") {
            val bytes = try {
                shrunk(activity, picture)
            } catch (_: Exception) {
                null
            }
            activity.runOnUiThread { result.success(bytes) }
        }
    }

    /** The picture as a JPEG whose longer side is at most [LONG_SIDE]. */
    private fun shrunk(context: Context, picture: Uri): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(picture)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply { inSampleSize = sample(bounds.outWidth, bounds.outHeight, LONG_SIDE) }
        val decoded = context.contentResolver.openInputStream(picture)?.use { BitmapFactory.decodeStream(it, null, options) } ?: return null
        val longest = maxOf(decoded.width, decoded.height)
        val sized = if (longest > LONG_SIDE) {
            Bitmap.createScaledBitmap(decoded, decoded.width * LONG_SIDE / longest, decoded.height * LONG_SIDE / longest, true)
        } else {
            decoded
        }
        val out = ByteArrayOutputStream()
        sized.compress(Bitmap.CompressFormat.JPEG, 88, out)
        if (sized !== decoded) sized.recycle()
        decoded.recycle()
        return out.toByteArray()
    }

    /** How coarsely a picture can be decoded and still be at least [longSide] on its longer side: a power of two. */
    fun sample(width: Int, height: Int, longSide: Int): Int {
        var step = 1
        while (maxOf(width, height) / (step * 2) >= longSide) step *= 2
        return step
    }
}
