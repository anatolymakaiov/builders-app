import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_remote_image.dart';

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
  });

  final Job? job;
  final bool isWorker;
  final bool isEmployerOwner;
  final bool isSaved;
  final bool applying;
  final VoidCallback? onApply;
  final VoidCallback? onToggleSaved;
  final VoidCallback? onViewCompanyProfile;

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
    return WebPanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Hero(job: currentJob),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WebCircleImage(
                          url: currentJob.companyLogo,
                          size: 58,
                          fallbackIcon: Icons.business_outlined,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentJob.displayTitle,
                                style:
                                    Theme.of(context).textTheme.headlineMedium,
                              ),
                              if (currentJob.companyName.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  currentJob.companyName,
                                  style: const TextStyle(
                                    color: WebTheme.muted,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
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
                        if (currentJob.rateText.isNotEmpty)
                          _DetailChip(
                            icon: Icons.payments_outlined,
                            label: currentJob.rateText,
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
                        if (currentJob.startDate != null)
                          _DetailChip(
                            icon: Icons.event_outlined,
                            label:
                                'Starts ${_formatDate(currentJob.startDate!)}',
                          ),
                        _DetailChip(
                          icon: Icons.verified_outlined,
                          label: isEmployerOwner
                              ? currentJob.moderationLabel
                              : 'Public vacancy',
                        ),
                      ],
                    ),
                    if (isWorker) ...[
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: applying ? null : onApply,
                            icon: applying
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_outlined),
                            label: const Text('Apply'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: onToggleSaved,
                            icon: Icon(isSaved
                                ? Icons.favorite
                                : Icons.favorite_border),
                            label: Text(isSaved ? 'Saved' : 'Save'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: onViewCompanyProfile,
                            icon: const Icon(Icons.business_outlined),
                            label: const Text('View company profile'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 28),
                    if (currentJob.photos.isNotEmpty) ...[
                      _PhotoGrid(photos: currentJob.photos),
                      const SizedBox(height: 28),
                    ],
                    _Section(
                      title: 'Description',
                      body: currentJob.description,
                      fallback: 'No description has been added yet.',
                    ),
                    _Section(
                      title: 'Responsibilities',
                      body: currentJob.responsibilities,
                    ),
                    _Section(
                      title: 'Candidate requirements',
                      body: currentJob.candidateRequirements,
                    ),
                    _Section(
                      title: 'Required documents',
                      body: currentJob.requiredDocuments,
                    ),
                    _Section(
                      title: 'Additional information',
                      body: currentJob.additionalInformation,
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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final photo = job.photos.isNotEmpty ? job.photos.first.trim() : '';
    return Container(
      height: 210,
      color: WebTheme.deep,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo.isNotEmpty)
            WebRemoteImage(
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
            left: 28,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: WebTheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                job.moderationLabel,
                style: const TextStyle(
                  color: WebTheme.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.photos});

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
            url: photos[index],
            fit: BoxFit.cover,
            borderRadius: 12,
          ),
        );
      },
    );
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
          Icon(icon, size: 17, color: WebTheme.green),
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
