import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/job.dart';
import '../services/application_status_utils.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';
import '../widgets/app_photo_grid_gallery.dart';
import '../widgets/phone_link.dart';
import 'job_details_screen.dart';
import 'worker_profile_screen.dart';

class EmployerOfferDetailsScreen extends StatelessWidget {
  final String applicationId;
  final String? fallbackJobId;
  final String? fallbackWorkerId;

  const EmployerOfferDetailsScreen({
    super.key,
    required this.applicationId,
    this.fallbackJobId,
    this.fallbackWorkerId,
  });

  Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String text(dynamic value) => value?.toString().trim() ?? "";

  String firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = text(data[key]);
      if (value.isNotEmpty) return value;
    }
    return "";
  }

  String displayDate(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      return "${date.day.toString().padLeft(2, "0")}/"
          "${date.month.toString().padLeft(2, "0")}/${date.year}";
    }
    if (value is DateTime) {
      return "${value.day.toString().padLeft(2, "0")}/"
          "${value.month.toString().padLeft(2, "0")}/${value.year}";
    }
    return text(value);
  }

  String physicalAddress(
    Map<String, dynamic> offer,
    Map<String, dynamic> application,
    Map<String, dynamic>? job,
  ) {
    final direct = firstText(offer, ["fullAddress", "siteAddress"]);
    if (direct.isNotEmpty) return direct;

    final street = text(offer["siteStreet"]).isNotEmpty
        ? text(offer["siteStreet"])
        : firstText(application, ["siteStreet", "jobSiteStreet"]);
    final city = text(offer["siteCity"]).isNotEmpty
        ? text(offer["siteCity"])
        : firstText(application, ["siteCity", "jobSiteCity"]);
    final postcode = text(offer["sitePostcode"]).isNotEmpty
        ? text(offer["sitePostcode"])
        : firstText(application, ["sitePostcode", "jobPostcode"]);
    final parts = [street, city, postcode]
        .where((part) => part.trim().isNotEmpty)
        .join(", ");
    if (parts.isNotEmpty) return parts;

    return firstText(application, [
      "jobSite",
      "site",
      "siteName",
      "location",
      "address",
    ]).isNotEmpty
        ? firstText(application, [
            "jobSite",
            "site",
            "siteName",
            "location",
            "address",
          ])
        : firstText(job ?? const {}, [
            "site",
            "siteName",
            "location",
            "address",
            "postcode",
          ]);
  }

  String rateText(Map<String, dynamic> offer, Map<String, dynamic>? job) {
    final direct = text(offer["rate"]);
    if (direct.isNotEmpty) {
      return direct.contains("£") ? direct : "£$direct";
    }
    final salary = text(job?["salary"]);
    if (salary.isNotEmpty && salary != "0") return "£$salary";
    return firstText(job ?? const {}, ["payType", "paymentType", "priceType"]);
  }

  String workerIdFrom(Map<String, dynamic> application) {
    final direct =
        firstText(application, ["workerId", "userId", "applicantId"]);
    if (direct.isNotEmpty) return direct;
    final members = application["members"];
    if (members is List && members.isNotEmpty) return text(members.first);
    return text(fallbackWorkerId);
  }

  String jobIdFrom(Map<String, dynamic> application) {
    final direct = firstText(application, ["jobId", "vacancyId"]);
    return direct.isNotEmpty ? direct : text(fallbackJobId);
  }

  Future<Map<String, dynamic>?> loadDocument(
      String collection, String id) async {
    if (id.trim().isEmpty) return null;
    final doc =
        await FirebaseFirestore.instance.collection(collection).doc(id).get();
    return doc.data();
  }

  Future<List<String>> loadPortfolioUrls(String workerId) async {
    final urls = <String>[];
    final db = FirebaseFirestore.instance;

    final nestedSnapshot = await db
        .collection("users")
        .doc(workerId)
        .collection("portfolio")
        .get();
    for (final doc in nestedSnapshot.docs) {
      final url = doc.data()["imageUrl"] ?? doc.data()["image"];
      if (url != null) urls.add(url.toString());
    }

    final flatSnapshot = await db
        .collection("portfolio")
        .where("userId", isEqualTo: workerId)
        .get();
    for (final doc in flatSnapshot.docs) {
      final url = doc.data()["imageUrl"] ?? doc.data()["image"];
      final value = url?.toString();
      if (value != null && value.isNotEmpty && !urls.contains(value)) {
        urls.add(value);
      }
    }

    return urls;
  }

  Color statusColor(String status) {
    switch (status) {
      case "offer_accepted":
      case "accepted":
        return AppColors.success;
      case "offer_rejected":
      case "rejected":
        return AppColors.danger;
      case "offer_withdrawn":
      case "withdrawn":
        return AppColors.warning;
      case "negotiation":
        return AppColors.purple;
      default:
        return AppColors.greenDark;
    }
  }

  Widget detailRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return detailWidgetRow(
        label,
        Text(
          value,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ));
  }

  Widget detailWidgetRow(String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 126,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: child,
          ),
        ],
      ),
    );
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget offerSection(
    BuildContext context,
    Map<String, dynamic> application,
    Map<String, dynamic> offer,
    Map<String, dynamic>? job,
  ) {
    final status =
        ApplicationStatusUtils.normalizeStatus(application["status"]);
    final statusLabel =
        ApplicationStatusUtils.getStatusDisplayLabel(status, "employer");
    final jobTitle =
        firstText(application, ["jobTitle", "title", "position"]).isNotEmpty
            ? firstText(application, ["jobTitle", "title", "position"])
            : firstText(job ?? const {}, ["title", "trade", "position"]);
    final recipient = firstText(application, [
      "workerName",
      "applicantName",
      "recipientName",
      "teamName",
    ]);
    final sentDate = displayDate(offer["createdAt"]);
    final responseDate = displayDate(
      application["offerAcceptedAt"] ??
          application["offerRejectedAt"] ??
          application["updatedAt"] ??
          application["applicationActivityAt"],
    );

    return StroykaSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: sectionTitle("Offer details")),
              AppChip.status(statusLabel, color: statusColor(status)),
            ],
          ),
          detailRow("Vacancy", jobTitle),
          detailRow("Recipient", recipient),
          detailRow("Site", physicalAddress(offer, application, job)),
          detailRow("Pay / rate", rateText(offer, job)),
          detailRow("Work format", firstText(offer, ["workFormat", "jobType"])),
          detailRow(
              "Start date",
              displayDate(
                offer["startDateTimestamp"] ??
                    offer["startDateTime"] ??
                    offer["startDate"],
              )),
          detailRow("Duration", text(offer["workPeriod"])),
          detailRow("Hours", text(offer["weeklyHours"])),
          detailRow("Schedule", text(offer["schedule"])),
          detailRow(
            "Notes",
            firstText(offer, ["description", "message", "notes"]),
          ),
          detailRow("First day", text(offer["firstDayRequirements"])),
          detailRow("Sent", sentDate),
          detailRow("Response", responseDate),
          detailRow("Valid until",
              displayDate(offer["validUntilTimestamp"] ?? offer["validUntil"])),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => openVacancy(context, jobIdFrom(application)),
            icon: const Icon(Icons.work_outline),
            label: const Text("View Vacancy"),
          ),
        ],
      ),
    );
  }

  Future<void> openVacancy(BuildContext context, String jobId) async {
    if (jobId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vacancy is no longer available.")),
      );
      return;
    }
    final doc =
        await FirebaseFirestore.instance.collection("jobs").doc(jobId).get();
    if (!context.mounted) return;
    final data = doc.data();
    if (!doc.exists || data == null || data["deleted"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vacancy is no longer available.")),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(job: Job.fromFirestore(doc.id, data)),
      ),
    );
  }

  Widget workerSection(
    BuildContext context,
    String workerId,
    Map<String, dynamic>? worker,
  ) {
    if (workerId.isEmpty || worker == null) {
      return const StroykaSurface(
        padding: EdgeInsets.all(18),
        child: Text("Worker profile is no longer available."),
      );
    }

    final status = text(worker["status"]).toLowerCase();
    final unavailable = worker["deleted"] == true ||
        worker["active"] == false ||
        worker["accountDeleted"] == true ||
        status == "deleted";
    if (unavailable) {
      return const StroykaSurface(
        padding: EdgeInsets.all(18),
        child: Text("Worker profile is no longer available."),
      );
    }

    final name = firstText(worker, ["name", "fullName", "displayName"]);
    final trade = firstText(worker, ["trade", "position", "jobTitle"]);
    final photo = firstText(worker, ["photo", "photoUrl", "avatarUrl"]);
    final location = firstText(worker, ["location", "postcode", "city"]);
    final bio = firstText(worker, ["bio", "about", "summary"]);
    final phone = firstText(worker, ["phone", "phoneNumber"]);
    final email = firstText(worker, ["email"]);

    return StroykaSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle("Worker"),
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: AppColors.surfaceAlt,
                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                child:
                    photo.isEmpty ? const Icon(Icons.person, size: 30) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? "Worker" : name,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (trade.isNotEmpty)
                      Text(
                        trade,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          detailRow("Location", location),
          detailRow("About", bio),
          if (phone.isNotEmpty)
            detailWidgetRow(
              "Phone",
              Align(
                alignment: Alignment.centerLeft,
                child: PhoneLink(phone: phone, label: phone, compact: true),
              ),
            ),
          detailRow("Email", email),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WorkerProfileScreen(userId: workerId),
                ),
              );
            },
            icon: const Icon(Icons.person_outline),
            label: const Text("Open worker profile"),
          ),
          const SizedBox(height: 18),
          FutureBuilder<List<String>>(
            future: loadPortfolioUrls(workerId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              final photos = snapshot.data ?? const <String>[];
              if (photos.isEmpty) {
                return const Text("No portfolio photos yet");
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Work gallery",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  AppPhotoGridGallery(imageUrls: photos),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StroykaBackground(
      asset: AppAssets.backgroundHighriseSunset,
      child: Scaffold(
        appBar: AppBar(title: const Text("Offer Details")),
        body: StroykaScreenBody(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection("applications")
                .doc(applicationId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final application = snapshot.data?.data();
              if (application == null) {
                return const Center(
                    child: Text("Offer is no longer available."));
              }

              final offer = asMap(application["offer"]);
              final workerId = workerIdFrom(application);
              final jobId = jobIdFrom(application);

              return FutureBuilder<List<Map<String, dynamic>?>>(
                future: Future.wait([
                  loadDocument("jobs", jobId),
                  loadDocument("users", workerId),
                ]),
                builder: (context, detailsSnapshot) {
                  final job = detailsSnapshot.data?.first;
                  final worker = detailsSnapshot.data != null &&
                          detailsSnapshot.data!.length > 1
                      ? detailsSnapshot.data![1]
                      : null;

                  return RefreshIndicator(
                    onRefresh: () async {},
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(18),
                      children: [
                        offerSection(context, application, offer, job),
                        const SizedBox(height: 16),
                        if (detailsSnapshot.connectionState ==
                                ConnectionState.waiting &&
                            worker == null)
                          const StroykaSurface(
                            padding: EdgeInsets.all(18),
                            child: LinearProgressIndicator(),
                          )
                        else
                          workerSection(context, workerId, worker),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
