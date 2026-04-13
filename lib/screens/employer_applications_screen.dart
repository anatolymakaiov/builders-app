import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'employer_profile_screen.dart';
import 'team_details_screen.dart';
import 'applicants_screen.dart';
import 'application_details_screen.dart';

class EmployerApplicationsScreen extends StatelessWidget {
  const EmployerApplicationsScreen({super.key});

  Color getStatusColor(String status) {
    switch (status) {
      case "accepted":
        return Colors.green;
      case "rejected":
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> updateStatus(String id, String status) async {
    await FirebaseFirestore.instance
        .collection("applications")
        .doc(id)
        .update({"status": status});
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
      );
    }

    final employerId = user.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("Applications")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("applications")
            .where("employerId", isEqualTo: employerId)
            .orderBy("createdAt", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final apps = snapshot.data!.docs;

          if (apps.isEmpty) {
            return const Center(child: Text("No applications yet"));
          }

          return ListView.builder(
            itemCount: apps.length,
            itemBuilder: (context, index) {
              final doc = apps[index];
              final data = doc.data() as Map<String, dynamic>;

              final workerId = data["workerId"];
              final type = data["type"] ?? "single";
              final teamId = data["teamId"];
              final workerName = data["workerName"] ?? "Worker";
              final members = List<String>.from(data["members"] ?? []);
              final jobTitle = data["jobTitle"] ?? "Job";
              final status = data["status"] ?? "pending";
              final Timestamp? createdAt = data["createdAt"];
              final dateText = createdAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                          createdAt.millisecondsSinceEpoch)
                      .toString()
                      .substring(0, 16)
                  : "";

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ApplicationDetailsScreen(
                        applicationId: doc.id,
                        data: data,
                      ),
                    ),
                  );
                },
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// 👤 WORKER
                      Row(
                        children: [
                          CircleAvatar(
                            child: Icon(
                              type == "team" ? Icons.groups : Icons.person,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  type == "team"
                                      ? "Team application"
                                      : workerName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                if (type == "team")
                                  Text(
                                    "${members.length} members",
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: getStatusColor(status),
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        ],
                      ),

                      const SizedBox(height: 8),

                      /// JOB
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(jobTitle),
                          if (dateText.isNotEmpty)
                            Text(
                              dateText,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
