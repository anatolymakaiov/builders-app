import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/stroyka_background.dart';

enum WebAuthBackdrop { plain, login, recovery }

class WebAuthPageFrame extends StatelessWidget {
  const WebAuthPageFrame({
    super.key,
    required this.child,
    this.maxWidth = 640,
    this.backdrop = WebAuthBackdrop.plain,
  });

  final Widget child;
  final double maxWidth;
  final WebAuthBackdrop backdrop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(maxWidth, constraints.maxWidth - 32);
        return Stack(
          fit: StackFit.expand,
          children: [
            switch (backdrop) {
              WebAuthBackdrop.login => Image.asset(
                  'assets/branding/login_background_stroyka.png',
                  fit: BoxFit.cover,
                  alignment: constraints.maxWidth < 700
                      ? const Alignment(0, -0.5)
                      : Alignment.center,
                ),
              WebAuthBackdrop.recovery => const StroykaBackground(
                  asset: AppAssets.backgroundWorkersCity,
                  child: SizedBox.expand(),
                ),
              WebAuthBackdrop.plain => ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: const SizedBox.expand(),
                ),
            },
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: math.max(0, width),
                height: constraints.maxHeight,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
