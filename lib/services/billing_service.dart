import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:pdf/widgets.dart' as pw;

import 'notification_service.dart';

class BillingLimitException implements Exception {
  final String message;

  const BillingLimitException(this.message);
}

class BillingApprovalException implements Exception {
  final String message;

  const BillingApprovalException(this.message);
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
      "activePlanId",
      "activePlanName",
      "paymentMode",
      "paymentMethod",
      "billingPlanStatus",
      "paymentStatus",
      "invoiceStatus",
      "directDebitEnabled",
      "directDebitMandateId",
      "mandateStatus",
      "availableJobPosts",
      "includedJobSlots",
      "usedJobPosts",
      "activeUntil",
      "nextBillingDate",
      "billingCycle",
      "monthlyPrice",
      "currency",
      "status",
      "trialActive",
      "planRequestStatus",
      "paymentRequestId",
      "lastInvoiceId",
      "lastInvoicePdfUrl",
      "trialStartedAt",
      "approvedAt",
      "approvedBy",
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

  static double readMoney(dynamic value) {
    if (value is num) return value.toDouble();
    final cleaned = value?.toString().replaceAll(RegExp(r"[^0-9.]"), "") ?? "";
    return double.tryParse(cleaned) ?? 0;
  }

  static Timestamp nextMonthlyBillingDate() {
    final now = DateTime.now();
    return Timestamp.fromDate(DateTime(now.year, now.month + 1, now.day));
  }

  static String invoiceNumber(String invoiceId) {
    final now = DateTime.now();
    return "STK-${now.year}${now.month.toString().padLeft(2, "0")}-${invoiceId.substring(0, 6).toUpperCase()}";
  }

  static bool hasDirectDebitMandate(Map<String, dynamic> data) {
    final billing = billingFromUserData(data);
    final mandateId = (billing["directDebitMandateId"] ??
            billing["mandateId"] ??
            data["directDebitMandateId"] ??
            data["mandateId"])
        ?.toString()
        .trim();
    final mandateStatus = (billing["mandateStatus"] ??
            data["mandateStatus"] ??
            data["directDebitMandateStatus"])
        ?.toString()
        .trim()
        .toLowerCase();
    return mandateId != null &&
        mandateId.isNotEmpty &&
        (mandateStatus == null ||
            mandateStatus.isEmpty ||
            mandateStatus == "active" ||
            mandateStatus == "verified" ||
            mandateStatus == "set_up");
  }

  Future<String> createManualInvoicePdf({
    required String invoiceId,
    required String invoiceNumber,
    required Map<String, dynamic> employerData,
    required Map<String, dynamic> planData,
    required String planName,
    required String currency,
    required double amount,
    required Timestamp invoiceDate,
    required Timestamp dueDate,
  }) async {
    final employerName =
        (employerData["companyName"] ?? employerData["name"] ?? "Employer")
            .toString();
    final employerAddress =
        (employerData["location"] ?? employerData["address"] ?? "").toString();
    final pdf = pw.Document();
    final invoiceDateText = formatDate(invoiceDate);
    final dueDateText = formatDate(dueDate);

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(28),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                "INVOICE",
                style: pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text("Invoice number: $invoiceNumber"),
              pw.Text("Invoice date: $invoiceDateText"),
              pw.Text("Payment due date: $dueDateText"),
              pw.SizedBox(height: 20),
              pw.Text("Seller",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text("Stroyka UK Ltd"),
              pw.Text("Company number: [TO BE ADDED]"),
              pw.Text("Registered office: [TO BE ADDED]"),
              pw.Text("VAT number: [TO BE ADDED IF VAT REGISTERED]"),
              pw.Text(
                  "VAT note: VAT is not charged unless VAT registration is confirmed."),
              pw.SizedBox(height: 20),
              pw.Text("Customer",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(employerName),
              if (employerAddress.trim().isNotEmpty) pw.Text(employerAddress),
              pw.SizedBox(height: 20),
              pw.Text("Description of service",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text("$planName monthly service plan"),
              pw.Text("Billing cycle: Monthly"),
              pw.Text(
                  "Included job slots: ${readInt(planData["jobPosts"] ?? planData["availableJobPosts"])}"),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text("Item"),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text("Amount"),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text("$planName subscription"),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child:
                            pw.Text("$currency ${amount.toStringAsFixed(2)}"),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  "Total due: $currency ${amount.toStringAsFixed(2)}",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text("Payment instructions",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text("[TO BE ADDED]"),
            ],
          ),
        ),
      ),
    );

    final bytes = await pdf.save();
    final ref =
        FirebaseStorage.instance.ref().child("billing_invoices/$invoiceId.pdf");
    await ref.putData(
      bytes,
      SettableMetadata(contentType: "application/pdf"),
    );
    return ref.getDownloadURL();
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
    var notificationStatus = status;
    String? invoiceId;
    String? invoicePdfUrl;
    String? invoiceNo;
    Map<String, dynamic> preloadedRequest = const <String, dynamic>{};
    Map<String, dynamic> preloadedPlan = const <String, dynamic>{};
    Map<String, dynamic> preloadedEmployer = const <String, dynamic>{};

    if (status == "approved") {
      final requestSnap = await ref.get();
      preloadedRequest =
          requestSnap.data() as Map<String, dynamic>? ?? <String, dynamic>{};
      employerId = preloadedRequest["employerId"]?.toString() ?? "";
      final planId = preloadedRequest["planId"]?.toString() ?? "";
      if (employerId.isEmpty || planId.isEmpty) {
        throw const BillingApprovalException(
          "Billing request is missing employer or plan details.",
        );
      }

      final employerSnap =
          await firestore.collection("users").doc(employerId).get();
      preloadedEmployer = employerSnap.data() ?? <String, dynamic>{};

      final paymentMode =
          preloadedRequest["paymentMode"]?.toString() ?? "manual_invoice";
      if (paymentMode == "direct_debit" &&
          !hasDirectDebitMandate(preloadedEmployer)) {
        throw const BillingApprovalException(
          "Direct Debit mandate is not set up.",
        );
      }

      final planSnap = await firestore.collection("plans").doc(planId).get();
      preloadedPlan = planSnap.data() ?? <String, dynamic>{};

      if (paymentMode == "manual_invoice") {
        final invoiceRef = firestore.collection("invoices").doc();
        invoiceId = invoiceRef.id;
        invoiceNo = invoiceNumber(invoiceRef.id);
        final invoiceDate = Timestamp.now();
        final dueDate = Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 14)),
        );
        final amount = readMoney(preloadedPlan["price"]);
        final currency = preloadedPlan["currency"]?.toString() ?? "GBP";
        planName = preloadedRequest["planName"]?.toString() ??
            preloadedPlan["name"]?.toString() ??
            "Selected plan";

        invoicePdfUrl = await createManualInvoicePdf(
          invoiceId: invoiceRef.id,
          invoiceNumber: invoiceNo,
          employerData: preloadedEmployer,
          planData: preloadedPlan,
          planName: planName,
          currency: currency,
          amount: amount,
          invoiceDate: invoiceDate,
          dueDate: dueDate,
        );
      }
    }

    await firestore.runTransaction((transaction) async {
      final requestSnap = await transaction.get(ref);
      final requestData =
          requestSnap.data() as Map<String, dynamic>? ?? <String, dynamic>{};
      employerId = requestData["employerId"]?.toString() ?? "";
      planName = requestData["planName"]?.toString() ?? "";
      final planId = requestData["planId"]?.toString() ?? "";

      Map<String, dynamic> planData = const <String, dynamic>{};
      Map<String, dynamic> employerData = const <String, dynamic>{};
      final employerRef = firestore.collection("users").doc(employerId);
      if (employerId.isNotEmpty) {
        final employerSnap = await transaction.get(employerRef);
        employerData = employerSnap.data() ?? <String, dynamic>{};
      }
      if (status == "approved" && planId.isNotEmpty) {
        final planRef = firestore.collection("plans").doc(planId);
        final planSnap = await transaction.get(planRef);
        planData = planSnap.data() ?? <String, dynamic>{};
      }

      final paymentMode =
          requestData["paymentMode"]?.toString() ?? "manual_invoice";
      if (status == "approved" &&
          paymentMode == "direct_debit" &&
          !hasDirectDebitMandate(employerData)) {
        throw const BillingApprovalException(
          "Direct Debit mandate is not set up.",
        );
      }

      transaction.set(
        ref,
        {
          "status": status,
          "billingPlanStatus": status,
          "paymentMethod": paymentMode,
          "paymentStatus": status == "approved" ? "unpaid" : "pending",
          if (paymentMode == "manual_invoice" && status == "approved")
            "invoiceStatus": "issued",
          "updatedAt": FieldValue.serverTimestamp(),
          if (status == "approved") "approvedAt": FieldValue.serverTimestamp(),
          if (status == "approved")
            "approvedBy": FirebaseAuth.instance.currentUser?.uid,
          if (invoiceId != null) "invoiceId": invoiceId,
          if (invoiceNo != null) "invoiceNumber": invoiceNo,
          if (invoicePdfUrl != null) "invoicePdfUrl": invoicePdfUrl,
        },
        SetOptions(merge: true),
      );

      if (employerId.isEmpty) return;

      if (status != "approved") {
        final inactiveStatuses = {
          "rejected",
          "cancelled",
          "failed",
          "on_hold",
        };
        transaction.set(
          employerRef,
          {
            "billing": {
              "planRequestStatus": status,
              "billingPlanStatus": status,
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
      final nextBillingDate = nextMonthlyBillingDate();
      final amount = readMoney(planData["price"]);
      final currency = planData["currency"]?.toString() ?? "GBP";
      final activePlanName =
          requestData["planName"] ?? planData["name"] ?? planName;

      transaction.set(
        employerRef,
        {
          "billing": {
            "planId": planId,
            "planName": activePlanName,
            "activePlanId": planId,
            "activePlanName": activePlanName,
            "paymentMode": paymentMode,
            "paymentMethod": paymentMode,
            "directDebitEnabled": paymentMode == "direct_debit",
            "availableJobPosts": availableJobPosts,
            "includedJobSlots": availableJobPosts,
            "usedJobPosts": 0,
            "monthlyPrice": amount,
            "currency": currency,
            "billingCycle": "monthly",
            "nextBillingDate": nextBillingDate,
            "status": "active",
            "billingPlanStatus": "approved",
            "paymentStatus":
                paymentMode == "manual_invoice" ? "unpaid" : "pending",
            if (paymentMode == "manual_invoice") "invoiceStatus": "issued",
            if (paymentMode == "direct_debit") "mandateStatus": "active",
            "trialActive": false,
            "planRequestStatus": "approved",
            "approvedAt": FieldValue.serverTimestamp(),
            "approvedBy": FirebaseAuth.instance.currentUser?.uid,
            if (invoiceId != null) "lastInvoiceId": invoiceId,
            if (invoicePdfUrl != null) "lastInvoicePdfUrl": invoicePdfUrl,
            "updatedAt": FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );

      if (invoiceId != null) {
        final invoiceRef = firestore.collection("invoices").doc(invoiceId);
        final invoiceDate = Timestamp.now();
        final dueDate = Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 14)),
        );
        transaction.set(invoiceRef, {
          "invoiceId": invoiceId,
          "invoiceNumber": invoiceNo,
          "employerId": employerId,
          "paymentRequestId": ref.id,
          "planId": planId,
          "planName": activePlanName,
          "amount": amount,
          "currency": currency,
          "status": "issued",
          "paymentStatus": "unpaid",
          "invoiceStatus": "issued",
          "billingCycle": "monthly",
          "invoiceDate": invoiceDate,
          "dueDate": dueDate,
          "pdfUrl": invoicePdfUrl,
          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        });
        transaction.set(
          employerRef.collection("billing").doc("currentPlan"),
          {
            "activePlanId": planId,
            "activePlanName": activePlanName,
            "billingPlanStatus": "approved",
            "paymentMethod": paymentMode,
            "paymentStatus": "unpaid",
            "invoiceStatus": "issued",
            "includedJobSlots": availableJobPosts,
            "monthlyPrice": amount,
            "currency": currency,
            "billingCycle": "monthly",
            "nextBillingDate": nextBillingDate,
            "lastInvoiceId": invoiceId,
            "lastInvoicePdfUrl": invoicePdfUrl,
            "updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        transaction.set(
          employerRef
              .collection("billing")
              .doc("currentPlan")
              .collection("invoices")
              .doc(invoiceId),
          {
            "invoiceId": invoiceId,
            "invoiceNumber": invoiceNo,
            "status": "issued",
            "paymentStatus": "unpaid",
            "pdfUrl": invoicePdfUrl,
            "amount": amount,
            "currency": currency,
            "invoiceDate": invoiceDate,
            "dueDate": dueDate,
            "createdAt": FieldValue.serverTimestamp(),
          },
        );
      }
    });

    if (status == "approved" && invoiceId != null) {
      notificationStatus = "invoice_issued";
    }
    if (employerId.isNotEmpty) {
      try {
        await NotificationService().notifyEmployerBillingEvent(
          employerId: employerId,
          paymentRequestId: ref.id,
          status: notificationStatus,
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
    final billingPlanStatus = billing["billingPlanStatus"]?.toString() ?? "";
    final planRequestStatus = billing["planRequestStatus"]?.toString() ?? "";
    final availableJobPosts = readInt(billing["availableJobPosts"]);
    final usedJobPosts = readInt(billing["usedJobPosts"]);

    if (status == "pending" ||
        billingPlanStatus == "pending" ||
        planRequestStatus == "pending") {
      throw const BillingLimitException(pendingBillingMessage);
    }

    if (status != "active" && billingPlanStatus != "approved") {
      throw const BillingLimitException(inactiveBillingMessage);
    }

    if (usedJobPosts >= availableJobPosts) {
      throw const BillingLimitException(postingLimitMessage);
    }

    return billing;
  }
}
