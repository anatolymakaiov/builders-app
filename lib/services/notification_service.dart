import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// 🔥 INIT
  Future<void> init() async {
    /// 🔐 Permissions
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await _fcm.setAutoInitEnabled(true);

    /// 🔥 LOCAL NOTIFICATIONS INIT
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: android,
      iOS: ios,
    );

    await _local.initialize(settings);

    /// 🔔 FOREGROUND сообщения
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;

      if (notification == null) return;

      _local.show(
        0,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'General',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    });

    debugPrint("NotificationService initialized");
  }

  /// 🔥 SAVE TOKEN (без краша на iOS)
  Future<void> saveToken(String userId) async {
    debugPrint("saveToken called");

    try {
      /// 🍏 Проверяем APNS (iOS)
      final apns = await _fcm.getAPNSToken();

      if (apns == null) {
        debugPrint("iOS push token unavailable");
        return;
      }

      debugPrint("APNS token received");

      /// 🔥 Получаем FCM
      final token = await _fcm.getToken();

      if (token == null) {
        debugPrint("FCM token is null");
        return;
      }

      debugPrint("FCM token received");

      /// 🔥 Сохраняем
      await _db.collection("users").doc(userId).set({
        "fcmToken": token,
      }, SetOptions(merge: true));

      debugPrint("FCM token saved");
    } catch (e) {
      debugPrint("saveToken error: $e");
    }
  }

  /// 🔔 Локальная запись уведомления (Firestore)
  Future<void> sendNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    String? applicationId,
    String? jobId,
    Map<String, dynamic>? extra,
  }) async {
    final payload = {
      "title": title,
      "body": body,
      "message": body,
      "type": type,
      "applicationId": applicationId,
      "jobId": jobId,
      "createdAt": FieldValue.serverTimestamp(),
      "read": false,
      ...?extra,
    };

    await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .add(payload);
  }

  Future<void> sendEmployerNotification({
    required String employerId,
    required String type,
    required String title,
    required String message,
    String? applicationId,
    String? relatedJobId,
    String? relatedReportId,
    String? relatedPaymentRequestId,
    Map<String, dynamic> extra = const {},
  }) async {
    if (employerId.trim().isEmpty) return;

    await sendNotification(
      userId: employerId,
      title: title,
      body: message,
      type: type,
      applicationId: applicationId,
      jobId: relatedJobId,
      extra: {
        if (relatedJobId != null && relatedJobId.isNotEmpty)
          "relatedJobId": relatedJobId,
        if (relatedReportId != null && relatedReportId.isNotEmpty)
          "relatedReportId": relatedReportId,
        if (relatedPaymentRequestId != null &&
            relatedPaymentRequestId.isNotEmpty)
          "relatedPaymentRequestId": relatedPaymentRequestId,
        ...extra,
      },
    );
  }

  Future<void> notifyEmployerOfferDecision({
    required String applicationId,
    required Map<String, dynamic> applicationData,
    required String status,
  }) async {
    final employerId = applicationData["employerId"]?.toString() ?? "";
    if (employerId.trim().isEmpty) return;

    final isAccepted = status == "offer_accepted" || status == "accepted";
    final isRejected = status == "offer_rejected";
    if (!isAccepted && !isRejected) return;

    final offerRaw = applicationData["offer"];
    final offer = offerRaw is Map<String, dynamic>
        ? Map<String, dynamic>.from(offerRaw)
        : offerRaw is Map
            ? Map<String, dynamic>.from(offerRaw)
            : <String, dynamic>{};
    final jobId = applicationData["jobId"]?.toString();
    final jobTitle =
        applicationData["jobTitle"]?.toString().trim().isNotEmpty == true
            ? applicationData["jobTitle"].toString().trim()
            : "the job";
    final workerId = applicationData["workerId"]?.toString() ??
        (applicationData["members"] is List &&
                (applicationData["members"] as List).isNotEmpty
            ? (applicationData["members"] as List).first.toString()
            : null);
    final workerName =
        applicationData["workerName"]?.toString().trim().isNotEmpty == true
            ? applicationData["workerName"].toString().trim()
            : applicationData["teamName"]?.toString().trim().isNotEmpty == true
                ? applicationData["teamName"].toString().trim()
                : "Worker";
    final startDate =
        (offer["startDateTime"] ?? offer["startDate"])?.toString().trim() ?? "";
    final jobAddress = _offerAddress(offer, applicationData);

    await sendEmployerNotification(
      employerId: employerId,
      type: isAccepted ? "offer_accepted" : "offer_rejected",
      title: isAccepted ? "Offer accepted" : "Offer rejected",
      message: isAccepted
          ? startDate.isEmpty
              ? "$workerName accepted the offer for $jobTitle."
              : "$workerName accepted the offer for $jobTitle and starts on $startDate."
          : "$workerName rejected the offer for $jobTitle.",
      applicationId: applicationId,
      relatedJobId: jobId,
      extra: {
        "status": status,
        if (workerId != null && workerId.isNotEmpty) "workerId": workerId,
        "workerName": workerName,
        "applicationId": applicationId,
        if (jobId != null && jobId.isNotEmpty) "jobId": jobId,
        if (startDate.isNotEmpty) ...{
          "offerStartDate": startDate,
          "startDate": startDate,
          "startDateTime": startDate,
        },
        if (jobTitle.isNotEmpty) "jobTitle": jobTitle,
        if (jobAddress.isNotEmpty) "jobAddress": jobAddress,
        if (offer.isNotEmpty) "offer": offer,
      },
    );
  }

  String _offerAddress(
    Map<String, dynamic> offer,
    Map<String, dynamic> applicationData,
  ) {
    final direct = (offer["fullAddress"] ??
            offer["siteAddress"] ??
            applicationData["fullAddress"] ??
            applicationData["siteAddress"])
        ?.toString()
        .trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final street =
        (offer["siteStreet"] ?? applicationData["siteStreet"])?.toString() ??
            "";
    final city =
        (offer["siteCity"] ?? applicationData["siteCity"])?.toString() ?? "";
    final postcode = (offer["sitePostcode"] ?? applicationData["sitePostcode"])
            ?.toString() ??
        "";

    return [street.trim(), city.trim(), postcode.trim()]
        .where((part) => part.isNotEmpty)
        .join(", ");
  }

  Future<void> notifyEmployerJobModeration({
    required String employerId,
    required String jobId,
    required String jobTitle,
    required String moderationStatus,
    String? reason,
  }) async {
    final approved = moderationStatus == "approved";
    await sendEmployerNotification(
      employerId: employerId,
      type: "job_status",
      title: approved ? "Job approved" : "Job rejected",
      message: approved
          ? "$jobTitle has been approved and can be published."
          : reason?.trim().isNotEmpty == true
              ? "$jobTitle was rejected: ${reason!.trim()}"
              : "$jobTitle was rejected by admin.",
      relatedJobId: jobId,
      extra: {
        "status": moderationStatus,
        if (reason != null && reason.trim().isNotEmpty)
          "moderationReason": reason.trim(),
      },
    );
  }

  Future<void> notifyEmployerJobStatusChanged({
    required String employerId,
    required String jobId,
    required String jobTitle,
    required String status,
  }) async {
    final title = switch (status) {
      "active" => "Job activated",
      "inactive" || "closed" => "Job made inactive",
      "paused" => "Job paused",
      "expired" => "Job expired",
      "publication_ended" => "Publication period ended",
      _ => "Job status updated",
    };

    final message = switch (status) {
      "active" => "$jobTitle is active.",
      "inactive" || "closed" => "$jobTitle is inactive.",
      "paused" => "$jobTitle has been paused.",
      "expired" => "$jobTitle has expired.",
      "publication_ended" => "$jobTitle publication period has ended.",
      _ => "$jobTitle status changed to $status.",
    };

    await sendEmployerNotification(
      employerId: employerId,
      type: "job_status",
      title: title,
      message: message,
      relatedJobId: jobId,
      extra: {"status": status},
    );
  }

  Future<void> notifyEmployerBillingEvent({
    required String employerId,
    required String paymentRequestId,
    required String status,
    String? planName,
  }) async {
    final plan = planName?.trim().isNotEmpty == true
        ? planName!.trim()
        : "Selected plan";
    final title = switch (status) {
      "paid" => "Plan approved",
      "failed" => "Payment failed",
      "cancelled" => "Plan request cancelled",
      "rejected" => "Plan rejected",
      "invoice_issued" => "Invoice issued",
      "payment_received" => "Payment received",
      "upcoming_direct_debit" => "Upcoming direct debit",
      _ => "Billing request updated",
    };

    final message = switch (status) {
      "paid" => "$plan has been approved and payment was received.",
      "failed" => "Payment for $plan failed.",
      "cancelled" => "$plan request was cancelled.",
      "rejected" => "$plan request was rejected.",
      "invoice_issued" => "An invoice has been issued for $plan.",
      "payment_received" => "Payment for $plan was received.",
      "upcoming_direct_debit" => "Direct debit for $plan is coming up.",
      _ => "$plan billing status changed to $status.",
    };

    await sendEmployerNotification(
      employerId: employerId,
      type: "billing",
      title: title,
      message: message,
      relatedPaymentRequestId: paymentRequestId,
      extra: {
        "status": status,
        if (planName != null) "planName": planName,
      },
    );
  }

  Future<void> notifyEmployerReportSubmitted({
    required String employerId,
    required String reportId,
    required String reportType,
  }) async {
    await sendEmployerNotification(
      employerId: employerId,
      type: "report",
      title: "Complaint submitted",
      message: "A $reportType complaint was submitted against your company.",
      relatedReportId: reportId,
      extra: {"status": "open", "reportType": reportType},
    );
  }

  Future<void> notifyEmployerReportStatusChanged({
    required String employerId,
    required String reportId,
    required String status,
  }) async {
    await sendEmployerNotification(
      employerId: employerId,
      type: "report",
      title: "Complaint review result",
      message: "Admin updated complaint status to $status.",
      relatedReportId: reportId,
      extra: {"status": status},
    );
  }

  List<String> applicationRecipients(Map<String, dynamic> applicationData) {
    final members = applicationData["members"];
    if (members is List && members.isNotEmpty) {
      return members.map((id) => id.toString()).toSet().toList();
    }

    final workerId = applicationData["workerId"] ?? applicationData["userId"];
    if (workerId == null) return [];

    return [workerId.toString()];
  }

  Future<void> notifyApplicationStatus({
    required String applicationId,
    required Map<String, dynamic> applicationData,
    required String status,
  }) async {
    final recipients = applicationRecipients(applicationData);
    if (recipients.isEmpty) return;

    final jobId = applicationData["jobId"]?.toString();
    final jobTitle = applicationData["jobTitle"]?.toString() ?? "your job";
    final title = _statusTitle(status);

    for (final userId in recipients) {
      await sendNotification(
        userId: userId,
        title: title,
        body: "$jobTitle: ${_statusBody(status)}",
        type: "application_status",
        applicationId: applicationId,
        jobId: jobId,
        extra: {"status": status},
      );
    }
  }

  Future<void> notifyOfferCreated({
    required String applicationId,
    required Map<String, dynamic> applicationData,
    required Map<String, dynamic> offer,
  }) async {
    final recipients = applicationRecipients(applicationData);
    if (recipients.isEmpty) return;

    final jobId = applicationData["jobId"]?.toString();
    final jobTitle = applicationData["jobTitle"]?.toString() ?? "Job";
    final validUntil = offer["validUntil"]?.toString().trim() ?? "";

    for (final userId in recipients) {
      await sendNotification(
        userId: userId,
        title: "New offer received",
        body: "$jobTitle: review the offer details",
        type: "offer",
        applicationId: applicationId,
        jobId: jobId,
        extra: {
          "offer": offer,
          "jobTitle": jobTitle,
          "startDateTime": offer["startDateTime"] ?? offer["startDate"],
          "validUntil": offer["validUntil"],
        },
      );

      if (validUntil.isNotEmpty) {
        await sendNotification(
          userId: userId,
          title: "Offer expiry reminder",
          body: "$jobTitle offer is valid until $validUntil",
          type: "offer_expiry",
          applicationId: applicationId,
          jobId: jobId,
          extra: {
            "offer": offer,
            "jobTitle": jobTitle,
            "validUntil": offer["validUntil"],
          },
        );
      }
    }
  }

  Future<void> notifyWorkStartReminder({
    required String applicationId,
    required Map<String, dynamic> applicationData,
    required Map<String, dynamic> offer,
  }) async {
    final recipients = applicationRecipients(applicationData);
    if (recipients.isEmpty) return;

    final jobId = applicationData["jobId"]?.toString();
    final jobTitle = applicationData["jobTitle"]?.toString() ?? "Job";
    final start = (offer["startDateTime"] ?? offer["startDate"])?.toString();

    for (final userId in recipients) {
      await sendNotification(
        userId: userId,
        title: "Work start reminder",
        body: start == null || start.trim().isEmpty
            ? "$jobTitle start date is in your offer"
            : "$jobTitle starts $start",
        type: "work_start",
        applicationId: applicationId,
        jobId: jobId,
        extra: {
          "offer": offer,
          "jobTitle": jobTitle,
          "startDateTime": start,
        },
      );
    }
  }

  String _statusTitle(String status) {
    switch (status) {
      case "negotiation":
        return "Application moved to negotiation";
      case "review":
        return "Application is in review";
      case "rejected":
        return "Application rejected";
      case "offer_accepted":
      case "accepted":
        return "Offer accepted";
      default:
        return "Application status updated";
    }
  }

  String _statusBody(String status) {
    switch (status) {
      case "negotiation":
        return "the employer wants to negotiate";
      case "review":
        return "your application is being reviewed";
      case "rejected":
        return "your application was rejected";
      case "offer_accepted":
      case "accepted":
        return "your offer was accepted";
      default:
        return "status changed to $status";
    }
  }
}
