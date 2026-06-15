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
      "subscriptionStatus",
      "trialStartDate",
      "trialEndDate",
      "currentPlan",
      "pendingPlan",
      "currentPaymentMethod",
      "pendingPaymentMethod",
      "billingReminder10Sent",
      "billingReminder5Sent",
      "billingReminder3Sent",
      "billingReminder1Sent",
      "lastPaymentDate",
      "nextInvoiceDate",
      "activeSlots",
      "usedSlots",
      "availableSlots",
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

  static bool hasConfiguredPaymentMethod(Map<String, dynamic> userData) {
    final billing = billingFromUserData(userData);
    final method =
        (billing["currentPaymentMethod"] ?? billing["paymentMethod"] ?? "")
            .toString()
            .trim()
            .toLowerCase();
    if (method == "manual_invoice") {
      return billingEmailFromUserData(userData).isNotEmpty;
    }
    if (method == "direct_debit") {
      return hasDirectDebitMandate(userData);
    }
    if (method == "card") {
      return (billing["cardPaymentMethodId"] ??
              billing["paymentMethodId"] ??
              billing["stripePaymentMethodId"] ??
              "")
          .toString()
          .trim()
          .isNotEmpty;
    }
    return false;
  }

  static String subscriptionStatusFor(
    Map<String, dynamic> userData, {
    DateTime? now,
  }) {
    final billing = billingFromUserData(userData);
    final explicit = billing["subscriptionStatus"]?.toString();
    final billingPlanStatus =
        billing["billingPlanStatus"]?.toString().trim().toLowerCase() ?? "";
    final trialEndValue = billing["trialEndDate"] ?? billing["trialEndsAt"];
    DateTime? trialEndDate;
    if (trialEndValue is Timestamp) {
      trialEndDate = trialEndValue.toDate();
    } else if (trialEndValue is DateTime) {
      trialEndDate = trialEndValue;
    }

    final current = now ?? DateTime.now();
    final trialActive = billing["trialActive"] == true ||
        billing["trialStatus"]?.toString() == "active" ||
        explicit == "trial";
    if (trialActive && trialEndDate != null && trialEndDate.isAfter(current)) {
      return "trial";
    }

    if (billingPlanStatus == "approved") {
      return hasConfiguredPaymentMethod(userData)
          ? "active"
          : "payment_required";
    }

    return "billing_required";
  }

  static Map<String, dynamic> subscriptionSnapshot({
    required Map<String, dynamic> userData,
    required int usedJobPosts,
  }) {
    final billing = billingFromUserData(userData);
    final totalSlots = readInt(
      billing["includedJobSlots"] ??
          billing["availableJobPosts"] ??
          billing["activeSlots"],
    );
    final availableSlots = (totalSlots - usedJobPosts).clamp(0, 999999);
    final paymentMethod =
        (billing["currentPaymentMethod"] ?? billing["paymentMethod"] ?? "")
            .toString();
    final plan =
        (billing["currentPlan"] ?? billing["activePlanId"] ?? billing["planId"])
            ?.toString();

    return {
      "subscriptionStatus": subscriptionStatusFor(userData),
      "trialStartDate": billing["trialStartDate"] ?? billing["trialStartedAt"],
      "trialEndDate": billing["trialEndDate"] ?? billing["trialEndsAt"],
      "currentPlan": plan ?? "",
      "pendingPlan": billing["pendingPlan"] ?? "",
      "currentPaymentMethod": paymentMethod,
      "pendingPaymentMethod": billing["pendingPaymentMethod"] ?? "",
      "nextBillingDate": billing["nextBillingDate"],
      "billingReminder10Sent": billing["billingReminder10Sent"] == true,
      "billingReminder5Sent": billing["billingReminder5Sent"] == true,
      "billingReminder3Sent": billing["billingReminder3Sent"] == true,
      "billingReminder1Sent": billing["billingReminder1Sent"] == true,
      "invoiceStatus": billing["invoiceStatus"] ?? "pending",
      "lastPaymentDate": billing["lastPaymentDate"] ?? "",
      "nextInvoiceDate": billing["nextInvoiceDate"] ?? "",
      "activeSlots": totalSlots,
      "usedSlots": usedJobPosts,
      "availableSlots": availableSlots,
    };
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
    var userData = userSnap.data() ?? {};
    final usedJobPosts = await countPublishedJobSlots(employerId);
    userData = await refreshSubscriptionLifecycle(
      employerId: employerId,
      userData: _userDataWithUsedJobPosts(userData, usedJobPosts),
      usedJobPosts: usedJobPosts,
    );
    _assertEmployerCanPostFromData(
      _userDataWithUsedJobPosts(userData, usedJobPosts),
    );
  }

  Future<Map<String, dynamic>> refreshSubscriptionLifecycle({
    required String employerId,
    required Map<String, dynamic> userData,
    required int usedJobPosts,
  }) async {
    final billing = billingFromUserData(userData);
    final next = Map<String, dynamic>.from(userData);
    final nextBilling = Map<String, dynamic>.from(billing);
    nextBilling.addAll(subscriptionSnapshot(
      userData: userData,
      usedJobPosts: usedJobPosts,
    ));

    final trialEndValue = billing["trialEndDate"] ?? billing["trialEndsAt"];
    DateTime? trialEndDate;
    if (trialEndValue is Timestamp) {
      trialEndDate = trialEndValue.toDate();
    } else if (trialEndValue is DateTime) {
      trialEndDate = trialEndValue;
    }

    final trialExpired =
        trialEndDate != null && !trialEndDate.isAfter(DateTime.now());
    final wasTrial = billing["subscriptionStatus"] == "trial" ||
        billing["trialActive"] == true ||
        billing["trialStatus"] == "active";

    if (trialExpired && wasTrial) {
      final status = subscriptionStatusFor(userData);
      nextBilling["subscriptionStatus"] = status;
      nextBilling["trialActive"] = false;
      nextBilling["trialStatus"] = "expired";
      if (status == "payment_required") {
        nextBilling["paymentStatus"] = "payment_required";
      }
      if (status == "billing_required") {
        nextBilling["billingPlanStatus"] = "billing_required";
      }
    }

    next["billing"] = nextBilling;

    await FirebaseFirestore.instance.collection("users").doc(employerId).set(
      {
        "billing": {
          ...nextBilling,
          "updatedAt": FieldValue.serverTimestamp(),
        },
      },
      SetOptions(merge: true),
    );
    return next;
  }

  Future<String> createJobWithBillingLimit({
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
        final billing = billingFromUserData(userData);
        userData["billing"] = {
          ...billing,
          ...subscriptionSnapshot(
            userData: userData,
            usedJobPosts: usedJobPosts,
          ),
        };
        _assertEmployerCanPostFromData(userData);
      }

      transaction.set(jobRef, {
        ...jobData,
        "billingCounted": false,
        "createdAt": FieldValue.serverTimestamp(),
      });
    });
    return jobRef.id;
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
          final billing = billingFromUserData(userData);
          userData["billing"] = {
            ...billing,
            ...subscriptionSnapshot(
              userData: userData,
              usedJobPosts: usedJobPosts,
            ),
          };
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
    final currentPlanId =
        (currentBilling["activePlanId"] ?? currentBilling["planId"] ?? "")
            .toString();
    final currentPrice = readMoney(currentBilling["monthlyPrice"]);
    final requestedPrice = readMoney(planData["price"]);
    final changeDirection = currentPlanId.isEmpty
        ? "initial"
        : requestedPrice > currentPrice
            ? "upgrade"
            : requestedPrice < currentPrice
                ? "downgrade"
                : "same_price_change";
    final nextBillingValue = currentBilling["nextBillingDate"];
    final now = DateTime.now();
    final nextBillingDate = nextBillingValue is Timestamp
        ? nextBillingValue.toDate()
        : addOneMonth(now);
    final daysRemaining = nextBillingDate.isAfter(now)
        ? nextBillingDate.difference(now).inDays
        : 0;
    final proratedDifference = changeDirection == "upgrade"
        ? ((requestedPrice - currentPrice) * (daysRemaining.clamp(0, 30) / 30))
        : 0.0;

    await firestore.runTransaction((transaction) async {
      final userRef = firestore.collection("users").doc(employerId);
      final paymentRequestRef = firestore.collection("payment_requests").doc();

      transaction.set(paymentRequestRef, {
        "employerId": employerId,
        "planId": plan.id,
        "planName": selectedPlanName,
        "paymentMode": paymentMode,
        "requestType": currentPlanId.isEmpty ? "initial_plan" : "plan_change",
        "currentPlan": currentPlanId,
        "pendingPlan": plan.id,
        "currentPaymentMethod": currentBilling["paymentMethod"] ??
            currentBilling["currentPaymentMethod"] ??
            "",
        "pendingPaymentMethod": paymentMode,
        "changeDirection": changeDirection,
        "proratedDifference": proratedDifference,
        "effectiveAt": changeDirection == "downgrade"
            ? Timestamp.fromDate(nextBillingDate)
            : FieldValue.serverTimestamp(),
        "planChangeWarning": changeDirection == "upgrade"
            ? "Additional charges will be applied proportionally for the remainder of the current billing period."
            : changeDirection == "downgrade"
                ? "Downgrade will take effect on your next billing date. Current billing charges are non-refundable."
                : "",
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
            "pendingPlan": plan.id,
            "paymentMode": paymentMode,
            "pendingPaymentMethod": paymentMode,
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
    final reminder3Days = nextBillingDate.subtract(const Duration(days: 3));
    final reminder1Day = nextBillingDate.subtract(const Duration(days: 1));
    final reminder2Days = nextBillingDate.subtract(const Duration(days: 2));
    final overdueCheck = nextBillingDate.add(const Duration(days: 1));

    void writeTrialReminder(int days, DateTime scheduledAt) {
      transaction.set(
        firestore.collection("billing_schedules").doc(),
        {
          ...scheduleBase,
          "type": "trial_expiry_reminder_${days}_days",
          "scheduledAt": Timestamp.fromDate(scheduledAt),
          "dueDate": Timestamp.fromDate(nextBillingDate),
          "opens": "billing",
          "pushRequired": true,
          "alertRequired": true,
          "message":
              "Your trial period will end in $days days. Please ensure a billing plan and payment method are configured to avoid service interruption.",
        },
      );
    }

    writeTrialReminder(10, reminder10Days);
    writeTrialReminder(5, reminder5Days);
    writeTrialReminder(3, reminder3Days);
    writeTrialReminder(1, reminder1Day);

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
      final trialEndsAt = approvedAt.add(const Duration(days: 30));
      final nextBillingDate = Timestamp.fromDate(trialEndsAt);
      final trialStartedAt = Timestamp.fromDate(approvedAt);
      final amount = readMoney(planData["price"]);
      final currency = planData["currency"]?.toString() ?? "GBP";
      final activePlanName =
          requestData["planName"] ?? planData["name"] ?? planName;
      final changeDirection =
          requestData["changeDirection"]?.toString() ?? "initial";
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
            "currentPlan": planId,
            "pendingPlan": "",
            "paymentMode": paymentMode,
            "paymentMethod": paymentMode,
            "currentPaymentMethod": paymentMode,
            "pendingPaymentMethod": "",
            "directDebitEnabled": paymentMode == "direct_debit",
            "availableJobPosts": availableJobPosts,
            "includedJobSlots": availableJobPosts,
            "usedJobPosts": 0,
            "activeSlots": availableJobPosts,
            "usedSlots": 0,
            "availableSlots": availableJobPosts,
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
            if (paymentMode == "direct_debit")
              "directDebitGatewayStatus": "gateway_pending",
            "subscriptionStatus": "trial",
            "trialActive": true,
            "trialStatus": "active",
            "trialStartedAt": trialStartedAt,
            "trialEndsAt": nextBillingDate,
            "trialStartDate": trialStartedAt,
            "trialEndDate": nextBillingDate,
            "activeUntil": nextBillingDate,
            "planRequestStatus": "approved",
            "planChangeDirection": changeDirection,
            if (requestData["proratedDifference"] != null)
              "proratedDifference": requestData["proratedDifference"],
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
          "currentPlan": planId,
          "billingPlanStatus": "approved",
          "paymentMethod": paymentMode,
          "currentPaymentMethod": paymentMode,
          "paymentStatus": "pending",
          if (paymentMode == "manual_invoice") "invoiceStatus": "scheduled",
          "includedJobSlots": availableJobPosts,
          "activeSlots": availableJobPosts,
          "usedSlots": 0,
          "availableSlots": availableJobPosts,
          "monthlyPrice": amount,
          "currency": currency,
          "billingCycle": "monthly",
          "nextBillingDate": nextBillingDate,
          "billingEmail": billingEmail,
          "billingEmailVerified": billingEmailVerified,
          "subscriptionStatus": "trial",
          "trialStatus": "active",
          "trialStartedAt": trialStartedAt,
          "trialEndsAt": nextBillingDate,
          "trialStartDate": trialStartedAt,
          "trialEndDate": nextBillingDate,
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
    final subscriptionStatus =
        billing["subscriptionStatus"]?.toString().trim().toLowerCase() ?? "";
    final availableJobPosts = readInt(billing["availableJobPosts"]);
    final usedJobPosts = readInt(billing["usedJobPosts"]);

    if (status == "pending" ||
        billingPlanStatus == "pending" ||
        planRequestStatus == "pending") {
      throw const BillingLimitException(pendingBillingMessage);
    }

    if (subscriptionStatus == "payment_required" ||
        subscriptionStatus == "billing_required" ||
        subscriptionStatus == "suspended" ||
        subscriptionStatus == "cancelled") {
      throw const BillingLimitException(
        "Your trial period has ended. Please configure a payment method or billing plan to continue publishing vacancies.",
      );
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
