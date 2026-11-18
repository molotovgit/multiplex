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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ShareEvent_File value)?  file,TResult Function( ShareEvent_Clip value)?  clip,TResult Function( ShareEvent_Picture value)?  picture,TResult Function( ShareEvent_Ring value)?  ring,TResult Function( ShareEvent_Sms value)?  sms,TResult Function( ShareEvent_Agent value)?  agent,TResult Function( ShareEvent_Settled value)?  settled,TResult Function( ShareEvent_Approve value)?  approve,TResult Function( ShareEvent_Sign value)?  sign,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ShareEvent_File() when file != null:
return file(_that);case ShareEvent_Clip() when clip != null:
return clip(_that);case ShareEvent_Picture() when picture != null:
return picture(_that);case ShareEvent_Ring() when ring != null:
return ring(_that);case ShareEvent_Sms() when sms != null:
return sms(_that);case ShareEvent_Agent() when agent != null:
return agent(_that);case ShareEvent_Settled() when settled != null:
return settled(_that);case ShareEvent_Approve() when approve != null:
return approve(_that);case ShareEvent_Sign() when sign != null:
return sign(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ShareEvent_File value)  file,required TResult Function( ShareEvent_Clip value)  clip,required TResult Function( ShareEvent_Picture value)  picture,required TResult Function( ShareEvent_Ring value)  ring,required TResult Function( ShareEvent_Sms value)  sms,required TResult Function( ShareEvent_Agent value)  agent,required TResult Function( ShareEvent_Settled value)  settled,required TResult Function( ShareEvent_Approve value)  approve,required TResult Function( ShareEvent_Sign value)  sign,}){
final _that = this;
switch (_that) {
case ShareEvent_File():
return file(_that);case ShareEvent_Clip():
return clip(_that);case ShareEvent_Picture():
return picture(_that);case ShareEvent_Ring():
return ring(_that);case ShareEvent_Sms():
return sms(_that);case ShareEvent_Agent():
return agent(_that);case ShareEvent_Settled():
return settled(_that);case ShareEvent_Approve():
return approve(_that);case ShareEvent_Sign():
return sign(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ShareEvent_File value)?  file,TResult? Function( ShareEvent_Clip value)?  clip,TResult? Function( ShareEvent_Picture value)?  picture,TResult? Function( ShareEvent_Ring value)?  ring,TResult? Function( ShareEvent_Sms value)?  sms,TResult? Function( ShareEvent_Agent value)?  agent,TResult? Function( ShareEvent_Settled value)?  settled,TResult? Function( ShareEvent_Approve value)?  approve,TResult? Function( ShareEvent_Sign value)?  sign,}){
final _that = this;
switch (_that) {
case ShareEvent_File() when file != null:
return file(_that);case ShareEvent_Clip() when clip != null:
return clip(_that);case ShareEvent_Picture() when picture != null:
return picture(_that);case ShareEvent_Ring() when ring != null:
return ring(_that);case ShareEvent_Sms() when sms != null:
return sms(_that);case ShareEvent_Agent() when agent != null:
return agent(_that);case ShareEvent_Settled() when settled != null:
return settled(_that);case ShareEvent_Approve() when approve != null:
return approve(_that);case ShareEvent_Sign() when sign != null:
return sign(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  String name,  BigInt size,  String path)?  file,TResult Function( String text)?  clip,TResult Function( String kind,  BigInt size,  String mark)?  picture,TResult Function( int seconds)?  ring,TResult Function( String to,  String text)?  sms,TResult Function( String name,  String title,  String workspace,  bool waiting,  String session,  String pane,  HerdAsked? asked)?  agent,TResult Function( String session,  String pane)?  settled,TResult Function( String id,  String reason,  String challenge)?  approve,TResult Function( String id,  String data)?  sign,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ShareEvent_File() when file != null:
return file(_that.id,_that.name,_that.size,_that.path);case ShareEvent_Clip() when clip != null:
return clip(_that.text);case ShareEvent_Picture() when picture != null:
return picture(_that.kind,_that.size,_that.mark);case ShareEvent_Ring() when ring != null:
return ring(_that.seconds);case ShareEvent_Sms() when sms != null:
return sms(_that.to,_that.text);case ShareEvent_Agent() when agent != null:
return agent(_that.name,_that.title,_that.workspace,_that.waiting,_that.session,_that.pane,_that.asked);case ShareEvent_Settled() when settled != null:
return settled(_that.session,_that.pane);case ShareEvent_Approve() when approve != null:
return approve(_that.id,_that.reason,_that.challenge);case ShareEvent_Sign() when sign != null:
return sign(_that.id,_that.data);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  String name,  BigInt size,  String path)  file,required TResult Function( String text)  clip,required TResult Function( String kind,  BigInt size,  String mark)  picture,required TResult Function( int seconds)  ring,required TResult Function( String to,  String text)  sms,required TResult Function( String name,  String title,  String workspace,  bool waiting,  String session,  String pane,  HerdAsked? asked)  agent,required TResult Function( String session,  String pane)  settled,required TResult Function( String id,  String reason,  String challenge)  approve,required TResult Function( String id,  String data)  sign,}) {final _that = this;
switch (_that) {
case ShareEvent_File():
return file(_that.id,_that.name,_that.size,_that.path);case ShareEvent_Clip():
return clip(_that.text);case ShareEvent_Picture():
return picture(_that.kind,_that.size,_that.mark);case ShareEvent_Ring():
return ring(_that.seconds);case ShareEvent_Sms():
return sms(_that.to,_that.text);case ShareEvent_Agent():
return agent(_that.name,_that.title,_that.workspace,_that.waiting,_that.session,_that.pane,_that.asked);case ShareEvent_Settled():
return settled(_that.session,_that.pane);case ShareEvent_Approve():
return approve(_that.id,_that.reason,_that.challenge);case ShareEvent_Sign():
return sign(_that.id,_that.data);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  String name,  BigInt size,  String path)?  file,TResult? Function( String text)?  clip,TResult? Function( String kind,  BigInt size,  String mark)?  picture,TResult? Function( int seconds)?  ring,TResult? Function( String to,  String text)?  sms,TResult? Function( String name,  String title,  String workspace,  bool waiting,  String session,  String pane,  HerdAsked? asked)?  agent,TResult? Function( String session,  String pane)?  settled,TResult? Function( String id,  String reason,  String challenge)?  approve,TResult? Function( String id,  String data)?  sign,}) {final _that = this;
switch (_that) {
case ShareEvent_File() when file != null:
return file(_that.id,_that.name,_that.size,_that.path);case ShareEvent_Clip() when clip != null:
return clip(_that.text);case ShareEvent_Picture() when picture != null:
return picture(_that.kind,_that.size,_that.mark);case ShareEvent_Ring() when ring != null:
return ring(_that.seconds);case ShareEvent_Sms() when sms != null:
return sms(_that.to,_that.text);case ShareEvent_Agent() when agent != null:
return agent(_that.name,_that.title,_that.workspace,_that.waiting,_that.session,_that.pane,_that.asked);case ShareEvent_Settled() when settled != null:
return settled(_that.session,_that.pane);case ShareEvent_Approve() when approve != null:
return approve(_that.id,_that.reason,_that.challenge);case ShareEvent_Sign() when sign != null:
return sign(_that.id,_that.data);case _:
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


class ShareEvent_Picture extends ShareEvent {
  const ShareEvent_Picture({required this.kind, required this.size, required this.mark}): super._();
  

 final  String kind;
 final  BigInt size;
 final  String mark;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareEvent_PictureCopyWith<ShareEvent_Picture> get copyWith => _$ShareEvent_PictureCopyWithImpl<ShareEvent_Picture>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareEvent_Picture&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.size, size) || other.size == size)&&(identical(other.mark, mark) || other.mark == mark));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,size,mark);
}

@override
String toString() {
    return 'ShareEvent.picture(kind: $kind, size: $size, mark: $mark)';
}


}

/// @nodoc
abstract mixin class $ShareEvent_PictureCopyWith<$Res> implements $ShareEventCopyWith<$Res> {
  factory $ShareEvent_PictureCopyWith(ShareEvent_Picture value, $Res Function(ShareEvent_Picture) _then) = _$ShareEvent_PictureCopyWithImpl;
@useResult
$Res call({
 String kind, BigInt size, String mark
});




}
/// @nodoc
class _$ShareEvent_PictureCopyWithImpl<$Res>
    implements $ShareEvent_PictureCopyWith<$Res> {
  _$ShareEvent_PictureCopyWithImpl(this._self, this._then);

  final ShareEvent_Picture _self;
  final $Res Function(ShareEvent_Picture) _then;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? size = null,Object? mark = null,}) {
  return _then(ShareEvent_Picture(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as BigInt,mark: null == mark ? _self.mark : mark // ignore: cast_nullable_to_non_nullable
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

/// @nodoc


class ShareEvent_Sms extends ShareEvent {
  const ShareEvent_Sms({required this.to, required this.text}): super._();
  

 final  String to;
 final  String text;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareEvent_SmsCopyWith<ShareEvent_Sms> get copyWith => _$ShareEvent_SmsCopyWithImpl<ShareEvent_Sms>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareEvent_Sms&&(identical(other.to, to) || other.to == to)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,to,text);
}

@override
String toString() {
    return 'ShareEvent.sms(to: $to, text: $text)';
}


}

/// @nodoc
abstract mixin class $ShareEvent_SmsCopyWith<$Res> implements $ShareEventCopyWith<$Res> {
  factory $ShareEvent_SmsCopyWith(ShareEvent_Sms value, $Res Function(ShareEvent_Sms) _then) = _$ShareEvent_SmsCopyWithImpl;
@useResult
$Res call({
 String to, String text
});




}
/// @nodoc
class _$ShareEvent_SmsCopyWithImpl<$Res>
    implements $ShareEvent_SmsCopyWith<$Res> {
  _$ShareEvent_SmsCopyWithImpl(this._self, this._then);

  final ShareEvent_Sms _self;
  final $Res Function(ShareEvent_Sms) _then;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? to = null,Object? text = null,}) {
  return _then(ShareEvent_Sms(
to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShareEvent_Agent extends ShareEvent {
  const ShareEvent_Agent({required this.name, required this.title, required this.workspace, required this.waiting, required this.session, required this.pane, this.asked}): super._();
  

 final  String name;
 final  String title;
 final  String workspace;
 final  bool waiting;
 final  String session;
 final  String pane;
 final  HerdAsked? asked;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareEvent_AgentCopyWith<ShareEvent_Agent> get copyWith => _$ShareEvent_AgentCopyWithImpl<ShareEvent_Agent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareEvent_Agent&&(identical(other.name, name) || other.name == name)&&(identical(other.title, title) || other.title == title)&&(identical(other.workspace, workspace) || other.workspace == workspace)&&(identical(other.waiting, waiting) || other.waiting == waiting)&&(identical(other.session, session) || other.session == session)&&(identical(other.pane, pane) || other.pane == pane)&&(identical(other.asked, asked) || other.asked == asked));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,title,workspace,waiting,session,pane,asked);
}

@override
String toString() {
    return 'ShareEvent.agent(name: $name, title: $title, workspace: $workspace, waiting: $waiting, session: $session, pane: $pane, asked: $asked)';
}


}

/// @nodoc
abstract mixin class $ShareEvent_AgentCopyWith<$Res> implements $ShareEventCopyWith<$Res> {
  factory $ShareEvent_AgentCopyWith(ShareEvent_Agent value, $Res Function(ShareEvent_Agent) _then) = _$ShareEvent_AgentCopyWithImpl;
@useResult
$Res call({
 String name, String title, String workspace, bool waiting, String session, String pane, HerdAsked? asked
});




}
/// @nodoc
class _$ShareEvent_AgentCopyWithImpl<$Res>
    implements $ShareEvent_AgentCopyWith<$Res> {
  _$ShareEvent_AgentCopyWithImpl(this._self, this._then);

  final ShareEvent_Agent _self;
  final $Res Function(ShareEvent_Agent) _then;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? title = null,Object? workspace = null,Object? waiting = null,Object? session = null,Object? pane = null,Object? asked = freezed,}) {
  return _then(ShareEvent_Agent(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,workspace: null == workspace ? _self.workspace : workspace // ignore: cast_nullable_to_non_nullable
as String,waiting: null == waiting ? _self.waiting : waiting // ignore: cast_nullable_to_non_nullable
as bool,session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as String,pane: null == pane ? _self.pane : pane // ignore: cast_nullable_to_non_nullable
as String,asked: freezed == asked ? _self.asked : asked // ignore: cast_nullable_to_non_nullable
as HerdAsked?,
  ));
}


}

/// @nodoc


class ShareEvent_Settled extends ShareEvent {
  const ShareEvent_Settled({required this.session, required this.pane}): super._();
  

 final  String session;
 final  String pane;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareEvent_SettledCopyWith<ShareEvent_Settled> get copyWith => _$ShareEvent_SettledCopyWithImpl<ShareEvent_Settled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareEvent_Settled&&(identical(other.session, session) || other.session == session)&&(identical(other.pane, pane) || other.pane == pane));
}


@override
int get hashCode {
    return Object.hash(runtimeType,session,pane);
}

@override
String toString() {
    return 'ShareEvent.settled(session: $session, pane: $pane)';
}


}

/// @nodoc
abstract mixin class $ShareEvent_SettledCopyWith<$Res> implements $ShareEventCopyWith<$Res> {
  factory $ShareEvent_SettledCopyWith(ShareEvent_Settled value, $Res Function(ShareEvent_Settled) _then) = _$ShareEvent_SettledCopyWithImpl;
@useResult
$Res call({
 String session, String pane
});




}
/// @nodoc
class _$ShareEvent_SettledCopyWithImpl<$Res>
    implements $ShareEvent_SettledCopyWith<$Res> {
  _$ShareEvent_SettledCopyWithImpl(this._self, this._then);

  final ShareEvent_Settled _self;
  final $Res Function(ShareEvent_Settled) _then;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? session = null,Object? pane = null,}) {
  return _then(ShareEvent_Settled(
session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as String,pane: null == pane ? _self.pane : pane // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShareEvent_Approve extends ShareEvent {
  const ShareEvent_Approve({required this.id, required this.reason, required this.challenge}): super._();
  

 final  String id;
 final  String reason;
 final  String challenge;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareEvent_ApproveCopyWith<ShareEvent_Approve> get copyWith => _$ShareEvent_ApproveCopyWithImpl<ShareEvent_Approve>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareEvent_Approve&&(identical(other.id, id) || other.id == id)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.challenge, challenge) || other.challenge == challenge));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,reason,challenge);
}

@override
String toString() {
    return 'ShareEvent.approve(id: $id, reason: $reason, challenge: $challenge)';
}


}

/// @nodoc
abstract mixin class $ShareEvent_ApproveCopyWith<$Res> implements $ShareEventCopyWith<$Res> {
  factory $ShareEvent_ApproveCopyWith(ShareEvent_Approve value, $Res Function(ShareEvent_Approve) _then) = _$ShareEvent_ApproveCopyWithImpl;
@useResult
$Res call({
 String id, String reason, String challenge
});




}
/// @nodoc
class _$ShareEvent_ApproveCopyWithImpl<$Res>
    implements $ShareEvent_ApproveCopyWith<$Res> {
  _$ShareEvent_ApproveCopyWithImpl(this._self, this._then);

  final ShareEvent_Approve _self;
  final $Res Function(ShareEvent_Approve) _then;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? reason = null,Object? challenge = null,}) {
  return _then(ShareEvent_Approve(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,challenge: null == challenge ? _self.challenge : challenge // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ShareEvent_Sign extends ShareEvent {
  const ShareEvent_Sign({required this.id, required this.data}): super._();
  

 final  String id;
 final  String data;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareEvent_SignCopyWith<ShareEvent_Sign> get copyWith => _$ShareEvent_SignCopyWithImpl<ShareEvent_Sign>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareEvent_Sign&&(identical(other.id, id) || other.id == id)&&(identical(other.data, data) || other.data == data));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,data);
}

@override
String toString() {
    return 'ShareEvent.sign(id: $id, data: $data)';
}


}

/// @nodoc
abstract mixin class $ShareEvent_SignCopyWith<$Res> implements $ShareEventCopyWith<$Res> {
  factory $ShareEvent_SignCopyWith(ShareEvent_Sign value, $Res Function(ShareEvent_Sign) _then) = _$ShareEvent_SignCopyWithImpl;
@useResult
$Res call({
 String id, String data
});




}
/// @nodoc
class _$ShareEvent_SignCopyWithImpl<$Res>
    implements $ShareEvent_SignCopyWith<$Res> {
  _$ShareEvent_SignCopyWithImpl(this._self, this._then);

  final ShareEvent_Sign _self;
  final $Res Function(ShareEvent_Sign) _then;

/// Create a copy of ShareEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? data = null,}) {
  return _then(ShareEvent_Sign(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
