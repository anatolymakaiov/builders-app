import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'application_details_screen.dart';
import 'worker_profile_screen.dart';
import '../services/application_activity_service.dart';
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
    final doc = await FirebaseFirestore.instance
        .collection("applications")
        .doc(id)
        .get();
    final data = doc.data() ?? {};

    await ApplicationActivityService.updateStatus(
      applicationId: id,
      status: status,
      unreadFor: ApplicationActivityService.workerRecipients(data),
    );
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

                  final allApps = [...snapshot.data!.docs]..sort(
                      (a, b) => ApplicationActivityService.compareForUser(
                        a,
                        b,
                        employerId,
                      ),
                    );

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
                      final isUnread = ApplicationActivityService.isUnreadFor(
                        data,
                        employerId,
                      );

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
                        onTap: () async {
                          await ApplicationActivityService.markRead(
                            doc.id,
                            employerId,
                          );
                          final workerId = data["workerId"] ??
                              (members.isNotEmpty ? members.first : null);
                          final jobId = data["jobId"]?.toString();
                          final appEmployerId = data["employerId"]?.toString();

                          if (!context.mounted) return;

                          if (type != "team" && workerId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WorkerProfileScreen(
                                  userId: workerId.toString(),
                                  jobId: jobId,
                                  employerId: appEmployerId,
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
                            color: isUnread
                                ? AppColors.surfaceAlt
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isUnread
                                  ? AppColors.green
                                  : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (isUnread)
                                    Container(
                                      width: 10,
                                      height: 10,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: const BoxDecoration(
                                        color: AppColors.green,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
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
                                          style: TextStyle(
                                            color: AppColors.ink,
                                            fontWeight: isUnread
                                                ? FontWeight.w900
                                                : FontWeight.w800,
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
                                      fontWeight: isUnread
                                          ? FontWeight.w900
                                          : FontWeight.bold,
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
