import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/job.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_profile_screen.dart';
import '../widgets/phone_link.dart';
import '../widgets/job_card.dart';
import '../services/billing_service.dart';
import '../services/report_service.dart';
import '../services/support_request_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class EmployerProfileScreen extends StatefulWidget {
  final String userId;
  final int initialTab;

  const EmployerProfileScreen({
    super.key,
    required this.userId,
    this.initialTab = 0,
  });

  @override
  State<EmployerProfileScreen> createState() => _EmployerProfileScreenState();
}

class _EmployerProfileScreenState extends State<EmployerProfileScreen> {
  final picker = ImagePicker();
  String viewerRole = "worker";
  bool uploadingCompanyPhotos = false;

  Stream<List<Job>> getJobs() {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final canViewAllJobs = viewerId == widget.userId || viewerRole == "admin";

    return FirebaseFirestore.instance
        .collection("jobs")
        .where("ownerId", isEqualTo: widget.userId)
        .orderBy("createdAt", descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Job.fromFirestore(doc.id, doc.data());
      }).where((job) {
        if (canViewAllJobs) return true;
        return _isWorkerVisibleCompanyJob(job);
      }).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    loadViewerRole();
  }

  Future<void> loadViewerRole() async {
    final viewer = FirebaseAuth.instance.currentUser;
    if (viewer == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(viewer.uid)
        .get();

    if (!mounted) return;

    setState(() {
      viewerRole = snapshot.data()?["role"]?.toString() ?? "worker";
    });
  }

  bool _isWorkerVisibleCompanyJob(Job job) {
    final status = job.status.trim().toLowerCase();
    final isPublished =
        status.isEmpty || status == "active" || status == "published";

    return job.moderationStatus == "approved" && isPublished;
  }

  Future<void> addCompanyPhoto() async {
    if (uploadingCompanyPhotos) return;

    try {
      final picked = await picker.pickMultiImage();
      if (picked.isEmpty) return;

      setState(() => uploadingCompanyPhotos = true);

      final urls = <String>[];
      for (final image in picked) {
        final ref = FirebaseStorage.instance.ref().child(
            "company_photos/${widget.userId}_${DateTime.now().millisecondsSinceEpoch}_${image.name}");

        await ref.putFile(File(image.path));
        urls.add(await ref.getDownloadURL());
      }

      if (urls.isEmpty) return;

      await FirebaseFirestore.instance
          .collection("users")
          .doc(widget.userId)
          .set({
        "companyPhotos": FieldValue.arrayUnion(urls),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("COMPANY PHOTOS UPLOAD ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not upload company photos")),
      );
    } finally {
      if (mounted) setState(() => uploadingCompanyPhotos = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Company Profile"),
        actions: [
          if (FirebaseAuth.instance.currentUser?.uid == widget.userId) ...[
            IconButton(
              tooltip: "Support",
              icon: const Icon(Icons.support_agent_outlined),
              onPressed: () => SupportRequestService.showSupportDialog(context),
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileScreen(),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
            ),
          ] else ...[
            IconButton(
              tooltip: "Report company",
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => ReportService.showReportDialog(
                context,
                type: "company",
                againstUserId: widget.userId,
              ),
            ),
          ],
        ],
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection("users")
            .doc(widget.userId)
            .get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.data!.exists) {
            return const Center(child: Text("Company not found"));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final name = data["companyName"] ?? "Company";
          final description = data["bio"] ?? "";
          final address = data["location"] ?? "";
          final phone = data["phone"] ?? "";
          final contactPerson = data["contactPerson"] ?? "";
          final extraPhones = List<String>.from(data["phones"] ?? []);
          final website = data["website"] ?? "";
          final email = data["email"] ?? "";
          final companyGoals = data["companyGoals"]?.toString() ?? "";
          final companyAdvantages = data["companyAdvantages"]?.toString() ?? "";
          final companyClients = data["companyClients"]?.toString() ?? "";
          final companyWhoWeAre = data["companyWhoWeAre"]?.toString() ?? "";
          final companyHistory = data["companyHistory"]?.toString() ?? "";
          final role = data["role"]?.toString() ?? "";
          final billing = BillingService.billingFromUserData(data);

          final contacts = (data["contacts"] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          final logo = data["photo"];
          final headerImage =
              (data["profileHeaderImage"] ?? data["headerImage"])?.toString();
          final photos = List<String>.from(data["companyPhotos"] ?? []);
          final isMyCompany =
              FirebaseAuth.instance.currentUser?.uid == widget.userId;
          final showBilling = isMyCompany && role == "employer";
          final tabCount = showBilling ? 5 : 4;
          final initialTab = widget.initialTab.clamp(0, tabCount - 1).toInt();

          return DefaultTabController(
            length: tabCount,
            initialIndex: initialTab,
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
                                    backgroundImage: logo is String
                                        ? NetworkImage(logo)
                                        : null,
                                    child: logo == null
                                        ? const Icon(Icons.business, size: 30)
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
                        const Tab(text: "Contacts"),
                        const Tab(text: "Vacancies"),
                        const Tab(text: "Photos"),
                        if (showBilling) const Tab(text: "Billing"),
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
                                  const Text(
                                    "About company",
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    description.isEmpty
                                        ? "No company description yet"
                                        : description,
                                  ),
                                  _CompanyInfoBlock(
                                    title: "Our goals and objectives",
                                    text: companyGoals,
                                  ),
                                  _CompanyInfoBlock(
                                    title: "Our advantages",
                                    text: companyAdvantages,
                                  ),
                                  _CompanyInfoBlock(
                                    title: "Our clients",
                                    text: companyClients,
                                  ),
                                  _CompanyInfoBlock(
                                    title: "Who we are",
                                    text: companyWhoWeAre,
                                  ),
                                  _CompanyInfoBlock(
                                    title: "Our history",
                                    text: companyHistory,
                                  ),
                                  if (address.isNotEmpty) ...[
                                    const SizedBox(height: 18),
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(address)),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          children: [
                            StroykaSurface(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (phone.isNotEmpty) ...[
                                    PhoneLink(phone: phone),
                                    const SizedBox(height: 16),
                                  ],
                                  if (contactPerson.isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.person),
                                        const SizedBox(width: 8),
                                        Text(contactPerson),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (extraPhones.isNotEmpty) ...[
                                    ...extraPhones.map(
                                      (p) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child:
                                            PhoneLink(phone: p, compact: true),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  if (email.isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.email),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(email)),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (website.isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.language),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(website)),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (contacts.isEmpty &&
                                      phone.isEmpty &&
                                      email.isEmpty &&
                                      website.isEmpty)
                                    const Text("No contacts yet"),
                                  if (contacts.isNotEmpty) ...[
                                    const Text(
                                      "Team contacts",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 6),
                                    ...contacts.map(
                                      (c) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(c["name"] ?? ""),
                                        subtitle: PhoneLink(
                                          phone: c["phone"]?.toString(),
                                          compact: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        StreamBuilder<List<Job>>(
                          stream: getJobs(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final jobs = snapshot.data!;

                            if (jobs.isEmpty) {
                              return const Center(child: Text("No jobs yet"));
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
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
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          children: [
                            if (isMyCompany)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: uploadingCompanyPhotos
                                        ? null
                                        : addCompanyPhoto,
                                    icon: const Icon(Icons.add_a_photo),
                                    label: Text(uploadingCompanyPhotos
                                        ? "Uploading..."
                                        : "Add company photos"),
                                  ),
                                ),
                              ),
                            if (uploadingCompanyPhotos)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: LinearProgressIndicator(),
                              ),
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
                                  itemBuilder: (_, i) => ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(
                                      photos[i],
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (showBilling)
                          _BillingSection(
                            employerId: widget.userId,
                            billing: billing,
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

class _CompanyInfoBlock extends StatelessWidget {
  final String title;
  final String text;

  const _CompanyInfoBlock({
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(cleanText),
        ],
      ),
    );
  }
}

class _BillingSection extends StatelessWidget {
  final String employerId;
  final Map<String, dynamic> billing;

  const _BillingSection({
    required this.employerId,
    required this.billing,
  });

  static const paymentModes = [
    "manual_invoice",
    "direct_debit",
    "card",
  ];

  Future<void> _choosePlan(
    BuildContext context,
    QueryDocumentSnapshot plan,
  ) async {
    var paymentMode = billing["paymentMode"]?.toString() ?? paymentModes.first;
    if (!paymentModes.contains(paymentMode)) {
      paymentMode = paymentModes.first;
    }

    final confirmedMode = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Choose plan"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    BillingService.planName(plan),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: paymentMode,
                    decoration:
                        const InputDecoration(labelText: "Payment mode"),
                    items: paymentModes
                        .map(
                          (mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(BillingService.formatLabel(mode)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => paymentMode = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, paymentMode),
                  child: const Text("Request plan"),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmedMode == null) return;

    await BillingService().createPaymentRequest(
      employerId: employerId,
      plan: plan,
      paymentMode: confirmedMode,
      currentBilling: billing,
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Trial activated. Plan request is pending approval."),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planId = billing["planId"]?.toString() ?? "";
    final planName = billing["planName"]?.toString().trim().isNotEmpty == true
        ? billing["planName"].toString()
        : planId;
    final paymentMode = billing["paymentMode"]?.toString() ?? "Not set";
    final status = billing["status"]?.toString() ?? "Not set";
    final planRequestStatus =
        billing["planRequestStatus"]?.toString() ?? "not_requested";
    final trialActive = billing["trialActive"] == true;
    final availableJobPosts =
        BillingService.readInt(billing["availableJobPosts"]);
    final usedJobPosts = BillingService.readInt(billing["usedJobPosts"]);
    final activeUntil = BillingService.formatDate(billing["activeUntil"]);
    final trialDaysLeft = BillingService.daysRemaining(billing["activeUntil"]);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
      children: [
        StroykaSurface(
          padding: const EdgeInsets.all(18),
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Billing",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _BillingPill(
                    label: BillingService.formatLabel(status),
                    active: status == "active",
                  ),
                  if (trialActive) ...[
                    const SizedBox(width: 8),
                    const _BillingPill(
                      label: "Trial active",
                      active: true,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _BillingRow(
                label: "Current plan",
                value: planName.isEmpty ? "No plan selected" : planName,
              ),
              _BillingRow(
                label: "Available job posts",
                value: availableJobPosts.toString(),
              ),
              _BillingRow(
                label: "Used job posts",
                value: usedJobPosts.toString(),
              ),
              _BillingRow(
                label: "Payment mode",
                value: BillingService.formatLabel(paymentMode),
              ),
              _BillingRow(
                label: "Billing status",
                value: BillingService.formatLabel(status),
              ),
              _BillingRow(
                label: "Plan request",
                value: BillingService.formatLabel(planRequestStatus),
              ),
              if (trialActive)
                _BillingRow(
                  label: "Trial days left",
                  value: trialDaysLeft.toString(),
                ),
              if (activeUntil.isNotEmpty)
                _BillingRow(label: "Active until", value: activeUntil),
            ],
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection("plans").snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const StroykaSurface(
                padding: EdgeInsets.all(18),
                child: LinearProgressIndicator(),
              );
            }

            final plans = snapshot.data!.docs;
            if (plans.isEmpty) {
              return const StroykaSurface(
                padding: EdgeInsets.all(18),
                child: Text("No tariff plans yet"),
              );
            }

            return Column(
              children: plans.map((plan) {
                final data = plan.data() as Map<String, dynamic>;
                final price = data["price"]?.toString() ?? "";
                final currency = data["currency"]?.toString() ?? "GBP";
                final jobPosts = BillingService.readInt(
                  data["jobPosts"] ?? data["availableJobPosts"],
                );
                final isCurrentPlan = plan.id == billing["planId"]?.toString();

                return StroykaSurface(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              BillingService.planName(plan),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (isCurrentPlan)
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.greenDark,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (price.isNotEmpty) "$currency $price",
                          "$jobPosts job posts",
                        ].join(" • "),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _choosePlan(context, plan),
                          child: Text(
                            isCurrentPlan
                                ? "Change payment mode"
                                : "Choose plan",
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _BillingPill extends StatelessWidget {
  final String label;
  final bool active;

  const _BillingPill({
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? AppColors.green.withValues(alpha: 0.14)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? AppColors.greenDark : Colors.transparent,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? AppColors.greenDark : AppColors.ink,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _BillingRow extends StatelessWidget {
  final String label;
  final String value;

  const _BillingRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
