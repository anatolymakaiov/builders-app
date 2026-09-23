import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/app/web_auth_gate.dart';

void main() {
  testWidgets('Web auth landing offers Enter and Registration', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WebLoginPage()));

    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('Registration'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Enter'));
    await tester.pump();

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Apple ID'), findsOneWidget);
    expect(find.text('Facebook'), findsOneWidget);
  });
}
