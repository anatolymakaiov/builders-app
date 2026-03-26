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
  }) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .add({
      "title": title,
      "body": body,
      "type": type,
      "applicationId": applicationId,
      "jobId": jobId,
      "createdAt": FieldValue.serverTimestamp(),
      "read": false,
    });
  }
}