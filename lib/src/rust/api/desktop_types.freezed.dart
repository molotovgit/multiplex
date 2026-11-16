// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'desktop_types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DesktopEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DesktopEvent()';
}


}

/// @nodoc
class $DesktopEventCopyWith<$Res>  {
$DesktopEventCopyWith(DesktopEvent _, $Res Function(DesktopEvent) __);
}


/// Adds pattern-matching-related methods to [DesktopEvent].
extension DesktopEventPatterns on DesktopEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DesktopEvent_Started value)?  started,TResult Function( DesktopEvent_Stream value)?  stream,TResult Function( DesktopEvent_Picture value)?  picture,TResult Function( DesktopEvent_CursorShape value)?  cursorShape,TResult Function( DesktopEvent_CursorMoved value)?  cursorMoved,TResult Function( DesktopEvent_Clipboard value)?  clipboard,TResult Function( DesktopEvent_Stats value)?  stats,TResult Function( DesktopEvent_Ended value)?  ended,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DesktopEvent_Started() when started != null:
return started(_that);case DesktopEvent_Stream() when stream != null:
return stream(_that);case DesktopEvent_Picture() when picture != null:
return picture(_that);case DesktopEvent_CursorShape() when cursorShape != null:
return cursorShape(_that);case DesktopEvent_CursorMoved() when cursorMoved != null:
return cursorMoved(_that);case DesktopEvent_Clipboard() when clipboard != null:
return clipboard(_that);case DesktopEvent_Stats() when stats != null:
return stats(_that);case DesktopEvent_Ended() when ended != null:
return ended(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DesktopEvent_Started value)  started,required TResult Function( DesktopEvent_Stream value)  stream,required TResult Function( DesktopEvent_Picture value)  picture,required TResult Function( DesktopEvent_CursorShape value)  cursorShape,required TResult Function( DesktopEvent_CursorMoved value)  cursorMoved,required TResult Function( DesktopEvent_Clipboard value)  clipboard,required TResult Function( DesktopEvent_Stats value)  stats,required TResult Function( DesktopEvent_Ended value)  ended,}){
final _that = this;
switch (_that) {
case DesktopEvent_Started():
return started(_that);case DesktopEvent_Stream():
return stream(_that);case DesktopEvent_Picture():
return picture(_that);case DesktopEvent_CursorShape():
return cursorShape(_that);case DesktopEvent_CursorMoved():
return cursorMoved(_that);case DesktopEvent_Clipboard():
return clipboard(_that);case DesktopEvent_Stats():
return stats(_that);case DesktopEvent_Ended():
return ended(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DesktopEvent_Started value)?  started,TResult? Function( DesktopEvent_Stream value)?  stream,TResult? Function( DesktopEvent_Picture value)?  picture,TResult? Function( DesktopEvent_CursorShape value)?  cursorShape,TResult? Function( DesktopEvent_CursorMoved value)?  cursorMoved,TResult? Function( DesktopEvent_Clipboard value)?  clipboard,TResult? Function( DesktopEvent_Stats value)?  stats,TResult? Function( DesktopEvent_Ended value)?  ended,}){
final _that = this;
switch (_that) {
case DesktopEvent_Started() when started != null:
return started(_that);case DesktopEvent_Stream() when stream != null:
return stream(_that);case DesktopEvent_Picture() when picture != null:
return picture(_that);case DesktopEvent_CursorShape() when cursorShape != null:
return cursorShape(_that);case DesktopEvent_CursorMoved() when cursorMoved != null:
return cursorMoved(_that);case DesktopEvent_Clipboard() when clipboard != null:
return clipboard(_that);case DesktopEvent_Stats() when stats != null:
return stats(_that);case DesktopEvent_Ended() when ended != null:
return ended(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( bool fitted,  String output,  List<DesktopOutput> outputs)?  started,TResult Function( int width,  int height,  double scale,  bool hardware)?  stream,TResult Function( int width,  int height,  int visibleWidth,  int visibleHeight)?  picture,TResult Function( int id,  int width,  int height,  int hotX,  int hotY,  Uint8List bgra)?  cursorShape,TResult Function( double x,  double y,  int shapeId,  bool visible)?  cursorMoved,TResult Function( String text)?  clipboard,TResult Function( DesktopStats field0)?  stats,TResult Function( String reason,  bool retryable)?  ended,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DesktopEvent_Started() when started != null:
return started(_that.fitted,_that.output,_that.outputs);case DesktopEvent_Stream() when stream != null:
return stream(_that.width,_that.height,_that.scale,_that.hardware);case DesktopEvent_Picture() when picture != null:
return picture(_that.width,_that.height,_that.visibleWidth,_that.visibleHeight);case DesktopEvent_CursorShape() when cursorShape != null:
return cursorShape(_that.id,_that.width,_that.height,_that.hotX,_that.hotY,_that.bgra);case DesktopEvent_CursorMoved() when cursorMoved != null:
return cursorMoved(_that.x,_that.y,_that.shapeId,_that.visible);case DesktopEvent_Clipboard() when clipboard != null:
return clipboard(_that.text);case DesktopEvent_Stats() when stats != null:
return stats(_that.field0);case DesktopEvent_Ended() when ended != null:
return ended(_that.reason,_that.retryable);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( bool fitted,  String output,  List<DesktopOutput> outputs)  started,required TResult Function( int width,  int height,  double scale,  bool hardware)  stream,required TResult Function( int width,  int height,  int visibleWidth,  int visibleHeight)  picture,required TResult Function( int id,  int width,  int height,  int hotX,  int hotY,  Uint8List bgra)  cursorShape,required TResult Function( double x,  double y,  int shapeId,  bool visible)  cursorMoved,required TResult Function( String text)  clipboard,required TResult Function( DesktopStats field0)  stats,required TResult Function( String reason,  bool retryable)  ended,}) {final _that = this;
switch (_that) {
case DesktopEvent_Started():
return started(_that.fitted,_that.output,_that.outputs);case DesktopEvent_Stream():
return stream(_that.width,_that.height,_that.scale,_that.hardware);case DesktopEvent_Picture():
return picture(_that.width,_that.height,_that.visibleWidth,_that.visibleHeight);case DesktopEvent_CursorShape():
return cursorShape(_that.id,_that.width,_that.height,_that.hotX,_that.hotY,_that.bgra);case DesktopEvent_CursorMoved():
return cursorMoved(_that.x,_that.y,_that.shapeId,_that.visible);case DesktopEvent_Clipboard():
return clipboard(_that.text);case DesktopEvent_Stats():
return stats(_that.field0);case DesktopEvent_Ended():
return ended(_that.reason,_that.retryable);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( bool fitted,  String output,  List<DesktopOutput> outputs)?  started,TResult? Function( int width,  int height,  double scale,  bool hardware)?  stream,TResult? Function( int width,  int height,  int visibleWidth,  int visibleHeight)?  picture,TResult? Function( int id,  int width,  int height,  int hotX,  int hotY,  Uint8List bgra)?  cursorShape,TResult? Function( double x,  double y,  int shapeId,  bool visible)?  cursorMoved,TResult? Function( String text)?  clipboard,TResult? Function( DesktopStats field0)?  stats,TResult? Function( String reason,  bool retryable)?  ended,}) {final _that = this;
switch (_that) {
case DesktopEvent_Started() when started != null:
return started(_that.fitted,_that.output,_that.outputs);case DesktopEvent_Stream() when stream != null:
return stream(_that.width,_that.height,_that.scale,_that.hardware);case DesktopEvent_Picture() when picture != null:
return picture(_that.width,_that.height,_that.visibleWidth,_that.visibleHeight);case DesktopEvent_CursorShape() when cursorShape != null:
return cursorShape(_that.id,_that.width,_that.height,_that.hotX,_that.hotY,_that.bgra);case DesktopEvent_CursorMoved() when cursorMoved != null:
return cursorMoved(_that.x,_that.y,_that.shapeId,_that.visible);case DesktopEvent_Clipboard() when clipboard != null:
return clipboard(_that.text);case DesktopEvent_Stats() when stats != null:
return stats(_that.field0);case DesktopEvent_Ended() when ended != null:
return ended(_that.reason,_that.retryable);case _:
  return null;

}
}

}

/// @nodoc


class DesktopEvent_Started extends DesktopEvent {
  const DesktopEvent_Started({required this.fitted, required this.output, required  List<DesktopOutput> outputs}): _outputs = outputs,super._();
  

/// True when the screen is a private one made for this phone.
 final  bool fitted;
 final  String output;
/// The remote's monitors.
 final  List<DesktopOutput> _outputs;
/// The remote's monitors.
 List<DesktopOutput> get outputs {
  if (_outputs is EqualUnmodifiableListView) return _outputs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_outputs);
}


/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DesktopEvent_StartedCopyWith<DesktopEvent_Started> get copyWith => _$DesktopEvent_StartedCopyWithImpl<DesktopEvent_Started>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopEvent_Started&&(identical(other.fitted, fitted) || other.fitted == fitted)&&(identical(other.output, output) || other.output == output)&&const DeepCollectionEquality().equals(other.outputs, _outputs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,fitted,output,const DeepCollectionEquality().hash(_outputs));
}

@override
String toString() {
    return 'DesktopEvent.started(fitted: $fitted, output: $output, outputs: $outputs)';
}


}

/// @nodoc
abstract mixin class $DesktopEvent_StartedCopyWith<$Res> implements $DesktopEventCopyWith<$Res> {
  factory $DesktopEvent_StartedCopyWith(DesktopEvent_Started value, $Res Function(DesktopEvent_Started) _then) = _$DesktopEvent_StartedCopyWithImpl;
@useResult
$Res call({
 bool fitted, String output, List<DesktopOutput> outputs
});




}
/// @nodoc
class _$DesktopEvent_StartedCopyWithImpl<$Res>
    implements $DesktopEvent_StartedCopyWith<$Res> {
  _$DesktopEvent_StartedCopyWithImpl(this._self, this._then);

  final DesktopEvent_Started _self;
  final $Res Function(DesktopEvent_Started) _then;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? fitted = null,Object? output = null,Object? outputs = null,}) {
  return _then(DesktopEvent_Started(
fitted: null == fitted ? _self.fitted : fitted // ignore: cast_nullable_to_non_nullable
as bool,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as String,outputs: null == outputs ? _self._outputs : outputs // ignore: cast_nullable_to_non_nullable
as List<DesktopOutput>,
  ));
}


}

/// @nodoc


class DesktopEvent_Stream extends DesktopEvent {
  const DesktopEvent_Stream({required this.width, required this.height, required this.scale, required this.hardware}): super._();
  

/// Video size in pixels.
 final  int width;
 final  int height;
/// Remote scale: logical size = video size / scale.
 final  double scale;
/// True when the remote encodes on its graphics card.
 final  bool hardware;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DesktopEvent_StreamCopyWith<DesktopEvent_Stream> get copyWith => _$DesktopEvent_StreamCopyWithImpl<DesktopEvent_Stream>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopEvent_Stream&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.scale, scale) || other.scale == scale)&&(identical(other.hardware, hardware) || other.hardware == hardware));
}


@override
int get hashCode {
    return Object.hash(runtimeType,width,height,scale,hardware);
}

@override
String toString() {
    return 'DesktopEvent.stream(width: $width, height: $height, scale: $scale, hardware: $hardware)';
}


}

/// @nodoc
abstract mixin class $DesktopEvent_StreamCopyWith<$Res> implements $DesktopEventCopyWith<$Res> {
  factory $DesktopEvent_StreamCopyWith(DesktopEvent_Stream value, $Res Function(DesktopEvent_Stream) _then) = _$DesktopEvent_StreamCopyWithImpl;
@useResult
$Res call({
 int width, int height, double scale, bool hardware
});




}
/// @nodoc
class _$DesktopEvent_StreamCopyWithImpl<$Res>
    implements $DesktopEvent_StreamCopyWith<$Res> {
  _$DesktopEvent_StreamCopyWithImpl(this._self, this._then);

  final DesktopEvent_Stream _self;
  final $Res Function(DesktopEvent_Stream) _then;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? width = null,Object? height = null,Object? scale = null,Object? hardware = null,}) {
  return _then(DesktopEvent_Stream(
width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,scale: null == scale ? _self.scale : scale // ignore: cast_nullable_to_non_nullable
as double,hardware: null == hardware ? _self.hardware : hardware // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class DesktopEvent_Picture extends DesktopEvent {
  const DesktopEvent_Picture({required this.width, required this.height, required this.visibleWidth, required this.visibleHeight}): super._();
  

 final  int width;
 final  int height;
 final  int visibleWidth;
 final  int visibleHeight;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DesktopEvent_PictureCopyWith<DesktopEvent_Picture> get copyWith => _$DesktopEvent_PictureCopyWithImpl<DesktopEvent_Picture>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopEvent_Picture&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.visibleWidth, visibleWidth) || other.visibleWidth == visibleWidth)&&(identical(other.visibleHeight, visibleHeight) || other.visibleHeight == visibleHeight));
}


@override
int get hashCode {
    return Object.hash(runtimeType,width,height,visibleWidth,visibleHeight);
}

@override
String toString() {
    return 'DesktopEvent.picture(width: $width, height: $height, visibleWidth: $visibleWidth, visibleHeight: $visibleHeight)';
}


}

/// @nodoc
abstract mixin class $DesktopEvent_PictureCopyWith<$Res> implements $DesktopEventCopyWith<$Res> {
  factory $DesktopEvent_PictureCopyWith(DesktopEvent_Picture value, $Res Function(DesktopEvent_Picture) _then) = _$DesktopEvent_PictureCopyWithImpl;
@useResult
$Res call({
 int width, int height, int visibleWidth, int visibleHeight
});




}
/// @nodoc
class _$DesktopEvent_PictureCopyWithImpl<$Res>
    implements $DesktopEvent_PictureCopyWith<$Res> {
  _$DesktopEvent_PictureCopyWithImpl(this._self, this._then);

  final DesktopEvent_Picture _self;
  final $Res Function(DesktopEvent_Picture) _then;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? width = null,Object? height = null,Object? visibleWidth = null,Object? visibleHeight = null,}) {
  return _then(DesktopEvent_Picture(
width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,visibleWidth: null == visibleWidth ? _self.visibleWidth : visibleWidth // ignore: cast_nullable_to_non_nullable
as int,visibleHeight: null == visibleHeight ? _self.visibleHeight : visibleHeight // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class DesktopEvent_CursorShape extends DesktopEvent {
  const DesktopEvent_CursorShape({required this.id, required this.width, required this.height, required this.hotX, required this.hotY, required this.bgra}): super._();
  

 final  int id;
 final  int width;
 final  int height;
 final  int hotX;
 final  int hotY;
 final  Uint8List bgra;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DesktopEvent_CursorShapeCopyWith<DesktopEvent_CursorShape> get copyWith => _$DesktopEvent_CursorShapeCopyWithImpl<DesktopEvent_CursorShape>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopEvent_CursorShape&&(identical(other.id, id) || other.id == id)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.hotX, hotX) || other.hotX == hotX)&&(identical(other.hotY, hotY) || other.hotY == hotY)&&const DeepCollectionEquality().equals(other.bgra, bgra));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,width,height,hotX,hotY,const DeepCollectionEquality().hash(bgra));
}

@override
String toString() {
    return 'DesktopEvent.cursorShape(id: $id, width: $width, height: $height, hotX: $hotX, hotY: $hotY, bgra: $bgra)';
}


}

/// @nodoc
abstract mixin class $DesktopEvent_CursorShapeCopyWith<$Res> implements $DesktopEventCopyWith<$Res> {
  factory $DesktopEvent_CursorShapeCopyWith(DesktopEvent_CursorShape value, $Res Function(DesktopEvent_CursorShape) _then) = _$DesktopEvent_CursorShapeCopyWithImpl;
@useResult
$Res call({
 int id, int width, int height, int hotX, int hotY, Uint8List bgra
});




}
/// @nodoc
class _$DesktopEvent_CursorShapeCopyWithImpl<$Res>
    implements $DesktopEvent_CursorShapeCopyWith<$Res> {
  _$DesktopEvent_CursorShapeCopyWithImpl(this._self, this._then);

  final DesktopEvent_CursorShape _self;
  final $Res Function(DesktopEvent_CursorShape) _then;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? width = null,Object? height = null,Object? hotX = null,Object? hotY = null,Object? bgra = null,}) {
  return _then(DesktopEvent_CursorShape(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,hotX: null == hotX ? _self.hotX : hotX // ignore: cast_nullable_to_non_nullable
as int,hotY: null == hotY ? _self.hotY : hotY // ignore: cast_nullable_to_non_nullable
as int,bgra: null == bgra ? _self.bgra : bgra // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

/// @nodoc


class DesktopEvent_CursorMoved extends DesktopEvent {
  const DesktopEvent_CursorMoved({required this.x, required this.y, required this.shapeId, required this.visible}): super._();
  

 final  double x;
 final  double y;
 final  int shapeId;
 final  bool visible;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DesktopEvent_CursorMovedCopyWith<DesktopEvent_CursorMoved> get copyWith => _$DesktopEvent_CursorMovedCopyWithImpl<DesktopEvent_CursorMoved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopEvent_CursorMoved&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y)&&(identical(other.shapeId, shapeId) || other.shapeId == shapeId)&&(identical(other.visible, visible) || other.visible == visible));
}


@override
int get hashCode {
    return Object.hash(runtimeType,x,y,shapeId,visible);
}

@override
String toString() {
    return 'DesktopEvent.cursorMoved(x: $x, y: $y, shapeId: $shapeId, visible: $visible)';
}


}

/// @nodoc
abstract mixin class $DesktopEvent_CursorMovedCopyWith<$Res> implements $DesktopEventCopyWith<$Res> {
  factory $DesktopEvent_CursorMovedCopyWith(DesktopEvent_CursorMoved value, $Res Function(DesktopEvent_CursorMoved) _then) = _$DesktopEvent_CursorMovedCopyWithImpl;
@useResult
$Res call({
 double x, double y, int shapeId, bool visible
});




}
/// @nodoc
class _$DesktopEvent_CursorMovedCopyWithImpl<$Res>
    implements $DesktopEvent_CursorMovedCopyWith<$Res> {
  _$DesktopEvent_CursorMovedCopyWithImpl(this._self, this._then);

  final DesktopEvent_CursorMoved _self;
  final $Res Function(DesktopEvent_CursorMoved) _then;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? x = null,Object? y = null,Object? shapeId = null,Object? visible = null,}) {
  return _then(DesktopEvent_CursorMoved(
x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,shapeId: null == shapeId ? _self.shapeId : shapeId // ignore: cast_nullable_to_non_nullable
as int,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class DesktopEvent_Clipboard extends DesktopEvent {
  const DesktopEvent_Clipboard({required this.text}): super._();
  

 final  String text;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DesktopEvent_ClipboardCopyWith<DesktopEvent_Clipboard> get copyWith => _$DesktopEvent_ClipboardCopyWithImpl<DesktopEvent_Clipboard>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopEvent_Clipboard&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'DesktopEvent.clipboard(text: $text)';
}


}

/// @nodoc
abstract mixin class $DesktopEvent_ClipboardCopyWith<$Res> implements $DesktopEventCopyWith<$Res> {
  factory $DesktopEvent_ClipboardCopyWith(DesktopEvent_Clipboard value, $Res Function(DesktopEvent_Clipboard) _then) = _$DesktopEvent_ClipboardCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$DesktopEvent_ClipboardCopyWithImpl<$Res>
    implements $DesktopEvent_ClipboardCopyWith<$Res> {
  _$DesktopEvent_ClipboardCopyWithImpl(this._self, this._then);

  final DesktopEvent_Clipboard _self;
  final $Res Function(DesktopEvent_Clipboard) _then;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(DesktopEvent_Clipboard(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DesktopEvent_Stats extends DesktopEvent {
  const DesktopEvent_Stats(this.field0): super._();
  

 final  DesktopStats field0;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DesktopEvent_StatsCopyWith<DesktopEvent_Stats> get copyWith => _$DesktopEvent_StatsCopyWithImpl<DesktopEvent_Stats>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopEvent_Stats&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'DesktopEvent.stats(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $DesktopEvent_StatsCopyWith<$Res> implements $DesktopEventCopyWith<$Res> {
  factory $DesktopEvent_StatsCopyWith(DesktopEvent_Stats value, $Res Function(DesktopEvent_Stats) _then) = _$DesktopEvent_StatsCopyWithImpl;
@useResult
$Res call({
 DesktopStats field0
});




}
/// @nodoc
class _$DesktopEvent_StatsCopyWithImpl<$Res>
    implements $DesktopEvent_StatsCopyWith<$Res> {
  _$DesktopEvent_StatsCopyWithImpl(this._self, this._then);

  final DesktopEvent_Stats _self;
  final $Res Function(DesktopEvent_Stats) _then;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(DesktopEvent_Stats(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as DesktopStats,
  ));
}


}

/// @nodoc


class DesktopEvent_Ended extends DesktopEvent {
  const DesktopEvent_Ended({required this.reason, required this.retryable}): super._();
  

 final  String reason;
/// True when trying again may work (network trouble, a busy
/// server); false for problems that need fixing first.
 final  bool retryable;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DesktopEvent_EndedCopyWith<DesktopEvent_Ended> get copyWith => _$DesktopEvent_EndedCopyWithImpl<DesktopEvent_Ended>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopEvent_Ended&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason,retryable);
}

@override
String toString() {
    return 'DesktopEvent.ended(reason: $reason, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class $DesktopEvent_EndedCopyWith<$Res> implements $DesktopEventCopyWith<$Res> {
  factory $DesktopEvent_EndedCopyWith(DesktopEvent_Ended value, $Res Function(DesktopEvent_Ended) _then) = _$DesktopEvent_EndedCopyWithImpl;
@useResult
$Res call({
 String reason, bool retryable
});




}
/// @nodoc
class _$DesktopEvent_EndedCopyWithImpl<$Res>
    implements $DesktopEvent_EndedCopyWith<$Res> {
  _$DesktopEvent_EndedCopyWithImpl(this._self, this._then);

  final DesktopEvent_Ended _self;
  final $Res Function(DesktopEvent_Ended) _then;

/// Create a copy of DesktopEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,Object? retryable = null,}) {
  return _then(DesktopEvent_Ended(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$DesktopMode {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopMode);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DesktopMode()';
}


}

/// @nodoc
class $DesktopModeCopyWith<$Res>  {
$DesktopModeCopyWith(DesktopMode _, $Res Function(DesktopMode) __);
}


/// Adds pattern-matching-related methods to [DesktopMode].
extension DesktopModePatterns on DesktopMode {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DesktopMode_Fitted value)?  fitted,TResult Function( DesktopMode_Mirror value)?  mirror,TResult Function( DesktopMode_Output value)?  output,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DesktopMode_Fitted() when fitted != null:
return fitted(_that);case DesktopMode_Mirror() when mirror != null:
return mirror(_that);case DesktopMode_Output() when output != null:
return output(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DesktopMode_Fitted value)  fitted,required TResult Function( DesktopMode_Mirror value)  mirror,required TResult Function( DesktopMode_Output value)  output,}){
final _that = this;
switch (_that) {
case DesktopMode_Fitted():
return fitted(_that);case DesktopMode_Mirror():
return mirror(_that);case DesktopMode_Output():
return output(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DesktopMode_Fitted value)?  fitted,TResult? Function( DesktopMode_Mirror value)?  mirror,TResult? Function( DesktopMode_Output value)?  output,}){
final _that = this;
switch (_that) {
case DesktopMode_Fitted() when fitted != null:
return fitted(_that);case DesktopMode_Mirror() when mirror != null:
return mirror(_that);case DesktopMode_Output() when output != null:
return output(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  fitted,TResult Function()?  mirror,TResult Function( String name)?  output,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DesktopMode_Fitted() when fitted != null:
return fitted();case DesktopMode_Mirror() when mirror != null:
return mirror();case DesktopMode_Output() when output != null:
return output(_that.name);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  fitted,required TResult Function()  mirror,required TResult Function( String name)  output,}) {final _that = this;
switch (_that) {
case DesktopMode_Fitted():
return fitted();case DesktopMode_Mirror():
return mirror();case DesktopMode_Output():
return output(_that.name);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  fitted,TResult? Function()?  mirror,TResult? Function( String name)?  output,}) {final _that = this;
switch (_that) {
case DesktopMode_Fitted() when fitted != null:
return fitted();case DesktopMode_Mirror() when mirror != null:
return mirror();case DesktopMode_Output() when output != null:
return output(_that.name);case _:
  return null;

}
}

}

/// @nodoc


class DesktopMode_Fitted extends DesktopMode {
  const DesktopMode_Fitted(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopMode_Fitted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DesktopMode.fitted()';
}


}




/// @nodoc


class DesktopMode_Mirror extends DesktopMode {
  const DesktopMode_Mirror(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopMode_Mirror);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DesktopMode.mirror()';
}


}




/// @nodoc


class DesktopMode_Output extends DesktopMode {
  const DesktopMode_Output({required this.name}): super._();
  

 final  String name;

/// Create a copy of DesktopMode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DesktopMode_OutputCopyWith<DesktopMode_Output> get copyWith => _$DesktopMode_OutputCopyWithImpl<DesktopMode_Output>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DesktopMode_Output&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'DesktopMode.output(name: $name)';
}


}

/// @nodoc
abstract mixin class $DesktopMode_OutputCopyWith<$Res> implements $DesktopModeCopyWith<$Res> {
  factory $DesktopMode_OutputCopyWith(DesktopMode_Output value, $Res Function(DesktopMode_Output) _then) = _$DesktopMode_OutputCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$DesktopMode_OutputCopyWithImpl<$Res>
    implements $DesktopMode_OutputCopyWith<$Res> {
  _$DesktopMode_OutputCopyWithImpl(this._self, this._then);

  final DesktopMode_Output _self;
  final $Res Function(DesktopMode_Output) _then;

/// Create a copy of DesktopMode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(DesktopMode_Output(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
