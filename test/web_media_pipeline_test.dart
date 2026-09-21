import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:test_app/web_app/services/web_media_pipeline.dart';

void main() {
  test('large JPEG is resized for Web upload', () async {
    final source = image.Image(width: 2200, height: 1100);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(
          x,
          y,
          (x * 17 + y * 3) % 256,
          (x * 5 + y * 11) % 256,
          (x * 7 + y * 13) % 256,
        );
      }
    }
    final original = image.encodeJpg(source, quality: 100);

    final result = await WebMediaPipeline.optimizeImage(
      bytes: original,
      fileName: 'site-photo.jpg',
      contentType: 'image/jpeg',
    );
    final decoded = image.decodeJpg(result.bytes)!;

    expect(result.optimized, isTrue);
    expect(
        math.max(decoded.width, decoded.height), WebMediaPipeline.maxImageEdge);
    expect(result.bytes.length, lessThan(original.length));
    expect(result.contentType, 'image/jpeg');
  });

  test('small image is not recompressed', () async {
    final original = image.encodePng(image.Image(width: 640, height: 480));
    final result = await WebMediaPipeline.optimizeImage(
      bytes: original,
      fileName: 'logo.png',
      contentType: 'image/png',
    );

    expect(result.optimized, isFalse);
    expect(identical(result.bytes, original), isTrue);
  });

  test('five uploads keep order and never exceed three workers', () async {
    var active = 0;
    var peak = 0;
    final result = await WebMediaPipeline.mapBounded<int, int>(
      List<int>.generate(5, (index) => index),
      (value, index) async {
        active++;
        peak = math.max(peak, active);
        await Future<void>.delayed(Duration(milliseconds: (5 - index) * 5));
        active--;
        return value * 10;
      },
    );

    expect(result, [0, 10, 20, 30, 40]);
    expect(peak, 3);
  });
}
