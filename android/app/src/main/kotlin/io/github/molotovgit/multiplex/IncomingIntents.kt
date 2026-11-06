package io.github.molotovgit.multiplex

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import java.io.File

/**
 * Things other parts of Android ask Multiplex to do, queued until the
 * Flutter side collects them ("take"):
 * - a tap on a host in the home-screen widget (connect to it);
 * - files shared from another app (upload them to a server).
 *
 * Shared files arrive as content links that only this activity may read,
 * so each one is copied into the app's cache first (on a background
 * thread) and Flutter gets the copies' paths. Flutter deletes a copy once
 * its upload ends; copies older than a day are cleared here.
 *
 * Flutter waits for the app lock before it acts on anything.
 */
class IncomingIntents(private val context: Context, private val onChanged: () -> Unit) {
    private val pending = mutableListOf<Map<String, Any>>()

    /** Reads [intent]; returns true when it was one of ours. */
    fun read(intent: Intent?): Boolean = when (intent?.action) {
        ACTION_CONNECT -> readConnect(intent)
        Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE -> readShare(intent)
        else -> false
    }

    /** Everything waiting, oldest first, and forgets it. */
    @Synchronized
    fun take(): List<Map<String, Any>> {
        val all = pending.toList()
        pending.clear()
        return all
    }

    private fun readConnect(intent: Intent): Boolean {
        val data = intent.data ?: return false
        if (data.scheme != "multiplex" || data.host != "connect") return false
        val hostId = data.lastPathSegment ?: return false
        add(mapOf("type" to "connect", "hostId" to hostId))
        return true
    }

    private fun readShare(intent: Intent): Boolean {
        val links = streams(intent)
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (links.isEmpty() && text.isNullOrEmpty()) return false
        Thread {
            val folder = shareFolder()
            val names = mutableSetOf<String>()
            val files = mutableListOf<Map<String, String>>()
            for (link in links) {
                val name = unique(safeName(displayName(link)), names)
                val copy = File(folder, name)
                val copied = try {
                    context.contentResolver.openInputStream(link)?.use { input -> copy.outputStream().use { input.copyTo(it) } } != null
                } catch (_: Exception) {
                    false
                }
                if (copied) files.add(mapOf("name" to name, "path" to copy.absolutePath))
            }
            // Shared text without a file (a link, a note) becomes a text file.
            if (links.isEmpty() && text != null) {
                val copy = File(folder, unique("shared-text.txt", names))
                copy.writeText(text)
                files.add(mapOf("name" to copy.name, "path" to copy.absolutePath))
            }
            if (files.isNotEmpty()) add(mapOf("type" to "share", "files" to files))
        }.start()
        return true
    }

    private fun streams(intent: Intent): List<Uri> {
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val list = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
            return list.orEmpty().filterNotNull()
        }
        val one = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
        return listOfNotNull(one)
    }

    /** A new folder per share in the cache; clears shares older than a day. */
    private fun shareFolder(): File {
        val root = File(context.cacheDir, "shared")
        val dayAgo = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        root.listFiles()?.filter { it.lastModified() < dayAgo }?.forEach { it.deleteRecursively() }
        return File(root, System.currentTimeMillis().toString()).apply { mkdirs() }
    }

    private fun displayName(link: Uri): String {
        try {
            context.contentResolver.query(link, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val name = cursor.getString(0)
                    if (!name.isNullOrBlank()) return name
                }
            }
        } catch (_: Exception) {
            // Some apps share links that cannot be asked for a name.
        }
        return link.lastPathSegment ?: "shared-file"
    }

    @Synchronized
    private fun queue(action: Map<String, Any>) {
        pending.add(action)
    }

    private fun add(action: Map<String, Any>) {
        queue(action)
        onChanged()
    }

    companion object {
        const val ACTION_CONNECT = "io.github.molotovgit.multiplex.CONNECT"

        /** No folder parts and no empty name: the name is used on the server too. */
        fun safeName(name: String): String {
            val cleaned = name.substringAfterLast('/').replace('\u0000', '_').trim()
            return if (cleaned.isEmpty() || cleaned == "." || cleaned == "..") "shared-file" else cleaned
        }

        /** "photo.jpg", then "photo (1).jpg" for a second file of that name. */
        fun unique(name: String, taken: MutableSet<String>): String {
            var candidate = name
            var n = 1
            val dot = name.lastIndexOf('.').takeIf { it > 0 } ?: name.length
            while (!taken.add(candidate)) {
                candidate = name.substring(0, dot) + " (" + n++ + ")" + name.substring(dot)
            }
            return candidate
        }
    }
}
