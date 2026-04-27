import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/job.dart';
import 'job_details_screen.dart';
import '../services/job_repository.dart';
import '../theme/app_theme.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // ✅ FIX: убрали test_user_123
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  final MapController mapController = MapController();
  final ScrollController listController = ScrollController();
  final jobRepository = JobRepository();
  final DraggableScrollableController sheetController =
      DraggableScrollableController();

  Set<String> savedJobIds = {};

  double? userLat;
  double? userLng;
  String role = "worker";

  String? selectedJobId;
  Job? selectedJob;

  List<Job> allJobs = [];

  LatLngBounds? mapBounds;
  LatLngBounds? searchBounds;

  bool panelOpen = true;
  bool showSearchButton = false;

  String tradeFilter = "All";
  String sortBy = "distance";

  final trades = ["All", "Bricklayer", "Dryliner", "Painter", "Labourer"];

  @override
  void initState() {
    super.initState();
    loadRole();
    requestLocation();
    loadSavedJobs();

    listController.addListener(() {
      if (!listController.hasClients) return;

      final offset = listController.offset;

      int index = (offset / 170).round();

      if (index < 0 || index >= allJobs.length) return;

      final job = allJobs[index];

      mapController.move(
        LatLng(job.lat, job.lng),
        mapController.camera.zoom < 14 ? 14 : mapController.camera.zoom,
      );

      setState(() {
        selectedJobId = job.id;
      });
    });
  }

  bool get isEmployer => role == "employer";

  Future<void> loadRole() async {
    final userId = currentUserId;
    if (userId == null) return;

    final doc =
        await FirebaseFirestore.instance.collection("users").doc(userId).get();
    if (!doc.exists) return;

    if (!mounted) return;

    setState(() {
      role = doc.data()?["role"] == "employer" ? "employer" : "worker";
    });
  }

  // ✅ FIX: теперь берём реального пользователя
  Future<void> loadSavedJobs() async {
    final userId = currentUserId;
    if (userId == null || isEmployer) return;

    final ids = await jobRepository.getSavedJobs(userId);

    setState(() {
      savedJobIds = ids;
    });
  }

  Future<void> toggleSaveJob(String jobId) async {
    final userId = currentUserId;
    if (userId == null || isEmployer) return;

    final isSaved = savedJobIds.contains(jobId);

    await jobRepository.toggleSaveJob(userId, jobId, isSaved);

    setState(() {
      if (isSaved) {
        savedJobIds.remove(jobId);
      } else {
        savedJobIds.add(jobId);
      }
    });
  }

  // ✅ FIX: apply теперь тоже на реального юзера
  Future<void> applyToJob(Job job) async {
    final userId = currentUserId;
    if (userId == null || isEmployer) return;

    await jobRepository.applyToJob(job.id, userId);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Applied successfully")),
    );
  }

  Future<void> requestLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition();

    setState(() {
      userLat = position.latitude;
      userLng = position.longitude;
    });
  }

  double calculateDistance(double lat, double lng) {
    if (userLat == null || userLng == null) return double.infinity;

    final meters = Geolocator.distanceBetween(
      userLat!,
      userLng!,
      lat,
      lng,
    );

    return meters / 1609.34;
  }

  String rateText(Job job) {
    if (job.jobType == "negotiable") return "PRICE";
    if (job.jobType == "price") return "£${job.rate.toInt()}";

    return "£${job.rate.toInt()}/h";
  }

  void scrollToJob(int index) {
    listController.animateTo(
      index * 170,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  List<Job> getVisibleJobs() {
    if (searchBounds == null) return allJobs;

    return allJobs.where((job) {
      final point = LatLng(job.lat, job.lng);
      return searchBounds!.contains(point);
    }).toList();
  }

  List<Job> applyFilters(List<Job> jobs) {
    List<Job> result = jobs;

    if (tradeFilter != "All") {
      result = result.where((job) {
        return job.trade.toLowerCase() == tradeFilter.toLowerCase();
      }).toList();
    }

    if (sortBy == "distance") {
      result.sort((a, b) {
        final d1 = calculateDistance(a.lat, a.lng);
        final d2 = calculateDistance(b.lat, b.lng);

        return d1.compareTo(d2);
      });
    }

    if (sortBy == "rate") {
      result.sort((a, b) => b.rate.compareTo(a.rate));
    }

    if (sortBy == "newest") {
      result.sort((a, b) {
        final aDate = a.createdAt ?? DateTime(2000);
        final bDate = b.createdAt ?? DateTime(2000);

        return bDate.compareTo(aDate);
      });
    }

    if (selectedJobId != null) {
      result.sort((a, b) {
        if (a.id == selectedJobId) return -1;
        if (b.id == selectedJobId) return 1;
        return 0;
      });
    }

    return result;
  }

  Marker buildUserMarker() {
    if (isEmployer) {
      return const Marker(
        point: LatLng(0, 0),
        width: 0,
        height: 0,
        child: SizedBox(),
      );
    }

    if (userLat == null || userLng == null) {
      return const Marker(
        point: LatLng(0, 0),
        width: 0,
        height: 0,
        child: SizedBox(),
      );
    }

    return Marker(
      width: 40,
      height: 40,
      point: LatLng(userLat!, userLng!),
      child: const Icon(
        Icons.my_location,
        size: 36,
        color: AppColors.green,
      ),
    );
  }

  Widget buildMarker(Job job) {
    final selected = job.id == selectedJobId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? AppColors.green : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Text(
        rateText(job),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: selected ? 13 : 12,
          color: selected ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  Widget buildMap(LatLng center, List<Marker> markers) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 10,
        minZoom: 3,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onPositionChanged: (position, hasGesture) {
          if (hasGesture && position.bounds != null) {
            mapBounds = position.bounds;

            if (!showSearchButton) {
              setState(() {
                showSearchButton = true;
              });
            }
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          userAgentPackageName: "builder.jobs.app",
        ),
        MarkerClusterLayerWidget(
          options: MarkerClusterLayerOptions(
            markers: markers,
            maxClusterRadius: 120,
            size: const Size(40, 40),
            onClusterTap: (cluster) {
              final zoom = mapController.camera.zoom;

              mapController.move(
                cluster.bounds.center,
                zoom + 2,
              );
            },
            builder: (context, cluster) {
              return Container(
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  cluster.length.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget buildBottomSheet(List<Job> jobs) {
    return DraggableScrollableSheet(
      controller: sheetController,
      initialChildSize: 0.2,
      minChildSize: 0.18,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    DropdownButton<String>(
                      value: tradeFilter,
                      items: trades.map((trade) {
                        return DropdownMenuItem(
                          value: trade,
                          child: Text(trade),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          tradeFilter = value!;
                        });
                      },
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: sortBy,
                      items: const [
                        DropdownMenuItem(
                            value: "distance", child: Text("Distance")),
                        DropdownMenuItem(value: "rate", child: Text("Pay")),
                        DropdownMenuItem(
                            value: "newest", child: Text("Newest")),
                      ],
                      onChanged: (value) {
                        setState(() {
                          sortBy = value!;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: jobs.length,
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedJobId = job.id;
                        });
                        mapController.move(LatLng(job.lat, job.lng), 16);
                      },
                      child: buildJobCard(job),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildJobCard(Job job) {
    final distance = calculateDistance(job.lat, job.lng);
    final selected = job.id == selectedJobId;

    return Container(
      decoration: BoxDecoration(
        color: selected ? AppColors.surfaceAlt : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              job.trade,
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              job.title,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            if (job.companyName.isNotEmpty) Text(job.companyName),
            Text("${job.city} ${job.postcode}"),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    rateText(job),
                    style: const TextStyle(
                      color: AppColors.greenDark,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    job.workFormatText,
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (distance != double.infinity)
                  Text("${distance.toStringAsFixed(1)} mi")
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () {
                    mapController.move(LatLng(job.lat, job.lng), 17);
                    setState(() {
                      selectedJobId = job.id;
                    });
                  },
                  child: const Text("Show on map"),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => JobDetailScreen(job: job),
                      ),
                    );
                  },
                  child: const Text("View", style: TextStyle(fontSize: 12)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Jobs Map")),
      body: StreamBuilder<List<Job>>(
        stream: jobRepository.getJobs(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          allJobs = snapshot.data!;

          List<Job> visibleJobs = getVisibleJobs();

          if (visibleJobs.isEmpty) {
            visibleJobs = allJobs;
          }

          visibleJobs = applyFilters(visibleJobs);

          final markers = <Marker>[];

          for (int i = 0; i < visibleJobs.length; i++) {
            final job = visibleJobs[i];

            markers.add(
              Marker(
                width: 80,
                height: 40,
                point: LatLng(job.lat, job.lng),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedJobId = job.id;
                      selectedJob = job;
                    });

                    mapController.move(
                      LatLng(job.lat, job.lng),
                      16,
                    );

                    Future.delayed(const Duration(milliseconds: 50), () {
                      if (sheetController.isAttached) {
                        sheetController.animateTo(
                          0.5,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    });

                    scrollToJob(i);
                  },
                  child: buildMarker(job),
                ),
              ),
            );
          }

          markers.add(buildUserMarker());

          final center = userLat != null
              ? LatLng(userLat!, userLng!)
              : const LatLng(53.4808, -2.2426);

          return Stack(
            children: [
              buildMap(center, markers),
              if (showSearchButton)
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          searchBounds = mapBounds;
                          showSearchButton = false;
                        });
                      },
                      child: const Text("Search this area"),
                    ),
                  ),
                ),
              buildBottomSheet(visibleJobs),
              if (!isEmployer)
                Positioned(
                  top: 10,
                  right: 0,
                  child: Row(
                    children: [
                      FloatingActionButton(
                        heroTag: "location",
                        mini: true,
                        onPressed: () {
                          if (userLat == null || userLng == null) return;
                          mapController.move(
                            LatLng(userLat!, userLng!),
                            15,
                          );
                        },
                        child: const Icon(Icons.my_location),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
