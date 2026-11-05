// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ssh_types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConnectError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ConnectError()';
}


}

/// @nodoc
class $ConnectErrorCopyWith<$Res>  {
$ConnectErrorCopyWith(ConnectError _, $Res Function(ConnectError) __);
}


/// Adds pattern-matching-related methods to [ConnectError].
extension ConnectErrorPatterns on ConnectError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ConnectError_HostKeyUnknown value)?  hostKeyUnknown,TResult Function( ConnectError_HostKeyChanged value)?  hostKeyChanged,TResult Function( ConnectError_AuthFailed value)?  authFailed,TResult Function( ConnectError_KeyNeedsPassphrase value)?  keyNeedsPassphrase,TResult Function( ConnectError_KeyWrongPassphrase value)?  keyWrongPassphrase,TResult Function( ConnectError_KeyUnreadable value)?  keyUnreadable,TResult Function( ConnectError_Network value)?  network,TResult Function( ConnectError_Timeout value)?  timeout,TResult Function( ConnectError_Protocol value)?  protocol,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ConnectError_HostKeyUnknown() when hostKeyUnknown != null:
return hostKeyUnknown(_that);case ConnectError_HostKeyChanged() when hostKeyChanged != null:
return hostKeyChanged(_that);case ConnectError_AuthFailed() when authFailed != null:
return authFailed(_that);case ConnectError_KeyNeedsPassphrase() when keyNeedsPassphrase != null:
return keyNeedsPassphrase(_that);case ConnectError_KeyWrongPassphrase() when keyWrongPassphrase != null:
return keyWrongPassphrase(_that);case ConnectError_KeyUnreadable() when keyUnreadable != null:
return keyUnreadable(_that);case ConnectError_Network() when network != null:
return network(_that);case ConnectError_Timeout() when timeout != null:
return timeout(_that);case ConnectError_Protocol() when protocol != null:
return protocol(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ConnectError_HostKeyUnknown value)  hostKeyUnknown,required TResult Function( ConnectError_HostKeyChanged value)  hostKeyChanged,required TResult Function( ConnectError_AuthFailed value)  authFailed,required TResult Function( ConnectError_KeyNeedsPassphrase value)  keyNeedsPassphrase,required TResult Function( ConnectError_KeyWrongPassphrase value)  keyWrongPassphrase,required TResult Function( ConnectError_KeyUnreadable value)  keyUnreadable,required TResult Function( ConnectError_Network value)  network,required TResult Function( ConnectError_Timeout value)  timeout,required TResult Function( ConnectError_Protocol value)  protocol,}){
final _that = this;
switch (_that) {
case ConnectError_HostKeyUnknown():
return hostKeyUnknown(_that);case ConnectError_HostKeyChanged():
return hostKeyChanged(_that);case ConnectError_AuthFailed():
return authFailed(_that);case ConnectError_KeyNeedsPassphrase():
return keyNeedsPassphrase(_that);case ConnectError_KeyWrongPassphrase():
return keyWrongPassphrase(_that);case ConnectError_KeyUnreadable():
return keyUnreadable(_that);case ConnectError_Network():
return network(_that);case ConnectError_Timeout():
return timeout(_that);case ConnectError_Protocol():
return protocol(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ConnectError_HostKeyUnknown value)?  hostKeyUnknown,TResult? Function( ConnectError_HostKeyChanged value)?  hostKeyChanged,TResult? Function( ConnectError_AuthFailed value)?  authFailed,TResult? Function( ConnectError_KeyNeedsPassphrase value)?  keyNeedsPassphrase,TResult? Function( ConnectError_KeyWrongPassphrase value)?  keyWrongPassphrase,TResult? Function( ConnectError_KeyUnreadable value)?  keyUnreadable,TResult? Function( ConnectError_Network value)?  network,TResult? Function( ConnectError_Timeout value)?  timeout,TResult? Function( ConnectError_Protocol value)?  protocol,}){
final _that = this;
switch (_that) {
case ConnectError_HostKeyUnknown() when hostKeyUnknown != null:
return hostKeyUnknown(_that);case ConnectError_HostKeyChanged() when hostKeyChanged != null:
return hostKeyChanged(_that);case ConnectError_AuthFailed() when authFailed != null:
return authFailed(_that);case ConnectError_KeyNeedsPassphrase() when keyNeedsPassphrase != null:
return keyNeedsPassphrase(_that);case ConnectError_KeyWrongPassphrase() when keyWrongPassphrase != null:
return keyWrongPassphrase(_that);case ConnectError_KeyUnreadable() when keyUnreadable != null:
return keyUnreadable(_that);case ConnectError_Network() when network != null:
return network(_that);case ConnectError_Timeout() when timeout != null:
return timeout(_that);case ConnectError_Protocol() when protocol != null:
return protocol(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String host,  int port,  HostKeyInfo key)?  hostKeyUnknown,TResult Function( String host,  int port,  HostKeyInfo key)?  hostKeyChanged,TResult Function( String host,  List<String> tried,  List<String> serverAccepts)?  authFailed,TResult Function()?  keyNeedsPassphrase,TResult Function()?  keyWrongPassphrase,TResult Function( String reason)?  keyUnreadable,TResult Function( String host,  int port,  String message)?  network,TResult Function()?  timeout,TResult Function( String message)?  protocol,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ConnectError_HostKeyUnknown() when hostKeyUnknown != null:
return hostKeyUnknown(_that.host,_that.port,_that.key);case ConnectError_HostKeyChanged() when hostKeyChanged != null:
return hostKeyChanged(_that.host,_that.port,_that.key);case ConnectError_AuthFailed() when authFailed != null:
return authFailed(_that.host,_that.tried,_that.serverAccepts);case ConnectError_KeyNeedsPassphrase() when keyNeedsPassphrase != null:
return keyNeedsPassphrase();case ConnectError_KeyWrongPassphrase() when keyWrongPassphrase != null:
return keyWrongPassphrase();case ConnectError_KeyUnreadable() when keyUnreadable != null:
return keyUnreadable(_that.reason);case ConnectError_Network() when network != null:
return network(_that.host,_that.port,_that.message);case ConnectError_Timeout() when timeout != null:
return timeout();case ConnectError_Protocol() when protocol != null:
return protocol(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String host,  int port,  HostKeyInfo key)  hostKeyUnknown,required TResult Function( String host,  int port,  HostKeyInfo key)  hostKeyChanged,required TResult Function( String host,  List<String> tried,  List<String> serverAccepts)  authFailed,required TResult Function()  keyNeedsPassphrase,required TResult Function()  keyWrongPassphrase,required TResult Function( String reason)  keyUnreadable,required TResult Function( String host,  int port,  String message)  network,required TResult Function()  timeout,required TResult Function( String message)  protocol,}) {final _that = this;
switch (_that) {
case ConnectError_HostKeyUnknown():
return hostKeyUnknown(_that.host,_that.port,_that.key);case ConnectError_HostKeyChanged():
return hostKeyChanged(_that.host,_that.port,_that.key);case ConnectError_AuthFailed():
return authFailed(_that.host,_that.tried,_that.serverAccepts);case ConnectError_KeyNeedsPassphrase():
return keyNeedsPassphrase();case ConnectError_KeyWrongPassphrase():
return keyWrongPassphrase();case ConnectError_KeyUnreadable():
return keyUnreadable(_that.reason);case ConnectError_Network():
return network(_that.host,_that.port,_that.message);case ConnectError_Timeout():
return timeout();case ConnectError_Protocol():
return protocol(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String host,  int port,  HostKeyInfo key)?  hostKeyUnknown,TResult? Function( String host,  int port,  HostKeyInfo key)?  hostKeyChanged,TResult? Function( String host,  List<String> tried,  List<String> serverAccepts)?  authFailed,TResult? Function()?  keyNeedsPassphrase,TResult? Function()?  keyWrongPassphrase,TResult? Function( String reason)?  keyUnreadable,TResult? Function( String host,  int port,  String message)?  network,TResult? Function()?  timeout,TResult? Function( String message)?  protocol,}) {final _that = this;
switch (_that) {
case ConnectError_HostKeyUnknown() when hostKeyUnknown != null:
return hostKeyUnknown(_that.host,_that.port,_that.key);case ConnectError_HostKeyChanged() when hostKeyChanged != null:
return hostKeyChanged(_that.host,_that.port,_that.key);case ConnectError_AuthFailed() when authFailed != null:
return authFailed(_that.host,_that.tried,_that.serverAccepts);case ConnectError_KeyNeedsPassphrase() when keyNeedsPassphrase != null:
return keyNeedsPassphrase();case ConnectError_KeyWrongPassphrase() when keyWrongPassphrase != null:
return keyWrongPassphrase();case ConnectError_KeyUnreadable() when keyUnreadable != null:
return keyUnreadable(_that.reason);case ConnectError_Network() when network != null:
return network(_that.host,_that.port,_that.message);case ConnectError_Timeout() when timeout != null:
return timeout();case ConnectError_Protocol() when protocol != null:
return protocol(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class ConnectError_HostKeyUnknown extends ConnectError {
  const ConnectError_HostKeyUnknown({required this.host, required this.port, required this.key}): super._();
  

 final  String host;
 final  int port;
 final  HostKeyInfo key;

/// Create a copy of ConnectError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectError_HostKeyUnknownCopyWith<ConnectError_HostKeyUnknown> get copyWith => _$ConnectError_HostKeyUnknownCopyWithImpl<ConnectError_HostKeyUnknown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectError_HostKeyUnknown&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&(identical(other.key, key) || other.key == key));
}


@override
int get hashCode {
    return Object.hash(runtimeType,host,port,key);
}

@override
String toString() {
    return 'ConnectError.hostKeyUnknown(host: $host, port: $port, key: $key)';
}


}

/// @nodoc
abstract mixin class $ConnectError_HostKeyUnknownCopyWith<$Res> implements $ConnectErrorCopyWith<$Res> {
  factory $ConnectError_HostKeyUnknownCopyWith(ConnectError_HostKeyUnknown value, $Res Function(ConnectError_HostKeyUnknown) _then) = _$ConnectError_HostKeyUnknownCopyWithImpl;
@useResult
$Res call({
 String host, int port, HostKeyInfo key
});




}
/// @nodoc
class _$ConnectError_HostKeyUnknownCopyWithImpl<$Res>
    implements $ConnectError_HostKeyUnknownCopyWith<$Res> {
  _$ConnectError_HostKeyUnknownCopyWithImpl(this._self, this._then);

  final ConnectError_HostKeyUnknown _self;
  final $Res Function(ConnectError_HostKeyUnknown) _then;

/// Create a copy of ConnectError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? host = null,Object? port = null,Object? key = null,}) {
  return _then(ConnectError_HostKeyUnknown(
host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as HostKeyInfo,
  ));
}


}

/// @nodoc


class ConnectError_HostKeyChanged extends ConnectError {
  const ConnectError_HostKeyChanged({required this.host, required this.port, required this.key}): super._();
  

 final  String host;
 final  int port;
 final  HostKeyInfo key;

/// Create a copy of ConnectError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectError_HostKeyChangedCopyWith<ConnectError_HostKeyChanged> get copyWith => _$ConnectError_HostKeyChangedCopyWithImpl<ConnectError_HostKeyChanged>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectError_HostKeyChanged&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&(identical(other.key, key) || other.key == key));
}


@override
int get hashCode {
    return Object.hash(runtimeType,host,port,key);
}

@override
String toString() {
    return 'ConnectError.hostKeyChanged(host: $host, port: $port, key: $key)';
}


}

/// @nodoc
abstract mixin class $ConnectError_HostKeyChangedCopyWith<$Res> implements $ConnectErrorCopyWith<$Res> {
  factory $ConnectError_HostKeyChangedCopyWith(ConnectError_HostKeyChanged value, $Res Function(ConnectError_HostKeyChanged) _then) = _$ConnectError_HostKeyChangedCopyWithImpl;
@useResult
$Res call({
 String host, int port, HostKeyInfo key
});




}
/// @nodoc
class _$ConnectError_HostKeyChangedCopyWithImpl<$Res>
    implements $ConnectError_HostKeyChangedCopyWith<$Res> {
  _$ConnectError_HostKeyChangedCopyWithImpl(this._self, this._then);

  final ConnectError_HostKeyChanged _self;
  final $Res Function(ConnectError_HostKeyChanged) _then;

/// Create a copy of ConnectError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? host = null,Object? port = null,Object? key = null,}) {
  return _then(ConnectError_HostKeyChanged(
host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as HostKeyInfo,
  ));
}


}

/// @nodoc


class ConnectError_AuthFailed extends ConnectError {
  const ConnectError_AuthFailed({required this.host, required  List<String> tried, required  List<String> serverAccepts}): _tried = tried,_serverAccepts = serverAccepts,super._();
  

 final  String host;
/// Methods Multiplex tried, such as "publickey" or "password".
 final  List<String> _tried;
/// Methods Multiplex tried, such as "publickey" or "password".
 List<String> get tried {
  if (_tried is EqualUnmodifiableListView) return _tried;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tried);
}

/// Methods the server said it accepts.
 final  List<String> _serverAccepts;
/// Methods the server said it accepts.
 List<String> get serverAccepts {
  if (_serverAccepts is EqualUnmodifiableListView) return _serverAccepts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_serverAccepts);
}


/// Create a copy of ConnectError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectError_AuthFailedCopyWith<ConnectError_AuthFailed> get copyWith => _$ConnectError_AuthFailedCopyWithImpl<ConnectError_AuthFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectError_AuthFailed&&(identical(other.host, host) || other.host == host)&&const DeepCollectionEquality().equals(other.tried, _tried)&&const DeepCollectionEquality().equals(other.serverAccepts, _serverAccepts));
}


@override
int get hashCode {
    return Object.hash(runtimeType,host,const DeepCollectionEquality().hash(_tried),const DeepCollectionEquality().hash(_serverAccepts));
}

@override
String toString() {
    return 'ConnectError.authFailed(host: $host, tried: $tried, serverAccepts: $serverAccepts)';
}


}

/// @nodoc
abstract mixin class $ConnectError_AuthFailedCopyWith<$Res> implements $ConnectErrorCopyWith<$Res> {
  factory $ConnectError_AuthFailedCopyWith(ConnectError_AuthFailed value, $Res Function(ConnectError_AuthFailed) _then) = _$ConnectError_AuthFailedCopyWithImpl;
@useResult
$Res call({
 String host, List<String> tried, List<String> serverAccepts
});




}
/// @nodoc
class _$ConnectError_AuthFailedCopyWithImpl<$Res>
    implements $ConnectError_AuthFailedCopyWith<$Res> {
  _$ConnectError_AuthFailedCopyWithImpl(this._self, this._then);

  final ConnectError_AuthFailed _self;
  final $Res Function(ConnectError_AuthFailed) _then;

/// Create a copy of ConnectError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? host = null,Object? tried = null,Object? serverAccepts = null,}) {
  return _then(ConnectError_AuthFailed(
host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,tried: null == tried ? _self._tried : tried // ignore: cast_nullable_to_non_nullable
as List<String>,serverAccepts: null == serverAccepts ? _self._serverAccepts : serverAccepts // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class ConnectError_KeyNeedsPassphrase extends ConnectError {
  const ConnectError_KeyNeedsPassphrase(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectError_KeyNeedsPassphrase);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ConnectError.keyNeedsPassphrase()';
}


}




/// @nodoc


class ConnectError_KeyWrongPassphrase extends ConnectError {
  const ConnectError_KeyWrongPassphrase(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectError_KeyWrongPassphrase);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ConnectError.keyWrongPassphrase()';
}


}




/// @nodoc


class ConnectError_KeyUnreadable extends ConnectError {
  const ConnectError_KeyUnreadable({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of ConnectError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectError_KeyUnreadableCopyWith<ConnectError_KeyUnreadable> get copyWith => _$ConnectError_KeyUnreadableCopyWithImpl<ConnectError_KeyUnreadable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectError_KeyUnreadable&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}

@override
String toString() {
    return 'ConnectError.keyUnreadable(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $ConnectError_KeyUnreadableCopyWith<$Res> implements $ConnectErrorCopyWith<$Res> {
  factory $ConnectError_KeyUnreadableCopyWith(ConnectError_KeyUnreadable value, $Res Function(ConnectError_KeyUnreadable) _then) = _$ConnectError_KeyUnreadableCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$ConnectError_KeyUnreadableCopyWithImpl<$Res>
    implements $ConnectError_KeyUnreadableCopyWith<$Res> {
  _$ConnectError_KeyUnreadableCopyWithImpl(this._self, this._then);

  final ConnectError_KeyUnreadable _self;
  final $Res Function(ConnectError_KeyUnreadable) _then;

/// Create a copy of ConnectError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(ConnectError_KeyUnreadable(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ConnectError_Network extends ConnectError {
  const ConnectError_Network({required this.host, required this.port, required this.message}): super._();
  

 final  String host;
 final  int port;
 final  String message;

/// Create a copy of ConnectError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectError_NetworkCopyWith<ConnectError_Network> get copyWith => _$ConnectError_NetworkCopyWithImpl<ConnectError_Network>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectError_Network&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,host,port,message);
}

@override
String toString() {
    return 'ConnectError.network(host: $host, port: $port, message: $message)';
}


}

/// @nodoc
abstract mixin class $ConnectError_NetworkCopyWith<$Res> implements $ConnectErrorCopyWith<$Res> {
  factory $ConnectError_NetworkCopyWith(ConnectError_Network value, $Res Function(ConnectError_Network) _then) = _$ConnectError_NetworkCopyWithImpl;
@useResult
$Res call({
 String host, int port, String message
});




}
/// @nodoc
class _$ConnectError_NetworkCopyWithImpl<$Res>
    implements $ConnectError_NetworkCopyWith<$Res> {
  _$ConnectError_NetworkCopyWithImpl(this._self, this._then);

  final ConnectError_Network _self;
  final $Res Function(ConnectError_Network) _then;

/// Create a copy of ConnectError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? host = null,Object? port = null,Object? message = null,}) {
  return _then(ConnectError_Network(
host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ConnectError_Timeout extends ConnectError {
  const ConnectError_Timeout(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectError_Timeout);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ConnectError.timeout()';
}


}




/// @nodoc


class ConnectError_Protocol extends ConnectError {
  const ConnectError_Protocol({required this.message}): super._();
  

 final  String message;

/// Create a copy of ConnectError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectError_ProtocolCopyWith<ConnectError_Protocol> get copyWith => _$ConnectError_ProtocolCopyWithImpl<ConnectError_Protocol>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectError_Protocol&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'ConnectError.protocol(message: $message)';
}


}

/// @nodoc
abstract mixin class $ConnectError_ProtocolCopyWith<$Res> implements $ConnectErrorCopyWith<$Res> {
  factory $ConnectError_ProtocolCopyWith(ConnectError_Protocol value, $Res Function(ConnectError_Protocol) _then) = _$ConnectError_ProtocolCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$ConnectError_ProtocolCopyWithImpl<$Res>
    implements $ConnectError_ProtocolCopyWith<$Res> {
  _$ConnectError_ProtocolCopyWithImpl(this._self, this._then);

  final ConnectError_Protocol _self;
  final $Res Function(ConnectError_Protocol) _then;

/// Create a copy of ConnectError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(ConnectError_Protocol(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
