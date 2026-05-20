import 'package:cloud_firestore/cloud_firestore.dart';

import 'notification_service.dart';

class BillingLimitException implements Exception {
  final String message;

  const BillingLimitException(this.message);
}

class BillingService {
  static const inactiveBillingMessage =
      "Choose a billing plan before posting a job. After admin approval, you can publish vacancies.";

  static const pendingBillingMessage =
      "Your billing plan request is under review. You can browse the app while waiting for approval.";

  static const postingLimitMessage =
      "You have reached your job posting limit. Please open Billing and choose a plan with more job posts.";

  static int readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? "") ?? 0;
  }

  static String formatLabel(String value) {
    return value
        .split("_")
        .where((part) => part.isNotEmpty)
        .map((part) => "${part[0].toUpperCase()}${part.substring(1)}")
        .join(" ");
  }

  static String formatDate(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      return "${date.day.toString().padLeft(2, "0")}/"
          "${date.month.toString().padLeft(2, "0")}/"
          "${date.year}";
    }
    return value?.toString() ?? "";
  }

  static Map<String, dynamic> billingFromUserData(Map<String, dynamic> data) {
    final billing = <String, dynamic>{};
    final rawBilling = data["billing"];

    if (rawBilling is Map) {
      billing.addAll(Map<String, dynamic>.from(rawBilling));
    }

    const fields = [
      "planId",
      "planName",
      "paymentMode",
      "directDebitEnabled",
      "availableJobPosts",
      "usedJobPosts",
      "activeUntil",
      "status",
      "trialActive",
      "planRequestStatus",
      "paymentRequestId",
      "trialStartedAt",
      "updatedAt",
    ];

    for (final field in fields) {
      final legacyKey = "billing.$field";
      if (billing[field] == null && data.containsKey(legacyKey)) {
        billing[field] = data[legacyKey];
      }
    }

    return billing;
  }

  static int daysRemaining(dynamic value) {
    if (value is! Timestamp) return 0;

    final remaining = value.toDate().difference(DateTime.now());
    if (remaining.isNegative) return 0;

    return (remaining.inHours / 24).ceil().clamp(0, 9999).toInt();
  }

  static String planName(QueryDocumentSnapshot plan) {
    final data = plan.data() as Map<String, dynamic>;
    return data["name"]?.toString().trim().isNotEmpty == true
        ? data["name"].toString()
        : plan.id;
  }

  static Timestamp activeUntilForPlan(Map<String, dynamic> planData) {
    final durationDays = readInt(planData["durationDays"]);
    return Timestamp.fromDate(
      DateTime.now().add(
        Duration(days: durationDays > 0 ? durationDays : 30),
      ),
    );
  }

  Future<void> assertEmployerCanPost(String employerId) async {
    final userSnap = await FirebaseFirestore.instance
        .collection("users")
        .doc(employerId)
        .get();
    final userData = userSnap.data() ?? {};
    final usedJobPosts = await countPublishedJobSlots(employerId);
    _assertEmployerCanPostFromData(
      _userDataWithUsedJobPosts(userData, usedJobPosts),
    );
  }

  Future<void> createJobWithBillingLimit({
    required String employerId,
    required Map<String, dynamic> jobData,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection("users").doc(employerId);
    final jobRef = firestore.collection("jobs").doc();
    final usedJobPosts = await countPublishedJobSlots(employerId);

    await firestore.runTransaction((transaction) async {
      final userSnap = await transaction.get(userRef);
      final userData =
          _userDataWithUsedJobPosts(userSnap.data() ?? {}, usedJobPosts);
      final role = userData["role"]?.toString() ?? "";

      if (role == "employer") {
        _assertEmployerCanPostFromData(userData);
      }

      transaction.set(jobRef, {
        ...jobData,
        "billingCounted": false,
        "createdAt": FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> approveJobAndCountSlot({
    required DocumentReference jobRef,
    required String employerId,
    required Map<String, dynamic> moderationData,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection("users").doc(employerId);
    final usedJobPosts = await countPublishedJobSlots(employerId);

    await firestore.runTransaction((transaction) async {
      final jobSnap = await transaction.get(jobRef);
      final jobData = jobSnap.data() as Map<String, dynamic>? ?? {};
      final wasApproved = jobData["moderationStatus"]?.toString() == "approved";
      final jobStatus = jobData["status"]?.toString().trim().toLowerCase();
      final wasPublished =
          jobStatus == null || jobStatus.isEmpty || jobStatus == "active";

      if (!wasApproved && employerId.isNotEmpty) {
        final userSnap = await transaction.get(userRef);
        final userData =
            _userDataWithUsedJobPosts(userSnap.data() ?? {}, usedJobPosts);
        final role = userData["role"]?.toString() ?? "";

        if (role == "employer") {
          _assertEmployerCanPostFromData(userData);
          final nextUsedJobPosts =
              wasPublished ? usedJobPosts + 1 : usedJobPosts;

          transaction.set(
            userRef,
            {
              "billing": {
                "usedJobPosts": nextUsedJobPosts,
                "updatedAt": FieldValue.serverTimestamp(),
              },
            },
            SetOptions(merge: true),
          );
        }
      }

      transaction.set(
        jobRef,
        {
          ...moderationData,
          "billingCounted": wasPublished,
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<int> countPublishedJobSlots(String employerId) async {
    if (employerId.isEmpty) return 0;

    final snapshot = await FirebaseFirestore.instance
        .collection("jobs")
        .where("ownerId", isEqualTo: employerId)
        .where("moderationStatus", isEqualTo: "approved")
        .get();

    return snapshot.docs.where((doc) {
      final data = doc.data();
      final status = data["status"]?.toString().trim().toLowerCase() ?? "";
      return status.isEmpty ||
          status == "active" ||
          status == "published" ||
          status == "open";
    }).length;
  }

  Stream<int> publishedJobSlotsStream(String employerId) {
    if (employerId.isEmpty) return Stream.value(0);

    return FirebaseFirestore.instance
        .collection("jobs")
        .where("ownerId", isEqualTo: employerId)
        .where("moderationStatus", isEqualTo: "approved")
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.where((doc) {
        final data = doc.data();
        final status = data["status"]?.toString().trim().toLowerCase() ?? "";
        return status.isEmpty ||
            status == "active" ||
            status == "published" ||
            status == "open";
      }).length;
    });
  }

  Future<void> syncUsedJobPosts(String employerId) async {
    final usedJobPosts = await countPublishedJobSlots(employerId);
    await FirebaseFirestore.instance.collection("users").doc(employerId).set(
      {
        "billing": {
          "usedJobPosts": usedJobPosts,
          "updatedAt": FieldValue.serverTimestamp(),
        },
      },
      SetOptions(merge: true),
    );
  }

  Map<String, dynamic> _userDataWithUsedJobPosts(
    Map<String, dynamic> userData,
    int usedJobPosts,
  ) {
    final next = Map<String, dynamic>.from(userData);
    final billing = billingFromUserData(next);
    billing["usedJobPosts"] = usedJobPosts;
    next["billing"] = billing;
    return next;
  }

  Future<void> createPaymentRequest({
    required String employerId,
    required QueryDocumentSnapshot plan,
    required String paymentMode,
    required Map<String, dynamic> currentBilling,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final planData = plan.data() as Map<String, dynamic>;
    final availableJobPosts = readInt(
      planData["jobPosts"] ?? planData["availableJobPosts"],
    );
    final currentStatus = currentBilling["status"]?.toString() ?? "";
    final usedJobPosts =
        currentStatus == "active" ? readInt(currentBilling["usedJobPosts"]) : 0;
    final activeUntil = activeUntilForPlan(planData);
    final selectedPlanName = planName(plan);

    await firestore.runTransaction((transaction) async {
      final userRef = firestore.collection("users").doc(employerId);
      final paymentRequestRef = firestore.collection("payment_requests").doc();

      transaction.set(paymentRequestRef, {
        "employerId": employerId,
        "planId": plan.id,
        "planName": selectedPlanName,
        "paymentMode": paymentMode,
        "status": "pending",
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });

      transaction.set(
        userRef,
        {
          "billing": {
            "planId": plan.id,
            "planName": selectedPlanName,
            "paymentMode": paymentMode,
            "directDebitEnabled": paymentMode == "direct_debit",
            "availableJobPosts": 0,
            "requestedJobPosts": availableJobPosts,
            "usedJobPosts": usedJobPosts,
            "requestedActiveUntil": activeUntil,
            "status": "pending",
            "trialActive": false,
            "planRequestStatus": "pending",
            "paymentRequestId": paymentRequestRef.id,
            "trialStartedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> updatePaymentRequestStatus(
    DocumentReference ref,
    String status,
  ) async {
    final firestore = FirebaseFirestore.instance;
    var employerId = "";
    var planName = "";

    await firestore.runTransaction((transaction) async {
      final requestSnap = await transaction.get(ref);
      final requestData =
          requestSnap.data() as Map<String, dynamic>? ?? <String, dynamic>{};
      employerId = requestData["employerId"]?.toString() ?? "";
      planName = requestData["planName"]?.toString() ?? "";
      final planId = requestData["planId"]?.toString() ?? "";

      Map<String, dynamic> planData = const <String, dynamic>{};
      if (status == "paid" && planId.isNotEmpty) {
        final planRef = firestore.collection("plans").doc(planId);
        final planSnap = await transaction.get(planRef);
        planData = planSnap.data() ?? <String, dynamic>{};
      }

      transaction.set(
        ref,
        {
          "status": status,
          "updatedAt": FieldValue.serverTimestamp(),
          if (status == "paid") "paidAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (employerId.isEmpty) return;

      final employerRef = firestore.collection("users").doc(employerId);
      if (status != "paid") {
        final inactiveStatuses = {
          "rejected",
          "cancelled",
          "failed",
        };
        transaction.set(
          employerRef,
          {
            "billing": {
              "planRequestStatus": status,
              if (inactiveStatuses.contains(status)) "status": status,
              "updatedAt": FieldValue.serverTimestamp(),
            },
          },
          SetOptions(merge: true),
        );
        return;
      }

      if (planId.isEmpty) return;

      final availableJobPosts = readInt(
        planData["jobPosts"] ?? planData["availableJobPosts"],
      );
      final activeUntil = activeUntilForPlan(planData);

      transaction.set(
        employerRef,
        {
          "billing": {
            "planId": planId,
            "planName": requestData["planName"],
            "paymentMode": requestData["paymentMode"],
            "directDebitEnabled":
                requestData["paymentMode"]?.toString() == "direct_debit",
            "availableJobPosts": availableJobPosts,
            "usedJobPosts": 0,
            "activeUntil": activeUntil,
            "status": "active",
            "trialActive": false,
            "planRequestStatus": status,
            "updatedAt": FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );
    });

    if (employerId.isNotEmpty) {
      try {
        await NotificationService().notifyEmployerBillingEvent(
          employerId: employerId,
          paymentRequestId: ref.id,
          status: status,
          planName: planName,
        );
      } catch (_) {
        // Billing status changes must not be rolled back by notification issues.
      }
    }
  }

  Map<String, dynamic> _assertEmployerCanPostFromData(
    Map<String, dynamic> userData,
  ) {
    final role = userData["role"]?.toString() ?? "";
    if (role != "employer") return {};

    final billing = billingFromUserData(userData);
    final status = billing["status"]?.toString() ?? "";
    final planRequestStatus = billing["planRequestStatus"]?.toString() ?? "";
    final availableJobPosts = readInt(billing["availableJobPosts"]);
    final usedJobPosts = readInt(billing["usedJobPosts"]);

    if (status == "pending" || planRequestStatus == "pending") {
      throw const BillingLimitException(pendingBillingMessage);
    }

    if (status != "active") {
      throw const BillingLimitException(inactiveBillingMessage);
    }

    if (usedJobPosts >= availableJobPosts) {
      throw const BillingLimitException(postingLimitMessage);
    }

    return billing;
  }
}
