import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:test_app/services/job_repository.dart';
import '../models/job.dart';
import 'map_screen.dart';
import 'job_details_screen.dart';
import 'post_job_screen.dart';
import 'filter_sheet.dart';

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

  double? userLat;
  double? userLng;

  SortType sortType = SortType.nearest;

  FilterResult filters = FilterResult(
    trade: "All",
    minRate: 0,
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

  Future<void> openPostJob() async {

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostJobScreen(
          onJobCreated: (_) {},
        ),
      ),
    );

    if (mounted) setState(() {});
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

  Widget buildJobCard(Job job) {

    final distance = calculateDistance(job.lat, job.lng);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
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

            if (job.photos != null && job.photos!.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
                child: Image.network(
                  job.photos!.first,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Text(
                    job.trade,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(job.title),

                  const SizedBox(height: 10),

                  Row(
                    children: [

                      if (job.companyLogo != null)
                        CircleAvatar(
                          radius: 12,
                          backgroundImage: NetworkImage(job.companyLogo!),
                        )
                      else
                        const CircleAvatar(
                          radius: 12,
                          child: Icon(Icons.business, size: 14),
                        ),

                      const SizedBox(width: 8),

                      Expanded(
                        child: Text(
                          job.companyName ?? "Construction company",
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )

                    ],
                  ),

                  const SizedBox(height: 6),

                  Text("${job.city} ${job.postcode}"),

                  const SizedBox(height: 10),

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
                            color: Colors.green,
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

    return Scaffold(

      appBar: AppBar(
        title: const Text("Jobs"),
        actions: [

          IconButton(
            icon: const Icon(Icons.filter_alt),
            onPressed: openFilters,
          ),

          IconButton(
            icon: const Icon(Icons.map),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MapScreen(),
                ),
              );
            },
          ),

          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: getUserLocation,
          )

        ],
      ),

      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: openPostJob,
      ),

      body: Column(
        children: [

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

          Expanded(
            child: StreamBuilder<List<Job>>(
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
                      job.trade.toLowerCase() != filters.trade.toLowerCase()) {
                    return false;
                  }

                  if (job.rate < filters.minRate) {
                    return false;
                  }

                  final distance = calculateDistance(job.lat, job.lng);

                  if (distance != double.infinity &&
                      distance > filters.distance) {
                    return false;
                  }

                  return true;

                }).toList();

                if (sortType == SortType.nearest) {
                  filteredJobs.sort((a, b) {
                    final distA = calculateDistance(a.lat, a.lng);
                    final distB = calculateDistance(b.lat, b.lng);
                    return distA.compareTo(distB);
                  });
                }

                if (sortType == SortType.highestPay) {
                  filteredJobs.sort((a, b) => b.rate.compareTo(a.rate));
                }

                if (sortType == SortType.newest) {
                  filteredJobs.sort((a, b) =>
                      (b.createdAt ?? DateTime.now())
                          .compareTo(a.createdAt ?? DateTime.now()));
                }

                return Column(
                  children: [

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [

                          Text(
                            "${filteredJobs.length} jobs found",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          PopupMenuButton<SortType>(
                            onSelected: (value) {
                              setState(() {
                                sortType = value;
                              });
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: SortType.nearest,
                                child: Text("Nearest"),
                              ),
                              const PopupMenuItem(
                                value: SortType.highestPay,
                                child: Text("Highest pay"),
                              ),
                              const PopupMenuItem(
                                value: SortType.newest,
                                child: Text("Newest"),
                              ),
                            ],
                            child: Row(
                              children: [
                                const Icon(Icons.sort),
                                const SizedBox(width: 4),
                                Text(sortLabel()),
                              ],
                            ),
                          )

                        ],
                      ),
                    ),

                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredJobs.length,
                        itemBuilder: (context, index) {
                          final job = filteredJobs[index];
                          return buildJobCard(job);
                        },
                      ),
                    )

                  ],
                );
              },
            ),
          ),

        ],
      ),
    );
  }
}