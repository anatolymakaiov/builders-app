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
    this.drawCorners = false,
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
