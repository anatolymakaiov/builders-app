import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'application_details_screen.dart';
import 'worker_profile_screen.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class EmployerApplicationsScreen extends StatefulWidget {
  const EmployerApplicationsScreen({super.key});

  @override
  State<EmployerApplicationsScreen> createState() =>
      _EmployerApplicationsScreenState();
}

class _EmployerApplicationsScreenState
    extends State<EmployerApplicationsScreen> {
  String selectedStatus = "all";
  Set<String> trades = {"all"};
  Set<String> sites = {"all"};
  String selectedTrade = "all";
  String selectedSite = "all";
  Color getStatusColor(String status) {
    switch (status) {
      case "accepted":
        return Colors.green;
      case "rejected":
        return Colors.red;
      default:
        return AppColors.ink;
    }
  }

  String statusLabel(String status) {
    switch (status) {
      case "pending":
      case "applied":
        return "IN REVIEW";
      case "negotiation":
        return "NEGOTIATION";
      case "offer_sent":
        return "OFFER";
      case "offer_accepted":
      case "accepted":
        return "ACCEPTED";
      case "rejected":
        return "REJECTED";
      default:
        return status.toUpperCase();
    }
  }

  Widget buildApplicantAvatar(Map<String, dynamic> data) {
    final type = data["type"] ?? "single";

    if (type == "team") {
      final teamId = data["teamId"];
      if (teamId == null) {
        return const CircleAvatar(child: Icon(Icons.groups));
      }

      return FutureBuilder<DocumentSnapshot>(
        future:
            FirebaseFirestore.instance.collection("teams").doc(teamId).get(),
        builder: (context, snapshot) {
          final team = snapshot.data?.data() as Map<String, dynamic>?;
          final avatar = team?["avatarUrl"] ?? team?["photo"] ?? team?["logo"];

          return CircleAvatar(
            backgroundImage:
                avatar == null ? null : NetworkImage(avatar.toString()),
            child: avatar == null ? const Icon(Icons.groups) : null,
          );
        },
      );
    }

    final workerId = data["workerId"] ?? data["userId"];
    if (workerId == null) {
      return const CircleAvatar(child: Icon(Icons.person));
    }

    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection("users").doc(workerId).get(),
      builder: (context, snapshot) {
        final user = snapshot.data?.data() as Map<String, dynamic>?;
        final photo = user?["photo"] ?? user?["avatarUrl"];

        return CircleAvatar(
          backgroundImage:
              photo == null ? null : NetworkImage(photo.toString()),
          child: photo == null ? const Icon(Icons.person) : null,
        );
      },
    );
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
      body: StroykaScreenBody(
        child: Column(
          children: [
            StroykaSurface(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  /// STATUS
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedStatus,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        hintText: "Status",
                        border: OutlineInputBorder(),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: [
                        "all",
                        "pending",
                        "negotiation",
                        "offer_sent",
                        "rejected",
                        "offer_accepted"
                      ]
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child:
                                    Text(e == "all" ? "All" : statusLabel(e)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedStatus = value!;
                        });
                      },
                    ),
                  ),

                  const SizedBox(width: 8),

                  /// TRADE
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedTrade,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        hintText: "Trade",
                        border: OutlineInputBorder(),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: trades
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e == "all" ? "All" : e),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedTrade = value!;
                        });
                      },
                    ),
                  ),

                  const SizedBox(width: 8),

                  /// SITE
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedSite,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        hintText: "Site",
                        border: OutlineInputBorder(),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: sites
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e == "all" ? "All" : e),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedSite = value!;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection("applications")
                    .where("employerId", isEqualTo: employerId)
                    .orderBy("createdAt", descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allApps = snapshot.data!.docs;

                  trades = {"all"};
                  sites = {"all"};

                  for (var doc in allApps) {
                    final data = doc.data() as Map<String, dynamic>;

                    final trade = (data["jobTrade"] ?? "").toString().trim();
                    final site = (data["jobSite"] ?? "").toString().trim();

                    if (trade.isNotEmpty) {
                      trades.add(trade);
                    }

                    if (site.isNotEmpty) {
                      sites.add(site);
                    }
                  }
                  final apps = allApps.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;

                    final status = data["status"] ?? "pending";
                    final trade = (data["jobTrade"] ?? "").toString().trim();
                    final site = (data["jobSite"] ?? "").toString().trim();

                    if (selectedStatus != "all" && status != selectedStatus) {
                      return false;
                    }

                    if (selectedTrade != "all" && trade != selectedTrade) {
                      return false;
                    }

                    if (selectedSite != "all" && site != selectedSite) {
                      return false;
                    }

                    return true;
                  }).toList();
                  if (apps.isEmpty) {
                    return const Center(child: Text("No applications yet"));
                  }

                  return ListView.builder(
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      final doc = apps[index];
                      final data = doc.data() as Map<String, dynamic>;

                      final type = data["type"] ?? "single";
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
                          final workerId = data["workerId"] ??
                              (members.isNotEmpty ? members.first : null);
                          final jobId = data["jobId"]?.toString();
                          final employerId = data["employerId"]?.toString();

                          if (type != "team" && workerId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WorkerProfileScreen(
                                  userId: workerId.toString(),
                                  jobId: jobId,
                                  employerId: employerId,
                                ),
                              ),
                            );
                            return;
                          }

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
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  buildApplicantAvatar(data),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          type == "team"
                                              ? "Team application"
                                              : workerName,
                                          style: const TextStyle(
                                            color: AppColors.ink,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (type == "team")
                                          Text(
                                            "${members.length} members",
                                            style: const TextStyle(
                                                color: Colors.grey),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    statusLabel(status),
                                    style: TextStyle(
                                      color: getStatusColor(status),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(jobTitle),
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
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
