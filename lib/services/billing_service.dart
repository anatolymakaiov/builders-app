import 'package:cloud_firestore/cloud_firestore.dart';

class BillingLimitException implements Exception {
  final String message;

  const BillingLimitException(this.message);
}

class BillingService {
  static const inactiveBillingMessage =
      "Your billing plan is not active. Please open Billing and choose or activate a plan before posting a job.";

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
    _assertEmployerCanPostFromData(userData);
  }

  Future<void> createJobWithBillingLimit({
    required String employerId,
    required Map<String, dynamic> jobData,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection("users").doc(employerId);
    final jobRef = firestore.collection("jobs").doc();

    await firestore.runTransaction((transaction) async {
      final userSnap = await transaction.get(userRef);
      final userData = userSnap.data() ?? {};
      final role = userData["role"]?.toString() ?? "";

      if (role == "employer") {
        final billing = _assertEmployerCanPostFromData(userData);
        final usedJobPosts = readInt(billing["usedJobPosts"]);

        transaction.set(
          userRef,
          {
            "billing.usedJobPosts": usedJobPosts + 1,
            "billing.updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      transaction.set(jobRef, {
        ...jobData,
        "createdAt": FieldValue.serverTimestamp(),
      });
    });
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
          "billing.planId": plan.id,
          "billing.planName": selectedPlanName,
          "billing.paymentMode": paymentMode,
          "billing.directDebitEnabled": paymentMode == "direct_debit",
          "billing.availableJobPosts": availableJobPosts,
          "billing.usedJobPosts": usedJobPosts,
          "billing.activeUntil": activeUntil,
          "billing.status": "active",
          "billing.trialActive": true,
          "billing.planRequestStatus": "pending",
          "billing.paymentRequestId": paymentRequestRef.id,
          "billing.trialStartedAt": FieldValue.serverTimestamp(),
          "billing.updatedAt": FieldValue.serverTimestamp(),
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

    await firestore.runTransaction((transaction) async {
      final requestSnap = await transaction.get(ref);
      final requestData =
          requestSnap.data() as Map<String, dynamic>? ?? <String, dynamic>{};

      transaction.set(
        ref,
        {
          "status": status,
          "updatedAt": FieldValue.serverTimestamp(),
          if (status == "paid") "paidAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      final employerId = requestData["employerId"]?.toString() ?? "";
      final planId = requestData["planId"]?.toString() ?? "";
      if (employerId.isEmpty) return;

      final employerRef = firestore.collection("users").doc(employerId);
      if (status != "paid") {
        transaction.set(
          employerRef,
          {
            "billing.planRequestStatus": status,
            "billing.updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return;
      }

      if (planId.isEmpty) return;

      final planRef = firestore.collection("plans").doc(planId);
      final planSnap = await transaction.get(planRef);
      final planData = planSnap.data() ?? <String, dynamic>{};

      final availableJobPosts = readInt(
        planData["jobPosts"] ?? planData["availableJobPosts"],
      );
      final activeUntil = activeUntilForPlan(planData);

      transaction.set(
        employerRef,
        {
          "billing.planId": planId,
          "billing.planName": requestData["planName"],
          "billing.paymentMode": requestData["paymentMode"],
          "billing.directDebitEnabled":
              requestData["paymentMode"]?.toString() == "direct_debit",
          "billing.availableJobPosts": availableJobPosts,
          "billing.usedJobPosts": 0,
          "billing.activeUntil": activeUntil,
          "billing.status": "active",
          "billing.trialActive": false,
          "billing.planRequestStatus": status,
          "billing.updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Map<String, dynamic> _assertEmployerCanPostFromData(
    Map<String, dynamic> userData,
  ) {
    final role = userData["role"]?.toString() ?? "";
    if (role != "employer") return {};

    final billing = Map<String, dynamic>.from(userData["billing"] ?? {});
    final status = billing["status"]?.toString() ?? "";
    final availableJobPosts = readInt(billing["availableJobPosts"]);
    final usedJobPosts = readInt(billing["usedJobPosts"]);

    if (status != "active") {
      throw const BillingLimitException(inactiveBillingMessage);
    }

    if (usedJobPosts >= availableJobPosts) {
      throw const BillingLimitException(postingLimitMessage);
    }

    return billing;
  }
}
