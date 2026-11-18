package io.github.molotovgit.multiplex

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Paired computers as targets in Android's share sheet ("omarchy" next
 * to the people and apps it suggests). Each is a sharing shortcut; only
 * the computer's id and name go into it.
 */
object ShareTargets {
    private const val CHANNEL = "multiplex/share_targets"
    private const val CATEGORY = "io.github.molotovgit.multiplex.category.COMPUTER"
    private const val PREFIX = "computer-"

    /** Shortcuts on the app's icon (a long press): straight to a thing on the first computer. */
    private const val GO_PREFIX = "go-"
    const val ACTION_GO = "io.github.molotovgit.multiplex.GO"
    private val GO = listOf("agents" to "Agents", "desktop" to "Desktop", "terminal" to "Terminal")

    /** The computer a share was aimed at, from the shortcut id Android passes along. */
    fun hostId(intent: Intent): String? =
        intent.getStringExtra(Intent.EXTRA_SHORTCUT_ID)?.takeIf { it.startsWith(PREFIX) }?.removePrefix(PREFIX)

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // [{"id": "...", "label": "..."}]: the paired computers now.
                "set" -> {
                    val wanted = (call.arguments as? List<*>).orEmpty().mapNotNull { it as? Map<*, *> }
                    try {
                        set(app, wanted.mapNotNull { c -> (c["id"] as? String)?.let { id -> id to ((c["label"] as? String) ?: "Computer") } })
                    } catch (_: Exception) {
                        // Shortcuts are a convenience; the share screen still lists the computers.
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun set(context: Context, computers: List<Pair<String, String>>) {
        val limit = ShortcutManagerCompat.getMaxShortcutCountPerActivity(context).coerceAtLeast(1)
        val shortcuts = computers.take(limit).map { (id, label) ->
            ShortcutInfoCompat.Builder(context, PREFIX + id)
                .setShortLabel(label)
                .setLongLabel("Send to $label")
                .setIcon(IconCompat.createWithResource(context, R.mipmap.ic_launcher))
                // Tapped on the home screen it just opens the app.
                .setIntent(Intent(context, MainActivity::class.java).setAction(Intent.ACTION_MAIN))
                .setCategories(setOf(CATEGORY))
                .setLongLived(true)
                .build()
        }
        // What is done most, one long press on the app's icon away, for the
        // first computer; as many as Android leaves room for. They carry
        // this install's token, like the widget's taps (see ConnectToken).
        val room = (limit - shortcuts.size).coerceAtLeast(0)
        val go = computers.firstOrNull()?.let { (id, label) ->
            GO.take(room).map { (what, name) ->
                ShortcutInfoCompat.Builder(context, "$GO_PREFIX$what")
                    .setShortLabel(name)
                    .setLongLabel("$name on $label")
                    .setIcon(IconCompat.createWithResource(context, R.mipmap.ic_launcher))
                    .setIntent(
                        Intent(context, MainActivity::class.java)
                            .setAction(ACTION_GO)
                            .setData(android.net.Uri.parse("multiplex://go/" + android.net.Uri.encode(id) + "/" + what))
                            .putExtra(ConnectToken.EXTRA, ConnectToken.get(context)),
                    )
                    .build()
            }
        }.orEmpty()
        // Only ours are replaced: other shortcuts the app may have stay.
        val mine = ShortcutManagerCompat.getDynamicShortcuts(context).map { it.id }.filter { it.startsWith(PREFIX) || it.startsWith(GO_PREFIX) }
        val gone = mine - (shortcuts + go).map { it.id }.toSet()
        if (gone.isNotEmpty()) {
            ShortcutManagerCompat.removeLongLivedShortcuts(context, gone.filter { it.startsWith(PREFIX) })
            ShortcutManagerCompat.removeDynamicShortcuts(context, gone.filter { it.startsWith(GO_PREFIX) })
        }
        for (shortcut in shortcuts + go) ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
    }
}
