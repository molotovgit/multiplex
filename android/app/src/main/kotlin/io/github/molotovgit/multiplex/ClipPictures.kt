package io.github.molotovgit.multiplex

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Pictures on this phone's clipboard, for sharing the clipboard with a
 * paired computer (text goes through Flutter's own clipboard calls).
 *
 * Android keeps a picture on the clipboard as a link to a file. Reading:
 * the file behind the link, when it is a picture of a kind that is shared.
 * Writing: the picture is put in the app's cache and a link to it on the
 * clipboard; only the app that is pasted into gets to read it.
 */
object ClipPictures {
    private const val CHANNEL = "multiplex/clipboard"

    /** The same limit as on the computer's side. */
    private const val MAX_BYTES = 8 * 1024 * 1024

    private val KINDS = mapOf("image/png" to "png", "image/jpeg" to "jpeg", "image/jpg" to "jpeg", "image/webp" to "webp", "image/gif" to "gif")

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // {kind, bytes}, or null when the clipboard holds no such picture
                // (or the app is not in front: Android then shows it nothing).
                "read" -> result.success(
                    try {
                        read(app)
                    } catch (_: Exception) {
                        null
                    },
                )
                // Text, for when the app has no screen (Flutter's own clipboard
                // calls need one).
                "writeText" -> result.success(
                    try {
                        val text = call.arguments as? String
                        if (text == null) {
                            false
                        } else {
                            app.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Text", text))
                            true
                        }
                    } catch (_: Exception) {
                        false
                    },
                )
                "write" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val kind = call.argument<String>("kind")
                    result.success(
                        try {
                            bytes != null && kind != null && write(app, bytes, kind)
                        } catch (_: Exception) {
                            false
                        },
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun read(context: Context): Map<String, Any>? {
        val clip = context.getSystemService(ClipboardManager::class.java).primaryClip ?: return null
        if (clip.itemCount == 0) return null
        val link = clip.getItemAt(0).uri ?: return null
        val description = clip.description
        val said = (0 until description.mimeTypeCount).map { description.getMimeType(it).lowercase() }
        val kind = said.firstNotNullOfOrNull { KINDS[it] } ?: KINDS[context.contentResolver.getType(link)?.lowercase()] ?: return null
        val bytes = context.contentResolver.openInputStream(link)?.use { input ->
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                out.write(buffer, 0, n)
                if (out.size() > MAX_BYTES) return null
            }
            out.toByteArray()
        } ?: return null
        return if (bytes.isEmpty()) null else mapOf("kind" to kind, "bytes" to bytes)
    }

    private fun write(context: Context, bytes: ByteArray, kind: String): Boolean {
        if (kind !in KINDS.values || bytes.isEmpty() || bytes.size > MAX_BYTES) return false
        val folder = File(context.cacheDir, "clipboard")
        folder.mkdirs()
        // One picture at a time; a new name each time, so an app that looked
        // at the last one does not show that again.
        folder.listFiles()?.forEach { it.delete() }
        val file = File(folder, "picture-${System.currentTimeMillis()}.${if (kind == "jpeg") "jpg" else kind}")
        file.writeBytes(bytes)
        val link = FileProvider.getUriForFile(context, "${context.packageName}.updates", file)
        context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newUri(context.contentResolver, "Picture", link))
        return true
    }
}
