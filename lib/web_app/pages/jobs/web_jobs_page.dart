import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../services/web_data_state.dart';
import '../../services/web_jobs_data_service.dart';
import '../../theme/web_breakpoints.dart';
import '../../widgets/web_page_container.dart';
import 'web_job_details_panel.dart';
import 'web_job_list_panel.dart';

class WebJobsPage extends StatefulWidget {
  const WebJobsPage({
    super.key,
    required this.userId,
    required this.role,
    this.onOpenProfile,
  });

  final String userId;
  final String role;
  final void Function(String userId, String role)? onOpenProfile;

  @override
  State<WebJobsPage> createState() => _WebJobsPageState();
}

class _WebJobsPageState extends State<WebJobsPage> {
  final service = WebJobsDataService();
  final searchController = TextEditingController();
  late final Stream<WebDataState<WebJobsResult>> jobsStream;
  WebJobsMode mode = WebJobsMode.market;
  Set<String> savedJobIds = const <String>{};
  String search = '';
  String? selectedJobId;
  bool applying = false;

  bool get isEmployer => widget.role == 'employer';
  bool get isWorker => widget.role == 'worker';

  @override
  void initState() {
    super.initState();
    mode = isEmployer ? WebJobsMode.owner : WebJobsMode.market;
    jobsStream = service.jobs(userId: widget.userId, role: widget.role);
    _loadSavedJobs();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Job> filterJobs(List<Job> jobs) {
    final query = search.trim().toLowerCase();
    if (query.isEmpty) return jobs;
    return jobs.where((job) {
      return [
        job.displayTitle,
        job.trade,
        job.companyName,
        job.fullAddress,
        job.description,
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebDataState<WebJobsResult>>(
      stream: jobsStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || state.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final result = state.data ??
            const WebJobsResult(publicJobs: <Job>[], ownerJobs: <Job>[]);
        final jobs = filterJobs(result.jobsForMode(mode, widget.role));
        if (selectedJobId == null && jobs.isNotEmpty) {
          selectedJobId = jobs.first.id;
        }
        if (selectedJobId != null &&
            jobs.every((job) => job.id != selectedJobId)) {
          selectedJobId = jobs.isEmpty ? null : jobs.first.id;
        }
        Job? selectedJob;
        for (final job in jobs) {
          if (job.id == selectedJobId) {
            selectedJob = job;
            break;
          }
        }

        return WebPageContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                      selectedJobId = null;
                    });
                  },
                ),
                const SizedBox(height: 14),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < WebBreakpoints.compactWidth;
                    final list = WebJobListPanel(
                      jobs: jobs,
                      selectedJobId: selectedJobId,
                      searchController: searchController,
                      onSearchChanged: (value) =>
                          setState(() => search = value),
                      onSelected: (job) =>
                          setState(() => selectedJobId = job.id),
                      title: _listTitle(jobs.length),
                      savedJobIds: savedJobIds,
                    );
                    final detail = WebJobDetailsPanel(
                      job: selectedJob,
                      isWorker: isWorker,
                      isEmployerOwner: selectedJob != null &&
                          selectedJob.ownerId == widget.userId,
                      isSaved: selectedJob == null
                          ? false
                          : savedJobIds.contains(selectedJob.id),
                      applying: applying,
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
                    );
                    if (compact) {
                      return Column(
                        children: [
                          SizedBox(height: 430, child: list),
                          const SizedBox(height: 18),
                          SizedBox(height: 760, child: detail),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 410, child: list),
                        const SizedBox(width: 22),
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
      await service.applyAsSingle(userId: widget.userId, job: job);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application sent')),
      );
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
