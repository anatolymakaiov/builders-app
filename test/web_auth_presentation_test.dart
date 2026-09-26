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

  testWidgets('Web login scrolls in a short landscape viewport',
      (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: WebLoginPage()));

    expect(tester.takeException(), isNull);
    expect(find.text('Registration'), findsOneWidget);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getBottomLeft(find.text('Registration')).dy, lessThan(390));
  });
}
