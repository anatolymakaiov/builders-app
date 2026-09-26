import 'package:flutter/material.dart';

import '../../services/worker_availability_service.dart';
import '../services/web_profile_data_service.dart';
import '../theme/web_theme.dart';
import '../widgets/web_remote_image.dart';

class PortraitWorkerProfileHeader extends StatelessWidget {
  const PortraitWorkerProfileHeader({
    super.key,
    required this.profile,
    required this.ownProfile,
    required this.mediaBusy,
    this.onBack,
    this.onEdit,
    this.onChangeAvatar,
    this.onChangeHeader,
    this.onSwitchAccount,
    this.onAvailabilityChanged,
  });

  final WebProfileData profile;
  final bool ownProfile;
  final bool mediaBusy;
  final VoidCallback? onBack;
  final VoidCallback? onEdit;
  final VoidCallback? onChangeAvatar;
  final VoidCallback? onChangeHeader;
  final VoidCallback? onSwitchAccount;
  final ValueChanged<WorkerAvailability>? onAvailabilityChanged;

  @override
  Widget build(BuildContext context) {
    final availability = WorkerAvailabilityService.fromProfile(profile.data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 156,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (profile.headerUrl.isNotEmpty)
                WebRemoteImage(
                  url: profile.headerUrl,
                  fit: BoxFit.cover,
                  fallbackIcon: Icons.image_outlined,
                )
              else
                const ColoredBox(color: WebTheme.deep),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      WebTheme.deep.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: onBack == null || ownProfile
                    ? const SizedBox.shrink()
                    : IconButton.filledTonal(
                        tooltip: 'Back',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onChangeHeader != null)
                      IconButton.filledTonal(
                        tooltip: 'Change header',
                        onPressed: mediaBusy ? null : onChangeHeader,
                        icon:
                            const Icon(Icons.photo_size_select_actual_outlined),
                      ),
                    if (onEdit != null)
                      IconButton.filledTonal(
                        tooltip: 'Edit profile',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (onSwitchAccount != null)
                      IconButton.filledTonal(
                        tooltip: 'Switch account',
                        onPressed: onSwitchAccount,
                        icon: const Icon(Icons.swap_horiz),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                children: [
                  WebCircleImage(
                    url: profile.avatarUrl,
                    size: 76,
                    fallbackIcon: Icons.person_outline,
                  ),
                  if (onChangeAvatar != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: IconButton.filled(
                        tooltip: 'Change avatar',
                        onPressed: mediaBusy ? null : onChangeAvatar,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: const EdgeInsets.all(5),
                        icon: mediaBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.photo_camera_outlined, size: 18),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WebTheme.ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      ownProfile ? 'Your worker profile' : 'Worker profile',
                      style:
                          const TextStyle(color: WebTheme.muted, fontSize: 13),
                    ),
                    if (onAvailabilityChanged == null)
                      Text(
                        WorkerAvailabilityService.label(availability),
                        style: const TextStyle(
                          color: WebTheme.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      PopupMenuButton<WorkerAvailability>(
                        tooltip: 'Change availability',
                        onSelected: onAvailabilityChanged,
                        itemBuilder: (_) => [
                          for (final status in WorkerAvailability.values)
                            PopupMenuItem(
                              value: status,
                              child:
                                  Text(WorkerAvailabilityService.label(status)),
                            ),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              WorkerAvailabilityService.label(availability),
                              style: const TextStyle(
                                color: WebTheme.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down,
                                color: WebTheme.accent),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
