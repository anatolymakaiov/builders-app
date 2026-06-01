import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

class QuietTileProvider extends TileProvider {
  final http.Client _client;

  QuietTileProvider({http.Client? client}) : _client = client ?? http.Client();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _QuietTileImageProvider(
      url: getTileUrl(coordinates, options),
      fallbackUrl: getTileFallbackUrl(coordinates, options),
      headers: headers,
      client: _client,
    );
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

class _QuietTileImageProvider extends ImageProvider<_QuietTileImageProvider> {
  static final Uint8List _transparentPng = Uint8List.fromList(const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  final String url;
  final String? fallbackUrl;
  final Map<String, String> headers;
  final http.Client client;

  const _QuietTileImageProvider({
    required this.url,
    required this.fallbackUrl,
    required this.headers,
    required this.client,
  });

  @override
  ImageStreamCompleter loadImage(
    _QuietTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1,
      debugLabel: url,
    );
  }

  @override
  Future<_QuietTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_QuietTileImageProvider>(this);
  }

  Future<Codec> _loadAsync(
    _QuietTileImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final urls = [
      key.url,
      if (key.fallbackUrl != null && key.fallbackUrl!.isNotEmpty)
        key.fallbackUrl!,
    ];

    for (var attempt = 0; attempt < 3; attempt += 1) {
      for (final url in urls) {
        try {
          final bytes = await client.readBytes(
            Uri.parse(url),
            headers: key.headers,
          );
          return decode(await ImmutableBuffer.fromUint8List(bytes));
        } catch (_) {
          // Initial tile requests may be cancelled while the map settles.
          // Retry before falling back so the first viewport is not cached blank.
        }
      }

      await Future<void>.delayed(Duration(milliseconds: 180 * (attempt + 1)));
    }

    return decode(await ImmutableBuffer.fromUint8List(_transparentPng));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _QuietTileImageProvider &&
          url == other.url &&
          fallbackUrl == other.fallbackUrl;

  @override
  int get hashCode => Object.hash(url, fallbackUrl);
}
