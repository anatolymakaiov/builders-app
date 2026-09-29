import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'registration_validation_service.dart';
import 'registration_wizard_steps.dart';

/// Rules shared by the mobile and web registration entry points.
class RegistrationLifecycle {
  static bool isComplete(Map<String, dynamic> data) {
    if (data['profileComplete'] == true ||
        data['onboardingComplete'] == true ||
        data['profileCreated'] == true) {
      return true;
    }
    if (data.containsKey('profileComplete') ||
        data.containsKey('onboardingComplete') ||
        data.containsKey('profileCreated')) {
      return false;
    }
    if (data['draft'] == true ||
        data['pendingRegistration'] == true ||
        data['registrationFormComplete'] == false) {
      return false;
    }
    final role = data['role'];
    return role == 'employer'
        ? (data['companyName']?.toString().trim().isNotEmpty ?? false)
        : (data['name']?.toString().trim().isNotEmpty ?? false);
  }

  static List<ProfileCompletionStep> completionSteps(String role) => [
        ProfileCompletionStep.emailVerification,
        if (role == 'employer') ProfileCompletionStep.phoneVerification,
        ProfileCompletionStep.optionalDetails,
      ];

  static int previousCompletionStep(int step) => step == 0 ? -1 : step - 1;

  static bool canComplete({
    required String role,
    required bool emailVerified,
    required bool phoneVerified,
  }) =>
      emailVerified && (role != 'employer' || phoneVerified);

  static bool canDiscard(Map<String, dynamic>? profile) =>
      profile == null || !isComplete(profile);

  static bool requiresEmailChangeVerification({
    required bool creatingProfile,
    required String currentEmail,
    required String loadedEmail,
  }) =>
      !creatingProfile &&
      RegistrationValidationService.normalizeEmail(currentEmail) !=
          RegistrationValidationService.normalizeEmail(loadedEmail);

  static Map<String, Set<String>> cancellationIndexKeys(
      Map<String, dynamic>? profile, Map<String, dynamic>? draft) {
    final email = <String>{};
    final phone = <String>{};
    for (final data in [profile, draft]) {
      if (data == null) continue;
      for (final key in ['email', 'normalizedEmail', 'billingEmail']) {
        final value = RegistrationValidationService.normalizeEmail(
            data[key]?.toString() ?? '');
        if (value.isNotEmpty) email.add(value);
      }
      for (final key in ['phone', 'normalizedPhone']) {
        final value = RegistrationValidationService.normalizePhone(
            data[key]?.toString() ?? '');
        if (value.isNotEmpty) phone.add(value);
      }
    }
    return {'email': email, 'phone': phone};
  }

  static int resumeStep(Map<String, dynamic> data, String role) {
    if (role != 'worker' && role != 'employer') {
      return RegistrationWizardStep.accountType.index;
    }
    final storedName =
        (data['registrationName'] ?? data['name'] ?? '').toString();
    final parts = storedName.trim().split(RegExp(r'\s+'));
    final firstName = (data['registrationFirstName'] ?? parts.first).toString();
    final lastName = (data['registrationLastName'] ??
            (parts.length > 1 ? parts.skip(1).join(' ') : ''))
        .toString();
    final trade =
        (data['registrationPosition'] ?? data['trade'] ?? '').toString();
    final company =
        (data['registrationCompanyName'] ?? data['companyName'] ?? '')
            .toString();
    for (final step in RegistrationWizardStep.values) {
      if (step == RegistrationWizardStep.accountType) continue;
      if (step == RegistrationWizardStep.credentials) break;
      final error = RegistrationWizardSteps.validate(
        step,
        role: role,
        firstName: firstName,
        lastName: lastName,
        trade: trade,
        companyName: company,
        addressLine1:
            (data['addressLine1'] ?? data['location'] ?? '').toString(),
        townCity: (data['townCity'] ?? data['city'] ?? '').toString(),
        postcode: (data['postcode'] ?? '').toString(),
        country: (data['country'] ?? 'United Kingdom').toString(),
        email: (data['email'] ?? '').toString(),
        phone: (data['phone'] ?? '').toString(),
      );
      if (error != null) return step.index;
    }
    return RegistrationWizardStep.credentials.index;
  }

  /// Discards only an explicitly unfinished account. Auth identity is retained:
  /// it may already be linked to another provider/account and can be reused.
  static Future<void> cancel({
    required User user,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(user.uid);
    final draftRef = db.collection('pending_registrations').doc(user.uid);
    final draftLegal = await draftRef.collection('legalAcceptances').get();
    final userLegal = await userRef.collection('legalAcceptances').get();
    final identities = await db.runTransaction((transaction) async {
      final userDoc = await transaction.get(userRef);
      final draftDoc = await transaction.get(draftRef);
      if (!canDiscard(userDoc.data())) {
        throw StateError('Completed accounts cannot be discarded.');
      }
      for (final legal in [...draftLegal.docs, ...userLegal.docs]) {
        transaction.delete(legal.reference);
      }
      transaction.delete(draftRef);
      if (userDoc.exists) transaction.delete(userRef);
      return cancellationIndexKeys(userDoc.data(), draftDoc.data());
    });

    // Legacy incomplete profiles can own lookup indexes. Release them after
    // the required draft deletion, so an index failure cannot trap sign-out.
    for (final entry in {
      'emailIndex': identities['email']!,
      'registrationEmailIndex': identities['email']!,
      'phoneIndex': identities['phone']!,
      'registrationPhoneIndex': identities['phone']!,
    }.entries) {
      for (final value in entry.value) {
        final indexRef = db.collection(entry.key).doc(value);
        try {
          await db.runTransaction((transaction) async {
            final index = await transaction.get(indexRef);
            final owner = index.data()?['uid'] ?? index.data()?['userId'];
            if (index.exists && owner == user.uid) {
              transaction.update(indexRef, {
                'active': false,
                'deleted': true,
                'stale': true,
                'previousUserId': user.uid,
                'cleanupReason': 'registration_cancelled',
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
          });
        } catch (error) {
          debugPrint('REGISTRATION_DISCARD_INDEX_CLEANUP_ERROR '
              'collection=${entry.key} error=$error');
        }
      }
    }
    RegistrationValidationService.clearPending(user.email ?? '');
    for (final email in identities['email']!) {
      RegistrationValidationService.clearPending(email);
    }
    await (auth ?? FirebaseAuth.instance).signOut();
  }

  /// Publish once per UID, copying legal acceptance and removing the draft
  /// atomically. A retry cannot overwrite an already completed profile.
  static Future<void> finalize({
    required String uid,
    required Map<String, dynamic> profileData,
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(uid);
    final draftRef = db.collection('pending_registrations').doc(uid);
    final legalDocs = await draftRef.collection('legalAcceptances').get();
    await db.runTransaction((transaction) async {
      final existing = await transaction.get(userRef);
      if (!existing.exists || !isComplete(existing.data()!)) {
        transaction.set(userRef, profileData, SetOptions(merge: true));
      }
      for (final legal in legalDocs.docs) {
        transaction.set(userRef.collection('legalAcceptances').doc(legal.id),
            legal.data(), SetOptions(merge: true));
        transaction.delete(legal.reference);
      }
      transaction.delete(draftRef);
    });
  }
}

/// Invalidates results from earlier asynchronous identity checks after edits.
class RegistrationInputRevision {
  int _revision = 0;
  int get value => _revision;
  void changed() => _revision++;
  bool isCurrent(int revision) => revision == _revision;
}
