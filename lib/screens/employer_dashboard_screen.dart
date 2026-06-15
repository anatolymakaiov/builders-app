import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/job.dart';
import 'employer_applications_screen.dart';
import 'job_details_screen.dart';
import '../services/job_repository.dart';
import '../services/notification_service.dart';
import '../services/billing_service.dart';
import '../services/job_taxonomy_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';
import '../widgets/job_pagination.dart';
import '../widgets/smart_job_search.dart';

class EmployerDashboardScreen extends StatefulWidget {
  const EmployerDashboardScreen({super.key});

  @override
  State<EmployerDashboardScreen> createState() =>
      _EmployerDashboardScreenState();
}

class _EmployerDashboardScreenState extends State<EmployerDashboardScreen> {
  static const int _jobsPerPage = 10;

  final jobRepository = JobRepository();
  late final Stream<List<Job>> publicJobsStream;
  final Map<String, Stream<List<Job>>> ownerJobsStreams = {};
  String selectedTrade = "All";
  String selectedSite = "All";
  String searchQuery = "";
  List<ConstructionRole> selectedRoles = [];
  JobSearchFilters searchFilters = const JobSearchFilters();
  bool showOnlyMyJobs = false;
  int currentPage = 1;

  @override
  void initState() {
    super.initState();
    publicJobsStream = jobRepository.getJobs();
  }

  Stream<List<Job>> ownerJobsStream(String ownerId) {
    return ownerJobsStreams.putIfAbsent(
      ownerId,
      () => jobRepository.getJobsByOwner(ownerId),
    );
  }

  Widget buildCompanyAvatar(Job job, Map<String, dynamic>? employerData) {
    final avatarUrl = employerData?["companyLogo"] ??
        employerData?["photo"] ??
        employerData?["avatarUrl"] ??
        job.companyLogo;
    return StroykaAvatar(
      imageUrl: avatarUrl?.toString(),
      fallbackIcon: Icons.business,
      size: 64,
    );
  }

  String companyNameFor(Job job, Map<String, dynamic>? employerData) {
    return (employerData?["companyName"] ??
            employerData?["name"] ??
            employerData?["displayName"] ??
            job.companyName)
        .toString()
        .trim();
  }

  Widget buildMetaChip({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return AppChip(
      icon: icon,
      label: label,
      color: color ?? AppColors.greenDark,
    );
  }

  List<Widget> buildJobChips(Job job) {
    final chips = <Widget>[
      buildMetaChip(
        icon: Icons.work_outline,
        label: job.workFormatText,
        color: AppColors.ink,
      ),
    ];

    if (job.duration.isNotEmpty) {
      chips.add(
        buildMetaChip(
          icon: Icons.timelapse,
          label: job.duration,
          color: AppColors.greenDark,
        ),
      );
    }

    if (job.listRateText.isNotEmpty) {
      chips.add(
        buildMetaChip(
          icon: Icons.payments_outlined,
          label: job.listRateText,
          color: Colors.green,
        ),
      );
    }

    return chips;
  }

  int applicationSlotCount(Map<String, dynamic> data) {
    final workersCount = data["workersCount"];
    if (workersCount is num && workersCount > 0) return workersCount.toInt();

    final members = data["members"];
    if (members is List && members.isNotEmpty) return members.length;

    return 1;
  }

  Widget buildStatTile({
    required String label,
    required int value,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: value > 0 ? onTap : null,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Text(
                value.toString(),
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void openApplicationsFor(Job job, String status) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployerApplicationsScreen(
          initialJobId: job.id,
          initialStatus: status,
        ),
      ),
    );
  }

  Future<void> setJobActive(Job job, bool active) async {
    final nextStatus = active ? "active" : "closed";

    if (active && job.moderationStatus == "approved") {
      try {
        await BillingService().assertEmployerCanPost(job.ownerId);
      } on BillingLimitException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        return;
      }
    }

    await FirebaseFirestore.instance.collection("jobs").doc(job.id).set({
      "status": nextStatus,
      if (job.moderationStatus == "approved") "billingCounted": active,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (job.moderationStatus == "approved") {
      await BillingService().syncUsedJobPosts(job.ownerId);
    }

    await NotificationService().notifyEmployerJobStatusChanged(
      employerId: job.ownerId,
      jobId: job.id,
      jobTitle: job.displayTitle,
      status: nextStatus,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(active ? "Vacancy activated" : "Vacancy made inactive"),
      ),
    );
  }

  Widget buildFilterDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: items.contains(value) ? value : "All",
      isExpanded: true,
      decoration: AppInputFields.decoration().copyWith(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      style: const TextStyle(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
      ),
      items: items.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(
            item,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
    );
  }

  Widget buildFilterPanel(List<String> tradeList, List<String> siteList) {
    return StroykaSurface(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: buildFilterDropdown(
              value: selectedTrade,
              items: tradeList,
              onChanged: (value) => setState(() => selectedTrade = value),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: buildFilterDropdown(
              value: selectedSite,
              items: siteList,
              onChanged: (value) => setState(() => selectedSite = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildStatusBadge(Job job) {
    if (job.moderationStatus == "pending_review") {
      return AppChip.status(
        "PENDING",
        color: AppColors.blueprintLine,
      );
    }

    if (job.moderationStatus == "rejected") {
      return AppChip.status(
        "REJECTED",
        color: AppColors.danger,
      );
    }

    final isClosed = job.isClosed;
    return AppChip.status(
      isClosed ? "INACTIVE" : "ACTIVE",
      color: isClosed ? AppColors.warning : AppColors.success,
    );
  }

  Widget buildApplicationStats(Job job) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("applications")
          .where("jobId", isEqualTo: job.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Text("Applications: ...");
        }

        final docs = snapshot.data!.docs;

        int inReview = 0;
        int offer = 0;
        int acceptedSlots = 0;
        int rejected = 0;

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data["status"] ?? "pending";

          if (status == "pending" ||
              status == "applied" ||
              status == "review") {
            inReview++;
          }
          if (status == "offer_sent") offer++;
          if (status == "offer_accepted" || status == "accepted") {
            acceptedSlots += applicationSlotCount(data);
          }
          if (status == "rejected" || status == "withdrawn") rejected++;
        }

        final spotsLeft =
            (job.positions - acceptedSlots).clamp(0, job.positions);

        final stats = [
          (
            label: "Applied",
            value: docs.length,
            color: AppColors.ink,
            status: "all"
          ),
          (
            label: "Review",
            value: inReview,
            color: AppColors.greenDark,
            status: "pending"
          ),
          (
            label: "Offers",
            value: offer,
            color: AppColors.green,
            status: "offer_sent"
          ),
          (
            label: "Accepted",
            value: acceptedSlots,
            color: Colors.green,
            status: "offer_accepted"
          ),
          (
            label: "Rejected",
            value: rejected,
            color: Colors.red,
            status: "rejected"
          ),
          (
            label: "Left",
            value: spotsLeft,
            color: Colors.deepPurple,
            status: "all"
          ),
        ];

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            mainAxisExtent: 34,
          ),
          itemBuilder: (context, index) {
            final stat = stats[index];
            return buildStatTile(
              label: stat.label,
              value: stat.value,
              color: stat.color,
              onTap: stat.label == "Left"
                  ? null
                  : () => openApplicationsFor(job, stat.status),
            );
          },
        );
      },
    );
  }

  Future<void> deleteJob(BuildContext context, Job job) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete vacancy"),
        content: Text("Delete \"${job.displayTitle}\"?"),
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

    await FirebaseFirestore.instance.collection("jobs").doc(job.id).delete();

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Vacancy deleted")),
    );
  }

  Widget buildJobCard(
    BuildContext context,
    Job job,
    Map<String, dynamic>? employerData,
    String ownerId,
    Set<String> ownerJobIds,
  ) {
    if (employerData == null &&
        job.ownerId.isNotEmpty &&
        job.ownerId != "unknown") {
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection("users")
            .doc(job.ownerId)
            .get(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() as Map<String, dynamic>?;
          return buildJobCardContent(context, job, data, ownerId, ownerJobIds);
        },
      );
    }

    return buildJobCardContent(
        context, job, employerData, ownerId, ownerJobIds);
  }

  Widget buildJobCardContent(
    BuildContext context,
    Job job,
    Map<String, dynamic>? employerData,
    String ownerId,
    Set<String> ownerJobIds,
  ) {
    final isOwnJob = ownerJobIds.contains(job.id) || job.ownerId == ownerId;
    final isClosed = job.isClosed;
    final companyName = companyNameFor(job, employerData);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobDetailScreen(job: job),
          ),
        );
      },
      child: AppCard(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.all(16),
        dimmed: isOwnJob && isClosed,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildCompanyAvatar(job, employerData),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isOwnJob) ...[
                        buildStatusBadge(job),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        job.displayTitle,
                        style: const TextStyle(
                          fontSize: 20,
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (companyName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          companyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        [
                          if (job.shouldShowTrade) job.trade,
                          "${job.city} ${job.postcode}".trim(),
                        ].where((item) => item.isNotEmpty).join(" • "),
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isOwnJob)
                  StroykaPopupMenuButton<String>(
                    actions: [
                      if (job.moderationStatus == "approved")
                        StroykaMenuAction<String>(
                          value: "toggle",
                          label: isClosed ? "Make active" : "Make inactive",
                          icon:
                              isClosed ? Icons.play_circle : Icons.pause_circle,
                        ),
                      const StroykaMenuAction<String>(
                        value: "delete",
                        label: "Delete vacancy",
                        icon: Icons.delete_outline,
                        danger: true,
                      ),
                    ],
                    onSelected: (value) {
                      if (value == "delete") {
                        deleteJob(context, job);
                      } else if (value == "toggle") {
                        setJobActive(job, isClosed);
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: buildJobChips(job),
            ),
          ],
        ),
      ),
    );
  }

  List<Job> mergeEmployerVisibleJobs({
    required List<Job> publicJobs,
    required List<Job> ownerJobs,
  }) {
    final byId = <String, Job>{};

    for (final job in publicJobs) {
      byId[job.id] = job;
    }
    for (final job in ownerJobs) {
      byId[job.id] = job;
    }

    final jobs = byId.values.toList();
    jobs.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return jobs;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("User not logged in")),
      );
    }

    final ownerId = user.uid;

    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          width: 220,
          child: JobScopeToggle(
            showOnlyMyJobs: showOnlyMyJobs,
            onChanged: (value) => setState(() {
              showOnlyMyJobs = value;
              currentPage = 1;
            }),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: StroykaScreenBody(
        child: StreamBuilder<List<Job>>(
          stream: ownerJobsStream(ownerId),
          builder: (context, ownerSnapshot) {
            if (ownerSnapshot.connectionState == ConnectionState.waiting &&
                !ownerSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final ownerJobs = ownerSnapshot.data ?? const <Job>[];
            final ownerJobIds = ownerJobs.map((job) => job.id).toSet();

            return StreamBuilder<List<Job>>(
              stream: publicJobsStream,
              builder: (context, publicSnapshot) {
                final publicJobs = publicSnapshot.data ?? const <Job>[];
                final jobs = mergeEmployerVisibleJobs(
                  publicJobs: publicJobs,
                  ownerJobs: ownerJobs,
                );
                final visibleJobs = showOnlyMyJobs
                    ? jobs.where((job) => ownerJobIds.contains(job.id)).toList()
                    : jobs;

                final filteredJobs = visibleJobs.where((job) {
                  return jobMatchesSearch(
                    job,
                    roles: selectedRoles,
                    query: searchQuery,
                    filters: searchFilters,
                    originJobs: visibleJobs,
                  );
                }).toList();
                debugPrint(
                  "MY JOBS RAW COUNT=${ownerJobs.length} "
                  "MY JOBS AFTER OWNER FILTER=${visibleJobs.length} "
                  "MY JOBS AFTER STATUS FILTER=${visibleJobs.length} "
                  "MY JOBS FINAL COUNT=${filteredJobs.length}",
                );
                if (showOnlyMyJobs) {
                  final finalIds = filteredJobs.map((job) => job.id).toSet();
                  for (final job in ownerJobs) {
                    if (!finalIds.contains(job.id)) {
                      debugPrint(
                        "FILTERED OUT OWN JOB: "
                        "jobId=${job.id} status=${job.status} "
                        "active=${!job.isClosed} deleted=${job.status.toLowerCase() == "deleted"} "
                        "reason=search_or_scope_filter",
                      );
                    }
                  }
                }

                final totalPages = (filteredJobs.length / _jobsPerPage).ceil();
                final safePage = totalPages == 0
                    ? 1
                    : currentPage.clamp(1, totalPages).toInt();
                final pageStart = (safePage - 1) * _jobsPerPage;
                final pageJobs =
                    filteredJobs.skip(pageStart).take(_jobsPerPage).toList();
                final emptyMessage = showOnlyMyJobs
                    ? "You have not created any vacancies yet."
                    : "No active vacancies available.";

                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection("users")
                      .doc(ownerId)
                      .snapshots(),
                  builder: (context, employerSnapshot) {
                    final employerData =
                        employerSnapshot.data?.data() as Map<String, dynamic>?;

                    return Column(
                      children: [
                        SmartJobSearchField(
                          selectedRoles: selectedRoles,
                          query: searchQuery,
                          filters: searchFilters,
                          jobs: jobs,
                          hintText: "Search jobs",
                          showJobScopeToggle: false,
                          showJobScopeToggleInField: false,
                          showOnlyMyJobs: showOnlyMyJobs,
                          currentUserId: ownerId,
                          onChanged: (value) {
                            setState(() {
                              selectedRoles = value.roles;
                              searchQuery = value.query;
                              searchFilters = value.filters;
                              showOnlyMyJobs = value.showOnlyMyJobs;
                              currentPage = 1;
                            });
                          },
                        ),
                        Expanded(
                          child: pageJobs.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      emptyMessage,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.ink,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: pageJobs.length,
                                  itemBuilder: (context, index) {
                                    return buildJobCard(
                                      context,
                                      pageJobs[index],
                                      ownerJobIds.contains(pageJobs[index].id)
                                          ? employerData
                                          : null,
                                      ownerId,
                                      ownerJobIds,
                                    );
                                  },
                                ),
                        ),
                        JobPagination(
                          currentPage: safePage,
                          totalItems: filteredJobs.length,
                          itemsPerPage: _jobsPerPage,
                          onPageChanged: (page) {
                            setState(() => currentPage = page);
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
