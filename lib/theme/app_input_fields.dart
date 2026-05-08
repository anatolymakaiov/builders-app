import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

class StroykaInputField extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final IconData? prefixIcon;
  final bool isPassword;

  const StroykaInputField({
    super.key,
    this.controller,
    required this.hintText,
    this.prefixIcon,
    this.isPassword = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _InputFramePainter(),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
        ),
        child: TextField(
          controller: controller,
          obscureText: isPassword,
          style: const TextStyle(
            color: Color(0xFF1A2B3C),
            fontSize: 16,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: const Color(0xFF1A2B3C).withValues(alpha: 0.5),
            ),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: const Color(0xFF1A2B3C))
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _InputFramePainter extends CustomPainter {
  const _InputFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paintFrame = Paint()
      ..color = const Color(0xFFABB2BF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final paintGrid = Paint()
      ..color = const Color(0xFF5890FF).withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    const t = 6.0;
    const step = 10.0;

    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paintGrid);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paintGrid);
    }

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paintFrame);

    final markPaint = Paint()
      ..color = const Color(0xFFABB2BF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    _drawCorner(canvas, Offset.zero, t, markPaint);
    _drawCorner(canvas, Offset(size.width, 0), t, markPaint);
    _drawCorner(canvas, Offset(0, size.height), t, markPaint);
    _drawCorner(canvas, Offset(size.width, size.height), t, markPaint);
  }

  void _drawCorner(Canvas canvas, Offset center, double t, Paint paint) {
    canvas.drawLine(
      Offset(center.dx - t, center.dy),
      Offset(center.dx + t, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - t),
      Offset(center.dx, center.dy + t),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StroykaDropdown extends StatefulWidget {
  final List<String> items;
  final String value;
  final Function(String?) onChanged;

  const StroykaDropdown({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  @override
  State<StroykaDropdown> createState() => _StroykaDropdownState();
}

class _StroykaDropdownState extends State<StroykaDropdown> {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DropdownFramePainter(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(2),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: widget.value,
            isExpanded: true,
            icon: const Icon(
              Icons.keyboard_arrow_down,
              color: Color(0xFF1A2B3C),
            ),
            style: const TextStyle(
              color: Color(0xFF1A2B3C),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            dropdownColor: Colors.white,
            onChanged: widget.onChanged,
            items: widget.items.map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _DropdownFramePainter extends CustomPainter {
  const _DropdownFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paintFrame = Paint()
      ..color = const Color(0xFFABB2BF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final paintGrid = Paint()
      ..color = const Color(0xFF5890FF).withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    const t = 6.0;
    const step = 8.0;
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paintGrid);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paintGrid);
    }

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paintFrame);

    final markPaint = Paint()
      ..color = const Color(0xFFABB2BF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    _drawTechCorner(canvas, Offset.zero, t, markPaint);
    _drawTechCorner(canvas, Offset(size.width, 0), t, markPaint);
    _drawTechCorner(canvas, Offset(0, size.height), t, markPaint);
    _drawTechCorner(canvas, Offset(size.width, size.height), t, markPaint);
  }

  void _drawTechCorner(Canvas canvas, Offset center, double t, Paint paint) {
    canvas.drawLine(
      Offset(center.dx - t, center.dy),
      Offset(center.dx + t, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - t),
      Offset(center.dx, center.dy + t),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StroykaInputBorder extends OutlineInputBorder {
  const StroykaInputBorder({
    super.borderSide = const BorderSide(
      color: Color(0xFFABB2BF),
      width: 0.5,
    ),
    super.borderRadius = const BorderRadius.all(Radius.circular(4)),
  });

  @override
  OutlineInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) {
    return StroykaInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    final gridPaint = Paint()
      ..color = const Color(0xFF5890FF).withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    const step = 8.0;
    for (double x = rect.left; x < rect.right; x += step) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
    }
    for (double y = rect.top; y < rect.bottom; y += step) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }

    final framePaint = Paint()
      ..color = borderSide.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderSide.width == 0 ? 0.5 : borderSide.width;

    final safeRect = rect.deflate(framePaint.strokeWidth / 2);
    canvas.drawRect(safeRect, framePaint);

    final markPaint = Paint()
      ..color = borderSide.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    const t = 6.0;

    void corner(Offset center) {
      canvas.drawLine(
        Offset(center.dx - t, center.dy),
        Offset(center.dx + t, center.dy),
        markPaint,
      );
      canvas.drawLine(
        Offset(center.dx, center.dy - t),
        Offset(center.dx, center.dy + t),
        markPaint,
      );
    }

    corner(safeRect.topLeft);
    corner(safeRect.topRight);
    corner(safeRect.bottomLeft);
    corner(safeRect.bottomRight);
  }
}

class AppInputFields {
  static InputDecoration decoration({
    String? label,
    String? hint,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      contentPadding: AppSpacing.field,
    );
  }

  static InputDecorationTheme theme() {
    StroykaInputBorder border(Color color, {double width = 1}) {
      return StroykaInputBorder(
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.9),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      labelStyle: const TextStyle(
        color: Color(0xFF1A2B3C),
        fontWeight: FontWeight.w700,
      ),
      hintStyle: const TextStyle(
        color: Color(0x801A2B3C),
        fontWeight: FontWeight.w600,
      ),
      prefixIconColor: const Color(0xFF1A2B3C),
      suffixIconColor: const Color(0xFF1A2B3C),
      border: border(const Color(0xFFABB2BF), width: 0.5),
      enabledBorder: border(const Color(0xFFABB2BF), width: 0.5),
      focusedBorder: border(const Color(0xFF5890FF), width: 1.0),
      errorBorder: border(AppColors.danger.withValues(alpha: 0.72)),
      focusedErrorBorder: border(AppColors.danger, width: 1.4),
    );
  }
}
