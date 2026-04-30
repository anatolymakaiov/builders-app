import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'worker_profile_screen.dart';
import '../services/application_activity_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
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

  Future<void> updateStatus(BuildContext context, String status) async {
    final db = FirebaseFirestore.instance;

    final employerId = data["employerId"];
    final jobId = data["jobId"];

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
        final workersCount = data["workersCount"] ?? 1;

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
              ApplicationActivityService.workerRecipients(data),
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
        applicationData: data,
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

  Future<void> openChat(BuildContext context) async {
    final chatId = await chatIdForApplication(data);
    if (chatId == null || !context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(chatId: chatId),
      ),
    );
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

  Future<void> openOfferDialog(BuildContext context) async {
    String jobType = "hourly";
    final rateController = TextEditingController();
    final workPeriodController = TextEditingController();
    final weeklyHoursController = TextEditingController();
    final scheduleController = TextEditingController();
    final startDateTimeController = TextEditingController();
    final siteAddressController = TextEditingController(
      text: (data["jobSite"] ?? data["site"] ?? "").toString(),
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
                          setDialogState(() {
                            jobType = value;
                          });
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

    if (result != true) return;

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
        // Backward-compatible fields used by the worker screens.
        "startDate": startDateTimeController.text.trim(),
        "message": descriptionController.text.trim(),
        "createdAt": FieldValue.serverTimestamp(),
      };
      final notificationOffer = Map<String, dynamic>.from(offer)
        ..remove("createdAt");

      /// 🔥 СОХРАНЕНИЕ OFFER
      await ApplicationActivityService.updateStatus(
        applicationId: applicationId,
        status: "offer_sent",
        unreadFor: ApplicationActivityService.workerRecipients(data),
        extra: {"offer": offer},
      );

      await NotificationService().notifyOfferCreated(
        applicationId: applicationId,
        applicationData: data,
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

  ButtonStyle get primaryActionStyle => ElevatedButton.styleFrom(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      );

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
  ) {
    final teamId = data["teamId"];
    final memberIds = List<String>.from(data["members"] ?? []);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("teams")
          .doc(teamId ?? "__missing_team__")
          .snapshots(),
      builder: (context, snapshot) {
        final team = snapshot.data?.data() as Map<String, dynamic>?;
        final teamName = team?["name"] ?? data["teamName"] ?? "Team";
        final description =
            team?["description"] ?? team?["bio"] ?? data["teamDescription"];
        final avatar = team?["avatarUrl"] ?? team?["photo"] ?? team?["logo"];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage:
                        avatar == null ? null : NetworkImage(avatar.toString()),
                    child: avatar == null
                        ? const Icon(Icons.groups, size: 40)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    teamName.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${memberIds.length} members",
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
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

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ApplicationActivityService.markRead(applicationId, currentUserId);
      });
    }

    final Set<String> selectedMembers = {};
    final workerId = data["workerId"] ??
        data["userId"] ??
        (data["members"] != null && data["members"].isNotEmpty
            ? data["members"][0]
            : null);

    if (workerId == null) {
      return const Scaffold(
        body: Center(child: Text("No worker data")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Application")),
      body: StroykaScreenBody(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection("users")
              .doc(workerId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.data!.exists) {
              return const Center(child: Text("User not found"));
            }

            final user = snapshot.data!.data() as Map<String, dynamic>;

            final name = user["name"] ?? "Worker";
            final trade = user["trade"] ?? "";
            final bio = user["bio"] ?? "";
            final location = user["location"] ?? "";
            final photo = user["photo"];
            final isTeam = (data["type"] ?? "single") == "team";
            final phone = user["phone"];
            final experience = user["experience"];
            final experienceDuration = experienceDurationText(user);
            final permits = user["permits"];
            final qualifications = user["qualifications"];
            final certifications = textFromListOrString(
                user["certificationsText"] ?? user["certifications"]);
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
                      /// 👤 HEADER
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 45,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage:
                                  photo != null ? NetworkImage(photo) : null,
                              child: photo == null
                                  ? const Icon(Icons.person, size: 40)
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (trade.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                trade,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      buildWorkerPhoneSection(phone),
                      buildWorkerInfoSection("Location", location),
                      buildWorkerInfoSection("About worker", bio),
                      buildWorkerInfoSection(
                          "Work experience", experienceDuration),
                      buildWorkerInfoSection("Experience details", experience),
                      buildWorkerInfoSection("Permits / licences", permits),
                      buildWorkerInfoSection("Qualifications", qualifications),
                      buildWorkerInfoSection("Certifications", certifications),
                      buildWorkerInfoSection("Education (optional)", education),
                      buildWorkerInfoSection("Previous work", previousWork),
                      buildReferencesSection(references),
                    ],

                    if (isTeam)
                      buildTeamProfile(context, selectedMembers)
                    else ...[
                      buildPortfolioGallery(workerId),
                    ],
                    const SizedBox(height: 40),

                    /// 🔥 BUTTONS
                    /// 🔥 ACTIONS (НОВАЯ ЛОГИКА)
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection("applications")
                          .doc(applicationId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox();

                        final liveData =
                            snapshot.data!.data() as Map<String, dynamic>;
                        final status = liveData["status"] ?? "pending";

                        return Column(
                          children: [
                            /// =========================
                            /// PENDING
                            /// =========================
                            if (status == "pending") ...[
                              /// NEGOTIATION
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: primaryActionStyle,
                                  onPressed: () async {
                                    if ((liveData["type"] ?? "single") ==
                                        "team") {
                                      for (var memberId in selectedMembers) {
                                        await FirebaseFirestore.instance
                                            .collection("applications")
                                            .doc(applicationId)
                                            .update({
                                          "membersStatus.$memberId":
                                              "negotiation",
                                        });
                                      }
                                      await ApplicationActivityService
                                          .updateStatus(
                                        applicationId: applicationId,
                                        status: "negotiation",
                                        unreadFor: ApplicationActivityService
                                            .workerRecipients(liveData),
                                      );
                                    } else {
                                      await updateStatus(
                                          context, "negotiation");
                                    }

                                    final chatId =
                                        await chatIdForApplication(liveData);

                                    if (chatId == null) return;

                                    if (context.mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ChatScreen(chatId: chatId),
                                        ),
                                      );
                                    }
                                  },
                                  child:
                                      const Text("Start negotiation / Message"),
                                ),
                              ),

                              const SizedBox(height: 10),

                              /// MAKE OFFER
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: primaryActionStyle,
                                  onPressed: () => openOfferDialog(context),
                                  child: const Text("Make offer"),
                                ),
                              ),

                              const SizedBox(height: 10),

                              /// REJECT
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.red),
                                  ),
                                  onPressed: () async {
                                    if ((liveData["type"] ?? "single") ==
                                        "team") {
                                      await ApplicationActivityService
                                          .updateStatus(
                                        applicationId: applicationId,
                                        status: "rejected",
                                        unreadFor: ApplicationActivityService
                                            .workerRecipients(liveData),
                                      );
                                    } else {
                                      await updateStatus(context, "rejected");
                                    }
                                  },
                                  child: const Text("Reject"),
                                ),
                              ),
                            ],

                            /// =========================
                            /// NEGOTIATION
                            /// =========================
                            if (status == "negotiation") ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: primaryActionStyle,
                                  onPressed: () => openChat(context),
                                  child: const Text("Negotiation / Message"),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: primaryActionStyle,
                                  onPressed: () => openOfferDialog(context),
                                  child: const Text("Make offer"),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.red),
                                  ),
                                  onPressed: () async {
                                    if ((liveData["type"] ?? "single") ==
                                        "team") {
                                      await ApplicationActivityService
                                          .updateStatus(
                                        applicationId: applicationId,
                                        status: "rejected",
                                        unreadFor: ApplicationActivityService
                                            .workerRecipients(liveData),
                                      );
                                    } else {
                                      await updateStatus(context, "rejected");
                                    }
                                  },
                                  child: const Text("Reject"),
                                ),
                              ),
                            ],

                            /// =========================
                            /// OFFER SENT
                            /// =========================
                            if (status == "offer_sent") ...[
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.red),
                                  ),
                                  onPressed: () async {
                                    await updateStatus(context, "negotiation");
                                  },
                                  child: const Text("Withdraw offer"),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await ApplicationActivityService
                                        .updateStatus(
                                      applicationId: applicationId,
                                      status: "negotiation",
                                      unreadFor: ApplicationActivityService
                                          .workerRecipients(liveData),
                                      extra: {"offer": FieldValue.delete()},
                                    );
                                  },
                                  child: const Text("Reject"),
                                ),
                              ),
                            ],

                            /// =========================
                            /// HIRED
                            /// =========================
                            if (status == "offer_accepted") ...[
                              const SizedBox(height: 10),
                              const Text(
                                "Worker hired",
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],

                            if (status == "rejected") ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.red.withValues(alpha: 0.22),
                                  ),
                                ),
                                child: const Text(
                                  "Application rejected",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    )
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
