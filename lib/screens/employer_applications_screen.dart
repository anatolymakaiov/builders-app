import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'application_details_screen.dart';
import 'worker_profile_screen.dart';
import '../services/application_activity_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class EmployerApplicationsScreen extends StatefulWidget {
  final String? initialJobId;
  final String initialStatus;

  const EmployerApplicationsScreen({
    super.key,
    this.initialJobId,
    this.initialStatus = "all",
  });

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

  @override
  void initState() {
    super.initState();
    selectedStatus = widget.initialStatus == "all"
        ? "all"
        : canonicalStatus(widget.initialStatus);
  }

  Color getStatusColor(String status) {
    switch (canonicalStatus(status)) {
      case "accepted":
      case "offer_accepted":
        return Colors.green;
      case "rejected":
        return Colors.red;
      case "negotiation":
        return Colors.purple;
      case "offer_sent":
        return AppColors.greenDark;
      case "offer_withdrawn":
      case "offer_rejected":
        return Colors.orange;
      default:
        return AppColors.ink;
    }
  }

  String canonicalStatus(dynamic value) {
    final status = value?.toString().toLowerCase().trim() ?? "pending";
    if (status == "review" || status == "in_review" || status == "applied") {
      return "pending";
    }
    return status.isEmpty ? "pending" : status;
  }

  String statusLabel(String status) {
    switch (canonicalStatus(status)) {
      case "pending":
        return "IN REVIEW";
      case "negotiation":
        return "NEGOTIATION";
      case "offer_sent":
        return "OFFER SENT";
      case "offer_withdrawn":
        return "OFFER WITHDRAWN";
      case "offer_accepted":
      case "accepted":
        return "ACCEPTED";
      case "offer_rejected":
        return "OFFER REJECTED";
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
        return const StroykaAvatar(
          fallbackIcon: Icons.groups,
          size: 64,
        );
      }

      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection("teams")
            .doc(teamId)
            .snapshots(),
        builder: (context, snapshot) {
          final team = snapshot.data?.data() as Map<String, dynamic>?;
          final avatar = team?["avatarUrl"] ?? team?["photo"] ?? team?["logo"];

          return StroykaAvatar(
            imageUrl: avatar?.toString(),
            fallbackIcon: Icons.groups,
            size: 64,
          );
        },
      );
    }

    final workerId = data["workerId"] ?? data["userId"];
    if (workerId == null) {
      return const StroykaAvatar(
        fallbackIcon: Icons.person,
        size: 64,
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(workerId)
          .snapshots(),
      builder: (context, snapshot) {
        final user = snapshot.data?.data() as Map<String, dynamic>?;
        final photo = user?["photo"] ?? user?["avatarUrl"];

        return StroykaAvatar(
          imageUrl: photo?.toString(),
          fallbackIcon: Icons.person,
          size: 64,
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

  Stream<List<QueryDocumentSnapshot>> employerApplicationsStream(
    String employerId,
  ) {
    final controller = StreamController<List<QueryDocumentSnapshot>>();
    final applicationsRef =
        FirebaseFirestore.instance.collection("applications");

    List<QueryDocumentSnapshot>? employerDocs;
    List<QueryDocumentSnapshot>? ownerDocs;
    late final StreamSubscription employerSub;
    late final StreamSubscription ownerSub;

    void emit() {
      final byEmployer = employerDocs;
      final byOwner = ownerDocs;
      if (byEmployer == null || byOwner == null || controller.isClosed) return;

      final seen = <String>{};
      final merged = <QueryDocumentSnapshot>[];
      for (final doc in [...byEmployer, ...byOwner]) {
        if (seen.add(doc.id)) merged.add(doc);
      }

      merged.sort(
        (a, b) => ApplicationActivityService.compareForUser(a, b, employerId),
      );
      controller.add(merged);
    }

    employerSub = applicationsRef
        .where("employerId", isEqualTo: employerId)
        .snapshots()
        .listen((snapshot) {
      employerDocs = snapshot.docs;
      emit();
    }, onError: controller.addError);

    ownerSub = applicationsRef
        .where("ownerId", isEqualTo: employerId)
        .snapshots()
        .listen((snapshot) {
      ownerDocs = snapshot.docs;
      emit();
    }, onError: (error) {
      debugPrint("OWNER APPLICATIONS STREAM SKIPPED: $error");
      ownerDocs = const [];
      emit();
    });

    controller.onCancel = () async {
      await employerSub.cancel();
      await ownerSub.cancel();
    };

    return controller.stream;
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
                        border: StroykaInputBorder(),
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
                        border: StroykaInputBorder(),
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
                        border: StroykaInputBorder(),
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
              child: StreamBuilder<List<QueryDocumentSnapshot>>(
                stream: employerApplicationsStream(employerId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allApps = snapshot.data!;

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

                    final status = canonicalStatus(data["status"]);
                    final trade = (data["jobTrade"] ?? "").toString().trim();
                    final site = (data["jobSite"] ?? "").toString().trim();

                    if (widget.initialJobId != null &&
                        data["jobId"]?.toString() != widget.initialJobId) {
                      return false;
                    }

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
                      final status = canonicalStatus(data["status"]);
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
                          if (data["viewedByEmployer"] != true) {
                            await ApplicationActivityService
                                .markViewedByEmployer(doc.id);
                          }
                          if (!context.mounted) return;

                          final workerId = data["workerId"]?.toString();
                          final jobId = data["jobId"]?.toString();
                          final applicationEmployerId =
                              data["employerId"]?.toString();

                          if (type != "team" &&
                              workerId != null &&
                              workerId.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WorkerProfileScreen(
                                  userId: workerId,
                                  jobId: jobId,
                                  employerId: applicationEmployerId,
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
                        child: AppCard(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          padding: const EdgeInsets.all(16),
                          dimmed: isUnread,
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
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: AppChip.status(
                                            statusLabel(status),
                                            color: getStatusColor(status),
                                          ),
                                        ),
                                        const SizedBox(height: 7),
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
