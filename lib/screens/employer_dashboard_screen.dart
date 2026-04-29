import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/job.dart';
import 'employer_applications_screen.dart';
import 'job_details_screen.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class EmployerDashboardScreen extends StatefulWidget {
  const EmployerDashboardScreen({super.key});

  @override
  State<EmployerDashboardScreen> createState() =>
      _EmployerDashboardScreenState();
}

class _EmployerDashboardScreenState extends State<EmployerDashboardScreen> {
  String selectedTrade = "All";
  String selectedSite = "All";

  Widget buildCompanyAvatar(Job job, Map<String, dynamic>? employerData) {
    final avatarUrl = job.companyLogo ??
        employerData?["companyLogo"] ??
        employerData?["photo"] ??
        employerData?["avatarUrl"];
    final name = job.companyName.isNotEmpty
        ? job.companyName
        : (employerData?["companyName"] ?? employerData?["name"] ?? "Company")
            .toString();

    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.green.shade100,
      backgroundImage: avatarUrl == null || avatarUrl.toString().isEmpty
          ? null
          : NetworkImage(avatarUrl.toString()),
      child: avatarUrl == null || avatarUrl.toString().isEmpty
          ? Text(
              name.characters.first.toUpperCase(),
              style: TextStyle(
                color: Colors.green.shade900,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }

  Widget buildMetaChip({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color ?? Colors.grey.shade700),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color ?? Colors.grey.shade800,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
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

    if (job.weeklyHours.isNotEmpty) {
      chips.add(
        buildMetaChip(
          icon: Icons.schedule,
          label: "${job.weeklyHours} hrs/week",
          color: Colors.deepPurple,
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
    await FirebaseFirestore.instance.collection("jobs").doc(job.id).set({
      "status": active ? "active" : "closed",
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

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
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
    final isClosed = job.isClosed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isClosed ? Colors.grey.shade700 : AppColors.green,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isClosed ? "INACTIVE" : "ACTIVE",
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
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
  ) {
    final isClosed = job.isClosed;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobDetailScreen(job: job),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isClosed ? Colors.grey.shade100 : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isClosed ? Colors.grey.shade400 : AppColors.surface,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
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
                      buildStatusBadge(job),
                      const SizedBox(height: 6),
                      Text(
                        job.displayTitle,
                        style: const TextStyle(
                          fontSize: 20,
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == "delete") {
                      deleteJob(context, job);
                    } else if (value == "toggle") {
                      setJobActive(job, isClosed);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: "toggle",
                      child: Row(
                        children: [
                          Icon(
                            isClosed ? Icons.play_circle : Icons.pause_circle,
                            color:
                                isClosed ? AppColors.greenDark : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(isClosed ? "Make active" : "Make inactive"),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: "delete",
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: Colors.red),
                          SizedBox(width: 8),
                          Text("Delete vacancy"),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: buildJobChips(job),
            ),
            const SizedBox(height: 12),
            buildApplicationStats(job),
          ],
        ),
      ),
    );
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
        title: const Text("My Jobs"),
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
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("jobs")
              .where("ownerId", isEqualTo: ownerId)
              .orderBy("createdAt", descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData) {
              return const Center(child: Text("Error loading jobs"));
            }

            final jobs = snapshot.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return Job.fromFirestore(doc.id, data);
            }).toList();

            final tradeSet = <String>{};
            final siteSet = <String>{};

            for (var job in jobs) {
              if (job.trade.isNotEmpty) tradeSet.add(job.trade);
              if (job.site.isNotEmpty) siteSet.add(job.site);
            }

            final tradeList = ["All", ...tradeSet];
            final siteList = ["All", ...siteSet];

            final filteredJobs = jobs.where((job) {
              if (selectedTrade != "All" &&
                  job.trade.toLowerCase().trim() !=
                      selectedTrade.toLowerCase().trim()) {
                return false;
              }

              if (selectedSite != "All" &&
                  job.site.toLowerCase().trim() !=
                      selectedSite.toLowerCase().trim()) {
                return false;
              }

              return true;
            }).toList();

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection("users")
                  .doc(ownerId)
                  .get(),
              builder: (context, employerSnapshot) {
                final employerData =
                    employerSnapshot.data?.data() as Map<String, dynamic>?;

                return Column(
                  children: [
                    buildFilterPanel(tradeList, siteList),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredJobs.length,
                        itemBuilder: (context, index) {
                          return buildJobCard(
                            context,
                            filteredJobs[index],
                            employerData,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
