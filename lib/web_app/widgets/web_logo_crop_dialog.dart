import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;

import '../services/web_profile_edit_service.dart';
import '../theme/web_theme.dart';

class WebLogoCropDialog extends StatefulWidget {
  const WebLogoCropDialog({
    super.key,
    required this.file,
  });

  final WebPickedFile file;

  @override
  State<WebLogoCropDialog> createState() => _WebLogoCropDialogState();
}

class _WebLogoCropDialogState extends State<WebLogoCropDialog> {
  final controller = TransformationController();
  bool processing = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _confirm(double cropSize) async {
    if (processing || widget.file.bytes == null) return;
    setState(() => processing = true);
    try {
      final result = await _cropSquareLogo(
        file: widget.file,
        matrix: controller.value,
        cropSize: cropSize,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      debugPrint('WEB LOGO CROP ERROR $error');
      if (!mounted) return;
      setState(() => processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not crop this logo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cropSize = math.min(MediaQuery.sizeOf(context).width - 96, 360.0);
    return AlertDialog(
      title: const Text('Position company logo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: cropSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipOval(
                  child: InteractiveViewer(
                    transformationController: controller,
                    minScale: 1,
                    maxScale: 5,
                    boundaryMargin: EdgeInsets.zero,
                    trackpadScrollCausesScale: true,
                    child: SizedBox.square(
                      dimension: cropSize,
                      child: Image.memory(
                        widget.file.bytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: WebTheme.accent, width: 3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Drag to position. Pinch or scroll to zoom.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: WebTheme.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: processing ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: processing ? null : () => _confirm(cropSize),
          child: processing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Use logo'),
        ),
      ],
    );
  }
}

Future<WebPickedFile> _cropSquareLogo({
  required WebPickedFile file,
  required Matrix4 matrix,
  required double cropSize,
}) async {
  final decoded = image.decodeImage(file.bytes!);
  if (decoded == null) throw StateError('unsupported_image');
  final source = image.bakeOrientation(decoded);
  final inverse = Matrix4.inverted(matrix);
  final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
  final bottomRight = MatrixUtils.transformPoint(
    inverse,
    Offset(cropSize, cropSize),
  );

  final imageWidth = source.width.toDouble();
  final imageHeight = source.height.toDouble();
  final baseScale = math.max(cropSize / imageWidth, cropSize / imageHeight);
  final fittedLeft = (cropSize - imageWidth * baseScale) / 2;
  final fittedTop = (cropSize - imageHeight * baseScale) / 2;

  final sourceLeft =
      ((topLeft.dx - fittedLeft) / baseScale).clamp(0.0, imageWidth - 1);
  final sourceTop =
      ((topLeft.dy - fittedTop) / baseScale).clamp(0.0, imageHeight - 1);
  final sourceRight = ((bottomRight.dx - fittedLeft) / baseScale)
      .clamp(sourceLeft + 1, imageWidth);
  final sourceBottom = ((bottomRight.dy - fittedTop) / baseScale)
      .clamp(sourceTop + 1, imageHeight);

  final cropped = image.copyCrop(
    source,
    x: sourceLeft.floor(),
    y: sourceTop.floor(),
    width: math.max(1, (sourceRight - sourceLeft).round()),
    height: math.max(1, (sourceBottom - sourceTop).round()),
  );
  final square = image.copyResize(
    cropped,
    width: 768,
    height: 768,
    interpolation: image.Interpolation.average,
  );
  final preserveTransparency = file.contentType == 'image/png';
  final outputBytes = preserveTransparency
      ? image.encodePng(square, level: 6)
      : image.encodeJpg(square, quality: 90);
  final extension = preserveTransparency ? 'png' : 'jpg';
  return WebPickedFile(
    name: 'company_logo.$extension',
    safeName: 'company_logo.$extension',
    extension: extension,
    bytes: Uint8List.fromList(outputBytes),
    contentType: preserveTransparency ? 'image/png' : 'image/jpeg',
  );
}
