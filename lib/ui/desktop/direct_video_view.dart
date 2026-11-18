import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The direct video layer: an Android SurfaceView the hardware decoder
/// draws into, shown by Android's compositor itself (hybrid composition),
/// so a new picture does not wait for Flutter to redraw. Touches pass
/// through to the Flutter gesture layer around it.
class DirectVideoView extends StatelessWidget {
  const DirectVideoView({super.key, required this.onSurface});

  /// Called with the decoder id of the layer's Surface once it exists.
  final ValueChanged<int> onSurface;

  static const _viewType = 'multiplex/desktop_surface';

  /// Must match DesktopSurfaceFactory.SURFACE_BASE on the Android side.
  static const _surfaceBase = 1 << 40;

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      onCreatePlatformView: (params) {
        return PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: _viewType,
            layoutDirection: TextDirection.ltr,
            creationParamsCodec: const StandardMessageCodec(),
          )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener((id) => onSurface(_surfaceBase + id))
          ..create();
      },
    );
  }
}
