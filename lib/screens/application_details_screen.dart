import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'job_list_screen.dart';
import 'worker_profile_screen.dart';
import '../services/application_activity_service.dart';
import '../services/calendar_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../widgets/make_offer_dialog.dart';
import '../widgets/phone_link.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class ApplicationDetailsScreen extends StatelessWidget {
  final String applicationId;
  final Map<String, dynamic> data;

  const ApplicationDetailsScreen({
    super.key,
    required this.applicationId,
    required this.data,
  });

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
    final status = value?.toString().toLowerCase().trim() ?? "pending";
    if (status == "review" || status == "in_review" || status == "applied") {
      return "pending";
    }
    return status.isEmpty ? "pending" : status;
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
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final appRef = FirebaseFirestore.instance
            .collection("applications")
            .doc(applicationId);

        final appSnap = await transaction.get(appRef);

        if (!appSnap.exists) return;

        final appData = appSnap.data() as Map<String, dynamic>;
        final currentStatus = appData["status"]?.toString() ?? "";

        if (currentStatus == "accepted" || currentStatus == "offer_accepted") {
          return;
        }

        transaction.update(appRef, {
          "status": "offer_accepted",
          "offerAcceptedAt": FieldValue.serverTimestamp(),
          "acceptedByWorkerId": FirebaseAuth.instance.currentUser?.uid,
          "applicationActivityAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
          "unreadFor": FieldValue.arrayUnion(
            ApplicationActivityService.employerRecipients(appData),
          ),
        });
      });

      final updatedApplication = await FirebaseFirestore.instance
          .collection("applications")
          .doc(applicationId)
          .get();
      final updatedData = updatedApplication.data();
      if (updatedData != null) {
        final offer = updatedData["offer"];
        await NotificationService().notifyEmployerOfferDecision(
          applicationId: applicationId,
          applicationData: updatedData,
          status: "offer_accepted",
        );
        if (offer is Map<String, dynamic>) {
          await NotificationService().scheduleWorkerStartReminders(
            applicationId: applicationId,
            applicationData: updatedData,
            offer: offer,
          );
          if (!context.mounted) return;
          await addEmployerOfferToCalendar(context, updatedData);
        }
      }
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
    Map<String, dynamic> source,
  ) async {
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
        "createdAt": FieldValue.serverTimestamp(),
      };
      final notificationOffer = Map<String, dynamic>.from(offer)
        ..remove("createdAt");

      /// 🔥 СОХРАНЕНИЕ OFFER
      await ApplicationActivityService.updateStatus(
        applicationId: applicationId,
        status: "offer_sent",
        unreadFor: ApplicationActivityService.workerRecipients(source),
        extra: {"offer": offer},
      );

      await NotificationService().notifyOfferCreated(
        applicationId: applicationId,
        applicationData: source,
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
          PhoneLink(phone: phone),
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
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final image = items[index];

                  return GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          child: Image.network(image, fit: BoxFit.contain),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        image,
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
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget buildTeamProfile(
    BuildContext context,
    Set<String> selectedMembers,
    Map<String, dynamic> source,
    Widget headerControls,
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
              child: const Text(
                "Team members",
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                ),
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
                  final photo = user["photo"] ?? user["avatarUrl"];
                  return StatefulBuilder(
                    builder: (context, setLocalState) {
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
                            child:
                                photo == null ? const Icon(Icons.person) : null,
                          ),
                          title: Text(user["name"] ?? "Worker"),
                          subtitle: Text(user["trade"] ?? ""),
                          trailing: Checkbox(
                            value: isSelected,
                            onChanged: (value) {
                              setLocalState(() {
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
                                builder: (_) =>
                                    WorkerProfileScreen(userId: memberId),
                              ),
                            );
                          },
                        ),
                      );
                    },
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

    return Scaffold(
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
                ApplicationActivityService.markViewedByEmployer(applicationId);
              });
            }
            final status = canonicalStatus(liveData["status"]);
            final selectedMembers = <String>{};

            Widget statusBadge({required bool forEmployer}) {
              Color color;
              String label;
              switch (status) {
                case "negotiation":
                  color = AppColors.purple;
                  label = "Negotiation";
                  break;
                case "offer_sent":
                  color = AppColors.greenDark;
                  label = forEmployer ? "Offer Sent" : "Offer Received";
                  break;
                case "offer_withdrawn":
                  color = AppColors.warning;
                  label = "Offer Withdrawn";
                  break;
                case "offer_accepted":
                case "accepted":
                  color = AppColors.success;
                  label = forEmployer ? "Hired" : "Offer Accepted";
                  break;
                case "offer_rejected":
                  color = AppColors.danger;
                  label = "Offer Rejected";
                  break;
                case "rejected":
                  color = AppColors.danger;
                  label = "Rejected";
                  break;
                case "withdrawn":
                  color = AppColors.muted;
                  label = "Withdrawn";
                  break;
                default:
                  color = AppColors.greenDark;
                  label = "Pending";
              }

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
                    run: () => openOfferDialog(context, liveData),
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
                    run: () => openOfferDialog(context, liveData),
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

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: StroykaSurface(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isTeam) ...[
                        applicationHeaderCard(
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
                        ),
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

                final user = userSnapshot.data!.data() as Map<String, dynamic>;
                return profileBody(user);
              },
            );
          },
        ),
      ),
    );
  }
}
