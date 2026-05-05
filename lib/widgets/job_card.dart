import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/job.dart';
import '../screens/job_details_screen.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class JobCard extends StatelessWidget {
  final Job job;
  final VoidCallback? onTap;
  final Widget? trailingAction;
  final Widget? bottomAction;
  final String? statusText;
  final Color? statusColor;
  final String? detailText;
  final bool unread;
  final String? distanceText;
  final EdgeInsetsGeometry margin;
  final bool dense;

  const JobCard({
    super.key,
    required this.job,
    this.onTap,
    this.trailingAction,
    this.bottomAction,
    this.statusText,
    this.statusColor,
    this.detailText,
    this.unread = false,
    this.distanceText,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return StroykaSurface(
      margin: margin,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap ??
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => JobDetailScreen(job: job),
                ),
              );
            },
        child: Padding(
          padding: EdgeInsets.all(dense ? 12 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (unread) ...[
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 8, right: 10),
                      decoration: const BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  Expanded(
                    child: _CompanyHeader(
                      job: job,
                      detailText: detailText,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CompanyLogo(job: job),
                  if (trailingAction != null) ...[
                    const SizedBox(width: 4),
                    trailingAction!,
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MetaChip(label: job.workFormatText),
                  if (job.duration.trim().isNotEmpty)
                    _MetaChip(label: job.duration.trim()),
                  if (job.listRateText.isNotEmpty)
                    _MetaChip(
                      label: job.listRateText,
                      color: AppColors.greenDark,
                    ),
                  if (distanceText != null && distanceText!.isNotEmpty)
                    _MetaChip(label: distanceText!),
                ],
              ),
              if (statusText != null && statusText!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: _MetaChip(
                    label: statusText!,
                    color: statusColor ?? AppColors.greenDark,
                  ),
                ),
              ],
              if (bottomAction != null) ...[
                const SizedBox(height: 10),
                bottomAction!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyHeader extends StatelessWidget {
  final Job job;
  final String? detailText;

  const _CompanyHeader({
    required this.job,
    this.detailText,
  });

  @override
  Widget build(BuildContext context) {
    if (job.ownerId.isEmpty || job.ownerId == "unknown") {
      return _TitleBlock(
        job: job,
        companyName: job.companyName,
        detailText: detailText,
      );
    }

    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection("users").doc(job.ownerId).get(),
      builder: (context, snapshot) {
        String companyName = job.companyName.trim();
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          companyName = (data["companyName"] ?? data["name"] ?? companyName)
              .toString()
              .trim();
        }

        return _TitleBlock(
          job: job,
          companyName: companyName,
          detailText: detailText,
        );
      },
    );
  }
}

class _TitleBlock extends StatelessWidget {
  final Job job;
  final String companyName;
  final String? detailText;

  const _TitleBlock({
    required this.job,
    required this.companyName,
    this.detailText,
  });

  @override
  Widget build(BuildContext context) {
    final location = [
      job.city.trim(),
      job.postcode.trim(),
    ].where((item) => item.isNotEmpty).join(" ");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          job.displayTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w900,
            fontSize: 19,
          ),
        ),
        if (companyName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            companyName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
        if (location.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
        if (detailText != null && detailText!.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            detailText!.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _CompanyLogo extends StatelessWidget {
  final Job job;

  const _CompanyLogo({required this.job});

  @override
  Widget build(BuildContext context) {
    if (job.ownerId.isEmpty || job.ownerId == "unknown") {
      return _Logo(photo: job.companyLogo);
    }

    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection("users").doc(job.ownerId).get(),
      builder: (context, snapshot) {
        String? photo = job.companyLogo;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          photo = (data["photo"] ?? data["companyLogo"] ?? photo)?.toString();
        }

        return _Logo(photo: photo);
      },
    );
  }
}

class _Logo extends StatelessWidget {
  final String? photo;

  const _Logo({this.photo});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photo != null && photo!.trim().isNotEmpty;
    return CircleAvatar(
      radius: 32,
      backgroundColor: Colors.grey.shade300,
      backgroundImage: hasPhoto ? NetworkImage(photo!) : null,
      child: hasPhoto ? null : const Icon(Icons.business, size: 30),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MetaChip({
    required this.label,
    this.color = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
