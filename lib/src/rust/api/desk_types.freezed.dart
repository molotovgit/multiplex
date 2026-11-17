// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'desk_types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DeskAction {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeskAction()';
}


}

/// @nodoc
class $DeskActionCopyWith<$Res>  {
$DeskActionCopyWith(DeskAction _, $Res Function(DeskAction) __);
}


/// Adds pattern-matching-related methods to [DeskAction].
extension DeskActionPatterns on DeskAction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DeskAction_Workspace value)?  workspace,TResult Function( DeskAction_MoveWindow value)?  moveWindow,TResult Function( DeskAction_FocusMonitor value)?  focusMonitor,TResult Function( DeskAction_Focus value)?  focus,TResult Function( DeskAction_Swap value)?  swap,TResult Function( DeskAction_Close value)?  close,TResult Function( DeskAction_Fullscreen value)?  fullscreen,TResult Function( DeskAction_Float value)?  float,TResult Function( DeskAction_Split value)?  split,TResult Function( DeskAction_PlayPause value)?  playPause,TResult Function( DeskAction_Next value)?  next,TResult Function( DeskAction_Previous value)?  previous,TResult Function( DeskAction_VolumeUp value)?  volumeUp,TResult Function( DeskAction_VolumeDown value)?  volumeDown,TResult Function( DeskAction_Mute value)?  mute,TResult Function( DeskAction_Dnd value)?  dnd,TResult Function( DeskAction_Bind value)?  bind,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DeskAction_Workspace() when workspace != null:
return workspace(_that);case DeskAction_MoveWindow() when moveWindow != null:
return moveWindow(_that);case DeskAction_FocusMonitor() when focusMonitor != null:
return focusMonitor(_that);case DeskAction_Focus() when focus != null:
return focus(_that);case DeskAction_Swap() when swap != null:
return swap(_that);case DeskAction_Close() when close != null:
return close(_that);case DeskAction_Fullscreen() when fullscreen != null:
return fullscreen(_that);case DeskAction_Float() when float != null:
return float(_that);case DeskAction_Split() when split != null:
return split(_that);case DeskAction_PlayPause() when playPause != null:
return playPause(_that);case DeskAction_Next() when next != null:
return next(_that);case DeskAction_Previous() when previous != null:
return previous(_that);case DeskAction_VolumeUp() when volumeUp != null:
return volumeUp(_that);case DeskAction_VolumeDown() when volumeDown != null:
return volumeDown(_that);case DeskAction_Mute() when mute != null:
return mute(_that);case DeskAction_Dnd() when dnd != null:
return dnd(_that);case DeskAction_Bind() when bind != null:
return bind(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DeskAction_Workspace value)  workspace,required TResult Function( DeskAction_MoveWindow value)  moveWindow,required TResult Function( DeskAction_FocusMonitor value)  focusMonitor,required TResult Function( DeskAction_Focus value)  focus,required TResult Function( DeskAction_Swap value)  swap,required TResult Function( DeskAction_Close value)  close,required TResult Function( DeskAction_Fullscreen value)  fullscreen,required TResult Function( DeskAction_Float value)  float,required TResult Function( DeskAction_Split value)  split,required TResult Function( DeskAction_PlayPause value)  playPause,required TResult Function( DeskAction_Next value)  next,required TResult Function( DeskAction_Previous value)  previous,required TResult Function( DeskAction_VolumeUp value)  volumeUp,required TResult Function( DeskAction_VolumeDown value)  volumeDown,required TResult Function( DeskAction_Mute value)  mute,required TResult Function( DeskAction_Dnd value)  dnd,required TResult Function( DeskAction_Bind value)  bind,}){
final _that = this;
switch (_that) {
case DeskAction_Workspace():
return workspace(_that);case DeskAction_MoveWindow():
return moveWindow(_that);case DeskAction_FocusMonitor():
return focusMonitor(_that);case DeskAction_Focus():
return focus(_that);case DeskAction_Swap():
return swap(_that);case DeskAction_Close():
return close(_that);case DeskAction_Fullscreen():
return fullscreen(_that);case DeskAction_Float():
return float(_that);case DeskAction_Split():
return split(_that);case DeskAction_PlayPause():
return playPause(_that);case DeskAction_Next():
return next(_that);case DeskAction_Previous():
return previous(_that);case DeskAction_VolumeUp():
return volumeUp(_that);case DeskAction_VolumeDown():
return volumeDown(_that);case DeskAction_Mute():
return mute(_that);case DeskAction_Dnd():
return dnd(_that);case DeskAction_Bind():
return bind(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DeskAction_Workspace value)?  workspace,TResult? Function( DeskAction_MoveWindow value)?  moveWindow,TResult? Function( DeskAction_FocusMonitor value)?  focusMonitor,TResult? Function( DeskAction_Focus value)?  focus,TResult? Function( DeskAction_Swap value)?  swap,TResult? Function( DeskAction_Close value)?  close,TResult? Function( DeskAction_Fullscreen value)?  fullscreen,TResult? Function( DeskAction_Float value)?  float,TResult? Function( DeskAction_Split value)?  split,TResult? Function( DeskAction_PlayPause value)?  playPause,TResult? Function( DeskAction_Next value)?  next,TResult? Function( DeskAction_Previous value)?  previous,TResult? Function( DeskAction_VolumeUp value)?  volumeUp,TResult? Function( DeskAction_VolumeDown value)?  volumeDown,TResult? Function( DeskAction_Mute value)?  mute,TResult? Function( DeskAction_Dnd value)?  dnd,TResult? Function( DeskAction_Bind value)?  bind,}){
final _that = this;
switch (_that) {
case DeskAction_Workspace() when workspace != null:
return workspace(_that);case DeskAction_MoveWindow() when moveWindow != null:
return moveWindow(_that);case DeskAction_FocusMonitor() when focusMonitor != null:
return focusMonitor(_that);case DeskAction_Focus() when focus != null:
return focus(_that);case DeskAction_Swap() when swap != null:
return swap(_that);case DeskAction_Close() when close != null:
return close(_that);case DeskAction_Fullscreen() when fullscreen != null:
return fullscreen(_that);case DeskAction_Float() when float != null:
return float(_that);case DeskAction_Split() when split != null:
return split(_that);case DeskAction_PlayPause() when playPause != null:
return playPause(_that);case DeskAction_Next() when next != null:
return next(_that);case DeskAction_Previous() when previous != null:
return previous(_that);case DeskAction_VolumeUp() when volumeUp != null:
return volumeUp(_that);case DeskAction_VolumeDown() when volumeDown != null:
return volumeDown(_that);case DeskAction_Mute() when mute != null:
return mute(_that);case DeskAction_Dnd() when dnd != null:
return dnd(_that);case DeskAction_Bind() when bind != null:
return bind(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int slot,  String? monitor)?  workspace,TResult Function( int slot)?  moveWindow,TResult Function( String name)?  focusMonitor,TResult Function( DeskDirection direction)?  focus,TResult Function( DeskDirection direction)?  swap,TResult Function()?  close,TResult Function()?  fullscreen,TResult Function()?  float,TResult Function()?  split,TResult Function()?  playPause,TResult Function()?  next,TResult Function()?  previous,TResult Function()?  volumeUp,TResult Function()?  volumeDown,TResult Function()?  mute,TResult Function( bool enabled)?  dnd,TResult Function( String keys)?  bind,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DeskAction_Workspace() when workspace != null:
return workspace(_that.slot,_that.monitor);case DeskAction_MoveWindow() when moveWindow != null:
return moveWindow(_that.slot);case DeskAction_FocusMonitor() when focusMonitor != null:
return focusMonitor(_that.name);case DeskAction_Focus() when focus != null:
return focus(_that.direction);case DeskAction_Swap() when swap != null:
return swap(_that.direction);case DeskAction_Close() when close != null:
return close();case DeskAction_Fullscreen() when fullscreen != null:
return fullscreen();case DeskAction_Float() when float != null:
return float();case DeskAction_Split() when split != null:
return split();case DeskAction_PlayPause() when playPause != null:
return playPause();case DeskAction_Next() when next != null:
return next();case DeskAction_Previous() when previous != null:
return previous();case DeskAction_VolumeUp() when volumeUp != null:
return volumeUp();case DeskAction_VolumeDown() when volumeDown != null:
return volumeDown();case DeskAction_Mute() when mute != null:
return mute();case DeskAction_Dnd() when dnd != null:
return dnd(_that.enabled);case DeskAction_Bind() when bind != null:
return bind(_that.keys);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int slot,  String? monitor)  workspace,required TResult Function( int slot)  moveWindow,required TResult Function( String name)  focusMonitor,required TResult Function( DeskDirection direction)  focus,required TResult Function( DeskDirection direction)  swap,required TResult Function()  close,required TResult Function()  fullscreen,required TResult Function()  float,required TResult Function()  split,required TResult Function()  playPause,required TResult Function()  next,required TResult Function()  previous,required TResult Function()  volumeUp,required TResult Function()  volumeDown,required TResult Function()  mute,required TResult Function( bool enabled)  dnd,required TResult Function( String keys)  bind,}) {final _that = this;
switch (_that) {
case DeskAction_Workspace():
return workspace(_that.slot,_that.monitor);case DeskAction_MoveWindow():
return moveWindow(_that.slot);case DeskAction_FocusMonitor():
return focusMonitor(_that.name);case DeskAction_Focus():
return focus(_that.direction);case DeskAction_Swap():
return swap(_that.direction);case DeskAction_Close():
return close();case DeskAction_Fullscreen():
return fullscreen();case DeskAction_Float():
return float();case DeskAction_Split():
return split();case DeskAction_PlayPause():
return playPause();case DeskAction_Next():
return next();case DeskAction_Previous():
return previous();case DeskAction_VolumeUp():
return volumeUp();case DeskAction_VolumeDown():
return volumeDown();case DeskAction_Mute():
return mute();case DeskAction_Dnd():
return dnd(_that.enabled);case DeskAction_Bind():
return bind(_that.keys);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int slot,  String? monitor)?  workspace,TResult? Function( int slot)?  moveWindow,TResult? Function( String name)?  focusMonitor,TResult? Function( DeskDirection direction)?  focus,TResult? Function( DeskDirection direction)?  swap,TResult? Function()?  close,TResult? Function()?  fullscreen,TResult? Function()?  float,TResult? Function()?  split,TResult? Function()?  playPause,TResult? Function()?  next,TResult? Function()?  previous,TResult? Function()?  volumeUp,TResult? Function()?  volumeDown,TResult? Function()?  mute,TResult? Function( bool enabled)?  dnd,TResult? Function( String keys)?  bind,}) {final _that = this;
switch (_that) {
case DeskAction_Workspace() when workspace != null:
return workspace(_that.slot,_that.monitor);case DeskAction_MoveWindow() when moveWindow != null:
return moveWindow(_that.slot);case DeskAction_FocusMonitor() when focusMonitor != null:
return focusMonitor(_that.name);case DeskAction_Focus() when focus != null:
return focus(_that.direction);case DeskAction_Swap() when swap != null:
return swap(_that.direction);case DeskAction_Close() when close != null:
return close();case DeskAction_Fullscreen() when fullscreen != null:
return fullscreen();case DeskAction_Float() when float != null:
return float();case DeskAction_Split() when split != null:
return split();case DeskAction_PlayPause() when playPause != null:
return playPause();case DeskAction_Next() when next != null:
return next();case DeskAction_Previous() when previous != null:
return previous();case DeskAction_VolumeUp() when volumeUp != null:
return volumeUp();case DeskAction_VolumeDown() when volumeDown != null:
return volumeDown();case DeskAction_Mute() when mute != null:
return mute();case DeskAction_Dnd() when dnd != null:
return dnd(_that.enabled);case DeskAction_Bind() when bind != null:
return bind(_that.keys);case _:
  return null;

}
}

}

/// @nodoc


class DeskAction_Workspace extends DeskAction {
  const DeskAction_Workspace({required this.slot, this.monitor}): super._();
  

 final  int slot;
 final  String? monitor;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeskAction_WorkspaceCopyWith<DeskAction_Workspace> get copyWith => _$DeskAction_WorkspaceCopyWithImpl<DeskAction_Workspace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_Workspace&&(identical(other.slot, slot) || other.slot == slot)&&(identical(other.monitor, monitor) || other.monitor == monitor));
}


@override
int get hashCode {
    return Object.hash(runtimeType,slot,monitor);
}

@override
String toString() {
    return 'DeskAction.workspace(slot: $slot, monitor: $monitor)';
}


}

/// @nodoc
abstract mixin class $DeskAction_WorkspaceCopyWith<$Res> implements $DeskActionCopyWith<$Res> {
  factory $DeskAction_WorkspaceCopyWith(DeskAction_Workspace value, $Res Function(DeskAction_Workspace) _then) = _$DeskAction_WorkspaceCopyWithImpl;
@useResult
$Res call({
 int slot, String? monitor
});




}
/// @nodoc
class _$DeskAction_WorkspaceCopyWithImpl<$Res>
    implements $DeskAction_WorkspaceCopyWith<$Res> {
  _$DeskAction_WorkspaceCopyWithImpl(this._self, this._then);

  final DeskAction_Workspace _self;
  final $Res Function(DeskAction_Workspace) _then;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? slot = null,Object? monitor = freezed,}) {
  return _then(DeskAction_Workspace(
slot: null == slot ? _self.slot : slot // ignore: cast_nullable_to_non_nullable
as int,monitor: freezed == monitor ? _self.monitor : monitor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class DeskAction_MoveWindow extends DeskAction {
  const DeskAction_MoveWindow({required this.slot}): super._();
  

 final  int slot;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeskAction_MoveWindowCopyWith<DeskAction_MoveWindow> get copyWith => _$DeskAction_MoveWindowCopyWithImpl<DeskAction_MoveWindow>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_MoveWindow&&(identical(other.slot, slot) || other.slot == slot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,slot);
}

@override
String toString() {
    return 'DeskAction.moveWindow(slot: $slot)';
}


}

/// @nodoc
abstract mixin class $DeskAction_MoveWindowCopyWith<$Res> implements $DeskActionCopyWith<$Res> {
  factory $DeskAction_MoveWindowCopyWith(DeskAction_MoveWindow value, $Res Function(DeskAction_MoveWindow) _then) = _$DeskAction_MoveWindowCopyWithImpl;
@useResult
$Res call({
 int slot
});




}
/// @nodoc
class _$DeskAction_MoveWindowCopyWithImpl<$Res>
    implements $DeskAction_MoveWindowCopyWith<$Res> {
  _$DeskAction_MoveWindowCopyWithImpl(this._self, this._then);

  final DeskAction_MoveWindow _self;
  final $Res Function(DeskAction_MoveWindow) _then;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? slot = null,}) {
  return _then(DeskAction_MoveWindow(
slot: null == slot ? _self.slot : slot // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class DeskAction_FocusMonitor extends DeskAction {
  const DeskAction_FocusMonitor({required this.name}): super._();
  

 final  String name;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeskAction_FocusMonitorCopyWith<DeskAction_FocusMonitor> get copyWith => _$DeskAction_FocusMonitorCopyWithImpl<DeskAction_FocusMonitor>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_FocusMonitor&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'DeskAction.focusMonitor(name: $name)';
}


}

/// @nodoc
abstract mixin class $DeskAction_FocusMonitorCopyWith<$Res> implements $DeskActionCopyWith<$Res> {
  factory $DeskAction_FocusMonitorCopyWith(DeskAction_FocusMonitor value, $Res Function(DeskAction_FocusMonitor) _then) = _$DeskAction_FocusMonitorCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$DeskAction_FocusMonitorCopyWithImpl<$Res>
    implements $DeskAction_FocusMonitorCopyWith<$Res> {
  _$DeskAction_FocusMonitorCopyWithImpl(this._self, this._then);

  final DeskAction_FocusMonitor _self;
  final $Res Function(DeskAction_FocusMonitor) _then;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(DeskAction_FocusMonitor(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DeskAction_Focus extends DeskAction {
  const DeskAction_Focus({required this.direction}): super._();
  

 final  DeskDirection direction;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeskAction_FocusCopyWith<DeskAction_Focus> get copyWith => _$DeskAction_FocusCopyWithImpl<DeskAction_Focus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_Focus&&(identical(other.direction, direction) || other.direction == direction));
}


@override
int get hashCode {
    return Object.hash(runtimeType,direction);
}

@override
String toString() {
    return 'DeskAction.focus(direction: $direction)';
}


}

/// @nodoc
abstract mixin class $DeskAction_FocusCopyWith<$Res> implements $DeskActionCopyWith<$Res> {
  factory $DeskAction_FocusCopyWith(DeskAction_Focus value, $Res Function(DeskAction_Focus) _then) = _$DeskAction_FocusCopyWithImpl;
@useResult
$Res call({
 DeskDirection direction
});




}
/// @nodoc
class _$DeskAction_FocusCopyWithImpl<$Res>
    implements $DeskAction_FocusCopyWith<$Res> {
  _$DeskAction_FocusCopyWithImpl(this._self, this._then);

  final DeskAction_Focus _self;
  final $Res Function(DeskAction_Focus) _then;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? direction = null,}) {
  return _then(DeskAction_Focus(
direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as DeskDirection,
  ));
}


}

/// @nodoc


class DeskAction_Swap extends DeskAction {
  const DeskAction_Swap({required this.direction}): super._();
  

 final  DeskDirection direction;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeskAction_SwapCopyWith<DeskAction_Swap> get copyWith => _$DeskAction_SwapCopyWithImpl<DeskAction_Swap>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_Swap&&(identical(other.direction, direction) || other.direction == direction));
}


@override
int get hashCode {
    return Object.hash(runtimeType,direction);
}

@override
String toString() {
    return 'DeskAction.swap(direction: $direction)';
}


}

/// @nodoc
abstract mixin class $DeskAction_SwapCopyWith<$Res> implements $DeskActionCopyWith<$Res> {
  factory $DeskAction_SwapCopyWith(DeskAction_Swap value, $Res Function(DeskAction_Swap) _then) = _$DeskAction_SwapCopyWithImpl;
@useResult
$Res call({
 DeskDirection direction
});




}
/// @nodoc
class _$DeskAction_SwapCopyWithImpl<$Res>
    implements $DeskAction_SwapCopyWith<$Res> {
  _$DeskAction_SwapCopyWithImpl(this._self, this._then);

  final DeskAction_Swap _self;
  final $Res Function(DeskAction_Swap) _then;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? direction = null,}) {
  return _then(DeskAction_Swap(
direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as DeskDirection,
  ));
}


}

/// @nodoc


class DeskAction_Close extends DeskAction {
  const DeskAction_Close(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_Close);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeskAction.close()';
}


}




/// @nodoc


class DeskAction_Fullscreen extends DeskAction {
  const DeskAction_Fullscreen(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_Fullscreen);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeskAction.fullscreen()';
}


}




/// @nodoc


class DeskAction_Float extends DeskAction {
  const DeskAction_Float(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_Float);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeskAction.float()';
}


}




/// @nodoc


class DeskAction_Split extends DeskAction {
  const DeskAction_Split(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_Split);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeskAction.split()';
}


}




/// @nodoc


class DeskAction_PlayPause extends DeskAction {
  const DeskAction_PlayPause(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_PlayPause);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeskAction.playPause()';
}


}




/// @nodoc


class DeskAction_Next extends DeskAction {
  const DeskAction_Next(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_Next);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeskAction.next()';
}


}




/// @nodoc


class DeskAction_Previous extends DeskAction {
  const DeskAction_Previous(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_Previous);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeskAction.previous()';
}


}




/// @nodoc


class DeskAction_VolumeUp extends DeskAction {
  const DeskAction_VolumeUp(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_VolumeUp);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeskAction.volumeUp()';
}


}




/// @nodoc


class DeskAction_VolumeDown extends DeskAction {
  const DeskAction_VolumeDown(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_VolumeDown);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeskAction.volumeDown()';
}


}




/// @nodoc


class DeskAction_Mute extends DeskAction {
  const DeskAction_Mute(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_Mute);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DeskAction.mute()';
}


}




/// @nodoc


class DeskAction_Dnd extends DeskAction {
  const DeskAction_Dnd({required this.enabled}): super._();
  

 final  bool enabled;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeskAction_DndCopyWith<DeskAction_Dnd> get copyWith => _$DeskAction_DndCopyWithImpl<DeskAction_Dnd>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_Dnd&&(identical(other.enabled, enabled) || other.enabled == enabled));
}


@override
int get hashCode {
    return Object.hash(runtimeType,enabled);
}

@override
String toString() {
    return 'DeskAction.dnd(enabled: $enabled)';
}


}

/// @nodoc
abstract mixin class $DeskAction_DndCopyWith<$Res> implements $DeskActionCopyWith<$Res> {
  factory $DeskAction_DndCopyWith(DeskAction_Dnd value, $Res Function(DeskAction_Dnd) _then) = _$DeskAction_DndCopyWithImpl;
@useResult
$Res call({
 bool enabled
});




}
/// @nodoc
class _$DeskAction_DndCopyWithImpl<$Res>
    implements $DeskAction_DndCopyWith<$Res> {
  _$DeskAction_DndCopyWithImpl(this._self, this._then);

  final DeskAction_Dnd _self;
  final $Res Function(DeskAction_Dnd) _then;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? enabled = null,}) {
  return _then(DeskAction_Dnd(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class DeskAction_Bind extends DeskAction {
  const DeskAction_Bind({required this.keys}): super._();
  

 final  String keys;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeskAction_BindCopyWith<DeskAction_Bind> get copyWith => _$DeskAction_BindCopyWithImpl<DeskAction_Bind>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeskAction_Bind&&(identical(other.keys, keys) || other.keys == keys));
}


@override
int get hashCode {
    return Object.hash(runtimeType,keys);
}

@override
String toString() {
    return 'DeskAction.bind(keys: $keys)';
}


}

/// @nodoc
abstract mixin class $DeskAction_BindCopyWith<$Res> implements $DeskActionCopyWith<$Res> {
  factory $DeskAction_BindCopyWith(DeskAction_Bind value, $Res Function(DeskAction_Bind) _then) = _$DeskAction_BindCopyWithImpl;
@useResult
$Res call({
 String keys
});




}
/// @nodoc
class _$DeskAction_BindCopyWithImpl<$Res>
    implements $DeskAction_BindCopyWith<$Res> {
  _$DeskAction_BindCopyWithImpl(this._self, this._then);

  final DeskAction_Bind _self;
  final $Res Function(DeskAction_Bind) _then;

/// Create a copy of DeskAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? keys = null,}) {
  return _then(DeskAction_Bind(
keys: null == keys ? _self.keys : keys // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
