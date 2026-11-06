package io.github.molotovgit.multiplex

import android.content.Context
import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Proof that a "connect to this host" request comes from our own widget.
 *
 * MainActivity has to be exported (it is the launcher screen and the share
 * target), so any app could send it the CONNECT action. Only our widget
 * knows this random value: it is made once per install, kept in the app's
 * private preferences, and put into the widget's PendingIntents, whose
 * extras other apps cannot read. A CONNECT request without it is ignored.
 */
object ConnectToken {
    const val EXTRA = "io.github.molotovgit.multiplex.CONNECT_TOKEN"
    private const val PREFS = "multiplex_widget"
    private const val KEY = "connect_token"

    /** This install's token, made on first use. */
    @Synchronized
    fun get(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.getString(KEY, null)?.let { return it }
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val token = Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.URL_SAFE)
        prefs.edit().putString(KEY, token).apply()
        return token
    }

    /** True only when [given] is this install's token (compared in constant time). */
    fun matches(context: Context, given: String?): Boolean {
        if (given.isNullOrEmpty()) return false
        return MessageDigest.isEqual(given.toByteArray(), get(context).toByteArray())
    }
}
