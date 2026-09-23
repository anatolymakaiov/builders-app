import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/screens/login_screen.dart';
import 'package:test_app/services/auth_preferences_service.dart';
import 'package:test_app/services/registration_validation_service.dart';
import 'package:test_app/services/social_auth_service.dart';

void main() {
  testWidgets('biometric cancellation offers password sign-in', (tester) async {
    var openedPassword = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BiometricFallbackDialog(
          result: const BiometricLoginResult(
            success: false,
            message: 'Biometric authentication was cancelled.',
            cancelled: true,
          ),
          onRetry: () {},
          onBack: () {},
          onPassword: () => openedPassword = true,
        ),
      ),
    ));
    expect(find.text('Sign in with email and password'), findsOneWidget);
    await tester.tap(find.text('Sign in with email and password'));
    expect(openedPassword, isTrue);
  });

  testWidgets('unavailable biometric login has the same fallback',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BiometricFallbackDialog(
          result: const BiometricLoginResult(
            success: false,
            message: 'Biometrics are unavailable.',
          ),
          onRetry: () {},
          onBack: () {},
          onPassword: () {},
        ),
      ),
    ));
    expect(find.text('Biometrics are unavailable.'), findsOneWidget);
    expect(find.text('Sign in with email and password'), findsOneWidget);
  });

  test('successful biometric result needs no password fallback', () {
    const result = BiometricLoginResult.success();
    expect(result.success, isTrue);
    expect(result.needsPasswordLogin, isFalse);
  });

  test('provider IDs map only to supported social registration providers', () {
    expect(SocialAuthService.providerFromIds(['google.com']),
        SocialProvider.google);
    expect(
        SocialAuthService.providerFromIds(['apple.com']), SocialProvider.apple);
    expect(SocialAuthService.providerFromIds(['facebook.com']),
        SocialProvider.facebook);
    expect(SocialAuthService.providerFromIds(['password']), isNull);
  });

  test('verified Google-style identity pre-fills only supplied data', () {
    final details = PendingRegistrationDetails.fromSocialIdentity(
      email: 'ALEX@example.com',
      displayName: 'Alex Morgan',
      photoUrl: 'https://example.com/avatar.png',
      verifiedPhoneNumber: null,
      emailVerified: true,
    );
    final data = details.toUserDocument();
    expect(details.firstName, 'Alex');
    expect(details.lastName, 'Morgan');
    expect(details.email, 'alex@example.com');
    expect(data['emailVerified'], isTrue);
    expect(data['phoneVerified'], isFalse);
    expect(data['photo'], 'https://example.com/avatar.png');
    expect(data['profileComplete'], isFalse);
  });

  test('Apple-style missing email and name remain incomplete', () {
    final details = PendingRegistrationDetails.fromSocialIdentity(
      email: null,
      displayName: null,
      photoUrl: null,
      verifiedPhoneNumber: null,
      emailVerified: false,
    );
    final data = details.toUserDocument();
    expect(details.email, isEmpty);
    expect(details.firstName, isEmpty);
    expect(data['emailVerified'], isFalse);
    expect(data['phoneVerified'], isFalse);
    expect(data['profileComplete'], isFalse);
  });

  test('Facebook-style unverified email still requires verification', () {
    final details = PendingRegistrationDetails.fromSocialIdentity(
      email: 'alex@example.com',
      displayName: 'Alex',
      photoUrl: null,
      verifiedPhoneNumber: null,
      emailVerified: false,
    );
    final data = details.toUserDocument();
    expect(details.firstName, 'Alex');
    expect(details.lastName, isEmpty);
    expect(data['emailVerified'], isFalse);
    expect(data['phoneVerified'], isFalse);
  });

  test('only a Firebase-linked phone is treated as verified', () {
    final details = PendingRegistrationDetails.fromSocialIdentity(
      email: 'alex@example.com',
      displayName: 'Alex Morgan',
      photoUrl: null,
      verifiedPhoneNumber: '+447700900123',
      emailVerified: true,
    );
    final data = details.toUserDocument();
    expect(data['phoneVerified'], isTrue);
    expect(data['verifiedNormalizedPhone'], '+447700900123');
  });
}
