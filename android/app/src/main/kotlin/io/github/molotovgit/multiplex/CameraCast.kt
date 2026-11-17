package io.github.molotovgit.multiplex

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Range
import android.view.Display
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * This phone's camera as a video stream, for a paired computer to offer
 * to its programs as a webcam. Android asks for the camera once; while
 * the camera is in use a notification says so, and Android shows its own
 * camera indicator.
 *
 * The picture is encoded here (H.264, hardware) and handed to Flutter in
 * pieces, which sends them over the SSH connection. Nothing is stored.
 */
object CameraCast {
    private const val CHANNEL = "multiplex/camcast"
    private const val FRAMES = "multiplex/camcast/frames"
    const val REQUEST = 4312

    private val main = Handler(Looper.getMainLooper())
    private var pending: Pair<MethodCall, MethodChannel.Result>? = null
    private var sink: EventChannel.EventSink? = null

    /** How far the picture has to be turned clockwise to stand upright, in degrees. */
    @Volatile private var turn = 0

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // True once the camera may be used and filming has begun.
                "start" -> when {
                    pending != null -> result.success(false)
                    activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED -> result.success(launch(activity, call))
                    else -> {
                        pending = call to result
                        activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST)
                    }
                }
                "stop" -> {
                    activity.stopService(Intent(activity, CameraCastService::class.java))
                    result.success(null)
                }
                // The connection decides how good a picture it can carry.
                "adjust" -> {
                    CameraCastService.adjust(call.argument<Int>("bitrate"), call.argument<Boolean>("keyFrame") == true)
                    result.success(null)
                }
                "turn" -> result.success(turn)
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, FRAMES).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
    }

    /** The user answered Android's question about the camera (called by the activity). */
    fun onPermission(activity: Activity, grantResults: IntArray) {
        val (call, result) = pending ?: return
        pending = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        result.success(granted && launch(activity, call))
    }

    /** Picks the camera, works out how its picture lies, and starts filming. */
    private fun launch(activity: Activity, call: MethodCall): Boolean {
        return try {
            val manager = activity.getSystemService(CameraManager::class.java)
            val wanted = if (call.argument<String>("facing") == "front") CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
            val id = manager.cameraIdList.firstOrNull { manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == wanted }
                ?: manager.cameraIdList.firstOrNull()
                ?: return false
            val traits = manager.getCameraCharacteristics(id)
            val sensor = traits.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
            val front = traits.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
            val held = when (activity.getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY).rotation) {
                Surface.ROTATION_90 -> 90
                Surface.ROTATION_180 -> 180
                Surface.ROTATION_270 -> 270
                else -> 0
            }
            turn = upright(sensor, held, front)
            val intent = Intent(activity, CameraCastService::class.java).putExtra("camera", id).putExtra("bitrate", call.argument<Int>("bitrate") ?: 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) activity.startForegroundService(intent) else activity.startService(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * The clockwise turn that makes a camera's picture upright: the sensor
     * lies at [sensor] degrees in the phone, and the phone is held turned
     * by [held] degrees. A front camera looks the other way, so the
     * phone's turn counts the other way round.
     */
    fun upright(sensor: Int, held: Int, front: Boolean): Int = if (front) (sensor + held) % 360 else (sensor - held + 360) % 360

    /** A piece of the stream; an empty one says it has ended. */
    fun piece(bytes: ByteArray) {
        main.post { sink?.success(bytes) }
    }
}

/** Films and encodes while the camera is lent to a computer. */
class CameraCastService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var encoder: PictureEncoder? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android wants the notification up before the camera opens.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
        } else {
            startForeground(NOTIFICATION_ID, notification())
        }
        try {
            open(intent?.getStringExtra("camera") ?: throw IllegalStateException("no camera"), intent.getIntExtra("bitrate", 0).takeIf { it > 0 } ?: 4_000_000)
        } catch (_: Exception) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun open(id: String, bitrate: Int) {
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) throw IllegalStateException("no permission")
        val manager = getSystemService(CameraManager::class.java)
        val encoder = PictureEncoder(WIDTH, HEIGHT, bitrate, repeatStill = false) { _, bytes -> CameraCast.piece(bytes) }
        this.encoder = encoder
        live = encoder
        // 30 pictures a second when the camera can hold that, else its best.
        val rates = manager.getCameraCharacteristics(id).get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
        val rate = rates?.filter { it.upper == 30 }?.maxByOrNull { it.lower } ?: rates?.maxByOrNull { it.upper }
        manager.openCamera(id, object : CameraDevice.StateCallback() {
            override fun onOpened(device: CameraDevice) {
                camera = device
                try {
                    val request = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                        addTarget(encoder.surface)
                        if (rate != null) set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, Range(rate.lower, rate.upper))
                    }
                    @Suppress("DEPRECATION")
                    device.createCaptureSession(listOf(encoder.surface), object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(configured: CameraCaptureSession) {
                            session = configured
                            try {
                                configured.setRepeatingRequest(request.build(), null, main)
                                encoder.start()
                            } catch (_: Exception) {
                                stopSelf()
                            }
                        }

                        override fun onConfigureFailed(failed: CameraCaptureSession) {
                            stopSelf()
                        }
                    }, main)
                } catch (_: Exception) {
                    stopSelf()
                }
            }

            // Another app took the camera, or it failed.
            override fun onDisconnected(device: CameraDevice) {
                stopSelf()
            }

            override fun onError(device: CameraDevice, error: Int) {
                stopSelf()
            }
        }, main)
    }

    override fun onDestroy() {
        live = null
        try {
            session?.close()
        } catch (_: Exception) {
        }
        try {
            camera?.close()
        } catch (_: Exception) {
        }
        encoder?.stop()
        session = null
        camera = null
        encoder = null
        // An empty piece: the stream is over.
        CameraCast.piece(ByteArray(0))
        super.onDestroy()
    }

    private fun notification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "This phone's camera on a computer", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Shown while a paired computer is using this phone's camera."
            manager.createNotificationChannel(channel)
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        return builder
            .setSmallIcon(R.drawable.ic_stat_connected)
            .setContentTitle("Your computer is using this phone's camera")
            .setContentText("Open Multiplex to stop")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "camcast"
        private const val NOTIFICATION_ID = 4313
        private const val WIDTH = 1280
        private const val HEIGHT = 720

        @Volatile private var live: PictureEncoder? = null

        /** Changes the running encoder: a new bitrate, a full picture now, or both. */
        fun adjust(bitrate: Int?, keyFrame: Boolean) {
            live?.adjust(bitrate, keyFrame)
        }
    }
}
