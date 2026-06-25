import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:test_app/services/job_alert_service.dart';
import 'package:test_app/services/job_repository.dart';
import '../models/job.dart';
import '../services/geocoding_service.dart';
import '../services/job_taxonomy_service.dart';
import 'filter_sheet.dart';
import '../theme/stroyka_background.dart';
import '../widgets/job_card.dart';
import '../widgets/job_pagination.dart';
import '../widgets/smart_job_search.dart';

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
  static const int _jobsPerPage = 10;

  final jobRepository = JobRepository();
  final jobAlertService = JobAlertService();
  final geocodingService = GeocodingService();

  double? userLat;
  double? userLng;

  SortType sortType = SortType.nearest;

  FilterResult filters = FilterResult(
    trade: "All",
    jobType: "All",
    distance: 50,
    postcode: "",
  );

  String searchQuery = "";
  List<ConstructionRole> selectedRoles = [];
  JobSearchFilters searchFilters = const JobSearchFilters();
  int currentPage = 1;
  int refreshTick = 0;
  bool showSavedOnly = false;

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

    if (!mounted) return;
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

    final postcode = alertFilters.postcode.trim();
    if (postcode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter a postcode for this job subscription"),
        ),
      );
      return;
    }

    final center = await geocodingService.lookupUKPostcode(postcode);
    if (center == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not find that postcode"),
        ),
      );
      return;
    }

    await jobAlertService.saveWorkerAlert(
      userId: user.uid,
      trade: alertFilters.trade,
      jobType: alertFilters.jobType,
      distance: alertFilters.distance,
      postcode: center.postcode,
      lat: center.lat,
      lng: center.lng,
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

  Future<void> toggleSavedJob(Job job, bool isSaved) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await jobRepository.toggleSaveJob(user.uid, job.id, isSaved);
  }

  Future<void> refreshJobs() async {
    await getUserLocation();
    if (!mounted) return;
    setState(() => refreshTick++);
  }

  Widget buildJobCard(Job job, bool isSaved) {
    final distance = calculateDistance(job.lat, job.lng);
    return JobCard(
      job: job,
      detailText: distance == double.infinity
          ? null
          : "${distance.toStringAsFixed(1)} miles away",
      trailingAction: IconButton(
        tooltip: isSaved ? "Remove from saved" : "Save job",
        icon: Icon(
          isSaved ? Icons.favorite : Icons.favorite_border,
          color: isSaved ? Colors.red : Colors.grey,
        ),
        onPressed: () => toggleSavedJob(job, isSaved),
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
            icon: const Icon(Icons.rss_feed),
            onPressed: saveJobAlert,
          ),
          IconButton(
            tooltip: showSavedOnly ? "Show all jobs" : "Show saved jobs",
            icon: Icon(
              showSavedOnly ? Icons.favorite : Icons.favorite_border,
              color: showSavedOnly ? Colors.red : null,
            ),
            onPressed: () {
              setState(() {
                showSavedOnly = !showSavedOnly;
                currentPage = 1;
              });
            },
          ),
        ],
      ),
      body: StroykaScreenBody(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<Set<String>>(
                stream: userId == null
                    ? Stream.value(<String>{})
                    : jobRepository.getSavedJobsStream(userId),
                builder: (context, savedSnapshot) {
                  final savedJobIds = savedSnapshot.data ?? <String>{};

                  return StreamBuilder<List<Job>>(
                    key: ValueKey("jobs-$refreshTick"),
                    stream: jobRepository.getJobs(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final jobs = snapshot.data!;
                      final sourceJobs = showSavedOnly
                          ? jobs
                              .where((job) => savedJobIds.contains(job.id))
                              .toList()
                          : jobs;

                      final searchField = SmartJobSearchField(
                        selectedRoles: selectedRoles,
                        query: searchQuery,
                        filters: searchFilters,
                        jobs: sourceJobs,
                        onChanged: (value) {
                          setState(() {
                            selectedRoles = value.roles;
                            searchQuery = value.query;
                            searchFilters = value.filters;
                            currentPage = 1;
                          });
                        },
                      );

                      final filteredJobs = sourceJobs.where((job) {
                        if (!jobMatchesSearch(
                          job,
                          roles: selectedRoles,
                          query: searchQuery,
                          filters: searchFilters,
                          originJobs: sourceJobs,
                        )) {
                          return false;
                        }

                        if (filters.trade != "All" &&
                            !JobTaxonomyService.matchesTradeFilter(
                              job,
                              filters.trade,
                            )) {
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

                      final totalPages =
                          (filteredJobs.length / _jobsPerPage).ceil();
                      final safePage = totalPages == 0
                          ? 1
                          : currentPage.clamp(1, totalPages).toInt();
                      final pageStart = (safePage - 1) * _jobsPerPage;
                      final pageJobs = filteredJobs
                          .skip(pageStart)
                          .take(_jobsPerPage)
                          .toList();

                      return Column(
                        children: [
                          searchField,
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: refreshJobs,
                              child: pageJobs.isEmpty
                                  ? ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      children: [
                                        SizedBox(
                                          height: MediaQuery.sizeOf(context)
                                                  .height *
                                              0.42,
                                          child: Center(
                                            child: Text(
                                              showSavedOnly
                                                  ? "No saved jobs yet."
                                                  : "No jobs found.",
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : ListView.builder(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      itemCount: pageJobs.length,
                                      itemBuilder: (context, index) {
                                        final job = pageJobs[index];

                                        return buildJobCard(
                                          job,
                                          savedJobIds.contains(job.id),
                                        );
                                      },
                                    ),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
