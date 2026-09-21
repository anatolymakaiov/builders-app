import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LinkedAccountIdentity {
  const LinkedAccountIdentity({
    required this.uid,
    required this.role,
    required this.displayName,
    required this.avatarUrl,
    required this.username,
  });

  final String uid;
  final String role;
  final String displayName;
  final String avatarUrl;
  final String username;

  bool get isEmployer => role == 'employer' || role == 'company';

  factory LinkedAccountIdentity.fromMap(Map<String, dynamic> data) {
    return LinkedAccountIdentity(
      uid: (data['uid'] ?? '').toString(),
      role: (data['role'] ?? 'worker').toString().toLowerCase(),
      displayName: (data['displayName'] ?? 'STROYKA account').toString(),
      avatarUrl: (data['avatarUrl'] ?? '').toString(),
      username: (data['username'] ?? '').toString(),
    );
  }
}

class MultiAccountService {
  MultiAccountService({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FlutterSecureStorage? secureStorage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final FlutterSecureStorage _secureStorage;

  static const _pendingLinkSessionKey =
      'stroyka.multi_account.pending_link_session';
  static final Set<String> _pendingCompletionInFlight = <String>{};

  Future<List<LinkedAccountIdentity>> linkedAccounts() async {
    final result = await _functions.httpsCallable('listLinkedAccounts').call();
    final payload = Map<String, dynamic>.from(result.data as Map);
    final raw = payload['accounts'];
    if (raw is! Iterable) return const <LinkedAccountIdentity>[];
    return raw
        .whereType<Map>()
        .map((item) => LinkedAccountIdentity.fromMap(
              Map<String, dynamic>.from(item),
            ))
        .where((account) => account.uid.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> linkExistingAccount({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-credentials',
        message: 'Enter the email and password for the account.',
      );
    }

    final secondaryApp = await Firebase.initializeApp(
      name: 'stroyka-account-link-${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
    try {
      if (kIsWeb) {
        await secondaryAuth.setPersistence(Persistence.NONE);
      }
      final credential = await secondaryAuth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final idToken = await credential.user?.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-id-token',
          message: 'Could not verify the account.',
        );
      }
      await _functions.httpsCallable('linkAuthenticatedAccount').call({
        'secondaryIdToken': idToken,
      });
    } finally {
      await secondaryAuth.signOut();
      await secondaryApp.delete();
    }
  }

  Future<void> switchTo(String targetUid) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) {
      throw FirebaseAuthException(
        code: 'unauthenticated',
        message: 'Sign in before switching accounts.',
      );
    }
    if (currentUid == targetUid) return;

    final result = await _functions
        .httpsCallable('createLinkedAccountSwitchToken')
        .call({'targetUid': targetUid});
    final payload = Map<String, dynamic>.from(result.data as Map);
    final token = (payload['token'] ?? '').toString();
    if (token.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-custom-token',
        message: 'Could not authorize the account switch.',
      );
    }
    await _auth.signInWithCustomToken(token);
    await _auth.currentUser?.getIdToken(true);
  }

  Future<void> prepareCreateNewAccount() async {
    final result =
        await _functions.httpsCallable('createAccountLinkSession').call();
    final payload = Map<String, dynamic>.from(result.data as Map);
    final token = (payload['sessionToken'] ?? '').toString();
    if (token.isEmpty) {
      throw StateError('Account link session was not created.');
    }
    await _secureStorage.write(key: _pendingLinkSessionKey, value: token);
  }

  Future<void> completePendingNewAccountLink() async {
    final user = _auth.currentUser;
    if (user == null || _pendingCompletionInFlight.contains(user.uid)) return;
    final token = await _secureStorage.read(key: _pendingLinkSessionKey);
    if (token == null || token.isEmpty) return;

    _pendingCompletionInFlight.add(user.uid);
    try {
      await _functions.httpsCallable('redeemAccountLinkSession').call({
        'sessionToken': token,
      });
      await _secureStorage.delete(key: _pendingLinkSessionKey);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'invalid-argument' ||
          error.code == 'not-found' ||
          error.code == 'deadline-exceeded' ||
          error.code == 'failed-precondition') {
        await _secureStorage.delete(key: _pendingLinkSessionKey);
      }
      rethrow;
    } finally {
      _pendingCompletionInFlight.remove(user.uid);
    }
  }
}
