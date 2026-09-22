import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/job.dart';
import '../../services/billing_service.dart';
import '../../services/job_alert_service.dart';
import '../../services/moderation_hold_service.dart';
import '../../services/notification_service.dart';

class WebAdminRecord {
  const WebAdminRecord(this.collection, this.id, this.data);

  final String collection;
  final String id;
  final Map<String, dynamic> data;

  String get text {
    if (collection == 'users') {
      return [data['role'], data['email'], data['phone']]
          .whereType<String>()
          .where((part) => part.trim().isNotEmpty)
          .join(' | ');
    }
    if (collection == 'jobs') {
      return [data['companyName'], data['site'], data['postcode']]
          .whereType<String>()
          .where((part) => part.trim().isNotEmpty)
          .join(' | ');
    }
    return (data['message'] ?? data['description'] ?? '').toString();
  }

  String get title {
    final name = [data['firstName'], data['lastName']]
        .whereType<String>()
        .where((part) => part.trim().isNotEmpty)
        .join(' ');
    return (data['subject'] ??
            data['typeLabel'] ??
            data['requestTypeLabel'] ??
            data['title'] ??
            data['companyName'] ??
            data['name'] ??
            data['displayName'] ??
            (name.isNotEmpty ? name : null) ??
            data['email'] ??
            '')
        .toString();
  }

  String get status =>
      (data['moderationStatus'] ?? data['status'] ?? '').toString();
  DateTime get date {
    final value = data['createdAt'] ?? data['updatedAt'];
    return value is Timestamp ? value.toDate() : DateTime(0);
  }
}

class WebAdminProfileService {
  WebAdminProfileService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<bool> isAuthorized(String uid) async {
    if (_auth.currentUser?.uid != uid) return false;
    final profile = await _db.collection('users').doc(uid).get();
    return webAdminRoleAllowsAccess(
      authenticatedUid: _auth.currentUser?.uid,
      requestedUid: uid,
      role: profile.data()?['role']?.toString(),
    );
  }

  Future<void> _requireAdmin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || !await isAuthorized(uid)) {
      throw StateError('Administrator access required.');
    }
  }

  Future<List<WebAdminRecord>> load(String collection) async {
    await _requireAdmin();
    final snapshot = await _db.collection(collection).get();
    return snapshot.docs
        .map((doc) => WebAdminRecord(collection, doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<List<WebAdminRecord>> loadMany(List<String> collections) async {
    await _requireAdmin();
    final groups = await Future.wait(collections.map((collection) async {
      final snapshot = await _db.collection(collection).get();
      return snapshot.docs
          .map((doc) => WebAdminRecord(collection, doc.id, doc.data()))
          .toList(growable: false);
    }));
    return [for (final group in groups) ...group];
  }

  Future<void> holdUser(WebAdminRecord user, String reason) async {
    await _requireAdmin();
    final role = user.data['role']?.toString() ?? 'worker';
    final holds = ModerationHoldService();
    await holds.holdUser(targetUserId: user.id, role: role, message: reason);
    await holds.sendAdminHoldMessage(
      userId: user.id,
      role: role,
      title: 'Profile temporarily suspended',
      message: reason,
      relatedTargetType: 'profile_hold',
      relatedTargetId: user.id,
    );
  }

  Future<void> restoreUser(String uid) async {
    await _requireAdmin();
    await ModerationHoldService().restoreUser(uid);
  }

  Future<void> holdJob(WebAdminRecord record, String reason) async {
    await _requireAdmin();
    final job = Job.fromFirestore(record.id, record.data);
    final holds = ModerationHoldService();
    await holds.holdJob(jobId: record.id, message: reason);
    if (job.ownerId.isNotEmpty) {
      await holds.sendAdminHoldMessage(
        userId: job.ownerId,
        role: 'employer',
        title: 'Vacancy temporarily suspended',
        message: '${job.displayTitle}\n\n$reason',
        relatedTargetType: 'job_hold',
        relatedTargetId: record.id,
      );
    }
  }

  Future<void> restoreJob(String jobId) async {
    await _requireAdmin();
    await ModerationHoldService().restoreJob(jobId);
  }

  Future<void> approveJob(WebAdminRecord record, String message) async {
    await _requireAdmin();
    final job = Job.fromFirestore(record.id, record.data);
    await BillingService().approveJobAndCountSlot(
      jobRef: _db.collection('jobs').doc(record.id),
      employerId: job.ownerId,
      moderationData: {
        'moderationStatus': 'approved',
        'moderationReason': '',
        'status': 'active',
        'visibility': 'public',
        'moderatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    await NotificationService().notifyEmployerJobModeration(
      employerId: job.ownerId,
      jobId: job.id,
      jobTitle: job.displayTitle,
      moderationStatus: 'approved',
      approvalMessage: message,
    );
    if (message.trim().isNotEmpty) {
      await sendMessage(
        receiverId: job.ownerId,
        receiverRole: 'employer',
        subject: 'Vacancy approved',
        message: message,
        relatedTargetType: 'job',
        relatedTargetId: record.id,
      );
    }
    await JobAlertService().notifyMatchingWorkers(
      jobId: job.id,
      jobData: {
        'title': job.title,
        'trade': job.trade,
        'jobType': job.jobType,
        'lat': job.lat,
        'lng': job.lng,
      },
    );
  }

  Future<void> rejectJob(WebAdminRecord record, String reason) async {
    await _requireAdmin();
    final job = Job.fromFirestore(record.id, record.data);
    await _db.collection('jobs').doc(record.id).set({
      'moderationStatus': 'rejected',
      'moderationReason': reason,
      'moderatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await NotificationService().notifyEmployerJobModeration(
      employerId: job.ownerId,
      jobId: job.id,
      jobTitle: job.displayTitle,
      moderationStatus: 'rejected',
      reason: reason,
    );
    await sendMessage(
      receiverId: job.ownerId,
      receiverRole: 'employer',
      subject: 'Job publication rejected',
      message: reason,
      relatedTargetType: 'job',
      relatedTargetId: record.id,
    );
  }

  Future<void> reviewEdit(String reviewId, String decision) async {
    await _requireAdmin();
    await FirebaseFunctions.instance.httpsCallable('reviewVacancyEdit').call({
      'reviewId': reviewId,
      'decision': decision,
    });
  }

  Future<void> updateRequest(WebAdminRecord record, String status) async {
    await _requireAdmin();
    final ref = _db.collection(record.collection).doc(record.id);
    if (record.collection == 'payment_requests') {
      await BillingService().updatePaymentRequestStatus(ref, status);
      return;
    }
    await ref.set({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (record.collection == 'reports') {
      final targetId = record.data['againstUserId']?.toString() ?? '';
      if (targetId.isNotEmpty) {
        final target = await _db.collection('users').doc(targetId).get();
        if (target.data()?['role'] == 'employer') {
          await NotificationService().notifyEmployerReportStatusChanged(
            employerId: targetId,
            reportId: record.id,
            status: status,
          );
        }
      }
    }
  }

  Future<void> markRequestRead(WebAdminRecord record) async {
    await _requireAdmin();
    await _db.collection(record.collection).doc(record.id).set({
      'readByAdmin': true,
      'viewedByAdmin': true,
      'viewedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setMailFlag(String messageId, String field, bool value) async {
    await _requireAdmin();
    if (!const ['readByAdmin', 'important', 'deletedByAdmin'].contains(field)) {
      throw ArgumentError.value(field, 'field');
    }
    await _db.collection('admin_messages').doc(messageId).set({
      field: value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> sendMessage({
    required String receiverId,
    required String receiverRole,
    required String subject,
    required String message,
    String? threadId,
    String? relatedTargetType,
    String? relatedTargetId,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    await _requireAdmin();
    if (receiverId.trim().isEmpty ||
        subject.trim().isEmpty ||
        (message.trim().isEmpty && attachments.isEmpty)) {
      throw ArgumentError(
          'Recipient, subject and message or file are required.');
    }
    final user = await _db.collection('users').doc(receiverId).get();
    if (!user.exists) throw StateError('Recipient not found.');
    final userData = user.data() ?? {};
    final actualRole = receiverRole.trim().isEmpty
        ? userData['role']?.toString() ?? 'worker'
        : receiverRole;
    final receiverName = (userData['companyName'] ??
            userData['name'] ??
            userData['displayName'] ??
            receiverId)
        .toString();
    final threadRef = _db.collection('message_threads').doc(threadId);
    final mailRef = _db.collection('admin_messages').doc();
    final inboxRef =
        _db.collection('users').doc(receiverId).collection('admin_inbox').doc();
    final sentRef = _db.collection('admin_inbox_messages').doc();
    final notificationRef = _db
        .collection('users')
        .doc(receiverId)
        .collection('notifications')
        .doc();
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.set(mailRef, {
      'threadId': threadRef.id,
      'direction': 'outgoing',
      'senderId': 'admin',
      'senderName': 'Admin',
      'senderRole': 'admin',
      'receiverId': receiverId,
      'receiverName': receiverName,
      'receiverRole': actualRole,
      'recipientId': receiverId,
      'recipientRole': actualRole,
      'threadParticipants': ['admin', receiverId],
      'audienceType': actualRole,
      'canReply': true,
      'subject': subject.trim(),
      'message': message.trim(),
      'type': 'admin_message',
      if (relatedTargetType == 'support' ||
          relatedTargetType == 'support_request' ||
          relatedTargetType == 'support_requests')
        'relatedSupportRequestId': relatedTargetId,
      if (relatedTargetType == 'payment_request' ||
          relatedTargetType == 'payment_requests' ||
          relatedTargetType == 'billing')
        'relatedBillingRequestId': relatedTargetId,
      'readByAdmin': true,
      'readByReceiver': false,
      'important': false,
      'deletedByAdmin': false,
      'deletedByReceiver': false,
      'deletedBySender': false,
      'attachments': attachments,
      'hasAttachments': attachments.isNotEmpty,
      if (relatedTargetType != null) 'relatedTargetType': relatedTargetType,
      if (relatedTargetId != null) 'relatedTargetId': relatedTargetId,
      'createdAt': now,
    });
    batch.set(
        threadRef,
        {
          'subject': subject.trim(),
          'participants': ['admin', receiverId],
          'lastMessage': message.trim(),
          'lastMessageAt': now,
          'lastSenderId': 'admin',
          'unreadForAdmin': 0,
          'updatedAt': now,
        },
        SetOptions(merge: true));
    for (final attachment in attachments) {
      batch.set(_db.collection('message_attachments').doc(), {
        ...attachment,
        'threadId': threadRef.id,
        'messageId': mailRef.id,
        'createdAt': now,
      });
    }
    final legacy = {
      'userId': receiverId,
      'title': subject.trim(),
      'message': message.trim(),
      'type': 'admin_message',
      'targetType': 'admin_message',
      'targetId': threadRef.id,
      'audience': actualRole,
      'audienceType': actualRole,
      'canReply': true,
      'read': false,
      'threadId': threadRef.id,
      'adminMessageId': mailRef.id,
      if (relatedTargetType != null) 'relatedTargetType': relatedTargetType,
      if (relatedTargetId != null) 'relatedTargetId': relatedTargetId,
      'createdAt': now,
    };
    batch.set(inboxRef, legacy);
    batch.set(
        sentRef, {...legacy, 'targetUserId': receiverId, 'recipientCount': 1});
    batch.set(notificationRef, {
      'notificationId': notificationRef.id,
      'userId': receiverId,
      'type': 'admin_message',
      'category': 'admin',
      'targetType': 'admin_message',
      'targetId': threadRef.id,
      'threadId': threadRef.id,
      'adminMessageId': mailRef.id,
      'title': subject.trim(),
      'message': message.trim(),
      'read': false,
      'badgeEligible': true,
      'pushEligible': true,
      'push': {
        'title': subject.trim(),
        'body': message.trim(),
        'category': 'admin',
        'sound': true,
        'badge': true,
        'data': {
          'notificationId': notificationRef.id,
          'userId': receiverId,
          'type': 'admin_message',
          'category': 'admin',
          'targetType': 'admin_message',
          'targetId': threadRef.id,
          'threadId': threadRef.id,
          'adminMessageId': mailRef.id,
        },
      },
      'createdAt': now,
    });
    batch.set(_db.collection('unread_counters').doc('admin'),
        {'updatedAt': now}, SetOptions(merge: true));
    await batch.commit();
  }
}

bool webAdminRoleAllowsAccess({
  required String? authenticatedUid,
  required String requestedUid,
  required String? role,
}) =>
    authenticatedUid != null &&
    authenticatedUid == requestedUid &&
    role == 'admin';

bool webAdminSearchMatches(WebAdminRecord record, String query) {
  String normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9@+]+'), '');
  final needle = normalize(query);
  if (needle.isEmpty) return false;
  final fields = record.collection == 'users'
      ? const [
          'name',
          'displayName',
          'firstName',
          'lastName',
          'companyName',
          'email',
          'normalizedEmail',
          'phone',
          'normalizedPhone',
          'role'
        ]
      : const [
          'title',
          'trade',
          'companyName',
          'site',
          'postcode',
          'ownerId',
          'employerId',
          'status',
          'moderationStatus'
        ];
  final haystack = normalize([
    record.id,
    for (final field in fields) record.data[field]?.toString() ?? '',
  ].join(' '));
  return haystack.contains(needle);
}
