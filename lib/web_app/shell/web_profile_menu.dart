import 'package:flutter/material.dart';

import '../theme/web_theme.dart';
import '../widgets/web_remote_image.dart';

class WebProfileAvatar extends StatelessWidget {
  const WebProfileAvatar({
    super.key,
    required this.profile,
    this.role,
  });

  final Map<String, dynamic> profile;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final isEmployer = role == 'employer';
    final photo = (isEmployer
            ? profile['companyLogoUrl'] ??
                profile['companyLogo'] ??
                profile['companyAvatarUrl'] ??
                profile['logo'] ??
                profile['avatarUrl'] ??
                profile['photoUrl'] ??
                profile['photo']
            : profile['avatarUrl'] ??
                profile['profilePhotoUrl'] ??
                profile['photoUrl'] ??
                profile['photo'])
        ?.toString()
        .trim();

    return CircleAvatar(
      radius: 20,
      backgroundColor: WebTheme.accentSoft,
      child: photo == null || photo.isEmpty
          ? const Icon(Icons.person_outline, color: WebTheme.accent)
          : ClipOval(
              child: WebRemoteImage(
                url: photo,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                fallbackIcon: Icons.person_outline,
              ),
            ),
    );
  }
}
