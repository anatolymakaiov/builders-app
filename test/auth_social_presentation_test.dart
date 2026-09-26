import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/social_auth_service.dart';
import 'package:test_app/widgets/mobile_social_auth_buttons.dart';

void main() {
  test('social controls are excluded from Web presentation', () {
    expect(showMobileSocialAuthControls(isWeb: true), isFalse);
    expect(showMobileSocialAuthControls(isWeb: false), isTrue);
  });

  testWidgets('native social buttons retain provider callbacks and labels',
      (tester) async {
    final selected = <SocialProvider>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MobileSocialAuthButtons(onSelected: selected.add),
      ),
    ));

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Facebook'), findsOneWidget);
    expect(find.byIcon(Icons.facebook), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    expect(selected, [SocialProvider.google]);
    await tester.tap(find.text('Continue with Facebook'));
    expect(selected, [SocialProvider.google, SocialProvider.facebook]);
  });

  testWidgets('social labels fit a narrow Mobile auth card', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240,
          child: MobileSocialAuthButtons(onSelected: (_) {}),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('Continue with Facebook'), findsOneWidget);
  });
}
