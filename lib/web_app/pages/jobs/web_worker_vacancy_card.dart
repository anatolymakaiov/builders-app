import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_design_components.dart';
import '../../widgets/web_remote_image.dart';
import 'web_job_display.dart';
import 'web_worker_job_application_status.dart';

class WebWorkerVacancyCard extends StatelessWidget {
  const WebWorkerVacancyCard({
    super.key,
    required this.job,
    required this.selected,
    required this.saved,
    required this.onTap,
    this.applicationStatus,
    this.applicationStatusResolved = true,
    this.showApplicationStatus = true,
    this.distanceMiles,
    this.onToggleSaved,
    this.onViewVacancy,
  });

  final Job job;
  final bool selected;
  final bool saved;
  final VoidCallback onTap;
  final WebWorkerJobApplicationStatus? applicationStatus;
  final bool applicationStatusResolved;
  final bool showApplicationStatus;
  final double? distanceMiles;
  final VoidCallback? onToggleSaved;
  final VoidCallback? onViewVacancy;

  @override
  Widget build(BuildContext context) {
    final rate = webJobRate(job);
    final posted = webJobPostedLabel(job);
    return InkWell(
      borderRadius: BorderRadius.circular(WebRadii.card),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? WebTheme.accentSoft : WebTheme.surface,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              job.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: WebTheme.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (onToggleSaved != null)
                            Transform.translate(
                              offset: const Offset(6, -8),
                              child: IconButton(
                                tooltip:
                                    saved ? 'Remove from saved' : 'Save job',
                                visualDensity: VisualDensity.compact,
                                onPressed: onToggleSaved,
                                icon: Icon(
                                  saved
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color:
                                      saved ? WebTheme.accent : WebTheme.muted,
                                  size: 20,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (job.companyName.trim().isNotEmpty ||
                          (showApplicationStatus && applicationStatusResolved))
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                job.companyName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: WebTheme.muted),
                              ),
                            ),
                            if (showApplicationStatus &&
                                applicationStatusResolved) ...[
                              const SizedBox(width: WebSpacing.xs),
                              _ApplicationStatusBadge(
                                status: applicationStatus,
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (job.fullAddress.trim().isNotEmpty) ...[
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
                      job.fullAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: WebTheme.muted),
                    ),
                  ),
                ],
              ),
            ],
            if (posted != null || onViewVacancy != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  if (posted != null)
                    Expanded(
                      child: Text(
                        posted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WebTheme.subtleText,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (onViewVacancy != null)
                    IconButton(
                      tooltip: 'View vacancy',
                      visualDensity: VisualDensity.compact,
                      onPressed: onViewVacancy,
                      icon: const Icon(Icons.visibility_outlined, size: 19),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FactChip(label: webJobWorkFormat(job)),
                if (rate != null) _FactChip(label: rate),
                if (job.duration.trim().isNotEmpty)
                  _FactChip(label: job.duration),
                if (distanceMiles != null)
                  _FactChip(
                    label: '${distanceMiles!.toStringAsFixed(1)} miles away',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplicationStatusBadge extends StatelessWidget {
  const _ApplicationStatusBadge({required this.status});

  final WebWorkerJobApplicationStatus? status;

  @override
  Widget build(BuildContext context) {
    final resolved = status;
    final label = resolved?.label ?? 'Not Applied';
    final tone = resolved?.tone ?? WebStatusTone.neutral;
    final colors = switch (tone) {
      WebStatusTone.success => (WebTheme.accent, WebTheme.accentSoft),
      WebStatusTone.info => (WebTheme.info, WebTheme.infoSoft),
      WebStatusTone.danger => (WebTheme.danger, WebTheme.dangerSoft),
      WebStatusTone.warning => (WebTheme.warning, WebTheme.warningSoft),
      WebStatusTone.neutral => (WebTheme.muted, WebTheme.surfaceAlt),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 116),
      child: Tooltip(
        message: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.$2,
            borderRadius: BorderRadius.circular(WebRadii.tag),
            border: Border.all(color: colors.$1.withValues(alpha: 0.28)),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.$1,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.label});

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
