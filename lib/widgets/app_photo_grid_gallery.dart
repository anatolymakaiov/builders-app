import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../screens/image_gallery_viewer_screen.dart';
import '../theme/app_theme.dart';

class AppPhotoGridGallery extends StatelessWidget {
  final List<String> imageUrls;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics physics;
  final bool shrinkWrap;
  final double spacing;
  final double borderRadius;
  final Widget Function(BuildContext context, int index, String imageUrl)?
      overlayBuilder;

  const AppPhotoGridGallery({
    super.key,
    required this.imageUrls,
    this.padding = EdgeInsets.zero,
    this.physics = const NeverScrollableScrollPhysics(),
    this.shrinkWrap = true,
    this.spacing = 10,
    this.borderRadius = 10,
    this.overlayBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final photos = imageUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();

    if (photos.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: photos.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
      itemBuilder: (context, index) {
        final imageUrl = photos[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ImageGalleryViewerScreen(
                  imageUrls: photos,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: AppColors.surfaceAlt,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: AppColors.surfaceAlt,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                if (overlayBuilder != null)
                  overlayBuilder!(context, index, imageUrl),
              ],
            ),
          ),
        );
      },
    );
  }
}
