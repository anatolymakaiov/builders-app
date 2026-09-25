import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/legal_documents.dart';
import 'moderation_hold_service.dart';
import 'registration_validation_service.dart';
import 'registration_lifecycle.dart';
import 'social_auth_service.dart';

enum AuthSessionDestination { registration, legal, profile, home, deleted }

class AuthSessionResolution {
  const AuthSessionResolution({
    required this.destination,
    required this.role,
    required this.profile,
    this.hasDraft = false,
  });

  final AuthSessionDestination destination;
  final String role;
  final Map<String, dynamic> profile;
  final bool hasDraft;
}

class AuthSessionResolver {
  AuthSessionResolver({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static AuthSessionResolution classify({
    Map<String, dynamic>? profile,
    Map<String, dynamic>? draft,
    bool Function(Map<String, dynamic>, String)? hasAcceptedLegal,
  }) {
    final data = profile != null &&
            draft != null &&
            !RegistrationLifecycle.isComplete(profile)
        ? <String, dynamic>{...profile, ...draft}
        : profile ?? draft ?? <String, dynamic>{};
    final role = switch (data['role']?.toString()) {
      'admin' => 'admin',
      'employer' => 'employer',
      _ => 'worker',
    };
    final acceptedLegal = hasAcceptedLegal ??
        (Map<String, dynamic> value, String valueRole) =>
            LegalDocuments.hasAcceptedCurrentVersion(value, valueRole);

    if (profile != null &&
        (profile['accountDeleted'] == true || profile['deleted'] == true)) {
      return AuthSessionResolution(
        destination: AuthSessionDestination.deleted,
        role: role,
        profile: data,
      );
    }
    if ((profile == null && draft?['registrationFormComplete'] == false) ||
        (profile != null &&
            !RegistrationLifecycle.isComplete(profile) &&
            (draft?['registrationFormComplete'] == false ||
                profile['registrationFormComplete'] == false))) {
      return AuthSessionResolution(
        destination: AuthSessionDestination.registration,
        role: role,
        profile: data,
        hasDraft: true,
      );
    }
    if (profile == null && draft == null) {
      return AuthSessionResolution(
        destination: AuthSessionDestination.registration,
        role: role,
        profile: data,
      );
    }
    final legalAccepted = acceptedLegal(data, role) ||
        (profile != null && acceptedLegal(profile, role)) ||
        (draft != null && acceptedLegal(draft, role));
    if (role != 'admin' && !legalAccepted) {
      return AuthSessionResolution(
        destination: AuthSessionDestination.legal,
        role: role,
        profile: data,
        hasDraft: draft != null,
      );
    }
    final active = profile?['active'] != false ||
        ModerationHoldService.isProfileHeld(profile);
    final complete =
        profile != null && RegistrationLifecycle.isComplete(profile);
    return AuthSessionResolution(
      destination: active && (complete || role == 'admin' && profile != null)
          ? AuthSessionDestination.home
          : AuthSessionDestination.profile,
      role: role,
      profile: data,
      hasDraft: draft != null,
    );
  }

  Future<AuthSessionResolution> resolve(User user) async {
    final profileSnapshot =
        await _firestore.collection('users').doc(user.uid).get();
    if (profileSnapshot.exists) {
      final profile = profileSnapshot.data()!;
      if (RegistrationLifecycle.isComplete(profile)) {
        return classify(profile: profile);
      }
      final draft = await _firestore
          .collection('pending_registrations')
          .doc(user.uid)
          .get();
      return classify(profile: profile, draft: draft.data());
    }

    final draftRef =
        _firestore.collection('pending_registrations').doc(user.uid);
    final draftSnapshot = await draftRef.get();
    if (draftSnapshot.exists) {
      return classify(draft: draftSnapshot.data());
    }

    final pending = RegistrationValidationService.pendingForEmail(user.email);
    final fallback = PendingRegistrationDetails(
      email: RegistrationValidationService.normalizeEmail(user.email ?? ''),
      role: 'worker',
      registrationName: user.displayName?.trim() ?? '',
      phone: '',
      normalizedPhone: '',
    );
    final provider = SocialAuthService.providerFromIds(
      user.providerData.map((identity) => identity.providerId),
    );
    final draft = {
      ...(pending ?? fallback).toUserDocument(),
      if (provider != null) 'authMethod': provider.name,
      'uid': user.uid,
      'active': false,
      'draft': true,
      'pendingRegistration': true,
      'registrationFormComplete': pending != null,
    };
    await draftRef.set(draft, SetOptions(merge: true));
    RegistrationValidationService.clearPending(user.email ?? '');
    return classify(draft: draft);
  }
}
