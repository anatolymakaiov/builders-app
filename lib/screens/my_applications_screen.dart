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
  Stream<List<QueryDocumentSnapshot>> getApplicationsStream(String userId) {
    final singleStream = FirebaseFirestore.instance
        .collection("applications")
        .where("workerId", isEqualTo: userId)
        .snapshots();

    final teamStream = FirebaseFirestore.instance
        .collection("applications")
        .where("members", arrayContains: userId)
        .snapshots();

    return singleStream.asyncMap((singleSnap) async {
      final teamSnap = await teamStream.first;

      final allDocs = [
        ...singleSnap.docs,
        ...teamSnap.docs,
      ];

      /// 🔥 убираем дубликаты (на всякий случай)
      final unique = {
        for (var doc in allDocs) doc.id: doc,
      }.values.toList();

      /// 🔥 сортировка
      unique.sort((a, b) {
        final aTime = (a.data() as Map)["createdAt"] as Timestamp?;
        final bTime = (b.data() as Map)["createdAt"] as Timestamp?;

        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });

      return unique;
    });
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
            child: StreamBuilder<List<QueryDocumentSnapshot>>(
              stream: getApplicationsStream(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData) {
                  return const Center(child: Text("Error loading"));
                }

                final apps = snapshot.data!;

                if (apps.isEmpty) {
                  return const Center(child: Text("No applications"));
                }

                return ListView.builder(
                  itemCount: apps.length,
                  itemBuilder: (context, index) {
                    final data = apps[index].data() as Map<String, dynamic>;

                    final offer = data["offer"] as Map<String, dynamic>?;

                    final status = data["status"] ?? "pending";

                    /// ✅ БЕРЕМ ИЗ APPLICATION (быстро)
                    final jobTitle = data["jobTitle"] ?? "Job";

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
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          if (!jobSnapshot.data!.exists) {
                            return const ListTile(
                              title: Text("Job not found"),
                            );
                          }

                          final jobData =
                              jobSnapshot.data!.data() as Map<String, dynamic>;

                          final job = Job.fromFirestore(
                            jobSnapshot.data!.id,
                            jobData,
                          );

                          return buildCard(job, status);
                        },
                      );
                    }

                    /// ✅ если есть jobTitle — просто показываем
                    return Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          /// TITLE
                          Text(
                            jobTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),

                          const SizedBox(height: 6),

                          /// STATUS
                          Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: getStatusColor(status),
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 10),

                          /// 🔥 OFFER UI
                          if (status == "offer_sent" &&
                              data["offer"] != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Offer details",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  Text("Rate: £${data["offer"]["rate"]}/h"),
                                  Text("Start: ${data["offer"]["startDate"]}"),
                                  if (data["offer"]["message"] != null)
                                    Text(
                                        "Message: ${data["offer"]["message"]}"),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            /// ACCEPT OFFER
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  await FirebaseFirestore.instance
                                      .collection("applications")
                                      .doc(apps[index].id)
                                      .update({"status": "accepted"});

                                  await FirebaseFirestore.instance
                                      .collection("jobs")
                                      .doc(jobId)
                                      .update({
                                    "filledPositions": FieldValue.increment(1)
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                                child: const Text("Accept offer"),
                              ),
                            ),

                            const SizedBox(height: 8),

                            /// DECLINE
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () async {
                                  await FirebaseFirestore.instance
                                      .collection("applications")
                                      .doc(apps[index].id)
                                      .update({"status": "rejected"});
                                },
                                child: const Text("Decline"),
                              ),
                            ),
                          ],

                          const SizedBox(height: 10),

                          /// OPEN JOB
                          GestureDetector(
                            onTap: () async {
                              final jobDoc = await FirebaseFirestore.instance
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
                                    builder: (_) => JobDetailScreen(job: job),
                                  ),
                                );
                              }
                            },
                            child: const Text(
                              "Tap to view",
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  Future<void> updateApplicationStatus(
    String applicationId,
    String status,
  ) async {
    await FirebaseFirestore.instance
        .collection("applications")
        .doc(applicationId)
        .update({
      "status": status,
    });
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
