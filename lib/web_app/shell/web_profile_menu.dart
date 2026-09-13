import 'package:flutter/material.dart';

import '../theme/web_theme.dart';

class WebProfileAvatar extends StatelessWidget {
  const WebProfileAvatar({
    super.key,
    required this.profile,
  });

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final photo = (profile['avatarUrl'] ??
            profile['photo'] ??
            profile['companyLogo'] ??
            profile['profilePhotoUrl'])
        ?.toString()
        .trim();

    return CircleAvatar(
      radius: 20,
      backgroundColor: WebTheme.greenSoft,
      child: photo == null || photo.isEmpty
          ? const Icon(Icons.person_outline, color: WebTheme.green)
          : ClipOval(
              child: Image.network(
                photo,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                errorBuilder: (_, __, ___) {
                  return const Icon(
                    Icons.person_outline,
                    color: WebTheme.green,
                  );
                },
              ),
            ),
    );
  }
}
