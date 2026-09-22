class ChatImageGallery {
  const ChatImageGallery({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  static ChatImageGallery? fromAttachments(
    List<Map<String, dynamic>> attachments,
    int selectedIndex,
  ) {
    if (selectedIndex < 0 || selectedIndex >= attachments.length) return null;
    final urls = <String>[];
    int? initialIndex;
    for (var i = 0; i < attachments.length; i++) {
      final attachment = attachments[i];
      final url = attachment['url']?.toString().trim() ?? '';
      if (url.isEmpty || !isPreviewableImage(attachment)) continue;
      if (i == selectedIndex) initialIndex = urls.length;
      urls.add(url);
    }
    if (initialIndex == null) return null;
    return ChatImageGallery(urls: urls, initialIndex: initialIndex);
  }

  static bool isPreviewableImage(Map<String, dynamic> attachment) {
    final type = attachment['type']?.toString().toLowerCase() ?? '';
    if (type == 'video' || type == 'audio') return false;
    if (type == 'image') return true;
    final mime = attachment['mimeType']?.toString().toLowerCase() ?? '';
    if (mime.startsWith('image/')) return true;
    final name = attachment['fileName']?.toString().toLowerCase() ?? '';
    return RegExp(r'\.(jpe?g|png|gif|webp|bmp|heic|heif)$').hasMatch(name);
  }
}
