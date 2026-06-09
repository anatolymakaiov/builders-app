import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
      "normalizedEmail": RegistrationIdentityService.normalizeEmail(email),
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

    final blockedByIndex = await _checkIdentityIndexes(
      kind: "email",
      collections: const ["emailIndex", "registrationEmailIndex"],
      identity: normalizedEmail,
    );
    if (blockedByIndex) {
      return const IdentityAvailabilityResult.blocked(
        "An active account with this email address already exists.",
      );
    }

    final blockedByUserEmail = await _activeUserExists(
      identityKind: "email",
      source: "users",
      field: "email",
      value: normalizedEmail,
    );
    if (blockedByUserEmail) {
      return const IdentityAvailabilityResult.blocked(
        "An active account with this email address already exists.",
      );
    }

    final blockedByUserNormalizedEmail = await _activeUserExists(
      identityKind: "email",
      source: "users",
      field: "normalizedEmail",
      value: normalizedEmail,
    );
    if (blockedByUserNormalizedEmail) {
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

    final blockedByIndex = await _checkIdentityIndexes(
      kind: "phone",
      collections: const ["phoneIndex", "registrationPhoneIndex"],
      identity: normalizedPhone,
    );
    if (blockedByIndex) {
      _logPhoneDuplicateCheck(
        normalizedPhone: normalizedPhone,
        source: "phoneIndex",
        activeDuplicate: true,
      );
      return const IdentityAvailabilityResult.blocked(
        "An active account with this phone number already exists.",
      );
    }

    if (FirebaseAuth.instance.currentUser == null) {
      _logPhoneDuplicateCheck(
        normalizedPhone: normalizedPhone,
        source: "phoneIndex_pre_auth",
        activeDuplicate: false,
      );
      return const IdentityAvailabilityResult.available();
    }

    if (normalizedPhone.isNotEmpty) {
      final blockedByNormalizedPhone = await _activeUserExists(
        identityKind: "phone",
        source: "users",
        field: "normalizedPhone",
        value: normalizedPhone,
      );
      if (blockedByNormalizedPhone) {
        _logPhoneDuplicateCheck(
          normalizedPhone: normalizedPhone,
          source: "users.normalizedPhone",
          activeDuplicate: true,
        );
        return const IdentityAvailabilityResult.blocked(
          "An active account with this phone number already exists.",
        );
      }
    }

    if (rawPhone.isNotEmpty) {
      final blockedByRawPhone = await _activeUserExists(
        identityKind: "phone",
        source: "users",
        field: "phone",
        value: rawPhone,
      );
      if (blockedByRawPhone) {
        _logPhoneDuplicateCheck(
          normalizedPhone: normalizedPhone,
          source: "users.phone",
          activeDuplicate: true,
        );
        return const IdentityAvailabilityResult.blocked(
          "An active account with this phone number already exists.",
        );
      }

      final blockedByPhonesArray = await _activeArrayContains(
        identityKind: "phone",
        source: "users",
        field: "phones",
        value: rawPhone,
      );
      if (blockedByPhonesArray) {
        _logPhoneDuplicateCheck(
          normalizedPhone: normalizedPhone,
          source: "users.phones",
          activeDuplicate: true,
        );
        return const IdentityAvailabilityResult.blocked(
          "An active account with this phone number already exists.",
        );
      }
    }

    _logPhoneDuplicateCheck(
      normalizedPhone: normalizedPhone,
      source: "users",
      activeDuplicate: false,
    );
    return const IdentityAvailabilityResult.available();
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

  Future<void> cleanupStaleIdentityRecords({
    String? email,
    String? phone,
  }) async {
    final normalizedEmail = normalizeEmail(email ?? "");
    final normalizedPhone = normalizePhone(phone ?? "");

    if (normalizedEmail.isNotEmpty) {
      for (final collection in ["emailIndex", "registrationEmailIndex"]) {
        await _cleanupIndexIfStale(
          collectionName: collection,
          documentId: normalizedEmail,
          kind: "email",
        );
      }
    }

    if (normalizedPhone.isNotEmpty) {
      for (final collection in ["phoneIndex", "registrationPhoneIndex"]) {
        await _cleanupIndexIfStale(
          collectionName: collection,
          documentId: normalizedPhone,
          kind: "phone",
        );
      }
    }
  }

  Future<bool> _checkIdentityIndexes({
    required String kind,
    required List<String> collections,
    required String identity,
  }) async {
    if (identity.trim().isEmpty) return false;

    for (final collectionName in collections) {
      final blocked = await _checkIdentityIndex(
        kind: kind,
        collectionName: collectionName,
        documentId: identity,
      );
      if (blocked) return true;
    }

    return false;
  }

  Future<bool> _checkIdentityIndex({
    required String kind,
    required String collectionName,
    required String documentId,
  }) async {
    final ref = firestore.collection(collectionName).doc(documentId);
    final snapshot = await ref.get();
    if (!snapshot.exists) return false;

    final data = snapshot.data() ?? <String, dynamic>{};
    if (!_isActiveAccount(data)) {
      _logDuplicateDiagnostic(
        title: "DUPLICATE ${kind.toUpperCase()} CHECK INACTIVE INDEX IGNORED",
        source: collectionName,
        document: "$collectionName/$documentId",
        field: kind,
        data: data,
      );
      return false;
    }

    final uid = _uidFromIndex(data);
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null && uid == currentUid) {
      _logDuplicateDiagnostic(
        title: "DUPLICATE ${kind.toUpperCase()} CHECK CURRENT USER IGNORED",
        source: collectionName,
        document: "$collectionName/$documentId",
        field: kind,
        data: data,
        uid: uid,
      );
      return false;
    }

    if (FirebaseAuth.instance.currentUser == null) {
      _logDuplicateDiagnostic(
        title: "DUPLICATE ${kind.toUpperCase()} CHECK BLOCKED BY",
        source: collectionName,
        document: "$collectionName/$documentId",
        field: kind,
        data: data,
        uid: uid,
        extra: "active lookup index matched before auth",
      );
      return true;
    }

    if (uid == null || uid.isEmpty) {
      _logDuplicateDiagnostic(
        title: "DUPLICATE ${kind.toUpperCase()} CHECK STALE INDEX FOUND",
        source: collectionName,
        document: "$collectionName/$documentId",
        field: kind,
        data: data,
        extra:
            "referenced user missing\naction: allow registration + cleanup index",
      );
      await _markIndexInactive(
        collectionName: collectionName,
        documentId: documentId,
        reason: "missing_uid",
      );
      return false;
    }

    final userSnapshot = await firestore.collection("users").doc(uid).get();
    final userData = userSnapshot.data();
    if (!userSnapshot.exists || userData == null) {
      _logDuplicateDiagnostic(
        title: "DUPLICATE ${kind.toUpperCase()} CHECK STALE INDEX FOUND",
        source: collectionName,
        document: "$collectionName/$documentId",
        field: kind,
        data: data,
        uid: uid,
        extra:
            "referenced user missing\naction: allow registration + cleanup index",
      );
      await _markIndexInactive(
        collectionName: collectionName,
        documentId: documentId,
        reason: "missing_user",
        previousUserId: uid,
      );
      return false;
    }

    if (!_isActiveAccount(userData)) {
      _logDuplicateDiagnostic(
        title: "DUPLICATE ${kind.toUpperCase()} CHECK STALE INDEX FOUND",
        source: collectionName,
        document: "$collectionName/$documentId",
        field: kind,
        data: userData,
        uid: uid,
        extra:
            "referenced user deleted/inactive\naction: allow registration + cleanup index",
      );
      await _markIndexInactive(
        collectionName: collectionName,
        documentId: documentId,
        reason: "deleted_user",
        previousUserId: uid,
      );
      return false;
    }

    _logDuplicateDiagnostic(
      title: "DUPLICATE ${kind.toUpperCase()} CHECK BLOCKED BY",
      source: collectionName,
      document: "$collectionName/$documentId",
      field: kind,
      data: userData,
      uid: uid,
    );
    return true;
  }

  Future<bool> _activeUserExists({
    required String identityKind,
    required String source,
    required String field,
    required String value,
  }) async {
    if (value.trim().isEmpty) return false;
    final snapshot = await firestore
        .collection(source)
        .where(field, isEqualTo: value)
        .limit(10)
        .get();

    var hasActive = false;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (doc.id == FirebaseAuth.instance.currentUser?.uid) {
        _logDuplicateDiagnostic(
          title:
              "DUPLICATE ${identityKind.toUpperCase()} CHECK CURRENT USER IGNORED",
          source: source,
          document: "$source/${doc.id}",
          field: field,
          data: data,
          uid: doc.id,
        );
        continue;
      }
      if (_isActiveAccount(data)) {
        hasActive = true;
        _logDuplicateDiagnostic(
          title: "DUPLICATE ${identityKind.toUpperCase()} CHECK BLOCKED BY",
          source: source,
          document: "$source/${doc.id}",
          field: field,
          data: data,
          uid: doc.id,
        );
      } else {
        _logDuplicateDiagnostic(
          title:
              "DUPLICATE ${identityKind.toUpperCase()} CHECK DELETED USER IGNORED",
          source: source,
          document: "$source/${doc.id}",
          field: field,
          data: data,
          uid: doc.id,
        );
      }
    }
    return hasActive;
  }

  Future<bool> _activeArrayContains({
    required String identityKind,
    required String source,
    required String field,
    required String value,
  }) async {
    if (value.trim().isEmpty) return false;
    final snapshot = await firestore
        .collection(source)
        .where(field, arrayContains: value)
        .limit(10)
        .get();

    var hasActive = false;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (doc.id == FirebaseAuth.instance.currentUser?.uid) {
        _logDuplicateDiagnostic(
          title:
              "DUPLICATE ${identityKind.toUpperCase()} CHECK CURRENT USER IGNORED",
          source: source,
          document: "$source/${doc.id}",
          field: field,
          data: data,
          uid: doc.id,
        );
        continue;
      }
      if (_isActiveAccount(data)) {
        hasActive = true;
        _logDuplicateDiagnostic(
          title: "DUPLICATE ${identityKind.toUpperCase()} CHECK BLOCKED BY",
          source: source,
          document: "$source/${doc.id}",
          field: field,
          data: data,
          uid: doc.id,
        );
      } else {
        _logDuplicateDiagnostic(
          title:
              "DUPLICATE ${identityKind.toUpperCase()} CHECK DELETED USER IGNORED",
          source: source,
          document: "$source/${doc.id}",
          field: field,
          data: data,
          uid: doc.id,
        );
      }
    }
    return hasActive;
  }

  Future<void> _cleanupIndexIfStale({
    required String collectionName,
    required String documentId,
    required String kind,
  }) async {
    final ref = firestore.collection(collectionName).doc(documentId);
    final snapshot = await ref.get();
    if (!snapshot.exists) return;
    final data = snapshot.data() ?? <String, dynamic>{};
    final uid = _uidFromIndex(data);
    if (uid == null || uid.isEmpty) {
      await _markIndexInactive(
        collectionName: collectionName,
        documentId: documentId,
        reason: "missing_uid",
      );
      return;
    }

    final userSnapshot = await firestore.collection("users").doc(uid).get();
    final userData = userSnapshot.data();
    if (!userSnapshot.exists ||
        userData == null ||
        !_isActiveAccount(userData)) {
      _logDuplicateDiagnostic(
        title: "DUPLICATE ${kind.toUpperCase()} CHECK STALE INDEX FOUND",
        source: collectionName,
        document: "$collectionName/$documentId",
        field: kind,
        data: userData ?? data,
        uid: uid,
        extra: "cleanupStaleIdentityRecords",
      );
      await _markIndexInactive(
        collectionName: collectionName,
        documentId: documentId,
        reason: "stale_identity",
        previousUserId: uid,
      );
    }
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

  String? _uidFromIndex(Map<String, dynamic> data) {
    for (final key in ["uid", "userId", "ownerId", "profileId"]) {
      final value = data[key]?.toString();
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  bool _isActiveAccount(Map<String, dynamic> data) {
    final status = data["status"]?.toString().toLowerCase();
    return data["accountDeleted"] != true &&
        data["deleted"] != true &&
        data["anonymised"] != true &&
        data["active"] != false &&
        status != "deleted";
  }

  void _logDuplicateDiagnostic({
    required String title,
    required String source,
    required String document,
    required String field,
    required Map<String, dynamic> data,
    String? uid,
    String? extra,
  }) {
    final status = data["status"]?.toString();
    debugPrint(
      [
        "$title:",
        "source: $source",
        "document: $document",
        if (uid != null) "uid: $uid",
        "field matched: $field",
        "active: ${data["active"]}",
        "deleted: ${data["deleted"]}",
        "accountDeleted: ${data["accountDeleted"]}",
        "anonymised: ${data["anonymised"]}",
        if (status != null) "status: $status",
        if (extra != null) extra,
      ].join("\n"),
    );
  }

  void _logPhoneDuplicateCheck({
    required String normalizedPhone,
    required String source,
    required bool activeDuplicate,
  }) {
    debugPrint(
      "PHONE DUPLICATE CHECK: normalizedPhone=$normalizedPhone source=$source activeDuplicate=$activeDuplicate",
    );
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
