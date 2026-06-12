import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

class QuietTileProvider extends TileProvider {
  final http.Client _client;
  bool _disposed = false;

  QuietTileProvider({http.Client? client}) : _client = client ?? http.Client();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _QuietTileImageProvider(
      url: getTileUrl(coordinates, options),
      fallbackUrl: getTileFallbackUrl(coordinates, options),
      headers: headers,
      client: _client,
      isDisposed: () => _disposed,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}

class _QuietTileImageProvider extends ImageProvider<_QuietTileImageProvider> {
  final String url;
  final String? fallbackUrl;
  final Map<String, String> headers;
  final http.Client client;
  final bool Function() isDisposed;

  const _QuietTileImageProvider({
    required this.url,
    required this.fallbackUrl,
    required this.headers,
    required this.client,
    required this.isDisposed,
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
    if (key.isDisposed()) {
      return _decodeTransparentTile(decode);
    }

    Object? lastError;
    final urls = [
      key.url,
      if (key.fallbackUrl != null && key.fallbackUrl!.isNotEmpty)
        key.fallbackUrl!,
    ];

    for (var attempt = 0; attempt < 3; attempt += 1) {
      for (final url in urls) {
        try {
          if (key.isDisposed()) {
            return _decodeTransparentTile(decode);
          }

          final bytes = await client.readBytes(
            Uri.parse(url),
            headers: key.headers,
          );
          return decode(await ImmutableBuffer.fromUint8List(bytes));
        } catch (error) {
          lastError = error;
          if (key.isDisposed() || error.toString().contains("already closed")) {
            return _decodeTransparentTile(decode);
          }
          // Initial tile requests may be cancelled while the map settles.
          // Retry before failing so the first viewport is not cached blank.
          debugPrint("MAP TILE LOAD FAILED url=$url error=$error");
        }
      }

      await Future<void>.delayed(Duration(milliseconds: 180 * (attempt + 1)));
    }

    throw StateError("Could not load map tile ${key.url}: $lastError");
  }

  Future<Codec> _decodeTransparentTile(ImageDecoderCallback decode) async {
    return decode(await awaitImmutableTransparentTile());
  }

  Future<ImmutableBuffer> awaitImmutableTransparentTile() {
    return ImmutableBuffer.fromUint8List(Uint8List.fromList(_transparentPng));
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

const List<int> _transparentPng = [
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
];
