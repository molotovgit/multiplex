// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'terminal_types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ShellEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShellEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ShellEvent()';
}


}

/// @nodoc
class $ShellEventCopyWith<$Res>  {
$ShellEventCopyWith(ShellEvent _, $Res Function(ShellEvent) __);
}


/// Adds pattern-matching-related methods to [ShellEvent].
extension ShellEventPatterns on ShellEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ShellEvent_Changed value)?  changed,TResult Function( ShellEvent_Title value)?  title,TResult Function( ShellEvent_Bell value)?  bell,TResult Function( ShellEvent_Clipboard value)?  clipboard,TResult Function( ShellEvent_Exited value)?  exited,TResult Function( ShellEvent_Disconnected value)?  disconnected,TResult Function( ShellEvent_CommandStarted value)?  commandStarted,TResult Function( ShellEvent_CommandFinished value)?  commandFinished,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ShellEvent_Changed() when changed != null:
return changed(_that);case ShellEvent_Title() when title != null:
return title(_that);case ShellEvent_Bell() when bell != null:
return bell(_that);case ShellEvent_Clipboard() when clipboard != null:
return clipboard(_that);case ShellEvent_Exited() when exited != null:
return exited(_that);case ShellEvent_Disconnected() when disconnected != null:
return disconnected(_that);case ShellEvent_CommandStarted() when commandStarted != null:
return commandStarted(_that);case ShellEvent_CommandFinished() when commandFinished != null:
return commandFinished(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ShellEvent_Changed value)  changed,required TResult Function( ShellEvent_Title value)  title,required TResult Function( ShellEvent_Bell value)  bell,required TResult Function( ShellEvent_Clipboard value)  clipboard,required TResult Function( ShellEvent_Exited value)  exited,required TResult Function( ShellEvent_Disconnected value)  disconnected,required TResult Function( ShellEvent_CommandStarted value)  commandStarted,required TResult Function( ShellEvent_CommandFinished value)  commandFinished,}){
final _that = this;
switch (_that) {
case ShellEvent_Changed():
return changed(_that);case ShellEvent_Title():
return title(_that);case ShellEvent_Bell():
return bell(_that);case ShellEvent_Clipboard():
return clipboard(_that);case ShellEvent_Exited():
return exited(_that);case ShellEvent_Disconnected():
return disconnected(_that);case ShellEvent_CommandStarted():
return commandStarted(_that);case ShellEvent_CommandFinished():
return commandFinished(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ShellEvent_Changed value)?  changed,TResult? Function( ShellEvent_Title value)?  title,TResult? Function( ShellEvent_Bell value)?  bell,TResult? Function( ShellEvent_Clipboard value)?  clipboard,TResult? Function( ShellEvent_Exited value)?  exited,TResult? Function( ShellEvent_Disconnected value)?  disconnected,TResult? Function( ShellEvent_CommandStarted value)?  commandStarted,TResult? Function( ShellEvent_CommandFinished value)?  commandFinished,}){
final _that = this;
switch (_that) {
case ShellEvent_Changed() when changed != null:
return changed(_that);case ShellEvent_Title() when title != null:
return title(_that);case ShellEvent_Bell() when bell != null:
return bell(_that);case ShellEvent_Clipboard() when clipboard != null:
return clipboard(_that);case ShellEvent_Exited() when exited != null:
return exited(_that);case ShellEvent_Disconnected() when disconnected != null:
return disconnected(_that);case ShellEvent_CommandStarted() when commandStarted != null:
return commandStarted(_that);case ShellEvent_CommandFinished() when commandFinished != null:
return commandFinished(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  changed,TResult Function( String field0)?  title,TResult Function()?  bell,TResult Function( String field0)?  clipboard,TResult Function( int? code)?  exited,TResult Function()?  disconnected,TResult Function()?  commandStarted,TResult Function( int? exitCode)?  commandFinished,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ShellEvent_Changed() when changed != null:
return changed();case ShellEvent_Title() when title != null:
return title(_that.field0);case ShellEvent_Bell() when bell != null:
return bell();case ShellEvent_Clipboard() when clipboard != null:
return clipboard(_that.field0);case ShellEvent_Exited() when exited != null:
return exited(_that.code);case ShellEvent_Disconnected() when disconnected != null:
return disconnected();case ShellEvent_CommandStarted() when commandStarted != null:
return commandStarted();case ShellEvent_CommandFinished() when commandFinished != null:
return commandFinished(_that.exitCode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  changed,required TResult Function( String field0)  title,required TResult Function()  bell,required TResult Function( String field0)  clipboard,required TResult Function( int? code)  exited,required TResult Function()  disconnected,required TResult Function()  commandStarted,required TResult Function( int? exitCode)  commandFinished,}) {final _that = this;
switch (_that) {
case ShellEvent_Changed():
return changed();case ShellEvent_Title():
return title(_that.field0);case ShellEvent_Bell():
return bell();case ShellEvent_Clipboard():
return clipboard(_that.field0);case ShellEvent_Exited():
return exited(_that.code);case ShellEvent_Disconnected():
return disconnected();case ShellEvent_CommandStarted():
return commandStarted();case ShellEvent_CommandFinished():
return commandFinished(_that.exitCode);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  changed,TResult? Function( String field0)?  title,TResult? Function()?  bell,TResult? Function( String field0)?  clipboard,TResult? Function( int? code)?  exited,TResult? Function()?  disconnected,TResult? Function()?  commandStarted,TResult? Function( int? exitCode)?  commandFinished,}) {final _that = this;
switch (_that) {
case ShellEvent_Changed() when changed != null:
return changed();case ShellEvent_Title() when title != null:
return title(_that.field0);case ShellEvent_Bell() when bell != null:
return bell();case ShellEvent_Clipboard() when clipboard != null:
return clipboard(_that.field0);case ShellEvent_Exited() when exited != null:
return exited(_that.code);case ShellEvent_Disconnected() when disconnected != null:
return disconnected();case ShellEvent_CommandStarted() when commandStarted != null:
return commandStarted();case ShellEvent_CommandFinished() when commandFinished != null:
return commandFinished(_that.exitCode);case _:
  return null;

}
}

}

/// @nodoc


class ShellEvent_Changed extends ShellEvent {
  const ShellEvent_Changed(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShellEvent_Changed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ShellEvent.changed()';
}


}




/// @nodoc


class ShellEvent_Title extends ShellEvent {
  const ShellEvent_Title(this.field0): super._();
  

 final  String field0;

/// Create a copy of ShellEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShellEvent_TitleCopyWith<ShellEvent_Title> get copyWith => _$ShellEvent_TitleCopyWithImpl<ShellEvent_Title>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShellEvent_Title&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ShellEvent.title(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ShellEvent_TitleCopyWith<$Res> implements $ShellEventCopyWith<$Res> {
  factory $ShellEvent_TitleCopyWith(ShellEvent_Title value, $Res Function(ShellEvent_Title) _then) = _$ShellEvent_TitleCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ShellEvent_TitleCopyWithImpl<$Res>
    implements $ShellEvent_TitleCopyWith<$Res> {
  _$ShellEvent_TitleCopyWithImpl(this._self, this._then);

  final ShellEvent_Title _self;
  final $Res Function(ShellEvent_Title) _then;

/// Create a copy of ShellEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ShellEvent_Title(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShellEvent_Bell extends ShellEvent {
  const ShellEvent_Bell(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShellEvent_Bell);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ShellEvent.bell()';
}


}




/// @nodoc


class ShellEvent_Clipboard extends ShellEvent {
  const ShellEvent_Clipboard(this.field0): super._();
  

 final  String field0;

/// Create a copy of ShellEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShellEvent_ClipboardCopyWith<ShellEvent_Clipboard> get copyWith => _$ShellEvent_ClipboardCopyWithImpl<ShellEvent_Clipboard>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShellEvent_Clipboard&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ShellEvent.clipboard(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ShellEvent_ClipboardCopyWith<$Res> implements $ShellEventCopyWith<$Res> {
  factory $ShellEvent_ClipboardCopyWith(ShellEvent_Clipboard value, $Res Function(ShellEvent_Clipboard) _then) = _$ShellEvent_ClipboardCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ShellEvent_ClipboardCopyWithImpl<$Res>
    implements $ShellEvent_ClipboardCopyWith<$Res> {
  _$ShellEvent_ClipboardCopyWithImpl(this._self, this._then);

  final ShellEvent_Clipboard _self;
  final $Res Function(ShellEvent_Clipboard) _then;

/// Create a copy of ShellEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ShellEvent_Clipboard(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShellEvent_Exited extends ShellEvent {
  const ShellEvent_Exited({this.code}): super._();
  

 final  int? code;

/// Create a copy of ShellEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShellEvent_ExitedCopyWith<ShellEvent_Exited> get copyWith => _$ShellEvent_ExitedCopyWithImpl<ShellEvent_Exited>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShellEvent_Exited&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code);
}

@override
String toString() {
    return 'ShellEvent.exited(code: $code)';
}


}

/// @nodoc
abstract mixin class $ShellEvent_ExitedCopyWith<$Res> implements $ShellEventCopyWith<$Res> {
  factory $ShellEvent_ExitedCopyWith(ShellEvent_Exited value, $Res Function(ShellEvent_Exited) _then) = _$ShellEvent_ExitedCopyWithImpl;
@useResult
$Res call({
 int? code
});




}
/// @nodoc
class _$ShellEvent_ExitedCopyWithImpl<$Res>
    implements $ShellEvent_ExitedCopyWith<$Res> {
  _$ShellEvent_ExitedCopyWithImpl(this._self, this._then);

  final ShellEvent_Exited _self;
  final $Res Function(ShellEvent_Exited) _then;

/// Create a copy of ShellEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = freezed,}) {
  return _then(ShellEvent_Exited(
code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class ShellEvent_Disconnected extends ShellEvent {
  const ShellEvent_Disconnected(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShellEvent_Disconnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ShellEvent.disconnected()';
}


}




/// @nodoc


class ShellEvent_CommandStarted extends ShellEvent {
  const ShellEvent_CommandStarted(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShellEvent_CommandStarted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ShellEvent.commandStarted()';
}


}




/// @nodoc


class ShellEvent_CommandFinished extends ShellEvent {
  const ShellEvent_CommandFinished({this.exitCode}): super._();
  

 final  int? exitCode;

/// Create a copy of ShellEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShellEvent_CommandFinishedCopyWith<ShellEvent_CommandFinished> get copyWith => _$ShellEvent_CommandFinishedCopyWithImpl<ShellEvent_CommandFinished>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShellEvent_CommandFinished&&(identical(other.exitCode, exitCode) || other.exitCode == exitCode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,exitCode);
}

@override
String toString() {
    return 'ShellEvent.commandFinished(exitCode: $exitCode)';
}


}

/// @nodoc
abstract mixin class $ShellEvent_CommandFinishedCopyWith<$Res> implements $ShellEventCopyWith<$Res> {
  factory $ShellEvent_CommandFinishedCopyWith(ShellEvent_CommandFinished value, $Res Function(ShellEvent_CommandFinished) _then) = _$ShellEvent_CommandFinishedCopyWithImpl;
@useResult
$Res call({
 int? exitCode
});




}
/// @nodoc
class _$ShellEvent_CommandFinishedCopyWithImpl<$Res>
    implements $ShellEvent_CommandFinishedCopyWith<$Res> {
  _$ShellEvent_CommandFinishedCopyWithImpl(this._self, this._then);

  final ShellEvent_CommandFinished _self;
  final $Res Function(ShellEvent_CommandFinished) _then;

/// Create a copy of ShellEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? exitCode = freezed,}) {
  return _then(ShellEvent_CommandFinished(
exitCode: freezed == exitCode ? _self.exitCode : exitCode // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
