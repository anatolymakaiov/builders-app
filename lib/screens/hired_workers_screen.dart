import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'worker_profile_screen.dart';

class HiredWorkersScreen extends StatelessWidget {
  final String jobId;

  const HiredWorkersScreen({
    super.key,
    required this.jobId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Hired workers"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("applications")
            .where("jobId", isEqualTo: jobId)
            .where("status", isEqualTo: "offer_accepted")
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("No hired workers"));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final workerId = data["workerId"];

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection("users")
                    .doc(workerId)
                    .get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox();
                  }

                  final user =
                      snapshot.data!.data() as Map<String, dynamic>?;

                  final name = user?["name"] ?? "Worker";
                  final trade = user?["trade"] ?? "";
                  final photo = user?["photo"];

                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkerProfileScreen(
                            userId: workerId,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundImage:
                                photo != null ? NetworkImage(photo) : null,
                            child: photo == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          const SizedBox(width: 10),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (trade.isNotEmpty)
                                  Text(
                                    trade,
                                    style:
                                        const TextStyle(color: Colors.grey),
                                  ),
                              ],
                            ),
                          ),

                          const Icon(Icons.check_circle, color: Colors.green),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}