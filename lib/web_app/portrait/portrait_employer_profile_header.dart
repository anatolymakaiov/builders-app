import 'package:flutter/material.dart';

import '../services/web_profile_data_service.dart';
import '../theme/web_theme.dart';
import '../widgets/web_remote_image.dart';

class PortraitEmployerProfileHeader extends StatelessWidget {
  const PortraitEmployerProfileHeader({
    super.key,
    required this.profile,
    required this.ownProfile,
    required this.mediaBusy,
    this.onBack,
    this.onEdit,
    this.onChangeAvatar,
    this.onChangeHeader,
    this.onSwitchAccount,
  });

  final WebProfileData profile;
  final bool ownProfile;
  final bool mediaBusy;
  final VoidCallback? onBack;
  final VoidCallback? onEdit;
  final VoidCallback? onChangeAvatar;
  final VoidCallback? onChangeHeader;
  final VoidCallback? onSwitchAccount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 164,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (profile.headerUrl.isNotEmpty)
                WebRemoteImage(
                  url: profile.headerUrl,
                  fit: BoxFit.cover,
                  fallbackIcon: Icons.business_outlined,
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
              if (!ownProfile && onBack != null)
                Positioned(
                  left: 8,
                  top: 8,
                  child: IconButton.filledTonal(
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
                        tooltip: 'Edit company profile',
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
            children: [
              Stack(
                children: [
                  WebCircleImage(
                    url: profile.avatarUrl,
                    size: 76,
                    fallbackIcon: Icons.business_outlined,
                  ),
                  if (onChangeAvatar != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: IconButton.filled(
                        tooltip: 'Change logo',
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
                      ownProfile ? 'Your company profile' : 'Company profile',
                      style: const TextStyle(
                        color: WebTheme.muted,
                        fontSize: 13,
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
