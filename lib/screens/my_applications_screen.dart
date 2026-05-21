import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/job.dart';
import '../screens/job_details_screen.dart';
import '../services/application_activity_service.dart';
import '../services/application_status_utils.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';
import '../widgets/job_card.dart';

class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  String statusFilter = "all";

  Color getStatusColor(String status) {
    switch (ApplicationStatusUtils.normalizeStatus(status)) {
      case "accepted":
      case "offer_accepted":
        return Colors.green;
      case "offer_sent":
        return AppColors.greenDark;
      case "negotiation":
        return Colors.purple;
      case "rejected":
      case "offer_rejected":
        return Colors.red;
      default:
        return AppColors.ink;
    }
  }

  String canonicalStatus(dynamic value) {
    return ApplicationStatusUtils.normalizeStatus(value);
  }

  bool matchesStatusFilter(String status) {
    return ApplicationStatusUtils.isStatusInFilter(status, statusFilter);
  }

  String statusLabel(String status) {
    return ApplicationStatusUtils.getStatusDisplayLabel(status, "worker")
        .toUpperCase();
  }

  String applicationDateText(dynamic value) {
    if (value is! Timestamp) return "";

    final date = value.toDate();
    final day = date.day.toString().padLeft(2, "0");
    final month = date.month.toString().padLeft(2, "0");
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, "0");
    final minute = date.minute.toString().padLeft(2, "0");

    return "Applied $day/$month/$year $hour:$minute";
  }

  bool jobUnavailableForWorker(Job job) {
    return job.isClosed || job.moderationStatus == "rejected";
  }

  String unavailableJobMessage(Job job) {
    final status = job.status.trim().toLowerCase();
    if (status == "deleted" || status == "archived") {
      return "Employer removed this vacancy.";
    }
    return "Employer deactivated this vacancy.";
  }

  Widget unavailableJobNotice(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Job fallbackJobFromApplication(String id, Map<String, dynamic> data) {
    return Job.fromFirestore(id, {
      "title": data["jobTitle"] ?? data["title"] ?? data["trade"] ?? "Job",
      "trade": data["jobTrade"] ?? data["trade"] ?? data["jobTitle"] ?? "Job",
      "site": data["jobSite"] ?? data["site"] ?? "",
      "location": data["jobLocation"] ??
          data["siteAddress"] ??
          data["jobAddress"] ??
          data["location"] ??
          "",
      "street": data["siteStreet"] ?? data["street"] ?? "",
      "city": data["siteCity"] ?? data["city"] ?? "",
      "postcode": data["sitePostcode"] ?? data["postcode"] ?? "",
      "county": data["siteCounty"] ?? data["county"] ?? "",
      "rate": data["rate"] ?? data["jobRate"] ?? 0,
      "companyName": data["companyName"] ??
          data["employerName"] ??
          data["ownerName"] ??
          "",
      "companyLogo":
          data["companyLogo"] ?? data["employerLogo"] ?? data["ownerLogo"],
      "photos": data["jobPhotos"] ?? data["photos"] ?? const [],
      "jobType": data["jobType"] ?? "hourly",
      "duration": data["duration"] ?? data["jobDuration"] ?? "",
      "weeklyHours": data["weeklyHours"] ?? "",
      "employmentType": data["employmentType"] ?? "",
      "ownerId": data["ownerId"] ?? data["employerId"] ?? "",
      "createdAt": data["createdAt"],
      "status": "active",
      "moderationStatus": "approved",
    });
  }

  /// 🔥 ПРАВИЛЬНЫЙ STREAM
  Stream<List<QueryDocumentSnapshot>> getApplicationsStream(String userId) {
    final singleStream = FirebaseFirestore.instance
        .collection("applications")
        .where("workerId", isEqualTo: userId)
        .snapshots(includeMetadataChanges: true);

    late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
        singleSub;
    late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> teamsSub;
    final teamApplicationSubs =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    List<QueryDocumentSnapshot<Map<String, dynamic>>> singleDocs = [];
    final teamDocsByTeam =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    var hasSingleSnapshot = false;
    var hasTeamSnapshot = false;

    final controller = StreamController<List<QueryDocumentSnapshot>>();

    List<String> memberIds(dynamic value) {
      if (value is! List) return [];
      return value
          .map((item) {
            if (item is String) return item;
            if (item is Map) return item["userId"]?.toString();
            return null;
          })
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
    }

    bool isUserTeam(Map<String, dynamic> data) {
      return data["ownerId"] == userId ||
          data["createdBy"] == userId ||
          memberIds(data["members"]).contains(userId);
    }

    bool isRelevantTeamApplication(Map<String, dynamic> data, String teamId) {
      final type = data["type"]?.toString();
      final status = data["status"]?.toString().toLowerCase().trim();
      return type == "team" &&
          data["teamId"]?.toString() == teamId &&
          status != "withdrawn" &&
          status != "cancelled" &&
          status != "deleted";
    }

    void emit() {
      if ((!hasSingleSnapshot && !hasTeamSnapshot) || controller.isClosed) {
        return;
      }

      final teamDocs = teamDocsByTeam.values.expand((docs) => docs).toList();
      final allDocs = [
        ...singleDocs,
        ...teamDocs,
      ];

      /// 🔥 убираем дубликаты (на всякий случай)
      final unique = {
        for (var doc in allDocs) doc.id: doc,
      }.values.toList();

      unique.sort(
        (a, b) => ApplicationActivityService.compareForUser(a, b, userId),
      );

      controller.add(unique);
    }

    singleSub = singleStream.listen((snapshot) {
      hasSingleSnapshot = true;
      singleDocs = snapshot.docs;
      emit();
    }, onError: (error) {
      hasSingleSnapshot = true;
      singleDocs = [];
      emit();
    });

    void clearTeamApplicationSubscriptions() {
      for (final sub in teamApplicationSubs) {
        sub.cancel();
      }
      teamApplicationSubs.clear();
      teamDocsByTeam.clear();
    }

    teamsSub =
        FirebaseFirestore.instance.collection("teams").snapshots().listen(
      (snapshot) {
        final teamIds = snapshot.docs
            .where((doc) => isUserTeam(doc.data()))
            .map((doc) => doc.id)
            .toSet()
            .toList();

        clearTeamApplicationSubscriptions();

        if (teamIds.isEmpty) {
          hasTeamSnapshot = true;
          emit();
          return;
        }

        hasTeamSnapshot = false;
        var received = 0;

        for (final teamId in teamIds) {
          final sub = FirebaseFirestore.instance
              .collection("applications")
              .where("teamId", isEqualTo: teamId)
              .snapshots(includeMetadataChanges: true)
              .listen((appSnapshot) {
            received++;
            teamDocsByTeam[teamId] = appSnapshot.docs.where((doc) {
              return isRelevantTeamApplication(doc.data(), teamId);
            }).toList();
            hasTeamSnapshot = received >= teamIds.length;
            emit();
          }, onError: (_) {
            received++;
            teamDocsByTeam[teamId] = [];
            hasTeamSnapshot = received >= teamIds.length;
            emit();
          });
          teamApplicationSubs.add(sub);
        }
      },
      onError: (_) {
        clearTeamApplicationSubscriptions();
        hasTeamSnapshot = true;
        emit();
      },
    );

    controller.onCancel = () async {
      await singleSub.cancel();
      await teamsSub.cancel();
      clearTeamApplicationSubscriptions();
    };

    return controller.stream;
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
      body: StroykaScreenBody(
        child: Column(
          children: [
            buildFilters(),

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

                  final apps = snapshot.data!.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final status = canonicalStatus(data["status"]);

                    return matchesStatusFilter(status);
                  }).toList();

                  apps.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    return ApplicationStatusUtils.compareNewestFirst(
                      aData,
                      bData,
                    );
                  });

                  if (apps.isEmpty) {
                    return const Center(child: Text("No applications"));
                  }

                  return ListView.builder(
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      final data = apps[index].data() as Map<String, dynamic>;
                      final isUnread = ApplicationActivityService.isUnreadFor(
                        data,
                        user.uid,
                      );

                      final status = canonicalStatus(data["status"]);
                      final jobDocId = data["jobId"]?.toString() ?? "";
                      final fallbackJob = fallbackJobFromApplication(
                        jobDocId.isEmpty ? apps[index].id : jobDocId,
                        data,
                      );

                      if (jobDocId.isEmpty) {
                        return buildCard(
                          fallbackJob,
                          status,
                          apps[index].id,
                          appliedAt: data["createdAt"],
                          isUnread: isUnread,
                          userId: user.uid,
                        );
                      }

                      return StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection("jobs")
                            .doc(jobDocId)
                            .snapshots(),
                        builder: (context, jobSnapshot) {
                          if (!jobSnapshot.hasData ||
                              jobSnapshot.hasError ||
                              !jobSnapshot.data!.exists) {
                            return buildCard(
                              fallbackJob,
                              status,
                              apps[index].id,
                              appliedAt: data["createdAt"],
                              isUnread: isUnread,
                              userId: user.uid,
                            );
                          }

                          final jobData =
                              jobSnapshot.data!.data() as Map<String, dynamic>;

                          final job = Job.fromFirestore(
                            jobSnapshot.data!.id,
                            jobData,
                          );

                          return buildCard(
                            job,
                            status,
                            apps[index].id,
                            appliedAt: data["createdAt"],
                            isUnread: isUnread,
                            userId: user.uid,
                          );
                        },
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

  /// 🔥 reusable card
  List<Widget> buildOfferDetails(Map<String, dynamic> offer) {
    final rows = <Widget>[];

    void addRow(String label, dynamic value) {
      final text = value?.toString().trim() ?? "";
      if (text.isEmpty) return;

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text("$label: $text"),
        ),
      );
    }

    String physicalAddressFromOffer() {
      final street = offer["siteStreet"]?.toString().trim() ?? "";
      final city = offer["siteCity"]?.toString().trim() ?? "";
      final postcode = offer["sitePostcode"]?.toString().trim() ?? "";
      final fromParts = [
        street,
        city,
        postcode,
      ].where((part) => part.isNotEmpty).join(", ");
      if (fromParts.isNotEmpty) return fromParts;

      return (offer["fullAddress"] ?? offer["siteAddress"])?.toString() ?? "";
    }

    addRow("Work format", offer["workFormat"]);
    addRow("Rate / price", offer["rate"] == null ? null : "£${offer["rate"]}");
    addRow("Work period", offer["workPeriod"]);
    addRow("Hours per week", offer["weeklyHours"]);
    addRow("Schedule", offer["schedule"]);
    addRow("Start", offer["startDateTime"] ?? offer["startDate"]);
    addRow("Site address", physicalAddressFromOffer());
    addRow("Required on first day", offer["firstDayRequirements"]);
    addRow("Description", offer["description"] ?? offer["message"]);
    addRow("Valid until", offer["validUntil"]);

    if (rows.isEmpty) {
      rows.add(const Text("Offer details not provided"));
    }

    return rows;
  }

  /// 🔥 reusable card
  Widget buildCard(
    Job job,
    String status,
    String applicationId, {
    dynamic appliedAt,
    required bool isUnread,
    required String userId,
  }) {
    final unavailable = jobUnavailableForWorker(job);
    final unavailableMessage = unavailableJobMessage(job);

    return JobCard(
      job: job,
      unread: isUnread,
      statusText: statusLabel(status),
      statusColor: getStatusColor(status),
      detailText: applicationDateText(appliedAt),
      bottomAction:
          unavailable ? unavailableJobNotice(unavailableMessage) : null,
      onTap: () async {
        await ApplicationActivityService.markRead(applicationId, userId);
        if (!mounted) return;
        if (unavailable) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(unavailableMessage)),
          );
          return;
        }
        await openJobDetails(context, job.id, applicationId);
      },
    );
  }

  Future<void> openJobDetails(
    BuildContext context,
    String? jobId,
    String applicationId,
  ) async {
    if (jobId == null) return;

    final jobDoc =
        await FirebaseFirestore.instance.collection("jobs").doc(jobId).get();

    if (!jobDoc.exists) return;

    final job = Job.fromFirestore(
      jobDoc.id,
      jobDoc.data()!,
    );

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          job: job,
          applicationId: applicationId,
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

  Widget buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        children: [
          filterDropdown(
            label: "Status",
            value: statusFilter,
            items: const [
              DropdownMenuItem(value: "all", child: Text("All")),
              DropdownMenuItem(value: "review", child: Text("In review")),
              DropdownMenuItem(
                  value: "negotiation", child: Text("Negotiation")),
              DropdownMenuItem(value: "offer", child: Text("Offer")),
              DropdownMenuItem(value: "rejected", child: Text("Rejected")),
              DropdownMenuItem(value: "hired", child: Text("Hired")),
              DropdownMenuItem(value: "withdrawn", child: Text("Withdrawn")),
            ],
            onChanged: (value) => setState(() => statusFilter = value),
          ),
        ],
      ),
    );
  }

  Widget filterDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items,
      isExpanded: true,
      decoration: const InputDecoration(
        border: StroykaInputBorder(),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
      ),
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
    );
  }
}
