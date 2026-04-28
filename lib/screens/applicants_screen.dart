import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'worker_profile_screen.dart';
import 'team_details_screen.dart';
import 'hired_workers_screen.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class ApplicantsScreen extends StatelessWidget {
  final String jobId;

  const ApplicantsScreen({
    super.key,
    required this.jobId,
  });

  Color getStatusColor(String status) {
    switch (status) {
      case "offer_accepted":
        return Colors.green;

      case "offer_sent":
        return Colors.deepPurple;

      case "negotiation":
        return AppColors.greenDark;

      case "rejected":
        return Colors.red;

      default:
        return AppColors.ink;
    }
  }

  String getStatusText(String status) {
    switch (status) {
      case "pending":
        return "New";
      case "negotiation":
        return "In negotiation";
      case "offer_sent":
        return "Offer sent";
      case "offer_accepted":
        return "Hired";
      case "rejected":
        return "Rejected";
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    Future<void> openTeam(BuildContext context, String? teamId) async {
      if (teamId == null) return;

      final navigator = Navigator.of(context);
      final scaffold = ScaffoldMessenger.of(context);

      final teamSnap = await FirebaseFirestore.instance
          .collection("teams")
          .doc(teamId)
          .get();

      if (!teamSnap.exists) {
        scaffold.showSnackBar(
          const SnackBar(content: Text("Team not found")),
        );
        return;
      }

      final teamData = teamSnap.data() as Map<String, dynamic>;

      navigator.push(
        MaterialPageRoute(
          builder: (_) => TeamDetailsScreen(
            teamId: teamId,
            teamData: teamData,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Applicants"),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HiredWorkersScreen(jobId: jobId),
                ),
              );
            },
          ),
        ],
      ),
      body: StroykaScreenBody(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("applications")
              .where("jobId", isEqualTo: jobId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final applications = (snapshot.data?.docs ?? []).where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final status = data["status"] ?? "pending";

              return status == "pending" ||
                  status == "negotiation" ||
                  status == "offer_sent";
            }).toList()
              ..sort((a, b) {
                final aStatus =
                    (a.data() as Map<String, dynamic>)["status"] ?? "pending";
                final bStatus =
                    (b.data() as Map<String, dynamic>)["status"] ?? "pending";

                /// 🟡 pending выше
                if (aStatus == "pending" && bStatus != "pending") return -1;
                if (aStatus != "pending" && bStatus == "pending") return 1;

                /// одинаковые — по дате
                final aDate = (a.data() as Map<String, dynamic>)["createdAt"]
                    as Timestamp?;
                final bDate = (b.data() as Map<String, dynamic>)["createdAt"]
                    as Timestamp?;

                if (aDate == null && bDate == null) return 0;
                if (aDate == null) return 1;
                if (bDate == null) return -1;

                return bDate.compareTo(aDate);
              });

            if (applications.isEmpty) {
              return const Center(child: Text("No applicants yet"));
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: applications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = applications[index];
                final data = doc.data() as Map<String, dynamic>;
                final type = data["type"] ?? "single";
                final isTeam = type == "team";
                final status = data["status"] ?? "pending";
                final Timestamp? createdAt = data["createdAt"];
                final dateText = createdAt != null
                    ? DateTime.fromMillisecondsSinceEpoch(
                            createdAt.millisecondsSinceEpoch)
                        .toString()
                        .substring(0, 16)
                    : "";

                if (isTeam) {
                  final members = List<String>.from(data["members"] ?? []);
                  final String? teamId = data["teamId"] as String?;

                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => openTeam(context, teamId),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          /// STATUS
                          Align(
                            alignment: Alignment.topRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: getStatusColor(status)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                getStatusText(status),
                                style: TextStyle(
                                  color: getStatusColor(status),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          /// TEAM HEADER
                          Row(
                            children: [
                              const Icon(Icons.groups),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Team application • ${members.length} ${members.length == 1 ? 'member' : 'members'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (dateText.isNotEmpty)
                                      Text(
                                        dateText,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (status != "offer_sent") ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      await FirebaseFirestore.instance
                                          .collection("applications")
                                          .doc(doc.id)
                                          .update({"status": "offer_sent"});
                                    },
                                    child: const Text("Send offer"),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      await FirebaseFirestore.instance
                                          .collection("applications")
                                          .doc(doc.id)
                                          .update({"status": "rejected"});
                                    },
                                    child: const Text("Reject"),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                /// SINGLE
                final String? workerId = data["workerId"];

                if (workerId == null || workerId.isEmpty) {
                  return const SizedBox();
                }

                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection("users")
                      .doc(workerId)
                      .get(),
                  builder: (context, userSnapshot) {
                    if (!userSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final userData =
                        userSnapshot.data!.data() as Map<String, dynamic>?;

                    final name = userData?["name"] ?? "Worker";
                    final trade = userData?["trade"] ?? "";
                    final rate = userData?["rate"];
                    final photo = userData?["photo"];

                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WorkerProfileScreen(
                              userId: workerId,
                              jobId: jobId,
                              employerId: currentUser?.uid,
                            ),
                          ),
                        );
                      },
                      child: Container(
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
                            /// STATUS
                            Align(
                              alignment: Alignment.topRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: getStatusColor(status)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  getStatusText(status),
                                  style: TextStyle(
                                    color: getStatusColor(status),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            /// 👤 USER INFO
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.grey.shade300,
                                  backgroundImage: photo != null
                                      ? NetworkImage(photo)
                                      : null,
                                  child: photo == null
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (trade.isNotEmpty)
                                        Text(
                                          trade,
                                          style: const TextStyle(
                                              color: Colors.grey),
                                        ),
                                      if (rate != null)
                                        Text("£${rate.toString()}/h"),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    );
                  },
                ); // FutureBuilder
              },
            ); // ListView
          },
        ), // StreamBuilder
      ),
    );
  }
}
