import 'package:flutter/material.dart';

class BlueprintFrame extends StatelessWidget {
  final Widget child;
  final double height;
  final VoidCallback? onTap;

  const BlueprintFrame({
    super.key,
    required this.child,
    this.height = 64,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: const _BlueprintPainter(),
          child: Container(
            height: height,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _BlueprintPainter extends CustomPainter {
  const _BlueprintPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const designWidth = 2048.0;
    const designHeight = 512.0;

    final backgroundPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF062E4B),
          Color(0xFF052238),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(const Rect.fromLTWH(0, 0, designWidth, designHeight));

    final gridMinor = Paint()
      ..color = const Color(0xFF2F86BE).withValues(alpha: 0.26)
      ..strokeWidth = 1.2;

    final gridMajor = Paint()
      ..color = const Color(0xFF2F86BE).withValues(alpha: 0.46)
      ..strokeWidth = 2.0;

    final panelPaint = Paint()
      ..color = const Color(0xFF073F67).withValues(alpha: 0.78);

    final panelEdgePaint = Paint()
      ..color = const Color(0xFF0D5D8D).withValues(alpha: 0.76)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0;

    final framePaint = Paint()
      ..color = const Color(0xFFE6ECF4)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    canvas.save();
    canvas.scale(size.width / designWidth, size.height / designHeight);

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, designWidth, designHeight),
      backgroundPaint,
    );

    final panel = RRect.fromRectAndRadius(
      const Rect.fromLTWH(75, 58, 1898, 438),
      const Radius.circular(10),
    );
    canvas.drawRRect(panel, panelPaint);
    canvas.drawRRect(panel, panelEdgePaint);

    canvas.save();
    canvas.clipRRect(panel);

    const grid = 56.0;
    for (double x = 83; x <= 1968; x += grid) {
      final isMajor = (((x - 83) / grid).round() % 4) == 0;
      canvas.drawLine(
        Offset(x, 63),
        Offset(x, 490),
        isMajor ? gridMajor : gridMinor,
      );
    }

    for (double y = 87; y <= 480; y += grid) {
      final isMajor = (((y - 87) / grid).round() % 4) == 0;
      canvas.drawLine(
        Offset(82, y),
        Offset(1966, y),
        isMajor ? gridMajor : gridMinor,
      );
    }

    canvas.restore();

    canvas.drawLine(const Offset(125, 68), const Offset(1924, 68), framePaint);
    canvas.drawLine(
        const Offset(125, 488), const Offset(1924, 488), framePaint);
    canvas.drawLine(const Offset(92, 114), const Offset(92, 397), framePaint);
    canvas.drawLine(
        const Offset(1924, 114), const Offset(1924, 397), framePaint);

    canvas.drawLine(const Offset(125, 40), const Offset(125, 165), framePaint);
    canvas.drawLine(const Offset(125, 108), const Offset(218, 108), framePaint);
    canvas.drawLine(const Offset(52, 162), const Offset(179, 36), framePaint);

    canvas.drawLine(
        const Offset(1922, 36), const Offset(1922, 165), framePaint);
    canvas.drawLine(
        const Offset(1830, 108), const Offset(1922, 108), framePaint);
    canvas.drawLine(
        const Offset(1868, 36), const Offset(1995, 162), framePaint);

    canvas.drawLine(const Offset(125, 391), const Offset(125, 515), framePaint);
    canvas.drawLine(const Offset(125, 449), const Offset(218, 449), framePaint);
    canvas.drawLine(const Offset(52, 394), const Offset(179, 520), framePaint);

    canvas.drawLine(
        const Offset(1922, 391), const Offset(1922, 515), framePaint);
    canvas.drawLine(
        const Offset(1830, 449), const Offset(1922, 449), framePaint);
    canvas.drawLine(
        const Offset(1868, 520), const Offset(1995, 394), framePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
