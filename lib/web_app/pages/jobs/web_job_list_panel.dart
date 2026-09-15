import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_design_components.dart';
import '../../widgets/web_smart_job_search_field.dart';
import 'web_worker_job_application_status.dart';
import 'web_worker_vacancy_card.dart';

class WebJobListPanel extends StatelessWidget {
  const WebJobListPanel({
    super.key,
    required this.jobs,
    required this.selectedJobId,
    required this.onSelected,
    required this.searchController,
    required this.onSearchChanged,
    required this.title,
    required this.savedJobIds,
    this.applicationStatuses = const {},
    this.applicationStatusesResolved = true,
    this.showApplicationStatus = false,
    this.onToggleSaved,
    this.onViewVacancy,
    this.showSearch = true,
  });

  final List<Job> jobs;
  final String? selectedJobId;
  final ValueChanged<Job> onSelected;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String title;
  final Set<String> savedJobIds;
  final Map<String, WebWorkerJobApplicationStatus> applicationStatuses;
  final bool applicationStatusesResolved;
  final bool showApplicationStatus;
  final ValueChanged<Job>? onToggleSaved;
  final ValueChanged<Job>? onViewVacancy;
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
    return WebPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (showSearch) ...[
                  const SizedBox(height: 12),
                  WebSmartJobSearchField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: WebTheme.border),
          Expanded(
            child: jobs.isEmpty
                ? const WebEmptyState(
                    icon: Icons.work_outline,
                    title: 'No vacancies to display',
                    message: 'Try adjusting your search or filters.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: jobs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final job = jobs[index];
                      return WebWorkerVacancyCard(
                        key: ValueKey<String>('web-job-card:${job.id}'),
                        job: job,
                        selected: job.id == selectedJobId,
                        saved: savedJobIds.contains(job.id),
                        applicationStatus: applicationStatuses[job.id],
                        applicationStatusResolved: applicationStatusesResolved,
                        showApplicationStatus: showApplicationStatus,
                        onTap: () => onSelected(job),
                        onViewVacancy: onViewVacancy == null
                            ? null
                            : () => onViewVacancy!(job),
                        onToggleSaved: onToggleSaved == null
                            ? null
                            : () => onToggleSaved!(job),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
