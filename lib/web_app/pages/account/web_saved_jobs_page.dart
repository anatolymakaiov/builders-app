import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../services/web_account_data_service.dart';
import '../../services/web_data_state.dart';
import '../../theme/web_breakpoints.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_design_components.dart';
import '../../theme/web_theme.dart';
import '../jobs/web_job_details_panel.dart';
import '../jobs/web_job_list_panel.dart';

class WebSavedJobsPage extends StatefulWidget {
  const WebSavedJobsPage({
    super.key,
    required this.userId,
    required this.onClose,
    required this.onOpenProfile,
  });

  final String userId;
  final VoidCallback onClose;
  final void Function(String userId, String role) onOpenProfile;

  @override
  State<WebSavedJobsPage> createState() => _WebSavedJobsPageState();
}

class _WebSavedJobsPageState extends State<WebSavedJobsPage> {
  final service = WebAccountDataService();
  final searchController = TextEditingController();
  late Stream<WebDataState<List<Job>>> stream;
  String search = '';
  String? selectedJobId;
  bool compactDetailVisible = false;

  @override
  void initState() {
    super.initState();
    stream = _savedStream();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebPageContainer(
      child: StreamBuilder<WebDataState<List<Job>>>(
        stream: stream,
        builder: (context, snapshot) {
          final state = snapshot.data;
          final jobs = _filter(state?.data ?? const <Job>[]);
          if (selectedJobId == null && jobs.isNotEmpty) {
            selectedJobId = jobs.first.id;
          }
          if (selectedJobId != null &&
              jobs.every((job) => job.id != selectedJobId)) {
            selectedJobId = jobs.isEmpty ? null : jobs.first.id;
          }
          final selected = jobs
              .where((job) => job.id == selectedJobId)
              .cast<Job?>()
              .firstOrNull;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(title: 'Saved Jobs', onClose: widget.onClose),
              if (state?.error != null)
                const _ErrorBanner(message: 'Could not refresh saved jobs.'),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < WebBreakpoints.compactWidth;
                    final list = WebPanel(
                      padding: EdgeInsets.zero,
                      child: (state == null || state.loading) && jobs.isEmpty
                          ? const WebLoadingState(label: 'Loading saved jobs')
                          : WebJobListPanel(
                              jobs: jobs,
                              selectedJobId: selectedJobId,
                              searchController: searchController,
                              onSearchChanged: (value) =>
                                  setState(() => search = value),
                              onSelected: (job) => setState(() {
                                selectedJobId = job.id;
                                compactDetailVisible = true;
                              }),
                              title: jobs.isEmpty
                                  ? 'No saved jobs yet'
                                  : '${jobs.length} saved jobs',
                              savedJobIds: jobs.map((job) => job.id).toSet(),
                            ),
                    );
                    final detail = WebJobDetailsPanel(
                      job: selected,
                      isWorker: true,
                      isEmployerOwner: false,
                      isSaved: selected != null,
                      onToggleSaved:
                          selected == null ? null : () => _unsave(selected.id),
                      onViewCompanyProfile:
                          selected == null || selected.ownerId == 'unknown'
                              ? null
                              : () => widget.onOpenProfile(
                                    selected.ownerId,
                                    'employer',
                                  ),
                    );
                    if (compact) {
                      return WebCompactDetailView(
                        showDetail: compactDetailVisible && selected != null,
                        list: list,
                        detail: detail,
                        onBack: () => setState(
                          () => compactDetailVisible = false,
                        ),
                        backLabel: 'Back to saved jobs',
                      );
                    }
                    return Row(
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
          );
        },
      ),
    );
  }

  Stream<WebDataState<List<Job>>> _savedStream() {
    return service.poll(
      () => service.loadSavedJobs(widget.userId),
      empty: const <Job>[],
      logPrefix: 'WEB SAVED JOBS LOAD ERROR',
    );
  }

  List<Job> _filter(List<Job> jobs) {
    final query = search.trim().toLowerCase();
    if (query.isEmpty) return jobs;
    return jobs.where((job) {
      return [
        job.displayTitle,
        job.trade,
        job.companyName,
        job.fullAddress,
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _unsave(String jobId) async {
    await service.unsaveJob(widget.userId, jobId);
    setState(() {
      selectedJobId = null;
      compactDetailVisible = false;
      stream = _savedStream();
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return WebPageHeader(
      title: title,
      subtitle: 'Vacancies you saved for later.',
      leading: IconButton(
        tooltip: 'Back',
        onPressed: onClose,
        icon: const Icon(Icons.arrow_back),
      ),
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
