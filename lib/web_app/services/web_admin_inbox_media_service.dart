import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'web_chat_media_service.dart';

class WebAdminInboxMediaService {
  WebAdminInboxMediaService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;
  final WebChatMediaService _picker = WebChatMediaService();

  Future<List<WebPendingChatAttachment>> pickAttachments() {
    return _picker.pickFiles();
  }

  Future<List<Map<String, dynamic>>> upload({
    required String uid,
    required List<WebPendingChatAttachment> attachments,
  }) async {
    final uploaded = <Map<String, dynamic>>[];
    final uploadedPaths = <String>[];
    try {
      for (final attachment in attachments) {
        final name = attachment.fileName.trim().isEmpty
            ? 'attachment_${DateTime.now().microsecondsSinceEpoch}'
            : attachment.fileName.trim();
        final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final extension =
            name.contains('.') ? name.split('.').last.toLowerCase() : '';
        final path =
            'admin_mail/$uid/${DateTime.now().microsecondsSinceEpoch}_$safeName';
        final ref = _storage.ref(path);
        await ref.putData(
          attachment.bytes,
          SettableMetadata(contentType: attachment.mimeType),
        );
        uploadedPaths.add(path);
        final url = await ref.getDownloadURL();
        uploaded.add({
          'name': name,
          'fileName': name,
          'url': url,
          'fileUrl': url,
          'type': extension.isEmpty ? 'file' : extension,
          'fileType': extension.isEmpty ? 'file' : extension,
          'size': attachment.sizeBytes ?? attachment.bytes.length,
          'uploadedAt': Timestamp.now(),
          'uploadedBy': uid,
        });
      }
      return uploaded;
    } catch (error) {
      debugPrint('WEB ADMIN INBOX ATTACHMENT UPLOAD FAILED $error');
      for (final path in uploadedPaths) {
        try {
          await _storage.ref(path).delete();
        } catch (_) {
          // Best-effort cleanup for a partially uploaded reply.
        }
      }
      rethrow;
    }
  }
}
