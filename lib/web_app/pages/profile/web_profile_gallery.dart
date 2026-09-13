import 'package:flutter/material.dart';

import '../../theme/web_theme.dart';
import '../../widgets/web_remote_image.dart';

class WebProfileGallery extends StatelessWidget {
  const WebProfileGallery({
    super.key,
    required this.urls,
    this.onRemove,
  });

  final List<String> urls;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const Text(
        'No photos yet.',
        style: TextStyle(color: WebTheme.muted),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: urls.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final url = urls[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => _WebGalleryDialog(
                  urls: urls,
                  initialIndex: index,
                ),
              ),
              child: WebRemoteImage(
                url: url,
                fit: BoxFit.cover,
                borderRadius: 12,
              ),
            ),
            if (onRemove != null)
              Positioned(
                right: 6,
                top: 6,
                child: IconButton.filledTonal(
                  tooltip: 'Remove photo',
                  onPressed: () => onRemove!(url),
                  icon: const Icon(Icons.close, size: 17),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(32, 32),
                    fixedSize: const Size(32, 32),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WebGalleryDialog extends StatefulWidget {
  const _WebGalleryDialog({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_WebGalleryDialog> createState() => _WebGalleryDialogState();
}

class _WebGalleryDialogState extends State<_WebGalleryDialog> {
  late final PageController controller;
  late int index;

  @override
  void initState() {
    super.initState();
    index = widget.initialIndex;
    controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PageView.builder(
            controller: controller,
            itemCount: widget.urls.length,
            onPageChanged: (value) => setState(() => index = value),
            itemBuilder: (context, pageIndex) {
              return Center(
                child: InteractiveViewer(
                  minScale: 0.7,
                  maxScale: 4,
                  child: WebRemoteImage(
                    url: widget.urls[pageIndex],
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 20,
            top: 20,
            child: Text(
              '${index + 1} / ${widget.urls.length}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Positioned(
            right: 18,
            top: 18,
            child: IconButton.filled(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }
}
