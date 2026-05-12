import 'package:flutter/material.dart';

import 'app_blueprint.dart';
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

    return SizedBox(
      width: width,
      height: height ?? 48,
      child: Opacity(
        opacity: enabled ? 1 : 0.48,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: BlueprintDecorationPainter(
                  fillColor: AppButtonStyles.primaryFill,
                  lineColor: enabled
                      ? AppButtonStyles.frameColor
                      : Colors.white.withValues(alpha: 0.34),
                  gridColor: AppButtonStyles.frameColor,
                  radius: 6,
                  subtle: false,
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                splashColor: AppButtonStyles.frameColor.withValues(alpha: 0.3),
                highlightColor: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Center(
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    final painter = BlueprintDecorationPainter(
      fillColor: Colors.transparent,
      lineColor: side.color,
      gridColor: side.color,
      radius: 6,
      subtle: true,
    );
    canvas.save();
    canvas.translate(rect.left, rect.top);
    painter.paint(canvas, rect.size);
    canvas.restore();
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
