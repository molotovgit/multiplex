package io.github.molotovgit.multiplex

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Phone storage for the two-pane copy and folder sync. Reading files that
 * other apps made (Download, Documents...) needs "All files access" on
 * Android 11 and later; the user grants it on a system settings page,
 * which this opens. Nothing is asked until the user taps the button.
 */
object StorageChannel {
    private const val CHANNEL = "multiplex/storage"

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAllFilesAccess" -> result.success(hasAccess(activity))
                "askAllFilesAccess" -> {
                    ask(activity)
                    result.success(null)
                }
                "storageRoot" -> result.success(Environment.getExternalStorageDirectory().absolutePath)
                else -> result.notImplemented()
            }
        }
    }

    private fun hasAccess(activity: Activity): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }

    private fun ask(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${activity.packageName}"))
            try {
                activity.startActivity(intent)
            } catch (e: Exception) {
                // Some phones only have the general list of apps.
                activity.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            activity.requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE), 2)
        }
    }
}
