import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ApplicantsScreen extends StatelessWidget {
  final String jobId;

  const ApplicantsScreen({
    super.key,
    required this.jobId,
  });

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Applicants"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("applications")
            .where("jobId", isEqualTo: jobId)
            .orderBy("createdAt", descending: true) // ✅ FIX
            .snapshots(),
        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text("Error: ${snapshot.error}"),
            );
          }

          final applications = snapshot.data?.docs ?? [];

          if (applications.isEmpty) {
            return const Center(
              child: Text("No applicants yet"),
            );
          }

          return ListView.builder(
            itemCount: applications.length,
            itemBuilder: (context, index) {

              final doc = applications[index];
              final data = doc.data() as Map<String, dynamic>;

              /// 🔥 FIX: workerId вместо userId
              final workerId = data["workerId"] ?? "";
              final status = data["status"] ?? "pending";

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection("users")
                    .doc(workerId)
                    .get(),
                builder: (context, userSnapshot) {

                  String name = "Worker";
                  String trade = "";
                  String rate = "";

                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (userSnapshot.hasData && userSnapshot.data!.exists) {
                    final userData =
                        userSnapshot.data!.data() as Map<String, dynamic>;

                    name = userData["name"] ?? "Worker";
                    trade = userData["trade"] ?? "";
                    final r = userData["rate"];
                    if (r != null) {
                      rate = "£${r.toString()}/h";
                    }
                  }

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          /// STATUS
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: getStatusColor(status).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: getStatusColor(status),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),

                          if (trade.isNotEmpty) Text(trade),
                          if (rate.isNotEmpty) Text(rate),

                          const SizedBox(height: 12),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [

                              /// REJECT
                              OutlinedButton(
                                onPressed: () {
                                  updateStatus(doc.id, "rejected");
                                },
                                child: const Text("Reject"),
                              ),

                              const SizedBox(width: 10),

                              /// ACCEPT
                              ElevatedButton(
                                onPressed: () {
                                  updateStatus(doc.id, "accepted");
                                },
                                child: const Text("Accept"),
                              ),
                            ],
                          )
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

  Future<void> updateStatus(
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
}