import 'package:flutter/material.dart';

class WebRemoteImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final clean = url?.trim();
    final child = clean == null || clean.isEmpty
        ? _Fallback(icon: fallbackIcon)
        : Image.network(
            clean,
            width: width,
            height: height,
            fit: fit,
            gaplessPlayback: true,
            webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
            errorBuilder: (_, error, __) {
              debugPrint('WEB IMAGE LOAD ERROR ${_safeUrl(clean)} $error');
              return _Fallback(icon: fallbackIcon);
            },
          );

    if (borderRadius <= 0) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: child,
    );
  }

  static String _safeUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return '<invalid-url>';
    return uri.replace(query: uri.hasQuery ? '<redacted>' : '').toString();
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

class _Fallback extends StatelessWidget {
  const _Fallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEAF4EC),
      child: Center(
        child: Icon(icon, color: const Color(0xFF2E7D32)),
      ),
    );
  }
}
