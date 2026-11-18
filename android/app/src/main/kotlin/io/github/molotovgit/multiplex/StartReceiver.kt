package io.github.molotovgit.multiplex

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Starts the app without its screen when the phone has started (after it
 * was first unlocked) or the app was updated, if a paired computer is to
 * be kept linked. The service it starts brings up the engine; the app
 * then connects by itself, as it does when opened.
 */
class StartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> if (AppEngine.wantsToStart(context)) SessionService.startForLinks(context)
        }
    }
}
