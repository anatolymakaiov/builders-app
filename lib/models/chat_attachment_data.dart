String _attachmentText(dynamic value) => value?.toString().trim() ?? '';

String _attachmentType({
  required String declaredType,
  required String mimeType,
  required String fileName,
}) {
  if (declaredType == 'image' ||
      declaredType == 'video' ||
      declaredType == 'audio' ||
      declaredType == 'file') {
    return declaredType;
  }
  if (mimeType.startsWith('image/')) return 'image';
  if (mimeType.startsWith('video/')) return 'video';
  if (mimeType.startsWith('audio/')) return 'audio';

  final lowerName = fileName.toLowerCase();
  if (RegExp(r'\.(jpe?g|png|gif|webp|heic|heif)$').hasMatch(lowerName)) {
    return 'image';
  }
  if (RegExp(r'\.(mp4|mov|m4v|webm)$').hasMatch(lowerName)) return 'video';
  if (RegExp(r'\.(m4a|mp3|wav|aac|ogg)$').hasMatch(lowerName)) return 'audio';
  return 'file';
}

Map<String, dynamic>? normalizeChatAttachment(Map<dynamic, dynamic> source) {
  final url = _attachmentText(
    source['url'] ??
        source['downloadUrl'] ??
        source['fileUrl'] ??
        source['mediaUrl'],
  );
  if (url.isEmpty) return null;

  final fileName = _attachmentText(source['fileName'] ?? source['name']);
  final mimeType = _attachmentText(source['mimeType'] ?? source['contentType']);
  final type = _attachmentType(
    declaredType: _attachmentText(source['type']),
    mimeType: mimeType,
    fileName: fileName,
  );

  return <String, dynamic>{
    ...source.map((key, value) => MapEntry(key.toString(), value)),
    'type': type,
    'url': url,
    'fileName': fileName.isEmpty
        ? switch (type) {
            'image' => 'Photo',
            'video' => 'Video',
            'audio' => 'Audio',
            _ => 'Attachment',
          }
        : fileName,
    if (mimeType.isNotEmpty) 'mimeType': mimeType,
  };
}

List<Map<String, dynamic>> chatAttachmentsFromMessage(
  Map<String, dynamic> data,
) {
  final attachments = <Map<String, dynamic>>[];
  final rawAttachments = data['attachments'];
  if (rawAttachments is List) {
    for (final raw in rawAttachments.whereType<Map>()) {
      final normalized = normalizeChatAttachment(raw);
      if (normalized != null) attachments.add(normalized);
    }
  }
  if (attachments.isNotEmpty) return attachments;

  final declaredType = _attachmentText(data['type']);
  final legacyUrl = switch (declaredType) {
    'image' => data['imageUrl'] ?? data['mediaUrl'],
    'video' => data['videoUrl'] ?? data['mediaUrl'],
    'audio' => data['audioUrl'] ?? data['mediaUrl'],
    _ => data['mediaUrl'] ??
        data['imageUrl'] ??
        data['videoUrl'] ??
        data['audioUrl'],
  };
  return [
    if (legacyUrl != null)
      normalizeChatAttachment({
        'type': declaredType,
        'url': legacyUrl,
        'fileName': data['fileName'],
        'mimeType': data['mimeType'],
      }),
  ].whereType<Map<String, dynamic>>().toList();
}
