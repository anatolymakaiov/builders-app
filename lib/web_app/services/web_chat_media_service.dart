import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../models/chat_attachment_data.dart';
import 'web_media_pipeline.dart';

class WebChatAttachment {
  const WebChatAttachment({
    required this.type,
    required this.url,
    required this.fileName,
    this.mimeType,
    this.sizeBytes,
    this.storagePath,
  });

  final String type;
  final String url;
  final String fileName;
  final String? mimeType;
  final int? sizeBytes;
  final String? storagePath;

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'url': url,
      'fileName': fileName,
      if (mimeType != null && mimeType!.isNotEmpty) 'mimeType': mimeType,
      if (sizeBytes != null) 'sizeBytes': sizeBytes,
      if (storagePath != null && storagePath!.isNotEmpty)
        'storagePath': storagePath,
    };
  }
}

class WebPendingChatAttachment {
  const WebPendingChatAttachment({
    required this.type,
    required this.fileName,
    required this.bytes,
    this.mimeType,
    this.sizeBytes,
  });

  final String type;
  final String fileName;
  final Uint8List bytes;
  final String? mimeType;
  final int? sizeBytes;
}

class WebChatMediaService {
  Future<List<WebPendingChatAttachment>> pickImages() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    return _pendingFromResult(picked, forcedType: 'image');
  }

  Future<List<WebPendingChatAttachment>> pickVideos() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
      withData: true,
    );
    return _pendingFromResult(picked, forcedType: 'video');
  }

  Future<List<WebPendingChatAttachment>> pickFiles() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    return _pendingFromResult(picked);
  }

  Future<List<WebChatAttachment>> uploadAttachments({
    required String chatId,
    required String messageId,
    required String senderId,
    required List<WebPendingChatAttachment> attachments,
  }) async {
    final uploaded = List<WebChatAttachment?>.filled(attachments.length, null);
    final uploadedPaths = <String>[];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    try {
      await WebMediaPipeline.mapBounded(
        attachments,
        (attachment, index) async {
          final originalContentType =
              attachment.mimeType ?? _fallbackMime(attachment.fileName);
          final media = attachment.type == 'image'
              ? await WebMediaPipeline.optimizeImage(
                  bytes: attachment.bytes,
                  fileName: attachment.fileName,
                  contentType: originalContentType,
                )
              : WebMediaPayload(
                  bytes: attachment.bytes,
                  fileName: attachment.fileName,
                  contentType: originalContentType,
                  originalSizeBytes: attachment.bytes.length,
                  optimized: false,
                );
          final cleanName = _sanitizeStorageName(attachment.fileName);
          final storagePath = 'chat_attachments/$chatId/$messageId/$senderId/'
              '${stamp}_${index}_$cleanName';
          debugPrint(
            'WEB CHAT ATTACHMENT UPLOAD START chatId=$chatId '
            'messageId=$messageId senderId=$senderId storagePath=$storagePath',
          );
          try {
            final ref = FirebaseStorage.instance.ref().child(storagePath);
            final metadata = SettableMetadata(
              contentType: media.contentType,
              cacheControl: WebMediaPipeline.browserCacheControl,
            );
            await ref.putData(media.bytes, metadata);
            uploadedPaths.add(storagePath);
            final url = await ref.getDownloadURL();
            uploaded[index] = WebChatAttachment(
              type: attachment.type,
              url: url,
              fileName: attachment.fileName,
              mimeType: metadata.contentType,
              sizeBytes: media.bytes.length,
              storagePath: storagePath,
            );
            debugPrint(
                'WEB CHAT ATTACHMENT UPLOAD SUCCESS storagePath=$storagePath');
          } catch (error) {
            debugPrint(
              'WEB CHAT ATTACHMENT UPLOAD FAILED storagePath=$storagePath '
              'error=$error',
            );
            rethrow;
          }
        },
      );
      return uploaded.cast<WebChatAttachment>();
    } catch (error) {
      debugPrint('WEB CHAT ATTACHMENT UPLOAD FAILED error=$error');
      for (final path in uploadedPaths) {
        try {
          await FirebaseStorage.instance.ref(path).delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
      rethrow;
    }
  }

  List<WebPendingChatAttachment> _pendingFromResult(
    FilePickerResult? result, {
    String? forcedType,
  }) {
    if (result == null) return const [];
    return result.files.where((file) => file.bytes != null).map((file) {
      final mimeType = _fallbackMime(file.name);
      return WebPendingChatAttachment(
        type: forcedType ?? _typeFromMime(mimeType),
        fileName: file.name,
        bytes: file.bytes!,
        mimeType: mimeType,
        sizeBytes: file.size,
      );
    }).toList();
  }

  String _typeFromMime(String mimeType) {
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType.startsWith('video/')) return 'video';
    if (mimeType.startsWith('audio/')) return 'audio';
    return 'file';
  }

  String _fallbackMime(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }

  String _sanitizeStorageName(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }
}

List<WebChatAttachment> normalizeWebChatAttachments(
  Map<String, dynamic> data,
) {
  return chatAttachmentsFromMessage(data).map((map) {
    return WebChatAttachment(
      type: map['type'].toString(),
      url: map['url'].toString(),
      fileName: map['fileName'].toString(),
      mimeType: map['mimeType']?.toString(),
      sizeBytes: _readInt(map['sizeBytes'] ?? map['size']),
      storagePath: map['storagePath']?.toString(),
    );
  }).toList(growable: false);
}

String webChatAttachmentPreview(List<WebChatAttachment> attachments) {
  if (attachments.isEmpty) return '';
  if (attachments.length > 1) return '${attachments.length} attachments';
  switch (attachments.first.type) {
    case 'image':
      return 'Photo';
    case 'video':
      return 'Video';
    case 'audio':
      return 'Voice message';
    default:
      return attachments.first.fileName;
  }
}

int? _readInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
