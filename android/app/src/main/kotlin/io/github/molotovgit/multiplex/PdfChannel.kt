package io.github.molotovgit.multiplex

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Draws PDF pages for the file preview with Android's own PdfRenderer,
 * so the app needs no PDF library. Flutter opens a file, asks for pages
 * as PNG pictures of a given width, and closes it again.
 *
 * PdfRenderer allows one page open at a time and is not thread safe, so
 * all work runs on one background thread, away from the UI.
 */
class PdfChannel private constructor() {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val open = HashMap<Int, PdfRenderer>()
    private var nextId = 1

    private fun handle(method: String, args: Map<*, *>, result: MethodChannel.Result) {
        worker.execute {
            try {
                val answer: Any? = when (method) {
                    "open" -> openFile(args["path"] as String)
                    "render" -> render(args["id"] as Int, args["page"] as Int, args["width"] as Int)
                    "close" -> {
                        open.remove(args["id"] as Int)?.close()
                        null
                    }
                    else -> {
                        main.post { result.notImplemented() }
                        return@execute
                    }
                }
                main.post { result.success(answer) }
            } catch (e: Exception) {
                main.post { result.error("pdf", e.message ?: "The PDF could not be read.", null) }
            }
        }
    }

    /** Opens a PDF and returns its id and every page's size in points. */
    private fun openFile(path: String): Map<String, Any> {
        val descriptor = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        val renderer = try {
            PdfRenderer(descriptor)
        } catch (e: Exception) {
            descriptor.close()
            throw e
        }
        val sizes = ArrayList<Double>(renderer.pageCount * 2)
        for (i in 0 until renderer.pageCount) {
            renderer.openPage(i).use { page ->
                sizes.add(page.width.toDouble())
                sizes.add(page.height.toDouble())
            }
        }
        val id = nextId++
        open[id] = renderer
        return mapOf("id" to id, "sizes" to sizes)
    }

    /** One page as a PNG, [width] pixels wide, on white paper. */
    private fun render(id: Int, index: Int, width: Int): ByteArray {
        val renderer = open[id] ?: throw IllegalStateException("The PDF is closed.")
        renderer.openPage(index).use { page ->
            val w = width.coerceIn(64, MAX_SIDE)
            val h = (w.toLong() * page.height / page.width.coerceAtLeast(1)).toInt().coerceIn(64, MAX_SIDE)
            val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            try {
                bitmap.eraseColor(Color.WHITE)
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                val out = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                return out.toByteArray()
            } finally {
                bitmap.recycle()
            }
        }
    }

    companion object {
        private const val CHANNEL = "multiplex/pdf"

        /** Neither side of a page grows past this many pixels (memory). */
        private const val MAX_SIDE = 4096

        fun register(messenger: BinaryMessenger) {
            val pdf = PdfChannel()
            MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
                pdf.handle(call.method, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
            }
        }
    }
}
