import 'dart:js_interop';

import 'package:web/web.dart' as web;

void downloadCalendarIcs(String contents, String filename) {
  final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
  final blob = web.Blob(<JSAny>[contents.toJS].toJS,
      web.BlobPropertyBag(type: 'text/calendar;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = safeName;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(
      const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
}
