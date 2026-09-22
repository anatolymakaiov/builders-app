import 'package:flutter/material.dart';

import '../../../screens/image_gallery_viewer_screen.dart';
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
              onTap: () => showImageGallery(
                context,
                imageUrls: urls,
                initialIndex: index,
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
