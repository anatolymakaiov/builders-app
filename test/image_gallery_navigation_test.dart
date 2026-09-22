import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/chat_image_gallery.dart';
import 'package:test_app/screens/image_gallery_viewer_screen.dart';

void main() {
  test('chat gallery keeps only previewable images in message order', () {
    final message = [
      {'type': 'image', 'url': 'photo-1'},
      {'type': 'file', 'fileName': 'plans.pdf', 'url': 'document'},
      {'type': 'file', 'mimeType': 'image/png', 'url': 'scan'},
      {'type': 'video', 'url': 'video'},
      {'type': 'image', 'url': 'photo-3'},
    ];

    final gallery = ChatImageGallery.fromAttachments(message, 2)!;
    expect(gallery.urls, ['photo-1', 'scan', 'photo-3']);
    expect(gallery.initialIndex, 1);
    expect(ChatImageGallery.fromAttachments(message, 1), isNull);
    expect(ChatImageGallery.fromAttachments(message, 4)!.initialIndex, 2);
  });

  test('a one-image message stays a one-item gallery', () {
    final gallery = ChatImageGallery.fromAttachments([
      {'type': 'image', 'url': 'only-photo'},
    ], 0)!;
    expect(gallery.urls, ['only-photo']);
    expect(gallery.initialIndex, 0);
  });

  testWidgets('viewer opens at selected index, swipes, and closes to caller',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showImageGallery(
              context,
              imageUrls: const ['', '', ''],
              initialIndex: 1,
            ),
            child: const Text('Open gallery'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open gallery'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(650, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Open gallery'), findsOneWidget);
    expect(find.byType(ImageGalleryViewerScreen), findsNothing);
  });

  testWidgets('single image has no position controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ImageGalleryViewerScreen(imageUrls: ['']),
    ));
    expect(find.text('1 / 1'), findsNothing);
  });
}
