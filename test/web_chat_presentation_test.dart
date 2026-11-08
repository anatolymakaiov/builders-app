import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/pages/chats/web_chat_media_widgets.dart';
import 'package:test_app/web_app/pages/chats/web_chats_page.dart';
import 'package:test_app/web_app/pages/chats/web_chat_timeline.dart';
import 'package:test_app/web_app/services/web_chat_media_service.dart';
import 'package:test_app/web_app/services/web_chats_data_service.dart';
import 'package:test_app/web_app/theme/web_theme.dart';

Future<Uint8List> _testImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF4488AA),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  Future<void> showMessage(WidgetTester tester, WebMessageItem message,
      {required bool isMine,
      Size size = const Size(390, 844),
      ImageProvider Function(String)? imageProviderFor,
      Widget Function(WebChatAttachment, double, double)?
          imagePreviewBuilder}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebChatMessageBubble(
            message: message,
            userId: isMine ? 'sender' : 'other',
            sentAt: DateTime(2026, 11, 8, 8, 26),
            onAction: (_) {},
            imageProviderFor: imageProviderFor,
            imagePreviewBuilder: imagePreviewBuilder,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('short outgoing and incoming text only color the compact text',
      (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final isMine in [true, false]) {
      await showMessage(
          tester,
          const WebMessageItem(id: 'short', data: {
            'senderId': 'sender',
            'text': 'fort',
            'type': 'text',
          }),
          isMine: isMine);
      final bubble =
          tester.getRect(find.byKey(const ValueKey('chat-text-bubble:short')));
      final menu = tester.getRect(find.byTooltip('Message actions'));
      final time = tester.getRect(find.text('08:26'));
      expect(bubble.width, lessThan(100));
      expect(menu.bottom, lessThanOrEqualTo(bubble.top));
      expect(time.top, greaterThanOrEqualTo(bubble.bottom));
      expect(bubble.right, isMine ? closeTo(390, 1) : lessThan(100));
      final colored = tester.widget<Container>(
          find.byKey(const ValueKey('chat-text-bubble:short')));
      expect((colored.decoration! as BoxDecoration).color,
          isMine ? WebTheme.accent : WebChatMessageColors.incoming);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('long text wraps with bounded width at Web breakpoints',
      (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const message = WebMessageItem(id: 'long', data: {
      'senderId': 'sender',
      'text':
          'Dryliner in Manchester. Please send the details for this vacancy, including the location and working hours. Thank you very much.',
      'type': 'text',
    });
    for (final width in [390.0, 430.0, 768.0, 1440.0]) {
      await showMessage(tester, message, isMine: true, size: Size(width, 900));
      final bubble =
          tester.getRect(find.byKey(const ValueKey('chat-text-bubble:long')));
      expect(bubble.width, lessThanOrEqualTo(420));
      expect(bubble.height, greaterThan(35));
      expect(tester.getRect(find.text('08:26')).top,
          greaterThanOrEqualTo(bubble.bottom));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('media-only has no text bubble, photo and text remain separate',
      (tester) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const image = {'type': 'image', 'url': 'https://example.com/photo.png'};
    final bytes = (await tester.runAsync(() => _testImage(16, 24)))!;
    Widget preview(WebChatAttachment _, double __, double ___) =>
        const ColoredBox(key: ValueKey('photo-preview'), color: Colors.blue);
    await showMessage(
        tester,
        const WebMessageItem(id: 'media', data: {
          'senderId': 'sender',
          'attachments': [image],
        }),
        isMine: true,
        size: const Size(390, 1000),
        imageProviderFor: (_) => MemoryImage(bytes),
        imagePreviewBuilder: preview);
    expect(find.byKey(const ValueKey('chat-text-bubble:media')), findsNothing);
    expect(find.byTooltip('Message actions'), findsOneWidget);
    expect(find.text('08:26'), findsOneWidget);

    await showMessage(
        tester,
        const WebMessageItem(id: 'mixed', data: {
          'senderId': 'sender',
          'attachments': [image],
          'text': 'Site photo',
        }),
        isMine: true,
        size: const Size(390, 1000),
        imageProviderFor: (_) => MemoryImage(bytes),
        imagePreviewBuilder: preview);
    final photo = tester.getRect(find.byKey(const ValueKey('photo-preview')));
    final bubble =
        tester.getRect(find.byKey(const ValueKey('chat-text-bubble:mixed')));
    final menu = tester.getRect(find.byTooltip('Message actions'));
    final time = tester.getRect(find.text('08:26'));
    expect(photo.bottom, lessThanOrEqualTo(bubble.top));
    expect(bubble.bottom, lessThanOrEqualTo(menu.top));
    expect(menu.bottom, lessThanOrEqualTo(time.top));
    expect(tester.takeException(), isNull);
  });

  test('message keys follow stable IDs when older messages are appended', () {
    const current = WebMessageItem(id: 'current', data: {});
    const previous = WebMessageItem(id: 'previous', data: {});
    const older = WebMessageItem(id: 'older', data: {});
    expect(
        webChatMessageIndexForKey(
            [current, previous], const ValueKey<String>('previous')),
        1);
    expect(
        webChatMessageIndexForKey(
            [older, current, previous], const ValueKey<String>('previous')),
        2);
    expect(
        webChatMessageIndexForKey(
            [older, current, previous], const ValueKey<String>('missing')),
        isNull);
  });

  testWidgets('loaded image stays with its message after older page arrives',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final bytes = (await tester.runAsync(() => _testImage(16, 24)))!;
    final current = [
      const WebMessageItem(id: 'new', data: {}),
      const WebMessageItem(id: 'existing', data: {}),
    ];

    Widget timeline(List<WebMessageItem> messages) => MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: messages.length,
              findChildIndexCallback: (key) =>
                  webChatMessageIndexForKey(messages, key),
              itemBuilder: (context, index) {
                final message = messages[index];
                return SizedBox(
                  key: ValueKey<String>(message.id),
                  height: 400,
                  child: WebChatAttachmentsView(
                    messageId: message.id,
                    attachments: [
                      WebChatAttachment(
                        type: 'image',
                        url: 'https://example.com/${message.id}.png',
                        fileName: '${message.id}.png',
                      ),
                    ],
                    isMine: false,
                    imageProviderFor: (_) => MemoryImage(bytes),
                    imagePreviewBuilder: (item, _, __) => Image.memory(
                      bytes,
                      key: ValueKey<String>(item.fileName),
                    ),
                  ),
                );
              },
            ),
          ),
        );

    await tester.pumpWidget(timeline(current));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('existing.png')), findsOneWidget);
    await tester.pumpWidget(timeline([
      const WebMessageItem(id: 'older', data: {}),
      ...current,
    ]));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('existing.png')), findsOneWidget);
    expect(find.byKey(const ValueKey('older.png')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Web photos have no individual frame and one-pixel spacing',
      (tester) async {
    const images = [
      WebChatAttachment(type: 'image', url: '', fileName: 'one.jpg'),
      WebChatAttachment(type: 'image', url: '', fileName: 'two.jpg'),
    ];
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WebChatAttachmentsView(attachments: images, isMine: true),
      ),
    ));
    final frames = tester.widgetList<Container>(find.byType(Container)).where(
          (widget) =>
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).border?.top.width == 1,
        );
    expect(frames, isEmpty);
    expect(
      tester.getTopLeft(find.byType(InkWell).at(1)).dx -
          tester.getTopRight(find.byType(InkWell).first).dx,
      1,
    );
  });

  testWidgets('Web gallery keeps mixed order and landscape full width',
      (tester) async {
    final portrait = (await tester.runAsync(() => _testImage(10, 20)))!;
    final landscape = (await tester.runAsync(() => _testImage(20, 10)))!;
    final images = [
      for (var index = 0; index < 7; index++)
        WebChatAttachment(
          type: 'image',
          url: 'https://example.com/photo-$index.png',
          fileName: 'photo-$index.png',
        ),
    ];
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
            child: WebChatAttachmentsView(
          attachments: images,
          isMine: false,
          imageProviderFor: (url) => MemoryImage(
            url.contains('photo-2') || url.contains('photo-6')
                ? landscape
                : portrait,
          ),
          imagePreviewBuilder: (attachment, width, height) => ColoredBox(
            key: Key(attachment.fileName),
            color: Colors.blue,
          ),
        )),
      ),
    ));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    final rects = [
      for (var index = 0; index < 7; index++)
        tester.getRect(find.byKey(Key('photo-$index.png'))),
    ];
    expect(rects[0].top, rects[1].top);
    expect(rects[2].width, 390);
    expect(rects[2].top, greaterThan(rects[0].bottom));
    expect(rects[3].top, greaterThan(rects[2].bottom));
    expect(rects[3].top, rects[4].top);
    expect(rects[4].top, rects[5].top);
    expect(rects[6].width, 390);
    expect(rects[6].top, greaterThan(rects[5].bottom));
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(200, 844);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('photo-2.png'))).width, 200);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(768, 844);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('photo-2.png'))).width, 420);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image tiles survive rebuild, resize and conversation switch',
      (tester) async {
    final bytes = (await tester.runAsync(() => _testImage(16, 24)))!;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    Widget gallery(String chatId) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebChatAttachmentsView(
                key: ValueKey(chatId),
                isMine: true,
                attachments: [
                  WebChatAttachment(
                    type: 'image',
                    url: 'https://example.com/$chatId.png',
                    fileName: '$chatId.png',
                  ),
                ],
                imageProviderFor: (_) => MemoryImage(bytes),
                imagePreviewBuilder: (item, width, height) => Image.memory(
                  bytes,
                  key: ValueKey(item.fileName),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(gallery('chat-a'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-a.png')), findsOneWidget);
    await tester.pumpWidget(gallery('chat-a'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-a.png')), findsOneWidget);
    tester.view.physicalSize = const Size(768, 900);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-a.png')), findsOneWidget);
    await tester.pumpWidget(gallery('chat-b'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-b.png')), findsOneWidget);
    await tester.pumpWidget(gallery('chat-a'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-a.png')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('message timestamps use local time and day headings do not repeat', () {
    final utc = DateTime.utc(2026, 9, 26, 15, 7);
    final local = webChatLocalTime(Timestamp.fromDate(utc));
    expect(local, utc.toLocal());
    expect(webChatTimeLabel(local!),
        '${local.hour.toString().padLeft(2, '0')}:07');

    final newest = DateTime(2026, 9, 26, 15);
    final sameDay = DateTime(2026, 9, 26, 9);
    final yesterday = DateTime(2026, 9, 25, 18);
    final older = DateTime(2026, 9, 24, 11);
    expect(
      webChatDateHeadings([newest, sameDay, yesterday, older]),
      [false, true, true, true],
    );
    expect(webChatDateHeadings([newest, null, sameDay]), [false, false, true]);
    expect(webChatDateLabel(newest, now: newest), 'Today');
    expect(webChatDateLabel(yesterday, now: newest), 'Yesterday');
    expect(webChatDateLabel(older, now: newest), '24.9.2026');
  });

  testWidgets('attach menu stays beside its button inside a narrow viewport',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: WebChatAttachMenu(
            enabled: true,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    ));

    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
    final button = tester.getRect(find.byTooltip('Attach'));
    final menu = tester.getRect(find.text('Photo'));
    expect(menu.left, greaterThanOrEqualTo(0));
    expect(menu.right, lessThanOrEqualTo(360));
    expect(menu.top, lessThan(button.top));
    await tester.tap(find.text('Photo'));
    await tester.pumpAndSettle();
    expect(selected, 'photo');
  });

  testWidgets('file, video and voice attachments show message direction',
      (tester) async {
    const file = WebChatAttachment(
      type: 'file',
      url: 'https://example.com/report.pdf',
      fileName: 'report.pdf',
    );
    const video = WebChatAttachment(
      type: 'video',
      url: 'https://example.com/site.mp4',
      fileName: 'site.mp4',
    );
    const voice = WebChatAttachment(
      type: 'audio',
      url: 'https://example.com/voice.m4a',
      fileName: 'voice.m4a',
    );

    Future<void> expectColor(
        WebChatAttachment attachment, bool isMine, Color color) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WebChatAttachmentsView(
            attachments: [attachment],
            isMine: isMine,
          ),
        ),
      ));
      expect(find.text(attachment.fileName), findsOneWidget);
      expect(
        tester.widgetList<Container>(find.byType(Container)).any(
              (widget) =>
                  widget.decoration is BoxDecoration &&
                  (widget.decoration! as BoxDecoration).color == color,
            ),
        isTrue,
      );
    }

    for (final attachment in [file, video]) {
      await expectColor(
          attachment, true, WebChatMessageColors.outgoingAttachment);
      await expectColor(
          attachment, false, WebChatMessageColors.incomingAttachment);
    }

    for (final isMine in [true, false]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WebChatAttachmentsView(
            attachments: const [voice],
            isMine: isMine,
          ),
        ),
      ));
      expect(find.byTooltip('Play voice message'), findsOneWidget);
      expect(
        tester.widgetList<Container>(find.byType(Container)).any(
              (widget) =>
                  widget.decoration is BoxDecoration &&
                  (widget.decoration! as BoxDecoration).color ==
                      (isMine
                          ? WebChatMessageColors.outgoingAttachment
                          : WebChatMessageColors.incomingAttachment),
            ),
        isTrue,
      );
    }
  });

  testWidgets('voice playback failure can be retried and URL change resets it',
      (tester) async {
    const voice = WebChatAttachment(
      type: 'audio',
      url: 'https://example.com/voice.m4a',
      fileName: 'voice.m4a',
    );
    Future<void> showVoice(String url) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WebChatAttachmentsView(
              attachments: [
                WebChatAttachment(
                  type: 'audio',
                  url: url,
                  fileName: voice.fileName,
                )
              ],
              isMine: true,
            ),
          ),
        ));

    await showVoice(voice.url);
    expect(find.text('0:00 / --:--'), findsOneWidget);
    await tester.tap(find.byTooltip('Play voice message'));
    await tester.pump();
    expect(find.text('Voice playback is only available in a browser.'),
        findsOneWidget);
    await showVoice('https://example.com/another.m4a');
    expect(find.text('0:00 / --:--'), findsOneWidget);
  });

  test('legacy Mobile voice URL is available to the Web attachment viewer', () {
    final attachments = normalizeWebChatAttachments({
      'type': 'audio',
      'audioUrl': 'https://example.com/voice.m4a',
    });
    expect(attachments.single.type, 'audio');
    expect(attachments.single.url, 'https://example.com/voice.m4a');
  });

  test('Web accepts current and legacy photo attachment URLs in order', () {
    final attachments = normalizeWebChatAttachments({
      'attachments': [
        {
          'type': 'image',
          'url': 'https://example.com/new.jpg',
          'storagePath': 'chat_attachments/c/m/u/new.jpg',
        },
        {
          'contentType': 'image/jpeg',
          'downloadUrl': 'https://example.com/old.jpg',
          'storagePath': 'chat_attachments/c/m/u/old.jpg',
        },
        {
          'type': 'image',
          'fileUrl': 'https://example.com/older.png',
        },
      ],
    });
    expect(attachments.map((item) => item.url), [
      'https://example.com/new.jpg',
      'https://example.com/old.jpg',
      'https://example.com/older.png',
    ]);
    expect(attachments.map((item) => item.type), everyElement('image'));
    expect(attachments[1].storagePath, 'chat_attachments/c/m/u/old.jpg');
  });

  test('older and current messages normalize through the same read model', () {
    const older = WebMessageItem(id: 'older', data: {
      'type': 'image',
      'mediaUrl': 'https://example.com/historical.jpg',
    });
    const current = WebMessageItem(id: 'current', data: {
      'attachments': [
        {'type': 'image', 'url': 'https://example.com/current.jpg'},
      ],
    });
    expect(older.attachments.single.url, 'https://example.com/historical.jpg');
    expect(current.attachments.single.url, 'https://example.com/current.jpg');
  });

  test('conversation deletion changes only the current user visibility', () {
    final update = webChatHideUpdate('worker-1');
    expect(
        update.keys,
        containsAll([
          'hiddenForUsers',
          'unreadFor',
          'deletedAtForUser.worker-1',
        ]));
    expect(update.keys, isNot(contains('deletedForEveryone')));
    expect(update.keys, isNot(contains('participants')));
  });
}
