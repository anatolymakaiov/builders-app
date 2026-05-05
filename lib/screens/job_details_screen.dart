import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'post_job_screen.dart';
import 'chat_screen.dart';

import '../models/job.dart';
import '../services/application_activity_service.dart';
import '../services/calendar_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/report_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';
import '../widgets/job_card.dart';
import '../widgets/phone_link.dart';

class JobDetailScreen extends StatefulWidget {
  final Job job;
  final String? applicationId;

  const JobDetailScreen({
    super.key,
    required this.job,
    this.applicationId,
  });

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  bool isApplying = false;
  bool isApplied = false;
  String? currentApplicationId;
  String role = "worker";

  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    await loadRole();
    await checkIfApplied();
  }

  Future<void> loadRole() async {
    final uid = userId;
    if (uid == null) return;

    final doc =
        await FirebaseFirestore.instance.collection("users").doc(uid).get();

    if (doc.exists) {
      role = doc.data()?["role"] ?? "worker";
    }
  }

  Future<void> checkIfApplied() async {
    final uid = userId;
    if (uid == null) return;

    final applications = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seenIds = <String>{};

    final workerSnap = await FirebaseFirestore.instance
        .collection("applications")
        .where("jobId", isEqualTo: widget.job.id)
        .where("workerId", isEqualTo: uid)
        .get();

    for (final doc in workerSnap.docs) {
      if (seenIds.add(doc.id)) applications.add(doc);
    }

    final teamMemberSnap = await FirebaseFirestore.instance
        .collection("applications")
        .where("jobId", isEqualTo: widget.job.id)
        .where("members", arrayContains: uid)
        .get();

    for (final doc in teamMemberSnap.docs) {
      if (seenIds.add(doc.id)) applications.add(doc);
    }

    QueryDocumentSnapshot<Map<String, dynamic>>? currentApplication;
    for (final doc in applications) {
      final data = doc.data();
      if (isCurrentUserApplicationData(data, uid)) {
        currentApplication = doc;
        break;
      }
    }

    if (mounted) {
      setState(() {
        isApplied = currentApplication != null;
        currentApplicationId = currentApplication?.id;
      });
    }
  }

  bool isActiveApplicationData(Map<String, dynamic> data) {
    final status = data["status"]?.toString();
    return status != "withdrawn";
  }

  bool isSingleApplicationData(Map<String, dynamic> data) {
    final type = data["type"]?.toString();
    return type != "team" && isActiveApplicationData(data);
  }

  bool isTeamApplicationForUser(Map<String, dynamic> data, String uid) {
    final type = data["type"]?.toString();
    if (type != "team" || !isActiveApplicationData(data)) return false;

    return data["workerId"] == uid ||
        data["applicantId"] == uid ||
        teamMemberIds(data["members"]).contains(uid);
  }

  bool isCurrentUserApplicationData(Map<String, dynamic> data, String uid) {
    return isSingleApplicationData(data) && data["workerId"] == uid ||
        isTeamApplicationForUser(data, uid);
  }

  /// 🔥 LOAD MY TEAMS
  Future<List<QueryDocumentSnapshot>> loadMyTeams() async {
    final uid = userId;
    if (uid == null) return [];

    final snap = await FirebaseFirestore.instance.collection("teams").get();

    return snap.docs.where((doc) {
      final data = doc.data();
      return teamMemberIds(data["members"]).contains(uid) ||
          data["ownerId"] == uid;
    }).toList();
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

  /// 🔥 PICK TEAM
  Future<Map<String, dynamic>?> pickTeam(BuildContext context) async {
    final teams = await loadMyTeams();

    if (!context.mounted) return null;
    if (teams.isEmpty) return null;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (_) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: teams.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final members = teamMemberIds(data["members"]);
            final avatarUrl = data["avatarUrl"] ?? data["photo"];

            return ListTile(
              leading: CircleAvatar(
                backgroundImage:
                    avatarUrl is String ? NetworkImage(avatarUrl) : null,
                child: avatarUrl is String ? null : const Icon(Icons.group),
              ),
              title: Text(data["name"] ?? "Team"),
              subtitle: Text("${members.length} members"),
              onTap: () {
                Navigator.pop(context, {
                  "teamId": doc.id,
                  "members": members,
                });
              },
            );
          }).toList(),
        );
      },
    );
  }

  /// 🔥 PICK APPLY TYPE
  Future<String?> pickApplyType(BuildContext context) async {
    return showModalBottomSheet<String>(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text("Apply as worker"),
                onTap: () => Navigator.pop(context, "single"),
              ),
              ListTile(
                leading: const Icon(Icons.group),
                title: const Text("Apply as team"),
                onTap: () => Navigator.pop(context, "team"),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> apply() async {
    final uid = userId;
    if (uid == null) return;

    if (isApplying) return;
    setState(() => isApplying = true);

    var remainingPositions = 0;
    try {
      /// 🔥 CHECK AVAILABLE POSITIONS
      remainingPositions = await loadRemainingPositions();
      if (!mounted) return;

      if (remainingPositions <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No positions left")),
        );
        setState(() => isApplying = false);
        return;
      }

      if (isApplied) {
        setState(() => isApplying = false);
        return;
      }
    } catch (e) {
      debugPrint("POSITION CHECK ERROR: $e");
      if (mounted) {
        setState(() => isApplying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not check available positions")),
        );
      }
      return;
    }

    try {
      /// 🔥 ШАГ 1 — ВЫБОР ТИПА
      if (!mounted) return;
      final type = await pickApplyType(context);

      /// ❌ пользователь закрыл выбор
      if (!mounted) return;
      if (type == null) {
        setState(() => isApplying = false);
        return;
      }

      /// =====================================================
      /// 👥 TEAM APPLY
      /// =====================================================
      if (type == "team") {
        if (!mounted) return;
        final team = await pickTeam(context);

        /// ❌ закрыл выбор команды
        if (team == null) {
          setState(() => isApplying = false);
          return;
        }

        final members = List<String>.from(team["members"]);
        final teamId = team["teamId"]?.toString() ?? "";

        final existingTeamApplication = await FirebaseFirestore.instance
            .collection("applications")
            .where("jobId", isEqualTo: widget.job.id)
            .where("teamId", isEqualTo: teamId)
            .get();

        final duplicateTeamApplication =
            existingTeamApplication.docs.where((doc) {
          final data = doc.data();
          return isTeamApplicationForUser(data, uid);
        }).toList();

        if (duplicateTeamApplication.isNotEmpty) {
          if (mounted) {
            setState(() {
              isApplying = false;
              isApplied = true;
              currentApplicationId = duplicateTeamApplication.first.id;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("You already applied")),
            );
          }
          return;
        }

        /// ❗ проверка мест
        if (members.length > remainingPositions) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Not enough spots")),
            );
          }
          setState(() => isApplying = false);
          return;
        }

        final applicationRef =
            FirebaseFirestore.instance.collection("applications").doc();

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final jobRef =
              FirebaseFirestore.instance.collection("jobs").doc(widget.job.id);
          final jobSnap = await transaction.get(jobRef);

          if (!jobSnap.exists) throw Exception("Job not found");

          final jobData = jobSnap.data() as Map<String, dynamic>;
          final ownerId = jobOwnerId(jobData);
          final counts = jobPositionCounts(jobData);
          if (ownerId.isEmpty) throw Exception("Job has no ownerId");
          if (members.length > counts.remaining) {
            throw Exception("not_enough_spots");
          }

          transaction.set(applicationRef, {
            "jobId": widget.job.id,
            "jobTitle": (jobData["title"] ??
                    jobData["trade"] ??
                    widget.job.displayTitle)
                .toString(),
            "jobTrade": jobData["trade"] ?? widget.job.trade,
            "jobSite": jobData["site"] ?? widget.job.site,
            ...applicationPhysicalAddressFields(jobData),
            "type": "team",
            "teamId": teamId,
            "workerId": uid,
            "applicantId": uid,
            "members": members,
            "workersCount": members.length,
            "membersStatus": {for (var id in members) id: "pending"},
            "employerId": ownerId,
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp(),
            ...ApplicationActivityService.createdForEmployer(ownerId),
          });
        });

        if (mounted) {
          setState(() {
            isApplying = false;
            isApplied = true;
            currentApplicationId = applicationRef.id;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Application sent")),
          );
        }

        return;

        /// 🔥 КРИТИЧНО: НЕ ПРОВАЛИВАЕМСЯ ДАЛЬШЕ
      }

      /// =====================================================
      /// 👤 SINGLE APPLY
      /// =====================================================
      if (type == "single") {
        /// 🔥 защита от дублей
        final existing = await FirebaseFirestore.instance
            .collection("applications")
            .where("jobId", isEqualTo: widget.job.id)
            .where("workerId", isEqualTo: uid)
            .get();

        final existingSingle = existing.docs
            .where((doc) => isSingleApplicationData(doc.data()))
            .toList();

        if (existingSingle.isNotEmpty) {
          if (mounted) {
            setState(() {
              isApplying = false;
              isApplied = true;
              currentApplicationId = existingSingle.first.id;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("You already applied")),
            );
          }
          return;
        }

        final userDoc =
            await FirebaseFirestore.instance.collection("users").doc(uid).get();
        final workerName = userDoc.data()?["name"] ?? "Worker";

        final applicationRef =
            FirebaseFirestore.instance.collection("applications").doc();

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final jobRef =
              FirebaseFirestore.instance.collection("jobs").doc(widget.job.id);
          final jobSnap = await transaction.get(jobRef);

          if (!jobSnap.exists) throw Exception("Job not found");

          final jobData = jobSnap.data() as Map<String, dynamic>;
          final ownerId = jobOwnerId(jobData);
          final counts = jobPositionCounts(jobData);
          if (ownerId.isEmpty) throw Exception("Job has no ownerId");
          if (counts.remaining <= 0) throw Exception("no_positions_left");

          transaction.set(applicationRef, {
            "jobId": widget.job.id,
            "jobTitle": (jobData["title"] ??
                    jobData["trade"] ??
                    widget.job.displayTitle)
                .toString(),
            "jobTrade": jobData["trade"] ?? widget.job.trade,
            "jobSite": jobData["site"] ?? widget.job.site,
            ...applicationPhysicalAddressFields(jobData),
            "workerId": uid,
            "applicantId": uid,
            "workerName": workerName,
            "type": "single",
            "members": [uid],
            "workersCount": 1,
            "membersStatus": {uid: "pending"},
            "employerId": ownerId,
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp(),
            ...ApplicationActivityService.createdForEmployer(ownerId),
          });
        });

        if (mounted) {
          setState(() {
            isApplying = false;
            isApplied = true;
            currentApplicationId = applicationRef.id;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Application sent")),
          );
        }

        return;
      }
    } catch (e) {
      debugPrint("APPLY ERROR: $e");
      if (mounted) {
        setState(() => isApplying = false);
        final message = e.toString().contains("not_enough_spots") ||
                e.toString().contains("no_positions_left")
            ? "No positions left"
            : "Could not send application";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  Future<void> withdrawApplication() async {
    final uid = userId;
    if (uid == null || isApplying) return;

    setState(() => isApplying = true);

    try {
      final refs = <DocumentReference<Map<String, dynamic>>>[];

      if (currentApplicationId != null) {
        final doc = await FirebaseFirestore.instance
            .collection("applications")
            .doc(currentApplicationId)
            .get();

        final data = doc.data();
        if (doc.exists &&
            data != null &&
            data["jobId"] == widget.job.id &&
            isCurrentUserApplicationData(data, uid)) {
          refs.add(doc.reference);
        }
      }

      if (refs.isEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection("applications")
            .where("jobId", isEqualTo: widget.job.id)
            .where("workerId", isEqualTo: uid)
            .get();

        refs.addAll(
          snap.docs
              .where((doc) => isCurrentUserApplicationData(doc.data(), uid))
              .map((doc) => doc.reference),
        );
      }

      if (refs.isEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection("applications")
            .where("jobId", isEqualTo: widget.job.id)
            .where("members", arrayContains: uid)
            .get();

        refs.addAll(
          snap.docs
              .where((doc) => isCurrentUserApplicationData(doc.data(), uid))
              .map((doc) => doc.reference),
        );
      }

      for (final ref in refs) {
        await ref.delete();
      }

      if (!mounted) return;
      setState(() {
        isApplied = false;
        isApplying = false;
        currentApplicationId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Application withdrawn")),
      );
    } catch (e) {
      debugPrint("WITHDRAW APPLICATION ERROR: $e");
      if (!mounted) return;
      setState(() => isApplying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not withdraw application")),
      );
    }
  }

  Future<void> openMaps() async {
    final query = widget.job.lat != 0 || widget.job.lng != 0
        ? "${widget.job.lat},${widget.job.lng}"
        : widget.job.fullAddress;
    final url =
        "https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}";

    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  int applicationSlotCount(Map<String, dynamic> data) {
    final workersCount = data["workersCount"];
    if (workersCount is num && workersCount > 0) return workersCount.toInt();

    final members = data["members"];
    if (members is List && members.isNotEmpty) return members.length;

    return 1;
  }

  int acceptedSlotsFromDocs(List<QueryDocumentSnapshot> docs) {
    int accepted = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data["status"] ?? "";

      if (status == "offer_accepted" || status == "accepted") {
        accepted += applicationSlotCount(data);
      }
    }

    return accepted;
  }

  int readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? "") ?? 0;
  }

  String jobOwnerId(Map<String, dynamic>? data) {
    final candidates = [
      data?["ownerId"],
      data?["employerId"],
      data?["createdBy"],
      data?["userId"],
      widget.job.ownerId,
    ];

    for (final value in candidates) {
      final id = value?.toString().trim() ?? "";
      if (id.isNotEmpty && id != "unknown") return id;
    }

    return "";
  }

  String textFromJob(Map<String, dynamic> data, String primary, String legacy) {
    final value = data[primary]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
    return data[legacy]?.toString().trim() ?? "";
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

  Map<String, dynamic> applicationPhysicalAddressFields(
    Map<String, dynamic> jobData,
  ) {
    final street = textFromJob(jobData, "siteStreet", "street");
    final city = textFromJob(jobData, "siteCity", "city");
    final postcode = textFromJob(jobData, "sitePostcode", "postcode");
    final county = jobData["siteCounty"]?.toString().trim() ?? "";
    final composedAddress = composePhysicalAddress(
      street: street,
      city: city,
      postcode: postcode,
    );
    final address = (jobData["siteAddress"] ??
            jobData["fullAddress"] ??
            jobData["location"] ??
            composedAddress)
        .toString()
        .trim();

    return {
      "siteStreet": street,
      "siteCity": city,
      "sitePostcode": postcode,
      "siteCounty": county,
      "siteAddress": address.isNotEmpty ? address : composedAddress,
      "fullAddress": address.isNotEmpty ? address : composedAddress,
    };
  }

  ({int positions, int filledPositions, int remaining}) jobPositionCounts(
    Map<String, dynamic>? data,
  ) {
    final rawPositions = readInt(data?["positions"]);
    final rawRemaining = readInt(data?["remainingPositions"]);
    final rawFilledPositions = readInt(data?["filledPositions"]);
    final positions = rawPositions <= 0
        ? (rawRemaining > 0
            ? rawRemaining + rawFilledPositions
            : widget.job.positions)
        : rawPositions;
    final safePositions = positions <= 0 ? 1 : positions;
    final filledPositions = rawFilledPositions <= 0 && rawRemaining > 0
        ? (safePositions - rawRemaining).clamp(0, safePositions).toInt()
        : rawFilledPositions.clamp(0, safePositions).toInt();
    final remaining =
        (safePositions - filledPositions).clamp(0, safePositions).toInt();

    return (
      positions: safePositions,
      filledPositions: filledPositions,
      remaining: remaining,
    );
  }

  Future<int> loadRemainingPositions() async {
    final jobDoc = await FirebaseFirestore.instance
        .collection("jobs")
        .doc(widget.job.id)
        .get();

    if (!jobDoc.exists) {
      throw Exception("Job not found");
    }

    final data = jobDoc.data();
    final ownerId = jobOwnerId(data);
    final counts = jobPositionCounts(data);

    debugPrint(
      "POSITION CHECK jobId=${widget.job.id} "
      "positions=${counts.positions} "
      "filledPositions=${counts.filledPositions} "
      "remainingPositions=${counts.remaining} "
      "rawPositions=${data?["positions"]} "
      "rawFilledPositions=${data?["filledPositions"]} "
      "rawRemainingPositions=${data?["remainingPositions"]} "
      "ownerId=$ownerId "
      "moderationStatus=${data?["moderationStatus"]} "
      "status=${data?["status"]}",
    );

    if (ownerId.isEmpty) {
      throw Exception("Job has no ownerId");
    }

    return counts.remaining;
  }

  Future<void> deleteJob() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete job"),
        content: const Text("Are you sure you want to delete this job?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Delete",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection("jobs")
          .doc(widget.job.id)
          .delete();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Job deleted")),
        );
      }
    } catch (e) {
      debugPrint("DELETE ERROR: $e");
    }
  }

  Widget buildApplyButton() {
    if (role != "worker") return const SizedBox();

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isApplying
            ? null
            : () async {
                if (isApplied) {
                  await withdrawApplication();
                } else {
                  await apply();
                }
              },
        child: Text(
          isApplied ? "Withdraw application" : "Apply for this job",
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }

  Widget buildEditButton() {
    final uid = userId;

    if (uid == null || uid != widget.job.ownerId) {
      return const SizedBox();
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostJobScreen(
                existingJob: widget.job,
                onJobCreated: (_) {},
              ),
            ),
          );
        },
        icon: const Icon(Icons.edit),
        label: const Text("Edit job"),
      ),
    );
  }

  Widget buildDeleteButton() {
    final uid = userId;

    if (uid == null || uid != widget.job.ownerId) {
      return const SizedBox();
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: deleteJob,
        icon: const Icon(Icons.delete, color: Colors.red),
        label: const Text(
          "Delete job",
          style: TextStyle(color: Colors.red),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  /// 🔥 EMPLOYER BLOCK (FULL FIX)
  Widget buildCompany() {
    final ownerId = widget.job.ownerId;

    /// ❌ защита от битых данных
    if (ownerId.isEmpty || ownerId == "unknown") {
      return const SizedBox();
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(ownerId)
          .snapshots(),
      builder: (context, snapshot) {
        /// ⏳ LOADING
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                CircleAvatar(radius: 28),
                SizedBox(width: 12),
                Text("Loading..."),
              ],
            ),
          );
        }

        /// ❌ нет данных
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;

        final name = data["companyName"] ?? data["name"] ?? "Company";
        final photo = data["companyLogo"] ?? data["photo"] ?? data["avatarUrl"];
        final companyCard = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey.shade300,
                backgroundImage: photo != null ? NetworkImage(photo) : null,
                child:
                    photo == null ? const Icon(Icons.business, size: 28) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Employer",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        return companyCard;
      },
    );
  }

  Widget buildPhotos() {
    if (widget.job.ownerId.isEmpty || widget.job.ownerId == "unknown") {
      return const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Photos",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: widget.job.photos.length,
            itemBuilder: (context, index) {
              final photo = widget.job.photos[index];

              return GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      child: Image.network(photo),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  width: 240,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                      image: NetworkImage(photo),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget buildRateCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments),
          const SizedBox(width: 10),
          Text(
            widget.job.rateText,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.greenDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildLocation() {
    return InkWell(
      onTap: openMaps,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.location_on, color: AppColors.greenDark),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.job.fullAddress,
                style: const TextStyle(
                  color: AppColors.greenDark,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildDescription() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Job description",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(widget.job.description.isNotEmpty
            ? widget.job.description
            : "No description"),
      ],
    );
  }

  Widget buildJobInfoSection(String title, String body) {
    final text = body.trim();
    if (text.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(text),
        ],
      ),
    );
  }

  Widget buildPositionsInfo() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("jobs")
          .doc(widget.job.id)
          .snapshots(),
      builder: (context, snapshot) {
        final counts = jobPositionCounts(snapshot.data?.data());

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              const Icon(Icons.group, size: 18),
              const SizedBox(width: 6),
              Text(
                "${counts.remaining}/${counts.positions} spots available",
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
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

    String physicalAddressFromOffer() {
      final street = offer["siteStreet"]?.toString().trim() ?? "";
      final city = offer["siteCity"]?.toString().trim() ?? "";
      final postcode = offer["sitePostcode"]?.toString().trim() ?? "";
      final fromParts = composePhysicalAddress(
        street: street,
        city: city,
        postcode: postcode,
      );
      if (fromParts.isNotEmpty) return fromParts;

      final storedAddress =
          (offer["fullAddress"] ?? offer["siteAddress"])?.toString().trim() ??
              "";
      if (storedAddress.isNotEmpty && storedAddress != widget.job.site) {
        return storedAddress;
      }

      return widget.job.fullAddress;
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

  Future<void> acceptOffer(String applicationId) async {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final appRef = FirebaseFirestore.instance
          .collection("applications")
          .doc(applicationId);
      final jobRef =
          FirebaseFirestore.instance.collection("jobs").doc(widget.job.id);

      final appSnap = await transaction.get(appRef);
      final jobSnap = await transaction.get(jobRef);

      if (!appSnap.exists || !jobSnap.exists) return;

      final appData = appSnap.data() as Map<String, dynamic>;
      final jobData = jobSnap.data() as Map<String, dynamic>;

      final currentStatus = appData["status"] ?? "";
      if (currentStatus == "accepted" || currentStatus == "offer_accepted") {
        return;
      }

      final workersCount = (appData["workersCount"] as num?)?.toInt() ?? 1;
      final filled = (jobData["filledPositions"] as num?)?.toInt() ?? 0;

      transaction.update(appRef, {
        "status": "offer_accepted",
        "applicationActivityAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
        "unreadFor": FieldValue.arrayUnion(
          ApplicationActivityService.employerRecipients(appData),
        ),
      });
      transaction.update(jobRef, {
        "filledPositions": filled + workersCount,
      });
    });

    final appSnap = await FirebaseFirestore.instance
        .collection("applications")
        .doc(applicationId)
        .get();
    final appData = appSnap.data();
    final offer = appData?["offer"];

    if (appData != null && offer is Map<String, dynamic>) {
      await NotificationService().notifyWorkStartReminder(
        applicationId: applicationId,
        applicationData: appData,
        offer: offer,
      );
    }
  }

  Future<void> withdrawOfferAcceptance(String applicationId) async {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final appRef = FirebaseFirestore.instance
          .collection("applications")
          .doc(applicationId);
      final jobRef =
          FirebaseFirestore.instance.collection("jobs").doc(widget.job.id);

      final appSnap = await transaction.get(appRef);
      final jobSnap = await transaction.get(jobRef);

      if (!appSnap.exists || !jobSnap.exists) return;

      final appData = appSnap.data() as Map<String, dynamic>;
      final jobData = jobSnap.data() as Map<String, dynamic>;

      final currentStatus = appData["status"] ?? "";
      if (currentStatus != "accepted" && currentStatus != "offer_accepted") {
        return;
      }

      final workersCount = (appData["workersCount"] as num?)?.toInt() ?? 1;
      final filled = (jobData["filledPositions"] as num?)?.toInt() ?? 0;
      final nextFilled = (filled - workersCount).clamp(0, filled).toInt();

      transaction.update(appRef, {
        "status": "offer_sent",
        "applicationActivityAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
        "unreadFor": FieldValue.arrayUnion(
          ApplicationActivityService.employerRecipients(appData),
        ),
      });
      transaction.update(jobRef, {
        "filledPositions": nextFilled,
      });
    });
  }

  Future<void> addOfferToCalendar(Map<String, dynamic> offer) async {
    final added = await CalendarService.addOfferToCalendar(
      title: widget.job.displayTitle,
      offer: offer,
      fallbackLocation: widget.job.fullAddress,
    );

    if (!mounted) return;

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

  ButtonStyle get compactPrimaryActionStyle => ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      );

  ButtonStyle get compactSecondaryActionStyle => OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      );

  Widget buildYourOfferTab(Map<String, dynamic> appData) {
    final applicationId = widget.applicationId;
    if (applicationId == null) return const SizedBox();

    final offer = appData["offer"] as Map<String, dynamic>?;
    final status = appData["status"] ?? "";

    if (offer == null) return const SizedBox();

    final accepted = status == "accepted" || status == "offer_accepted";
    final canAccept = status == "offer" || status == "offer_sent";

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
      children: [
        StroykaSurface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Your offer",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ...buildOfferDetails(offer),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: compactSecondaryActionStyle,
                  onPressed: () => addOfferToCalendar(offer),
                  icon: const Icon(Icons.calendar_month),
                  label: const Text("Add to phone calendar"),
                ),
              ),
              if (canAccept)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: compactPrimaryActionStyle,
                      onPressed: () => acceptOffer(applicationId),
                      child: const Text("Accept offer"),
                    ),
                  ),
                ),
              if (accepted)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: compactSecondaryActionStyle,
                      onPressed: () => withdrawOfferAcceptance(applicationId),
                      child: const Text("Withdraw acceptance"),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildMessageEmployerButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () async {
          final uid = userId;
          if (uid == null) return;

          final employerId = widget.job.ownerId;
          if (employerId.isEmpty) return;

          final chatId = await ChatService.getOrCreateChat(
            workerId: uid,
            employerId: employerId,
            jobId: widget.job.id,
            jobTitle: widget.job.displayTitle,
          );

          if (!mounted) return;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(chatId: chatId),
            ),
          );
        },
        icon: const Icon(Icons.chat),
        label: const Text("Message employer"),
      ),
    );
  }

  Widget buildActionPanel() {
    final isOwner = userId == widget.job.ownerId;

    return StroykaSurface(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isOwner) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: openMaps,
                icon: const Icon(Icons.map),
                label: const Text("Show location on map"),
              ),
            ),
            const SizedBox(height: 12),
            buildMessageEmployerButton(),
            const SizedBox(height: 12),
            buildApplyButton(),
          ] else ...[
            buildEditButton(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection("jobs")
                      .doc(widget.job.id)
                      .update({
                    "status": "completed",
                  });

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Job completed")),
                  );
                },
                icon: const Icon(Icons.check_circle),
                label: const Text("Complete job"),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildEmployerStats() {
    if (userId != widget.job.ownerId) return const SizedBox();

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection("applications")
          .where("jobId", isEqualTo: widget.job.id)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        final docs = snapshot.data!.docs;

        int pending = 0;
        int negotiation = 0;
        int offer = 0;
        int hired = 0;
        int rejected = 0;

        for (var doc in docs) {
          final status =
              (doc.data() as Map<String, dynamic>)["status"] ?? "pending";

          if (status == "pending") pending++;
          if (status == "negotiation") negotiation++;
          if (status == "offer_sent") offer++;
          if (status == "offer_accepted") hired++;
          if (status == "rejected") rejected++;
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: StroykaSurface(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Applications",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text("Total: ${docs.length}"),
                Text("New: $pending"),
                Text("Negotiation: $negotiation"),
                Text("Offer sent: $offer"),
                Text("Hired: $hired"),
                Text("Rejected: $rejected"),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
      children: [
        StroykaSurface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.job.shouldShowTrade)
                Text(
                  widget.job.trade,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                widget.job.displayTitle,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  metaPill(widget.job.workFormatText),
                  if (widget.job.duration.isNotEmpty)
                    metaPill(widget.job.duration),
                  if (widget.job.listRateText.isNotEmpty)
                    metaPill(widget.job.listRateText),
                ],
              ),
              buildPositionsInfo(),
              if (widget.job.weeklyHours.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        "${widget.job.weeklyHours} hours per week",
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              buildLocation(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StroykaSurface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildDescription(),
              buildJobInfoSection(
                "Candidate requirements",
                widget.job.candidateRequirements,
              ),
              buildJobInfoSection(
                "Required documents / certifications",
                widget.job.requiredDocuments,
              ),
            ],
          ),
        ),
        buildEmployerStats(),
      ],
    );
  }

  Widget metaPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget buildPhotosTab() {
    if (widget.job.photos.isEmpty) {
      return const Center(child: Text("No photos yet"));
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: widget.job.photos.length,
      itemBuilder: (context, index) {
        final photo = widget.job.photos[index];

        return GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => Dialog(
                child: Image.network(photo),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(photo, fit: BoxFit.cover),
          ),
        );
      },
    );
  }

  Widget buildCompanyTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height - 210,
          child: buildEmbeddedCompanyProfile(),
        ),
      ],
    );
  }

  Widget buildEmbeddedCompanyProfile() {
    final ownerId = widget.job.ownerId;
    if (ownerId.isEmpty || ownerId == "unknown") {
      return const StroykaSurface(
        padding: EdgeInsets.all(18),
        child: Text("Company details not available"),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(ownerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.data!.exists) {
          return const StroykaSurface(
            padding: EdgeInsets.all(18),
            child: Text("Company not found"),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final name = data["companyName"] ?? data["name"] ?? "Company";
        final description = data["bio"] ?? "";
        final address = data["location"] ?? "";
        final phone = data["phone"] ?? "";
        final contactPerson = data["contactPerson"] ?? "";
        final extraPhones = List<String>.from(data["phones"] ?? []);
        final website = data["website"] ?? "";
        final email = data["email"] ?? "";
        final logo = data["photo"] ?? data["companyLogo"] ?? data["avatarUrl"];
        final headerImage =
            (data["profileHeaderImage"] ?? data["headerImage"])?.toString();
        final photos = List<String>.from(data["companyPhotos"] ?? []);
        final canViewAllCompanyJobs = userId == ownerId || role == "admin";

        return DefaultTabController(
          length: 4,
          child: Column(
            children: [
              StroykaSurface(
                margin: const EdgeInsets.only(bottom: 10),
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
                                backgroundImage:
                                    logo is String ? NetworkImage(logo) : null,
                                child: logo == null
                                    ? const Icon(Icons.business, size: 30)
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                name.toString(),
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
                padding: const EdgeInsets.all(4),
                borderRadius: BorderRadius.circular(999),
                child: const TabBar(
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.ink,
                  labelStyle: TextStyle(fontWeight: FontWeight.w800),
                  tabs: [
                    Tab(text: "Info"),
                    Tab(text: "Contacts"),
                    Tab(text: "Vacancies"),
                    Tab(text: "Photos"),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        StroykaSurface(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "About company",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                description.toString().trim().isEmpty
                                    ? "No company description yet"
                                    : description.toString(),
                              ),
                              if (address.toString().trim().isNotEmpty) ...[
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(address.toString())),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        StroykaSurface(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (phone.toString().trim().isNotEmpty) ...[
                                PhoneLink(phone: phone.toString()),
                                const SizedBox(height: 16),
                              ],
                              if (contactPerson.toString().trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.person),
                                      const SizedBox(width: 8),
                                      Text(contactPerson.toString()),
                                    ],
                                  ),
                                ),
                              ...extraPhones.map(
                                (p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: PhoneLink(
                                    phone: p,
                                    compact: true,
                                  ),
                                ),
                              ),
                              if (email.toString().trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.email),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(email.toString())),
                                    ],
                                  ),
                                ),
                              if (website.toString().trim().isNotEmpty)
                                Row(
                                  children: [
                                    const Icon(Icons.language),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(website.toString())),
                                  ],
                                ),
                              if (phone.toString().trim().isEmpty &&
                                  extraPhones.isEmpty &&
                                  email.toString().trim().isEmpty &&
                                  website.toString().trim().isEmpty)
                                const Text("No contacts yet"),
                            ],
                          ),
                        ),
                      ],
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection("jobs")
                          .where("ownerId", isEqualTo: ownerId)
                          .orderBy("createdAt", descending: true)
                          .snapshots(),
                      builder: (context, jobsSnapshot) {
                        if (!jobsSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final jobs = jobsSnapshot.data!.docs
                            .map((doc) => Job.fromFirestore(
                                  doc.id,
                                  doc.data() as Map<String, dynamic>,
                                ))
                            .where((job) {
                          if (canViewAllCompanyJobs) return true;
                          return _isWorkerVisibleCompanyJob(job);
                        }).toList();

                        if (jobs.isEmpty) {
                          return const Center(child: Text("No jobs yet"));
                        }

                        return ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: jobs.length,
                          itemBuilder: (context, index) {
                            final job = jobs[index];
                            return JobCard(
                              job: job,
                              margin: const EdgeInsets.only(bottom: 10),
                            );
                          },
                        );
                      },
                    ),
                    ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        if (photos.isEmpty)
                          const StroykaSurface(
                            padding: EdgeInsets.all(18),
                            child: Text("No company photos yet"),
                          )
                        else
                          StroykaSurface(
                            padding: const EdgeInsets.all(18),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: photos.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemBuilder: (_, index) => ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  photos[index],
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isWorkerVisibleCompanyJob(Job job) {
    final status = job.status.trim().toLowerCase();
    final isPublished =
        status.isEmpty || status == "active" || status == "published";

    return job.moderationStatus == "approved" && isPublished;
  }

  @override
  Widget build(BuildContext context) {
    final applicationId = widget.applicationId;

    if (applicationId == null) {
      return buildScaffold(hasOffer: false);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("applications")
          .doc(applicationId)
          .snapshots(),
      builder: (context, snapshot) {
        final appData = snapshot.data?.data() as Map<String, dynamic>?;
        final offer = appData?["offer"];
        final status = appData?["status"]?.toString() ?? "";
        final hasOffer = offer is Map<String, dynamic> &&
            (status == "offer" ||
                status == "offer_sent" ||
                status == "accepted" ||
                status == "offer_accepted");

        return buildScaffold(
          hasOffer: hasOffer,
          appData: appData,
        );
      },
    );
  }

  Widget buildScaffold({
    required bool hasOffer,
    Map<String, dynamic>? appData,
  }) {
    return DefaultTabController(
      length: hasOffer ? 4 : 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Job"),
          actions: [
            IconButton(
              tooltip: "Report job",
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => ReportService.showReportDialog(
                context,
                type: "job",
                againstUserId: widget.job.ownerId,
                jobId: widget.job.id,
                applicationId: widget.applicationId,
              ),
            ),
          ],
        ),
        body: StroykaScreenBody(
          child: Column(
            children: [
              StroykaSurface(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
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
                    if (hasOffer) const Tab(text: "Offer"),
                    const Tab(text: "Info"),
                    const Tab(text: "Photos"),
                    const Tab(text: "About company"),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    if (hasOffer && appData != null) buildYourOfferTab(appData),
                    buildInfoTab(),
                    buildPhotosTab(),
                    buildCompanyTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: buildActionPanel(),
        ),
      ),
    );
  }
}
