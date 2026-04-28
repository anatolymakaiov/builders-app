import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:test_app/services/job_alert_service.dart';
import 'package:test_app/services/job_repository.dart';
import '../models/job.dart';
import 'job_details_screen.dart';
import 'filter_sheet.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

enum SortType {
  nearest,
  highestPay,
  newest,
}

class JobListScreen extends StatefulWidget {
  const JobListScreen({super.key});

  @override
  State<JobListScreen> createState() => _JobListScreenState();
}

class _JobListScreenState extends State<JobListScreen> {
  final jobRepository = JobRepository();
  final jobAlertService = JobAlertService();

  double? userLat;
  double? userLng;

  SortType sortType = SortType.nearest;

  FilterResult filters = FilterResult(
    trade: "All",
    jobType: "All",
    distance: 50,
  );

  final searchController = TextEditingController();
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    getUserLocation();
  }

  Future<void> getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      userLat = position.latitude;
      userLng = position.longitude;
    });
  }

  double calculateDistance(double lat, double lng) {
    if (userLat == null || userLng == null) {
      return double.infinity;
    }

    final meters = Geolocator.distanceBetween(
      userLat!,
      userLng!,
      lat,
      lng,
    );

    return meters / 1609.34;
  }

  Future<void> openFilters() async {
    final result = await showModalBottomSheet<FilterResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FilterSheet(current: filters),
    );

    if (result != null) {
      setState(() {
        filters = result;
      });
    }
  }

  Future<void> saveJobAlert() async {
    final alertFilters = await showModalBottomSheet<FilterResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FilterSheet(
        current: filters,
        title: "Job subscription",
        actionLabel: "Subscribe",
        showDistance: true,
      ),
    );

    if (alertFilters == null) return;
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please log in first")),
      );
      return;
    }

    if (userLat == null || userLng == null) {
      await getUserLocation();
    }

    if (userLat == null || userLng == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Turn on location to subscribe to nearby jobs"),
        ),
      );
      return;
    }

    await jobAlertService.saveWorkerAlert(
      userId: user.uid,
      trade: alertFilters.trade,
      jobType: alertFilters.jobType,
      distance: alertFilters.distance,
      lat: userLat!,
      lng: userLng!,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Job alert saved")),
    );
  }

  String sortLabel() {
    switch (sortType) {
      case SortType.nearest:
        return "Nearest";
      case SortType.highestPay:
        return "Highest pay";
      case SortType.newest:
        return "Newest";
    }
  }

  String jobTypeLabel(String jobType) {
    switch (jobType) {
      case "hourly":
        return "Daywork";
      case "price":
        return "Price";
      case "negotiable":
        return "Negotiable";
      default:
        return "Job";
    }
  }

  Future<void> toggleSavedJob(Job job, bool isSaved) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await jobRepository.toggleSaveJob(user.uid, job.id, isSaved);
  }

  Widget metaChip({
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget buildSortButton(SortType type, String label, IconData icon) {
    final selected = sortType == type;

    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () {
          setState(() {
            sortType = type;
          });
        },
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? AppColors.green : Colors.white,
          foregroundColor: selected ? Colors.white : AppColors.ink,
          side: BorderSide(
            color: selected ? AppColors.green : Colors.grey.shade300,
          ),
        ),
      ),
    );
  }

  Widget buildJobCard(Job job, bool isSaved) {
    final distance = calculateDistance(job.lat, job.lng);
    final duration =
        job.duration.trim().isEmpty ? "Duration not set" : job.duration.trim();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JobDetailScreen(job: job),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// 🔥 TRADE (только если есть)
                            if (job.trade.isNotEmpty)
                              Text(
                                job.trade,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),

                            if (job.trade.isNotEmpty) const SizedBox(height: 4),

                            /// 🔥 TITLE (главный)
                            Text(
                              job.title,
                              style: const TextStyle(
                                fontSize: 20,
                                color: AppColors.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: isSaved ? "Remove from saved" : "Save job",
                        icon: Icon(
                          isSaved ? Icons.favorite : Icons.favorite_border,
                          color: isSaved ? Colors.red : Colors.grey,
                        ),
                        onPressed: () => toggleSavedJob(job, isSaved),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  /// 🔥 EMPLOYER
                  if (job.ownerId.isNotEmpty && job.ownerId != "unknown")
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection("users")
                          .doc(job.ownerId)
                          .get(),
                      builder: (context, snapshot) {
                        String name = "Company";
                        String? photo;

                        if (snapshot.hasData && snapshot.data!.exists) {
                          final data =
                              snapshot.data!.data() as Map<String, dynamic>;

                          name =
                              data["companyName"] ?? data["name"] ?? "Company";

                          photo = data["photo"];
                        }

                        return Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage:
                                  photo != null ? NetworkImage(photo) : null,
                              child: photo == null
                                  ? const Icon(Icons.business, size: 16)
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          ],
                        );
                      },
                    ),

                  const SizedBox(height: 8),

                  /// 📍 LOCATION
                  Text(
                    "${job.city} ${job.postcode}",
                    style: const TextStyle(color: Colors.grey),
                  ),

                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      metaChip(
                        label: jobTypeLabel(job.jobType),
                      ),
                      metaChip(
                        label: duration,
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  /// 💰 RATE + 📏 DISTANCE
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          job.rateText,
                          style: const TextStyle(
                            color: AppColors.greenDark,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (distance != double.infinity)
                        Text(
                          "${distance.toStringAsFixed(1)} mi",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Jobs"),
        actions: [
          IconButton(
            tooltip: "Subscribe to jobs",
            icon: const Icon(Icons.notifications_active),
            onPressed: saveJobAlert,
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt),
            onPressed: openFilters,
          ),
        ],
      ),
      body: StroykaScreenBody(
        child: Column(
          children: [
            /// SEARCH
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: "Search jobs",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    searchQuery = value.toLowerCase();
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  buildSortButton(
                    SortType.nearest,
                    "Distance",
                    Icons.near_me_outlined,
                  ),
                  const SizedBox(width: 8),
                  buildSortButton(
                    SortType.highestPay,
                    "Pay",
                    Icons.payments_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            Expanded(
              child: StreamBuilder<Set<String>>(
                stream: userId == null
                    ? Stream.value(<String>{})
                    : jobRepository.getSavedJobsStream(userId),
                builder: (context, savedSnapshot) {
                  final savedJobIds = savedSnapshot.data ?? <String>{};

                  return StreamBuilder<List<Job>>(
                    stream: jobRepository.getJobs(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final jobs = snapshot.data!;

                      final filteredJobs = jobs.where((job) {
                        if (searchQuery.isNotEmpty &&
                            !job.title.toLowerCase().contains(searchQuery) &&
                            !job.trade.toLowerCase().contains(searchQuery)) {
                          return false;
                        }

                        if (filters.trade != "All" &&
                            job.trade.toLowerCase() !=
                                filters.trade.toLowerCase()) {
                          return false;
                        }

                        if (filters.jobType != "All" &&
                            job.jobType.toLowerCase() !=
                                filters.jobType.toLowerCase()) {
                          return false;
                        }

                        return true;
                      }).toList();

                      /// SORT
                      if (sortType == SortType.nearest) {
                        filteredJobs.sort((a, b) =>
                            calculateDistance(a.lat, a.lng)
                                .compareTo(calculateDistance(b.lat, b.lng)));
                      }

                      if (sortType == SortType.highestPay) {
                        filteredJobs.sort((a, b) => b.rate.compareTo(a.rate));
                      }

                      if (sortType == SortType.newest) {
                        filteredJobs.sort((a, b) =>
                            (b.createdAt ?? DateTime.now())
                                .compareTo(a.createdAt ?? DateTime.now()));
                      }

                      return ListView.builder(
                        itemCount: filteredJobs.length,
                        itemBuilder: (context, index) {
                          final job = filteredJobs[index];

                          return buildJobCard(
                            job,
                            savedJobIds.contains(job.id),
                          );
                        },
                      );
                    },
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
