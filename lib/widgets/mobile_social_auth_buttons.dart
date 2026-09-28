import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/social_auth_service.dart';

bool showMobileSocialAuthControls({required bool isWeb}) => !isWeb;

class MobileSocialAuthButtons extends StatelessWidget {
  const MobileSocialAuthButtons({
    super.key,
    required this.onEmail,
    required this.onSelected,
    this.enabled = true,
    this.registration = false,
  });

  final VoidCallback onEmail;
  final ValueChanged<SocialProvider> onSelected;
  final bool enabled;
  final bool registration;

  @override
  Widget build(BuildContext context) {
    if (!showMobileSocialAuthControls(isWeb: kIsWeb)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          registration ? 'Register with' : 'Sign in with',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: const Color(0xFF202B36),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ProviderButton(
              tooltip:
                  registration ? 'Register with email' : 'Sign in with email',
              onPressed: enabled ? onEmail : null,
              icon: const Icon(Icons.mail_outline, size: 24),
            ),
            for (final provider in const [
              SocialProvider.google,
              SocialProvider.facebook,
              SocialProvider.apple,
            ])
              if (SocialAuthService.available(provider)) ...[
                const SizedBox(width: 8),
                _ProviderButton(
                  tooltip: switch (provider) {
                    SocialProvider.google => 'Continue with Google',
                    SocialProvider.apple => 'Continue with Apple',
                    SocialProvider.facebook => 'Continue with Facebook',
                  },
                  onPressed: enabled ? () => onSelected(provider) : null,
                  icon: _ProviderIcon(provider),
                ),
              ],
          ],
        ),
      ],
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 48,
        height: 48,
        child: IconButton.outlined(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: icon,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF202B36),
            side: const BorderSide(color: Color(0xFFB7C5D1)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      );
}

class _ProviderIcon extends StatelessWidget {
  const _ProviderIcon(this.provider);

  final SocialProvider provider;

  @override
  Widget build(BuildContext context) => switch (provider) {
        SocialProvider.google => Image.asset(
            'assets/branding/google_g_official.png',
            width: 24,
            height: 24,
            excludeFromSemantics: true,
          ),
        SocialProvider.apple => const Icon(Icons.apple, size: 24),
        SocialProvider.facebook => const Icon(
            Icons.facebook,
            size: 24,
            color: Color(0xFF1877F2),
          ),
      };
}
