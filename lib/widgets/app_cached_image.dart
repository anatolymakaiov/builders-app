import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

String appImageCacheKey(String url) => url.trim();

ImageProvider appCachedImageProvider(String url) {
  final clean = url.trim();
  return CachedNetworkImageProvider(
    clean,
    cacheKey: appImageCacheKey(clean),
  );
}

Future<void> precacheAppRemoteImage(BuildContext context, String url) async {
  final clean = url.trim();
  if (clean.isEmpty) return;
  await precacheImage(appCachedImageProvider(clean), context);
}

class AppCachedImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final Widget? placeholder;
  final Widget? errorWidget;

  const AppCachedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final clean = imageUrl.trim();
    if (clean.isEmpty) {
      return errorWidget ?? const Icon(Icons.broken_image_outlined);
    }

    return CachedNetworkImage(
      imageUrl: clean,
      cacheKey: appImageCacheKey(clean),
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: (context, url) =>
          placeholder ??
          Container(
            width: width,
            height: height,
            color: AppColors.surfaceAlt,
            alignment: Alignment.center,
            child: const Icon(
              Icons.image_outlined,
              color: AppColors.muted,
            ),
          ),
      errorWidget: (context, url, error) =>
          errorWidget ??
          Container(
            width: width,
            height: height,
            color: AppColors.surfaceAlt,
            alignment: Alignment.center,
            child: const Icon(
              Icons.broken_image_outlined,
              color: AppColors.muted,
            ),
          ),
    );
  }
}
