import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  /// 🔥 INIT
  Future<void> init() async {
    await loadRole();
    await checkIfApplied();
  }

  /// 🔥 LOAD ROLE
  Future<void> loadRole() async {
    final uid = userId;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .get();

    if (doc.exists) {
      role = doc.data()?["role"] ?? "worker";
    }
  }

  /// 🔥 CHECK APPLICATION
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

  /// 🔥 APPLY (ФИНАЛЬНАЯ ВЕРСИЯ)
  Future<void> apply() async {
    final uid = userId;

    if (uid == null) return;

    try {
      setState(() => isApplying = true);

      /// 🔥 получаем имя worker
      final userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .get();

      final workerName = userDoc.data()?["name"] ?? "Worker";

      /// 🔥 защита от дублей
      final existing = await FirebaseFirestore.instance
          .collection("applications")
          .where("jobId", isEqualTo: widget.job.id)
          .where("workerId", isEqualTo: uid)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        setState(() {
          isApplying = false;
          isApplied = true;
        });
        return;
      }

      /// 🔥 создаем application (ВАЖНО — все поля)
      await FirebaseFirestore.instance.collection("applications").add({
        "jobId": widget.job.id,
        "jobTitle": widget.job.title,
        "workerId": uid,
        "workerName": workerName,
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

    } catch (e) {
      debugPrint("❌ APPLY ERROR: $e");

      if (mounted) {
        setState(() => isApplying = false);
      }
    }
  }

  /// MAP
  Future<void> openMaps() async {
    final url =
        "https://www.google.com/maps/search/?api=1&query=${widget.job.lat},${widget.job.lng}";

    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// 🔥 APPLY BUTTON
  Widget buildApplyButton() {
    /// ❌ employer не видит кнопку
    if (role == "employer") return const SizedBox();

    String text = "Apply for this job";

    if (isApplied) text = "Applied";
    if (isApplying) text = "Applying...";

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: isApplied || isApplying ? null : apply,
        child: Text(
          text,
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }

  /// ---------- UI ----------

  Widget buildPhotos() {
    if (widget.job.photos == null || widget.job.photos!.isEmpty) {
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
            itemCount: widget.job.photos!.length,
            itemBuilder: (context, index) {
              final photo = widget.job.photos![index];

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

  Widget buildCompany() {
    ImageProvider? logo;

    if (widget.job.companyLogo != null &&
        widget.job.companyLogo!.isNotEmpty) {
      logo = NetworkImage(widget.job.companyLogo!);
    }

    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.grey.shade300,
          backgroundImage: logo,
          child: logo == null ? const Icon(Icons.business) : null,
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Employer",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              widget.job.companyName ?? "Company",
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        )
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
          style:
              TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(widget.job.description ?? "No description"),
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
            buildApplyButton(),
          ],
        ),
      ),
    );
  }
}