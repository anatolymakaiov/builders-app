import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/web_data_state.dart';
import '../../services/web_profile_data_service.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_remote_image.dart';

class WebProfilePage extends StatelessWidget {
  const WebProfilePage({
    super.key,
    required this.user,
    required this.role,
    required this.profile,
  });

  final User user;
  final String role;
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: WebTheme.surface,
      ),
      body: StreamBuilder<WebDataState<WebProfileData?>>(
        stream: WebProfileDataService().profile(user.uid),
        builder: (context, snapshot) {
          final state = snapshot.data;
          final loaded = state?.data;
          final current = loaded ?? WebProfileData(id: user.uid, data: profile);
          if (state == null || state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return WebPageContainer(
            child: WebPanel(
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProfileHeader(profile: current, role: role),
                    if (state.error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: _ErrorBanner(
                          message: 'Could not refresh profile: ${state.error}',
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(22),
                      child: _ProfileFields(
                        data: current.data,
                        email: user.email ?? '',
                        role: role,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.role,
  });

  final WebProfileData profile;
  final String role;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
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
            _HeaderFallback(role: role),
          Container(color: Colors.black.withValues(alpha: 0.24)),
          Positioned(
            left: 24,
            right: 24,
            bottom: 22,
            child: Row(
              children: [
                WebCircleImage(
                  url: profile.avatarUrl,
                  size: 78,
                  fallbackIcon: role == 'employer'
                      ? Icons.business_outlined
                      : Icons.person_outline,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        role,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderFallback extends StatelessWidget {
  const _HeaderFallback({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: role == 'employer'
          ? const Color(0xFF253044)
          : const Color(0xFF2E3A4F),
    );
  }
}

class _ProfileFields extends StatelessWidget {
  const _ProfileFields({
    required this.data,
    required this.email,
    required this.role,
  });

  final Map<String, dynamic> data;
  final String email;
  final String role;

  @override
  Widget build(BuildContext context) {
    final fields = <MapEntry<String, String>>[
      MapEntry('Email', _value(data, const ['email'], email)),
      MapEntry('Phone', _value(data, const ['phone', 'phoneNumber'], '')),
      MapEntry('Town / City', _value(data, const ['city', 'town'], '')),
      MapEntry('Postcode', _value(data, const ['postcode', 'postCode'], '')),
      if (role == 'employer')
        MapEntry('Company', _value(data, const ['companyName'], ''))
      else
        MapEntry('Trade', _value(data, const ['trade', 'profession'], '')),
      MapEntry('Status', _value(data, const ['status'], 'active')),
    ].where((entry) => entry.value.trim().isNotEmpty).toList();

    return Wrap(
      runSpacing: 16,
      spacing: 16,
      children: fields.map((field) {
        return SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                field.key,
                style: const TextStyle(
                  color: WebTheme.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(field.value, style: const TextStyle(fontSize: 16)),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _value(
    Map<String, dynamic> data,
    List<String> keys,
    String fallback,
  ) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message),
    );
  }
}
