import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:local_auth/local_auth.dart';

class AuthPreferenceMethod {
  static const password = "password";
  static const passwordless = "passwordless";
  static const simpleEnter = "simple_enter";
  static const biometric = "biometric";

  static const all = [password, simpleEnter, biometric];

  static String label(String method) {
    switch (method) {
      case simpleEnter:
      case passwordless:
        return "Simple Enter";
      case biometric:
        return "Biometric login";
      case password:
      default:
        return "Password login";
    }
  }
}

class AuthPreferenceResult {
  final String message;
  final bool warning;

  const AuthPreferenceResult({
    required this.message,
    this.warning = false,
  });
}

class AuthPreferencesService {
  AuthPreferencesService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    LocalAuthentication? localAuth,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _localAuth = localAuth ?? LocalAuthentication();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final LocalAuthentication _localAuth;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return _firestore.collection("users").doc(uid);
  }

  String normalizeEmail(String value) => value.trim().toLowerCase();

  String normalizeMethod(dynamic value) {
    final method = value?.toString() ?? AuthPreferenceMethod.password;
    if (method == AuthPreferenceMethod.passwordless) {
      return AuthPreferenceMethod.simpleEnter;
    }
    if (AuthPreferenceMethod.all.contains(method)) return method;
    return AuthPreferenceMethod.password;
  }

  String methodFromUserData(Map<String, dynamic> data) {
    final prefs = data["authPreferences"] is Map
        ? Map<String, dynamic>.from(data["authPreferences"])
        : <String, dynamic>{};
    final settings = data["settings"] is Map
        ? Map<String, dynamic>.from(data["settings"])
        : <String, dynamic>{};

    return normalizeMethod(
      prefs["activeMethod"] ?? settings["authMethod"] ?? data["authMethod"],
    );
  }

  Future<String> methodForEmail(String email) async {
    final normalized = normalizeEmail(email);
    if (normalized.isEmpty) return AuthPreferenceMethod.password;

    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _firestore
          .collection("users")
          .where("email", isEqualTo: normalized)
          .limit(1)
          .get();
    } on FirebaseException catch (e) {
      if (e.code == "permission-denied") {
        return AuthPreferenceMethod.password;
      }
      rethrow;
    }

    if (snapshot.docs.isEmpty) return AuthPreferenceMethod.password;
    return methodFromUserData(snapshot.docs.first.data());
  }

  Future<bool> biometricAvailable() async {
    final supported = await _localAuth.isDeviceSupported();
    final canCheck = await _localAuth.canCheckBiometrics;
    if (!supported || !canCheck) return false;

    final biometrics = await _localAuth.getAvailableBiometrics();
    return biometrics.isNotEmpty;
  }

  Future<AuthPreferenceResult> saveCurrentUserMethod(String method) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: "not-signed-in",
        message: "You need to be signed in to change authentication settings.",
      );
    }

    final normalizedMethod = normalizeMethod(method);
    await user.reload();
    final refreshedUser = _auth.currentUser ?? user;
    final email = normalizeEmail(refreshedUser.email ?? "");

    var biometricEnabled = false;
    if (normalizedMethod == AuthPreferenceMethod.biometric) {
      final available = await biometricAvailable();
      if (!available) {
        throw FirebaseAuthException(
          code: "biometric-unavailable",
          message: "Biometric authentication is not available on this device.",
        );
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: "Confirm biometric login for your STROYKA account",
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!authenticated) {
        throw FirebaseAuthException(
          code: "biometric-cancelled",
          message: "Biometric confirmation was cancelled.",
        );
      }
      biometricEnabled = true;
    }

    final simpleEnterEnabled =
        normalizedMethod == AuthPreferenceMethod.simpleEnter;

    await _userRef(refreshedUser.uid).set({
      if (email.isNotEmpty) "email": email,
      "authMethod": normalizedMethod,
      "settings.authMethod": normalizedMethod,
      "settings.updatedAt": FieldValue.serverTimestamp(),
      "authPreferences": {
        "activeMethod": normalizedMethod,
        "passwordLoginEnabled": true,
        "passwordlessLoginEnabled": false,
        "simpleEnterEnabled": simpleEnterEnabled,
        "biometricLoginEnabled": biometricEnabled,
        "email": email,
        "emailVerified": refreshedUser.emailVerified,
        "emailVerificationRecommended": false,
        "updatedAt": FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));

    return AuthPreferenceResult(
      message:
          "Authentication method saved: ${AuthPreferenceMethod.label(normalizedMethod)}.",
    );
  }

  Future<bool> authenticateBiometricLogin() async {
    final available = await biometricAvailable();
    if (!available) return false;

    return _localAuth.authenticate(
      localizedReason: "Use Face ID / Touch ID to enter STROYKA",
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: true,
      ),
    );
  }

  Future<void> sendPasswordlessLink(String email) async {
    final normalized = normalizeEmail(email);
    if (normalized.isEmpty) {
      throw FirebaseAuthException(
        code: "missing-email",
        message: "Enter your email address to receive a sign-in link.",
      );
    }

    await _auth.sendSignInLinkToEmail(
      email: normalized,
      actionCodeSettings: ActionCodeSettings(
        url: "https://builder-jobs-app.firebaseapp.com/auth",
        handleCodeInApp: true,
        iOSBundleId: "com.makaiov.builderjob",
        androidPackageName: "com.example.test_app",
        androidInstallApp: true,
        androidMinimumVersion: "21",
      ),
    );
  }

  Future<UserCredential> signInWithEmailLink({
    required String email,
    required String emailLink,
  }) {
    return _auth.signInWithEmailLink(
      email: normalizeEmail(email),
      emailLink: emailLink.trim(),
    );
  }
}
