import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/job.dart';
import '../jobs/web_job_details_panel.dart';
import '../../services/web_job_filters.dart';
import '../../widgets/web_job_filters_dialog.dart';
import '../../widgets/web_apply_dialog.dart';
import '../../services/web_data_state.dart';
import '../../services/web_jobs_data_service.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_design_components.dart';
import '../../theme/web_breakpoints.dart';

class WebMapPage extends StatefulWidget {
  const WebMapPage({
    super.key,
    required this.userId,
    required this.role,
    this.onOpenProfile,
  });

  final String userId;
  final String role;
  final void Function(String userId, String role)? onOpenProfile;

  @override
  State<WebMapPage> createState() => _WebMapPageState();
}

class _WebMapPageState extends State<WebMapPage> {
  final service = WebJobsDataService();
  final mapController = MapController();
  final listController = ScrollController();
  final searchController = TextEditingController();
  late final Stream<WebDataState<WebJobsResult>> jobsStream;
  LatLngBounds? activeBounds;
  LatLngBounds? pendingBounds;
  LatLng? userLocation;
  String? selectedJobId;
  String search = '';
  bool showSearchArea = false;
  bool loadingLocation = false;
  String? locationError;
  WebJobFilters filters = const WebJobFilters();
  bool compactMapVisible = true;

  bool get isWorker => widget.role == 'worker';

  @override
  void initState() {
    super.initState();
    jobsStream = service.jobs(userId: widget.userId, role: 'worker');
    debugPrint('WEB MAP INIT tileSource=osm polling=jobs');
  }

  @override
  void dispose() {
    mapController.dispose();
    listController.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebDataState<WebJobsResult>>(
      stream: jobsStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || state.loading) {
          return const WebLoadingState(label: 'Loading vacancy map');
        }
        final result = state.data ??
            const WebJobsResult(publicJobs: <Job>[], ownerJobs: <Job>[]);
        final marketJobs = _filterJobs(result.publicJobs);
        final mapJobs = _jobsInBounds(marketJobs);
        if (selectedJobId == null && mapJobs.isNotEmpty) {
          selectedJobId = mapJobs.first.id;
        }
        if (selectedJobId != null &&
            mapJobs.every((job) => job.id != selectedJobId)) {
          selectedJobId = mapJobs.isEmpty ? null : mapJobs.first.id;
        }

        return WebPageContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.error != null)
                _ErrorBanner(
                    message: 'Could not refresh map jobs: ${state.error}'),
              WebPageHeader(
                title: 'Map',
                subtitle: '${mapJobs.length} active vacancies in this area.',
                actions: [
                  OutlinedButton.icon(
                      icon: const Icon(Icons.tune),
                      label: const Text('Trade filters'),
                      onPressed: () async {
                        final next = await showDialog<WebJobFilters>(
                            context: context,
                            builder: (_) => WebJobFiltersDialog(
                                current: filters, rolesOnly: true));
                        if (mounted && next != null) {
                          setState(() => filters = next);
                        }
                      }),
                  OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('View selected vacancy'),
                      onPressed: selectedJobId == null
                          ? null
                          : () => _openJob(mapJobs
                              .firstWhere((job) => job.id == selectedJobId))),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < WebBreakpoints.compactWidth;
                    final results = _MapResultsPanel(
                      jobs: mapJobs,
                      selectedJobId: selectedJobId,
                      controller: listController,
                      searchController: searchController,
                      search: search,
                      userLocation: userLocation,
                      onSearchChanged: (value) {
                        setState(() => search = value);
                      },
                      onSelected: _selectJobFromList,
                    );
                    final map = WebPanel(
                      padding: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(WebRadii.panel),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _MapCanvas(
                              jobs: mapJobs,
                              selectedJobId: selectedJobId,
                              userLocation: userLocation,
                              mapController: mapController,
                              onPositionChanged: (bounds, hasGesture) {
                                pendingBounds = bounds;
                                if (hasGesture && !showSearchArea) {
                                  setState(() => showSearchArea = true);
                                }
                              },
                              onMarkerSelected: _selectJobFromMarker,
                            ),
                            if (showSearchArea)
                              Positioned(
                                top: 18,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        activeBounds = pendingBounds;
                                        showSearchArea = false;
                                      });
                                    },
                                    icon: const Icon(Icons.search),
                                    label: const Text('Search this area'),
                                  ),
                                ),
                              ),
                            Positioned(
                              right: 18,
                              top: 18,
                              child: Column(
                                children: [
                                  FloatingActionButton.small(
                                    heroTag: 'web-map-zoom-in',
                                    onPressed: () => mapController.move(
                                      mapController.camera.center,
                                      mapController.camera.zoom + 1,
                                    ),
                                    child: const Icon(Icons.add),
                                  ),
                                  const SizedBox(height: 10),
                                  FloatingActionButton.small(
                                    heroTag: 'web-map-zoom-out',
                                    onPressed: () => mapController.move(
                                      mapController.camera.center,
                                      mapController.camera.zoom - 1,
                                    ),
                                    child: const Icon(Icons.remove),
                                  ),
                                  if (isWorker) ...[
                                    const SizedBox(height: 10),
                                    FloatingActionButton.small(
                                      heroTag: 'web-map-location',
                                      onPressed:
                                          loadingLocation ? null : _locateUser,
                                      child: loadingLocation
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.my_location),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (locationError != null)
                              Positioned(
                                right: 18,
                                bottom: 18,
                                child: _MapNotice(text: locationError!),
                              ),
                          ],
                        ),
                      ),
                    );
                    if (compact) {
                      return Column(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  icon: Icon(Icons.view_list_outlined),
                                  label: Text('Results'),
                                ),
                                ButtonSegment(
                                  value: true,
                                  icon: Icon(Icons.map_outlined),
                                  label: Text('Map'),
                                ),
                              ],
                              selected: {compactMapVisible},
                              onSelectionChanged: (selection) => setState(
                                () => compactMapVisible = selection.first,
                              ),
                            ),
                          ),
                          const SizedBox(height: WebSpacing.sm),
                          Expanded(child: compactMapVisible ? map : results),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(
                          width: WebBreakpoints.masterPaneWidth(
                            constraints.maxWidth,
                          ),
                          child: results,
                        ),
                        const SizedBox(width: WebSpacing.lg),
                        Expanded(child: map),
                      ],
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

  List<Job> _filterJobs(List<Job> jobs) {
    return filters.apply(
        jobs.where((job) => job.lat != 0 && job.lng != 0).toList(), search);
  }

  Future<void> _openJob(Job job) async {
    Set<String> saved;
    try {
      saved = isWorker ? await service.savedJobIds(widget.userId) : <String>{};
    } catch (_) {
      saved = <String>{};
    }
    if (!mounted) return;
    var busy = false;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
              insetPadding: const EdgeInsets.all(WebSpacing.lg),
              child: SizedBox(
                width: (MediaQuery.sizeOf(dialogContext).width - 48)
                    .clamp(280.0, 840.0)
                    .toDouble(),
                height: MediaQuery.sizeOf(dialogContext).height * .88,
                child: StatefulBuilder(
                    builder: (context, update) => Column(children: [
                          Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                  tooltip: 'Close',
                                  icon: const Icon(Icons.close),
                                  onPressed: () =>
                                      Navigator.pop(dialogContext))),
                          Expanded(
                              child: WebJobDetailsPanel(
                            job: job,
                            isWorker: isWorker,
                            isSaved: saved.contains(job.id),
                            applying: busy,
                            onApply: () async {
                              update(() => busy = true);
                              await showWebApplyDialog(context,
                                  userId: widget.userId, job: job);
                              if (context.mounted) update(() => busy = false);
                            },
                            onToggleSaved: () async {
                              try {
                                final wasSaved = saved.contains(job.id);
                                await service.toggleSavedJob(
                                    userId: widget.userId,
                                    jobId: job.id,
                                    isSaved: wasSaved);
                                if (context.mounted) {
                                  update(() {
                                    wasSaved
                                        ? saved.remove(job.id)
                                        : saved.add(job.id);
                                  });
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Could not save job: $error')));
                                }
                              }
                            },
                            onViewCompanyProfile: () {
                              Navigator.pop(dialogContext);
                              widget.onOpenProfile
                                  ?.call(job.ownerId, 'employer');
                            },
                          )),
                        ])),
              ),
            ));
  }

  List<Job> _jobsInBounds(List<Job> jobs) {
    final bounds = activeBounds;
    if (bounds == null) return jobs;
    return jobs
        .where((job) => bounds.contains(LatLng(job.lat, job.lng)))
        .toList();
  }

  void _selectJobFromList(Job job) {
    setState(() => selectedJobId = job.id);
    mapController.move(
        LatLng(job.lat, job.lng), math.max(13, mapController.camera.zoom));
  }

  void _selectJobFromMarker(Job job, int index) {
    setState(() => selectedJobId = job.id);
    _scrollTo(index);
  }

  void _scrollTo(int index) {
    if (!listController.hasClients) return;
    listController.animateTo(
      (index * 156).toDouble(),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _locateUser() async {
    setState(() {
      loadingLocation = true;
      locationError = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission denied.');
      }
      final position = await Geolocator.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => userLocation = point);
      mapController.move(point, 13);
    } catch (error) {
      if (mounted) setState(() => locationError = error.toString());
    } finally {
      if (mounted) setState(() => loadingLocation = false);
    }
  }
}

class _MapCanvas extends StatelessWidget {
  const _MapCanvas({
    required this.jobs,
    required this.selectedJobId,
    required this.userLocation,
    required this.mapController,
    required this.onPositionChanged,
    required this.onMarkerSelected,
  });

  final List<Job> jobs;
  final String? selectedJobId;
  final LatLng? userLocation;
  final MapController mapController;
  final void Function(LatLngBounds? bounds, bool hasGesture) onPositionChanged;
  final void Function(Job job, int index) onMarkerSelected;

  @override
  Widget build(BuildContext context) {
    final center = userLocation ??
        (jobs.isNotEmpty
            ? LatLng(jobs.first.lat, jobs.first.lng)
            : const LatLng(53.4808, -2.2426));
    final markers = <Marker>[
      for (var i = 0; i < jobs.length; i++)
        Marker(
          width: 112,
          height: 44,
          point: LatLng(jobs[i].lat, jobs[i].lng),
          child: GestureDetector(
            onTap: () => onMarkerSelected(jobs[i], i),
            child: _JobMarker(
              job: jobs[i],
              selected: jobs[i].id == selectedJobId,
            ),
          ),
        ),
    ];
    debugPrint('WEB MAP BUILD mapWidgetBuilt=true jobs=${jobs.length}');
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: jobs.isEmpty ? 6 : 10,
        minZoom: 3,
        maxZoom: 18,
        backgroundColor: const Color(0xFFE7EEF3),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onPositionChanged: (camera, hasGesture) {
          onPositionChanged(camera.bounds, hasGesture);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.makaiov.builderjob',
          errorTileCallback: (tile, error, stackTrace) {
            debugPrint('WEB MAP TILE ERROR tile=$tile error=$error');
          },
        ),
        MarkerClusterLayerWidget(
          options: MarkerClusterLayerOptions(
            markers: markers,
            maxClusterRadius: 120,
            size: const Size(42, 42),
            onClusterTap: (cluster) {
              mapController.move(
                cluster.bounds.center,
                mapController.camera.zoom + 2,
              );
            },
            builder: (context, cluster) {
              return Container(
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: WebTheme.green,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  cluster.length.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              );
            },
          ),
        ),
        if (userLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: userLocation!,
                width: 34,
                height: 34,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _MapResultsPanel extends StatelessWidget {
  const _MapResultsPanel({
    required this.jobs,
    required this.selectedJobId,
    required this.controller,
    required this.searchController,
    required this.search,
    required this.userLocation,
    required this.onSearchChanged,
    required this.onSelected,
  });

  final List<Job> jobs;
  final String? selectedJobId;
  final ScrollController controller;
  final TextEditingController searchController;
  final String search;
  final LatLng? userLocation;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Job> onSelected;

  @override
  Widget build(BuildContext context) {
    return WebPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Vacancies on map',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  jobs.length == 1
                      ? '1 vacancy in this area'
                      : '${jobs.length} vacancies in this area',
                  style: const TextStyle(color: WebTheme.muted),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search title, trade, company, location',
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: WebTheme.border),
          Expanded(
            child: jobs.isEmpty
                ? const Center(child: Text('No active vacancies available.'))
                : ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.all(12),
                    itemCount: jobs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final job = jobs[index];
                      return _ResultCard(
                        job: job,
                        selected: job.id == selectedJobId,
                        distanceMiles: _distanceMiles(job),
                        onTap: () => onSelected(job),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  double? _distanceMiles(Job job) {
    final location = userLocation;
    if (location == null) return null;
    final meters = Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      job.lat,
      job.lng,
    );
    return meters / 1609.344;
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.job,
    required this.selected,
    required this.distanceMiles,
    required this.onTap,
  });

  final Job job;
  final bool selected;
  final double? distanceMiles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WebRadii.card),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? WebTheme.greenSoft : WebTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(WebRadii.card),
          border: Border.all(
            color: selected ? WebTheme.green : WebTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              job.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WebTheme.ink,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              job.companyName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: WebTheme.muted),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 16, color: WebTheme.muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    job.fullAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: WebTheme.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (job.rateText.isNotEmpty) _MiniChip(label: job.rateText),
                _MiniChip(
                  label: '${job.remainingPositions}/${job.positions} spots',
                ),
                if (distanceMiles != null)
                  _MiniChip(label: '${distanceMiles!.toStringAsFixed(1)} mi'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JobMarker extends StatelessWidget {
  const _JobMarker({
    required this.job,
    required this.selected,
  });

  final Job job;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? WebTheme.deep : WebTheme.green,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        job.rateText.isEmpty ? job.workFormatText : job.rateText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: WebTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WebTheme.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: WebTheme.ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MapNotice extends StatelessWidget {
  const _MapNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebTheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebTheme.border),
      ),
      child: Text(text),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message),
    );
  }
}
