import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
    this.webHtmlElementStrategy = WebHtmlElementStrategy.prefer,
    this.errorLabel,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final IconData fallbackIcon;
  final WebHtmlElementStrategy webHtmlElementStrategy;
  final String? errorLabel;

  @override
  State<WebRemoteImage> createState() => _WebRemoteImageState();
}

class _WebRemoteImageState extends State<WebRemoteImage> {
  Future<WebImageResolution>? resolution;
  WebImageResolution? displayedResolution;
  final Set<String> displayedFrames = {};

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant WebRemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url?.trim() != widget.url?.trim()) {
      displayedResolution = null;
      _resolve();
    }
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
    if (cached != null && !cached.unsupported) {
      displayedResolution = cached;
    }
    final child = clean == null || clean.isEmpty
        ? _Fallback(icon: widget.fallbackIcon, label: widget.errorLabel)
        : cached != null
            ? (cached.unsupported
                ? _originalFallback(clean)
                : _resolvedImage(cached))
            : FutureBuilder<WebImageResolution>(
                future: resolution,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    WebImageService.logFailure(clean, snapshot.error!);
                    return _Fallback(
                        icon: widget.fallbackIcon, label: widget.errorLabel);
                  }
                  final resolved = snapshot.data;
                  if (resolved == null) {
                    final previous = displayedResolution;
                    return previous == null
                        ? _LoadingPlaceholder(icon: widget.fallbackIcon)
                        : _resolvedImage(previous);
                  }
                  if (resolved.unsupported) {
                    return _originalFallback(resolved.originalUrl);
                  }
                  displayedResolution = resolved;
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
      gaplessPlayback: true,
      webHtmlElementStrategy: widget.webHtmlElementStrategy,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null || wasSynchronouslyLoaded) {
          displayedFrames.add(resolved.url);
        }
        return displayedFrames.contains(resolved.url)
            ? child
            : _LoadingPlaceholder(icon: widget.fallbackIcon);
      },
      errorBuilder: (_, error, __) {
        WebImageService.logFailure(resolved.url, error);
        return resolved.usedDerivative
            ? _originalFallback(resolved.originalUrl)
            : _Fallback(icon: widget.fallbackIcon, label: widget.errorLabel);
      },
    );
  }

  Widget _originalFallback(String url) {
    return Tooltip(
      message: 'Preview unavailable. Open original image',
      child: InkWell(
        onTap: () => launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ),
        child: _Fallback(icon: widget.fallbackIcon, label: widget.errorLabel),
      ),
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
  const _Fallback({required this.icon, this.label});

  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WebTheme.accentSoft,
      child: Center(
          child: label == null
              ? Icon(icon, color: WebTheme.accent)
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: WebTheme.accent),
                  const SizedBox(height: 4),
                  Text(label!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11, color: WebTheme.accent)),
                ])),
    );
  }
}
