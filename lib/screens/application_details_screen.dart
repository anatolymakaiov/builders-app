import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ApplicationDetailsScreen extends StatelessWidget {
  final String applicationId;
  final Map<String, dynamic> data;

  const ApplicationDetailsScreen({
    super.key,
    required this.applicationId,
    required this.data,
  });

  Future<void> updateStatus(BuildContext context, String status) async {
    final db = FirebaseFirestore.instance;

    final workerId = data["workerId"] ?? data["userId"];
    final employerId = data["employerId"];
    final jobId = data["jobId"];

    if (workerId == null || employerId == null || jobId == null) return;

    /// ✅ обновляем статус
    await db.collection("applications").doc(applicationId).update({
      "status": status,
    });

    /// 🔥 СОЗДАЕМ ЧАТ
    if (status == "accepted") {

      final existing = await db
          .collection("chats")
          .where("jobId", isEqualTo: jobId)
          .where("workerId", isEqualTo: workerId)
          .where("employerId", isEqualTo: employerId)
          .limit(1)
          .get();

      if (existing.docs.isEmpty) {

        /// 🔥 получаем имена
        final workerDoc =
            await db.collection("users").doc(workerId).get();
        final employerDoc =
            await db.collection("users").doc(employerId).get();

        final workerName =
            workerDoc.data()?["name"] ?? "Worker";
        final employerName =
            employerDoc.data()?["name"] ?? "Employer";

        await db.collection("chats").add({
          "jobId": jobId,
          "workerId": workerId,
          "employerId": employerId,

          /// 🔥 ОБЯЗАТЕЛЬНО
          "participants": [workerId, employerId],

          "workerName": workerName,
          "employerName": employerName,

          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),

          "lastMessage": "",
          "unreadCount_worker": 0,
          "unreadCount_employer": 0,
        });
      }
    }

    /// 🔔 УВЕДОМЛЕНИЕ
    await db
        .collection("users")
        .doc(workerId)
        .collection("notifications")
        .add({
      "type": "application_update",
      "status": status, // accepted / rejected
      "jobId": jobId,
      "applicationId": applicationId,
      "fromUserId": employerId,
      "createdAt": FieldValue.serverTimestamp(),
      "read": false,
    });

    if (!context.mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final workerId = data["workerId"] ?? data["userId"];

    if (workerId == null) {
      return const Scaffold(
        body: Center(child: Text("Invalid application data")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Application"),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection("users")
            .doc(workerId)
            .get(),
        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text("Error: ${snapshot.error}"),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("User not found"));
          }

          final userData =
              snapshot.data!.data() as Map<String, dynamic>;

          final name = userData["name"] ?? "Worker";
          final trade = userData["trade"] ?? "";
          final rate = userData["rate"] != null
              ? "£${userData["rate"]}/h"
              : "";

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                if (trade.isNotEmpty) Text(trade),
                if (rate.isNotEmpty) Text(rate),

                const Spacer(),

                Row(
                  children: [

                    /// ✅ ACCEPT
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            updateStatus(context, "accepted"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: const Text("Accept"),
                      ),
                    ),

                    const SizedBox(width: 10),

                    /// ❌ REJECT
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            updateStatus(context, "rejected"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text("Reject"),
                      ),
                    ),
                  ],
                )
              ],
            ),
          );
        },
      ),
    );
  }
}