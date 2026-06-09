import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PostRegistrationRefreshService {
  PostRegistrationRefreshService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  Future<Map<String, dynamic>> refreshAfterRegistration(String uid) async {
    debugPrint("POST REGISTRATION REFRESH START: uid=$uid");

    await auth.currentUser?.reload();
    final refreshedUser = auth.currentUser;
    if (refreshedUser == null || refreshedUser.uid != uid) {
      throw StateError("Current Firebase Auth user is not ready.");
    }

    final profile = await waitForReadyProfile(uid);
    debugPrint("PROFILE RELOAD SUCCESS: uid=$uid role=${profile["role"]}");

    try {
      await refreshRoleSpecificData(uid: uid, profile: profile);
    } catch (error) {
      debugPrint("POST REGISTRATION SUMMARY REFRESH SKIPPED: $error");
    }
    debugPrint("PROVIDERS UPDATED: uid=$uid");
    debugPrint("DASHBOARD READY: uid=$uid");

    return profile;
  }

  Future<Map<String, dynamic>> waitForReadyProfile(String uid) async {
    Object? lastError;
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        final snapshot = await firestore
            .collection("users")
            .doc(uid)
            .get(const GetOptions(source: Source.server));
        final data = snapshot.data();
        if (snapshot.exists && data != null && isDashboardReady(data)) {
          return data;
        }
      } catch (error) {
        lastError = error;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    final fallback = await firestore.collection("users").doc(uid).get();
    final data = fallback.data();
    if (fallback.exists && data != null && isDashboardReady(data)) {
      return data;
    }

    throw StateError(
      "Profile is not ready after registration refresh. ${lastError ?? ""}",
    );
  }

  bool isDashboardReady(Map<String, dynamic> data) {
    final active = data["active"] != false &&
        data["deleted"] != true &&
        data["accountDeleted"] != true;
    final complete = data["profileComplete"] == true ||
        data["onboardingComplete"] == true ||
        data["profileCreated"] == true;
    final role = data["role"]?.toString();
    return active && complete && role != null && role.isNotEmpty;
  }

  Future<void> refreshRoleSpecificData({
    required String uid,
    required Map<String, dynamic> profile,
  }) async {
    final role = profile["role"]?.toString();
    if (role == "employer") {
      await firestore
          .collection("jobs")
          .where("ownerId", isEqualTo: uid)
          .limit(10)
          .get(const GetOptions(source: Source.server));
      return;
    }

    await refreshWorkerJobSummaries();
  }

  Future<void> refreshWorkerJobSummaries() async {
    final jobsSnapshot = await firestore
        .collection("jobs")
        .where("moderationStatus", isEqualTo: "approved")
        .where("status", whereIn: ["active", "published", "open"])
        .limit(10)
        .get(const GetOptions(source: Source.server));

    final employerIds = <String>{};
    for (final doc in jobsSnapshot.docs) {
      final data = doc.data();
      final ownerId = data["ownerId"] ??
          data["employerId"] ??
          data["createdBy"] ??
          data["userId"];
      final normalizedOwnerId = ownerId?.toString().trim();
      if (normalizedOwnerId != null && normalizedOwnerId.isNotEmpty) {
        employerIds.add(normalizedOwnerId);
      }
    }

    for (final employerId in employerIds.take(10)) {
      await firestore
          .collection("users")
          .doc(employerId)
          .get(const GetOptions(source: Source.server));
    }
  }
}
