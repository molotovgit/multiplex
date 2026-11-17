package io.github.molotovgit.multiplex

import android.app.Activity
import android.os.Build
import android.provider.Settings
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * What pairing needs from Android: the QR scanner and the phone's name.
 *
 * The scanner is Google's (from Play services). It opens its own camera
 * screen and hands back the text of the code, so Multiplex itself never
 * asks for the camera permission.
 */
object PairChannel {
    private const val CHANNEL = "multiplex/pair"

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // The scanned text, or null when the user closed the scanner.
                "scan" -> {
                    val options = GmsBarcodeScannerOptions.Builder()
                        .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                        .enableAutoZoom()
                        .build()
                    GmsBarcodeScanning.getClient(activity, options).startScan()
                        .addOnSuccessListener { code -> result.success(code.rawValue) }
                        .addOnCanceledListener { result.success(null) }
                        .addOnFailureListener { e -> result.error("scan", e.message, null) }
                }
                // The name the owner gave the phone, or its model.
                "deviceName" -> result.success(
                    Settings.Global.getString(activity.contentResolver, "device_name")?.takeIf { it.isNotBlank() } ?: Build.MODEL,
                )
                else -> result.notImplemented()
            }
        }
    }
}
