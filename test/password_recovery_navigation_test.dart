import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/screens/password_recovery_screen.dart';

void main() {
  testWidgets('recovery Back returns to sign-in without losing email',
      (tester) async {
    final loginEmail = TextEditingController(text: 'worker@example.com');
    addTearDown(loginEmail.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return Column(children: [
            TextField(controller: loginEmail),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PasswordRecoveryScreen(
                  initialEmail: loginEmail.text,
                ),
              )),
              child: const Text('Open recovery'),
            ),
          ]);
        }),
      ),
    ));

    await tester.tap(find.text('Open recovery'));
    await tester.pumpAndSettle();
    expect(find.text('Password recovery'), findsOneWidget);
    expect(find.text('worker@example.com'), findsOneWidget);

    await tester.tap(find.text('SMS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Open recovery'), findsOneWidget);
    expect(loginEmail.text, 'worker@example.com');
  });
}
