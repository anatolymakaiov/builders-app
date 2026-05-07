import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'application_details_screen.dart';
import 'chat_screen.dart';
import 'employer_profile_screen.dart';
import 'job_details_screen.dart';
import 'worker_profile_screen.dart';
import '../models/job.dart';
import '../services/calendar_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  String? cleanId(dynamic value) {
    final text = value?.toString().trim() ?? "";
    if (text.isEmpty || text == "null") return null;
    return text;
  }

  String notificationTitle(Map<String, dynamic> data) {
    final type = data["type"] ?? "";
    final title = data["title"]?.toString();
    if (title != null && title.isNotEmpty) return title;

    switch (type) {
      case "application":
        return "New application received";
      case "accepted":
        return "You got accepted";
      case "rejected":
        return "Application rejected";
      case "message":
        return "New message";
      case "job_alert":
        return "New matching job";
      case "application_status":
        return "Application status updated";
      case "offer":
        return "New offer received";
      case "offer_accepted":
        return "Offer accepted";
      case "offer_rejected":
        return "Offer rejected";
      case "offer_expiry":
        return "Offer expiry reminder";
      case "work_start":
        return "Work start reminder";
      case "job_status":
        return "Job status updated";
      case "billing":
        return "Billing update";
      case "report":
        return "Complaint update";
      case "admin_message":
        return "Admin message";
      case "package_approval":
        return "Package approval update";
      default:
        return "Notification";
    }
  }

  Future<void> openJobNotification(
    BuildContext context, {
    required String jobId,
    String? applicationId,
  }) async {
    final jobDoc =
        await FirebaseFirestore.instance.collection("jobs").doc(jobId).get();

    if (!jobDoc.exists) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This job is no longer available")),
      );
      return;
    }

    final job = Job.fromFirestore(jobDoc.id, jobDoc.data()!);

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          job: job,
          applicationId: applicationId,
        ),
      ),
    );
  }

  Future<void> openApplicationNotification(
    BuildContext context, {
    required String applicationId,
  }) async {
    final appDoc = await FirebaseFirestore.instance
        .collection("applications")
        .doc(applicationId)
        .get();

    if (!appDoc.exists || appDoc.data() == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("This application is no longer available")),
      );
      return;
    }

    final appData = appDoc.data()!;
    appData["id"] = appDoc.id;

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ApplicationDetailsScreen(
          applicationId: applicationId,
          data: appData,
        ),
      ),
    );
  }

  Future<void> openChatNotification(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final chatId = cleanId(data["chatId"] ?? data["targetId"]);
    if (chatId != null) {
      final chatDoc = await FirebaseFirestore.instance
          .collection("chats")
          .doc(chatId)
          .get();
      if (!chatDoc.exists) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This chat is no longer available")),
        );
        return;
      }

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)),
      );
      return;
    }

    final jobId = cleanId(data["jobId"] ?? data["relatedJobId"]);
    if (jobId == null) {
      openNotificationDetails(context, data);
      return;
    }

    final chatQuery = await FirebaseFirestore.instance
        .collection("chats")
        .where("jobId", isEqualTo: jobId)
        .limit(1)
        .get();

    if (!context.mounted) return;

    if (chatQuery.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This chat is no longer available")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(chatId: chatQuery.docs.first.id),
      ),
    );
  }

  void openBillingNotification(BuildContext context) {
    final uid = userId;
    if (uid == null) {
      openNotificationDetails(context, const {});
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployerProfileScreen(userId: uid, initialTab: 4),
      ),
    );
  }

  void openNotificationDetails(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationDetailsScreen(data: data),
      ),
    );
  }

  String targetTypeFor(Map<String, dynamic> data) {
    final explicit = cleanId(data["targetType"]);
    if (explicit != null) return explicit;

    final type = data["type"]?.toString() ?? "";
    if (type == "message" || cleanId(data["chatId"]) != null) return "chat";
    if (type == "billing" || cleanId(data["relatedPaymentRequestId"]) != null) {
      return "billing";
    }
    if (type == "report" || cleanId(data["relatedReportId"]) != null) {
      return "report";
    }
    if (type == "support" || cleanId(data["relatedSupportRequestId"]) != null) {
      return "support_request";
    }
    if (type == "admin_message") return "notification";
    if (type == "application" ||
        type == "application_status" ||
        type == "offer" ||
        type == "offer_accepted" ||
        type == "offer_rejected" ||
        type == "offer_expiry" ||
        type == "work_start") {
      return "application";
    }
    if (type == "job_alert" ||
        type == "job_status" ||
        type == "package_approval") {
      return "job";
    }

    if (cleanId(data["applicationId"] ?? data["relatedApplicationId"]) !=
        null) {
      return "application";
    }
    if (cleanId(data["jobId"] ?? data["relatedJobId"]) != null) return "job";

    return "notification";
  }

  Future<void> handleNotificationTap(
    BuildContext context,
    DocumentReference reference,
    Map<String, dynamic> data,
  ) async {
    await reference.set({
      "read": true,
      "readAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;

    final targetType = targetTypeFor(data);
    final targetId = cleanId(data["targetId"]);
    final applicationId = cleanId(
      data["relatedApplicationId"] ?? data["applicationId"],
    );
    final jobId = cleanId(data["relatedJobId"] ?? data["jobId"]);
    final workerId = cleanId(data["workerId"]);

    switch (targetType) {
      case "application":
      case "offer":
        final id = targetId ?? applicationId;
        if (id != null) {
          await openApplicationNotification(context, applicationId: id);
          return;
        }
        break;
      case "job":
      case "inactive_job":
      case "expired_job":
        final id = targetId ?? jobId;
        if (id != null) {
          await openJobNotification(
            context,
            jobId: id,
            applicationId: applicationId,
          );
          return;
        }
        break;
      case "billing":
      case "payment":
      case "payment_request":
        openBillingNotification(context);
        return;
      case "chat":
        await openChatNotification(context, data);
        return;
      case "worker":
        final id = targetId ?? workerId;
        if (id != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => WorkerProfileScreen(userId: id)),
          );
          return;
        }
        break;
      case "support_request":
      case "report":
      case "admin_message":
      case "notification":
        openNotificationDetails(context, data);
        return;
    }

    if (!context.mounted) return;

    if (applicationId != null) {
      await openApplicationNotification(context, applicationId: applicationId);
      return;
    }
    if (!context.mounted) return;

    if (jobId != null) {
      await openJobNotification(
        context,
        jobId: jobId,
        applicationId: applicationId,
      );
      return;
    }

    if (!context.mounted) return;
    openNotificationDetails(context, data);
  }

  Future<void> addNotificationOfferToCalendar(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final offerRaw = data["offer"];
    if (offerRaw is! Map) return;

    final offer = Map<String, dynamic>.from(offerRaw);
    final title = data["jobTitle"]?.toString() ??
        data["title"]?.toString() ??
        "Construction job";

    final added = await CalendarService.addOfferToCalendar(
      title: title,
      offer: offer,
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? "Offer added to calendar"
              : "Enter the start date in a calendar-readable format",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
      ),
      body: StroykaScreenBody(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("users")
              .doc(userId!)
              .collection("notifications")
              .orderBy("createdAt", descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return const Center(child: Text("No notifications"));
            }

            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;

                final bool read = data["read"] ?? false;
                final String type = data["type"] ?? "";

                final String? body =
                    (data["body"] ?? data["message"])?.toString();

                final titleText = notificationTitle(data);
                final canAddCalendar = (type == "work_start" ||
                        type == "offer" ||
                        type == "offer_accepted") &&
                    data["offer"] is Map;

                return StroykaSurface(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  texture: read
                      ? "assets/branding/texture_light_triangles.jpg"
                      : "assets/branding/texture_light_dots.jpg",
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    title: Text(
                      titleText,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(body ?? "Tap to open"),
                    trailing: canAddCalendar || !read
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canAddCalendar)
                                IconButton(
                                  tooltip: "Add to calendar",
                                  icon: const Icon(Icons.calendar_month),
                                  onPressed: () =>
                                      addNotificationOfferToCalendar(
                                    context,
                                    data,
                                  ),
                                ),
                              if (!read)
                                const Icon(
                                  Icons.circle,
                                  color: AppColors.green,
                                  size: 10,
                                ),
                            ],
                          )
                        : null,
                    onTap: () => handleNotificationTap(
                      context,
                      doc.reference,
                      data,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class NotificationDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const NotificationDetailsScreen({
    super.key,
    required this.data,
  });

  String valueText(dynamic value) {
    if (value == null) return "";
    if (value is Timestamp) return value.toDate().toString();
    if (value is Map || value is List) return value.toString();
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final title = data["title"]?.toString() ?? "Notification";
    final message = (data["message"] ?? data["body"])?.toString() ?? "";
    final rows = [
      ("Type", data["type"]),
      ("Status", data["status"]),
      ("Job", data["jobId"] ?? data["relatedJobId"]),
      ("Application", data["applicationId"] ?? data["relatedApplicationId"]),
      ("Payment request", data["relatedPaymentRequestId"]),
      ("Support request", data["relatedSupportRequestId"]),
      ("Report", data["relatedReportId"]),
      ("Created", data["createdAt"]),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Notification")),
      body: StroykaScreenBody(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            StroykaSurface(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(message),
                  ],
                  const SizedBox(height: 18),
                  ...rows.map((row) {
                    final value = valueText(row.$2);
                    if (value.isEmpty) return const SizedBox();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(
                              row.$1,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              value,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
