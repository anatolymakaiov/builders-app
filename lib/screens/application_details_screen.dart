import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'job_details_screen.dart';
import 'job_list_screen.dart';
import 'worker_profile_screen.dart';
import '../models/job.dart';
import '../services/application_activity_service.dart';
import '../services/application_status_utils.dart';
import '../services/calendar_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/offer_acceptance_service.dart';
import '../widgets/make_offer_dialog.dart';
import '../widgets/app_photo_grid_gallery.dart';
import '../widgets/phone_link.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class ApplicationDetailsScreen extends StatefulWidget {
  final String applicationId;
  final Map<String, dynamic> data;
  final bool initialOfferTab;

  const ApplicationDetailsScreen({
    super.key,
    required this.applicationId,
    required this.data,
    this.initialOfferTab = false,
  });

  @override
  State<ApplicationDetailsScreen> createState() =>
      _ApplicationDetailsScreenState();
}

class _ApplicationDetailsScreenState extends State<ApplicationDetailsScreen> {
  final Set<String> selectedMembers = <String>{};
  bool _inactiveApplicationSnackShown = false;

  String get applicationId => widget.applicationId;
  Map<String, dynamic> get data => widget.data;

  Future<void> updateStatus(
    BuildContext context,
    Map<String, dynamic> source,
    String status,
  ) async {
    final db = FirebaseFirestore.instance;

    final employerId = source["employerId"];
    final jobId = source["jobId"];

    if (employerId == null || jobId == null) return;

    try {
      /// 🔥 получаем вакансию
      final jobRef = db.collection("jobs").doc(jobId);

      await db.runTransaction((transaction) async {
        final jobSnap = await transaction.get(jobRef);

        if (!jobSnap.exists) throw Exception("Job not found");

        final jobData = jobSnap.data() as Map<String, dynamic>;

        final positions = jobData["positions"] ?? 1;
        final filled = jobData["filledPositions"] ?? 0;

        /// 🔥 сколько людей в заявке
        final workersCount = source["workersCount"] ?? 1;

        /// ❌ если не хватает мест — стоп
        if (status == "accepted" && (filled + workersCount) > positions) {
          throw Exception("Not enough positions");
        }

        /// ✅ обновляем статус заявки
        transaction.update(
          db.collection("applications").doc(applicationId),
          {
            "status": status,
            "applicationActivityAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "unreadFor": FieldValue.arrayUnion(
              ApplicationActivityService.workerRecipients(source),
            ),
          },
        );

        /// 🔥 если приняли — увеличиваем занятые места
        if (status == "offer_accepted") {
          transaction.update(jobRef, {
            "filledPositions": filled + workersCount,
          });
        }
      });

      await NotificationService().notifyApplicationStatus(
        applicationId: applicationId,
        applicationData: source,
        status: status,
      );

      if (!context.mounted) return;
    } catch (e) {
      debugPrint("UPDATE STATUS ERROR: $e");

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Not enough positions")),
      );
    }
  }

  String canonicalStatus(dynamic value) {
    return ApplicationStatusUtils.normalizeStatus(value);
  }

  Future<void> openChat(
    BuildContext context,
    Map<String, dynamic> source,
  ) async {
    final chatId = await chatIdForApplication(source);
    if (chatId == null || !context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(chatId: chatId),
      ),
    );
  }

  Future<void> openVacancyDetails(
    BuildContext context,
    Map<String, dynamic> source,
  ) async {
    final jobId = source["jobId"]?.toString().trim();
    if (jobId == null || jobId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This vacancy is no longer available")),
      );
      return;
    }

    final jobDoc =
        await FirebaseFirestore.instance.collection("jobs").doc(jobId).get();
    if (!context.mounted) return;

    final jobData = jobDoc.data();
    if (!jobDoc.exists || jobData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This vacancy is no longer available")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          job: Job.fromFirestore(jobDoc.id, jobData),
          applicationId: applicationId,
        ),
      ),
    );
  }

  Future<void> updateWorkerActionStatus({
    required String status,
    required Map<String, dynamic> source,
  }) async {
    await ApplicationActivityService.updateStatus(
      applicationId: applicationId,
      status: status,
      unreadFor: ApplicationActivityService.employerRecipients(source),
    );

    if (status == "offer_rejected") {
      await NotificationService().notifyEmployerOfferDecision(
        applicationId: applicationId,
        applicationData: {
          ...source,
          "status": status,
        },
        status: status,
      );
    }
  }

  Future<void> acceptOfferFromWorker(
    BuildContext context,
    Map<String, dynamic> source,
  ) async {
    final jobId = source["jobId"]?.toString();
    if (jobId == null || jobId.isEmpty) return;

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final accepted = await OfferAcceptanceService.acceptOffer(
        applicationId: applicationId,
        currentUserId: currentUserId,
      );
      if (!accepted) return;

      if (currentUserId != null) {
        await ApplicationActivityService.markRead(applicationId, currentUserId);
        await NotificationService().markApplicationNotificationsRead(
          userId: currentUserId,
          applicationId: applicationId,
        );
      }

      final updatedApplication = await FirebaseFirestore.instance
          .collection("applications")
          .doc(applicationId)
          .get();
      final updatedData = updatedApplication.data();
      if (updatedData != null) {
        final offer = updatedData["offer"];
        try {
          await NotificationService().notifyEmployerOfferDecision(
            applicationId: applicationId,
            applicationData: updatedData,
            status: "offer_accepted",
          );
        } catch (e) {
          debugPrint("OFFER ACCEPTED NOTIFICATION ERROR: $e");
        }
        if (offer is Map<String, dynamic>) {
          try {
            await NotificationService().scheduleWorkerStartReminders(
              applicationId: applicationId,
              applicationData: updatedData,
              offer: offer,
            );
          } catch (e) {
            debugPrint("WORKER START REMINDER ERROR: $e");
          }
          try {
            if (!context.mounted) return;
            await addEmployerOfferToCalendar(context, updatedData);
          } catch (e) {
            debugPrint("OFFER CALENDAR ERROR: $e");
          }
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Offer accepted")),
      );
    } catch (e) {
      debugPrint("ACCEPT OFFER ERROR: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not accept offer")),
      );
    }
  }

  Future<void> addEmployerOfferToCalendar(
    BuildContext context,
    Map<String, dynamic> source,
  ) async {
    final offerRaw = source["offer"];
    if (offerRaw is! Map) return;

    final offer = Map<String, dynamic>.from(offerRaw);
    final jobTitle = source["jobTitle"]?.toString().trim().isNotEmpty == true
        ? source["jobTitle"].toString().trim()
        : "Construction job";
    final workerName =
        source["workerName"]?.toString().trim().isNotEmpty == true
            ? source["workerName"].toString().trim()
            : source["teamName"]?.toString().trim().isNotEmpty == true
                ? source["teamName"].toString().trim()
                : "Worker";
    final location = (source["jobAddress"] ??
            source["jobLocation"] ??
            source["siteAddress"] ??
            source["fullAddress"])
        ?.toString();
    final contactInfo = [
      source["workerPhone"]?.toString().trim() ?? "",
      source["workerEmail"]?.toString().trim() ?? "",
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

  Future<void> withdrawWorkerApplication(BuildContext context) async {
    try {
      await FirebaseFirestore.instance
          .collection("applications")
          .doc(applicationId)
          .delete();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Application withdrawn")),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const JobListScreen()),
        (_) => false,
      );
    } catch (e) {
      debugPrint("WITHDRAW APPLICATION DETAILS ERROR: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not withdraw application")),
      );
    }
  }

  Future<String?> chatIdForApplication(Map<String, dynamic> source) async {
    final isTeam = (source["type"] ?? "single") == "team";
    final employerId = source["employerId"]?.toString();
    final jobId = source["jobId"]?.toString();

    if (employerId == null ||
        employerId.isEmpty ||
        jobId == null ||
        jobId.isEmpty) {
      return null;
    }

    if (isTeam) {
      final teamId = source["teamId"]?.toString();
      final members = List<String>.from(source["members"] ?? [])
          .where((id) => id.trim().isNotEmpty)
          .toList();

      if (teamId == null || teamId.isEmpty || members.isEmpty) return null;

      return ChatService.getOrCreateTeamChat(
        teamId: teamId,
        employerId: employerId,
        jobId: jobId,
        members: members,
        applicationId: applicationId,
      );
    }

    final workerId = source["workerId"] ??
        source["userId"] ??
        (source["members"] != null && source["members"].isNotEmpty
            ? source["members"][0]
            : null);

    if (workerId == null) return null;

    return ChatService.getOrCreateChat(
      workerId: workerId.toString(),
      employerId: employerId,
      jobId: jobId,
      applicationId: applicationId,
    );
  }

  String composePhysicalAddress({
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

  Map<String, String> physicalAddressFieldsFrom(Map<String, dynamic> source) {
    final street =
        (source["siteStreet"] ?? source["street"] ?? "").toString().trim();
    final city = (source["siteCity"] ?? source["city"] ?? "").toString().trim();
    final postcode =
        (source["sitePostcode"] ?? source["postcode"] ?? "").toString().trim();
    final county =
        (source["siteCounty"] ?? source["county"] ?? "").toString().trim();
    final composedAddress = composePhysicalAddress(
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

  Future<Map<String, String>> loadOfferPhysicalAddressFields(
    Map<String, dynamic> source,
  ) async {
    final fromApplication = physicalAddressFieldsFrom(source);
    if (fromApplication["siteAddress"]!.isNotEmpty &&
        fromApplication["siteAddress"] != source["jobSite"]?.toString()) {
      return fromApplication;
    }

    final jobId = source["jobId"]?.toString();
    if (jobId == null || jobId.isEmpty) return fromApplication;

    final jobDoc =
        await FirebaseFirestore.instance.collection("jobs").doc(jobId).get();
    final jobData = jobDoc.data();
    if (jobData == null) return fromApplication;

    return physicalAddressFieldsFrom(jobData);
  }

  Future<void> openOfferDialog(
    BuildContext context,
    Map<String, dynamic> source, {
    List<String> selectedWorkerIds = const [],
    List<String> selectedWorkerNames = const [],
  }) async {
    final physicalAddressFields = await loadOfferPhysicalAddressFields(source);
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
        // Backward-compatible fields used by the worker screens.
        "startDate": result["startDateTime"],
        "message": result["description"],
        if (selectedWorkerIds.isNotEmpty) ...{
          "applicationId": applicationId,
          "jobId": source["jobId"],
          "employerId": source["employerId"],
          "teamId": source["teamId"],
          "selectedWorkerIds": selectedWorkerIds,
          "selectedWorkerNames": selectedWorkerNames,
          "selectedWorkersCount": selectedWorkerIds.length,
        },
        "createdAt": FieldValue.serverTimestamp(),
      };
      final notificationOffer = Map<String, dynamic>.from(offer)
        ..remove("createdAt");

      /// 🔥 СОХРАНЕНИЕ OFFER
      await ApplicationActivityService.updateStatus(
        applicationId: applicationId,
        status: "offer_sent",
        unreadFor: selectedWorkerIds.isNotEmpty
            ? selectedWorkerIds
            : ApplicationActivityService.workerRecipients(source),
        extra: {
          "offer": offer,
          if (selectedWorkerIds.isNotEmpty) ...{
            "selectedWorkerIds": selectedWorkerIds,
            "selectedWorkerNames": selectedWorkerNames,
          },
        },
      );

      try {
        await NotificationService().notifyOfferCreated(
          applicationId: applicationId,
          applicationData: source,
          offer: notificationOffer,
        );
      } catch (e) {
        debugPrint("OFFER NOTIFICATION ERROR: $e");
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Offer sent")),
      );
    } catch (e) {
      debugPrint("MAKE OFFER ERROR: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not send offer")),
      );
    }
  }

  bool isTeamApplication(Map<String, dynamic> source) {
    final type = (source["applicationType"] ?? source["type"])
        ?.toString()
        .toLowerCase()
        .trim();
    final teamId = source["teamId"]?.toString().trim() ?? "";
    return type == "team" || teamId.isNotEmpty;
  }

  Future<List<String>?> selectedWorkerNamesFor(
    BuildContext context,
    List<String> ids,
  ) async {
    final names = <String>[];
    for (final id in ids) {
      final doc =
          await FirebaseFirestore.instance.collection("users").doc(id).get();
      final data = doc.data();
      final isInactive = !doc.exists ||
          data?["deleted"] == true ||
          data?["accountDeleted"] == true ||
          data?["active"] == false ||
          data?["status"]?.toString() == "deleted";
      if (isInactive) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Some selected workers are no longer active."),
            ),
          );
        }
        return null;
      }
      final name =
          (data?["name"] ?? data?["fullName"] ?? data?["displayName"] ?? "")
              .toString()
              .trim();
      names.add(name.isEmpty ? "Worker" : name);
    }
    return names;
  }

  Future<void> makeOfferForApplication(
    BuildContext context,
    Map<String, dynamic> source,
  ) async {
    if (!isTeamApplication(source)) {
      await openOfferDialog(context, source);
      return;
    }

    final selectedIds = selectedMembers.toList();
    if (selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select workers first.")),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Make offer to selected workers?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Yes"),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final names = await selectedWorkerNamesFor(context, selectedIds);
    if (names == null) return;
    if (!context.mounted) return;
    await openOfferDialog(
      context,
      source,
      selectedWorkerIds: selectedIds,
      selectedWorkerNames: names,
    );
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
        return "Offer";
    }
  }

  List<Widget> buildOfferDetails(Map<String, dynamic> offer) {
    final rows = <Widget>[];

    void addRow(String label, dynamic value) {
      final text = value?.toString().trim() ?? "";
      if (text.isEmpty) return;

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
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

  Widget buildWorkerInfoSection(String title, dynamic value) {
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

  Widget buildWorkerPhoneSection(dynamic value) {
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
          Align(
            alignment: Alignment.centerLeft,
            child: PhoneLink(phone: phone, compact: true),
          ),
        ],
      ),
    );
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

  Future<List<String>> loadPortfolioUrls(String userId) async {
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

  Stream<List<String>> portfolioUrlsStream(String userId) {
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

  Widget buildPortfolioGallery(String userId) {
    return StreamBuilder<List<String>>(
      stream: portfolioUrlsStream(userId),
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
            AppPhotoGridGallery(imageUrls: items),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget buildWorkerTeamsTab(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("teams")
          .where("members", arrayContains: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final teams = snapshot.data!.docs;
        if (teams.isEmpty) {
          return const Center(child: Text("No teams found"));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: teams.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final data = teams[index].data() as Map<String, dynamic>;
            final name = data["name"]?.toString().trim() ?? "Team";
            final members = List<String>.from(data["members"] ?? []);
            return StroykaSurface(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.groups_outlined)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          "${members.length} members",
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget buildTeamProfile(
    BuildContext context,
    Set<String> selectedMembers,
    Map<String, dynamic> source,
    Widget headerControls,
    Widget navigationActions,
  ) {
    final teamId = source["teamId"];
    final memberIds = List<String>.from(source["members"] ?? []);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("teams")
          .doc(teamId ?? "__missing_team__")
          .snapshots(),
      builder: (context, snapshot) {
        final team = snapshot.data?.data() as Map<String, dynamic>?;
        final teamName = team?["name"] ?? source["teamName"] ?? "Team";
        final description =
            team?["description"] ?? team?["bio"] ?? source["teamDescription"];
        final avatar = team?["avatarUrl"] ?? team?["photo"] ?? team?["logo"];
        final allSelected =
            memberIds.isNotEmpty && memberIds.every(selectedMembers.contains);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            applicationHeaderCard(
              headerControls: headerControls,
              avatar: CircleAvatar(
                radius: 44,
                backgroundColor: Colors.grey.shade300,
                backgroundImage:
                    avatar == null ? null : NetworkImage(avatar.toString()),
                child:
                    avatar == null ? const Icon(Icons.groups, size: 38) : null,
              ),
              title: teamName.toString(),
              subtitle: "${memberIds.length} members",
            ),
            navigationActions,
            const SizedBox(height: 24),
            if (description != null &&
                description.toString().trim().isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Team description",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(description.toString()),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Team members",
                      style: TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: memberIds.isEmpty
                        ? null
                        : () {
                            setState(() {
                              if (allSelected) {
                                selectedMembers.clear();
                              } else {
                                selectedMembers
                                  ..clear()
                                  ..addAll(memberIds);
                              }
                            });
                          },
                    child: Text(allSelected ? "Deselect All" : "Select All"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ...memberIds.map((memberId) {
              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection("users")
                    .doc(memberId)
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData || !snap.data!.exists) {
                    return const SizedBox();
                  }

                  final user = snap.data!.data() as Map<String, dynamic>;
                  final userStatus =
                      user["status"]?.toString().trim().toLowerCase() ?? "";
                  if (user["deleted"] == true ||
                      user["accountDeleted"] == true ||
                      user["active"] == false ||
                      userStatus == "deleted") {
                    return const SizedBox.shrink();
                  }
                  final photo = user["photo"] ?? user["avatarUrl"];
                  final isSelected = selectedMembers.contains(memberId);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundImage: photo == null
                            ? null
                            : NetworkImage(photo.toString()),
                        child: photo == null ? const Icon(Icons.person) : null,
                      ),
                      title: Text(user["name"] ?? "Worker"),
                      subtitle: Text(user["trade"] ?? ""),
                      trailing: Checkbox(
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              selectedMembers.add(memberId);
                            } else {
                              selectedMembers.remove(memberId);
                            }
                          });
                        },
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WorkerProfileScreen(
                              userId: memberId,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            }),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget applicationHeaderCard({
    required Widget headerControls,
    required Widget avatar,
    required String title,
    String? subtitle,
  }) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 172),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: headerControls,
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                avatar,
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return StroykaBackground(
      asset: AppAssets.backgroundHighriseSunset,
      child: Scaffold(
        appBar: AppBar(title: const Text("Application")),
        body: StroykaScreenBody(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection("applications")
                .doc(applicationId)
                .snapshots(),
            builder: (context, applicationSnapshot) {
              if (!applicationSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!applicationSnapshot.data!.exists ||
                  applicationSnapshot.data!.data() == null) {
                return const Center(child: Text("Application not found"));
              }

              final liveData =
                  applicationSnapshot.data!.data() as Map<String, dynamic>;

              if (currentUserId != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ApplicationActivityService.markRead(
                    applicationId,
                    currentUserId,
                  );
                  NotificationService().markApplicationNotificationsRead(
                    userId: currentUserId,
                    applicationId: applicationId,
                  );
                });
              }

              final isTeam = (liveData["type"] ?? "single") == "team";
              final workerId = liveData["workerId"] ??
                  liveData["userId"] ??
                  (liveData["members"] != null && liveData["members"].isNotEmpty
                      ? liveData["members"][0]
                      : null);
              final employerId = liveData["employerId"]?.toString();
              final isEmployerViewer =
                  currentUserId != null && currentUserId == employerId;
              if (isEmployerViewer && liveData["viewedByEmployer"] != true) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ApplicationActivityService.markViewedByEmployer(
                      applicationId);
                });
              }
              final status = canonicalStatus(liveData["status"]);
              final inactive = liveData["active"] == false ||
                  status == "inactive" ||
                  liveData["inactiveReason"] != null;
              final inactiveReason = liveData["inactiveReason"]?.toString();
              final inactiveMessage = inactiveReason == "worker_deleted_profile"
                  ? "This applicant has deleted their profile."
                  : "This vacancy is no longer active. The employer has deleted their profile.";

              if (inactive && !_inactiveApplicationSnackShown) {
                _inactiveApplicationSnackShown = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(inactiveMessage)),
                  );
                });
              }

              Widget statusBadge({required bool forEmployer}) {
                Color color;
                switch (status) {
                  case "negotiation":
                    color = AppColors.purple;
                    break;
                  case "offer_sent":
                    color = AppColors.greenDark;
                    break;
                  case "offer_withdrawn":
                    color = AppColors.warning;
                    break;
                  case "offer_accepted":
                  case "accepted":
                    color = AppColors.success;
                    break;
                  case "offer_rejected":
                    color = AppColors.danger;
                    break;
                  case "rejected":
                    color = AppColors.danger;
                    break;
                  case "withdrawn":
                    color = AppColors.muted;
                    break;
                  default:
                    color = AppColors.greenDark;
                }

                final label = ApplicationStatusUtils.getStatusDisplayLabel(
                  status,
                  forEmployer ? "employer" : "worker",
                );
                return AppChip.status(label, color: color);
              }

              Future<void> setEmployerStatus(String nextStatus) async {
                await ApplicationActivityService.updateStatus(
                  applicationId: applicationId,
                  status: nextStatus,
                  unreadFor: ApplicationActivityService.workerRecipients(
                    liveData,
                  ),
                );

                await NotificationService().notifyApplicationStatus(
                  applicationId: applicationId,
                  applicationData: liveData,
                  status: nextStatus,
                );
              }

              Future<void> startNegotiationAndOpenChat() async {
                await setEmployerStatus("negotiation");
                if (!context.mounted) return;
                await openChat(context, liveData);
              }

              Future<void> reopenRejectedApplication() async {
                await ApplicationActivityService.updateStatus(
                  applicationId: applicationId,
                  status: "negotiation",
                  unreadFor: ApplicationActivityService.workerRecipients(
                    liveData,
                  ),
                );

                await NotificationService().notifyApplicationReopened(
                  applicationId: applicationId,
                  applicationData: liveData,
                );
              }

              List<
                  ({
                    bool danger,
                    IconData icon,
                    String label,
                    Future<void> Function() run
                  })> employerMenuActions() {
                if (inactive) return [];

                final canRestartNegotiation = status == "pending" ||
                    status == "offer_withdrawn" ||
                    status == "offer_rejected";

                if (status == "rejected") {
                  return [
                    (
                      danger: false,
                      icon: Icons.chat_bubble_outline,
                      label: "Message",
                      run: () => openChat(context, liveData),
                    ),
                    (
                      danger: false,
                      icon: Icons.replay_outlined,
                      label: "Reopen Application",
                      run: reopenRejectedApplication,
                    ),
                  ];
                }

                if (canRestartNegotiation) {
                  return [
                    (
                      danger: false,
                      icon: Icons.forum_outlined,
                      label: "Message / Negotiation",
                      run: startNegotiationAndOpenChat,
                    ),
                    (
                      danger: false,
                      icon: Icons.local_offer_outlined,
                      label: "Make Offer",
                      run: () => makeOfferForApplication(context, liveData),
                    ),
                    (
                      danger: true,
                      icon: Icons.close,
                      label: "Reject",
                      run: () => setEmployerStatus("rejected"),
                    ),
                  ];
                }

                if (status == "negotiation") {
                  return [
                    (
                      danger: false,
                      icon: Icons.chat_bubble_outline,
                      label: "Message",
                      run: () => openChat(context, liveData),
                    ),
                    (
                      danger: false,
                      icon: Icons.local_offer_outlined,
                      label: "Make Offer",
                      run: () => makeOfferForApplication(context, liveData),
                    ),
                    (
                      danger: true,
                      icon: Icons.close,
                      label: "Reject",
                      run: () => setEmployerStatus("rejected"),
                    ),
                  ];
                }

                if (status == "offer_sent") {
                  return [
                    (
                      danger: false,
                      icon: Icons.chat_bubble_outline,
                      label: "Message",
                      run: () => openChat(context, liveData),
                    ),
                    (
                      danger: true,
                      icon: Icons.undo,
                      label: "Withdraw Offer",
                      run: () => setEmployerStatus("offer_withdrawn"),
                    ),
                  ];
                }

                if (status == "offer_accepted" || status == "accepted") {
                  return [
                    (
                      danger: false,
                      icon: Icons.chat_bubble_outline,
                      label: "Message",
                      run: () => openChat(context, liveData),
                    ),
                    (
                      danger: false,
                      icon: Icons.calendar_month_outlined,
                      label: "Add to Calendar",
                      run: () => addEmployerOfferToCalendar(context, liveData),
                    ),
                  ];
                }

                return [];
              }

              List<
                  ({
                    bool danger,
                    IconData icon,
                    String label,
                    Future<void> Function() run
                  })> workerMenuActions() {
                if (inactive) return [];

                bool canCurrentWorkerActOnOffer() {
                  final offerRaw = liveData["offer"];
                  final offer = offerRaw is Map
                      ? Map<String, dynamic>.from(offerRaw)
                      : <String, dynamic>{};
                  final selectedWorkerIds = offer["selectedWorkerIds"];
                  if (selectedWorkerIds is! List || selectedWorkerIds.isEmpty) {
                    return true;
                  }
                  if (currentUserId == null) return false;
                  return selectedWorkerIds
                      .map((id) => id.toString())
                      .contains(currentUserId);
                }

                if (status == "pending") {
                  return [
                    (
                      danger: false,
                      icon: Icons.undo,
                      label: "Withdraw Application",
                      run: () => withdrawWorkerApplication(context),
                    ),
                  ];
                }

                if (status == "negotiation") {
                  return [
                    (
                      danger: false,
                      icon: Icons.chat_bubble_outline,
                      label: "Message",
                      run: () => openChat(context, liveData),
                    ),
                  ];
                }

                if (status == "offer_sent") {
                  if (!canCurrentWorkerActOnOffer()) {
                    return [
                      (
                        danger: false,
                        icon: Icons.chat_bubble_outline,
                        label: "Message",
                        run: () => openChat(context, liveData),
                      ),
                    ];
                  }

                  return [
                    (
                      danger: false,
                      icon: Icons.check_circle_outline,
                      label: "Accept Offer",
                      run: () => acceptOfferFromWorker(
                            context,
                            liveData,
                          ),
                    ),
                    (
                      danger: true,
                      icon: Icons.cancel_outlined,
                      label: "Reject Offer",
                      run: () => updateWorkerActionStatus(
                            status: "offer_rejected",
                            source: liveData,
                          ),
                    ),
                  ];
                }

                if (status == "offer_accepted" ||
                    status == "accepted" ||
                    status == "offer_rejected" ||
                    status == "offer_withdrawn" ||
                    status == "rejected" ||
                    status == "withdrawn") {
                  return [
                    (
                      danger: false,
                      icon: Icons.chat_bubble_outline,
                      label: "Message",
                      run: () => openChat(context, liveData),
                    ),
                  ];
                }

                return [];
              }

              Widget headerControls({required bool forEmployer}) {
                final actions =
                    forEmployer ? employerMenuActions() : workerMenuActions();

                return Row(
                  children: [
                    statusBadge(forEmployer: forEmployer),
                    const Spacer(),
                    if (actions.isEmpty)
                      const IconButton(
                        tooltip: "No actions available",
                        onPressed: null,
                        icon: Icon(Icons.more_vert),
                        color: AppColors.ink,
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color:
                                AppColors.blueprintLine.withValues(alpha: 0.36),
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
                            for (var i = 0; i < actions.length; i++)
                              StroykaMenuAction<int>(
                                value: i,
                                label: actions[i].label,
                                icon: actions[i].icon,
                                danger: actions[i].danger,
                              ),
                          ],
                          onSelected: (index) async {
                            await actions[index].run();
                          },
                        ),
                      ),
                  ],
                );
              }

              Widget applicationNavigationActions() {
                final jobId = liveData["jobId"]?.toString().trim() ?? "";
                if (jobId.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (jobId.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () =>
                              openVacancyDetails(context, liveData),
                          icon: const Icon(Icons.work_outline, size: 17),
                          label: const Text("View Vacancy"),
                        ),
                    ],
                  ),
                );
              }

              Widget profileBody(Map<String, dynamic> user) {
                final name = user["name"] ?? "Worker";
                final trade = user["trade"] ?? "";
                final bio = user["bio"] ?? "";
                final location = user["location"] ?? "";
                final photo = user["photo"];
                final phone = user["phone"];
                final experience = user["experience"];
                final experienceDuration = experienceDurationText(user);
                final permits = user["permits"];
                final qualifications = user["qualifications"];
                final certifications = textFromListOrString(
                  user["certificationsText"] ?? user["certifications"],
                );
                final education = user["education"];
                final previousWork = user["previousWork"];
                final references = user["references"];
                final offerRaw = liveData["offer"];
                final hasOfferDetails = offerRaw is Map && offerRaw.isNotEmpty;

                Widget workerHeader() {
                  return applicationHeaderCard(
                    headerControls:
                        headerControls(forEmployer: isEmployerViewer),
                    avatar: CircleAvatar(
                      radius: 44,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage:
                          photo != null ? NetworkImage(photo) : null,
                      child: photo == null
                          ? const Icon(Icons.person, size: 38)
                          : null,
                    ),
                    title: name.toString(),
                    subtitle: trade.toString(),
                  );
                }

                Widget offerTab() {
                  final offer = Map<String, dynamic>.from(offerRaw as Map);
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      StroykaSurface(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            headerControls(forEmployer: true),
                            const SizedBox(height: 16),
                            const Text(
                              "Offer details",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...buildOfferDetails(offer),
                            if (status == "offer_accepted" ||
                                status == "accepted") ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => addEmployerOfferToCalendar(
                                    context, liveData),
                                icon: const Icon(Icons.calendar_month_outlined),
                                label: const Text("Add to Calendar"),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "Offer accepted.",
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                            if (status == "offer_rejected")
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  "Offer rejected.",
                                  style: TextStyle(
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                Widget infoTab() {
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      StroykaSurface(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildWorkerInfoSection("Location", location),
                            buildWorkerInfoSection("About worker", bio),
                            buildWorkerInfoSection(
                                "Work experience", experienceDuration),
                            buildWorkerInfoSection(
                                "Experience details", experience),
                            buildWorkerInfoSection(
                                "Permits / licences", permits),
                            buildWorkerInfoSection(
                                "Qualifications", qualifications),
                            buildWorkerInfoSection(
                                "Certifications", certifications),
                            buildWorkerInfoSection(
                                "Education (optional)", education),
                            buildWorkerInfoSection(
                                "Previous work", previousWork),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                Widget contactsTab() {
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      StroykaSurface(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildWorkerPhoneSection(phone),
                            buildReferencesSection(references),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                if (isEmployerViewer && hasOfferDetails && !isTeam) {
                  return DefaultTabController(
                    length: 5,
                    initialIndex: widget.initialOfferTab ? 0 : 1,
                    child: Column(
                      children: [
                        const StroykaTabBar(
                          margin: EdgeInsets.fromLTRB(12, 12, 12, 10),
                          labels: [
                            "Offer",
                            "Info",
                            "Contacts",
                            "Photos",
                            "Teams"
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: [
                              workerHeader(),
                              applicationNavigationActions(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: TabBarView(
                            children: [
                              offerTab(),
                              infoTab(),
                              contactsTab(),
                              ListView(
                                padding: const EdgeInsets.all(20),
                                children: [
                                  StroykaSurface(
                                    padding: const EdgeInsets.all(18),
                                    child: buildPortfolioGallery(
                                      workerId.toString(),
                                    ),
                                  ),
                                ],
                              ),
                              buildWorkerTeamsTab(workerId.toString()),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: StroykaSurface(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (inactive) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color:
                                    AppColors.warning.withValues(alpha: 0.42),
                              ),
                            ),
                            child: Text(
                              inactiveMessage,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (!isTeam) ...[
                          workerHeader(),
                          applicationNavigationActions(),
                          const SizedBox(height: 30),
                          buildWorkerPhoneSection(phone),
                          buildWorkerInfoSection("Location", location),
                          buildWorkerInfoSection("About worker", bio),
                          buildWorkerInfoSection(
                              "Work experience", experienceDuration),
                          buildWorkerInfoSection(
                              "Experience details", experience),
                          buildWorkerInfoSection("Permits / licences", permits),
                          buildWorkerInfoSection(
                              "Qualifications", qualifications),
                          buildWorkerInfoSection(
                              "Certifications", certifications),
                          buildWorkerInfoSection(
                              "Education (optional)", education),
                          buildWorkerInfoSection("Previous work", previousWork),
                          buildReferencesSection(references),
                        ],
                        if (isTeam)
                          buildTeamProfile(
                            context,
                            selectedMembers,
                            liveData,
                            headerControls(forEmployer: isEmployerViewer),
                            applicationNavigationActions(),
                          )
                        else
                          buildPortfolioGallery(workerId.toString()),
                      ],
                    ),
                  ),
                );
              }

              if (workerId == null) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: StroykaSurface(
                    padding: const EdgeInsets.all(18),
                    child: headerControls(forEmployer: isEmployerViewer),
                  ),
                );
              }

              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection("users")
                    .doc(workerId)
                    .snapshots(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!userSnapshot.data!.exists) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: StroykaSurface(
                        padding: const EdgeInsets.all(18),
                        child: headerControls(forEmployer: isEmployerViewer),
                      ),
                    );
                  }

                  final user =
                      userSnapshot.data!.data() as Map<String, dynamic>;
                  return profileBody(user);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
