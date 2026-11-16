package io.github.molotovgit.multiplex

import android.content.Context
import android.os.Build
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * "Direct video": the remote desktop drawn by the hardware decoder into a
 * SurfaceView of its own. Android's compositor shows each picture by
 * itself, so a new picture does not wait for Flutter to redraw its screen
 * (about one refresh less delay), and the decoder's crop is honoured.
 *
 * Flutter places the view (hybrid composition) and draws the pointer and
 * controls above it. The Surface goes to the Rust decoder exactly like a
 * texture's, under the id [SURFACE_BASE] + the platform view id.
 */
class DesktopSurfaceFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = DesktopSurface(context, viewId)

    companion object {
        const val VIEW_TYPE = "multiplex/desktop_surface"

        /** Keeps platform view ids apart from texture ids. */
        const val SURFACE_BASE = 1L shl 40
    }
}

private class DesktopSurface(context: Context, viewId: Int) : PlatformView, SurfaceHolder.Callback {
    private val id = DesktopSurfaceFactory.SURFACE_BASE + viewId
    private val view = SurfaceView(context).apply { holder.addCallback(this@DesktopSurface) }

    override fun getView(): View = view

    override fun surfaceCreated(holder: SurfaceHolder) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                holder.surface.setFrameRate(120f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
            } catch (_: Exception) {
            }
        }
        DesktopVideo.setSurface(id, holder.surface)
    }

    // The same Surface at another size: the decoder keeps drawing on it.
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        DesktopVideo.setSurface(id, null)
    }

    override fun dispose() {
        DesktopVideo.setSurface(id, null)
    }
}
