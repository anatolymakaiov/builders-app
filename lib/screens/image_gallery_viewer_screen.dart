import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_cached_image.dart';

class ImageGalleryViewerScreen extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const ImageGalleryViewerScreen({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<ImageGalleryViewerScreen> createState() =>
      _ImageGalleryViewerScreenState();
}

Future<void> showImageGallery(
  BuildContext context, {
  required List<String> imageUrls,
  required int initialIndex,
}) {
  if (imageUrls.isEmpty) return Future.value();
  final viewer = ImageGalleryViewerScreen(
    imageUrls: imageUrls,
    initialIndex: initialIndex,
  );
  if (kIsWeb) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(child: viewer),
    );
  }
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => viewer),
  );
}

class _ImageGalleryViewerScreenState extends State<ImageGalleryViewerScreen> {
  late final PageController controller;
  final FocusNode keyboardFocus = FocusNode();
  late int index;

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.imageUrls.isEmpty ? 0 : widget.imageUrls.length - 1;
    index = widget.initialIndex.clamp(0, maxIndex);
    controller = PageController(initialPage: index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheNearbyImages();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    keyboardFocus.dispose();
    super.dispose();
  }

  void precacheNearbyImages() {
    if (kIsWeb || !mounted || widget.imageUrls.isEmpty) return;
    for (final nextIndex in [index - 1, index + 1]) {
      if (nextIndex < 0 || nextIndex >= widget.imageUrls.length) continue;
      precacheAppRemoteImage(context, widget.imageUrls[nextIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      autofocus: kIsWeb,
      focusNode: keyboardFocus,
      onKeyEvent: (event) {
        if (!kIsWeb || event is! KeyDownEvent) return;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) _move(-1);
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) _move(1);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: controller,
              itemCount: widget.imageUrls.length,
              onPageChanged: (value) {
                setState(() => index = value);
                precacheNearbyImages();
              },
              itemBuilder: (context, pageIndex) {
                return Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: AppCachedImage(
                      imageUrl: widget.imageUrls[pageIndex],
                      fit: BoxFit.contain,
                      placeholder: const Icon(
                        Icons.image_outlined,
                        color: Colors.white,
                        size: 56,
                      ),
                      errorWidget: const Icon(
                        Icons.broken_image,
                        color: Colors.white,
                        size: 56,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 40,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            if (widget.imageUrls.length > 1)
              Positioned(
                top: 48,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    "${index + 1} / ${widget.imageUrls.length}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            if (kIsWeb && widget.imageUrls.length > 1) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Previous image',
                  onPressed: index > 0 ? () => _move(-1) : null,
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Next image',
                  onPressed: index < widget.imageUrls.length - 1
                      ? () => _move(1)
                      : null,
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _move(int delta) {
    final next = index + delta;
    if (next < 0 || next >= widget.imageUrls.length) return;
    controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }
}
