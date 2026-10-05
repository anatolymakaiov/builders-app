import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'address_lookup_service.dart';
import 'job_taxonomy_service.dart';

class PendingRegistrationDetails {
  final String email;
  final String role;
  final String registrationName;
  final String phone;
  final String normalizedPhone;
  final String firstName;
  final String lastName;
  final String trade;
  final List<String> tradeIds;
  final String companyName;
  final PostalAddress? address;
  final bool emailVerified;
  final bool phoneVerified;
  final String photoUrl;

  const PendingRegistrationDetails({
    required this.email,
    required this.role,
    required this.registrationName,
    required this.phone,
    required this.normalizedPhone,
    this.firstName = '',
    this.lastName = '',
    this.trade = '',
    this.tradeIds = const [],
    this.companyName = '',
    this.address,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.photoUrl = '',
  });

  factory PendingRegistrationDetails.fromSocialIdentity({
    required String? email,
    required String? displayName,
    required String? photoUrl,
    required String? verifiedPhoneNumber,
    required bool emailVerified,
  }) {
    final nameParts = (displayName ?? '').trim().split(RegExp(r'\s+'));
    final firstName = nameParts.first == '' ? '' : nameParts.first;
    final lastName = nameParts.length > 1 ? nameParts.skip(1).join(' ') : '';
    final phone = verifiedPhoneNumber?.trim() ?? '';
    return PendingRegistrationDetails(
      email: RegistrationIdentityService.normalizeEmail(email ?? ''),
      role: 'worker',
      registrationName:
          [firstName, lastName].where((part) => part.isNotEmpty).join(' '),
      phone: phone,
      normalizedPhone: RegistrationIdentityService.normalizePhone(phone),
      firstName: firstName,
      lastName: lastName,
      emailVerified: emailVerified && (email ?? '').trim().isNotEmpty,
      phoneVerified: phone.isNotEmpty,
      photoUrl: photoUrl?.trim() ?? '',
    );
  }

  Map<String, dynamic> toUserDocument() {
    final requiresPhoneVerification = role == "employer";
    final resolvedTradeIds = tradeIds.isNotEmpty
        ? tradeIds
        : (JobTaxonomyService.roleFor(trade) == null
            ? const <String>[]
            : <String>[JobTaxonomyService.roleFor(trade)!.id]);
    return {
      "role": role,
      "email": email,
      "normalizedEmail": RegistrationIdentityService.normalizeEmail(email),
      "registrationName": registrationName,
      if (firstName.isNotEmpty) 'registrationFirstName': firstName,
      if (lastName.isNotEmpty) 'registrationLastName': lastName,
      if (role == 'worker' && resolvedTradeIds.isNotEmpty)
        ...JobTaxonomyService.workerTradeFields(resolvedTradeIds),
      if (companyName.isNotEmpty) 'registrationCompanyName': companyName,
      if (address != null) ...{
        'addressLine1': address!.addressLine1,
        'addressLine2': address!.addressLine2,
        'addressLine3': address!.addressLine3,
        'townCity': address!.townCity,
        'county': address!.county,
        'postcode': address!.postcode,
        'country': address!.country,
        'location': address!.addressLine1,
      },
      "phone": phone,
      "normalizedPhone": normalizedPhone,
      "emailVerified": emailVerified,
      if (emailVerified) ...{
        'verifiedEmail': email,
        'verifiedNormalizedEmail':
            RegistrationIdentityService.normalizeEmail(email),
      },
      "phoneVerified": phoneVerified,
      if (phoneVerified) ...{
        'verifiedPhone': phone,
        'verifiedNormalizedPhone': normalizedPhone,
      },
      if (photoUrl.isNotEmpty) ...{
        'photo': photoUrl,
        'avatarUrl': photoUrl,
        'photoUrl': photoUrl,
      },
      "phoneVerificationRequired": requiresPhoneVerification,
      "phoneVerificationProviderConfigured": requiresPhoneVerification,
      "legalAccepted": false,
      "onboardingLegalStepComplete": false,
      "profileComplete": false,
      "onboardingComplete": false,
      "onboardingStatus": "registration_started",
      "active": true,
      "deleted": false,
      "accountDeleted": false,
      "anonymised": false,
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

class IdentityAvailabilityResult {
  final bool available;
  final String? blockingMessage;
  final bool blockedByActiveAccount;

  const IdentityAvailabilityResult.available()
      : available = true,
        blockingMessage = null,
        blockedByActiveAccount = false;

  const IdentityAvailabilityResult.blocked(this.blockingMessage)
      : available = false,
        blockedByActiveAccount = true;
}

class RegistrationIdentityService {
  RegistrationIdentityService({
    FirebaseFirestore? firestore,
  }) : firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore firestore;

  static final Map<String, PendingRegistrationDetails> _pendingByEmail = {};

  static void rememberPending(PendingRegistrationDetails details) {
    _pendingByEmail[normalizeEmail(details.email)] = details;
  }

  static PendingRegistrationDetails? pendingForEmail(String? email) {
    final normalized = normalizeEmail(email ?? "");
    if (normalized.isEmpty) return null;
    return _pendingByEmail[normalized];
  }

  static void clearPending(String email) {
    _pendingByEmail.remove(normalizeEmail(email));
  }

  static void clearPendingRegistrations() {
    _pendingByEmail.clear();
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
        return "An active account with this email address already exists.";
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

  static bool isEmailAlreadyInUse(Object error) {
    return error is FirebaseAuthException &&
        error.code == "email-already-in-use";
  }

  Future<RegistrationValidationResult> validate({
    required String email,
    required String phone,
  }) async {
    final errors = <String>[];

    try {
      final emailAvailability = await checkEmailAvailability(email);
      if (!emailAvailability.available &&
          emailAvailability.blockingMessage != null) {
        errors.add(emailAvailability.blockingMessage!);
      }
    } on FirebaseException catch (error) {
      if (error.code == "permission-denied" || error.code == "unavailable") {
        debugPrint(
          "EMAIL DUPLICATE VALIDATION SKIPPED: ${error.code}. Registration will rely on Firebase Auth.",
        );
      } else {
        rethrow;
      }
    }

    try {
      final phoneAvailability = await checkPhoneAvailability(phone);
      if (!phoneAvailability.available &&
          phoneAvailability.blockingMessage != null) {
        errors.add(phoneAvailability.blockingMessage!);
      }
    } on FirebaseException catch (error) {
      if (error.code == "permission-denied" || error.code == "unavailable") {
        debugPrint(
          "PHONE DUPLICATE VALIDATION FAILED: ${error.code}. Registration blocked until phone can be checked.",
        );
        errors.add(
          "Could not verify this phone number. Please try again.",
        );
      } else {
        rethrow;
      }
    }

    return RegistrationValidationResult(errors);
  }

  Future<IdentityAvailabilityResult> checkEmailAvailability(
    String email,
  ) async {
    final normalizedEmail = normalizeEmail(email);
    if (normalizedEmail.isEmpty) {
      return const IdentityAvailabilityResult.available();
    }

    if (await _identityInUse('email', normalizedEmail)) {
      return const IdentityAvailabilityResult.blocked(
        "An active account with this email address already exists.",
      );
    }

    return const IdentityAvailabilityResult.available();
  }

  Future<IdentityAvailabilityResult> checkPhoneAvailability(
    String phone,
  ) async {
    final rawPhone = phone.trim();
    final normalizedPhone = normalizePhone(phone);
    if (rawPhone.isEmpty && normalizedPhone.isEmpty) {
      return const IdentityAvailabilityResult.available();
    }

    if (await _identityInUse('phone', rawPhone)) {
      return const IdentityAvailabilityResult.blocked(
        "An active account with this phone number already exists.",
      );
    }
    return const IdentityAvailabilityResult.available();
  }

  Future<bool> _identityInUse(String kind, String value) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('checkRegistrationIdentity')
        .call({'kind': kind, 'value': value});
    final data = result.data;
    if (data is! Map || data['blocked'] is! bool) {
      throw StateError('Identity lookup returned an invalid response.');
    }
    return data['blocked'] as bool;
  }

  Future<void> updatePhoneIndexesForUser({
    required String uid,
    required String phone,
    String? previousPhone,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    final normalizedPrevious = normalizePhone(previousPhone ?? "");

    if (normalizedPrevious.isNotEmpty &&
        normalizedPrevious != normalizedPhone) {
      for (final collection in ["phoneIndex", "registrationPhoneIndex"]) {
        await _markIndexInactive(
          collectionName: collection,
          documentId: normalizedPrevious,
          reason: "phone_changed",
          previousUserId: uid,
        );
      }
    }

    if (normalizedPhone.isEmpty) return;

    for (final collection in ["phoneIndex", "registrationPhoneIndex"]) {
      await firestore.collection(collection).doc(normalizedPhone).set({
        "uid": uid,
        "userId": uid,
        "normalizedPhone": normalizedPhone,
        "active": true,
        "deleted": false,
        "stale": false,
        "kind": "phone",
        "updatedAt": FieldValue.serverTimestamp(),
        "createdAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> updateEmailIndexesForUser({
    required String uid,
    required String email,
    String? previousEmail,
  }) async {
    final normalizedEmail = normalizeEmail(email);
    final normalizedPrevious = normalizeEmail(previousEmail ?? "");

    if (normalizedPrevious.isNotEmpty &&
        normalizedPrevious != normalizedEmail) {
      for (final collection in ["emailIndex", "registrationEmailIndex"]) {
        await _markIndexInactive(
          collectionName: collection,
          documentId: normalizedPrevious,
          reason: "email_changed",
          previousUserId: uid,
        );
      }
    }

    if (normalizedEmail.isEmpty) return;

    for (final collection in ["emailIndex", "registrationEmailIndex"]) {
      await firestore.collection(collection).doc(normalizedEmail).set({
        "uid": uid,
        "userId": uid,
        "normalizedEmail": normalizedEmail,
        "active": true,
        "deleted": false,
        "stale": false,
        "kind": "email",
        "updatedAt": FieldValue.serverTimestamp(),
        "createdAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<bool> hasActiveAccountForEmail(String email) async {
    final availability = await checkEmailAvailability(email);
    return !availability.available && availability.blockedByActiveAccount;
  }

  Future<void> releaseIdentityForDeletedUser(String uid) async {
    final userRef = firestore.collection("users").doc(uid);
    final snapshot = await userRef.get();
    final data = snapshot.data();
    if (data == null) return;

    final email = normalizeEmail(data["email"]?.toString() ?? "");
    final normalizedEmail =
        normalizeEmail(data["normalizedEmail"]?.toString() ?? email);
    final phone = data["phone"]?.toString() ?? "";
    final normalizedPhone =
        normalizePhone(data["normalizedPhone"]?.toString() ?? phone);

    final updates = <String, dynamic>{
      "active": false,
      "deleted": true,
      "accountDeleted": true,
      "anonymised": true,
      "status": "deleted",
      "email": FieldValue.delete(),
      "normalizedEmail": FieldValue.delete(),
      "phone": FieldValue.delete(),
      "normalizedPhone": FieldValue.delete(),
      "phones": <String>[],
      "updatedAt": FieldValue.serverTimestamp(),
      "deletedAt": FieldValue.serverTimestamp(),
    };

    await userRef.set(updates, SetOptions(merge: true));

    final identities = <String, List<String>>{
      "emailIndex": [email, normalizedEmail],
      "registrationEmailIndex": [email, normalizedEmail],
      "phoneIndex": [phone, normalizedPhone],
      "registrationPhoneIndex": [phone, normalizedPhone],
    };

    for (final entry in identities.entries) {
      for (final identity in entry.value.toSet()) {
        final trimmed = identity.trim();
        if (trimmed.isEmpty) continue;
        await _markIndexInactive(
          collectionName: entry.key,
          documentId: trimmed,
          reason: "account_deleted",
          previousUserId: uid,
        );
      }
    }

    clearPending(email);
    clearPending(normalizedEmail);
  }

  Future<void> _markIndexInactive({
    required String collectionName,
    required String documentId,
    required String reason,
    String? previousUserId,
  }) async {
    try {
      await firestore.collection(collectionName).doc(documentId).set({
        "active": false,
        "deleted": true,
        "stale": true,
        "cleanupReason": reason,
        if (previousUserId != null) "previousUserId": previousUserId,
        "deletedAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (error) {
      debugPrint(
        "DUPLICATE INDEX CLEANUP SKIPPED: $collectionName/$documentId ${error.code}",
      );
    }
  }
}

class RegistrationValidationService extends RegistrationIdentityService {
  RegistrationValidationService({
    super.firestore,
  });

  static void rememberPending(PendingRegistrationDetails details) {
    RegistrationIdentityService.rememberPending(details);
  }

  static PendingRegistrationDetails? pendingForEmail(String? email) {
    return RegistrationIdentityService.pendingForEmail(email);
  }

  static void clearPending(String email) {
    RegistrationIdentityService.clearPending(email);
  }

  static void clearPendingRegistrations() {
    RegistrationIdentityService.clearPendingRegistrations();
  }

  static String normalizeEmail(String value) {
    return RegistrationIdentityService.normalizeEmail(value);
  }

  static String normalizePhone(String value) {
    return RegistrationIdentityService.normalizePhone(value);
  }

  static String firebaseAuthErrorMessage(Object error) {
    return RegistrationIdentityService.firebaseAuthErrorMessage(error);
  }

  static bool isEmailAlreadyInUse(Object error) {
    return RegistrationIdentityService.isEmailAlreadyInUse(error);
  }
}
