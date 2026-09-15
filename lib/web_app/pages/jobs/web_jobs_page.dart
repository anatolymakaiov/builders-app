import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../models/job.dart';
import '../../services/web_data_state.dart';
import '../../services/web_application_actions_service.dart';
import '../../services/web_applications_data_service.dart';
import '../../services/web_job_management_service.dart';
import '../../services/web_jobs_data_service.dart';
import '../../services/web_job_filters.dart';
import '../../services/web_profile_communication.dart';
import '../../widgets/web_job_filters_dialog.dart';
import '../../widgets/web_apply_dialog.dart';
import '../../theme/web_breakpoints.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_design_components.dart';
import 'web_job_details_panel.dart';
import 'web_job_list_panel.dart';
import 'web_post_job_page.dart';

class WebJobsPage extends StatefulWidget {
  const WebJobsPage({
    super.key,
    required this.userId,
    required this.role,
    this.onOpenProfile,
    this.onPostJob,
    this.onOpenSubscriptions,
    this.onOpenChat,
    this.onShowOnMap,
    this.onBackToMap,
    this.onViewApplications,
    this.initialJobId,
    this.initialOwnerMode,
  });

  final String userId;
  final String role;
  final void Function(String userId, String role)? onOpenProfile;
  final VoidCallback? onPostJob;
  final VoidCallback? onOpenSubscriptions;
  final ValueChanged<String>? onOpenChat;
  final ValueChanged<String>? onShowOnMap;
  final VoidCallback? onBackToMap;
  final void Function(String jobId, {String? statusFilter})? onViewApplications;
  final String? initialJobId;
  final bool? initialOwnerMode;

  @override
  State<WebJobsPage> createState() => _WebJobsPageState();
}

class _WebJobsPageState extends State<WebJobsPage> {
  final service = WebJobsDataService();
  final managementService = WebJobManagementService();
  final applicationsService = WebApplicationsDataService();
  final applicationActions = WebApplicationActionsService();
  final profileCommunication = WebProfileCommunication();
  final searchController = TextEditingController();
  late Stream<WebDataState<WebJobsResult>> jobsStream;
  WebJobsMode mode = WebJobsMode.market;
  Set<String> savedJobIds = const <String>{};
  String search = '';
  String? selectedJobId;
  bool applying = false;
  bool managing = false;
  bool creatingJob = false;
  Job? editingJob;
  WebJobFilters filters = const WebJobFilters();
  WebJobSort sort = WebJobSort.newest;
  Position? location;
  bool savedOnly = false;
  bool withdrawing = false;
  int page = 1;
  String? targetJobId;
  bool compactDetailVisible = false;
  StreamSubscription<WebDataState<List<WebApplicationSummary>>>?
      workerApplicationsSubscription;
  Map<String, _WorkerJobApplicationState> workerApplicationStates = const {};
  bool workerApplicationsReady = false;

  bool get isEmployer => widget.role == 'employer';
  bool get isWorker => widget.role == 'worker';

  @override
  void initState() {
    super.initState();
    mode = isEmployer && widget.initialOwnerMode != false
        ? WebJobsMode.owner
        : WebJobsMode.market;
    selectedJobId = widget.initialJobId;
    targetJobId = widget.initialJobId;
    compactDetailVisible = widget.initialJobId != null;
    _resetJobsStream();
    _loadSavedJobs();
    _startWorkerApplications();
  }

  @override
  void didUpdateWidget(covariant WebJobsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialJobId != widget.initialJobId ||
        oldWidget.initialOwnerMode != widget.initialOwnerMode) {
      setState(() {
        selectedJobId = widget.initialJobId;
        targetJobId = widget.initialJobId;
        compactDetailVisible = widget.initialJobId != null;
        if (isEmployer && widget.initialOwnerMode != null) {
          mode =
              widget.initialOwnerMode! ? WebJobsMode.owner : WebJobsMode.market;
        }
      });
    }
    if (oldWidget.userId != widget.userId || oldWidget.role != widget.role) {
      unawaited(_restartWorkerApplications());
    }
  }

  @override
  void dispose() {
    workerApplicationsSubscription?.cancel();
    searchController.dispose();
    super.dispose();
  }

  List<Job> filterJobs(List<Job> jobs) {
    final result = filters.apply(
        savedOnly
            ? jobs.where((job) => savedJobIds.contains(job.id)).toList()
            : jobs,
        search);
    result.sort((a, b) => switch (sort) {
          WebJobSort.highestPay => b.rate.compareTo(a.rate),
          WebJobSort.nearest => _distance(a).compareTo(_distance(b)),
          WebJobSort.newest => (b.createdAt ?? DateTime(1970))
              .compareTo(a.createdAt ?? DateTime(1970)),
        });
    return result;
  }

  double _distance(Job job) => location == null
      ? double.infinity
      : Geolocator.distanceBetween(
          location!.latitude, location!.longitude, job.lat, job.lng);

  @override
  Widget build(BuildContext context) {
    if (creatingJob || editingJob != null) {
      final editedJob = editingJob;
      return WebPostJobPage(
        userId: widget.userId,
        existingJob: editedJob,
        onCancel: () => setState(() {
          creatingJob = false;
          editingJob = null;
        }),
        onDone: (jobId) {
          setState(() {
            creatingJob = false;
            editingJob = null;
            mode = WebJobsMode.owner;
            if (jobId != null && jobId.isNotEmpty) selectedJobId = jobId;
            _resetJobsStream();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                editedJob == null
                    ? 'Vacancy sent for approval'
                    : 'Vacancy edit sent for review',
              ),
            ),
          );
        },
        onOpenBilling: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Open Billing from your profile menu.')),
        ),
      );
    }
    return StreamBuilder<WebDataState<WebJobsResult>>(
      stream: jobsStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || state.loading) {
          return const WebLoadingState(label: 'Loading vacancies');
        }

        final result = state.data ??
            const WebJobsResult(publicJobs: <Job>[], ownerJobs: <Job>[]);
        if (isWorker && !workerApplicationsReady) {
          return const WebLoadingState(label: 'Loading vacancies');
        }
        final permittedJobs = result.jobsForMode(mode, widget.role);
        final jobs = filterJobs(permittedJobs);
        final pages = (jobs.length / 10).ceil();
        final currentPage = page.clamp(1, pages == 0 ? 1 : pages);
        final pageJobs = jobs.skip((currentPage - 1) * 10).take(10).toList();
        final targetUnavailable = targetJobId != null &&
            permittedJobs.every((job) => job.id != targetJobId);
        if (targetJobId != null && !targetUnavailable) {
          selectedJobId = targetJobId;
        } else if (targetJobId == null &&
            selectedJobId == null &&
            jobs.isNotEmpty) {
          selectedJobId = jobs.first.id;
        }
        if (targetJobId == null &&
            selectedJobId != null &&
            jobs.every((job) => job.id != selectedJobId)) {
          selectedJobId = jobs.isEmpty ? null : jobs.first.id;
        }
        Job? selectedJob;
        for (final job in permittedJobs) {
          if (job.id == selectedJobId) {
            selectedJob = job;
            break;
          }
        }

        return WebPageContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onBackToMap != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onBackToMap,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to Jobs Map'),
                  ),
                ),
                const SizedBox(height: WebSpacing.sm),
              ],
              WebPageHeader(
                title: 'Jobs',
                subtitle: isEmployer
                    ? 'Manage your vacancies or explore the market.'
                    : 'Find active construction work across the UK.',
                actions: [
                  if (isEmployer && widget.onPostJob != null)
                    FilledButton.icon(
                      onPressed: widget.onPostJob,
                      icon: const Icon(Icons.add),
                      label: const Text('Post a job'),
                    ),
                ],
              ),
              if (state.error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Could not refresh jobs: ${state.error}'),
                ),
              if (isEmployer) ...[
                _EmployerModeTabs(
                  mode: mode,
                  onChanged: (value) {
                    setState(() {
                      mode = value;
                      targetJobId = null;
                      selectedJobId = null;
                      compactDetailVisible = false;
                    });
                  },
                ),
                const SizedBox(height: 14),
              ],
              Wrap(
                spacing: WebSpacing.sm,
                runSpacing: WebSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: searchController,
                      onChanged: (value) => setState(() {
                        search = value;
                        page = 1;
                      }),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search jobs, trades, companies',
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openFilters,
                    icon: const Icon(Icons.tune),
                    label: const Text('Filters'),
                  ),
                  MenuAnchor(
                    menuChildren: [
                      for (final option in WebJobSort.values)
                        MenuItemButton(
                          leadingIcon: option == sort
                              ? const Icon(Icons.check)
                              : const SizedBox(width: 24),
                          onPressed: () => _changeSort(option),
                          child: Text(_sortLabel(option)),
                        ),
                    ],
                    builder: (context, controller, child) =>
                        OutlinedButton.icon(
                      onPressed: controller.isOpen
                          ? controller.close
                          : controller.open,
                      icon: const Icon(Icons.swap_vert),
                      label: Text('Sort: ${_sortLabel(sort)}'),
                    ),
                  ),
                  if (isWorker && widget.onOpenSubscriptions != null)
                    OutlinedButton.icon(
                      onPressed: widget.onOpenSubscriptions,
                      icon: const Icon(Icons.work_history_outlined),
                      label: const Text('Subscriptions'),
                    ),
                  if (isWorker)
                    IconButton(
                      tooltip: savedOnly ? 'Show all jobs' : 'Show saved jobs',
                      icon: Icon(
                        savedOnly ? Icons.favorite : Icons.favorite_border,
                      ),
                      onPressed: () async {
                        await _loadSavedJobs();
                        if (mounted) {
                          setState(() {
                            savedOnly = !savedOnly;
                            page = 1;
                          });
                        }
                      },
                    ),
                  IconButton(
                    tooltip: 'Previous page',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: currentPage > 1
                        ? () => setState(() => page = currentPage - 1)
                        : null,
                  ),
                  Text('$currentPage / ${pages == 0 ? 1 : pages}'),
                  IconButton(
                    tooltip: 'Next page',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: currentPage < pages
                        ? () => setState(() => page = currentPage + 1)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < WebBreakpoints.compactWidth;
                    final list = WebJobListPanel(
                      jobs: pageJobs,
                      selectedJobId: selectedJobId,
                      searchController: searchController,
                      onSearchChanged: (value) => setState(() {
                        search = value;
                        page = 1;
                      }),
                      onSelected: (job) => setState(() {
                        targetJobId = null;
                        selectedJobId = job.id;
                        compactDetailVisible = true;
                      }),
                      title: _listTitle(jobs.length),
                      savedJobIds: savedJobIds,
                      appliedJobIds: workerApplicationStates.keys.toSet(),
                      onToggleSaved: isWorker ? _toggleSaved : null,
                      showSearch: false,
                    );
                    final applicationState = selectedJob == null
                        ? null
                        : workerApplicationStates[selectedJob.id];
                    final detail = targetUnavailable
                        ? const Center(
                            child: Text('This vacancy is no longer available.'),
                          )
                        : WebJobDetailsPanel(
                            job: selectedJob,
                            isWorker: isWorker,
                            isEmployerOwner: selectedJob != null &&
                                selectedJob.ownerId == widget.userId,
                            isSaved: selectedJob == null
                                ? false
                                : savedJobIds.contains(selectedJob.id),
                            applying: applying,
                            withdrawing: withdrawing,
                            hasApplication:
                                applicationState?.hasApplication ?? false,
                            canWithdraw: applicationState?.withdrawable != null,
                            acceptedApplication:
                                applicationState?.accepted ?? false,
                            onApply: selectedJob == null
                                ? null
                                : () => _applyToJob(selectedJob!),
                            onToggleSaved: selectedJob == null
                                ? null
                                : () => _toggleSaved(selectedJob!),
                            onViewCompanyProfile: selectedJob == null ||
                                    selectedJob.ownerId == 'unknown'
                                ? null
                                : () => widget.onOpenProfile?.call(
                                      selectedJob!.ownerId,
                                      'employer',
                                    ),
                            onMessageEmployer: selectedJob == null ||
                                    selectedJob.ownerId == 'unknown'
                                ? null
                                : () => _messageEmployer(selectedJob!),
                            onShowOnMap: selectedJob == null ||
                                    widget.onShowOnMap == null ||
                                    selectedJob.lat == 0 ||
                                    selectedJob.lng == 0
                                ? null
                                : () =>
                                    widget.onShowOnMap?.call(selectedJob!.id),
                            onWithdraw: applicationState?.withdrawable == null
                                ? null
                                : () => _withdrawApplication(
                                      applicationState!.withdrawable!,
                                    ),
                            onEdit: selectedJob == null ||
                                    !isEmployer ||
                                    selectedJob.ownerId != widget.userId
                                ? null
                                : () =>
                                    setState(() => editingJob = selectedJob),
                            onToggleActive: selectedJob == null ||
                                    !isEmployer ||
                                    selectedJob.ownerId != widget.userId
                                ? null
                                : () => _setJobActive(
                                      selectedJob!,
                                      selectedJob.status.trim().toLowerCase() !=
                                          'active',
                                    ),
                            onDelete: selectedJob == null ||
                                    !isEmployer ||
                                    selectedJob.ownerId != widget.userId
                                ? null
                                : () => _deleteJob(selectedJob!),
                            onViewApplications: selectedJob == null ||
                                    !isEmployer ||
                                    selectedJob.ownerId != widget.userId
                                ? null
                                : () => widget.onViewApplications
                                    ?.call(selectedJob!.id),
                            statsLoader: selectedJob == null ||
                                    !isEmployer ||
                                    selectedJob.ownerId != widget.userId
                                ? null
                                : () => managementService.applicationStats(
                                      selectedJob!.id,
                                    ),
                            managing: managing,
                          );
                    if (compact) {
                      return WebCompactDetailView(
                        showDetail: compactDetailVisible && selectedJob != null,
                        list: list,
                        detail: detail,
                        onBack: () => setState(
                          () => compactDetailVisible = false,
                        ),
                        backLabel: 'Back to vacancies',
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: WebBreakpoints.masterPaneWidth(
                            constraints.maxWidth,
                          ),
                          child: list,
                        ),
                        const SizedBox(width: WebSpacing.lg),
                        Expanded(child: detail),
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

  String _listTitle(int count) {
    if (isEmployer && mode == WebJobsMode.owner) {
      return count == 1 ? '1 of your vacancies' : '$count of your vacancies';
    }
    return count == 1 ? '1 market vacancy' : '$count market vacancies';
  }

  Future<void> _openFilters() async {
    final next = await showDialog<WebJobFilters>(
      context: context,
      builder: (_) => WebJobFiltersDialog(current: filters),
    );
    if (!mounted || next == null) return;
    setState(() {
      filters = next;
      page = 1;
    });
  }

  Future<void> _changeSort(WebJobSort value) async {
    if (value == WebJobSort.nearest && location == null) {
      try {
        location = await Geolocator.getCurrentPosition();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location unavailable. Allow location access and retry.',
              ),
            ),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      sort = value;
      page = 1;
    });
  }

  String _sortLabel(WebJobSort value) => switch (value) {
        WebJobSort.newest => 'Newest',
        WebJobSort.highestPay => 'Highest pay',
        WebJobSort.nearest => 'Nearest',
      };

  void _resetJobsStream() {
    jobsStream = service.jobs(userId: widget.userId, role: widget.role);
  }

  Future<void> _loadSavedJobs() async {
    if (!isWorker) return;
    try {
      final ids = await service.savedJobIds(widget.userId);
      if (mounted) setState(() => savedJobIds = ids);
    } catch (_) {
      if (mounted) setState(() => savedJobIds = const <String>{});
    }
  }

  Future<void> _toggleSaved(Job job) async {
    final wasSaved = savedJobIds.contains(job.id);
    setState(() {
      savedJobIds = {
        ...savedJobIds.where((id) => id != job.id),
        if (!wasSaved) job.id,
      };
    });
    try {
      await service.toggleSavedJob(
        userId: widget.userId,
        jobId: job.id,
        isSaved: wasSaved,
      );
      await _loadSavedJobs();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        savedJobIds = {
          ...savedJobIds.where((id) => id != job.id),
          if (wasSaved) job.id,
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update saved job: $error')),
      );
    }
  }

  Future<void> _applyToJob(Job job) async {
    if (applying) return;
    setState(() => applying = true);
    try {
      final applied =
          await showWebApplyDialog(context, userId: widget.userId, job: job);
      if (!applied) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application sent')),
      );
      await _refreshWorkerApplications();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().contains('already_applied')
          ? 'You already applied'
          : 'Could not send application. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => applying = false);
    }
  }

  void _startWorkerApplications() {
    if (!isWorker) return;
    workerApplicationsSubscription = applicationsService
        .workerJobApplications(widget.userId)
        .listen((state) {
      final applications = state.data;
      if (!mounted || applications == null) return;
      setState(() {
        workerApplicationStates = _groupWorkerApplications(applications);
        workerApplicationsReady = true;
      });
    });
  }

  Future<void> _restartWorkerApplications() async {
    await workerApplicationsSubscription?.cancel();
    workerApplicationsSubscription = null;
    if (!mounted) return;
    setState(() {
      workerApplicationStates = const {};
      workerApplicationsReady = false;
    });
    _startWorkerApplications();
  }

  Future<void> _refreshWorkerApplications() async {
    if (!isWorker) return;
    try {
      final applications =
          await applicationsService.loadWorkerJobApplications(widget.userId);
      if (!mounted) return;
      setState(() {
        workerApplicationStates = _groupWorkerApplications(applications);
        workerApplicationsReady = true;
      });
    } catch (error) {
      debugPrint('WEB JOB APPLICATION PRESENCE REFRESH ERROR $error');
    }
  }

  Map<String, _WorkerJobApplicationState> _groupWorkerApplications(
    List<WebApplicationSummary> applications,
  ) {
    final grouped = <String, List<WebApplicationSummary>>{};
    for (final application in applications) {
      final jobId = application.data['jobId']?.toString().trim() ?? '';
      final status = application.status.trim().toLowerCase();
      if (jobId.isEmpty ||
          status == 'withdrawn' ||
          status == 'cancelled' ||
          status == 'deleted') {
        continue;
      }
      grouped.putIfAbsent(jobId, () => []).add(application);
    }
    return {
      for (final entry in grouped.entries)
        entry.key: _WorkerJobApplicationState(entry.value),
    };
  }

  Future<void> _messageEmployer(Job job) async {
    try {
      final chatId = await profileCommunication.message(job.ownerId);
      if (!mounted) return;
      widget.onOpenChat?.call(chatId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat: $error')),
      );
    }
  }

  Future<void> _withdrawApplication(WebApplicationSummary application) async {
    if (withdrawing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw application'),
        content: const Text('Withdraw this application?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => withdrawing = true);
    try {
      await applicationActions.withdrawApplication(application);
      await _refreshWorkerApplications();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application withdrawn')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not withdraw application')),
      );
    } finally {
      if (mounted) setState(() => withdrawing = false);
    }
  }

  Future<void> _setJobActive(Job job, bool active) async {
    if (managing) return;
    setState(() => managing = true);
    try {
      await managementService.setJobActive(job, active);
      if (!mounted) return;
      setState(() => _resetJobsStream());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(active ? 'Vacancy activated' : 'Vacancy made inactive'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update vacancy: $error')),
      );
    } finally {
      if (mounted) setState(() => managing = false);
    }
  }

  Future<void> _deleteJob(Job job) async {
    if (managing) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete vacancy'),
        content: const Text('Delete this vacancy?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => managing = true);
    try {
      await managementService.deleteJob(job);
      if (!mounted) return;
      setState(() {
        selectedJobId = null;
        _resetJobsStream();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vacancy deleted')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete vacancy: $error')),
      );
    } finally {
      if (mounted) setState(() => managing = false);
    }
  }
}

class _WorkerJobApplicationState {
  const _WorkerJobApplicationState(this.applications);

  final List<WebApplicationSummary> applications;

  bool get hasApplication => applications.isNotEmpty;

  bool get accepted => applications.any((application) {
        final status = application.status.trim().toLowerCase();
        return status == 'offer_accepted' ||
            status == 'accepted' ||
            status == 'hired';
      });

  WebApplicationSummary? get withdrawable {
    for (final application in applications) {
      final status = application.status.trim().toLowerCase();
      if (status == 'pending' || status == 'in_review') return application;
    }
    return null;
  }
}

class _EmployerModeTabs extends StatelessWidget {
  const _EmployerModeTabs({
    required this.mode,
    required this.onChanged,
  });

  final WebJobsMode mode;
  final ValueChanged<WebJobsMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<WebJobsMode>(
        segments: const [
          ButtonSegment(
            value: WebJobsMode.owner,
            label: Text('My vacancies'),
            icon: Icon(Icons.business_center_outlined),
          ),
          ButtonSegment(
            value: WebJobsMode.market,
            label: Text('Market jobs'),
            icon: Icon(Icons.public_outlined),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (value) => onChanged(value.first),
      ),
    );
  }
}
