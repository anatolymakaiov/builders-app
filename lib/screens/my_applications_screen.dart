import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/job.dart';
import '../screens/job_details_screen.dart';
import '../services/application_activity_service.dart';
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
  String jobFilter = "all";
  String offerFilter = "all";

  Color getStatusColor(String status) {
    switch (status) {
      case "accepted":
      case "offer_accepted":
        return Colors.green;
      case "offer_sent":
        return AppColors.greenDark;
      case "negotiation":
        return Colors.purple;
      case "rejected":
        return Colors.red;
      default:
        return AppColors.ink;
    }
  }

  bool matchesStatusFilter(String status) {
    switch (statusFilter) {
      case "sent":
        return status == "pending" || status == "applied";
      case "review":
        return status == "pending" || status == "review";
      case "negotiation":
        return status == "negotiation";
      case "offer":
        return status == "offer_sent";
      case "rejected":
        return status == "rejected";
      default:
        return true;
    }
  }

  bool matchesJobFilter(String status) {
    switch (jobFilter) {
      case "new":
        return status != "accepted" && status != "offer_accepted";
      case "current":
        return status == "accepted" || status == "offer_accepted";
      default:
        return true;
    }
  }

  bool matchesOfferFilter(String status) {
    switch (offerFilter) {
      case "review":
        return status == "offer_sent";
      case "accepted":
        return status == "accepted" || status == "offer_accepted";
      default:
        return true;
    }
  }

  String statusLabel(String status) {
    switch (status) {
      case "pending":
      case "applied":
        return "SENT";
      case "review":
        return "IN REVIEW";
      case "negotiation":
        return "NEGOTIATION";
      case "offer_sent":
        return "OFFER";
      case "accepted":
      case "offer_accepted":
        return "ACCEPTED";
      case "rejected":
        return "REJECTED";
      default:
        return status.toUpperCase();
    }
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

      unique.sort(
        (a, b) => ApplicationActivityService.compareForUser(a, b, userId),
      );

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
                    final status = (data["status"] ?? "pending").toString();

                    return matchesStatusFilter(status) &&
                        matchesJobFilter(status) &&
                        matchesOfferFilter(status);
                  }).toList();

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

                      final status = data["status"] ?? "pending";
                      final jobId = data["jobId"];

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
    return JobCard(
      job: job,
      unread: isUnread,
      statusText: statusLabel(status),
      statusColor: getStatusColor(status),
      detailText: applicationDateText(appliedAt),
      onTap: () async {
        await ApplicationActivityService.markRead(applicationId, userId);
        if (!mounted) return;
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
              DropdownMenuItem(value: "all", child: Text("All statuses")),
              DropdownMenuItem(value: "sent", child: Text("Sent")),
              DropdownMenuItem(value: "review", child: Text("In review")),
              DropdownMenuItem(
                  value: "negotiation", child: Text("Negotiation")),
              DropdownMenuItem(value: "offer", child: Text("Offer")),
              DropdownMenuItem(value: "rejected", child: Text("Rejected")),
            ],
            onChanged: (value) => setState(() => statusFilter = value),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: filterDropdown(
                  label: "Your job",
                  value: jobFilter,
                  items: const [
                    DropdownMenuItem(value: "all", child: Text("All jobs")),
                    DropdownMenuItem(value: "new", child: Text("Your new job")),
                    DropdownMenuItem(
                      value: "current",
                      child: Text("Current job"),
                    ),
                  ],
                  onChanged: (value) => setState(() => jobFilter = value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: filterDropdown(
                  label: "Your offers",
                  value: offerFilter,
                  items: const [
                    DropdownMenuItem(value: "all", child: Text("All offers")),
                    DropdownMenuItem(
                      value: "review",
                      child: Text("Offers in review"),
                    ),
                    DropdownMenuItem(
                      value: "accepted",
                      child: Text("Accepted offers"),
                    ),
                  ],
                  onChanged: (value) => setState(() => offerFilter = value),
                ),
              ),
            ],
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
        border: OutlineInputBorder(),
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
