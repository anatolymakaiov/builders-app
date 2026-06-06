import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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

class _ImageGalleryViewerScreenState extends State<ImageGalleryViewerScreen> {
  late final PageController controller;
  late int index;

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.imageUrls.isEmpty ? 0 : widget.imageUrls.length - 1;
    index = widget.initialIndex.clamp(0, maxIndex);
    controller = PageController(initialPage: index);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: controller,
            itemCount: widget.imageUrls.length,
            onPageChanged: (value) => setState(() => index = value),
            itemBuilder: (context, pageIndex) {
              return Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: widget.imageUrls[pageIndex],
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (context, url, error) => const Icon(
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
        ],
      ),
    );
  }
}
