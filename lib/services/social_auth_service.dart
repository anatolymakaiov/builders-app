import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

enum SocialProvider { google, apple, facebook }

class SocialSignInResult {
  const SocialSignInResult({this.credential, this.cancelled = false});

  final UserCredential? credential;
  final bool cancelled;
}

class SocialAuthService {
  SocialAuthService({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  static Future<void>? _googleInitialization;
  static AuthCredential? _pendingLink;
  static String? _pendingEmail;

  static bool rememberLinkFromCollision(FirebaseAuthException error) {
    if (error.code != 'account-exists-with-different-credential' ||
        error.credential == null ||
        (error.email ?? '').trim().isEmpty) {
      return false;
    }
    _pendingLink = error.credential;
    _pendingEmail = error.email!.trim().toLowerCase();
    return true;
  }

  static bool rememberVerifiedProviderForLink({
    required AuthCredential? credential,
    required String? email,
  }) {
    if (credential == null || (email ?? '').trim().isEmpty) return false;
    _pendingLink = credential;
    _pendingEmail = email!.trim().toLowerCase();
    return true;
  }

  static Future<bool> linkAfterVerifiedPasswordSignIn(User user) async {
    final credential = _pendingLink;
    if (credential == null) {
      return false;
    }
    if (!matchesVerifiedEmail(
      userEmail: user.email,
      verified: user.emailVerified,
      pendingEmail: _pendingEmail,
    )) {
      _pendingLink = null;
      _pendingEmail = null;
      return false;
    }
    try {
      await user.linkWithCredential(credential);
      return true;
    } finally {
      _pendingLink = null;
      _pendingEmail = null;
    }
  }

  static bool matchesVerifiedEmail({
    required String? userEmail,
    required bool verified,
    required String? pendingEmail,
  }) =>
      verified &&
      pendingEmail != null &&
      userEmail?.trim().toLowerCase() == pendingEmail.trim().toLowerCase();

  static bool available(SocialProvider provider) =>
      provider != SocialProvider.apple ||
      kIsWeb ||
      Platform.isIOS ||
      Platform.isMacOS;

  static SocialProvider? providerFromIds(Iterable<String> providerIds) {
    if (providerIds.contains('google.com')) return SocialProvider.google;
    if (providerIds.contains('apple.com')) return SocialProvider.apple;
    if (providerIds.contains('facebook.com')) return SocialProvider.facebook;
    return null;
  }

  Future<SocialSignInResult> signIn(SocialProvider provider) async {
    try {
      if (kIsWeb) {
        final oauthProvider = switch (provider) {
          SocialProvider.google => GoogleAuthProvider(),
          SocialProvider.apple => AppleAuthProvider(),
          SocialProvider.facebook => FacebookAuthProvider(),
        };
        return SocialSignInResult(
          credential: await _auth.signInWithPopup(oauthProvider),
        );
      }

      switch (provider) {
        case SocialProvider.google:
          final google = GoogleSignIn.instance;
          try {
            await (_googleInitialization ??= google.initialize());
          } catch (_) {
            _googleInitialization = null;
            rethrow;
          }
          final account = await google.authenticate();
          final idToken = account.authentication.idToken;
          if (idToken == null) {
            throw StateError('Google did not return an identity token.');
          }
          return SocialSignInResult(
            credential: await _auth.signInWithCredential(
              GoogleAuthProvider.credential(idToken: idToken),
            ),
          );
        case SocialProvider.apple:
          if (!available(provider)) {
            throw UnsupportedError(
                'Apple sign-in is not available on this device.');
          }
          return SocialSignInResult(
            credential: await _auth.signInWithProvider(AppleAuthProvider()),
          );
        case SocialProvider.facebook:
          final result = await FacebookAuth.instance.login();
          if (result.status == LoginStatus.cancelled) {
            return const SocialSignInResult(cancelled: true);
          }
          if (result.status != LoginStatus.success ||
              result.accessToken == null) {
            throw StateError(result.message ?? 'Facebook sign-in failed.');
          }
          return SocialSignInResult(
            credential: await _auth.signInWithCredential(
              FacebookAuthProvider.credential(result.accessToken!.tokenString),
            ),
          );
      }
    } on FirebaseAuthException catch (error) {
      if (isCancellation(error.code)) {
        return const SocialSignInResult(cancelled: true);
      }
      rememberLinkFromCollision(error);
      rethrow;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return const SocialSignInResult(cancelled: true);
      }
      rethrow;
    }
  }

  static bool isCancellation(String code) =>
      code == 'popup-closed-by-user' ||
      code == 'cancelled-popup-request' ||
      code == 'canceled' ||
      code == 'cancelled';

  static String errorMessage(Object error) {
    if (error is FirebaseAuthException) {
      if (error.code == 'account-exists-with-different-credential') {
        return 'This email already has an account. Sign in with its existing verified account to link this provider.';
      }
      if (error.code == 'operation-not-allowed') {
        return 'This sign-in provider is not enabled yet.';
      }
      return error.message ?? 'Could not sign in. Please try again.';
    }
    return 'Could not sign in. Check provider setup and try again.';
  }
}
