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
    final rect = Offset.zero & size;

    final backgroundPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF003B73),
          Color(0xFF00315F),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);

    final borderPaint = Paint()
      ..color = const Color(0xFFE7EAF2)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final gridMinor = Paint()
      ..color = const Color(0x143A82C5)
      ..strokeWidth = 0.6;

    final gridMajor = Paint()
      ..color = const Color(0x223A82C5)
      ..strokeWidth = 1;

    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(8),
    );

    canvas.drawRRect(rrect, backgroundPaint);

    canvas.save();
    canvas.clipRRect(rrect);

    const grid = 18.0;

    for (double x = 0; x < size.width; x += grid) {
      final isMajor = ((x / grid).round() % 4) == 0;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? gridMajor : gridMinor,
      );
    }

    for (double y = 0; y < size.height; y += grid) {
      final isMajor = ((y / grid).round() % 4) == 0;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        isMajor ? gridMajor : gridMinor,
      );
    }

    canvas.restore();

    final w = size.width;
    final h = size.height;

    canvas.drawLine(const Offset(28, 5), Offset(w - 28, 5), borderPaint);
    canvas.drawLine(Offset(28, h - 5), Offset(w - 28, h - 5), borderPaint);
    canvas.drawLine(const Offset(5, 30), Offset(5, h - 30), borderPaint);
    canvas.drawLine(Offset(w - 5, 30), Offset(w - 5, h - 30), borderPaint);

    canvas.drawLine(const Offset(24, -6), const Offset(24, 44), borderPaint);
    canvas.drawLine(const Offset(24, 24), const Offset(72, 24), borderPaint);
    canvas.drawLine(const Offset(-8, 48), const Offset(48, -8), borderPaint);

    canvas.drawLine(Offset(w - 24, -6), Offset(w - 24, 44), borderPaint);
    canvas.drawLine(Offset(w - 72, 24), Offset(w - 24, 24), borderPaint);
    canvas.drawLine(Offset(w + 8, 48), Offset(w - 48, -8), borderPaint);

    canvas.drawLine(Offset(24, h + 6), Offset(24, h - 44), borderPaint);
    canvas.drawLine(Offset(24, h - 24), Offset(72, h - 24), borderPaint);
    canvas.drawLine(Offset(-8, h - 48), Offset(48, h + 8), borderPaint);

    canvas.drawLine(Offset(w - 24, h + 6), Offset(w - 24, h - 44), borderPaint);
    canvas.drawLine(
        Offset(w - 72, h - 24), Offset(w - 24, h - 24), borderPaint);
    canvas.drawLine(Offset(w + 8, h - 48), Offset(w - 48, h + 8), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
