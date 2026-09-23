import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/social_auth_service.dart';

void main() {
  test('provider cancellation does not become a login error', () {
    expect(SocialAuthService.isCancellation('popup-closed-by-user'), isTrue);
    expect(SocialAuthService.isCancellation('cancelled'), isTrue);
    expect(SocialAuthService.isCancellation('wrong-password'), isFalse);
  });

  test('email collision presents existing-account guidance', () {
    final error = FirebaseAuthException(
      code: 'account-exists-with-different-credential',
    );
    expect(SocialAuthService.errorMessage(error),
        contains('already has an account'));
    expect(SocialAuthService.rememberLinkFromCollision(error), isFalse);
  });

  test('disabled provider has actionable message', () {
    expect(
      SocialAuthService.errorMessage(
          FirebaseAuthException(code: 'operation-not-allowed')),
      contains('not enabled'),
    );
  });

  test('linking requires the same verified email', () {
    expect(
      SocialAuthService.matchesVerifiedEmail(
        userEmail: 'USER@example.com',
        verified: true,
        pendingEmail: 'user@example.com',
      ),
      isTrue,
    );
    expect(
      SocialAuthService.matchesVerifiedEmail(
        userEmail: 'user@example.com',
        verified: false,
        pendingEmail: 'user@example.com',
      ),
      isFalse,
    );
    expect(
      SocialAuthService.matchesVerifiedEmail(
        userEmail: 'other@example.com',
        verified: true,
        pendingEmail: 'user@example.com',
      ),
      isFalse,
    );
  });
}
