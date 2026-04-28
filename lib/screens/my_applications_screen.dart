import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/job.dart';
import '../screens/job_details_screen.dart';
import '../services/application_activity_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

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

                            final jobData = jobSnapshot.data!.data()
                                as Map<String, dynamic>;

                            final job = Job.fromFirestore(
                              jobSnapshot.data!.id,
                              jobData,
                            );

                            return buildCard(
                              job,
                              status,
                              apps[index].id,
                              isUnread: isUnread,
                              userId: user.uid,
                            );
                          },
                        );
                      }

                      /// ✅ если есть jobTitle — просто показываем
                      return InkWell(
                        onTap: () async {
                          await ApplicationActivityService.markRead(
                            apps[index].id,
                            user.uid,
                          );
                          if (!context.mounted) return;
                          await openJobDetails(
                            context,
                            jobId,
                            apps[index].id,
                          );
                        },
                        child: StroykaSurface(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          padding: const EdgeInsets.all(16),
                          borderRadius: BorderRadius.circular(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              /// TITLE
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
                                  Expanded(
                                    child: Text(
                                      jobTitle,
                                      style: TextStyle(
                                        fontWeight: isUnread
                                            ? FontWeight.w900
                                            : FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (isUnread)
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text(
                                    "Updated",
                                    style: TextStyle(
                                      color: AppColors.greenDark,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              if (!isUnread) const SizedBox(height: 0),

                              const SizedBox(height: 6),

                              /// STATUS
                              Text(
                                statusLabel(status),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text("Offer details",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      ...buildOfferDetails(offer!),
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
                                          .set({
                                        "status": "offer_accepted",
                                        "applicationActivityAt":
                                            FieldValue.serverTimestamp(),
                                        "updatedAt":
                                            FieldValue.serverTimestamp(),
                                        "unreadFor": FieldValue.arrayUnion(
                                          ApplicationActivityService
                                              .employerRecipients(data),
                                        ),
                                      }, SetOptions(merge: true));

                                      await FirebaseFirestore.instance
                                          .collection("jobs")
                                          .doc(jobId)
                                          .update({
                                        "filledPositions":
                                            FieldValue.increment(1)
                                      });

                                      final offer = data["offer"];
                                      if (offer is Map<String, dynamic>) {
                                        await NotificationService()
                                            .notifyWorkStartReminder(
                                          applicationId: apps[index].id,
                                          applicationData: data,
                                          offer: offer,
                                        );
                                      }
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
                                          .set({
                                        "status": "rejected",
                                        "applicationActivityAt":
                                            FieldValue.serverTimestamp(),
                                        "updatedAt":
                                            FieldValue.serverTimestamp(),
                                        "unreadFor": FieldValue.arrayUnion(
                                          ApplicationActivityService
                                              .employerRecipients(data),
                                        ),
                                      }, SetOptions(merge: true));
                                    },
                                    child: const Text("Decline"),
                                  ),
                                ),
                              ],
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

    addRow("Work format", offer["workFormat"]);
    addRow("Rate / price", offer["rate"] == null ? null : "£${offer["rate"]}");
    addRow("Work period", offer["workPeriod"]);
    addRow("Hours per week", offer["weeklyHours"]);
    addRow("Schedule", offer["schedule"]);
    addRow("Start", offer["startDateTime"] ?? offer["startDate"]);
    addRow("Site address", offer["siteAddress"]);
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
    required bool isUnread,
    required String userId,
  }) {
    return StroykaSurface(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: isUnread
            ? Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.green,
                  shape: BoxShape.circle,
                ),
              )
            : null,
        title: Text(
          job.title,
          style: TextStyle(
            color: AppColors.ink,
            fontWeight: isUnread ? FontWeight.w900 : FontWeight.w800,
          ),
        ),
        subtitle: Text([
          job.city,
          job.workFormatText,
          if (job.duration.isNotEmpty) job.duration,
          if (job.listRateText.isNotEmpty) job.listRateText,
        ].where((item) => item.trim().isNotEmpty).join(" • ")),
        trailing: Text(
          statusLabel(status),
          style: TextStyle(
            color: getStatusColor(status),
            fontWeight: FontWeight.bold,
          ),
        ),
        onTap: () async {
          await ApplicationActivityService.markRead(applicationId, userId);
          if (!mounted) return;
          await openJobDetails(context, job.id, applicationId);
        },
      ),
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
