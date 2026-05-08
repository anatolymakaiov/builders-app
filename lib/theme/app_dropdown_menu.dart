import 'package:flutter/material.dart';

import 'app_colors.dart';

class StroykaDropdownMenu extends StatelessWidget {
  final List<String> items;
  final Function(String) onSelect;

  const StroykaDropdownMenu({
    super.key,
    required this.items,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _MenuFramePainter(),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 250),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: items.map((item) {
            return InkWell(
              onTap: () => onSelect(item),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: const Color(0xFF1A2B3C).withValues(alpha: 0.05),
                      width: 1,
                    ),
                  ),
                ),
                child: Text(
                  item,
                  style: const TextStyle(
                    color: Color(0xFF1A2B3C),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class StroykaMenuAction<T> {
  final T value;
  final String label;
  final IconData? icon;
  final bool danger;

  const StroykaMenuAction({
    required this.value,
    required this.label,
    this.icon,
    this.danger = false,
  });
}

class StroykaPopupMenuButton<T> extends StatelessWidget {
  final List<StroykaMenuAction<T>> actions;
  final ValueChanged<T> onSelected;
  final Widget? icon;
  final bool enabled;
  final String? tooltip;

  const StroykaPopupMenuButton({
    super.key,
    required this.actions,
    required this.onSelected,
    this.icon,
    this.enabled = true,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      enabled: enabled && actions.isNotEmpty,
      icon: icon ?? const Icon(Icons.more_horiz, color: AppColors.ink),
      color: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (context) {
        return [
          _StroykaPopupMenuEntry<T>(actions: actions),
        ];
      },
    );
  }
}

class _StroykaPopupMenuEntry<T> extends PopupMenuEntry<T> {
  final List<StroykaMenuAction<T>> actions;

  const _StroykaPopupMenuEntry({
    required this.actions,
  });

  @override
  double get height => actions.length * 48.0;

  @override
  bool represents(T? value) => false;

  @override
  State<_StroykaPopupMenuEntry<T>> createState() =>
      _StroykaPopupMenuEntryState<T>();
}

class _StroykaPopupMenuEntryState<T> extends State<_StroykaPopupMenuEntry<T>> {
  @override
  Widget build(BuildContext context) {
    return _StroykaActionMenu<T>(actions: widget.actions);
  }
}

class _StroykaActionMenu<T> extends StatelessWidget {
  final List<StroykaMenuAction<T>> actions;

  const _StroykaActionMenu({
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _MenuFramePainter(),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 250),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++)
              InkWell(
                onTap: () => Navigator.pop<T>(context, actions[i].value),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: const Color(0xFF1A2B3C).withValues(alpha: 0.05),
                        width: i == actions.length - 1 ? 0 : 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (actions[i].icon != null) ...[
                        Icon(
                          actions[i].icon,
                          size: 18,
                          color: actions[i].danger
                              ? AppColors.danger
                              : const Color(0xFF1A2B3C),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          actions[i].label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: actions[i].danger
                                ? AppColors.danger
                                : const Color(0xFF1A2B3C),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuFramePainter extends CustomPainter {
  const _MenuFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paintFrame = Paint()
      ..color = const Color(0xFFABB2BF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final paintGrid = Paint()
      ..color = const Color(0xFF5890FF).withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    const step = 12.0;

    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paintGrid);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paintGrid);
    }

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paintFrame);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
