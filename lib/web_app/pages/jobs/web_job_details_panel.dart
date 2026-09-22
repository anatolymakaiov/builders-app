import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../../services/job_start_date.dart';
import '../../services/web_job_management_service.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_remote_image.dart';
import 'web_job_display.dart';
import 'web_vacancy_lifecycle_status.dart';

class WebJobDetailsPanel extends StatelessWidget {
  const WebJobDetailsPanel({
    super.key,
    required this.job,
    this.isWorker = false,
    this.isEmployerOwner = false,
    this.isSaved = false,
    this.applying = false,
    this.onApply,
    this.onToggleSaved,
    this.onViewCompanyProfile,
    this.onMessageEmployer,
    this.onShowOnMap,
    this.onWithdraw,
    this.hasApplication = false,
    this.canWithdraw = false,
    this.acceptedApplication = false,
    this.withdrawing = false,
    this.onEdit,
    this.onToggleActive,
    this.onDelete,
    this.onViewApplications,
    this.statsLoader,
    this.managing = false,
  });

  final Job? job;
  final bool isWorker;
  final bool isEmployerOwner;
  final bool isSaved;
  final bool applying;
  final VoidCallback? onApply;
  final VoidCallback? onToggleSaved;
  final VoidCallback? onViewCompanyProfile;
  final VoidCallback? onMessageEmployer;
  final VoidCallback? onShowOnMap;
  final VoidCallback? onWithdraw;
  final bool hasApplication;
  final bool canWithdraw;
  final bool acceptedApplication;
  final bool withdrawing;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleActive;
  final VoidCallback? onDelete;
  final VoidCallback? onViewApplications;
  final Future<WebJobApplicationStats> Function()? statsLoader;
  final bool managing;

  @override
  Widget build(BuildContext context) {
    if (job == null) {
      return const WebPanel(
        child: Center(
          child: Text('Select a job to view details.'),
        ),
      );
    }

    final currentJob = job!;
    final rate = webJobRate(currentJob);
    return WebPanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WebRadii.panel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Hero(
                      job: currentJob,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _IdentityRow(
                            job: currentJob,
                            isWorker: isWorker,
                            isSaved: isSaved,
                            applying: applying,
                            withdrawing: withdrawing,
                            hasApplication: hasApplication,
                            canWithdraw: canWithdraw,
                            acceptedApplication: acceptedApplication,
                            onApply: onApply,
                            onToggleSaved: onToggleSaved,
                            onViewCompanyProfile: onViewCompanyProfile,
                            onMessageEmployer: onMessageEmployer,
                            onShowOnMap: onShowOnMap,
                            onWithdraw: onWithdraw,
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _DetailChip(
                                icon: Icons.place_outlined,
                                label: currentJob.fullAddress.isEmpty
                                    ? 'Location not set'
                                    : currentJob.fullAddress,
                              ),
                              _DetailChip(
                                icon: Icons.work_outline,
                                label: webJobWorkFormat(currentJob),
                              ),
                              if (rate != null)
                                _DetailChip(
                                  icon: Icons.payments_outlined,
                                  label: rate,
                                ),
                              _DetailChip(
                                icon: Icons.groups_outlined,
                                label:
                                    '${currentJob.remainingPositions} of ${currentJob.positions} positions',
                              ),
                              if (currentJob.duration.isNotEmpty)
                                _DetailChip(
                                  icon: Icons.schedule_outlined,
                                  label: currentJob.duration,
                                ),
                              if (currentJob.weeklyHours.isNotEmpty)
                                _DetailChip(
                                  icon: Icons.access_time_outlined,
                                  label: '${currentJob.weeklyHours} hours/week',
                                ),
                              _DetailChip(
                                icon: Icons.event_outlined,
                                label:
                                    'Expected start: ${formatJobStartDate(currentJob.startDate)}',
                              ),
                            ],
                          ),
                          if (isEmployerOwner) ...[
                            const SizedBox(height: 22),
                            _OwnerActions(
                              job: currentJob,
                              managing: managing,
                              onEdit: onEdit,
                              onToggleActive: onToggleActive,
                              onDelete: onDelete,
                              onViewApplications: onViewApplications,
                              statsLoader: statsLoader,
                            ),
                          ],
                          const SizedBox(height: 28),
                          if (currentJob.photos.isNotEmpty) ...[
                            _PhotoGrid(
                              jobId: currentJob.id,
                              photos: currentJob.photos,
                            ),
                            const SizedBox(height: 28),
                          ],
                          _Section(
                            title: 'Job Description',
                            body: currentJob.description,
                            fallback: 'No description has been added yet.',
                          ),
                          _Section(
                            title: 'Responsibilities',
                            body: currentJob.responsibilities,
                          ),
                          _Section(
                            title: 'Candidate Requirements',
                            body: currentJob.candidateRequirements,
                          ),
                          _Section(
                            title: 'Required Documents',
                            body: currentJob.requiredDocuments,
                          ),
                          _Section(
                            title: 'Additional Information',
                            body: currentJob.additionalInformation,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final photo = job.photos.isNotEmpty ? job.photos.first.trim() : '';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final avatarFrameSize = compact ? 120.0 : 160.0;
        final avatarSize = avatarFrameSize - 10;
        return Container(
          height: 210,
          color: WebTheme.deep,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photo.isNotEmpty)
                WebRemoteImage(
                  key: ValueKey<String>('job-hero:${job.id}:$photo'),
                  url: photo,
                  fit: BoxFit.cover,
                  fallbackIcon: Icons.image_outlined,
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      WebTheme.deep.withValues(alpha: 0.18),
                      WebTheme.deep.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: compact ? 20 : 28,
                bottom: 20,
                child: Container(
                  width: avatarFrameSize,
                  height: avatarFrameSize,
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: WebTheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: WebCircleImage(
                    key: ValueKey<String>(
                      'job-company-logo:${job.id}:${job.ownerId}',
                    ),
                    url: job.companyLogo,
                    size: avatarSize,
                    fallbackIcon: Icons.business_outlined,
                  ),
                ),
              ),
              Positioned(
                right: compact ? 16 : 20,
                bottom: 20,
                child: webVacancyLifecycleBadge(job),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    required this.job,
    required this.isWorker,
    required this.isSaved,
    required this.applying,
    required this.withdrawing,
    required this.hasApplication,
    required this.canWithdraw,
    required this.acceptedApplication,
    this.onApply,
    this.onToggleSaved,
    this.onViewCompanyProfile,
    this.onMessageEmployer,
    this.onShowOnMap,
    this.onWithdraw,
  });

  final Job job;
  final bool isWorker;
  final bool isSaved;
  final bool applying;
  final bool withdrawing;
  final bool hasApplication;
  final bool canWithdraw;
  final bool acceptedApplication;
  final VoidCallback? onApply;
  final VoidCallback? onToggleSaved;
  final VoidCallback? onViewCompanyProfile;
  final VoidCallback? onMessageEmployer;
  final VoidCallback? onShowOnMap;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.displayTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (job.companyName.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: onViewCompanyProfile,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    alignment: Alignment.centerLeft,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(job.companyName),
                ),
              ],
            ],
          ),
        ),
        if (isWorker) ...[
          const SizedBox(width: WebSpacing.md),
          _WorkerActionsMenu(
            isSaved: isSaved,
            applying: applying,
            withdrawing: withdrawing,
            hasApplication: hasApplication,
            canWithdraw: canWithdraw,
            acceptedApplication: acceptedApplication,
            onApply: onApply,
            onToggleSaved: onToggleSaved,
            onViewCompanyProfile: onViewCompanyProfile,
            onMessageEmployer: onMessageEmployer,
            onShowOnMap: onShowOnMap,
            onWithdraw: onWithdraw,
          ),
        ],
      ],
    );
  }
}

class _WorkerActionsMenu extends StatelessWidget {
  const _WorkerActionsMenu({
    required this.isSaved,
    required this.applying,
    required this.withdrawing,
    required this.hasApplication,
    required this.canWithdraw,
    required this.acceptedApplication,
    this.onApply,
    this.onToggleSaved,
    this.onViewCompanyProfile,
    this.onMessageEmployer,
    this.onShowOnMap,
    this.onWithdraw,
  });

  final bool isSaved;
  final bool applying;
  final bool withdrawing;
  final bool hasApplication;
  final bool canWithdraw;
  final bool acceptedApplication;
  final VoidCallback? onApply;
  final VoidCallback? onToggleSaved;
  final VoidCallback? onViewCompanyProfile;
  final VoidCallback? onMessageEmployer;
  final VoidCallback? onShowOnMap;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final busy = applying || withdrawing;
    return MenuAnchor(
      menuChildren: [
        if (onMessageEmployer != null)
          MenuItemButton(
            onPressed: busy ? null : onMessageEmployer,
            leadingIcon: const Icon(Icons.chat_bubble_outline),
            child: const Text('Message employer'),
          ),
        if (onViewCompanyProfile != null)
          MenuItemButton(
            onPressed: busy ? null : onViewCompanyProfile,
            leadingIcon: const Icon(Icons.business_outlined),
            child: const Text('View company profile'),
          ),
        if (onShowOnMap != null)
          MenuItemButton(
            onPressed: busy ? null : onShowOnMap,
            leadingIcon: const Icon(Icons.map_outlined),
            child: const Text('Show location on map'),
          ),
        if (onToggleSaved != null)
          MenuItemButton(
            onPressed: busy ? null : onToggleSaved,
            leadingIcon: Icon(
              isSaved ? Icons.favorite : Icons.favorite_border,
            ),
            child: Text(isSaved ? 'Remove from saved' : 'Save job'),
          ),
        if (!hasApplication && onApply != null)
          MenuItemButton(
            onPressed: busy ? null : onApply,
            leadingIcon: const Icon(Icons.send_outlined),
            child: const Text('Apply for this job'),
          ),
        if (canWithdraw && onWithdraw != null)
          MenuItemButton(
            onPressed: busy ? null : onWithdraw,
            leadingIcon: const Icon(Icons.undo),
            child: const Text('Withdraw application'),
          ),
      ],
      builder: (context, controller, child) => OutlinedButton.icon(
        onPressed: busy
            ? null
            : controller.isOpen
                ? controller.close
                : controller.open,
        icon: const Icon(Icons.more_horiz),
        label: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Actions'),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.jobId, required this.photos});

  final String jobId;
  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        return InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => _PhotoDialog(photos: photos, initialIndex: index),
          ),
          child: WebRemoteImage(
            key: ValueKey<String>('job-photo:$jobId:${photos[index]}'),
            url: photos[index],
            fit: BoxFit.cover,
            borderRadius: 12,
          ),
        );
      },
    );
  }
}

class _OwnerActions extends StatelessWidget {
  const _OwnerActions({
    required this.job,
    required this.managing,
    this.onEdit,
    this.onToggleActive,
    this.onDelete,
    this.onViewApplications,
    this.statsLoader,
  });

  final Job job;
  final bool managing;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleActive;
  final VoidCallback? onDelete;
  final VoidCallback? onViewApplications;
  final Future<WebJobApplicationStats> Function()? statsLoader;

  @override
  Widget build(BuildContext context) {
    final status = job.status.trim().toLowerCase();
    final pending = job.moderationStatus == 'pending_review';
    final rejected = job.moderationStatus == 'rejected';
    final active =
        status == 'active' || status == 'published' || status == 'open';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(WebRadii.card),
        border: Border.all(color: WebTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Vacancy management',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _OwnerStatusBadge(job: job),
            ],
          ),
          if (pending ||
              rejected ||
              job.moderationReason.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              pending
                  ? 'Pending review'
                  : rejected
                      ? 'Rejected${job.moderationReason.trim().isEmpty ? '' : ': ${job.moderationReason}'}'
                      : job.moderationReason,
              style: TextStyle(
                color: rejected ? Colors.red : WebTheme.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (statsLoader != null)
            FutureBuilder<WebJobApplicationStats>(
              future: statsLoader!(),
              builder: (context, snapshot) {
                final stats = snapshot.data;
                if (stats == null) return const LinearProgressIndicator();
                final left = (job.positions - stats.acceptedSlots)
                    .clamp(0, job.positions)
                    .toInt();
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DetailChip(
                        icon: Icons.assignment_outlined,
                        label: '${stats.total} applications'),
                    _DetailChip(
                        icon: Icons.visibility_outlined,
                        label: '${stats.inReview} in review'),
                    _DetailChip(
                        icon: Icons.local_offer_outlined,
                        label: '${stats.offers} offers'),
                    _DetailChip(
                        icon: Icons.check_circle_outline,
                        label: '${stats.acceptedSlots} hired'),
                    _DetailChip(
                        icon: Icons.groups_outlined,
                        label: '$left/${job.positions} left'),
                  ],
                );
              },
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: managing ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit vacancy'),
              ),
              if (!pending && !rejected)
                OutlinedButton.icon(
                  onPressed: managing ? null : onToggleActive,
                  icon: Icon(active
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline),
                  label: Text(active ? 'Make inactive' : 'Make active'),
                ),
              OutlinedButton.icon(
                onPressed: managing ? null : onViewApplications,
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('View applications'),
              ),
              OutlinedButton.icon(
                onPressed: managing ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OwnerStatusBadge extends StatelessWidget {
  const _OwnerStatusBadge({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    return webVacancyLifecycleBadge(job);
  }
}

class _PhotoDialog extends StatefulWidget {
  const _PhotoDialog({
    required this.photos,
    required this.initialIndex,
  });

  final List<String> photos;
  final int initialIndex;

  @override
  State<_PhotoDialog> createState() => _PhotoDialogState();
}

class _PhotoDialogState extends State<_PhotoDialog> {
  late final PageController controller;

  @override
  void initState() {
    super.initState();
    controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PageView.builder(
            controller: controller,
            itemCount: widget.photos.length,
            itemBuilder: (context, index) {
              return Center(
                child: InteractiveViewer(
                  child: WebRemoteImage(
                    url: widget.photos[index],
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),
          Positioned(
            right: 18,
            top: 18,
            child: IconButton.filled(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: WebTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WebTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: WebTheme.accent),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.body,
    this.fallback,
  });

  final String title;
  final String body;
  final String? fallback;

  @override
  Widget build(BuildContext context) {
    final text = body.trim();
    if (text.isEmpty && fallback == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            text.isEmpty ? fallback! : text,
            style: const TextStyle(
              color: WebTheme.ink,
              fontSize: 15,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
