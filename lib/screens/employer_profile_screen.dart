import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/job.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_profile_screen.dart';
import '../widgets/job_card.dart';
import '../services/billing_service.dart';
import '../services/profile_communication_service.dart';
import '../services/report_service.dart';
import '../services/support_request_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';
import '../widgets/app_photo_grid_gallery.dart';
import '../widgets/company_profile_sections.dart';
import '../widgets/profile_hamburger_menu.dart';

class EmployerProfileScreen extends StatefulWidget {
  final String userId;
  final int initialTab;
  final bool showBackButton;

  const EmployerProfileScreen({
    super.key,
    required this.userId,
    this.initialTab = 0,
    this.showBackButton = false,
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
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      final jobs = snapshot.docs
          .where((doc) => _jobDataBelongsToCompany(doc.data(), widget.userId))
          .map((doc) => Job.fromFirestore(doc.id, doc.data()))
          .where(
            (job) => _isCompanyProfileVisibleJob(
              job,
              canViewAllJobs: canViewAllJobs,
            ),
          )
          .toList();

      jobs.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      return jobs;
    });
  }

  bool _jobDataBelongsToCompany(Map<String, dynamic> data, String companyId) {
    final normalizedCompanyId = companyId.trim();
    if (normalizedCompanyId.isEmpty) return false;

    for (final field in ["ownerId", "employerId", "createdBy", "userId"]) {
      final value = data[field]?.toString().trim();
      if (value == normalizedCompanyId) return true;
    }

    return false;
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

  bool _isCompanyProfileVisibleJob(
    Job job, {
    required bool canViewAllJobs,
  }) {
    final status = job.status.trim().toLowerCase();
    if (status == "deleted") return false;

    if (canViewAllJobs) return true;

    final activeStatus = status.isEmpty ||
        status == "active" ||
        status == "published" ||
        status == "open";

    if (!activeStatus || job.isClosed) return false;
    return job.isPubliclyVisible;
  }

  String _companyJobStatusLabel(Job job) {
    if (job.moderationStatus == "pending_review") return "ADMIN REVIEW";
    if (job.moderationStatus == "rejected") return "ADMIN REJECTED";
    return job.isClosed ? "INACTIVE" : "ACTIVE";
  }

  Color _companyJobStatusColor(Job job) {
    if (job.moderationStatus == "pending_review") {
      return AppColors.blueprintLine;
    }
    if (job.moderationStatus == "rejected") return AppColors.danger;
    return job.isClosed ? AppColors.warning : AppColors.success;
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
    final isMyCompany = FirebaseAuth.instance.currentUser?.uid == widget.userId;

    return Scaffold(
      drawer: isMyCompany ? const ProfileHamburgerMenu(role: "employer") : null,
      appBar: AppBar(
        leading: isMyCompany
            ? widget.showBackButton
                ? const BackButton()
                : Builder(
                    builder: (context) => const ProfileHamburgerButton(),
                  )
            : null,
        title: const Text("Company Profile"),
        actions: [
          if (isMyCompany) ...[
            IconButton(
              tooltip: "Support",
              icon: const Icon(Icons.support_agent_outlined),
              onPressed: () => SupportRequestService.showSupportDialog(context),
            ),
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
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (!context.mounted) return;
                Navigator.of(context, rootNavigator: true)
                    .popUntil((route) => route.isFirst);
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
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(widget.userId)
            .snapshots(),
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
          final showBilling = isMyCompany && role == "employer";
          final tabCount = showBilling ? 5 : 4;
          final initialTab = widget.initialTab.clamp(0, tabCount - 1).toInt();

          return DefaultTabController(
            length: tabCount,
            initialIndex: initialTab,
            child: StroykaScreenBody(
              child: Column(
                children: [
                  StroykaProfileHeader(
                    title: name,
                    avatarUrl: logo is String ? logo : null,
                    headerImageUrl: headerImage,
                    fallbackIcon: Icons.business,
                    rightBottomAction: !isMyCompany
                        ? ProfileCommunicationService.circleAction(
                            icon: Icons.chat_bubble_outline,
                            tooltip: "Message company",
                            onPressed: () => ProfileCommunicationService
                                .openDirectProfileChat(
                              context: context,
                              targetUserId: widget.userId,
                              targetRole: "employer",
                            ),
                          )
                        : null,
                  ),
                  StroykaTabBar(
                    labels: [
                      "Info",
                      "Contacts",
                      "Vacancies",
                      "Photos",
                      if (showBilling) "Billing",
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          children: [
                            CompanyInfoWidget(
                              description: description.toString(),
                              address: address.toString(),
                              companyGoals: companyGoals,
                              companyAdvantages: companyAdvantages,
                              companyClients: companyClients,
                              companyWhoWeAre: companyWhoWeAre,
                              companyHistory: companyHistory,
                            ),
                          ],
                        ),
                        ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                          children: [
                            CompanyContactsWidget(
                              phone: phone.toString(),
                              contactPerson: contactPerson.toString(),
                              extraPhones: extraPhones,
                              email: email.toString(),
                              website: website.toString(),
                              contacts: contacts,
                            ),
                          ],
                        ),
                        StreamBuilder<List<Job>>(
                          stream: getJobs(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.waiting &&
                                !snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (snapshot.hasError) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text("Could not load vacancies"),
                                ),
                              );
                            }

                            final jobs = snapshot.data ?? const <Job>[];

                            if (jobs.isEmpty) {
                              return const Center(
                                child: Text("No vacancies to display."),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                              itemCount: jobs.length + 1,
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return StroykaSurface(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(14),
                                    child: Text(
                                      "${jobs.length} ${jobs.length == 1 ? "vacancy" : "vacancies"}",
                                      style: const TextStyle(
                                        color: AppColors.ink,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  );
                                }

                                final job = jobs[index - 1];

                                return JobCard(
                                  job: job,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  statusText:
                                      isMyCompany || viewerRole == "admin"
                                          ? _companyJobStatusLabel(job)
                                          : null,
                                  statusColor:
                                      isMyCompany || viewerRole == "admin"
                                          ? _companyJobStatusColor(job)
                                          : null,
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
                                child: AppPhotoGridGallery(imageUrls: photos),
                              ),
                          ],
                        ),
                        if (showBilling)
                          _BillingSection(
                            employerId: widget.userId,
                            billing: billing,
                            closeAfterPlanRequest: widget.showBackButton,
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

class _BillingSection extends StatelessWidget {
  final String employerId;
  final Map<String, dynamic> billing;
  final bool closeAfterPlanRequest;

  const _BillingSection({
    required this.employerId,
    required this.billing,
    this.closeAfterPlanRequest = false,
  });

  static const paymentModes = [
    "manual_invoice",
    "direct_debit",
    "card",
  ];

  bool _hasManualInvoiceDetails(Map<String, dynamic> billing) {
    final details = billing["invoiceDetails"] is Map
        ? Map<String, dynamic>.from(billing["invoiceDetails"] as Map)
        : <String, dynamic>{};
    final legalName = details["legalCompanyName"]?.toString().trim() ?? "";
    final billingAddress = details["billingAddress"]?.toString().trim() ?? "";
    final contactName = details["billingContactName"]?.toString().trim() ?? "";
    return legalName.isNotEmpty &&
        billingAddress.isNotEmpty &&
        contactName.isNotEmpty;
  }

  Future<void> _choosePlan(
    BuildContext context,
    QueryDocumentSnapshot plan,
  ) async {
    var paymentMode = billing["paymentMode"]?.toString() ?? paymentModes.first;
    if (!paymentModes.contains(paymentMode)) {
      paymentMode = paymentModes.first;
    }
    final billingEmail = (billing["billingEmail"] ?? "").toString().trim();
    if (!BillingService.isValidEmail(billingEmail)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Add a valid company billing email before requesting a plan.",
          ),
        ),
      );
      return;
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
    if (confirmedMode == "manual_invoice" &&
        !_hasManualInvoiceDetails(billing)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Add manual invoice company details in your company profile before requesting Manual Invoice billing.",
          ),
        ),
      );
      return;
    }

    await BillingService().createPaymentRequest(
      employerId: employerId,
      plan: plan,
      paymentMode: confirmedMode,
      currentBilling: billing,
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Plan request submitted. It is pending admin approval."),
      ),
    );

    if (closeAfterPlanRequest && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final planId = billing["planId"]?.toString() ?? "";
    final planName = billing["planName"]?.toString().trim().isNotEmpty == true
        ? billing["planName"].toString()
        : planId;
    final paymentMode = billing["paymentMode"]?.toString() ?? "Not set";
    final status = billing["status"]?.toString() ?? "Not set";
    final billingPlanStatus =
        billing["billingPlanStatus"]?.toString() ?? status;
    final paymentStatus = billing["paymentStatus"]?.toString() ?? "Not set";
    final invoiceStatus = billing["invoiceStatus"]?.toString() ?? "Not set";
    final subscriptionStatus =
        billing["subscriptionStatus"]?.toString() ?? "not_started";
    final billingEmail = billing["billingEmail"]?.toString() ?? "Not set";
    final billingEmailVerified = billing["billingEmailVerified"] == true;
    final planRequestStatus =
        billing["planRequestStatus"]?.toString() ?? "not_requested";
    final trialActive = billing["trialActive"] == true;
    final trialStatus = billing["trialStatus"]?.toString() ??
        (trialActive ? "active" : "not_started");
    final availableJobPosts =
        BillingService.readInt(billing["availableJobPosts"]);
    final totalSlots = BillingService.readInt(
      billing["activeSlots"] ??
          billing["includedJobSlots"] ??
          billing["availableJobPosts"],
    );
    final pendingPlan = billing["pendingPlan"]?.toString() ?? "";
    final pendingPaymentMethod =
        billing["pendingPaymentMethod"]?.toString() ?? "";
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
                    label: BillingService.formatLabel(billingPlanStatus),
                    active: billingPlanStatus == "approved",
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
                label: "Total slots",
                value: totalSlots.toString(),
              ),
              StreamBuilder<int>(
                stream: BillingService().publishedJobSlotsStream(employerId),
                builder: (context, snapshot) {
                  final usedJobPosts = snapshot.data ??
                      BillingService.readInt(billing["usedJobPosts"]);
                  final calculatedAvailable =
                      (totalSlots - usedJobPosts).clamp(0, 999999);
                  return Column(
                    children: [
                      _BillingRow(
                        label: "Used slots",
                        value: usedJobPosts.toString(),
                      ),
                      _BillingRow(
                        label: "Available slots",
                        value: calculatedAvailable.toString(),
                      ),
                    ],
                  );
                },
              ),
              _BillingRow(
                label: "Payment mode",
                value: BillingService.formatLabel(paymentMode),
              ),
              _BillingRow(
                label: "Billing email",
                value: billingEmail,
              ),
              _BillingRow(
                label: "Billing email status",
                value: billingEmailVerified ? "Verified" : "Provided",
              ),
              _BillingRow(
                label: "Plan status",
                value: BillingService.formatLabel(billingPlanStatus),
              ),
              _BillingRow(
                label: "Subscription status",
                value: BillingService.formatLabel(subscriptionStatus),
              ),
              _BillingRow(
                label: "Trial status",
                value: BillingService.formatLabel(trialStatus),
              ),
              _BillingRow(
                label: "Trial end date",
                value: BillingService.formatDate(billing["trialEndsAt"]),
              ),
              _BillingRow(
                label: "Payment status",
                value: BillingService.formatLabel(paymentStatus),
              ),
              _BillingRow(
                label: "Invoice status",
                value: BillingService.formatLabel(invoiceStatus),
              ),
              _BillingRow(
                label: "Plan request",
                value: BillingService.formatLabel(planRequestStatus),
              ),
              if (pendingPlan.isNotEmpty)
                _BillingRow(label: "Pending plan", value: pendingPlan),
              if (pendingPaymentMethod.isNotEmpty)
                _BillingRow(
                  label: "Pending payment method",
                  value: BillingService.formatLabel(pendingPaymentMethod),
                ),
              _BillingRow(
                label: "Next billing date",
                value: BillingService.formatDate(billing["nextBillingDate"]),
              ),
              if (paymentMode == "direct_debit")
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    "Direct Debit integration will be activated once payment gateway implementation is completed.",
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if ((billing["lastInvoicePdfUrl"]?.toString() ?? "").isNotEmpty)
                const _BillingRow(
                  label: "Latest invoice",
                  value: "PDF available",
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
