import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

    print("✅ NotificationService initialized");
  }

  /// 🔥 SAVE TOKEN (без краша на iOS)
  Future<void> saveToken(String userId) async {
    print("🔥 saveToken CALLED");

    try {
      /// 🍏 Проверяем APNS (iOS)
      final apns = await _fcm.getAPNSToken();

      if (apns == null) {
        print("⚠️ iOS: Push отключён (нет paid аккаунта)");
        return;
      }

      print("🍏 APNS TOKEN: $apns");

      /// 🔥 Получаем FCM
      final token = await _fcm.getToken();

      if (token == null) {
        print("❌ FCM TOKEN NULL");
        return;
      }

      print("🔥 FCM TOKEN: $token");

      /// 🔥 Сохраняем
      await _db.collection("users").doc(userId).set({
        "fcmToken": token,
      }, SetOptions(merge: true));

      print("✅ TOKEN SAVED");
    } catch (e) {
      print("❌ saveToken error: $e");
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
