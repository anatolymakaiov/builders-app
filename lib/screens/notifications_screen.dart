import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'application_details_screen.dart';
import 'chat_screen.dart';
import 'applicants_screen.dart';
import 'job_details_screen.dart';
import 'worker_profile_screen.dart';
import '../models/job.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  String? get userId => FirebaseAuth.instance.currentUser?.uid;

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

              /// 🔥 TITLE
              String titleText;

              switch (type) {
                case "application":
                  titleText = "New application received";
                  break;
                case "accepted":
                  titleText = "You got accepted";
                  break;
                case "rejected":
                  titleText = "Application rejected";
                  break;
                case "message":
                  titleText = "New message";
                  break;
                case "job_alert":
                  titleText = data["title"] ?? "New matching job";
                  break;
                default:
                  titleText = "Notification";
              }

              return ListTile(
                tileColor: read ? null : Colors.orange.shade50,
                title: Text(titleText),
                subtitle: Text(body ?? "Tap to open"),
                trailing: read
                    ? null
                    : const Icon(Icons.circle, color: Colors.red, size: 10),
                onTap: () async {
                  /// ✅ mark as read
                  await FirebaseFirestore.instance
                      .collection("users")
                      .doc(userId!)
                      .collection("notifications")
                      .doc(doc.id)
                      .update({"read": true});

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

                  /// 🔥 4. JOB ALERT → JOB DETAILS
                  if (type == "job_alert" && jobId != null) {
                    final jobDoc = await FirebaseFirestore.instance
                        .collection("jobs")
                        .doc(jobId)
                        .get();

                    if (!jobDoc.exists) return;

                    final job = Job.fromFirestore(
                      jobDoc.id,
                      jobDoc.data()!,
                    );

                    if (!context.mounted) return;

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => JobDetailScreen(job: job),
                      ),
                    );

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
              );
            },
          );
        },
      ),
    );
  }
}
