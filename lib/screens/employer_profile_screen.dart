import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/job.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_profile_screen.dart';
import '../widgets/job_card.dart';
import '../services/billing_service.dart';
import '../services/job_repository.dart';
import '../services/moderation_hold_service.dart';
import '../services/profile_communication_service.dart';
import '../services/report_service.dart';
import '../services/stroyka_action_feedback.dart';
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
  final jobRepository = JobRepository();
  final Map<String, Stream<List<Job>>> jobStreams = {};
  String viewerRole = "worker";
  bool uploadingCompanyPhotos = false;

  Stream<List<Job>> getJobs() {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final canViewAllJobs = viewerId == widget.userId || viewerRole == "admin";
    final streamKey =
        canViewAllJobs ? "owner:${widget.userId}" : "public:${widget.userId}";

    return jobStreams.putIfAbsent(streamKey, () {
      if (canViewAllJobs) {
        return jobRepository.getJobsByOwner(widget.userId).map((jobs) {
          debugPrint(
            "COMPANY PROFILE OWNER JOBS source=ownerId:${widget.userId} raw=${jobs.length} final=${jobs.length}",
          );
          return jobs;
        });
      }

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

        debugPrint(
          "COMPANY PROFILE PUBLIC JOBS source=public raw=${snapshot.docs.length} final=${jobs.length}",
        );
        return jobs;
      });
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

  Future<String?> askHoldMessage() async {
    final controller = TextEditingController();
    String? errorText;
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Hold employer profile"),
              content: TextField(
                controller: controller,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: "Message to employer",
                  hintText: "Explain why this profile is temporarily suspended",
                  errorText: errorText,
                  border: const StroykaInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isEmpty) {
                      setDialogState(() {
                        errorText = "Moderator message is required";
                      });
                      return;
                    }
                    Navigator.pop(context, text);
                  },
                  child: const Text("Hold"),
                ),
              ],
            );
          },
        );
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 16));
    controller.dispose();
    return result;
  }

  Future<void> holdProfile() async {
    ModerationHoldService.logHoldLifecycle(
      "HOLD PROFILE BUTTON PRESSED",
      context,
    );
    final messenger = ScaffoldMessenger.maybeOf(context);
    final route = ModalRoute.of(context);
    ModerationHoldService.logHoldLifecycle(
        "HOLD PROFILE CONFIRM OPEN", context);
    final message = await askHoldMessage();
    ModerationHoldService.logHoldLifecycleState(
      "HOLD PROFILE CONFIRM CLOSED",
      mounted: mounted,
      routeIsCurrent: route?.isCurrent,
    );
    if (message == null || message.trim().isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
    final service = ModerationHoldService();
    ModerationHoldService.logHoldLifecycleState(
      "HOLD PROFILE WRITE START",
      mounted: mounted,
      routeIsCurrent: route?.isCurrent,
    );
    await service.holdUser(
      targetUserId: widget.userId,
      role: "employer",
      message: message,
    );
    ModerationHoldService.logHoldLifecycleState(
      "HOLD PROFILE WRITE SUCCESS",
      mounted: mounted,
      routeIsCurrent: route?.isCurrent,
    );
    if (!mounted) return;
    ModerationHoldService.logHoldLifecycleState(
      "HOLD PROFILE MESSAGE START",
      mounted: mounted,
      routeIsCurrent: route?.isCurrent,
    );
    await service.sendAdminHoldMessage(
      userId: widget.userId,
      role: "employer",
      title: "Profile temporarily suspended",
      message: message,
      relatedTargetType: "profile_hold",
      relatedTargetId: widget.userId,
    );
    ModerationHoldService.logHoldLifecycleState(
      "HOLD PROFILE MESSAGE SUCCESS",
      mounted: mounted,
      routeIsCurrent: route?.isCurrent,
    );
    if (!mounted) return;
    ModerationHoldService.logHoldLifecycleState(
      "HOLD PROFILE UI UPDATE START",
      mounted: mounted,
      routeIsCurrent: route?.isCurrent,
    );
    ModerationHoldService.showCapturedSnackBar(
      messenger,
      "Profile temporarily suspended.",
    );
    ModerationHoldService.logHoldLifecycleState(
      "HOLD PROFILE UI UPDATE END",
      mounted: mounted,
      routeIsCurrent: route?.isCurrent,
    );
    ModerationHoldService.logHoldLifecycleState(
      "HOLD PROFILE NAVIGATION START",
      mounted: mounted,
      routeIsCurrent: route?.isCurrent,
    );
    ModerationHoldService.logHoldLifecycleState(
      "HOLD PROFILE NAVIGATION END",
      mounted: mounted,
      routeIsCurrent: route?.isCurrent,
    );
  }

  Future<void> restoreProfile() async {
    await ModerationHoldService().restoreUser(widget.userId);
    if (!mounted) return;
    ModerationHoldService.showSafeSnackBar(
      context,
      "Profile restored.",
    );
  }

  void openAdminInbox() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminInboxScreen(
          userId: widget.userId,
          role: "employer",
        ),
      ),
    );
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
    if (job.moderationStatus == "pending_review") return "PENDING";
    if (job.moderationStatus == "rejected") return "REJECTED";
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
      resizeToAvoidBottomInset: false,
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
                StroykaActionFeedback.showSuccess(
                  context,
                  semanticLabel: "Profile saved",
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
          final profileHeld = ModerationHoldService.isProfileHeld(data);
          final isAdminViewer = viewerRole == "admin";
          if (profileHeld) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              FocusManager.instance.primaryFocus?.unfocus();
            });
          }

          if (profileHeld && !isMyCompany && !isAdminViewer) {
            return const StroykaScreenBody(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: StroykaSurface(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_clock_outlined, size: 42),
                        SizedBox(height: 12),
                        Text(
                          "This profile is temporarily unavailable.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return DefaultTabController(
            length: tabCount,
            initialIndex: initialTab,
            child: StroykaScreenBody(
              child: Column(
                children: [
                  if (profileHeld && isMyCompany)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: StroykaSurface(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline,
                                color: Colors.orange),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    ModerationHoldService.suspensionTitle,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    ModerationHoldService.suspensionMessage,
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: openAdminInbox,
                                    icon: const Icon(
                                        Icons.mark_email_unread_outlined),
                                    label: const Text(
                                        "View Administrator Message"),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                    headerControls: isAdminViewer
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed:
                                    profileHeld ? restoreProfile : holdProfile,
                                icon: Icon(profileHeld
                                    ? Icons.restore_outlined
                                    : Icons.pause_circle_outline),
                                label: Text(profileHeld
                                    ? "Restore Profile"
                                    : "Hold Profile"),
                              ),
                            ],
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

class _BillingSection extends StatefulWidget {
  final String employerId;
  final Map<String, dynamic> billing;
  final bool closeAfterPlanRequest;

  const _BillingSection({
    required this.employerId,
    required this.billing,
    this.closeAfterPlanRequest = false,
  });

  @override
  State<_BillingSection> createState() => _BillingSectionState();
}

class _BillingSectionState extends State<_BillingSection>
    with WidgetsBindingObserver {
  String? settingUpPlanId;
  String? changingPlanId;
  bool refreshing = false;
  Map<String, dynamic>? overrideBilling;

  String get employerId => widget.employerId;
  bool get closeAfterPlanRequest => widget.closeAfterPlanRequest;
  Map<String, dynamic> get billing => overrideBilling ?? widget.billing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshBillingStatus(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBillingStatus(silent: true);
    }
  }

  Future<void> _refreshBillingStatus({bool silent = false}) async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      overrideBilling =
          await BillingService().getAuthoritativeCompanyBillingStatus();
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Billing status refreshed")),
      );
    } catch (_) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not refresh billing status")),
      );
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> _setUpDirectDebit(
    BuildContext context,
    String planId,
  ) async {
    if (settingUpPlanId != null) return;
    setState(() => settingUpPlanId = planId);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable("createGoCardlessDirectDebitSetup")
          .call({"planId": planId});
      final data = result.data;
      final url = data is Map ? data["authorisationUrl"]?.toString() : null;
      final uri = Uri.tryParse(url ?? "");
      if (uri == null || uri.scheme != "https" || uri.host.isEmpty) {
        throw Exception("missing_authorisation_url");
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw Exception("launch_failed");

      await _refreshBillingStatus(silent: true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Direct Debit setup opened. Return here to refresh status.",
          ),
        ),
      );

      if (closeAfterPlanRequest && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } on FirebaseFunctionsException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? "Could not start Direct Debit setup"),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not start Direct Debit setup")),
      );
    } finally {
      if (mounted) setState(() => settingUpPlanId = null);
    }
  }

  Future<void> _changePlan(BuildContext context, String planId) async {
    if (changingPlanId != null) return;
    setState(() => changingPlanId = planId);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable("changeGoCardlessPlan")
          .call({"planId": planId});
      final data = result.data;
      if (data is Map) {
        overrideBilling = Map<String, dynamic>.from(data);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Billing plan updated")),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Could not change billing plan")),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not change billing plan")),
      );
    } finally {
      if (mounted) setState(() => changingPlanId = null);
    }
  }

  Future<void> _cancelDirectDebit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Cancel Direct Debit?"),
        content: const Text(
          "New vacancy publishing will pause while Direct Debit is restored. Existing live vacancies stay visible during the 3 day recovery window.",
        ),
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
    if (confirmed != true) return;

    setState(() => refreshing = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable("cancelGoCardlessSubscription")
          .call();
      final data = result.data;
      if (data is Map) {
        overrideBilling = Map<String, dynamic>.from(data);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Direct Debit cancellation requested")),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not cancel Direct Debit")),
      );
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final planId = billing["planId"]?.toString() ?? "";
    final planName = billing["planName"]?.toString().trim().isNotEmpty == true
        ? billing["planName"].toString()
        : planId;
    final status = billing["status"]?.toString() ?? "Not set";
    final billingPlanStatus =
        billing["billingPlanStatus"]?.toString() ?? status;
    final paymentStatus = billing["paymentStatus"]?.toString() ?? "Not set";
    final subscriptionStatus =
        billing["subscriptionStatus"]?.toString() ?? "not_started";
    final billingStatus =
        billing["billingStatus"]?.toString() ?? subscriptionStatus;
    final directDebitConfigured =
        BillingService.isDirectDebitConfigured(billing);
    final currentPlanId = BillingService.currentPlanId(billing);
    final pendingPlanId = billing["pendingPlanId"]?.toString() ?? "";
    final billingEmail = billing["billingEmail"]?.toString() ?? "Not set";
    final billingEmailVerified = billing["billingEmailVerified"] == true;
    final trialActive = billing["trialActive"] == true;
    final trialStatus = billing["trialStatus"]?.toString() ??
        (trialActive ? "active" : "not_started");
    final totalSlots = BillingService.readInt(
      billing["vacancySlotLimit"] ??
          billing["activeSlots"] ??
          billing["includedJobSlots"] ??
          billing["availableJobPosts"],
    );
    final trialEndsAt = billing["trialEndsAt"] ?? billing["trialEndDate"];
    final trialDaysLeft = BillingService.daysRemaining(trialEndsAt);

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
                    label: BillingService.formatLabel(
                      directDebitConfigured ? billingStatus : billingPlanStatus,
                    ),
                    active: billingStatus == "active" || directDebitConfigured,
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
                label: "Vacancy slot limit",
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
                label: "Billing email",
                value: billingEmail,
              ),
              _BillingRow(
                label: "Billing email status",
                value: billingEmailVerified ? "Verified" : "Provided",
              ),
              _BillingRow(
                label: "Billing status",
                value: BillingService.formatLabel(billingStatus),
              ),
              _BillingRow(
                label: "Subscription status",
                value: BillingService.formatLabel(subscriptionStatus),
              ),
              _BillingRow(
                label: "Direct Debit",
                value: directDebitConfigured ? "Active" : "Set up required",
              ),
              _BillingRow(
                label: "Trial status",
                value: BillingService.formatLabel(trialStatus),
              ),
              _BillingRow(
                label: "Trial end date",
                value: BillingService.formatDate(trialEndsAt),
              ),
              _BillingRow(
                label: "Payment status",
                value: BillingService.formatLabel(paymentStatus),
              ),
              _BillingRow(
                label: "Next billing date",
                value: BillingService.formatDate(
                  billing["nextChargeDate"] ??
                      billing["nextBillingDate"] ??
                      billing["firstPaymentDate"],
                ),
              ),
              if (pendingPlanId.isNotEmpty)
                _BillingRow(
                  label: "Pending plan",
                  value:
                      "${BillingService.formatLabel(pendingPlanId)} from ${BillingService.formatDate(billing["pendingPlanEffectiveAt"])}",
                ),
              if (trialActive)
                _BillingRow(
                  label: "Trial days left",
                  value: trialDaysLeft.toString(),
                ),
            ],
          ),
        ),
        Column(
          children: BillingService.plansFromBilling(billing).map((plan) {
            final planId = plan["id"]?.toString() ?? "";
            final amountPence = BillingService.readInt(plan["amountPence"]);
            final price = amountPence > 0
                ? (amountPence / 100).toStringAsFixed(0)
                : plan["price"]?.toString() ?? "";
            final currency = plan["currency"]?.toString() ?? "GBP";
            final vacancySlots = BillingService.readInt(
              plan["vacancySlotLimit"] ??
                  plan["jobPosts"] ??
                  plan["availableJobPosts"],
            );
            final isCurrentPlan = planId == currentPlanId;
            final planBusy = settingUpPlanId == planId;
            final changeBusy = changingPlanId == planId;
            final anySetupBusy =
                settingUpPlanId != null || changingPlanId != null || refreshing;

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
                          BillingService.planDisplayName(plan),
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
                      "$vacancySlots vacancy slots",
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
                      onPressed: anySetupBusy ||
                              (directDebitConfigured && isCurrentPlan)
                          ? null
                          : directDebitConfigured
                              ? () => _changePlan(context, planId)
                              : () => _setUpDirectDebit(context, planId),
                      child: Text(
                        directDebitConfigured
                            ? changeBusy
                                ? "Updating plan..."
                                : isCurrentPlan
                                    ? "Current plan"
                                    : "Change plan"
                            : planBusy
                                ? "Opening Direct Debit..."
                                : "Set up Direct Debit",
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        if (directDebitConfigured)
          StroykaSurface(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(top: 2),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: refreshing ? null : () => _refreshBillingStatus(),
                  icon: const Icon(Icons.refresh),
                  label: const Text("Refresh"),
                ),
                OutlinedButton.icon(
                  onPressed: settingUpPlanId != null
                      ? null
                      : () => _setUpDirectDebit(context, currentPlanId),
                  icon: const Icon(Icons.account_balance),
                  label: const Text("Replace Direct Debit"),
                ),
                OutlinedButton.icon(
                  onPressed:
                      refreshing ? null : () => _cancelDirectDebit(context),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text("Cancel Direct Debit"),
                ),
              ],
            ),
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
