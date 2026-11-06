package io.github.molotovgit.multiplex

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * The phone side of the in-app updater (lib/update/update_platform.dart).
 *
 * Flutter downloads the APK into cache/updates and checks its SHA-256.
 * Before it is installed, this looks inside the file and refuses it unless
 * it is Multiplex itself (same package name), signed with exactly the same
 * certificate(s) as the app that is installed now, and a newer build. Only
 * then is the system installer opened, through a content:// link from
 * [UpdateFileProvider]. The installer itself repeats the signature check,
 * so this is a second lock that also gives a clear message.
 */
object UpdateChannel {
    private const val CHANNEL = "multiplex/updater"
    private const val APK_TYPE = "application/vnd.android.package-archive"

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "installed" -> {
                        val info = packageInfo(activity, 0)
                        result.success(mapOf("versionName" to (info.versionName ?: ""), "versionCode" to versionCode(info)))
                    }
                    "checkApk" -> result.success(checkApk(activity, updateFile(activity, call.argument<String>("path"))))
                    "canInstall" -> result.success(activity.packageManager.canRequestPackageInstalls())
                    "openInstallPermission" -> {
                        openInstallPermission(activity)
                        result.success(null)
                    }
                    "install" -> {
                        install(activity, updateFile(activity, call.argument<String>("path")))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("update", e.message, null)
            }
        }
    }

    /** Only files in our own cache/updates folder are accepted. */
    private fun updateFile(activity: Activity, path: String?): File {
        val dir = File(activity.cacheDir, "updates").canonicalFile
        val file = File(path ?: "").canonicalFile
        require(file.parentFile == dir && file.isFile) { "not an update file" }
        return file
    }

    /**
     * Null when the APK may be installed; otherwise one word for Flutter:
     * notAnApp, otherApp, otherSigner or notNewer.
     */
    private fun checkApk(activity: Activity, file: File): String? {
        val pm = activity.packageManager
        val flags = signatureFlag()
        val apk = pm.getPackageArchiveInfo(file.path, flags) ?: return "notAnApp"
        if (apk.packageName != activity.packageName) return "otherApp"
        val ours = signers(packageInfo(activity, flags))
        // Some Android 9-10 builds leave signingInfo empty for a file that
        // is not installed; the older signature list still has it.
        val theirs = signers(apk).ifEmpty { pm.getPackageArchiveInfo(file.path, legacySignatureFlag())?.let(::signers).orEmpty() }
        // Both sets must be known and exactly equal: a missing list never
        // counts as a match.
        if (ours.isEmpty() || theirs != ours) return "otherSigner"
        if (versionCode(apk) <= versionCode(packageInfo(activity, 0))) return "notNewer"
        return null
    }

    @Suppress("DEPRECATION")
    private fun legacySignatureFlag(): Int = PackageManager.GET_SIGNATURES

    @Suppress("DEPRECATION")
    private fun signatureFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    /**
     * SHA-256 of each certificate that signs the APK now. On Android 9+ the
     * current signers (apkContentsSigners) are used, not the rotation
     * history; older phones only have the plain signature list.
     */
    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val certs: Array<Signature>? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.signingInfo?.apkContentsSigners ?: info.signatures else info.signatures
        return certs.orEmpty().map { sha256(it.toByteArray()) }.toSet()
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    @Suppress("DEPRECATION")
    private fun packageInfo(activity: Activity, flags: Int): PackageInfo = activity.packageManager.getPackageInfo(activity.packageName, flags)

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()

    /** The system page "Install unknown apps" for Multiplex alone. */
    private fun openInstallPermission(activity: Activity) {
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
        try {
            activity.startActivity(intent)
        } catch (e: Exception) {
            // Some phones only have the general security settings.
            activity.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
        }
    }

    private fun install(activity: Activity, file: File) {
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_TYPE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(intent)
    }
}

/** Shares only cache/updates (see res/xml/update_paths.xml) with the installer. */
class UpdateFileProvider : FileProvider()
