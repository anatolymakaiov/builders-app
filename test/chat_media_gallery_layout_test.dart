import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/chat_media_gallery_layout.dart';
import 'package:test_app/widgets/mobile_chat_media_gallery.dart';

void main() {
  const portrait = ChatMediaTileKind.portrait;
  const landscape = ChatMediaTileKind.landscape;

  test('portrait runs use at most three columns', () {
    for (final count in [1, 2, 3, 4, 6, 15]) {
      final rows = ChatMediaGalleryLayout.rows(List.filled(count, portrait));
      expect(rows.expand((row) => row), List.generate(count, (index) => index));
      expect(rows.every((row) => row.length <= 3), isTrue);
    }
    expect(ChatMediaGalleryLayout.rows(List.filled(4, portrait)), [
      [0, 1, 2],
      [3],
    ]);
  });

  test('landscapes flush portrait rows without reordering', () {
    expect(ChatMediaGalleryLayout.rows([landscape]), [
      [0]
    ]);
    expect(ChatMediaGalleryLayout.rows([landscape, landscape]), [
      [0],
      [1]
    ]);
    expect(
      ChatMediaGalleryLayout.rows([
        portrait,
        portrait,
        landscape,
        portrait,
        portrait,
        portrait,
        landscape,
      ]),
      [
        [0, 1],
        [2],
        [3, 4, 5],
        [6]
      ],
    );
  });

  testWidgets('mixed gallery uses full-width landscape and no overflow',
      (tester) async {
    final dimensions = [
      (600, 900),
      (600, 900),
      (900, 600),
      (600, 900),
      (600, 900),
      (600, 900),
      (900, 600),
    ];
    final attachments = [
      for (var index = 0; index < dimensions.length; index++)
        {
          'type': 'image',
          'url': 'https://example.com/$index.jpg',
          'width': dimensions[index].$1,
          'height': dimensions[index].$2,
        },
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240,
          child: MobileChatMediaGallery(
            attachments: attachments,
            itemBuilder: (index, width, height) => ColoredBox(
              key: Key('image-$index'),
              color: Colors.blue,
            ),
          ),
        ),
      ),
    ));
    final p1 = tester.getRect(find.byKey(const Key('image-0')));
    final p2 = tester.getRect(find.byKey(const Key('image-1')));
    final l1 = tester.getRect(find.byKey(const Key('image-2')));
    final p3 = tester.getRect(find.byKey(const Key('image-3')));
    final l2 = tester.getRect(find.byKey(const Key('image-6')));
    expect(p1.top, p2.top);
    expect(l1.top, greaterThan(p1.bottom));
    expect(l1.width, 240);
    expect(p3.top, greaterThan(l1.bottom));
    expect(l2.width, 240);
    expect(l2.top, greaterThan(p3.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('caption follows the whole gallery', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MobileChatMediaThenText(
          media: SizedBox(key: Key('gallery'), width: 200, height: 100),
          text: Text('Caption below photos'),
        ),
      ),
    ));
    expect(tester.getBottomLeft(find.byKey(const Key('gallery'))).dy,
        lessThan(tester.getTopLeft(find.text('Caption below photos')).dy));
  });
}
