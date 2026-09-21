import 'package:flutter/material.dart';

import '../services/web_image_service.dart';
import '../theme/app_colors.dart';

class WebRemoteImage extends StatefulWidget {
  const WebRemoteImage({
    super.key,
    required this.imageUrl,
    required this.fit,
    this.width,
    this.height,
    required this.alignment,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  State<WebRemoteImage> createState() => _WebRemoteImageState();
}

class _WebRemoteImageState extends State<WebRemoteImage> {
  late Future<WebImageResolution> _resolution;

  @override
  void initState() {
    super.initState();
    _resolution = WebImageService.instance.resolve(widget.imageUrl);
  }

  @override
  void didUpdateWidget(WebRemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl.trim() != widget.imageUrl.trim()) {
      _resolution = WebImageService.instance.resolve(widget.imageUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clean = widget.imageUrl.trim();
    if (clean.isEmpty) return _error();

    final cached = WebImageService.instance.cached(clean);
    if (cached != null) return _resolvedImage(cached);

    return FutureBuilder<WebImageResolution>(
      future: _resolution,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          WebImageService.logFailure(clean, snapshot.error!);
          return _error();
        }
        if (!snapshot.hasData) return _placeholder();

        final resolution = snapshot.data!;
        if (resolution.unsupported) {
          return _error();
        }

        return _resolvedImage(resolution);
      },
    );
  }

  Widget _resolvedImage(WebImageResolution resolution) {
    if (resolution.unsupported) return _error();
    return Image.network(
      resolution.url,
      key: ValueKey(resolution.url),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      gaplessPlayback: true,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _placeholder();
      },
      errorBuilder: (context, error, stackTrace) {
        WebImageService.logFailure(resolution.url, error);
        return _error();
      },
    );
  }

  Widget _placeholder() {
    return widget.placeholder ??
        Container(
          width: widget.width,
          height: widget.height,
          color: AppColors.surfaceAlt,
          alignment: Alignment.center,
          child: const Icon(
            Icons.image_outlined,
            color: AppColors.muted,
          ),
        );
  }

  Widget _error() {
    return widget.errorWidget ??
        Container(
          width: widget.width,
          height: widget.height,
          color: AppColors.surfaceAlt,
          alignment: Alignment.center,
          child: const Icon(
            Icons.broken_image_outlined,
            color: AppColors.muted,
          ),
        );
  }
}
