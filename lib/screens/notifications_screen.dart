import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'application_details_screen.dart';
import 'chat_screen.dart';
import 'applicants_screen.dart';
import 'job_details_screen.dart';
import 'worker_profile_screen.dart';
import '../models/job.dart';
import '../services/calendar_service.dart';
import '../theme/app_theme.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  String? get userId => FirebaseAuth.instance.currentUser?.uid;

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
      case "offer_expiry":
        return "Offer expiry reminder";
      case "work_start":
        return "Work start reminder";
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

    if (!jobDoc.exists) return;

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
      body: StreamBuilder<QuerySnapshot>(
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

              final String? jobId = data["jobId"];
              final String? applicationId = data["applicationId"];
              final String? workerId = data["workerId"];
              final String? body = data["body"];

              final titleText = notificationTitle(data);
              final canAddCalendar =
                  (type == "work_start" || type == "offer") &&
                      data["offer"] is Map;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: read ? AppColors.surface : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
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
                                onPressed: () => addNotificationOfferToCalendar(
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
                  onTap: () async {
                    /// ✅ mark as read
                    await FirebaseFirestore.instance
                        .collection("users")
                        .doc(userId!)
                        .collection("notifications")
                        .doc(doc.id)
                        .update({"read": true});

                    if (!context.mounted) return;

                    /// 🔥 1. APPLICATION → APPLICANTS LIST
                    if (type == "application" && jobId != null) {
                      if (!context.mounted) return;

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ApplicantsScreen(jobId: jobId),
                        ),
                      );

                      return;
                    }

                    /// 🔥 2. ACCEPTED → CHAT
                    if (type == "accepted" && jobId != null) {
                      final chatQuery = await FirebaseFirestore.instance
                          .collection("chats")
                          .where("jobId", isEqualTo: jobId)
                          .where("workerId", isEqualTo: userId)
                          .limit(1)
                          .get();

                      if (chatQuery.docs.isNotEmpty) {
                        final chatId = chatQuery.docs.first.id;

                        if (!context.mounted) return;

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(chatId: chatId),
                          ),
                        );
                      }

                      return;
                    }

                    /// 🔥 3. MESSAGE → CHAT
                    if (type == "message" && jobId != null) {
                      final chatQuery = await FirebaseFirestore.instance
                          .collection("chats")
                          .where("jobId", isEqualTo: jobId)
                          .limit(1)
                          .get();

                      if (chatQuery.docs.isNotEmpty) {
                        final chatId = chatQuery.docs.first.id;

                        if (!context.mounted) return;

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(chatId: chatId),
                          ),
                        );
                      }

                      return;
                    }

                    if ((type == "application_status" ||
                            type == "offer" ||
                            type == "offer_expiry" ||
                            type == "work_start") &&
                        jobId != null) {
                      await openJobNotification(
                        context,
                        jobId: jobId,
                        applicationId: applicationId,
                      );

                      return;
                    }

                    /// 🔥 4. JOB ALERT → JOB DETAILS
                    if (type == "job_alert" && jobId != null) {
                      await openJobNotification(context, jobId: jobId);

                      return;
                    }

                    /// 🔥 5. OPEN WORKER PROFILE (если есть)
                    if (workerId != null) {
                      if (!context.mounted) return;

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkerProfileScreen(userId: workerId),
                        ),
                      );

                      return;
                    }

                    /// 🔁 fallback → application details
                    if (applicationId != null) {
                      final appDoc = await FirebaseFirestore.instance
                          .collection("applications")
                          .doc(applicationId)
                          .get();

                      if (!appDoc.exists) return;

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
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
