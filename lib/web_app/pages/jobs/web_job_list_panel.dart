import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_remote_image.dart';
import '../../widgets/web_design_components.dart';

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
    this.showSearch = true,
  });

  final List<Job> jobs;
  final String? selectedJobId;
  final ValueChanged<Job> onSelected;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String title;
  final Set<String> savedJobIds;
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
                  TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search jobs, trades, companies',
                    ),
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
                      return _WebJobCard(
                        job: job,
                        selected: job.id == selectedJobId,
                        saved: savedJobIds.contains(job.id),
                        onTap: () => onSelected(job),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WebJobCard extends StatelessWidget {
  const _WebJobCard({
    required this.job,
    required this.selected,
    required this.saved,
    required this.onTap,
  });

  final Job job;
  final bool selected;
  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final location = job.fullAddress;
    return InkWell(
      borderRadius: BorderRadius.circular(WebRadii.card),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? WebTheme.selected : WebTheme.surface,
          borderRadius: BorderRadius.circular(WebRadii.card),
          border: Border.all(
            color: selected ? WebTheme.accent : WebTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WebCircleImage(
                  url: job.companyLogo,
                  size: 44,
                  fallbackIcon: Icons.business_outlined,
                ),
                const SizedBox(width: WebSpacing.sm),
                Expanded(
                  child: Text(
                    job.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WebTheme.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (saved)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child:
                        Icon(Icons.favorite, color: WebTheme.accent, size: 18),
                  ),
              ],
            ),
            if (job.companyName.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                job.companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: WebTheme.muted),
              ),
            ],
            if (location.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.place_outlined,
                    size: 16,
                    color: WebTheme.muted,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: WebTheme.muted),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (job.rateText.isNotEmpty) _Chip(label: job.rateText),
                if (job.duration.isNotEmpty) _Chip(label: job.duration),
                if (job.positions > 1)
                  _Chip(
                    label: '${job.remainingPositions} of ${job.positions}',
                  ),
                if (job.status.trim().isNotEmpty)
                  _Chip(
                      label: job.moderationStatus == 'approved'
                          ? job.status
                          : job.moderationLabel),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: WebTheme.surface,
        borderRadius: BorderRadius.circular(WebRadii.tag),
        border: Border.all(color: WebTheme.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: WebTheme.ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
