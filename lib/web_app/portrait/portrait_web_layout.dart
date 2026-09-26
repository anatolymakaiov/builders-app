import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum WebPresentationMode { desktop, portrait }

WebPresentationMode resolveWebPresentationMode({
  required Size viewport,
  required bool isWeb,
  required Uri uri,
}) {
  if (!isWeb) return WebPresentationMode.desktop;
  switch (uri.queryParameters['layout']?.toLowerCase()) {
    case 'portrait':
      return WebPresentationMode.portrait;
    case 'desktop':
      return WebPresentationMode.desktop;
  }
  return viewport.height > viewport.width
      ? WebPresentationMode.portrait
      : WebPresentationMode.desktop;
}

class WebPresentationDispatcher extends StatelessWidget {
  const WebPresentationDispatcher({
    super.key,
    required this.desktop,
    required this.portrait,
    this.isWeb = kIsWeb,
    this.uri,
  });

  final Widget desktop;
  final Widget portrait;
  final bool isWeb;
  final Uri? uri;

  @override
  Widget build(BuildContext context) {
    final mode = resolveWebPresentationMode(
      viewport: MediaQuery.sizeOf(context),
      isWeb: isWeb,
      uri: uri ?? Uri.base,
    );
    return KeyedSubtree(
      key: ValueKey(mode),
      child: mode == WebPresentationMode.portrait ? portrait : desktop,
    );
  }
}
