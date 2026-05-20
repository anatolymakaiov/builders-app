import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'team_details_screen.dart';

import 'edit_profile_screen.dart';
import '../services/application_activity_service.dart';
import '../services/calendar_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/report_service.dart';
import '../services/support_request_service.dart';
import 'chat_screen.dart';
import '../widgets/make_offer_dialog.dart';
import '../widgets/phone_link.dart';
import '../widgets/profile_hamburger_menu.dart';
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

  Widget buildWorkerContactsSection(Map<String, dynamic> data) {
    final rows = <Widget>[];

    void addTextRow(String label, IconData icon, dynamic value) {
      final text = value?.toString().trim() ?? "";
      if (text.isEmpty) return;

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.greenDark, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      text,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final phone = data["phone"]?.toString().trim() ?? "";
    if (phone.isNotEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Phone",
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              PhoneLink(phone: phone),
            ],
          ),
        ),
      );
    }

    final extraPhones = List<String>.from(data["phones"] ?? [])
        .map((phone) => phone.trim())
        .where((phone) => phone.isNotEmpty)
        .toList();
    if (extraPhones.isNotEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Additional phones",
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              ...extraPhones.map(
                (phone) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: PhoneLink(phone: phone, compact: true),
                ),
              ),
            ],
          ),
        ),
      );
    }

    addTextRow("Email", Icons.email_outlined, data["email"]);
    addTextRow("Location", Icons.place_outlined, data["location"]);
    addTextRow("Contact name", Icons.person_outline, data["name"]);
    addTextRow("Contact person", Icons.badge_outlined, data["contactPerson"]);
    addTextRow(
      "Nickname",
      Icons.alternate_email,
      data["nickname"] ?? data["username"] ?? data["nickName"],
    );

    if (rows.isEmpty) {
      return const Text(
        "No contact details available",
        style: TextStyle(
          color: AppColors.muted,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
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

  String _composePhysicalAddress({
    required String street,
    required String city,
    required String postcode,
  }) {
    return [
      street.trim(),
      city.trim(),
      postcode.trim(),
    ].where((part) => part.isNotEmpty).join(", ");
  }

  Map<String, String> _physicalAddressFieldsFrom(
    Map<String, dynamic> source,
  ) {
    final street =
        (source["siteStreet"] ?? source["street"] ?? "").toString().trim();
    final city = (source["siteCity"] ?? source["city"] ?? "").toString().trim();
    final postcode =
        (source["sitePostcode"] ?? source["postcode"] ?? "").toString().trim();
    final county =
        (source["siteCounty"] ?? source["county"] ?? "").toString().trim();
    final composedAddress = _composePhysicalAddress(
      street: street,
      city: city,
      postcode: postcode,
    );
    final projectNames = {
      source["jobSite"]?.toString().trim().toLowerCase(),
      source["site"]?.toString().trim().toLowerCase(),
    }..removeWhere((value) => value == null || value.isEmpty);
    final addressCandidates = [
      source["siteAddress"],
      source["fullAddress"],
      source["location"],
      composedAddress,
    ];
    final storedAddress = addressCandidates
        .map((value) => value?.toString().trim() ?? "")
        .where((value) => value.isNotEmpty)
        .firstWhere(
          (value) => !projectNames.contains(value.toLowerCase()),
          orElse: () => "",
        )
        .trim();

    return {
      "siteStreet": street,
      "siteCity": city,
      "sitePostcode": postcode,
      "siteCounty": county,
      "siteAddress": storedAddress.isNotEmpty ? storedAddress : composedAddress,
      "fullAddress": storedAddress.isNotEmpty ? storedAddress : composedAddress,
    };
  }

  Future<Map<String, String>> _loadOfferPhysicalAddressFields(
    Map<String, dynamic> applicationData,
  ) async {
    final fromApplication = _physicalAddressFieldsFrom(applicationData);
    if ((fromApplication["siteAddress"] ?? "").isNotEmpty) {
      return fromApplication;
    }

    final jobId = applicationData["jobId"]?.toString();
    if (jobId == null || jobId.isEmpty) return fromApplication;

    final jobDoc =
        await FirebaseFirestore.instance.collection("jobs").doc(jobId).get();
    final jobData = jobDoc.data();
    if (jobData == null) return fromApplication;

    return _physicalAddressFieldsFrom(jobData);
  }

  Future<void> openExpandedOfferDialog(
    BuildContext context, {
    required String applicationId,
    required Map<String, dynamic> applicationData,
  }) async {
    final physicalAddressFields =
        await _loadOfferPhysicalAddressFields(applicationData);
    if (!context.mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => MakeOfferDialog(
        physicalAddressFields: physicalAddressFields,
      ),
    );

    if (result == null) return;

    try {
      final offer = {
        "jobType": result["jobType"],
        "workFormat": _jobTypeLabel(result["jobType"]?.toString() ?? "hourly"),
        "rate": result["rate"],
        "workPeriod": result["workPeriod"],
        "weeklyHours": result["weeklyHours"],
        "schedule": result["schedule"],
        "startDateTime": result["startDateTime"],
        if (result["startDateTimestamp"] is DateTime)
          "startDateTimestamp":
              Timestamp.fromDate(result["startDateTimestamp"] as DateTime),
        "siteStreet": physicalAddressFields["siteStreet"],
        "siteCity": physicalAddressFields["siteCity"],
        "sitePostcode": physicalAddressFields["sitePostcode"],
        "siteCounty": physicalAddressFields["siteCounty"],
        "siteAddress": result["siteAddress"],
        "fullAddress": result["siteAddress"],
        "firstDayRequirements": result["firstDayRequirements"],
        "description": result["description"],
        "validUntil": result["validUntil"],
        if (result["validUntilTimestamp"] is DateTime)
          "validUntilTimestamp":
              Timestamp.fromDate(result["validUntilTimestamp"] as DateTime),
        "startDate": result["startDateTime"],
        "message": result["description"],
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
    } catch (e) {
      debugPrint("MAKE OFFER ERROR: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not send offer")),
      );
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
                      border: StroykaInputBorder(),
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
                        StroykaAvatar(
                          imageUrl: avatarUrl is String ? avatarUrl : null,
                          fallbackIcon: Icons.groups,
                          size: 58,
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

  Widget buildLiveApplicationHeaderControls({
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

    Widget statusBadge(String status) {
      switch (status) {
        case "negotiation":
          return AppChip.status("Negotiation", color: AppColors.purple);
        case "offer_sent":
          return AppChip.status("Offer Sent", color: AppColors.greenDark);
        case "offer_withdrawn":
          return AppChip.status("Offer Withdrawn", color: AppColors.warning);
        case "offer_accepted":
        case "accepted":
          return AppChip.status("Hired", color: AppColors.success);
        case "offer_rejected":
          return AppChip.status("Offer Rejected", color: AppColors.danger);
        case "rejected":
          return AppChip.status("Rejected", color: AppColors.danger);
        case "withdrawn":
          return AppChip.status("Withdrawn", color: AppColors.muted);
        default:
          return AppChip.status("Pending", color: AppColors.greenDark);
      }
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("applications")
          .doc(applicationId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Row(
            children: [
              AppChip.status("Pending", color: AppColors.greenDark),
              const Spacer(),
              const SizedBox(width: 42, height: 42),
            ],
          );
        }

        final applicationData =
            snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final status = canonicalStatus(applicationData["status"]);

        Future<void> updateStatus(String nextStatus) async {
          await ApplicationActivityService.updateStatus(
            applicationId: applicationId,
            status: nextStatus,
            unreadFor: ApplicationActivityService.workerRecipients(
              applicationData,
            ),
          );
        }

        Future<void> openMessage({required bool startNegotiation}) async {
          if (startNegotiation) {
            await updateStatus("negotiation");
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
        }

        Future<void> reopenRejectedApplication() async {
          await updateStatus("negotiation");

          await NotificationService().notifyApplicationReopened(
            applicationId: applicationId,
            applicationData: applicationData,
          );
        }

        Future<void> addAcceptedOfferToCalendar() async {
          final offerRaw = applicationData["offer"];
          if (offerRaw is! Map) return;

          final offer = Map<String, dynamic>.from(offerRaw);
          final jobTitle =
              applicationData["jobTitle"]?.toString().trim().isNotEmpty == true
                  ? applicationData["jobTitle"].toString().trim()
                  : "Construction job";
          final workerName =
              applicationData["workerName"]?.toString().trim().isNotEmpty ==
                      true
                  ? applicationData["workerName"].toString().trim()
                  : applicationData["teamName"]?.toString().trim().isNotEmpty ==
                          true
                      ? applicationData["teamName"].toString().trim()
                      : "Worker";
          final location = (applicationData["jobAddress"] ??
                  applicationData["jobLocation"] ??
                  applicationData["siteAddress"] ??
                  applicationData["fullAddress"])
              ?.toString();
          final contactInfo = [
            applicationData["workerPhone"]?.toString().trim() ?? "",
            applicationData["workerEmail"]?.toString().trim() ?? "",
          ].where((value) => value.isNotEmpty).join(" / ");

          final added = await CalendarService.addOfferToCalendar(
            title: "$jobTitle - $workerName",
            offer: offer,
            fallbackLocation: location,
            workerName: workerName,
            contactInfo: contactInfo.isEmpty ? null : contactInfo,
          );

          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                added
                    ? "Offer added to calendar"
                    : "Enter the start date in a calendar-readable format",
              ),
            ),
          );
        }

        List<
            ({
              bool danger,
              IconData icon,
              String label,
              Future<void> Function() run
            })> actions() {
          final canStartNegotiation = status == "pending" ||
              status == "offer_withdrawn" ||
              status == "offer_rejected";

          if (status == "rejected") {
            return [
              (
                danger: false,
                icon: Icons.chat_bubble_outline,
                label: "Message",
                run: () => openMessage(startNegotiation: false),
              ),
              (
                danger: false,
                icon: Icons.replay_outlined,
                label: "Reopen Application",
                run: reopenRejectedApplication,
              ),
            ];
          }

          if (canStartNegotiation) {
            return [
              (
                danger: false,
                icon: Icons.forum_outlined,
                label: "Message / Negotiation",
                run: () => openMessage(startNegotiation: true),
              ),
              (
                danger: false,
                icon: Icons.local_offer_outlined,
                label: "Make Offer",
                run: () => openExpandedOfferDialog(
                      context,
                      applicationId: applicationId,
                      applicationData: applicationData,
                    ),
              ),
              (
                danger: true,
                icon: Icons.close,
                label: "Reject",
                run: () => updateStatus("rejected"),
              ),
            ];
          }

          if (status == "negotiation") {
            return [
              (
                danger: false,
                icon: Icons.chat_bubble_outline,
                label: "Message",
                run: () => openMessage(startNegotiation: false),
              ),
              (
                danger: false,
                icon: Icons.local_offer_outlined,
                label: "Make Offer",
                run: () => openExpandedOfferDialog(
                      context,
                      applicationId: applicationId,
                      applicationData: applicationData,
                    ),
              ),
              (
                danger: true,
                icon: Icons.close,
                label: "Reject",
                run: () => updateStatus("rejected"),
              ),
            ];
          }

          if (status == "offer_sent") {
            return [
              (
                danger: false,
                icon: Icons.chat_bubble_outline,
                label: "Message",
                run: () => openMessage(startNegotiation: false),
              ),
              (
                danger: true,
                icon: Icons.undo,
                label: "Withdraw Offer",
                run: () => updateStatus("offer_withdrawn"),
              ),
            ];
          }

          if (status == "offer_accepted" || status == "accepted") {
            return [
              (
                danger: false,
                icon: Icons.chat_bubble_outline,
                label: "Message",
                run: () => openMessage(startNegotiation: false),
              ),
              (
                danger: false,
                icon: Icons.calendar_month_outlined,
                label: "Add to Calendar",
                run: addAcceptedOfferToCalendar,
              ),
            ];
          }

          return [
            (
              danger: false,
              icon: Icons.chat_bubble_outline,
              label: "Message",
              run: () => openMessage(startNegotiation: false),
            ),
          ];
        }

        final menuActions = actions();

        return Row(
          children: [
            statusBadge(status),
            const Spacer(),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.blueprintLine.withValues(alpha: 0.36),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.glow.withValues(alpha: 0.12),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: StroykaPopupMenuButton<int>(
                tooltip: "Actions",
                actions: [
                  for (var i = 0; i < menuActions.length; i++)
                    StroykaMenuAction<int>(
                      value: i,
                      label: menuActions[i].label,
                      icon: menuActions[i].icon,
                      danger: menuActions[i].danger,
                    ),
                ],
                onSelected: (index) async {
                  await menuActions[index].run();
                },
              ),
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
      drawer: isMyProfile ? const ProfileHamburgerMenu(role: "worker") : null,
      appBar: AppBar(
        leading: isMyProfile
            ? Builder(
                builder: (context) => const ProfileHamburgerButton(),
              )
            : null,
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
            length: 4,
            child: StroykaScreenBody(
              child: Column(
                children: [
                  StroykaProfileHeader(
                    title: name.toString(),
                    avatarUrl: photo is String ? photo : null,
                    headerImageUrl: headerImage,
                    fallbackIcon: Icons.person,
                    headerControls: canShowActions
                        ? buildLiveApplicationHeaderControls(
                            context: context,
                            applicationId: applicationId,
                            employerId: employerId!,
                            jobId: jobId!,
                          )
                        : null,
                  ),
                  const StroykaTabBar(
                    labels: ["Info", "Contacts", "Photos", "Teams"],
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
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          children: [
                            StroykaSurface(
                              padding: const EdgeInsets.all(18),
                              child: buildWorkerContactsSection(data),
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
                          if (!dialogContext.mounted) return;

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
                        if (!dialogContext.mounted) return;
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
                          if (!dialogContext.mounted) return;
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
