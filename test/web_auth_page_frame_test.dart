import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/screens/password_recovery_screen.dart';
import 'package:test_app/theme/stroyka_background.dart';
import 'package:test_app/web_app/widgets/web_auth_page_frame.dart';

void main() {
  testWidgets('auth page stays centered and capped on desktop', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: WebAuthPageFrame(
        maxWidth: 640,
        child:
            Scaffold(key: Key('form'), body: ColoredBox(color: Colors.white)),
      ),
    ));

    final form = tester.getRect(find.byKey(const Key('form')));
    expect(form.width, 640);
    expect(form.left, 400);
    expect(form.height, 900);
  });

  testWidgets('auth page shrinks with comfortable side padding',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: WebAuthPageFrame(
        maxWidth: 680,
        child:
            Scaffold(key: Key('form'), body: ColoredBox(color: Colors.white)),
      ),
    ));

    final form = tester.getRect(find.byKey(const Key('form')));
    expect(form.width, 328);
    expect(form.left, 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login backdrop preserves the capped form width', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: WebAuthPageFrame(
        backdrop: WebAuthBackdrop.login,
        child:
            Scaffold(key: Key('form'), body: ColoredBox(color: Colors.white)),
      ),
    ));

    expect(tester.getSize(find.byKey(const Key('form'))).width, 640);
    expect(tester.takeException(), isNull);
  });

  testWidgets('framed recovery paints one full-page backdrop', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: WebAuthPageFrame(
        maxWidth: 600,
        backdrop: WebAuthBackdrop.recovery,
        child: PasswordRecoveryScreen(webFramed: true),
      ),
    ));

    expect(find.byType(StroykaBackground), findsOneWidget);
    expect(tester.getSize(find.byType(PasswordRecoveryScreen)).width, 600);
    expect(tester.takeException(), isNull);
  });
}
