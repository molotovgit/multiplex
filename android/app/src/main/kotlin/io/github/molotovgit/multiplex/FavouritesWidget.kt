package io.github.molotovgit.multiplex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONException

/**
 * The home-screen widget: up to four favourite hosts. A tap on one opens
 * Multiplex and connects to it.
 *
 * Flutter writes the list as a small JSON (only each host's id and name,
 * no addresses or secrets) through [save]; the widget redraws from it.
 */
class FavouritesWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = build(context)
        for (id in ids) manager.updateAppWidget(id, views)
    }

    companion object {
        private const val PREFS = "multiplex_widget"
        private const val KEY = "favourites"
        private const val MAX = 4
        private const val OPEN_REQUEST = 100
        private val ROWS = intArrayOf(R.id.widget_host_0, R.id.widget_host_1, R.id.widget_host_2, R.id.widget_host_3)

        /** Stores the list from Flutter and redraws every placed widget. */
        fun save(context: Context, json: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json).apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, FavouritesWidget::class.java))
            if (ids.isNotEmpty()) {
                val views = build(context)
                for (id in ids) manager.updateAppWidget(id, views)
            }
        }

        /** (id, label) pairs; none when nothing was saved or it cannot be read. */
        private fun favourites(context: Context): List<Pair<String, String>> {
            val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return emptyList()
            return try {
                val array = JSONArray(json)
                (0 until minOf(array.length(), MAX)).mapNotNull { i ->
                    val item = array.optJSONObject(i) ?: return@mapNotNull null
                    val id = item.optString("id")
                    if (id.isEmpty()) null else id to item.optString("label", id)
                }
            } catch (_: JSONException) {
                emptyList()
            }
        }

        private fun build(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_favourites)
            val hosts = favourites(context)
            views.setOnClickPendingIntent(R.id.widget_title, openApp(context))
            views.setViewVisibility(R.id.widget_empty, if (hosts.isEmpty()) View.VISIBLE else View.GONE)
            views.setOnClickPendingIntent(R.id.widget_empty, openApp(context))
            ROWS.forEachIndexed { i, row ->
                val host = hosts.getOrNull(i)
                if (host == null) {
                    views.setViewVisibility(row, View.GONE)
                } else {
                    views.setViewVisibility(row, View.VISIBLE)
                    views.setTextViewText(row, host.second)
                    views.setContentDescription(row, context.getString(R.string.widget_connect_to, host.second))
                    views.setOnClickPendingIntent(row, connect(context, host.first, i))
                }
            }
            return views
        }

        private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
            context, OPEN_REQUEST,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        /** Each row gets its own data link, so Android keeps the intents apart. */
        private fun connect(context: Context, hostId: String, row: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(IncomingIntents.ACTION_CONNECT)
                .setData(Uri.parse("multiplex://connect/" + Uri.encode(hostId)))
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(context, row, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
    }
}
