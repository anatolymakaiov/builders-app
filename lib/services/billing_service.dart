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
      "billingEmail",
      "billingEmailVerified",
      "billingEmailVerifiedAt",
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
      "trialStatus",
      "trialEndsAt",
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

  static DateTime addOneMonth(DateTime date) {
    return DateTime(
      date.year,
      date.month + 1,
      date.day,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }

  static String billingEmailFromUserData(Map<String, dynamic> data) {
    final billing = billingFromUserData(data);
    final email =
        (billing["billingEmail"] ?? data["billingEmail"] ?? data["email"] ?? "")
            .toString()
            .trim();
    return email;
  }

  static bool isValidEmail(String email) {
    return RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$").hasMatch(email.trim());
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
    final billing = billingFromUserData(employerData);
    final invoiceDetails = billing["invoiceDetails"] is Map
        ? Map<String, dynamic>.from(billing["invoiceDetails"] as Map)
        : employerData["invoiceDetails"] is Map
            ? Map<String, dynamic>.from(employerData["invoiceDetails"] as Map)
            : <String, dynamic>{};
    final employerName = (invoiceDetails["legalCompanyName"] ??
            employerData["companyName"] ??
            employerData["name"] ??
            "Employer")
        .toString();
    final tradingName = invoiceDetails["tradingName"]?.toString() ?? "";
    final companyNumber =
        invoiceDetails["companyRegistrationNumber"]?.toString() ?? "";
    final employerAddress = (invoiceDetails["billingAddress"] ??
            employerData["location"] ??
            employerData["address"] ??
            "")
        .toString();
    final registeredOffice =
        invoiceDetails["registeredOfficeAddress"]?.toString() ?? "";
    final vatNumber = invoiceDetails["vatNumber"]?.toString() ?? "";
    final purchaseOrder =
        invoiceDetails["purchaseOrderReference"]?.toString() ?? "";
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
              if (tradingName.trim().isNotEmpty)
                pw.Text("Trading name: $tradingName"),
              if (companyNumber.trim().isNotEmpty)
                pw.Text("Company number: $companyNumber"),
              if (employerAddress.trim().isNotEmpty) pw.Text(employerAddress),
              if (registeredOffice.trim().isNotEmpty)
                pw.Text("Registered office: $registeredOffice"),
              if (vatNumber.trim().isNotEmpty)
                pw.Text("VAT number: $vatNumber"),
              if (purchaseOrder.trim().isNotEmpty)
                pw.Text("PO/reference: $purchaseOrder"),
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
    final invoiceDetails = currentBilling["invoiceDetails"] is Map
        ? Map<String, dynamic>.from(currentBilling["invoiceDetails"] as Map)
        : <String, dynamic>{};

    await firestore.runTransaction((transaction) async {
      final userRef = firestore.collection("users").doc(employerId);
      final paymentRequestRef = firestore.collection("payment_requests").doc();

      transaction.set(paymentRequestRef, {
        "employerId": employerId,
        "planId": plan.id,
        "planName": selectedPlanName,
        "paymentMode": paymentMode,
        "billingEmail": billingEmailFromUserData(
          {"billing": currentBilling},
        ),
        "billingEmailVerified": currentBilling["billingEmailVerified"] == true,
        if (paymentMode == "manual_invoice") "invoiceDetails": invoiceDetails,
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
            "billingEmail": billingEmailFromUserData(
              {"billing": currentBilling},
            ),
            "billingEmailVerified":
                currentBilling["billingEmailVerified"] == true,
            if (paymentMode == "manual_invoice")
              "invoiceDetails": invoiceDetails,
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

  void _writeBillingSchedules({
    required Transaction transaction,
    required FirebaseFirestore firestore,
    required String employerId,
    required String paymentRequestId,
    required String planId,
    required String planName,
    required String paymentMode,
    required String billingEmail,
    required double amount,
    required String currency,
    required DateTime nextBillingDate,
  }) {
    final scheduleBase = {
      "employerId": employerId,
      "paymentRequestId": paymentRequestId,
      "planId": planId,
      "planName": planName,
      "paymentMode": paymentMode,
      "billingEmail": billingEmail,
      "amount": amount,
      "currency": currency,
      "nextBillingDate": Timestamp.fromDate(nextBillingDate),
      "status": "pending",
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    };

    final reminder10Days = nextBillingDate.subtract(const Duration(days: 10));
    final reminder5Days = nextBillingDate.subtract(const Duration(days: 5));
    final reminder2Days = nextBillingDate.subtract(const Duration(days: 2));
    final overdueCheck = nextBillingDate.add(const Duration(days: 1));

    if (paymentMode == "manual_invoice") {
      transaction.set(
        firestore.collection("billing_schedules").doc(),
        {
          ...scheduleBase,
          "type": "manual_invoice_issue",
          "scheduledAt": Timestamp.fromDate(reminder10Days),
          "dueDate": Timestamp.fromDate(nextBillingDate),
          "emailDeliveryRequired": true,
          "message":
              "Issue invoice and email it to $billingEmail 10 days before the subscription due date.",
        },
      );
      transaction.set(
        firestore.collection("billing_schedules").doc(),
        {
          ...scheduleBase,
          "type": "manual_invoice_due_reminder_5_days",
          "scheduledAt": Timestamp.fromDate(reminder5Days),
          "dueDate": Timestamp.fromDate(nextBillingDate),
          "emailDeliveryRequired": true,
          "message": "Send a 5 day invoice payment reminder to $billingEmail.",
        },
      );
      transaction.set(
        firestore.collection("billing_schedules").doc(),
        {
          ...scheduleBase,
          "type": "manual_invoice_due_reminder_2_days",
          "scheduledAt": Timestamp.fromDate(reminder2Days),
          "dueDate": Timestamp.fromDate(nextBillingDate),
          "emailDeliveryRequired": true,
          "message": "Send a 2 day invoice payment reminder to $billingEmail.",
        },
      );
      transaction.set(
        firestore.collection("billing_schedules").doc(),
        {
          ...scheduleBase,
          "type": "manual_invoice_overdue_check",
          "scheduledAt": Timestamp.fromDate(overdueCheck),
          "dueDate": Timestamp.fromDate(nextBillingDate),
          "emailDeliveryRequired": true,
          "message":
              "Check whether the invoice remains unpaid after the due date and notify the employer if overdue.",
        },
      );
      return;
    }

    if (paymentMode == "direct_debit" || paymentMode == "card") {
      transaction.set(
        firestore.collection("billing_schedules").doc(),
        {
          ...scheduleBase,
          "type": "${paymentMode}_reminder_10_days",
          "scheduledAt": Timestamp.fromDate(reminder10Days),
          "emailDeliveryRequired": false,
          "message":
              "Your subscription payment is scheduled for ${formatDate(Timestamp.fromDate(nextBillingDate))}. Please ensure your payment method remains active.",
        },
      );
      transaction.set(
        firestore.collection("billing_schedules").doc(),
        {
          ...scheduleBase,
          "type": "${paymentMode}_reminder_2_days",
          "scheduledAt": Timestamp.fromDate(reminder2Days),
          "emailDeliveryRequired": false,
          "message":
              "Your subscription payment is scheduled in 2 days. Please ensure your payment method remains active.",
        },
      );
      transaction.set(
        firestore.collection("billing_schedules").doc(),
        {
          ...scheduleBase,
          "type": "${paymentMode}_payment_check",
          "scheduledAt": Timestamp.fromDate(overdueCheck),
          "emailDeliveryRequired": false,
          "message":
              "Check whether the scheduled subscription payment has been confirmed and flag overdue/failed status if needed.",
        },
      );
    }
  }

  Future<void> updatePaymentRequestStatus(
    DocumentReference ref,
    String status,
  ) async {
    final firestore = FirebaseFirestore.instance;
    var employerId = "";
    var planName = "";
    var notificationStatus = status;
    Map<String, dynamic> preloadedRequest = const <String, dynamic>{};
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
      final billingEmail = (requestData["billingEmail"] ??
              billingEmailFromUserData(employerData))
          .toString()
          .trim();
      if (status == "approved" && !isValidEmail(billingEmail)) {
        throw const BillingApprovalException(
          "Employer billing email is missing or invalid.",
        );
      }

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
          "billingEmail": billingEmail,
          "billingEmailVerified": requestData["billingEmailVerified"] == true ||
              BillingService.billingFromUserData(
                    employerData,
                  )["billingEmailVerified"] ==
                  true,
          "paymentStatus": "pending",
          if (paymentMode == "manual_invoice" && status == "approved")
            "invoiceStatus": "scheduled",
          "updatedAt": FieldValue.serverTimestamp(),
          if (status == "approved") "approvedAt": FieldValue.serverTimestamp(),
          if (status == "approved")
            "approvedBy": FirebaseAuth.instance.currentUser?.uid,
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
      final approvedAt = DateTime.now();
      final trialEndsAt = addOneMonth(approvedAt);
      final nextBillingDate = Timestamp.fromDate(trialEndsAt);
      final trialStartedAt = Timestamp.fromDate(approvedAt);
      final amount = readMoney(planData["price"]);
      final currency = planData["currency"]?.toString() ?? "GBP";
      final activePlanName =
          requestData["planName"] ?? planData["name"] ?? planName;
      final billingEmailVerified =
          requestData["billingEmailVerified"] == true ||
              BillingService.billingFromUserData(
                    employerData,
                  )["billingEmailVerified"] ==
                  true;

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
            "billingEmail": billingEmail,
            "billingEmailVerified": billingEmailVerified,
            "status": "active",
            "billingPlanStatus": "approved",
            "paymentStatus": "pending",
            if (paymentMode == "manual_invoice") "invoiceStatus": "scheduled",
            if (paymentMode == "direct_debit") "mandateStatus": "active",
            "trialActive": true,
            "trialStatus": "active",
            "trialStartedAt": trialStartedAt,
            "trialEndsAt": nextBillingDate,
            "activeUntil": nextBillingDate,
            "planRequestStatus": "approved",
            "approvedAt": FieldValue.serverTimestamp(),
            "approvedBy": FirebaseAuth.instance.currentUser?.uid,
            "updatedAt": FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );

      transaction.set(
        employerRef.collection("billing").doc("currentPlan"),
        {
          "activePlanId": planId,
          "activePlanName": activePlanName,
          "billingPlanStatus": "approved",
          "paymentMethod": paymentMode,
          "paymentStatus": "pending",
          if (paymentMode == "manual_invoice") "invoiceStatus": "scheduled",
          "includedJobSlots": availableJobPosts,
          "monthlyPrice": amount,
          "currency": currency,
          "billingCycle": "monthly",
          "nextBillingDate": nextBillingDate,
          "billingEmail": billingEmail,
          "billingEmailVerified": billingEmailVerified,
          "trialStatus": "active",
          "trialStartedAt": trialStartedAt,
          "trialEndsAt": nextBillingDate,
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      _writeBillingSchedules(
        transaction: transaction,
        firestore: firestore,
        employerId: employerId,
        paymentRequestId: ref.id,
        planId: planId,
        planName: activePlanName.toString(),
        paymentMode: paymentMode,
        billingEmail: billingEmail,
        amount: amount,
        currency: currency,
        nextBillingDate: trialEndsAt,
      );
    });

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
