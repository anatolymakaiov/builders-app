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
import '../services/job_taxonomy_service.dart';
import '../theme/app_theme.dart';
import '../widgets/job_card.dart';
import '../widgets/quiet_tile_provider.dart';
import '../widgets/smart_job_search.dart';

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
  final tileProvider = QuietTileProvider();

  Set<String> savedJobIds = {};

  double? userLat;
  double? userLng;
  String role = "worker";

  String? selectedJobId;
  Job? selectedJob;

  List<Job> allJobs = [];
  List<Job> currentVisibleJobs = [];

  LatLngBounds? mapBounds;
  LatLngBounds? searchBounds;

  bool panelOpen = true;
  bool showSearchButton = false;
  bool showUserLocationMarker = false;

  List<ConstructionRole> selectedRoles = [];
  String searchQuery = "";

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

      if (index < 0 || index >= currentVisibleJobs.length) return;

      final job = currentVisibleJobs[index];

      mapController.move(
        LatLng(job.lat, job.lng),
        mapController.camera.zoom < 14 ? 14 : mapController.camera.zoom,
      );

      setState(() {
        selectedJobId = job.id;
      });
    });
  }

  @override
  void dispose() {
    listController.dispose();
    tileProvider.dispose();
    super.dispose();
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

    if (!mounted) return;
    setState(() {
      savedJobIds = ids;
    });
  }

  Future<void> refreshMapData() async {
    await loadRole();
    await requestLocation();
    await loadSavedJobs();
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

    if (!mounted) return;
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
    final jobType = job.jobType.trim().toLowerCase();

    if (jobType == "negotiable") return "Negotiable";
    if (jobType == "price") {
      return job.rate > 0 ? "£${job.rate.toInt()}" : job.workFormatText;
    }
    if (job.rate > 0) return "£${job.rate.toInt()}/h";

    final fallback = job.workFormatText.trim();
    return fallback.isNotEmpty ? fallback : "Rate TBC";
  }

  void scrollToJob(int index) {
    if (!mounted) return;
    if (index < 0 || index >= currentVisibleJobs.length) return;
    if (!listController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!listController.hasClients) return;
        scrollToJob(index);
      });
      return;
    }

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
    final result = jobs.where((job) {
      return jobMatchesSearch(
        job,
        roles: selectedRoles,
        query: searchQuery,
        filters: const JobSearchFilters(),
        originJobs: allJobs,
      );
    }).toList();

    if (selectedJobId != null) {
      result.sort((a, b) {
        if (a.id == selectedJobId) return -1;
        if (b.id == selectedJobId) return 1;
        return 0;
      });
    }

    return result;
  }

  Marker? buildUserMarker() {
    if (isEmployer || !showUserLocationMarker) return null;
    if (userLat == null || userLng == null) return null;

    return Marker(
      width: 122,
      height: 58,
      point: LatLng(userLat!, userLng!),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Text(
              "Your Location",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const Icon(
            Icons.my_location,
            size: 26,
            color: AppColors.green,
          ),
        ],
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: selected ? 13 : 12,
          color: selected ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  Widget buildMap(
    LatLng center,
    List<Marker> jobMarkers,
    Marker? userMarker,
  ) {
    debugPrint("mapTileReady=true");
    debugPrint(
      "EMPLOYER TILE LAYER BUILT "
      "tileUrlTemplate=https://tile.openstreetmap.org/{z}/{x}/{y}.png "
      "tileProvider=${tileProvider.runtimeType} "
      "tileLayerOpacity=1.0 "
      "flutterMapChildrenCount=${userMarker == null ? 2 : 3} "
      "mapCenter=${center.latitude.toStringAsFixed(4)},${center.longitude.toStringAsFixed(4)} "
      "mapZoom=10 "
      "topOverlayWidget=DraggableScrollableSheet",
    );
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 10,
        minZoom: 3,
        maxZoom: 18,
        backgroundColor: const Color(0xFFE7EEF3),
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
          fallbackUrl:
              "https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png",
          userAgentPackageName: "builder.jobs.app",
          tileProvider: tileProvider,
        ),
        MarkerClusterLayerWidget(
          options: MarkerClusterLayerOptions(
            markers: jobMarkers,
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
        if (userMarker != null) MarkerLayer(markers: [userMarker]),
      ],
    );
  }

  Widget buildBottomSheet(List<Job> jobs) {
    return DraggableScrollableSheet(
      initialChildSize: 0.2,
      minChildSize: 0.18,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.deep.withValues(alpha: 0.96),
            image: DecorationImage(
              image: const AssetImage(AppAssets.backgroundForkliftSite),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              colorFilter: ColorFilter.mode(
                AppColors.deep.withValues(alpha: 0.72),
                BlendMode.srcOver,
              ),
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 26,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              SmartJobSearchField(
                selectedRoles: selectedRoles,
                query: searchQuery,
                filters: const JobSearchFilters(),
                jobs: allJobs,
                hintText: "Search jobs on map",
                showFilterButton: false,
                onChanged: (value) {
                  setState(() {
                    selectedRoles = value.roles;
                    searchQuery = value.query;
                    selectedJobId = null;
                    selectedJob = null;
                  });
                },
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: refreshMapData,
                  child: jobs.isEmpty
                      ? ListView(
                          controller: scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 48),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                "No active vacancies available.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          controller: scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: jobs.length,
                          itemBuilder: (context, index) {
                            final job = jobs[index];
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedJobId = job.id;
                                });
                                mapController.move(
                                    LatLng(job.lat, job.lng), 16);
                              },
                              child: buildJobCard(job),
                            );
                          },
                        ),
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

    return JobCard(
      job: job,
      dense: true,
      distanceText: distance == double.infinity
          ? null
          : "${distance.toStringAsFixed(1)} mi",
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobDetailScreen(job: job),
          ),
        );
      },
      bottomAction: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () {
            mapController.move(LatLng(job.lat, job.lng), 17);
            setState(() {
              selectedJobId = job.id;
            });
          },
          child: const Text("Show on map"),
        ),
      ),
    );
  }

  List<Job> mergeMapJobs(List<Job> publicJobs, List<Job> ownerJobs) {
    final byId = <String, Job>{};
    for (final job in publicJobs) {
      byId[job.id] = job;
    }
    for (final job in ownerJobs) {
      byId[job.id] = job;
    }
    return byId.values.toList();
  }

  Widget buildMapContent(List<Job> jobs) {
    debugPrint("EMPLOYER MAP LOAD START");
    allJobs = jobs;

    List<Job> visibleJobs = getVisibleJobs();

    if (visibleJobs.isEmpty) {
      visibleJobs = allJobs;
    }

    visibleJobs = applyFilters(visibleJobs);
    currentVisibleJobs = visibleJobs;
    debugPrint(
        "EMPLOYER MAP LOAD SUCCESS visibleJobsCount=${visibleJobs.length}");

    final jobMarkers = <Marker>[];

    for (int i = 0; i < visibleJobs.length; i++) {
      final job = visibleJobs[i];

      jobMarkers.add(
        Marker(
          width: 104,
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

              scrollToJob(i);
            },
            child: buildMarker(job),
          ),
        ),
      );
    }

    final userMarker = buildUserMarker();

    final center = userLat != null
        ? LatLng(userLat!, userLng!)
        : const LatLng(53.4808, -2.2426);

    return LayoutBuilder(
      builder: (context, constraints) {
        debugPrint(
          "EMPLOYER MAP BUILD mapWidgetBuilt=true "
          "mapContainerSize=${constraints.maxWidth.toStringAsFixed(1)}x"
          "${constraints.maxHeight.toStringAsFixed(1)} "
          "bottomSheetVisible=true greyPlaceholderVisible=false "
          "flutterMapLayerIndex=0 overlayLayerCount=${showSearchButton ? 2 : 1}",
        );

        return ColoredBox(
          color: const Color(0xFFE7EEF3),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: buildMap(center, jobMarkers, userMarker),
              ),
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
                          setState(() {
                            showUserLocationMarker = true;
                          });
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
          ),
        );
      },
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
            return buildMapContent(const <Job>[]);
          }

          final publicJobs = snapshot.data!;
          final employerId = currentUserId;
          if (!isEmployer || employerId == null) {
            return buildMapContent(publicJobs);
          }

          return StreamBuilder<List<Job>>(
            stream: jobRepository.getJobsByOwner(employerId),
            builder: (context, ownerSnapshot) {
              if (ownerSnapshot.connectionState == ConnectionState.waiting &&
                  !ownerSnapshot.hasData) {
                return buildMapContent(publicJobs);
              }

              return buildMapContent(
                mergeMapJobs(publicJobs, ownerSnapshot.data ?? const <Job>[]),
              );
            },
          );
        },
      ),
    );
  }
}
