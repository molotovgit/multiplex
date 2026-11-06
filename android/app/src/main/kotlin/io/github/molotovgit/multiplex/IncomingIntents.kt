package io.github.molotovgit.multiplex

import android.content.Intent

/**
 * Things other parts of Android ask Multiplex to do, queued until the
 * Flutter side collects them ("take"): a tap on a host in the home-screen
 * widget. Flutter waits for the app lock before it acts on them.
 */
class IncomingIntents(private val onChanged: () -> Unit) {
    private val pending = mutableListOf<Map<String, Any>>()

    /** Reads [intent]; returns true when it was one of ours. */
    fun read(intent: Intent?): Boolean {
        if (intent?.action != ACTION_CONNECT) return false
        val data = intent.data ?: return false
        if (data.scheme != "multiplex" || data.host != "connect") return false
        val hostId = data.lastPathSegment ?: return false
        add(mapOf("type" to "connect", "hostId" to hostId))
        return true
    }

    /** Everything waiting, oldest first, and forgets it. */
    @Synchronized
    fun take(): List<Map<String, Any>> {
        val all = pending.toList()
        pending.clear()
        return all
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
    }
}
