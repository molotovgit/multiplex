package io.github.molotovgit.multiplex

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Sees the phone's notifications, so they can be shown on a paired
 * computer. Android only starts this once the user has given Multiplex
 * notification access in the system settings; until then nothing is seen.
 *
 * Nothing is kept here. Each notification is handed to the app, which
 * decides (per computer, per app) whether it goes anywhere, and passes it
 * on only while that computer is connected.
 */
class PhoneNotifications : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // Not our own, not the permanent ones (music, navigation, the
        // "connections open" note), not the summary line of a group.
        if (sbn.packageName == packageName || sbn.isOngoing) return
        val notification = sbn.notification ?: return
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        if (title.isBlank() && text.isBlank()) return
        val app = try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0)).toString()
        } catch (_: Exception) {
            sbn.packageName
        }
        PhoneChannel.post(mapOf("app" to app, "title" to title, "text" to text))
    }
}
