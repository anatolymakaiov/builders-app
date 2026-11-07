import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/widgets/chat_list_avatar_target.dart';

void main() {
  testWidgets('row content opens chat while avatar opens profile only',
      (tester) async {
    var chats = 0;
    var profiles = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InkWell(
          onTap: () => chats++,
          child: Row(
            children: [
              ChatListAvatarTarget(
                onOpenProfile: () => profiles++,
                child: const CircleAvatar(child: Icon(Icons.person)),
              ),
              const Expanded(
                child: Column(
                  children: [
                    Text('Chat title'),
                    Text('Last message preview'),
                    Text('Vacancy'),
                    Text('12:30'),
                    Text('Unread'),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    for (final text in [
      'Chat title',
      'Last message preview',
      'Vacancy',
      '12:30',
      'Unread',
    ]) {
      await tester.tap(find.text(text));
      await tester.pump();
    }
    expect(chats, 5);
    await tester.tap(find.byType(CircleAvatar));
    await tester.pump();
    expect(profiles, 1);
    expect(chats, 5);
  });
}
