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
    Object? lastError;
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
        } catch (error) {
          lastError = error;
          // Initial tile requests may be cancelled while the map settles.
          // Retry before failing so the first viewport is not cached blank.
          debugPrint("MAP TILE LOAD FAILED url=$url error=$error");
        }
      }

      await Future<void>.delayed(Duration(milliseconds: 180 * (attempt + 1)));
    }

    throw StateError("Could not load map tile ${key.url}: $lastError");
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
