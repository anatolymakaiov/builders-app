import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/safe_profile_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'application_details_screen.dart';
import '../services/application_activity_service.dart';
import '../services/application_status_utils.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class EmployerApplicationsScreen extends StatefulWidget {
  final String? initialJobId;
  final String initialStatus;

  const EmployerApplicationsScreen({
    super.key,
    this.initialJobId,
    this.initialStatus = "all",
  });

  @override
  State<EmployerApplicationsScreen> createState() =>
      _EmployerApplicationsScreenState();
}

class _EmployerApplicationsScreenState
    extends State<EmployerApplicationsScreen> {
  String selectedStatus = "all";
  Set<String> trades = {"all"};
  Set<String> sites = {"all"};
  String selectedTrade = "all";
  String selectedSite = "all";
  bool oldestFirst = false;
  int refreshTick = 0;

  Future<void> openFilters() async {
    var status = selectedStatus;
    var trade = trades.contains(selectedTrade) ? selectedTrade : "all";
    var site = sites.contains(selectedSite) ? selectedSite : "all";
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Filter applications',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('status-$status'),
                  initialValue: status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    ApplicationStatusUtils.allFilter,
                    ApplicationStatusUtils.reviewFilter,
                    ApplicationStatusUtils.negotiationFilter,
                    ApplicationStatusUtils.offerFilter,
                    ApplicationStatusUtils.rejectedFilter,
                    ApplicationStatusUtils.hiredFilter,
                    ApplicationStatusUtils.withdrawnFilter,
                  ]
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(value == 'all'
                                ? 'All'
                                : ApplicationStatusUtils.getStatusDisplayLabel(
                                    value, 'employer')),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      updateSheet(() => status = value ?? 'all'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('site-$site'),
                  initialValue: site,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Site / Location'),
                  items: sites
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(value == 'all' ? 'All' : value),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      updateSheet(() => site = value ?? 'all'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('trade-$trade'),
                  initialValue: trade,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Trade'),
                  items: trades
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(value == 'all' ? 'All' : value),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      updateSheet(() => trade = value ?? 'all'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  TextButton(
                    onPressed: () => updateSheet(() {
                      status = 'all';
                      trade = 'all';
                      site = 'all';
                    }),
                    child: const Text('Clear filters'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        selectedStatus = status;
                        selectedTrade = trade;
                        selectedSite = site;
                      });
                      Navigator.pop(sheetContext);
                    },
                    child: const Text('Apply'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    selectedStatus = widget.initialStatus == "all"
        ? "all"
        : ApplicationStatusUtils.filterForStatus(widget.initialStatus);
  }

  Future<void> refreshApplications() async {
    setState(() => refreshTick++);
  }

  Color getStatusColor(String status) {
    switch (ApplicationStatusUtils.normalizeStatus(status)) {
      case "accepted":
      case "offer_accepted":
        return Colors.green;
      case "rejected":
        return Colors.red;
      case "negotiation":
        return Colors.purple;
      case "offer_sent":
        return AppColors.greenDark;
      case "offer_withdrawn":
      case "offer_rejected":
        return Colors.orange;
      default:
        return AppColors.ink;
    }
  }

  String canonicalStatus(dynamic value) {
    return ApplicationStatusUtils.normalizeStatus(value);
  }

  String statusLabel(String status) {
    return ApplicationStatusUtils.getStatusDisplayLabel(status, "employer")
        .toUpperCase();
  }

  Widget buildApplicantAvatar(Map<String, dynamic> data) {
    final type = data["type"] ?? "single";

    if (type == "team") {
      final teamId = data["teamId"];
      if (teamId == null) {
        return const StroykaAvatar(
          fallbackIcon: Icons.groups,
          size: 64,
        );
      }

      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection("teams")
            .doc(teamId)
            .snapshots(),
        builder: (context, snapshot) {
          final team = snapshot.data?.data() as Map<String, dynamic>?;
          final avatar = team?["avatarUrl"] ?? team?["photo"] ?? team?["logo"];

          return StroykaAvatar(
            imageUrl: avatar?.toString(),
            fallbackIcon: Icons.groups,
            size: 64,
          );
        },
      );
    }

    final workerId = data["workerId"] ?? data["userId"];
    if (workerId == null) {
      return const StroykaAvatar(
        fallbackIcon: Icons.person,
        size: 64,
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: SafeProfileService().profile(workerId).snapshots(),
      builder: (context, snapshot) {
        final user = snapshot.data?.data() as Map<String, dynamic>?;
        final photo = user?["photo"] ?? user?["avatarUrl"];

        return StroykaAvatar(
          imageUrl: photo?.toString(),
          fallbackIcon: Icons.person,
          size: 64,
        );
      },
    );
  }

  Future<void> updateStatus(String id, String status) async {
    final doc = await FirebaseFirestore.instance
        .collection("applications")
        .doc(id)
        .get();
    final data = doc.data() ?? {};

    await ApplicationActivityService.updateStatus(
      applicationId: id,
      status: status,
      unreadFor: ApplicationActivityService.workerRecipients(data),
    );
  }

  Stream<List<QueryDocumentSnapshot>> employerApplicationsStream(
    String employerId,
  ) {
    final controller = StreamController<List<QueryDocumentSnapshot>>();
    final applicationsRef =
        FirebaseFirestore.instance.collection("applications");

    List<QueryDocumentSnapshot>? employerDocs;
    List<QueryDocumentSnapshot>? ownerDocs;
    late final StreamSubscription employerSub;
    late final StreamSubscription ownerSub;

    void emit() {
      final byEmployer = employerDocs;
      final byOwner = ownerDocs;
      if (byEmployer == null || byOwner == null || controller.isClosed) return;

      final seen = <String>{};
      final merged = <QueryDocumentSnapshot>[];
      for (final doc in [...byEmployer, ...byOwner]) {
        if (seen.add(doc.id)) merged.add(doc);
      }

      merged.sort(
        (a, b) => ApplicationActivityService.compareForUser(a, b, employerId),
      );
      controller.add(merged);
    }

    employerSub = applicationsRef
        .where("employerId", isEqualTo: employerId)
        .snapshots()
        .listen((snapshot) {
      employerDocs = snapshot.docs;
      emit();
    }, onError: controller.addError);

    ownerSub = applicationsRef
        .where("ownerId", isEqualTo: employerId)
        .snapshots()
        .listen((snapshot) {
      ownerDocs = snapshot.docs;
      emit();
    }, onError: (error) {
      debugPrint("OWNER APPLICATIONS STREAM SKIPPED: $error");
      ownerDocs = const [];
      emit();
    });

    controller.onCancel = () async {
      await employerSub.cancel();
      await ownerSub.cancel();
    };

    return controller.stream;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
      );
    }

    final employerId = user.uid;
    final activeFilterCount = [selectedStatus, selectedTrade, selectedSite]
        .where((value) => value != 'all')
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Applications"),
        actions: [
          IconButton(
            tooltip: 'Filter applications',
            onPressed: openFilters,
            icon: Badge(
              isLabelVisible: activeFilterCount > 0,
              smallSize: 7,
              child: const Icon(Icons.filter_list),
            ),
          ),
          PopupMenuButton<bool>(
            tooltip: 'Sort applications',
            icon: const Icon(Icons.sort),
            onSelected: (value) => setState(() => oldestFirst = value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: false, child: Text('Newest first')),
              PopupMenuItem(value: true, child: Text('Oldest first')),
            ],
          ),
        ],
      ),
      body: StroykaScreenBody(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<QueryDocumentSnapshot>>(
                key: ValueKey("employer-applications-$refreshTick"),
                stream: employerApplicationsStream(employerId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allApps = snapshot.data!;

                  trades = {"all"};
                  sites = {"all"};

                  for (var doc in allApps) {
                    final data = doc.data() as Map<String, dynamic>;

                    final trade = (data["jobTrade"] ?? "").toString().trim();
                    final site = (data["jobSite"] ?? "").toString().trim();

                    if (trade.isNotEmpty) {
                      trades.add(trade);
                    }

                    if (site.isNotEmpty) {
                      sites.add(site);
                    }
                  }
                  final apps = allApps.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;

                    final status = canonicalStatus(data["status"]);
                    final trade = (data["jobTrade"] ?? "").toString().trim();
                    final site = (data["jobSite"] ?? "").toString().trim();

                    if (widget.initialJobId != null &&
                        data["jobId"]?.toString() != widget.initialJobId) {
                      return false;
                    }

                    if (!ApplicationStatusUtils.isStatusInFilter(
                      status,
                      selectedStatus,
                    )) {
                      return false;
                    }

                    if (selectedTrade != "all" && trade != selectedTrade) {
                      return false;
                    }

                    if (selectedSite != "all" && site != selectedSite) {
                      return false;
                    }

                    return true;
                  }).toList();

                  apps.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final newest = ApplicationStatusUtils.compareNewestFirst(
                      aData,
                      bData,
                    );
                    return oldestFirst ? -newest : newest;
                  });

                  if (apps.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: refreshApplications,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 220),
                          Center(child: Text("No applications yet")),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: refreshApplications,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: apps.length,
                      itemBuilder: (context, index) {
                        final doc = apps[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final isUnread = ApplicationActivityService.isUnreadFor(
                          data,
                          employerId,
                        );

                        final type = data["type"] ?? "single";
                        final workerName = data["workerName"] ?? "Worker";
                        final members =
                            List<String>.from(data["members"] ?? []);
                        final jobTitle = data["jobTitle"] ?? "Job";
                        final siteName = (data["jobSite"] ?? data["site"] ?? "")
                            .toString()
                            .trim();
                        final status = canonicalStatus(data["status"]);
                        final Timestamp? createdAt = data["createdAt"];

                        final dateText = createdAt != null
                            ? DateTime.fromMillisecondsSinceEpoch(
                                    createdAt.millisecondsSinceEpoch)
                                .toString()
                                .substring(0, 16)
                            : "";

                        return GestureDetector(
                          onTap: () async {
                            await ApplicationActivityService.markRead(
                              doc.id,
                              employerId,
                            );
                            if (data["viewedByEmployer"] != true) {
                              await ApplicationActivityService
                                  .markViewedByEmployer(doc.id);
                            }
                            if (!context.mounted) return;

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ApplicationDetailsScreen(
                                  applicationId: doc.id,
                                  data: data,
                                ),
                              ),
                            );
                          },
                          child: AppCard(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            padding: const EdgeInsets.all(16),
                            dimmed: isUnread,
                            child: Stack(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (isUnread)
                                          Container(
                                            width: 10,
                                            height: 10,
                                            margin:
                                                const EdgeInsets.only(right: 8),
                                            decoration: const BoxDecoration(
                                              color: AppColors.green,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        buildApplicantAvatar(data),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: AppChip.status(
                                                  statusLabel(status),
                                                  color: getStatusColor(status),
                                                ),
                                              ),
                                              const SizedBox(height: 7),
                                              Text(
                                                type == "team"
                                                    ? "Team application"
                                                    : workerName,
                                                style: TextStyle(
                                                  color: AppColors.ink,
                                                  fontWeight: isUnread
                                                      ? FontWeight.w900
                                                      : FontWeight.w800,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              if (type == "team")
                                                Text(
                                                  "${members.length} members",
                                                  style: const TextStyle(
                                                      color: Colors.grey),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(jobTitle),
                                    if (dateText.isNotEmpty)
                                      Text(
                                        dateText,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                  ],
                                ),
                                if (siteName.isNotEmpty)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 132),
                                      child: Text(
                                        "Site: $siteName",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
