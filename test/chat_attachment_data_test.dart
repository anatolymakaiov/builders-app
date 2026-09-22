import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/chat_attachment_data.dart';

void main() {
  const uploadedImage = {
    'type': 'image',
    'url': 'https://storage.example/final-photo.jpg',
    'fileName': 'site.jpg',
    'mimeType': 'image/jpeg',
  };

  test('sender preview uses the final uploaded image URL', () {
    final attachments = chatAttachmentsFromMessage({
      'senderId': 'sender',
      'attachments': [uploadedImage],
    });

    expect(attachments, hasLength(1));
    expect(attachments.single['url'], uploadedImage['url']);
    expect(attachments.single['type'], 'image');
  });

  test('receiver resolves the same final attachment data', () {
    final sender = chatAttachmentsFromMessage({
      'senderId': 'sender',
      'attachments': [uploadedImage],
    });
    final receiver = chatAttachmentsFromMessage({
      'senderId': 'sender',
      'attachments': [uploadedImage],
    });

    expect(receiver, sender);
  });

  test('reopened legacy message resolves its persisted image URL', () {
    final attachments = chatAttachmentsFromMessage({
      'type': 'image',
      'imageUrl': 'https://storage.example/persisted-photo.jpg',
      'mediaUrl': 'https://storage.example/persisted-photo.jpg',
      'fileName': 'persisted.jpg',
    });

    expect(attachments.single['url'],
        'https://storage.example/persisted-photo.jpg');
    expect(attachments.single['fileName'], 'persisted.jpg');
  });

  test('multiple final attachments retain their selection order', () {
    final attachments = chatAttachmentsFromMessage({
      'attachments': [
        uploadedImage,
        {
          'type': 'file',
          'downloadUrl': 'https://storage.example/spec.pdf',
          'name': 'spec.pdf',
          'contentType': 'application/pdf',
        },
      ],
    });

    expect(
        attachments.map((item) => item['fileName']), ['site.jpg', 'spec.pdf']);
    expect(attachments.map((item) => item['type']), ['image', 'file']);
  });

  test('failed attachment without a final URL is not rendered', () {
    final attachments = chatAttachmentsFromMessage({
      'attachments': [
        {'type': 'image', 'fileName': 'failed.jpg', 'localPath': '/tmp/x'},
      ],
    });

    expect(attachments, isEmpty);
  });
}
