import 'dart:js_interop';

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(JSString url);

void revokeObjectUrl(String url) => _revokeObjectUrl(url.toJS);
