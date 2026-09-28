import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/social_auth_service.dart';
import 'package:test_app/widgets/mobile_social_auth_buttons.dart';

void main() {
  test('social controls are excluded from Web presentation', () {
    expect(showMobileSocialAuthControls(isWeb: true), isFalse);
    expect(showMobileSocialAuthControls(isWeb: false), isTrue);
  });

  testWidgets('compact sign-in icons retain provider callbacks and labels',
      (tester) async {
    final selected = <SocialProvider>[];
    var emailSelected = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MobileSocialAuthButtons(
          onEmail: () => emailSelected = true,
          onSelected: selected.add,
        ),
      ),
    ));

    expect(find.text('Sign in with'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.byTooltip('Sign in with email'), findsOneWidget);
    expect(find.byTooltip('Continue with Google'), findsOneWidget);
    expect(find.byTooltip('Continue with Facebook'), findsOneWidget);
    expect(find.byIcon(Icons.facebook), findsOneWidget);
    await tester.tap(find.byTooltip('Sign in with email'));
    expect(emailSelected, isTrue);
    await tester.tap(find.byTooltip('Continue with Google'));
    expect(selected, [SocialProvider.google]);
    await tester.tap(find.byTooltip('Continue with Facebook'));
    expect(selected, [SocialProvider.google, SocialProvider.facebook]);
    if (SocialAuthService.available(SocialProvider.apple)) {
      expect(find.byTooltip('Continue with Apple'), findsOneWidget);
      await tester.tap(find.byTooltip('Continue with Apple'));
      expect(selected.last, SocialProvider.apple);
    }
  });

  testWidgets('registration icons fit a narrow Mobile auth card',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240,
          child: MobileSocialAuthButtons(
            registration: true,
            onEmail: () {},
            onSelected: (_) {},
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('Register with'), findsOneWidget);
    expect(find.byTooltip('Register with email'), findsOneWidget);
    expect(find.byTooltip('Continue with Facebook'), findsOneWidget);
  });

  testWidgets('disabled provider row does not launch authentication',
      (tester) async {
    var launched = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MobileSocialAuthButtons(
          enabled: false,
          onEmail: () => launched = true,
          onSelected: (_) => launched = true,
        ),
      ),
    ));
    await tester.tap(find.byTooltip('Sign in with email'));
    await tester.tap(find.byTooltip('Continue with Google'));
    expect(launched, isFalse);
  });
}
