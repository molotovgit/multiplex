// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'share.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ShareEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ShareEvent()';
}


}

/// @nodoc
class $ShareEventCopyWith<$Res>  {
$ShareEventCopyWith(ShareEvent _, $Res Function(ShareEvent) __);
}


/// Adds pattern-matching-related methods to [ShareEvent].
extension ShareEventPatterns on ShareEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ShareEvent_File value)?  file,TResult Function( ShareEvent_Clip value)?  clip,TResult Function( ShareEvent_Ring value)?  ring,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ShareEvent_File() when file != null:
return file(_that);case ShareEvent_Clip() when clip != null:
return clip(_that);case ShareEvent_Ring() when ring != null:
return ring(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ShareEvent_File value)  file,required TResult Function( ShareEvent_Clip value)  clip,required TResult Function( ShareEvent_Ring value)  ring,}){
final _that = this;
switch (_that) {
case ShareEvent_File():
return file(_that);case ShareEvent_Clip():
return clip(_that);case ShareEvent_Ring():
return ring(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ShareEvent_File value)?  file,TResult? Function( ShareEvent_Clip value)?  clip,TResult? Function( ShareEvent_Ring value)?  ring,}){
final _that = this;
switch (_that) {
case ShareEvent_File() when file != null:
return file(_that);case ShareEvent_Clip() when clip != null:
return clip(_that);case ShareEvent_Ring() when ring != null:
return ring(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  String name,  BigInt size,  String path)?  file,TResult Function( String text)?  clip,TResult Function( int seconds)?  ring,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ShareEvent_File() when file != null:
return file(_that.id,_that.name,_that.size,_that.path);case ShareEvent_Clip() when clip != null:
return clip(_that.text);case ShareEvent_Ring() when ring != null:
return ring(_that.seconds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  String name,  BigInt size,  String path)  file,required TResult Function( String text)  clip,required TResult Function( int seconds)  ring,}) {final _that = this;
switch (_that) {
case ShareEvent_File():
return file(_that.id,_that.name,_that.size,_that.path);case ShareEvent_Clip():
return clip(_that.text);case ShareEvent_Ring():
return ring(_that.seconds);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  String name,  BigInt size,  String path)?  file,TResult? Function( String text)?  clip,TResult? Function( int seconds)?  ring,}) {final _that = this;
switch (_that) {
case ShareEvent_File() when file != null:
return file(_that.id,_that.name,_that.size,_that.path);case ShareEvent_Clip() when clip != null:
return clip(_that.text);case ShareEvent_Ring() when ring != null:
return ring(_that.seconds);case _:
  return null;

}
}

}

/// @nodoc


class ShareEvent_File extends ShareEvent {
  const ShareEvent_File({required this.id, required this.name, required this.size, required this.path}): super._();
  

 final  String id;
 final  String name;
 final  BigInt size;
/// Where it is on the computer, for SFTP.
 final  String path;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareEvent_FileCopyWith<ShareEvent_File> get copyWith => _$ShareEvent_FileCopyWithImpl<ShareEvent_File>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareEvent_File&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.size, size) || other.size == size)&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,size,path);
}

@override
String toString() {
    return 'ShareEvent.file(id: $id, name: $name, size: $size, path: $path)';
}


}

/// @nodoc
abstract mixin class $ShareEvent_FileCopyWith<$Res> implements $ShareEventCopyWith<$Res> {
  factory $ShareEvent_FileCopyWith(ShareEvent_File value, $Res Function(ShareEvent_File) _then) = _$ShareEvent_FileCopyWithImpl;
@useResult
$Res call({
 String id, String name, BigInt size, String path
});




}
/// @nodoc
class _$ShareEvent_FileCopyWithImpl<$Res>
    implements $ShareEvent_FileCopyWith<$Res> {
  _$ShareEvent_FileCopyWithImpl(this._self, this._then);

  final ShareEvent_File _self;
  final $Res Function(ShareEvent_File) _then;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? size = null,Object? path = null,}) {
  return _then(ShareEvent_File(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as BigInt,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShareEvent_Clip extends ShareEvent {
  const ShareEvent_Clip({required this.text}): super._();
  

 final  String text;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareEvent_ClipCopyWith<ShareEvent_Clip> get copyWith => _$ShareEvent_ClipCopyWithImpl<ShareEvent_Clip>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareEvent_Clip&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'ShareEvent.clip(text: $text)';
}


}

/// @nodoc
abstract mixin class $ShareEvent_ClipCopyWith<$Res> implements $ShareEventCopyWith<$Res> {
  factory $ShareEvent_ClipCopyWith(ShareEvent_Clip value, $Res Function(ShareEvent_Clip) _then) = _$ShareEvent_ClipCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$ShareEvent_ClipCopyWithImpl<$Res>
    implements $ShareEvent_ClipCopyWith<$Res> {
  _$ShareEvent_ClipCopyWithImpl(this._self, this._then);

  final ShareEvent_Clip _self;
  final $Res Function(ShareEvent_Clip) _then;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(ShareEvent_Clip(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShareEvent_Ring extends ShareEvent {
  const ShareEvent_Ring({required this.seconds}): super._();
  

 final  int seconds;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareEvent_RingCopyWith<ShareEvent_Ring> get copyWith => _$ShareEvent_RingCopyWithImpl<ShareEvent_Ring>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareEvent_Ring&&(identical(other.seconds, seconds) || other.seconds == seconds));
}


@override
int get hashCode {
    return Object.hash(runtimeType,seconds);
}

@override
String toString() {
    return 'ShareEvent.ring(seconds: $seconds)';
}


}

/// @nodoc
abstract mixin class $ShareEvent_RingCopyWith<$Res> implements $ShareEventCopyWith<$Res> {
  factory $ShareEvent_RingCopyWith(ShareEvent_Ring value, $Res Function(ShareEvent_Ring) _then) = _$ShareEvent_RingCopyWithImpl;
@useResult
$Res call({
 int seconds
});




}
/// @nodoc
class _$ShareEvent_RingCopyWithImpl<$Res>
    implements $ShareEvent_RingCopyWith<$Res> {
  _$ShareEvent_RingCopyWithImpl(this._self, this._then);

  final ShareEvent_Ring _self;
  final $Res Function(ShareEvent_Ring) _then;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? seconds = null,}) {
  return _then(ShareEvent_Ring(
seconds: null == seconds ? _self.seconds : seconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
