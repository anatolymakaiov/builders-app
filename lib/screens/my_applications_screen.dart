import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/job.dart';
import '../screens/job_details_screen.dart';

class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  String filter = "all";

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

  /// 🔥 ПРАВИЛЬНЫЙ STREAM
  Stream<QuerySnapshot> getApplicationsStream(String userId) {
    Query base = FirebaseFirestore.instance
        .collection("applications")
        .where("workerId", isEqualTo: userId) // ✅ FIX
        .orderBy("createdAt", descending: true);

    switch (filter) {
      case "accepted":
        base = base.where("status", isEqualTo: "accepted");
        break;

      case "rejected":
        base = base.where("status", isEqualTo: "rejected");
        break;

      case "pending":
        base = base.where("status", isEqualTo: "pending");
        break;
    }

    return base.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("User not logged in")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("My Applications")),
      body: Column(
        children: [
          /// 🔥 FILTERS
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                filterButton("all", "All"),
                filterButton("pending", "In review"),
                filterButton("accepted", "Accepted"),
                filterButton("rejected", "Rejected"),
              ],
            ),
          ),

          /// 🔥 LIST
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: getApplicationsStream(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator());
                }

                if (!snapshot.hasData) {
                  return const Center(child: Text("Error loading"));
                }

                final apps = snapshot.data!.docs;

                if (apps.isEmpty) {
                  return const Center(child: Text("No applications"));
                }

                return ListView.builder(
                  itemCount: apps.length,
                  itemBuilder: (context, index) {
                    final data =
                        apps[index].data() as Map<String, dynamic>;

                    final status = data["status"] ?? "pending";

                    /// ✅ БЕРЕМ ИЗ APPLICATION (быстро)
                    final jobTitle =
                        data["jobTitle"] ?? "Job";

                    final jobId = data["jobId"];

                    /// 🔥 ЕСЛИ НЕТ jobTitle → fallback
                    if (data["jobTitle"] == null) {
                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection("jobs")
                            .doc(jobId)
                            .get(),
                        builder: (context, jobSnapshot) {
                          if (!jobSnapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child:
                                    CircularProgressIndicator(),
                              ),
                            );
                          }

                          if (!jobSnapshot.data!.exists) {
                            return const ListTile(
                              title: Text("Job not found"),
                            );
                          }

                          final jobData =
                              jobSnapshot.data!.data()
                                  as Map<String, dynamic>;

                          final job = Job.fromFirestore(
                            jobSnapshot.data!.id,
                            jobData,
                          );

                          return buildCard(job, status);
                        },
                      );
                    }

                    /// ✅ если есть jobTitle — просто показываем
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: Text(
                          jobTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text("Tap to view"),
                        trailing: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: getStatusColor(status),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onTap: () async {
                          final jobDoc =
                              await FirebaseFirestore.instance
                                  .collection("jobs")
                                  .doc(jobId)
                                  .get();

                          if (!jobDoc.exists) return;

                          final job = Job.fromFirestore(
                            jobDoc.id,
                            jobDoc.data()!,
                          );

                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    JobDetailScreen(job: job),
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
          ),
        ],
      ),
    );
  }

  /// 🔥 reusable card
  Widget buildCard(Job job, String status) {
    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 8),
      child: ListTile(
        title: Text(
          job.title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text("${job.city} • £${job.rate.toInt()}"),
        trailing: Text(
          status.toUpperCase(),
          style: TextStyle(
            color: getStatusColor(status),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget filterButton(String value, String label) {
    final selected = filter == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          filter = value;
        });
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}