import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';

import '../screens/notifications_screen.dart';
import 'app_navigation.dart';
import 'calendar_service.dart';

class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const defaultPreferences = <String, bool>{
    "enabled": true,
    "jobAlerts": true,
    "applicationUpdates": true,
    "offers": true,
    "messages": true,
    "adminMessages": true,
    "billing": true,
    "supportReplies": true,
    "policyUpdates": true,
    "sound": true,
    "badges": true,
  };

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
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: android,
      iOS: ios,
    );

    await _local.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        _handlePayload(response.payload);
      },
    );

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    /// 🔔 FOREGROUND сообщения
    FirebaseMessaging.onMessage.listen((message) async {
      final notification = message.notification;

      if (notification == null) return;
      final userId = message.data["userId"]?.toString();
      final preferences = await notificationPreferences(userId);
      if (!_shouldDisplayPush(message.data, preferences)) return;
      final badgeCount = userId == null
          ? null
          : await syncUnreadBadgeCount(userId, preferences: preferences);

      _local.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'General',
            importance: Importance.max,
            priority: Priority.high,
            playSound: preferences["sound"] != false,
          ),
          iOS: DarwinNotificationDetails(
            presentSound: preferences["sound"] != false,
            presentBadge: preferences["badges"] != false,
            badgeNumber: preferences["badges"] == false ? null : badgeCount,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen(handleRemoteMessageTap);

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        handleRemoteMessageTap(initialMessage);
      });
    }

    debugPrint("NotificationService initialized");
  }

  /// 🔥 SAVE TOKEN (без краша на iOS)
  Future<void> saveToken(String userId) async {
    debugPrint("saveToken called");

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final apns = await _fcm.getAPNSToken();
        if (apns == null) {
          debugPrint("iOS APNS token is not ready yet");
        }
      }

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
        "fcmTokens": FieldValue.arrayUnion([token]),
        "push.updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _db
          .collection("users")
          .doc(userId)
          .collection("deviceTokens")
          .doc(token)
          .set({
        "token": token,
        "platform": defaultTargetPlatform.name,
        "updatedAt": FieldValue.serverTimestamp(),
        "active": true,
      }, SetOptions(merge: true));

      _fcm.onTokenRefresh.listen((newToken) async {
        await _db.collection("users").doc(userId).set({
          "fcmToken": newToken,
          "fcmTokens": FieldValue.arrayUnion([newToken]),
          "push.updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await _db
            .collection("users")
            .doc(userId)
            .collection("deviceTokens")
            .doc(newToken)
            .set({
          "token": newToken,
          "platform": defaultTargetPlatform.name,
          "updatedAt": FieldValue.serverTimestamp(),
          "active": true,
        }, SetOptions(merge: true));
      });

      debugPrint("FCM token saved");
    } catch (e) {
      debugPrint("saveToken error: $e");
    }
  }

  Future<void> saveCurrentUserToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await saveToken(user.uid);
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
    final category = _categoryFor(type, extra: extra);
    final targetType = extra?["targetType"] ??
        _defaultTargetType(
          type: type,
          applicationId: applicationId,
          jobId: jobId,
          extra: extra,
        );
    final targetId = extra?["targetId"] ??
        _defaultTargetId(
          targetType: targetType?.toString(),
          applicationId: applicationId,
          jobId: jobId,
          extra: extra,
        );
    final payload = {
      "userId": userId,
      "title": title,
      "body": body,
      "message": body,
      "type": type,
      "category": category,
      if (targetType != null) "targetType": targetType,
      if (targetId != null) "targetId": targetId,
      "applicationId": applicationId,
      if (applicationId != null) "relatedApplicationId": applicationId,
      "jobId": jobId,
      if (jobId != null) "relatedJobId": jobId,
      "createdAt": FieldValue.serverTimestamp(),
      "read": false,
      "badgeEligible": true,
      "pushEligible": true,
      ...?extra,
    };

    final ref = await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .add(payload);

    await ref.set({
      "notificationId": ref.id,
      "push": {
        "title": title,
        "body": body,
        "category": category,
        "sound": true,
        "badge": true,
        "data": {
          "notificationId": ref.id,
          "userId": userId,
          "type": type,
          "category": category,
          if (targetType != null) "targetType": targetType,
          if (targetId != null) "targetId": targetId,
          if (applicationId != null) "applicationId": applicationId,
          if (jobId != null) "jobId": jobId,
        },
      },
    }, SetOptions(merge: true));

    try {
      await _db.collection('users').doc(userId).set({
        "notificationState.unreadCount": FieldValue.increment(1),
        "notificationState.updatedAt": FieldValue.serverTimestamp(),
        "notificationState.lastNotificationId": ref.id,
      }, SetOptions(merge: true));

      await syncUnreadBadgeCount(userId);
    } on FirebaseException catch (e) {
      if (e.code != "permission-denied") rethrow;
      debugPrint(
        "Notification badge sync skipped for $userId: ${e.code}",
      );
    }
  }

  Future<Map<String, bool>> notificationPreferences(String? userId) async {
    if (userId == null || userId.trim().isEmpty) return defaultPreferences;
    try {
      final doc = await _db.collection("users").doc(userId).get();
      final data = doc.data() ?? {};
      final settings = data["settings"] is Map
          ? Map<String, dynamic>.from(data["settings"])
          : <String, dynamic>{};
      final raw = settings["notifications"] is Map
          ? Map<String, dynamic>.from(settings["notifications"])
          : data["notificationPreferences"] is Map
              ? Map<String, dynamic>.from(data["notificationPreferences"])
              : <String, dynamic>{};
      return {
        for (final entry in defaultPreferences.entries)
          entry.key:
              raw[entry.key] is bool ? raw[entry.key] as bool : entry.value,
      };
    } catch (_) {
      return defaultPreferences;
    }
  }

  Future<void> saveNotificationPreference({
    required String userId,
    required String key,
    required bool value,
  }) async {
    if (!defaultPreferences.containsKey(key)) return;
    await _db.collection("users").doc(userId).set({
      "settings.notifications.$key": value,
      "notificationPreferences.$key": value,
      "settings.updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<int> syncUnreadBadgeCount(
    String userId, {
    Map<String, bool>? preferences,
  }) async {
    final prefs = preferences ?? await notificationPreferences(userId);
    final notifications = await _db
        .collection("users")
        .doc(userId)
        .collection("notifications")
        .where("read", isEqualTo: false)
        .get();
    final chats = await _db
        .collection("chats")
        .where("unreadFor", arrayContains: userId)
        .get();
    final count = (prefs["badges"] == false)
        ? 0
        : notifications.docs.length + chats.docs.length;
    await _db.collection("users").doc(userId).set({
      "notificationState.unreadCount": notifications.docs.length,
      "notificationState.unreadChatCount": chats.docs.length,
      "notificationState.badgeCount": count,
      "notificationState.updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return count;
  }

  bool _shouldDisplayPush(
    Map<String, dynamic> data,
    Map<String, bool> preferences,
  ) {
    if (preferences["enabled"] == false) return false;
    final category = data["category"]?.toString() ??
        _categoryFor(data["type"]?.toString() ?? "", extra: data);
    return preferences[_preferenceKeyForCategory(category)] != false;
  }

  String _preferenceKeyForCategory(String category) {
    return switch (category) {
      "job" => "jobAlerts",
      "application" => "applicationUpdates",
      "offer" => "offers",
      "chat" => "messages",
      "admin" => "adminMessages",
      "billing" => "billing",
      "support" => "supportReplies",
      "policy" => "policyUpdates",
      _ => "enabled",
    };
  }

  String _categoryFor(String type, {Map<String, dynamic>? extra}) {
    if (type.contains("offer")) return "offer";
    if (type == "message" || extra?["chatId"] != null) return "chat";
    if (type == "job_alert" || type == "job_status") return "job";
    if (type == "billing" || extra?["relatedPaymentRequestId"] != null) {
      return "billing";
    }
    if (type == "support" || extra?["relatedSupportRequestId"] != null) {
      return "support";
    }
    if (type == "admin_message") return "admin";
    if (type == "policy_update" || type == "legal_update") return "policy";
    if (type == "application" ||
        type == "application_status" ||
        type == "application_reopened") {
      return "application";
    }
    return "alert";
  }

  Future<void> handleRemoteMessageTap(RemoteMessage message) async {
    await _handlePayload(jsonEncode(message.data));
  }

  Future<void> _handlePayload(String? payload) async {
    if (payload == null || payload.trim().isEmpty) return;
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      final userId = data["userId"]?.toString() ??
          FirebaseAuth.instance.currentUser?.uid ??
          "";
      final notificationId = data["notificationId"]?.toString() ??
          data["targetNotificationId"]?.toString();
      if (notificationId != null &&
          notificationId.isNotEmpty &&
          data["userId"] != null) {
        final ref = _db
            .collection("users")
            .doc(data["userId"].toString())
            .collection("notifications")
            .doc(notificationId);
        final snapshot = await ref.get();
        final notificationData = snapshot.data() ?? data;
        if (!context.mounted) return;
        await const NotificationsScreen().handleNotificationTap(
          context,
          ref,
          notificationData,
        );
        return;
      }

      if (!context.mounted) return;
      const NotificationsScreen().openNotificationDetails(context, data);
      if (userId.isNotEmpty) {
        await syncUnreadBadgeCount(userId);
      }
    } catch (e) {
      debugPrint("Notification payload routing error: $e");
    }
  }

  Future<void> markApplicationNotificationsRead({
    required String userId,
    required String applicationId,
  }) async {
    if (userId.trim().isEmpty || applicationId.trim().isEmpty) return;

    final snapshot = await _db
        .collection("users")
        .doc(userId)
        .collection("notifications")
        .where("read", isEqualTo: false)
        .get();

    final batch = _db.batch();
    var hasUpdates = false;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final ids = [
        data["applicationId"],
        data["relatedApplicationId"],
        data["targetId"],
      ].map((value) => value?.toString().trim()).where(
            (value) => value != null && value.isNotEmpty && value != "null",
          );

      if (!ids.contains(applicationId)) continue;

      batch.set(
          doc.reference,
          {
            "read": true,
            "readAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      hasUpdates = true;
    }

    if (hasUpdates) {
      await batch.commit();
      await syncUnreadBadgeCount(userId);
    }
  }

  String? _defaultTargetType({
    required String type,
    String? applicationId,
    String? jobId,
    Map<String, dynamic>? extra,
  }) {
    if (extra?["chatId"] != null) return "chat";
    if (extra?["relatedPaymentRequestId"] != null) return "billing";
    if (extra?["relatedSupportRequestId"] != null) return "support_request";
    if (extra?["relatedReportId"] != null) return "report";
    if (applicationId != null ||
        type == "application" ||
        type == "application_status" ||
        type == "offer" ||
        type == "offer_accepted" ||
        type == "offer_rejected" ||
        type == "offer_expiry" ||
        type == "work_start") {
      return "application";
    }
    if (jobId != null ||
        type == "job_alert" ||
        type == "job_status" ||
        type == "package_approval") {
      return "job";
    }
    if (type == "billing") return "billing";
    if (type == "report") return "report";
    if (type == "support") return "support_request";
    if (type == "admin_message") return "notification";
    return null;
  }

  String? _defaultTargetId({
    required String? targetType,
    String? applicationId,
    String? jobId,
    Map<String, dynamic>? extra,
  }) {
    switch (targetType) {
      case "application":
        return applicationId ?? extra?["relatedApplicationId"]?.toString();
      case "job":
        return jobId ?? extra?["relatedJobId"]?.toString();
      case "chat":
        return extra?["chatId"]?.toString();
      case "billing":
        return extra?["relatedPaymentRequestId"]?.toString();
      case "support_request":
        return extra?["relatedSupportRequestId"]?.toString();
      case "report":
        return extra?["relatedReportId"]?.toString();
      default:
        return null;
    }
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
    Map<String, dynamic> workerProfile = {};
    if (workerId != null && workerId.isNotEmpty) {
      try {
        final workerDoc = await _db.collection("users").doc(workerId).get();
        workerProfile = workerDoc.data() ?? {};
      } catch (_) {
        workerProfile = {};
      }
    }
    final workerPhone =
        (applicationData["workerPhone"] ?? workerProfile["phone"])
                ?.toString()
                .trim() ??
            "";
    final workerEmail =
        (applicationData["workerEmail"] ?? workerProfile["email"])
                ?.toString()
                .trim() ??
            "";
    final startDate =
        (offer["startDateTime"] ?? offer["startDate"])?.toString().trim() ?? "";
    final jobAddress = _offerAddress(offer, applicationData);
    final contactInfo = [
      if (workerPhone.isNotEmpty) workerPhone,
      if (workerEmail.isNotEmpty) workerEmail,
    ].join(" / ");

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
        if (jobTitle.isNotEmpty) "position": jobTitle,
        if (jobAddress.isNotEmpty) "jobAddress": jobAddress,
        if (jobAddress.isNotEmpty) "jobLocation": jobAddress,
        if (jobAddress.isNotEmpty) "siteAddress": jobAddress,
        if (workerPhone.isNotEmpty) "workerPhone": workerPhone,
        if (workerEmail.isNotEmpty) "workerEmail": workerEmail,
        if (contactInfo.isNotEmpty) "contactInfo": contactInfo,
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
    final onHold = moderationStatus == "on_hold";
    await sendEmployerNotification(
      employerId: employerId,
      type: "job_status",
      title: approved
          ? "Job approved"
          : onHold
              ? "Job put on hold"
              : "Job rejected",
      message: approved
          ? "$jobTitle has been approved and can be published."
          : onHold
              ? reason?.trim().isNotEmpty == true
                  ? "$jobTitle was put on hold: ${reason!.trim()}"
                  : "$jobTitle was put on hold by admin."
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
      "approved" => "Plan approved",
      "trial_started" => "Trial started",
      "failed" => "Payment failed",
      "cancelled" => "Plan request cancelled",
      "rejected" => "Plan rejected",
      "on_hold" => "Plan request on hold",
      "invoice_issued" => "Invoice issued",
      "invoice_reminder" => "Invoice reminder",
      "payment_received" => "Payment received",
      "upcoming_direct_debit" => "Upcoming direct debit",
      "upcoming_card_payment" => "Upcoming card payment",
      "overdue" => "Payment overdue",
      _ => "Billing request updated",
    };

    final message = switch (status) {
      "approved" =>
        "$plan has been approved. Your one month free trial has started.",
      "trial_started" =>
        "Your one month free trial for $plan has started. Your next billing date is scheduled after the trial.",
      "failed" => "Payment for $plan failed.",
      "cancelled" => "$plan request was cancelled.",
      "rejected" => "$plan request was rejected.",
      "on_hold" => "$plan request is on hold.",
      "invoice_issued" =>
        "Your invoice for $plan has been issued and sent to your billing email.",
      "invoice_reminder" =>
        "Your invoice for $plan is due soon. Please complete payment before the due date.",
      "payment_received" => "Payment for $plan was received.",
      "upcoming_direct_debit" =>
        "Your subscription payment for $plan is scheduled. Please ensure your Direct Debit remains active.",
      "upcoming_card_payment" =>
        "Your subscription payment for $plan is scheduled. Please ensure your card remains active.",
      "overdue" => "Payment for $plan is overdue.",
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

  Future<void> notifyApplicationReopened({
    required String applicationId,
    required Map<String, dynamic> applicationData,
  }) async {
    final recipients = applicationRecipients(applicationData);
    if (recipients.isEmpty) return;

    final jobId = applicationData["jobId"]?.toString();
    final jobTitle = applicationData["jobTitle"]?.toString() ?? "your job";

    for (final userId in recipients) {
      await sendNotification(
        userId: userId,
        title: "Application reopened",
        body: "$jobTitle: the employer reopened your application.",
        type: "application_reopened",
        applicationId: applicationId,
        jobId: jobId,
        extra: {
          "status": "negotiation",
          "targetType": "application",
          "targetId": applicationId,
        },
      );
    }
  }

  Future<void> notifyOfferCreated({
    required String applicationId,
    required Map<String, dynamic> applicationData,
    required Map<String, dynamic> offer,
  }) async {
    final selectedWorkerIds = offer["selectedWorkerIds"];
    final recipients = selectedWorkerIds is List && selectedWorkerIds.isNotEmpty
        ? selectedWorkerIds.map((id) => id.toString()).toSet().toList()
        : applicationRecipients(applicationData);
    if (recipients.isEmpty) return;

    final jobId = applicationData["jobId"]?.toString();
    final jobTitle = applicationData["jobTitle"]?.toString() ?? "Job";
    final employerId = applicationData["employerId"]?.toString() ??
        applicationData["ownerId"]?.toString();
    final workerId = applicationData["workerId"]?.toString() ??
        applicationData["userId"]?.toString();
    final validUntil = offer["validUntil"]?.toString().trim() ?? "";

    for (final userId in recipients) {
      final notificationWorkerId =
          workerId?.isNotEmpty == true ? workerId : userId;

      await sendNotification(
        userId: userId,
        title: "New offer received",
        body: "$jobTitle: review the offer details",
        type: "offer",
        applicationId: applicationId,
        jobId: jobId,
        extra: {
          "targetType": "application",
          "targetId": applicationId,
          "applicationId": applicationId,
          "relatedApplicationId": applicationId,
          if (jobId != null && jobId.isNotEmpty) ...{
            "jobId": jobId,
            "relatedJobId": jobId,
          },
          "workerId": notificationWorkerId,
          if (employerId != null && employerId.isNotEmpty)
            "employerId": employerId,
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
            "targetType": "application",
            "targetId": applicationId,
            "applicationId": applicationId,
            "relatedApplicationId": applicationId,
            if (jobId != null && jobId.isNotEmpty) ...{
              "jobId": jobId,
              "relatedJobId": jobId,
            },
            "workerId": notificationWorkerId,
            if (employerId != null && employerId.isNotEmpty)
              "employerId": employerId,
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

  Future<void> scheduleWorkerStartReminders({
    required String applicationId,
    required Map<String, dynamic> applicationData,
    required Map<String, dynamic> offer,
  }) async {
    final recipients = applicationRecipients(applicationData);
    if (recipients.isEmpty) return;

    final start = CalendarService.parseOfferDate(
      offer["startDateTime"] ?? offer["startDate"],
    );
    if (start == null) return;

    final now = DateTime.now();
    final jobId = applicationData["jobId"]?.toString();
    final jobTitle = applicationData["jobTitle"]?.toString().trim();
    final companyName = applicationData["companyName"]?.toString().trim() ??
        applicationData["employerName"]?.toString().trim() ??
        "";
    final displayTitle =
        jobTitle == null || jobTitle.isEmpty ? "your job" : jobTitle;
    final startText =
        (offer["startDateTime"] ?? offer["startDate"])?.toString() ??
            start.toString();

    for (final daysBefore in const [7, 2]) {
      final reminderAt = start.subtract(Duration(days: daysBefore));
      if (!reminderAt.isAfter(now)) continue;

      for (final userId in recipients) {
        final ref = _db
            .collection("users")
            .doc(userId)
            .collection("notifications")
            .doc("work_start_${applicationId}_${daysBefore}d");
        final message = companyName.isEmpty
            ? "$displayTitle starts on $startText."
            : "$displayTitle with $companyName starts on $startText.";
        await ref.set({
          "notificationId": ref.id,
          "userId": userId,
          "type": "work_start_reminder",
          "category": "offer",
          "title": "Work starts soon",
          "message": message,
          "targetType": "application",
          "targetId": applicationId,
          "applicationId": applicationId,
          "relatedApplicationId": applicationId,
          if (jobId != null && jobId.isNotEmpty) ...{
            "jobId": jobId,
            "relatedJobId": jobId,
          },
          "jobTitle": displayTitle,
          if (companyName.isNotEmpty) "companyName": companyName,
          "startDateTime": startText,
          "reminderDaysBefore": daysBefore,
          "reminderAt": Timestamp.fromDate(reminderAt),
          "read": false,
          "badgeEligible": true,
          "pushEligible": true,
          "createdAt": FieldValue.serverTimestamp(),
          "offer": offer,
          "push": {
            "title": "Work starts soon",
            "body": message,
            "category": "offer",
            "sound": true,
            "badge": true,
            "data": {
              "notificationId": ref.id,
              "userId": userId,
              "type": "work_start_reminder",
              "category": "offer",
              "targetType": "application",
              "targetId": applicationId,
              "applicationId": applicationId,
              if (jobId != null && jobId.isNotEmpty) "jobId": jobId,
            },
          },
        }, SetOptions(merge: true));
        await syncUnreadBadgeCount(userId);
      }
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
