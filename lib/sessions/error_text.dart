/// An error from the Rust core as one readable sentence: the core's
/// messages are sentences already, only the wrapper and the backtrace go.
String errorSentence(Object error, {String fallback = 'Something went wrong.'}) {
  var text = '$error';
  final trace = text.indexOf('Stack backtrace');
  if (trace >= 0) text = text.substring(0, trace);
  final wrapped = RegExp(r'^(AnyhowException|Exception)\(').hasMatch(text);
  text = text.replaceFirst(RegExp(r'^(AnyhowException|Exception)[(:]?\s*'), '').trim();
  if (wrapped && text.endsWith(')')) text = text.substring(0, text.length - 1).trim();
  return text.isEmpty ? fallback : text[0].toUpperCase() + text.substring(1);
}
