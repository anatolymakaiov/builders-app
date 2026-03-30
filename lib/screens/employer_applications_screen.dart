import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'employer_profile_screen.dart';
import 'team_details_screen.dart';

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

              return Container(
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
                                    : "$workerName",
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

                        /// STATUS
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

                    const SizedBox(height: 16),

                    /// BUTTONS
                    if (status == "pending")
                      Row(
                        children: [
                          /// ACCEPT
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => updateStatus(doc.id, "accepted"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
                              child: const Text("Accept"),
                            ),
                          ),

                          const SizedBox(width: 10),

                          /// REJECT
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => updateStatus(doc.id, "rejected"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                              child: const Text("Reject"),
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 10),

                    /// VIEW PROFILE
                    TextButton(
                      onPressed: () async {
                        if (type == "team") {
                          if (teamId == null) return;

                          final teamSnap = await FirebaseFirestore.instance
                              .collection("teams")
                              .doc(teamId)
                              .get();

                          if (!teamSnap.exists) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Team not found")),
                            );
                            return;
                          }

                          final teamData =
                              teamSnap.data() as Map<String, dynamic>;

                          if (!context.mounted) return;

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeamDetailsScreen(
                                teamId: teamId,
                                teamData: teamData,
                              ),
                            ),
                          );
                        } else {
                          if (workerId == null) return;

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EmployerProfileScreen(
                                userId: workerId,
                              ),
                            ),
                          );
                        }
                      },
                      child: Text(
                        type == "team"
                            ? "View team profile"
                            : "View worker profile",
                      ),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
