import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'registration_validation_service.dart';
import 'auth_preferences_service.dart';

class AccountDeletionRequiresRecentLogin implements Exception {}

class AccountDeletionService {
  AccountDeletionService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<void> deleteCurrentAccount({bool runFullCleanup = true}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: "not-signed-in",
        message: "You need to be signed in to delete your account.",
      );
    }

    final uid = user.uid;
    final userRef = _firestore.collection("users").doc(uid);
    final snapshot = await userRef.get();
    final userData = snapshot.data() ?? <String, dynamic>{};
    final role = userData["role"]?.toString() ?? "worker";

    _ensureRecentLogin(user);
    debugPrint("ACCOUNT DELETE START uid=$uid role=$role");

    await RegistrationIdentityService(
      firestore: _firestore,
    ).releaseIdentityForDeletedUser(uid);
    debugPrint("CLEAN INDEXES SUCCESS uid=$uid");

    await _anonymiseUserDocument(userRef, role);
    debugPrint("DEACTIVATE PROFILE SUCCESS uid=$uid role=$role");

    if (runFullCleanup) {
      await _runBestEffortCleanup(uid: uid, role: role);
    }

    await AuthPreferencesService(
      auth: _auth,
      firestore: _firestore,
    ).clearBiometricLoginCredential();

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == "requires-recent-login") {
        throw AccountDeletionRequiresRecentLogin();
      }
      rethrow;
    }
    debugPrint("AUTH DELETE SUCCESS uid=$uid");

    try {
      await _auth.signOut();
    } catch (_) {
      // Firebase usually signs the user out after delete(); this is only cleanup.
    }
    debugPrint("ACCOUNT DELETE COMPLETE uid=$uid");
  }

  void _ensureRecentLogin(User user) {
    final lastSignIn = user.metadata.lastSignInTime;
    if (lastSignIn == null) return;
    final age = DateTime.now().difference(lastSignIn);
    if (age.inMinutes >= 5) {
      throw AccountDeletionRequiresRecentLogin();
    }
  }

  Future<void> _runBestEffortCleanup({
    required String uid,
    required String role,
  }) async {
    final steps = <({String label, Future<void> Function() run})>[
      (
        label: "delete_portfolio",
        run: () => _deleteUserSubcollection(uid, "portfolio"),
      ),
      (
        label: "delete_device_tokens",
        run: () => _deleteUserSubcollection(uid, "deviceTokens"),
      ),
      (label: "archive_owned_jobs", run: () => _archiveOwnedJobs(uid)),
      (label: "anonymise_owned_teams", run: () => _anonymiseOwnedTeams(uid)),
      (
        label: "inactivate_worker_applications",
        run: () => _inactivateWorkerApplications(uid),
      ),
      (
        label: "inactivate_employer_applications",
        run: () => _inactivateEmployerApplications(uid),
      ),
      (label: "cancel_billing", run: () => _cancelBilling(uid)),
      (
        label: "remove_notification_tokens",
        run: () => _removeNotificationTokens(uid),
      ),
      (
        label: "mark_user_mail_deleted",
        run: () => _markUserMailDeleted(uid, role),
      ),
      (
        label: "mark_support_requests_deleted",
        run: () => _markSupportRequestsDeleted(uid, role),
      ),
      (
        label: "mark_reports_deleted",
        run: () => _markReportsDeleted(uid, role),
      ),
      (label: "mark_chats_deleted", run: () => _markChatsDeleted(uid, role)),
    ];

    for (final step in steps) {
      try {
        await step.run();
      } catch (e) {
        debugPrint("Account deletion cleanup step ${step.label} failed: $e");
      }
    }
  }

  Future<void> _deleteUserSubcollection(String uid, String name) async {
    final snapshot =
        await _firestore.collection("users").doc(uid).collection(name).get();
    await _commitInChunks(
      snapshot.docs,
      (batch, doc) => batch.delete(doc.reference),
    );
  }

  Future<void> _anonymiseUserDocument(
    DocumentReference<Map<String, dynamic>> userRef,
    String role,
  ) {
    return userRef.set({
      "accountDeleted": true,
      "deleted": true,
      "anonymised": true,
      "active": false,
      "status": "deleted",
      "deletionReason": role == "employer"
          ? "employer_deleted_profile"
          : "worker_deleted_profile",
      "profileHidden": true,
      "profileComplete": false,
      "profileCreated": false,
      "onboardingComplete": false,
      "legalAccepted": false,
      "onboardingLegalStepComplete": false,
      "deletedAt": FieldValue.serverTimestamp(),
      "isOnline": false,
      "lastSeen": FieldValue.serverTimestamp(),
      "role": role,
      "displayName": "Deleted user",
      "name": "Deleted user",
      "companyName": role == "employer" ? "Deleted company" : "Deleted user",
      "email": FieldValue.delete(),
      "billingEmail": FieldValue.delete(),
      "billingEmailProvided": false,
      "billingEmailVerified": false,
      "phone": FieldValue.delete(),
      "phones": <String>[],
      "bio": FieldValue.delete(),
      "about": FieldValue.delete(),
      "location": FieldValue.delete(),
      "website": FieldValue.delete(),
      "contactPerson": FieldValue.delete(),
      "photo": FieldValue.delete(),
      "avatarUrl": FieldValue.delete(),
      "photoUrl": FieldValue.delete(),
      "headerImageUrl": FieldValue.delete(),
      "profileHeaderImage": FieldValue.delete(),
      "companyPhotos": <String>[],
      "portfolio": <String>[],
      "fcmToken": FieldValue.delete(),
      "fcmTokens": <String>[],
      "push": FieldValue.delete(),
      "legalAcceptedAt": FieldValue.delete(),
      "legalVersion": FieldValue.delete(),
      "acceptedPolicyVersion": FieldValue.delete(),
      "acceptedLanguage": FieldValue.delete(),
      "acceptedDocuments": FieldValue.delete(),
      "acceptedDocumentIds": FieldValue.delete(),
      "authPreferences": FieldValue.delete(),
      "settings": FieldValue.delete(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _archiveOwnedJobs(String uid) async {
    final byOwner = await _firestore
        .collection("jobs")
        .where("ownerId", isEqualTo: uid)
        .get();
    final byEmployer = await _firestore
        .collection("jobs")
        .where("employerId", isEqualTo: uid)
        .get();
    final byCreatedBy = await _firestore
        .collection("jobs")
        .where("createdBy", isEqualTo: uid)
        .get();
    final byUser = await _firestore
        .collection("jobs")
        .where("userId", isEqualTo: uid)
        .get();
    final docs = {
      for (final doc in [
        ...byOwner.docs,
        ...byEmployer.docs,
        ...byCreatedBy.docs,
        ...byUser.docs,
      ])
        doc.id: doc,
    }.values.toList();

    await _commitInChunks(docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "status": "deleted",
          "active": false,
          "visibility": "private",
          "isActive": false,
          "isDeleted": true,
          "deleted": true,
          "deletedAt": FieldValue.serverTimestamp(),
          "deletedReason": "employer_deleted_profile",
          "deletedByAccountOwner": true,
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
    debugPrint("DEACTIVATE JOBS COUNT uid=$uid count=${docs.length}");
  }

  Future<void> _anonymiseOwnedTeams(String uid) async {
    final owned = await _firestore
        .collection("teams")
        .where("ownerId", isEqualTo: uid)
        .get();
    await _commitInChunks(owned.docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "deleted": true,
          "active": false,
          "visibility": "private",
          "name": "Deleted team",
          "photo": FieldValue.delete(),
          "avatarUrl": FieldValue.delete(),
          "photos": <String>[],
          "deletedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    final memberships = await _firestore
        .collection("teams")
        .where("members", arrayContains: uid)
        .get();
    await _commitInChunks(memberships.docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "members": FieldValue.arrayRemove([uid]),
          "memberStatuses.$uid": "deleted",
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> _inactivateWorkerApplications(String uid) async {
    final byWorker = await _firestore
        .collection("applications")
        .where("workerId", isEqualTo: uid)
        .get();
    final byMember = await _firestore
        .collection("applications")
        .where("members", arrayContains: uid)
        .get();
    final docs = {
      for (final doc in [...byWorker.docs, ...byMember.docs]) doc.id: doc,
    }.values.toList();

    await _commitInChunks(docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "active": false,
          "status": "inactive",
          "inactiveReason": "worker_deleted_profile",
          "inactiveAt": FieldValue.serverTimestamp(),
          "workerDeleted": true,
          "workerName": "Deleted user",
          "workerPhoto": FieldValue.delete(),
          "unreadFor": <String>[],
          "updatedAt": FieldValue.serverTimestamp(),
          "lastStatusChangedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
    debugPrint(
        "INACTIVATE APPLICATIONS COUNT worker=$uid count=${docs.length}");
  }

  Future<void> _inactivateEmployerApplications(String uid) async {
    final byEmployer = await _firestore
        .collection("applications")
        .where("employerId", isEqualTo: uid)
        .get();
    final byOwner = await _firestore
        .collection("applications")
        .where("ownerId", isEqualTo: uid)
        .get();
    final docs = {
      for (final doc in [...byEmployer.docs, ...byOwner.docs]) doc.id: doc,
    }.values.toList();

    await _commitInChunks(docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "active": false,
          "status": "inactive",
          "inactiveReason": "employer_deleted_profile",
          "inactiveAt": FieldValue.serverTimestamp(),
          "employerDeleted": true,
          "companyName": "Deleted company",
          "unreadFor": <String>[],
          "updatedAt": FieldValue.serverTimestamp(),
          "lastStatusChangedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
    debugPrint(
        "INACTIVATE APPLICATIONS COUNT employer=$uid count=${docs.length}");
  }

  Future<void> _cancelBilling(String uid) async {
    await _firestore.collection("users").doc(uid).set({
      "billingPlanStatus": "cancelled",
      "billing.status": "cancelled",
      "billing.billingPlanStatus": "cancelled",
      "billing.cancelledAt": FieldValue.serverTimestamp(),
      "billing.updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final requests = await _firestore
        .collection("billingRequests")
        .where("employerId", isEqualTo: uid)
        .get();
    await _commitInChunks(requests.docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "status": "cancelled",
          "accountDeleted": true,
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> _removeNotificationTokens(String uid) async {
    try {
      await _firestore.collection("users").doc(uid).set({
        "fcmToken": FieldValue.delete(),
        "fcmTokens": <String>[],
        "push": FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Account deletion token cleanup skipped: $e");
    }
  }

  String _deletedParticipantLabel(String role) {
    if (role == "employer") return "Deleted employer";
    if (role == "admin") return "Deleted user";
    return "Deleted user";
  }

  Future<void> _markUserMailDeleted(String uid, String role) async {
    final sent = await _firestore
        .collection("admin_messages")
        .where("senderId", isEqualTo: uid)
        .get();
    final received = await _firestore
        .collection("admin_messages")
        .where("receiverId", isEqualTo: uid)
        .get();
    final docs = {
      for (final doc in [...sent.docs, ...received.docs]) doc.id: doc,
    }.values.toList();

    await _commitInChunks(docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "accountDeleted": true,
          "participantDeleted": true,
          "participantDeletedAt": FieldValue.serverTimestamp(),
          "participantDeletedRole": role,
          "deletedParticipantName": _deletedParticipantLabel(role),
          "deletedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> _markSupportRequestsDeleted(String uid, String role) async {
    final supportRequests = await _firestore
        .collection("support_requests")
        .where("userId", isEqualTo: uid)
        .get();
    await _commitInChunks(supportRequests.docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "accountDeleted": true,
          "senderDeleted": true,
          "participantDeleted": true,
          "participantDeletedAt": FieldValue.serverTimestamp(),
          "participantDeletedRole": role,
          "senderName": _deletedParticipantLabel(role),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> _markReportsDeleted(String uid, String role) async {
    final reports = await _firestore
        .collection("reports")
        .where("fromUserId", isEqualTo: uid)
        .get();
    await _commitInChunks(reports.docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "accountDeleted": true,
          "participantDeleted": true,
          "participantDeletedAt": FieldValue.serverTimestamp(),
          "participantDeletedRole": role,
          "fromUserName": _deletedParticipantLabel(role),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> _markChatsDeleted(String uid, String role) async {
    final byMembers = await _firestore
        .collection("chats")
        .where("members", arrayContains: uid)
        .get();
    final byParticipants = await _firestore
        .collection("chats")
        .where("participants", arrayContains: uid)
        .get();
    final docs = {
      for (final doc in [...byMembers.docs, ...byParticipants.docs])
        doc.id: doc,
    }.values.toList();

    await _commitInChunks(docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "active": false,
          "chatStatus": "inactive",
          "inactiveReason": "participant_deleted",
          "inactiveAt": FieldValue.serverTimestamp(),
          "canSendMessages": false,
          "deletedUsers": FieldValue.arrayUnion([uid]),
          "unreadFor": FieldValue.arrayRemove([uid]),
          "participantDeleted": true,
          "participantDeletedAt": FieldValue.serverTimestamp(),
          "participantDeletedRole": role,
          "deletedParticipantName": _deletedParticipantLabel(role),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
    debugPrint("INACTIVATE CHATS COUNT uid=$uid count=${docs.length}");
  }

  Future<void> _commitInChunks<T>(
    List<T> items,
    void Function(WriteBatch batch, T item) write,
  ) async {
    for (var start = 0; start < items.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450) > items.length ? items.length : start + 450;
      for (final item in items.sublist(start, end)) {
        write(batch, item);
      }
      await batch.commit();
    }
  }
}
