import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

class WebMediaPayload {
  const WebMediaPayload({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    required this.originalSizeBytes,
    required this.optimized,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
  final int originalSizeBytes;
  final bool optimized;
}

class WebMediaPipeline {
  static const int maxImageEdge = 1920;
  static const int jpegQuality = 86;
  static const int uploadConcurrency = 3;
  static const String browserCacheControl =
      'private, max-age=31536000, immutable';

  static Future<WebMediaPayload> optimizeImage({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final normalizedType = contentType.trim().toLowerCase();
    final extension = _extension(fileName);
    final isJpeg = normalizedType == 'image/jpeg' ||
        extension == 'jpg' ||
        extension == 'jpeg';
    final isPng = normalizedType == 'image/png' || extension == 'png';
    final original = WebMediaPayload(
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      originalSizeBytes: bytes.length,
      optimized: false,
    );

    // Keep animated, browser-compressed and HEIC/HEIF sources untouched.
    if (!isJpeg && !isPng) return original;

    await Future<void>.delayed(Duration.zero);
    try {
      final decoded = image.decodeImage(bytes);
      if (decoded == null) return original;
      final oriented = image.bakeOrientation(decoded);
      final longestEdge = math.max(oriented.width, oriented.height);
      if (longestEdge <= maxImageEdge) return original;

      final scale = maxImageEdge / longestEdge;
      final resized = image.copyResize(
        oriented,
        width: math.max(1, (oriented.width * scale).round()),
        height: math.max(1, (oriented.height * scale).round()),
        interpolation: image.Interpolation.average,
      );
      final encoded = isPng
          ? image.encodePng(resized, level: 6)
          : image.encodeJpg(resized, quality: jpegQuality);
      if (encoded.length >= bytes.length) return original;

      if (kDebugMode) {
        debugPrint(
          'WEB IMAGE OPTIMIZED file=$fileName '
          'dimensions=${oriented.width}x${oriented.height}->'
          '${resized.width}x${resized.height} '
          'bytes=${bytes.length}->${encoded.length}',
        );
      }
      return WebMediaPayload(
        bytes: encoded,
        fileName: fileName,
        contentType: isPng ? 'image/png' : 'image/jpeg',
        originalSizeBytes: bytes.length,
        optimized: true,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
            'WEB IMAGE OPTIMIZATION SKIPPED file=$fileName error=$error');
      }
      return original;
    }
  }

  static Future<List<R>> mapBounded<T, R>(
    List<T> items,
    Future<R> Function(T item, int index) mapper, {
    int concurrency = uploadConcurrency,
  }) async {
    if (items.isEmpty) return <R>[];
    final results = List<Object?>.filled(items.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < items.length) {
        final index = nextIndex++;
        results[index] = await mapper(items[index], index);
      }
    }

    final workerCount = math.min(math.max(1, concurrency), items.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return List<R>.generate(items.length, (index) => results[index] as R);
  }

  static String _extension(String fileName) {
    final clean = fileName.toLowerCase().split('?').first;
    final dot = clean.lastIndexOf('.');
    return dot < 0 ? '' : clean.substring(dot + 1);
  }
}
