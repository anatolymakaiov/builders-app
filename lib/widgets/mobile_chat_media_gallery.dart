import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/chat_image_gallery.dart';
import '../models/chat_media_gallery_layout.dart';
import 'app_cached_image.dart';

class MobileChatMediaThenText extends StatelessWidget {
  const MobileChatMediaThenText({super.key, this.media, this.text});

  final Widget? media;
  final Widget? text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (media != null) media!,
        if (text != null)
          Padding(
            padding: EdgeInsets.only(top: media == null ? 0 : 4),
            child: text!,
          ),
      ],
    );
  }
}

class MobileChatMediaGallery extends StatefulWidget {
  const MobileChatMediaGallery({
    super.key,
    required this.attachments,
    required this.itemBuilder,
  });

  final List<Map<String, dynamic>> attachments;
  final Widget Function(int index, double width, double height) itemBuilder;

  @override
  State<MobileChatMediaGallery> createState() => _MobileChatMediaGalleryState();
}

class _MobileChatMediaGalleryState extends State<MobileChatMediaGallery> {
  final Map<String, bool> _landscape = {};
  final Map<String, (ImageStream, ImageStreamListener)> _listeners = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveUnknownImages();
  }

  @override
  void didUpdateWidget(covariant MobileChatMediaGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentUrls = widget.attachments
        .map((attachment) => attachment['url']?.toString().trim() ?? '')
        .toSet();
    _landscape.removeWhere((url, _) => !currentUrls.contains(url));
    for (final url in _listeners.keys.toList()) {
      if (currentUrls.contains(url)) continue;
      final (stream, listener) = _listeners.remove(url)!;
      stream.removeListener(listener);
    }
    _resolveUnknownImages();
  }

  void _resolveUnknownImages() {
    for (final attachment in widget.attachments) {
      if (!ChatImageGallery.isPreviewableImage(attachment)) continue;
      final url = attachment['url']?.toString().trim() ?? '';
      if (url.isEmpty ||
          _landscape.containsKey(url) ||
          _listeners.containsKey(url)) {
        continue;
      }
      final width = _dimension(attachment['width'] ?? attachment['imageWidth']);
      final height =
          _dimension(attachment['height'] ?? attachment['imageHeight']);
      if (width != null && height != null) {
        _landscape[url] = width > height;
        continue;
      }
      final provider = appCachedImageProvider(url);
      final stream =
          (kIsWeb ? provider : ResizeImage.resizeIfNeeded(512, 512, provider))
              .resolve(
        createLocalImageConfiguration(context, size: const Size(240, 160)),
      );
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          stream.removeListener(listener);
          _listeners.remove(url);
          final isLandscape = info.image.width > info.image.height;
          Future.microtask(() {
            if (!mounted ||
                !widget.attachments.any(
                  (attachment) => attachment['url']?.toString().trim() == url,
                )) {
              return;
            }
            setState(() => _landscape[url] = isLandscape);
          });
        },
        onError: (error, stackTrace) {
          stream.removeListener(listener);
          _listeners.remove(url);
        },
      );
      _listeners[url] = (stream, listener);
      stream.addListener(listener);
    }
  }

  double? _dimension(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return value != null && value > 0 ? value : null;
  }

  @override
  void dispose() {
    for (final (stream, listener) in _listeners.values) {
      stream.removeListener(listener);
    }
    _listeners.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kinds = [
      for (final attachment in widget.attachments)
        if (!ChatImageGallery.isPreviewableImage(attachment))
          ChatMediaTileKind.other
        else if (_landscape[attachment['url']?.toString() ?? ''] == true)
          ChatMediaTileKind.landscape
        else
          ChatMediaTileKind.portrait,
    ];
    final rows = ChatMediaGalleryLayout.rows(kinds);
    return LayoutBuilder(builder: (context, constraints) {
      final width =
          constraints.maxWidth.isFinite ? constraints.maxWidth : 236.0;
      const gap = 2.0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
            if (rowIndex > 0) const SizedBox(height: gap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var cell = 0; cell < rows[rowIndex].length; cell++) ...[
                  if (cell > 0) const SizedBox(width: gap),
                  _tile(
                    rows[rowIndex][cell],
                    kinds[rows[rowIndex][cell]],
                    rows[rowIndex].length,
                    width,
                    gap,
                  ),
                ],
              ],
            ),
          ],
        ],
      );
    });
  }

  Widget _tile(
      int index, ChatMediaTileKind kind, int count, double width, double gap) {
    final cellWidth = (width - gap * (count - 1)) / count;
    final cellHeight = switch (kind) {
      ChatMediaTileKind.landscape => cellWidth * 9 / 16,
      ChatMediaTileKind.portrait => cellWidth * 4 / 3,
      ChatMediaTileKind.other => 0.0,
    };
    return SizedBox(
      width: cellWidth,
      child: kind == ChatMediaTileKind.other
          ? widget.itemBuilder(index, cellWidth, 0)
          : SizedBox(
              height: cellHeight,
              child: widget.itemBuilder(index, cellWidth, cellHeight),
            ),
    );
  }
}
