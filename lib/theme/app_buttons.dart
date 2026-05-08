import 'package:flutter/material.dart';

import 'app_colors.dart';

class StroykaButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double? width;
  final double? height;

  const StroykaButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return GestureDetector(
      onTap: onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.48,
        child: CustomPaint(
          painter: _ButtonFramePainter(
            color: enabled
                ? AppButtonStyles.frameColor
                : Colors.white.withValues(alpha: 0.34),
          ),
          child: Container(
            width: width,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: AppButtonStyles.primaryFill.withValues(alpha: 0.8),
            ),
            child: Center(
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonFramePainter extends CustomPainter {
  final Color color;

  const _ButtonFramePainter({
    this.color = AppButtonStyles.frameColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const t = 8.0;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    canvas.drawLine(const Offset(-t, 0), const Offset(t, 0), paint);
    canvas.drawLine(const Offset(0, -t), const Offset(0, t), paint);

    canvas.drawLine(
      Offset(size.width - t, 0),
      Offset(size.width + t, 0),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, -t),
      Offset(size.width, t),
      paint,
    );

    canvas.drawLine(
      Offset(-t, size.height),
      Offset(t, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height - t),
      Offset(0, size.height + t),
      paint,
    );

    canvas.drawLine(
      Offset(size.width - t, size.height),
      Offset(size.width + t, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height - t),
      Offset(size.width, size.height + t),
      paint,
    );

    const d = 4.0;
    canvas.drawLine(const Offset(d, 0), const Offset(0, d), paint);
    canvas.drawLine(Offset(size.width - d, 0), Offset(size.width, d), paint);
    canvas.drawLine(Offset(0, size.height - d), Offset(d, size.height), paint);
    canvas.drawLine(
      Offset(size.width, size.height - d),
      Offset(size.width - d, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ButtonFramePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class StroykaButtonBorder extends RoundedRectangleBorder {
  const StroykaButtonBorder({
    super.side = const BorderSide(color: AppButtonStyles.frameColor),
    super.borderRadius = const BorderRadius.all(Radius.circular(2)),
  });

  @override
  RoundedRectangleBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) {
    return StroykaButtonBorder(
      side: side ?? this.side,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    super.paint(canvas, rect, textDirection: textDirection);

    final paint = Paint()
      ..color = side.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = side.width == 0 ? 1.0 : side.width;

    final safeRect = rect.deflate(paint.strokeWidth / 2);
    const t = 8.0;
    const d = 4.0;

    canvas.drawRect(safeRect, paint);

    canvas.drawLine(
      Offset(safeRect.left, safeRect.top),
      Offset(safeRect.left + t, safeRect.top),
      paint,
    );
    canvas.drawLine(
      Offset(safeRect.left, safeRect.top),
      Offset(safeRect.left, safeRect.top + t),
      paint,
    );

    canvas.drawLine(
      Offset(safeRect.right - t, safeRect.top),
      Offset(safeRect.right, safeRect.top),
      paint,
    );
    canvas.drawLine(
      Offset(safeRect.right, safeRect.top),
      Offset(safeRect.right, safeRect.top + t),
      paint,
    );

    canvas.drawLine(
      Offset(safeRect.left, safeRect.bottom - t),
      Offset(safeRect.left, safeRect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(safeRect.left, safeRect.bottom),
      Offset(safeRect.left + t, safeRect.bottom),
      paint,
    );

    canvas.drawLine(
      Offset(safeRect.right - t, safeRect.bottom),
      Offset(safeRect.right, safeRect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(safeRect.right, safeRect.bottom - t),
      Offset(safeRect.right, safeRect.bottom),
      paint,
    );

    canvas.drawLine(
      Offset(safeRect.left + d, safeRect.top),
      Offset(safeRect.left, safeRect.top + d),
      paint,
    );
    canvas.drawLine(
      Offset(safeRect.right - d, safeRect.top),
      Offset(safeRect.right, safeRect.top + d),
      paint,
    );
    canvas.drawLine(
      Offset(safeRect.left, safeRect.bottom - d),
      Offset(safeRect.left + d, safeRect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(safeRect.right, safeRect.bottom - d),
      Offset(safeRect.right - d, safeRect.bottom),
      paint,
    );
  }
}

class AppButtonStyles {
  static const primaryFill = Color(0xFF0D1B2A);
  static const frameColor = Color(0xFF5890FF);

  static ButtonStyle primary({bool compact = true}) {
    return ElevatedButton.styleFrom(
      backgroundColor: primaryFill.withValues(alpha: 0.88),
      foregroundColor: Colors.white,
      disabledBackgroundColor: primaryFill.withValues(alpha: 0.42),
      disabledForegroundColor: Colors.white70,
      elevation: 0,
      minimumSize: Size(0, compact ? 42 : 48),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 20,
        vertical: compact ? 9 : 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
        side: BorderSide(color: frameColor.withValues(alpha: 0.82)),
      ),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 15,
        letterSpacing: 0,
      ),
      shadowColor: frameColor.withValues(alpha: 0.28),
    ).copyWith(
      shape: WidgetStatePropertyAll(
        StroykaButtonBorder(
          side: BorderSide(color: frameColor.withValues(alpha: 0.82)),
        ),
      ),
    );
  }

  static ButtonStyle secondary({bool compact = true, Color? color}) {
    final buttonColor = color ?? frameColor;
    return OutlinedButton.styleFrom(
      foregroundColor: buttonColor,
      backgroundColor: Colors.white.withValues(alpha: 0.78),
      side: BorderSide(color: buttonColor.withValues(alpha: 0.76)),
      minimumSize: Size(0, compact ? 40 : 46),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 8 : 11,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
      ),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 14,
        letterSpacing: 0,
      ),
    ).copyWith(
      shape: WidgetStatePropertyAll(
        StroykaButtonBorder(
          side: BorderSide(color: buttonColor.withValues(alpha: 0.76)),
        ),
      ),
    );
  }

  static ButtonStyle text() {
    return TextButton.styleFrom(
      foregroundColor: AppColors.greenDark,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    ).copyWith(
      shape: WidgetStatePropertyAll(
        StroykaButtonBorder(
          side: BorderSide(color: frameColor.withValues(alpha: 0.45)),
        ),
      ),
    );
  }
}
