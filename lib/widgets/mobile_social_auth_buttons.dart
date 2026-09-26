import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/social_auth_service.dart';

bool showMobileSocialAuthControls({required bool isWeb}) => !isWeb;

class MobileSocialAuthButtons extends StatelessWidget {
  const MobileSocialAuthButtons({
    super.key,
    required this.onSelected,
    this.enabled = true,
  });

  final ValueChanged<SocialProvider> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!showMobileSocialAuthControls(isWeb: kIsWeb)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final provider in SocialProvider.values)
          if (SocialAuthService.available(provider)) ...[
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: enabled ? () => onSelected(provider) : null,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF202B36),
                  side: const BorderSide(color: Color(0xFFB7C5D1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: Row(
                  children: [
                    SizedBox(
                        width: 24,
                        child: Center(child: _ProviderIcon(provider))),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          switch (provider) {
                            SocialProvider.google => 'Continue with Google',
                            SocialProvider.apple => 'Continue with Apple',
                            SocialProvider.facebook => 'Continue with Facebook',
                          },
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
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
