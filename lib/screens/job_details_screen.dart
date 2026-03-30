import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'employer_profile_screen.dart';
import 'post_job_screen.dart';
import 'applicants_screen.dart';

import '../models/job.dart';

class JobDetailScreen extends StatefulWidget {
  final Job job;

  const JobDetailScreen({
    super.key,
    required this.job,
  });

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  bool isApplying = false;
  bool isApplied = false;
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

    final snap = await FirebaseFirestore.instance
        .collection("applications")
        .where("jobId", isEqualTo: widget.job.id)
        .where("workerId", isEqualTo: uid)
        .limit(1)
        .get();

    if (mounted) {
      setState(() {
        isApplied = snap.docs.isNotEmpty;
      });
    }
  }

  /// 🔥 LOAD MY TEAMS
  Future<List<QueryDocumentSnapshot>> loadMyTeams() async {
    final uid = userId;
    if (uid == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection("teams")
        .where("members", arrayContains: uid)
        .get();

    return snap.docs;
  }

  /// 🔥 PICK TEAM
  Future<Map<String, dynamic>?> pickTeam(BuildContext context) async {
    final teams = await loadMyTeams();

    if (teams.isEmpty) return null;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (_) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: teams.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final members = (data["members"] as List?) ?? [];

            return ListTile(
              leading: const Icon(Icons.group),
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

    /// 🔥 CHECK AVAILABLE POSITIONS
    if (widget.job.remainingPositions <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No positions left")),
      );
      return;
    }

    try {
      setState(() => isApplying = true);

      final userDoc =
          await FirebaseFirestore.instance.collection("users").doc(uid).get();

      final workerName = userDoc.data()?["name"] ?? "Worker";

      /// 🔥 ШАГ 1 — ВЫБОР ТИПА
      final type = await pickApplyType(context);

      /// ❌ пользователь закрыл выбор
      if (type == null) {
        setState(() => isApplying = false);
        return;
      }

      /// =====================================================
      /// 👥 TEAM APPLY
      /// =====================================================
      if (type == "team") {
        final team = await pickTeam(context);

        /// ❌ закрыл выбор команды
        if (team == null) {
          setState(() => isApplying = false);
          return;
        }

        final members = List<String>.from(team["members"]);

        /// ❗ проверка мест
        if (members.length > widget.job.remainingPositions) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Not enough spots")),
            );
          }
          setState(() => isApplying = false);
          return;
        }

        await FirebaseFirestore.instance.collection("applications").add({
          "jobId": widget.job.id,
          "jobTitle": widget.job.title,
          "type": "team",
          "teamId": team["teamId"],
          "members": members,

          /// 🔥 НОВОЕ
          "membersStatus": {for (var id in members) id: "pending"},

          "employerId": widget.job.ownerId,
          "status": "pending",
          "createdAt": FieldValue.serverTimestamp(),
        });

        if (mounted) {
          setState(() {
            isApplying = false;
            isApplied = true;
          });
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
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) {
          if (mounted) {
            setState(() {
              isApplying = false;
              isApplied = true;
            });
          }
          return;
        }

        await FirebaseFirestore.instance.collection("applications").add({
          "jobId": widget.job.id,
          "jobTitle": widget.job.title,
          "workerId": uid,
          "workerName": workerName,
          "type": "single",

          /// 🔥 ДЕЛАЕМ ЕДИНУЮ ЛОГИКУ
          "members": [uid],
          "membersStatus": {uid: "pending"},

          "employerId": widget.job.ownerId,
          "status": "pending",
          "createdAt": FieldValue.serverTimestamp(),
        });

        if (mounted) {
          setState(() {
            isApplying = false;
            isApplied = true;
          });
        }

        return;
      }
    } catch (e) {
      debugPrint("APPLY ERROR: $e");
      if (mounted) setState(() => isApplying = false);
    }
  }

  Future<void> openMaps() async {
    final url =
        "https://www.google.com/maps/search/?api=1&query=${widget.job.lat},${widget.job.lng}";

    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
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
    if (role == "employer") return const SizedBox();

    String text = "Apply for this job";
    if (widget.job.remainingPositions <= 0) {
      text = "No spots left";
    }

    if (isApplied) text = "Applied";
    if (isApplying) text = "Applying...";

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed:
            (isApplied || isApplying || widget.job.remainingPositions <= 0)
                ? null
                : apply,
        child: Text(text, style: const TextStyle(fontSize: 18)),
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
      height: 50,
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
      height: 50,
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

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection("users").doc(ownerId).get(),
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

        final photo = data["photo"];

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EmployerProfileScreen(
                  userId: ownerId,
                ),
              ),
            );
          },
          child: Container(
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
                  child: photo == null
                      ? const Icon(Icons.business, size: 28)
                      : null,
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
                      const SizedBox(height: 4),
                      const Text(
                        "Tap to view profile",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16)
              ],
            ),
          ),
        );
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
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
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
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildLocation() {
    return Row(
      children: [
        const Icon(Icons.location_on),
        const SizedBox(width: 6),
        Expanded(
          child: Text(widget.job.fullAddress),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Job")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildCompany(),
            const SizedBox(height: 24),
            buildPhotos(),
            Text(widget.job.trade),
            const SizedBox(height: 4),
            Text(
              widget.job.title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            buildRateCard(),

            /// 👇 ВОТ СЮДА ВСТАВЛЯЙ
            if (widget.job.positions > 1)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    const Icon(Icons.group, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      "${widget.job.remainingPositions}/${widget.job.positions} spots available",
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            /// 🔥 DURATION (НОВОЕ)
            if (widget.job.duration.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      widget.job.duration,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            buildLocation(),
            const SizedBox(height: 24),
            buildDescription(),
            const SizedBox(height: 30),
            OutlinedButton.icon(
              onPressed: openMaps,
              icon: const Icon(Icons.map),
              label: const Text("Show location on map"),
            ),
            const SizedBox(height: 20),

            buildEditButton(),
            const SizedBox(height: 10),
            buildDeleteButton(),
            const SizedBox(height: 10),
            buildApplyButton(),
            if (userId == widget.job.ownerId)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ApplicantsScreen(
                            jobId: widget.job.id,
                          ),
                        ),
                      );
                    },
                    child: const Text("View applicants"),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
