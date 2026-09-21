import 'package:flutter/material.dart';

import '../../services/web_image_service.dart';
import '../theme/web_theme.dart';

class WebRemoteImage extends StatefulWidget {
  const WebRemoteImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
    this.fallbackIcon = Icons.image_outlined,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final IconData fallbackIcon;

  @override
  State<WebRemoteImage> createState() => _WebRemoteImageState();
}

class _WebRemoteImageState extends State<WebRemoteImage> {
  Future<WebImageResolution>? resolution;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant WebRemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url?.trim() != widget.url?.trim()) _resolve();
  }

  void _resolve() {
    final clean = widget.url?.trim();
    resolution = clean == null || clean.isEmpty
        ? null
        : WebImageService.instance.resolve(clean);
  }

  @override
  Widget build(BuildContext context) {
    final clean = widget.url?.trim();
    final cached = clean == null || clean.isEmpty
        ? null
        : WebImageService.instance.cached(clean);
    final child = clean == null || clean.isEmpty
        ? _Fallback(icon: widget.fallbackIcon)
        : cached != null
            ? (cached.unsupported
                ? _Fallback(icon: widget.fallbackIcon)
                : _resolvedImage(cached))
            : FutureBuilder<WebImageResolution>(
                future: resolution,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    WebImageService.logFailure(clean, snapshot.error!);
                    return _Fallback(icon: widget.fallbackIcon);
                  }
                  final resolved = snapshot.data;
                  if (resolved == null) {
                    return _LoadingPlaceholder(icon: widget.fallbackIcon);
                  }
                  if (resolved.unsupported) {
                    return _Fallback(icon: widget.fallbackIcon);
                  }
                  return _resolvedImage(resolved);
                },
              );

    if (widget.borderRadius <= 0) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: child,
    );
  }

  Widget _resolvedImage(WebImageResolution resolved) {
    return Image.network(
      key: ValueKey<String>('web-remote-image:${resolved.url}'),
      resolved.url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: false,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      loadingBuilder: (context, child, loadingProgress) =>
          loadingProgress == null
              ? child
              : _LoadingPlaceholder(icon: widget.fallbackIcon),
      errorBuilder: (_, error, __) {
        WebImageService.logFailure(resolved.url, error);
        return _Fallback(icon: widget.fallbackIcon);
      },
    );
  }
}

class WebCircleImage extends StatelessWidget {
  const WebCircleImage({
    super.key,
    required this.url,
    this.size,
    this.radius = 22,
    this.fallbackIcon = Icons.person_outline,
  });

  final String? url;
  final double? size;
  final double radius;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final dimension = size ?? radius * 2;
    return ClipOval(
      child: SizedBox(
        width: dimension,
        height: dimension,
        child: WebRemoteImage(
          url: url,
          width: dimension,
          height: dimension,
          fallbackIcon: fallbackIcon,
        ),
      ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WebTheme.surfaceAlt,
      child: Center(
        child: Icon(icon, color: WebTheme.subtleText),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WebTheme.accentSoft,
      child: Center(
        child: Icon(icon, color: WebTheme.accent),
      ),
    );
  }
}
