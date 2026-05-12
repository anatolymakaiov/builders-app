import 'package:flutter/material.dart';

class BlueprintDecorationPainter extends CustomPainter {
  final Color fillColor;
  final Color lineColor;
  final Color gridColor;
  final double radius;
  final bool drawGrid;
  final bool drawCorners;
  final bool subtle;

  const BlueprintDecorationPainter({
    required this.fillColor,
    required this.lineColor,
    required this.gridColor,
    this.radius = 8,
    this.drawGrid = true,
    this.drawCorners = true,
    this.subtle = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    canvas.drawRRect(rrect, Paint()..color = fillColor);

    canvas.save();
    canvas.clipRRect(rrect);
    if (drawGrid) {
      _drawGrid(canvas, size);
    }
    canvas.restore();

    final borderPaint = Paint()
      ..color = lineColor.withValues(alpha: subtle ? 0.42 : 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = subtle ? 0.8 : 1.05
      ..strokeCap = StrokeCap.square;

    final safeRect = rect.deflate(borderPaint.strokeWidth / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(safeRect, Radius.circular(radius)),
      borderPaint,
    );

    if (drawCorners) {
      _drawCorners(canvas, size);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final minorPaint = Paint()
      ..color = gridColor.withValues(alpha: subtle ? 0.08 : 0.12)
      ..strokeWidth = 0.45;
    final majorPaint = Paint()
      ..color = gridColor.withValues(alpha: subtle ? 0.13 : 0.2)
      ..strokeWidth = 0.7;

    const step = 12.0;
    var index = 0;
    for (double x = 0; x <= size.width; x += step) {
      final paint = index % 4 == 0 ? majorPaint : minorPaint;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      index++;
    }

    index = 0;
    for (double y = 0; y <= size.height; y += step) {
      final paint = index % 4 == 0 ? majorPaint : minorPaint;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      index++;
    }
  }

  void _drawCorners(Canvas canvas, Size size) {
    final cornerPaint = Paint()
      ..color = lineColor.withValues(alpha: subtle ? 0.48 : 0.74)
      ..style = PaintingStyle.stroke
      ..strokeWidth = subtle ? 0.85 : 1.15
      ..strokeCap = StrokeCap.square;

    final w = size.width;
    final h = size.height;
    final long = (h * 0.42).clamp(10.0, 20.0);
    final short = (h * 0.28).clamp(7.0, 14.0);
    final inset = (h * 0.12).clamp(4.0, 8.0);
    final diagonal = (h * 0.24).clamp(7.0, 13.0);

    void drawCorner({
      required bool right,
      required bool bottom,
    }) {
      final x = right ? w - inset : inset;
      final y = bottom ? h - inset : inset;
      final sx = right ? -1.0 : 1.0;
      final sy = bottom ? -1.0 : 1.0;

      canvas.drawLine(Offset(x, y), Offset(x + sx * long, y), cornerPaint);
      canvas.drawLine(Offset(x, y), Offset(x, y + sy * long), cornerPaint);
      canvas.drawLine(
        Offset(x + sx * short, y + sy * short),
        Offset(x + sx * (short + diagonal), y + sy * (short - diagonal)),
        cornerPaint,
      );
    }

    drawCorner(right: false, bottom: false);
    drawCorner(right: true, bottom: false);
    drawCorner(right: false, bottom: true);
    drawCorner(right: true, bottom: true);
  }

  @override
  bool shouldRepaint(covariant BlueprintDecorationPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.radius != radius ||
        oldDelegate.drawGrid != drawGrid ||
        oldDelegate.drawCorners != drawCorners ||
        oldDelegate.subtle != subtle;
  }
}
