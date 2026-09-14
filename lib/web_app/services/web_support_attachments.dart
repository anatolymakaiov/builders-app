import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'web_chat_media_service.dart';

const webWorkerSupportTypes = {
  'technical_issue': 'Technical issue',
  'employer_complaint': 'Complaint about employer/company',
  'participant_complaint': 'Complaint about another participant',
  'job_ad_complaint': 'Job advert complaint',
  'application_issue': 'Application issue',
  'chat_media_issue': 'Chat or media issue',
  'profile_account_issue': 'Profile/account issue',
  'safety_abuse_report': 'Safety or abuse report',
  'other': 'Other',
};
const webEmployerSupportTypes = {
  'billing': 'Billing',
  'payment': 'Payment',
  'tariff_plan': 'Tariff plan',
  'direct_debit': 'Direct debit',
  'invoice': 'Invoice',
  'job_posting_issue': 'Job posting issue',
  'job_moderation_issue': 'Job moderation issue',
  'technical_issue': 'Technical issue',
  'worker_team_complaint': 'Complaint about worker/team',
  'chat_media_issue': 'Chat or media issue',
  'profile_company_account_issue': 'Profile/company account issue',
  'safety_abuse_report': 'Safety or abuse report',
  'other': 'Other',
};

class WebSupportAttachments {
  Future<List<Map<String, dynamic>>> upload(
      String uid, List<WebPendingChatAttachment> files) async {
    final uploaded = <Map<String, dynamic>>[];
    final paths = <String>[];
    try {
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        final safeName =
            file.fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final extension = file.fileName.contains('.')
            ? file.fileName.split('.').last.toLowerCase()
            : 'file';
        final path =
            'support_requests/$uid/${DateTime.now().microsecondsSinceEpoch}_${index}_$safeName';
        paths.add(path);
        debugPrint('SUPPORT ATTACHMENT UPLOAD START path=$path');
        final ref = FirebaseStorage.instance.ref(path);
        await ref.putData(
            file.bytes,
            SettableMetadata(contentType: file.mimeType, customMetadata: {
              'fileName': file.fileName,
              'fileType': extension,
              'userId': uid
            }));
        final url = await ref.getDownloadURL();
        uploaded.add({
          'fileName': file.fileName,
          'fileUrl': url,
          'fileType': extension,
          'uploadedAt': Timestamp.now(),
          'size': file.bytes.length,
          'name': file.fileName,
          'url': url,
          'type': extension
        });
        debugPrint('SUPPORT ATTACHMENT UPLOAD SUCCESS path=$path');
      }
      return uploaded;
    } catch (error) {
      debugPrint('SUPPORT ATTACHMENT UPLOAD FAILED error=$error');
      for (final path in paths) {
        try {
          await FirebaseStorage.instance.ref(path).delete();
        } catch (_) {/* Best-effort incomplete-upload cleanup. */}
      }
      rethrow;
    }
  }
}
