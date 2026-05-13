import 'package:flutter/material.dart';

import 'app_blueprint.dart';
import 'app_cards.dart';
import 'app_colors.dart';

class StroykaAvatar extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;
  final double size;
  final Color backgroundColor;

  const StroykaAvatar({
    super.key,
    this.imageUrl,
    required this.fallbackIcon,
    this.size = 88,
    this.backgroundColor = AppColors.surfaceAlt,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    final hasImage = url != null && url.isNotEmpty;

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: backgroundColor,
      backgroundImage: hasImage ? NetworkImage(url) : null,
      child: hasImage
          ? null
          : Icon(
              fallbackIcon,
              size: size * 0.44,
              color: AppColors.greenDark,
            ),
    );
  }
}

class StroykaProfileHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? avatarUrl;
  final String? headerImageUrl;
  final IconData fallbackIcon;
  final Widget? headerControls;
  final EdgeInsetsGeometry margin;
  final double avatarSize;

  const StroykaProfileHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.avatarUrl,
    this.headerImageUrl,
    required this.fallbackIcon,
    this.headerControls,
    this.margin = const EdgeInsets.fromLTRB(12, 12, 12, 10),
    this.avatarSize = 88,
  });

  @override
  Widget build(BuildContext context) {
    final headerImage = headerImageUrl?.trim();
    final hasHeaderImage = headerImage != null && headerImage.isNotEmpty;
    final hasControls = headerControls != null;

    return AppCard(
      margin: margin,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: hasControls ? 202 : 188,
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: hasHeaderImage
                  ? DecorationImage(
                      image: NetworkImage(headerImage),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.16),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.92),
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasControls)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: headerControls!,
                        ),
                      Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: hasControls ? 8 : 0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StroykaAvatar(
                                imageUrl: avatarUrl,
                                fallbackIcon: fallbackIcon,
                                size: avatarSize,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.ink,
                                ),
                              ),
                              if (subtitle != null &&
                                  subtitle!.trim().isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  subtitle!.trim(),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StroykaTabBar extends StatelessWidget {
  final List<String> labels;
  final EdgeInsetsGeometry margin;

  const StroykaTabBar({
    super.key,
    required this.labels,
    this.margin = const EdgeInsets.symmetric(horizontal: 12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: CustomPaint(
        painter: BlueprintDecorationPainter(
          fillColor: AppColors.surface.withValues(alpha: 0.92),
          lineColor: AppColors.blueprintLine,
          gridColor: AppColors.blueprintLine,
          radius: 999,
          subtle: true,
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: TabBar(
            dividerColor: Colors.transparent,
            indicator: const BoxDecoration(
              color: AppColors.green,
              borderRadius: BorderRadius.all(Radius.circular(999)),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.ink,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
            tabs: [
              for (final label in labels)
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
