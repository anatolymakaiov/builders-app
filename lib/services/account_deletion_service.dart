import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AccountDeletionRequiresRecentLogin implements Exception {}

class AccountDeletionService {
  AccountDeletionService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<void> deleteCurrentAccount() async {
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

    await _runFirestoreCleanup(uid: uid, role: role, userRef: userRef);

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == "requires-recent-login") {
        await _auth.signOut();
        throw AccountDeletionRequiresRecentLogin();
      }
      rethrow;
    }

    try {
      await _auth.signOut();
    } catch (_) {
      // Firebase usually signs the user out after delete(); this is only cleanup.
    }
  }

  Future<void> _runFirestoreCleanup({
    required String uid,
    required String role,
    required DocumentReference<Map<String, dynamic>> userRef,
  }) async {
    await _deleteUserSubcollection(uid, "portfolio");
    await _deleteUserSubcollection(uid, "legalAcceptances");
    await _deleteUserSubcollection(uid, "deviceTokens");

    await _anonymiseUserDocument(userRef, role);
    await _archiveOwnedJobs(uid);
    await _anonymiseOwnedTeams(uid);
    await _withdrawWorkerApplications(uid);
    await _closeEmployerApplications(uid);
    await _cancelBilling(uid);
    await _removeNotificationTokens(uid);
    await _markUserMailDeleted(uid);
    await _markSupportRequestsDeleted(uid);
    await _markChatsDeleted(uid);
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
      "active": false,
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
    final snapshot = await _firestore
        .collection("jobs")
        .where("ownerId", isEqualTo: uid)
        .get();
    await _commitInChunks(snapshot.docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "status": "deleted",
          "visibility": "private",
          "isActive": false,
          "isDeleted": true,
          "deletedAt": FieldValue.serverTimestamp(),
          "deletedByAccountOwner": true,
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
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

  Future<void> _withdrawWorkerApplications(String uid) async {
    final snapshot = await _firestore
        .collection("applications")
        .where("workerId", isEqualTo: uid)
        .get();
    await _commitInChunks(snapshot.docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "status": "withdrawn",
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
  }

  Future<void> _closeEmployerApplications(String uid) async {
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
          "status": "closed",
          "employerDeleted": true,
          "companyName": "Deleted company",
          "unreadFor": <String>[],
          "updatedAt": FieldValue.serverTimestamp(),
          "lastStatusChangedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
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

  Future<void> _markUserMailDeleted(String uid) async {
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
          "deletedBySender": true,
          "deletedByReceiver": true,
          "accountDeleted": true,
          "deletedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> _markSupportRequestsDeleted(String uid) async {
    final sent = await _firestore
        .collection("supportRequests")
        .where("userId", isEqualTo: uid)
        .get();
    await _commitInChunks(sent.docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "accountDeleted": true,
          "senderDeleted": true,
          "senderName": "Deleted user",
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> _markChatsDeleted(String uid) async {
    final snapshot = await _firestore
        .collection("chats")
        .where("members", arrayContains: uid)
        .get();
    await _commitInChunks(snapshot.docs, (batch, doc) {
      batch.set(
        doc.reference,
        {
          "deletedUsers": FieldValue.arrayUnion([uid]),
          "unreadFor": FieldValue.arrayRemove([uid]),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
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
