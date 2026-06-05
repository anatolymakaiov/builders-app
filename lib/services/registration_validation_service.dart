import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PendingRegistrationDetails {
  final String email;
  final String role;
  final String registrationName;
  final String phone;
  final String normalizedPhone;

  const PendingRegistrationDetails({
    required this.email,
    required this.role,
    required this.registrationName,
    required this.phone,
    required this.normalizedPhone,
  });

  Map<String, dynamic> toUserDocument() {
    return {
      "role": role,
      "email": email,
      "registrationName": registrationName,
      "phone": phone,
      "normalizedPhone": normalizedPhone,
      "emailVerified": false,
      "phoneVerified": false,
      "phoneVerificationRequired": false,
      "phoneVerificationProviderConfigured": false,
      "legalAccepted": false,
      "onboardingLegalStepComplete": false,
      "profileComplete": false,
      "onboardingComplete": false,
      "registrationStarted": true,
      "authMethod": "password",
      "settings": {
        "authMethod": "password",
        "updatedAt": FieldValue.serverTimestamp(),
      },
      "authPreferences": {
        "activeMethod": "password",
        "passwordLoginEnabled": true,
        "passwordlessLoginEnabled": false,
        "biometricLoginEnabled": false,
        "email": email,
        "emailVerified": false,
        "updatedAt": FieldValue.serverTimestamp(),
      },
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    };
  }
}

class RegistrationValidationResult {
  final List<String> errors;

  const RegistrationValidationResult(this.errors);

  bool get hasErrors => errors.isNotEmpty;
  String get message => errors.join("\n");
}

class RegistrationValidationService {
  final FirebaseFirestore firestore;

  RegistrationValidationService({
    FirebaseFirestore? firestore,
  }) : firestore = firestore ?? FirebaseFirestore.instance;

  static final Map<String, PendingRegistrationDetails> _pendingByEmail = {};

  static void rememberPending(PendingRegistrationDetails details) {
    _pendingByEmail[details.email] = details;
  }

  static PendingRegistrationDetails? pendingForEmail(String? email) {
    final normalized = normalizeEmail(email ?? "");
    if (normalized.isEmpty) return null;
    return _pendingByEmail[normalized];
  }

  static void clearPending(String email) {
    _pendingByEmail.remove(normalizeEmail(email));
  }

  static String normalizeEmail(String value) {
    return value.trim().toLowerCase();
  }

  static String normalizePhone(String value) {
    var digits = value.trim().replaceAll(RegExp(r"[^0-9+]"), "");
    if (digits.startsWith("00")) {
      digits = "+${digits.substring(2)}";
    }
    if (digits.startsWith("+")) {
      return digits;
    }
    if (digits.startsWith("44")) {
      return "+$digits";
    }
    if (digits.startsWith("0") && digits.length > 1) {
      return "+44${digits.substring(1)}";
    }
    return digits;
  }

  static String firebaseAuthErrorMessage(Object error) {
    if (error is FirebaseAuthException) {
      if (error.code == "email-already-in-use") {
        return "An account with this email address already exists.";
      }
      if (error.code == "invalid-email") {
        return "Enter a valid email address.";
      }
      if (error.code == "weak-password") {
        return "Enter a stronger password.";
      }
    }
    return "Could not create account. Please try again.";
  }

  Future<RegistrationValidationResult> validate({
    required String email,
    required String phone,
  }) async {
    try {
      final normalizedEmail = normalizeEmail(email);
      final normalizedPhone = normalizePhone(phone);
      final errors = <String>[];

      final emailExists = await _activeUserExists(
        field: "email",
        value: normalizedEmail,
      );
      if (emailExists) {
        errors.add("An active account with this email address already exists.");
      }

      final phoneExists = await _phoneExists(
        phone: phone.trim(),
        normalizedPhone: normalizedPhone,
      );
      if (phoneExists) {
        errors.add("An active account with this phone number already exists.");
      }

      return RegistrationValidationResult(errors);
    } on FirebaseException catch (error) {
      if (error.code == "permission-denied" || error.code == "unavailable") {
        return const RegistrationValidationResult([]);
      }
      rethrow;
    }
  }

  Future<bool> _phoneExists({
    required String phone,
    required String normalizedPhone,
  }) async {
    if (normalizedPhone.isEmpty) return false;
    final normalizedMatch = await _activeUserExists(
      field: "normalizedPhone",
      value: normalizedPhone,
    );
    if (normalizedMatch) return true;
    if (phone.isEmpty) return false;
    final phoneMatch = await _activeUserExists(field: "phone", value: phone);
    if (phoneMatch) return true;
    return _activeArrayContains(field: "phones", value: phone);
  }

  Future<bool> _activeUserExists({
    required String field,
    required String value,
  }) async {
    if (value.trim().isEmpty) return false;
    final snapshot = await firestore
        .collection("users")
        .where(field, isEqualTo: value)
        .limit(5)
        .get();
    return snapshot.docs.any((doc) => _isActiveAccount(doc.data()));
  }

  Future<bool> _activeArrayContains({
    required String field,
    required String value,
  }) async {
    if (value.trim().isEmpty) return false;
    final snapshot = await firestore
        .collection("users")
        .where(field, arrayContains: value)
        .limit(5)
        .get();
    return snapshot.docs.any((doc) => _isActiveAccount(doc.data()));
  }

  bool _isActiveAccount(Map<String, dynamic> data) {
    final status = data["status"]?.toString().toLowerCase();
    return data["accountDeleted"] != true &&
        data["deleted"] != true &&
        data["anonymised"] != true &&
        data["active"] != false &&
        status != "deleted";
  }
}
