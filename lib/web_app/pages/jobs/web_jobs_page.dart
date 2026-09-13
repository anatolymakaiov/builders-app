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
  });

  final String userId;
  final String role;

  @override
  State<WebJobsPage> createState() => _WebJobsPageState();
}

class _WebJobsPageState extends State<WebJobsPage> {
  final searchController = TextEditingController();
  String search = '';
  String? selectedJobId;

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
    return StreamBuilder<WebDataState<List<Job>>>(
      stream: WebJobsDataService().jobs(
        userId: widget.userId,
        role: widget.role,
      ),
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || state.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final jobs = filterJobs(state.data ?? const <Job>[]);
        if (selectedJobId == null && jobs.isNotEmpty) {
          selectedJobId = jobs.first.id;
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
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < WebBreakpoints.compactWidth;
                    if (compact) {
                      return Column(
                        children: [
                          SizedBox(
                            height: 430,
                            child: WebJobListPanel(
                              jobs: jobs,
                              selectedJobId: selectedJobId,
                              searchController: searchController,
                              onSearchChanged: (value) =>
                                  setState(() => search = value),
                              onSelected: (job) =>
                                  setState(() => selectedJobId = job.id),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 720,
                            child: WebJobDetailsPanel(job: selectedJob),
                          ),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 410,
                          child: WebJobListPanel(
                            jobs: jobs,
                            selectedJobId: selectedJobId,
                            searchController: searchController,
                            onSearchChanged: (value) =>
                                setState(() => search = value),
                            onSelected: (job) =>
                                setState(() => selectedJobId = job.id),
                          ),
                        ),
                        const SizedBox(width: 22),
                        Expanded(child: WebJobDetailsPanel(job: selectedJob)),
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
}
