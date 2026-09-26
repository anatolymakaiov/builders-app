import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/app/web_auth_gate.dart';

void main() {
  testWidgets('Web entry exposes email login, recovery and registration',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WebLoginPage()));

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Registration'), findsOneWidget);
    expect(find.text('Enter'), findsNothing);
    expect(find.textContaining('Google'), findsNothing);
    expect(find.textContaining('Apple'), findsNothing);
    expect(find.textContaining('Facebook'), findsNothing);
  });
}
