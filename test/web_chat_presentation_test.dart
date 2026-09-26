import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/pages/chats/web_chat_media_widgets.dart';
import 'package:test_app/web_app/pages/chats/web_chat_timeline.dart';
import 'package:test_app/web_app/services/web_chat_media_service.dart';

void main() {
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
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(
        button.style!.backgroundColor!.resolve({}),
        isMine
            ? WebChatMessageColors.outgoingAttachment
            : WebChatMessageColors.incomingAttachment,
      );
    }
  });
}
