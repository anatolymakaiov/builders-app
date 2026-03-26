import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'application_details_screen.dart';
import 'chat_screen.dart'; // ⚠️ убедись что есть

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

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No notifications"));
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {

              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              final bool read = data["read"] ?? false;
              final String type = data["type"] ?? "";
              final String? jobId = data["jobId"];

              /// 🔥 TITLE
              String titleText;

              if (type == "application") {
                titleText = "New application received";
              } else if (type == "accepted") {
                titleText = "You got the job";
              } else if (type == "rejected") {
                titleText = "Application rejected";
              } else {
                titleText = "Notification";
              }

              return ListTile(
                tileColor: read ? null : Colors.orange.shade50,

                title: Text(titleText),
                subtitle: const Text("Tap to open"),

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

                  /// 🔥 ACCEPT → ОТКРЫТЬ ЧАТ
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

                  /// 🔁 СТАРАЯ ЛОГИКА (если есть applicationId)
                  final applicationId = data["applicationId"];

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