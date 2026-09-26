import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/web_image_service.dart';

void main() {
  test('recognizes case-insensitive HEIC Storage paths', () {
    const url =
        'https://firebasestorage.googleapis.com/v0/b/example/o/chat_attachments%2FPhoto.HEIC?alt=media&token=private';

    expect(WebImageService.detectExtension(url), 'heic');
    expect(
      WebImageService.storagePathFromUrl(url),
      'chat_attachments/Photo.HEIC',
    );
    expect(WebImageService.sanitizeUrl(url), isNot(contains('private')));
  });
}
