import 'dart:async';

import 'package:flutter/material.dart';

class StroykaActionFeedback {
  static OverlayEntry? _entry;

  static void showSuccess(
    BuildContext context, {
    String semanticLabel = "Action completed successfully",
  }) {
    _show(
      context,
      _ActionFeedbackStyle.success,
      semanticLabel: semanticLabel,
    );
  }

  static void showError(
    BuildContext context, {
    required String message,
    String semanticLabel = "Action failed",
  }) {
    _show(
      context,
      _ActionFeedbackStyle.error,
      semanticLabel: semanticLabel,
    );
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  static void _show(
    BuildContext context,
    _ActionFeedbackStyle style, {
    required String semanticLabel,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _entry?.remove();
    _entry = OverlayEntry(
      builder: (context) => _ActionFeedbackOverlay(
        style: style,
        semanticLabel: semanticLabel,
        onDismissed: () {
          _entry?.remove();
          _entry = null;
        },
      ),
    );
    overlay.insert(_entry!);
  }
}

enum _ActionFeedbackStyle { success, error }

class _ActionFeedbackOverlay extends StatefulWidget {
  final _ActionFeedbackStyle style;
  final String semanticLabel;
  final VoidCallback onDismissed;

  const _ActionFeedbackOverlay({
    required this.style,
    required this.semanticLabel,
    required this.onDismissed,
  });

  @override
  State<_ActionFeedbackOverlay> createState() => _ActionFeedbackOverlayState();
}

class _ActionFeedbackOverlayState extends State<_ActionFeedbackOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> opacity;
  late final Animation<double> scale;
  Timer? timer;
  bool dismissed = false;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
    );
    opacity = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.85, end: 1.05)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.05, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 30,
      ),
    ]).animate(controller);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        controller.value = 1;
        timer = Timer(const Duration(milliseconds: 900), dismiss);
      } else {
        controller.forward();
        timer = Timer(const Duration(milliseconds: 820), () async {
          if (!mounted) return;
          await controller.reverse();
          dismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Semantics(
        label: widget.semanticLabel,
        liveRegion: true,
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: FadeTransition(
              opacity: opacity,
              child: ScaleTransition(
                scale: scale,
                child: widget.style == _ActionFeedbackStyle.success
                    ? const _DoneMark()
                    : const _ErrorMark(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DoneMark extends StatelessWidget {
  const _DoneMark();

  @override
  Widget build(BuildContext context) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFF39FF88);

    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF39FF88).withValues(alpha: 0.34),
            blurRadius: 28,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Text(
        "DONE",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 54,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
          foreground: stroke,
          shadows: const [
            Shadow(
              color: Color(0xAA39FF88),
              blurRadius: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorMark extends StatelessWidget {
  const _ErrorMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFFF5A5F),
          width: 2.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF5A5F).withValues(alpha: 0.24),
            blurRadius: 22,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Text(
        "!",
        style: TextStyle(
          fontSize: 58,
          fontWeight: FontWeight.w800,
          color: Colors.transparent,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.9
            ..color = const Color(0xFFFF5A5F),
        ),
      ),
    );
  }
}
