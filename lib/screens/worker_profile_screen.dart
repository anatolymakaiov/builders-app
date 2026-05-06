import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'team_details_screen.dart';

import 'edit_profile_screen.dart';
import '../services/application_activity_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/report_service.dart';
import '../services/support_request_service.dart';
import 'chat_screen.dart';
import '../widgets/phone_link.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class WorkerProfileScreen extends StatelessWidget {
  final String userId;
  final String? jobId;
  final String? employerId;

  const WorkerProfileScreen({
    super.key,
    required this.userId,
    this.jobId,
    this.employerId,
  });

  Widget buildInfoSection(String title, dynamic value) {
    final text = value?.toString().trim() ?? "";
    if (text.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(text),
        ],
      ),
    );
  }

  Widget buildPhoneSection(dynamic value) {
    final phone = value?.toString().trim() ?? "";
    if (phone.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Phone",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          PhoneLink(phone: phone),
        ],
      ),
    );
  }

  List<Widget> buildOfferDetails(Map<String, dynamic> offer) {
    final rows = <Widget>[];

    void addRow(String label, dynamic value) {
      final text = value?.toString().trim() ?? "";
      if (text.isEmpty) return;

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
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

  String _jobTypeLabel(String jobType) {
    switch (jobType) {
      case "hourly":
        return "Daywork";
      case "price":
        return "Price";
      case "negotiable":
        return "Negotiable";
      default:
        return jobType;
    }
  }

  Future<void> openExpandedOfferDialog(
    BuildContext context, {
    required String applicationId,
    required Map<String, dynamic> applicationData,
  }) async {
    String jobType = "hourly";
    final rateController = TextEditingController();
    final workPeriodController = TextEditingController();
    final weeklyHoursController = TextEditingController();
    final scheduleController = TextEditingController();
    final startDateTimeController = TextEditingController();
    final siteAddressController = TextEditingController(
      text: (applicationData["jobSite"] ?? applicationData["site"] ?? "")
          .toString(),
    );
    final firstDayRequirementsController = TextEditingController();
    final descriptionController = TextEditingController();
    final validUntilController = TextEditingController();

    Widget offerTextField({
      required TextEditingController controller,
      required String label,
      String? hint,
      TextInputType? keyboardType,
      int maxLines = 1,
    }) {
      return TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      );
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Make offer"),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: jobType,
                        decoration: const InputDecoration(
                          labelText: "Work format",
                          hintText: "Daywork, price, negotiable",
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: "hourly",
                            child: Text("Daywork"),
                          ),
                          DropdownMenuItem(
                            value: "price",
                            child: Text("Price"),
                          ),
                          DropdownMenuItem(
                            value: "negotiable",
                            child: Text("Negotiable"),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => jobType = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      offerTextField(
                        controller: rateController,
                        label: jobType == "price" ? "Price (£)" : "Rate (£)",
                        hint: jobType == "price"
                            ? "Total project price"
                            : "Hourly or day rate",
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      offerTextField(
                        controller: workPeriodController,
                        label: "Work period",
                        hint: "2 weeks, 3 months, ongoing",
                      ),
                      const SizedBox(height: 12),
                      offerTextField(
                        controller: weeklyHoursController,
                        label: "Hours per week",
                        hint: "40",
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      offerTextField(
                        controller: scheduleController,
                        label: "Work schedule",
                        hint: "7:00-17:00, 1 hour break",
                      ),
                      const SizedBox(height: 12),
                      offerTextField(
                        controller: startDateTimeController,
                        label: "Start date and time",
                        hint: "Monday 12 May, 7:00",
                      ),
                      const SizedBox(height: 12),
                      offerTextField(
                        controller: siteAddressController,
                        label: "Site address",
                        hint: "Full construction site address",
                      ),
                      const SizedBox(height: 12),
                      offerTextField(
                        controller: firstDayRequirementsController,
                        label: "Required on first day",
                        hint: "Documents, certifications, tools, PPE, etc.",
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      offerTextField(
                        controller: descriptionController,
                        label: "Offer description",
                        hint: "Additional conditions, notes, or expectations",
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      offerTextField(
                        controller: validUntilController,
                        label: "Offer valid until",
                        hint: "Friday 16 May, 18:00",
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (startDateTimeController.text.trim().isEmpty ||
                        siteAddressController.text.trim().isEmpty) {
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text("Send offer"),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) {
      rateController.dispose();
      workPeriodController.dispose();
      weeklyHoursController.dispose();
      scheduleController.dispose();
      startDateTimeController.dispose();
      siteAddressController.dispose();
      firstDayRequirementsController.dispose();
      descriptionController.dispose();
      validUntilController.dispose();
      return;
    }

    try {
      final offer = {
        "jobType": jobType,
        "workFormat": _jobTypeLabel(jobType),
        "rate": rateController.text.trim(),
        "workPeriod": workPeriodController.text.trim(),
        "weeklyHours": weeklyHoursController.text.trim(),
        "schedule": scheduleController.text.trim(),
        "startDateTime": startDateTimeController.text.trim(),
        "siteAddress": siteAddressController.text.trim(),
        "firstDayRequirements": firstDayRequirementsController.text.trim(),
        "description": descriptionController.text.trim(),
        "validUntil": validUntilController.text.trim(),
        "startDate": startDateTimeController.text.trim(),
        "message": descriptionController.text.trim(),
        "createdAt": FieldValue.serverTimestamp(),
      };
      final notificationOffer = Map<String, dynamic>.from(offer)
        ..remove("createdAt");

      await ApplicationActivityService.updateStatus(
        applicationId: applicationId,
        status: "offer_sent",
        unreadFor: ApplicationActivityService.workerRecipients(applicationData),
        extra: {"offer": offer},
      );

      await NotificationService().notifyOfferCreated(
        applicationId: applicationId,
        applicationData: applicationData,
        offer: notificationOffer,
      );
    } finally {
      rateController.dispose();
      workPeriodController.dispose();
      weeklyHoursController.dispose();
      scheduleController.dispose();
      startDateTimeController.dispose();
      siteAddressController.dispose();
      firstDayRequirementsController.dispose();
      descriptionController.dispose();
      validUntilController.dispose();
    }
  }

  String textFromListOrString(dynamic value) {
    if (value == null) return "";
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join("\n");
    }
    return value.toString();
  }

  String experienceDurationText(Map<String, dynamic> data) {
    final years = int.tryParse(data["experienceYears"]?.toString() ?? "") ?? 0;
    final months =
        int.tryParse(data["experienceMonths"]?.toString() ?? "") ?? 0;
    final parts = <String>[];

    if (years > 0) {
      parts.add("$years ${years == 1 ? "year" : "years"}");
    }
    if (months > 0) {
      parts.add("$months ${months == 1 ? "month" : "months"}");
    }

    return parts.join(" ");
  }

  List<Map<String, dynamic>> parseReferences(dynamic value) {
    if (value is! List) return [];

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item.values.any(
              (field) => field != null && field.toString().trim().isNotEmpty,
            ))
        .toList();
  }

  List<String> teamMemberIds(dynamic value) {
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

  Widget buildReferencesSection(dynamic value) {
    final references = parseReferences(value);
    if (references.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "References",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...references.map((reference) {
            final name = reference["name"]?.toString().trim() ?? "";
            final company = reference["company"]?.toString().trim() ?? "";
            final phone = reference["phone"]?.toString().trim() ?? "";
            final email = reference["email"]?.toString().trim() ?? "";

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name.isNotEmpty)
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  if (company.isNotEmpty) Text(company),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    PhoneLink(phone: phone),
                  ],
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(email),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<List<String>> loadPortfolioUrls() async {
    final urls = <String>[];

    final nestedSnapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("portfolio")
        .get();

    for (final doc in nestedSnapshot.docs) {
      final data = doc.data();
      final url = data["imageUrl"] ?? data["image"];
      if (url != null) urls.add(url.toString());
    }

    final flatSnapshot = await FirebaseFirestore.instance
        .collection("portfolio")
        .where("userId", isEqualTo: userId)
        .get();

    for (final doc in flatSnapshot.docs) {
      final data = doc.data();
      final url = data["imageUrl"] ?? data["image"];
      if (url != null && !urls.contains(url.toString())) {
        urls.add(url.toString());
      }
    }

    return urls;
  }

  Stream<List<String>> portfolioUrlsStream() {
    return FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("portfolio")
        .snapshots()
        .asyncMap((nestedSnapshot) async {
      final urls = <String>[];

      for (final doc in nestedSnapshot.docs) {
        final data = doc.data();
        final url = data["imageUrl"] ?? data["image"];
        if (url != null) urls.add(url.toString());
      }

      final flatSnapshot = await FirebaseFirestore.instance
          .collection("portfolio")
          .where("userId", isEqualTo: userId)
          .get();

      for (final doc in flatSnapshot.docs) {
        final data = doc.data();
        final url = data["imageUrl"] ?? data["image"];
        if (url != null && !urls.contains(url.toString())) {
          urls.add(url.toString());
        }
      }

      return urls;
    });
  }

  Widget buildPortfolioGallery() {
    return StreamBuilder<List<String>>(
      stream: portfolioUrlsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Work gallery",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              LinearProgressIndicator(),
            ],
          );
        }

        if (snapshot.hasError) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Work gallery",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text("Could not load portfolio"),
            ],
          );
        }

        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Work gallery",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text("No portfolio yet"),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Work gallery",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final img = items[index];

                  return GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          child: Image.network(img, fit: BoxFit.contain),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        img,
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 110,
                          height: 110,
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            width: 110,
                            height: 110,
                            color: Colors.grey.shade100,
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 30),
          ],
        );
      },
    );
  }

  Future<void> leaveReview(BuildContext context) async {
    final employer = FirebaseAuth.instance.currentUser;
    if (employer == null) return;

    int rating = 5;
    final reviewController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Leave review"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          Icons.star,
                          color: index < rating ? Colors.orange : Colors.grey,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            rating = index + 1;
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reviewController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: "Review",
                      hintText: "Quality of work, reliability, communication",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Submit"),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) {
      reviewController.dispose();
      return;
    }

    final employerSnap = await FirebaseFirestore.instance
        .collection("users")
        .doc(employer.uid)
        .get();
    final employerData = employerSnap.data();

    await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("reviews")
        .add({
      "employerId": employer.uid,
      "employerName": employerData?["companyName"] ??
          employerData?["name"] ??
          employer.email ??
          "Employer",
      "rating": rating,
      "review": reviewController.text.trim(),
      "createdAt": FieldValue.serverTimestamp(),
      if (jobId != null) "jobId": jobId,
    });

    final reviewsSnapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .collection("reviews")
        .get();
    var total = 0.0;
    for (final doc in reviewsSnapshot.docs) {
      total += (doc.data()["rating"] ?? 0).toDouble();
    }

    final count = reviewsSnapshot.docs.length;
    await FirebaseFirestore.instance.collection("users").doc(userId).set({
      "rating": count == 0 ? 0 : total / count,
      "reviewsCount": count,
    }, SetOptions(merge: true));

    reviewController.dispose();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Review saved")),
    );
  }

  Widget buildReviewsSection(bool canReview) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(userId)
          .collection("reviews")
          .orderBy("createdAt", descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Employer reviews",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (canReview)
                    TextButton.icon(
                      onPressed: () => leaveReview(context),
                      icon: const Icon(Icons.rate_review),
                      label: const Text("Add review"),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (!snapshot.hasData)
                const LinearProgressIndicator()
              else if (docs.isEmpty)
                const Text("No reviews yet")
              else
                ...docs.map((doc) {
                  final review = doc.data() as Map<String, dynamic>;
                  final rating = review["rating"] ?? 0;
                  final text = review["review"]?.toString().trim() ?? "";
                  final employerName =
                      review["employerName"]?.toString() ?? "Employer";

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              employerName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.star,
                                color: Colors.orange, size: 18),
                            Text(rating.toString()),
                          ],
                        ),
                        if (text.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(text),
                        ],
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget buildWorkerTeamsSection(BuildContext context, bool isMyProfile) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("teams").snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return teamMemberIds(data["members"]).contains(userId) ||
              data["ownerId"] == userId;
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMyProfile) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await showCreateTeamDialog(context, userId);
                  },
                  icon: const Icon(Icons.group_add),
                  label: const Text(
                    "Create team",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              "Worker Teams",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 10),
            if (docs.isEmpty)
              const Text("No worker teams yet")
            else
              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = data["name"] ?? "Team";
                final members = teamMemberIds(data["members"]);
                final avatarUrl = data["avatarUrl"] ?? data["photo"];
                final description = data["description"]?.toString().trim();

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TeamDetailsScreen(
                          teamId: doc.id,
                          teamData: data,
                          showInternalChat: isMyProfile,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey.shade300,
                          backgroundImage: avatarUrl is String
                              ? NetworkImage(avatarUrl)
                              : null,
                          child: avatarUrl is String
                              ? null
                              : const Icon(Icons.groups),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (description != null && description.isNotEmpty)
                                Text(
                                  description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        Text("${members.length} members"),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_ios, size: 14),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget buildLiveApplicationActions({
    required BuildContext context,
    required String applicationId,
    required String employerId,
    required String jobId,
  }) {
    String canonicalStatus(dynamic value) {
      final status = value?.toString().toLowerCase().trim() ?? "pending";
      if (status == "review" || status == "in_review" || status == "applied") {
        return "pending";
      }
      return status.isEmpty ? "pending" : status;
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("applications")
          .doc(applicationId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.data!.exists) {
          return const Text("Application not found");
        }

        final applicationData =
            snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final status = canonicalStatus(applicationData["status"]);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (status == "pending" ||
                      status == "offer_withdrawn" ||
                      status == "offer_rejected") {
                    await ApplicationActivityService.updateStatus(
                      applicationId: applicationId,
                      status: "negotiation",
                      unreadFor: ApplicationActivityService.workerRecipients(
                        applicationData,
                      ),
                    );
                  }
                  final chatId = await ChatService.getOrCreateChat(
                    workerId: userId,
                    employerId: employerId,
                    jobId: jobId,
                    applicationId: applicationId,
                  );

                  if (!context.mounted) return;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(chatId: chatId),
                    ),
                  );
                },
                child: const Text("Message / Negotiation"),
              ),
            ),
            if (status == "offer_sent") ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Offer",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (applicationData["offer"] is Map<String, dynamic>)
                      ...buildOfferDetails(
                        applicationData["offer"] as Map<String, dynamic>,
                      )
                    else
                      const Text("Offer details not provided"),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (status == "offer_accepted") ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  "Worker hired",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.greenDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                status.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.greenDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Row(
              children: [
                if (status != "offer_accepted")
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Colors.red),
                      ),
                      onPressed: () async {
                        await ApplicationActivityService.updateStatus(
                          applicationId: applicationId,
                          status: "rejected",
                          unreadFor:
                              ApplicationActivityService.workerRecipients(
                            applicationData,
                          ),
                        );
                      },
                      child: const Text("Reject"),
                    ),
                  ),
                if (status != "offer_accepted") const SizedBox(width: 10),
                if (status == "pending" || status == "negotiation")
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => openExpandedOfferDialog(
                        context,
                        applicationId: applicationId,
                        applicationData: applicationData,
                      ),
                      child: const Text("Make offer"),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isMyProfile = currentUser?.uid == userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Worker Profile"),
        actions: [
          if (isMyProfile) ...[
            IconButton(
              tooltip: "Support",
              icon: const Icon(Icons.support_agent_outlined),
              onPressed: () => SupportRequestService.showSupportDialog(context),
            ),

            /// ✏️ EDIT
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final saved = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileScreen(),
                  ),
                );
                if (!context.mounted || saved != true) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Profile saved")),
                );
              },
            ),

            /// 🚪 LOGOUT
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
            ),
          ] else ...[
            IconButton(
              tooltip: "Report worker",
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => ReportService.showReportDialog(
                context,
                type: "worker",
                againstUserId: userId,
                jobId: jobId,
              ),
            ),
          ],
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(userId)
            .snapshots()
            .asyncMap((userSnap) async {
          final userData = userSnap.data() ?? <String, dynamic>{};

          String? applicationId;

          if (jobId != null && employerId != null) {
            final workerQuery = await FirebaseFirestore.instance
                .collection("applications")
                .where("jobId", isEqualTo: jobId)
                .where("employerId", isEqualTo: employerId)
                .where("workerId", isEqualTo: userId)
                .get();

            final applicantQuery = await FirebaseFirestore.instance
                .collection("applications")
                .where("jobId", isEqualTo: jobId)
                .where("employerId", isEqualTo: employerId)
                .where("applicantId", isEqualTo: userId)
                .get();

            final appDocs = {
              for (final doc in [...workerQuery.docs, ...applicantQuery.docs])
                doc.id: doc,
            }.values.toList();

            appDocs.sort((a, b) {
              final aData = a.data();
              final bData = b.data();
              final aTime = ApplicationActivityService.activityDate(aData);
              final bTime = ApplicationActivityService.activityDate(bData);
              return bTime.compareTo(aTime);
            });

            if (appDocs.isNotEmpty) {
              final appDoc = appDocs.first;
              applicationId = appDoc.id;
            }
          }

          String? currentRole;
          if (currentUser != null && !isMyProfile) {
            final currentSnap = await FirebaseFirestore.instance
                .collection("users")
                .doc(currentUser.uid)
                .get();
            currentRole = currentSnap.data()?["role"]?.toString();
          }

          return {
            "user": userData,
            "applicationId": applicationId,
            "currentRole": currentRole,
          };
        }),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final result = snapshot.data!;
          final data = result["user"] as Map<String, dynamic>;
          final String? applicationId = result["applicationId"];
          final String? currentRole = result["currentRole"];
          final name = data["name"] ?? "Worker";
          final bio = data["bio"] ?? "";
          final location = data["location"] ?? "";
          final photo = data["photo"];
          final headerImage =
              (data["profileHeaderImage"] ?? data["headerImage"])?.toString();
          final phone = data["phone"];
          final experience = data["experience"];
          final experienceDuration = experienceDurationText(data);
          final permits = data["permits"];
          final qualifications = data["qualifications"];
          final certifications = textFromListOrString(
              data["certificationsText"] ?? data["certifications"]);
          final education = data["education"];
          final previousWork = data["previousWork"];
          final references = data["references"];
          final canShowActions = !isMyProfile &&
              currentRole == "employer" &&
              applicationId != null &&
              employerId != null &&
              jobId != null;

          return DefaultTabController(
            length: canShowActions ? 4 : 3,
            child: StroykaScreenBody(
              child: Column(
                children: [
                  StroykaSurface(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 168,
                        child: Container(
                          decoration: BoxDecoration(
                            image: headerImage != null && headerImage.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(headerImage),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: Container(
                            alignment: Alignment.bottomCenter,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.08),
                                  Colors.black.withValues(alpha: 0.16),
                                ],
                              ),
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.82),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 32,
                                    backgroundColor: Colors.grey.shade300,
                                    backgroundImage: photo is String
                                        ? NetworkImage(photo)
                                        : null,
                                    child: photo == null
                                        ? const Icon(Icons.person, size: 30)
                                        : null,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  StroykaSurface(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(4),
                    borderRadius: BorderRadius.circular(999),
                    child: TabBar(
                      dividerColor: Colors.transparent,
                      indicator: const BoxDecoration(
                        color: AppColors.green,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Colors.white,
                      unselectedLabelColor: AppColors.ink,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                      tabs: [
                        const Tab(text: "Info"),
                        if (canShowActions) const Tab(text: "Actions"),
                        const Tab(text: "Photos"),
                        const Tab(text: "Teams"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          children: [
                            StroykaSurface(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  buildPhoneSection(phone),
                                  buildInfoSection("Location", location),
                                  buildInfoSection("About", bio),
                                  buildInfoSection(
                                      "Work experience", experienceDuration),
                                  buildInfoSection(
                                      "Experience details", experience),
                                  buildInfoSection(
                                      "Permits / licences", permits),
                                  buildInfoSection(
                                      "Qualifications", qualifications),
                                  buildInfoSection(
                                      "Certifications", certifications),
                                  buildInfoSection(
                                      "Education (optional)", education),
                                  buildInfoSection(
                                      "Previous work", previousWork),
                                  buildReferencesSection(references),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            StroykaSurface(
                              padding: const EdgeInsets.all(18),
                              child: buildReviewsSection(
                                  !isMyProfile && currentRole == "employer"),
                            ),
                          ],
                        ),
                        if (canShowActions)
                          ListView(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                            children: [
                              StroykaSurface(
                                padding: const EdgeInsets.all(18),
                                child: buildLiveApplicationActions(
                                  context: context,
                                  applicationId: applicationId,
                                  employerId: employerId!,
                                  jobId: jobId!,
                                ),
                              ),
                            ],
                          ),
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          children: [
                            StroykaSurface(
                              padding: const EdgeInsets.all(18),
                              child: buildPortfolioGallery(),
                            ),
                          ],
                        ),
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          children: [
                            StroykaSurface(
                              padding: const EdgeInsets.all(18),
                              child:
                                  buildWorkerTeamsSection(context, isMyProfile),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 🔥 CREATE TEAM DIALOG
Future<void> showCreateTeamDialog(
  BuildContext context,
  String userId,
) async {
  final controller = TextEditingController();
  final descriptionController = TextEditingController();
  final picker = ImagePicker();
  XFile? pickedAvatar;
  String? previewPath;
  var isSaving = false;
  var createRequestInProgress = false;
  String? validationError;

  Future<bool> teamAlreadyExists(String name) async {
    final normalizedName = name.trim().toLowerCase();

    final snap = await FirebaseFirestore.instance
        .collection("teams")
        .where("ownerId", isEqualTo: userId)
        .get();

    return snap.docs.any((doc) {
      final data = doc.data();
      final existingName =
          (data["nameLower"] ?? data["name"] ?? "").toString().toLowerCase();

      return existingName == normalizedName;
    });
  }

  await showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        return AlertDialog(
          title: const Text("Create team"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: isSaving
                      ? null
                      : () async {
                          final picked = await picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (picked == null) return;

                          setDialogState(() {
                            pickedAvatar = picked;
                            previewPath = picked.path;
                          });
                        },
                  child: CircleAvatar(
                    radius: 38,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage: previewPath != null
                        ? FileImage(File(previewPath!))
                        : null,
                    child: previewPath == null
                        ? const Icon(Icons.add_a_photo, size: 28)
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  enabled: !isSaving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: "Team name",
                    errorText: validationError,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  enabled: !isSaving,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "Team description",
                    hintText: "Trades, skills, availability, typical projects",
                  ),
                ),
                if (isSaving) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (createRequestInProgress) return;

                      final name = controller.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() {
                          validationError = "Enter team name";
                        });
                        return;
                      }

                      createRequestInProgress = true;
                      setDialogState(() {
                        isSaving = true;
                        validationError = null;
                      });

                      try {
                        final duplicate = await teamAlreadyExists(name);
                        if (duplicate) {
                          createRequestInProgress = false;
                          setDialogState(() {
                            isSaving = false;
                            validationError = "Team already exists";
                          });
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Team already exists"),
                              ),
                            );
                          }
                          return;
                        }

                        String? avatarUrl;

                        if (pickedAvatar != null) {
                          final ref = FirebaseStorage.instance.ref().child(
                              "team_avatars/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg");

                          await ref.putFile(File(pickedAvatar!.path));
                          avatarUrl = await ref.getDownloadURL();
                        }

                        await FirebaseFirestore.instance
                            .collection("teams")
                            .add({
                          "name": name,
                          "nameLower": name.toLowerCase(),
                          "description": descriptionController.text.trim(),
                          "ownerId": userId,
                          "createdBy": userId,
                          "members": [userId],
                          "memberKey": userId,
                          "memberStatuses": {userId: "active"},
                          if (avatarUrl != null) "avatarUrl": avatarUrl,
                          if (avatarUrl != null) "photo": avatarUrl,
                          "createdAt": FieldValue.serverTimestamp(),
                          "updatedAt": FieldValue.serverTimestamp(),
                        });

                        if (!dialogContext.mounted) return;

                        Navigator.pop(dialogContext);

                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Team created")),
                        );
                      } catch (e) {
                        debugPrint("CREATE TEAM ERROR: $e");
                        createRequestInProgress = false;
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          isSaving = false;
                        });
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text("Could not create team")),
                        );
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Create"),
            ),
          ],
        );
      },
    ),
  );

  controller.dispose();
  descriptionController.dispose();
}
