import 'package:flutter/material.dart';

import '../theme/web_theme.dart';

class WebPageHeader extends StatelessWidget {
  const WebPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackActions = constraints.maxWidth < 760 && actions.isNotEmpty;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: WebTypography.pageTitle),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: WebSpacing.xxs),
              Text(subtitle!, style: WebTypography.metadata),
            ],
          ],
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: WebSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: WebSpacing.sm),
                  ],
                  Expanded(child: heading),
                  if (!stackActions && actions.isNotEmpty)
                    Wrap(
                      spacing: WebSpacing.sm,
                      runSpacing: WebSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions,
                    ),
                ],
              ),
              if (stackActions) ...[
                const SizedBox(height: WebSpacing.md),
                Wrap(
                  spacing: WebSpacing.sm,
                  runSpacing: WebSpacing.xs,
                  children: actions,
                ),
              ],
              if (bottom != null) ...[
                const SizedBox(height: WebSpacing.md),
                bottom!,
              ],
            ],
          ),
        );
      },
    );
  }
}

class WebCompactDetailView extends StatelessWidget {
  const WebCompactDetailView({
    super.key,
    required this.showDetail,
    required this.list,
    required this.detail,
    required this.onBack,
    this.backLabel = 'Back to results',
  });

  final bool showDetail;
  final Widget list;
  final Widget detail;
  final VoidCallback onBack;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    if (!showDetail) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: Text(backLabel),
          ),
        ),
        const SizedBox(height: WebSpacing.xs),
        Expanded(child: detail),
      ],
    );
  }
}

class WebDialogScrollArea extends StatelessWidget {
  const WebDialogScrollArea({
    super.key,
    required this.child,
    required this.preferredWidth,
    this.maxHeightFactor = .72,
  });

  final Widget child;
  final double preferredWidth;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final availableWidth =
        (viewport.width - 80).clamp(280.0, preferredWidth).toDouble();
    return SizedBox(
      width: availableWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: viewport.height * maxHeightFactor,
        ),
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}

enum WebStatusTone { success, warning, danger, info, neutral }

class WebStatusChip extends StatelessWidget {
  const WebStatusChip({
    super.key,
    required this.label,
    this.tone,
    this.icon,
  });

  final String label;
  final WebStatusTone? tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final resolved = tone ?? webStatusTone(label);
    final colors = switch (resolved) {
      WebStatusTone.success => (WebTheme.success, WebTheme.greenSoft),
      WebStatusTone.warning => (WebTheme.warning, WebTheme.warningSoft),
      WebStatusTone.danger => (WebTheme.danger, WebTheme.dangerSoft),
      WebStatusTone.info => (WebTheme.info, WebTheme.infoSoft),
      WebStatusTone.neutral => (WebTheme.muted, WebTheme.surfaceAlt),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: colors.$2,
        borderRadius: BorderRadius.circular(WebRadii.tag),
        border: Border.all(color: colors.$1.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.$1),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: WebTypography.label.copyWith(color: colors.$1),
          ),
        ],
      ),
    );
  }
}

WebStatusTone webStatusTone(String status) {
  final value = status.trim().toLowerCase().replaceAll('-', '_');
  if (value.contains('accept') ||
      value.contains('active') ||
      value.contains('approved') ||
      value.contains('paid') ||
      value.contains('hired') ||
      value.contains('success')) {
    return WebStatusTone.success;
  }
  if (value.contains('pending') ||
      value.contains('review') ||
      value.contains('negotiat') ||
      value.contains('grace') ||
      value.contains('await')) {
    return WebStatusTone.warning;
  }
  if (value.contains('reject') ||
      value.contains('fail') ||
      value.contains('suspend') ||
      value.contains('deleted') ||
      value.contains('cancel')) {
    return WebStatusTone.danger;
  }
  if (value.contains('offer') ||
      value.contains('scheduled') ||
      value.contains('new')) {
    return WebStatusTone.info;
  }
  return WebStatusTone.neutral;
}

class WebLoadingState extends StatelessWidget {
  const WebLoadingState({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          if (label != null) ...[
            const SizedBox(height: WebSpacing.sm),
            Text(label!, style: WebTypography.metadata),
          ],
        ],
      ),
    );
  }
}

class WebEmptyState extends StatelessWidget {
  const WebEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(WebSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 34, color: WebTheme.subtleText),
              const SizedBox(height: WebSpacing.sm),
              Text(title, style: WebTypography.panelTitle),
              if (message != null) ...[
                const SizedBox(height: WebSpacing.xs),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: WebTypography.metadata,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: WebSpacing.md),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class WebErrorState extends StatelessWidget {
  const WebErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? WebSpacing.sm : WebSpacing.md),
      decoration: BoxDecoration(
        color: WebTheme.dangerSoft,
        borderRadius: BorderRadius.circular(WebRadii.card),
        border: Border.all(color: WebTheme.danger.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: WebTheme.danger, size: 20),
          const SizedBox(width: WebSpacing.sm),
          Expanded(child: Text(message, style: WebTypography.body)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
