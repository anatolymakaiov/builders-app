import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/job.dart';
import '../../services/billing_service.dart';
import '../../services/job_alert_service.dart';
import 'web_applications_data_service.dart';
import 'web_chats_data_service.dart';
import 'web_data_state.dart';
import 'web_jobs_data_service.dart';

class WebShellBadges {
  const WebShellBadges({
    this.notifications = 0,
    this.chats = 0,
    this.applications = 0,
    this.adminInbox = 0,
  });

  final int notifications;
  final int chats;
  final int applications;
  final int adminInbox;
}

class WebNotificationItem {
  const WebNotificationItem({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, dynamic> data;

  bool get read => data['read'] == true;
  String get type => (data['type'] ?? '').toString().trim().toLowerCase();
  String get category =>
      (data['category'] ?? '').toString().trim().toLowerCase();
  Timestamp? get createdAt =>
      data['createdAt'] is Timestamp ? data['createdAt'] as Timestamp : null;
  String get title {
    final explicit = data['title']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return WebNotificationsDataService.notificationTitle(data);
  }

  String get body {
    for (final key in const ['body', 'message', 'preview', 'description']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }
}

class WebAdminMessageThread {
  const WebAdminMessageThread({
    required this.key,
    required this.messages,
    required this.latest,
  });

  final String key;
  final List<WebAdminMessage> messages;
  final WebAdminMessage latest;

  bool get unread => messages.any((message) => !message.readByReceiver);
}

class WebAdminMessage {
  const WebAdminMessage({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, dynamic> data;

  String get subject => (data['subject'] ?? 'Admin message').toString();
  String get message => (data['message'] ?? '').toString();
  String get senderName => (data['senderName'] ?? 'Administrator').toString();
  bool get readByReceiver => data['readByReceiver'] == true;
  bool get deletedByReceiver => data['deletedByReceiver'] == true;
  Timestamp? get createdAt =>
      data['createdAt'] is Timestamp ? data['createdAt'] as Timestamp : null;
  String get threadId => (data['threadId'] ?? id).toString();
}

class WebJobAlertItem {
  const WebJobAlertItem({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

class WebAccountDataService {
  WebAccountDataService({
    FirebaseFirestore? firestore,
    this.pollInterval = const Duration(seconds: 8),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration pollInterval;
  final _jobsService = WebJobsDataService();
  final _applicationsService = WebApplicationsDataService();
  final _chatsService = WebChatsDataService();
  WebShellBadges _lastBadges = const WebShellBadges();

  Stream<WebDataState<WebShellBadges>> badges({
    required String uid,
    required String role,
  }) {
    return _poll(
      () => loadBadges(uid: uid, role: role),
      interval: pollInterval,
      empty: _lastBadges,
      logPrefix: 'WEB SHELL BADGES LOAD ERROR',
    );
  }

  Future<WebShellBadges> loadBadges({
    required String uid,
    required String role,
  }) async {
    final results = await Future.wait<int>([
      unreadNotifications(uid),
      unreadChats(uid),
      unreadApplications(uid: uid, role: role),
      unreadAdminInbox(uid),
    ]);
    _lastBadges = WebShellBadges(
      notifications: results[0],
      chats: results[1],
      applications: results[2],
      adminInbox: results[3],
    );
    return _lastBadges;
  }

  Future<int> unreadNotifications(String uid) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();
    return snapshot.docs.length;
  }

  Future<int> unreadChats(String uid) async {
    try {
      final chats = await _chatsService.loadChats(uid);
      return chats.where((chat) => chat.unreadFor(uid)).length;
    } catch (error) {
      debugPrint('WEB CHAT BADGE LOAD ERROR $error');
      return _lastBadges.chats;
    }
  }

  Future<int> unreadApplications({
    required String uid,
    required String role,
  }) async {
    try {
      final applications =
          await _applicationsService.loadApplications(uid: uid, role: role);
      return applications.where((item) => item.unreadFor(uid)).length;
    } catch (error) {
      debugPrint('WEB APPLICATION BADGE LOAD ERROR $error');
      return _lastBadges.applications;
    }
  }

  Future<int> unreadAdminInbox(String uid) async {
    final snapshot = await _firestore
        .collection('admin_messages')
        .where('receiverId', isEqualTo: uid)
        .where('readByReceiver', isEqualTo: false)
        .get();
    return snapshot.docs
        .where((doc) => doc.data()['deletedByReceiver'] != true)
        .length;
  }

  Future<List<WebNotificationItem>> loadNotifications(String uid) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    return snapshot.docs
        .map((doc) => WebNotificationItem(id: doc.id, data: doc.data()))
        .toList();
  }

  Future<void> markNotificationRead(String uid, String notificationId) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .set({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markAllNotificationsRead(String uid) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.set(
          doc.reference,
          {
            'read': true,
            'readAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<List<Job>> loadSavedJobs(String uid) async {
    final savedSnapshot = await _firestore
        .collection('saved_jobs')
        .doc(uid)
        .collection('jobs')
        .get();
    final jobs = <Job>[];
    for (final saved in savedSnapshot.docs) {
      try {
        final jobDoc = await _firestore.collection('jobs').doc(saved.id).get();
        final data = jobDoc.data();
        if (!jobDoc.exists || data == null) continue;
        final job = Job.fromFirestore(jobDoc.id, data);
        if (!job.isPubliclyVisible) continue;
        jobs.add(job);
      } catch (error) {
        debugPrint('WEB SAVED JOB SKIPPED jobId=${saved.id} error=$error');
      }
    }
    jobs.sort((a, b) {
      final aDate = a.postedAt ?? a.createdAt;
      final bDate = b.postedAt ?? b.createdAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return jobs;
  }

  Future<void> unsaveJob(String uid, String jobId) {
    return _jobsService.toggleSavedJob(
      userId: uid,
      jobId: jobId,
      isSaved: true,
    );
  }

  Future<List<WebAdminMessageThread>> loadAdminInbox(String uid) async {
    final received = await _firestore
        .collection('admin_messages')
        .where('receiverId', isEqualTo: uid)
        .get();
    final sent = await _firestore
        .collection('admin_messages')
        .where('senderId', isEqualTo: uid)
        .get();
    final messages = <WebAdminMessage>[
      ...received.docs
          .map((doc) => WebAdminMessage(id: doc.id, data: doc.data())),
      ...sent.docs.map((doc) => WebAdminMessage(id: doc.id, data: doc.data())),
    ].where((message) {
      final isReceiver = message.data['receiverId'] == uid;
      final deleted = isReceiver
          ? message.data['deletedByReceiver'] == true
          : message.data['deletedBySender'] == true;
      return !deleted;
    }).toList();
    final grouped = <String, List<WebAdminMessage>>{};
    for (final message in messages) {
      final subject = message.subject.trim().toLowerCase();
      final participant = message.data['senderId'] == uid
          ? message.data['receiverId']?.toString() ?? 'admin'
          : message.data['senderId']?.toString() ?? 'admin';
      grouped.putIfAbsent('$participant::$subject', () => []).add(message);
    }
    final threads = <WebAdminMessageThread>[];
    for (final entry in grouped.entries) {
      final sorted = entry.value..sort(_compareAdminMessages);
      threads.add(WebAdminMessageThread(
        key: entry.key,
        messages: List.unmodifiable(sorted),
        latest: sorted.last,
      ));
    }
    threads.sort((a, b) => _compareAdminMessages(b.latest, a.latest));
    return threads;
  }

  Future<void> markAdminThreadRead(String uid, WebAdminMessageThread thread) {
    final batch = _firestore.batch();
    for (final message in thread.messages) {
      if (message.data['receiverId'] == uid && !message.readByReceiver) {
        batch.set(
            _firestore.collection('admin_messages').doc(message.id),
            {
              'readByReceiver': true,
              'readAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }
    }
    return batch.commit();
  }

  Future<void> replyToAdminThread({
    required String uid,
    required String role,
    required WebAdminMessageThread thread,
    required String message,
    required String senderName,
  }) async {
    final clean = message.trim();
    if (clean.isEmpty) return;
    final latest = thread.latest.data;
    final ref = _firestore.collection('admin_messages').doc();
    final threadId = latest['threadId']?.toString() ?? thread.latest.id;
    await ref.set({
      'threadId': threadId,
      'direction': 'outgoing',
      'senderId': uid,
      'senderName': senderName,
      'senderRole': role,
      'receiverId': 'admin',
      'receiverName': 'Admin',
      'receiverRole': 'admin',
      'recipientId': 'admin',
      'recipientRole': 'admin',
      'threadParticipants': [uid, 'admin'],
      'subject': thread.latest.subject,
      'message': clean,
      'type': 'admin_reply',
      'canReply': true,
      'readByAdmin': false,
      'readByReceiver': true,
      'deletedByReceiver': false,
      'deletedBySender': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<WebJobAlertItem>> loadJobAlerts(String uid) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('job_alerts')
        .where('active', isEqualTo: true)
        .get();
    final alerts = snapshot.docs
        .map((doc) => WebJobAlertItem(id: doc.id, data: doc.data()))
        .toList();
    alerts.sort((a, b) => _timestampMs(b.data['createdAt'])
        .compareTo(_timestampMs(a.data['createdAt'])));
    return alerts;
  }

  Future<void> saveJobAlert({
    required String uid,
    required String trade,
    required String jobType,
    required double distance,
    required String postcode,
    required double lat,
    required double lng,
  }) {
    return JobAlertService().saveWorkerAlert(
      userId: uid,
      trade: trade,
      jobType: jobType,
      distance: distance,
      postcode: postcode,
      lat: lat,
      lng: lng,
    );
  }

  Future<void> deleteJobAlert(String uid, String alertId) {
    return JobAlertService().deleteWorkerAlert(userId: uid, alertId: alertId);
  }

  Future<Map<String, dynamic>> loadBillingStatus() {
    return BillingService().getAuthoritativeCompanyBillingStatus();
  }

  Future<void> submitSupportRequest({
    required String uid,
    required String role,
    required Map<String, dynamic> userData,
    required String type,
    required String message,
  }) async {
    final requestTypes = role == 'worker'
        ? const {
            'technical_issue': 'Technical issue',
            'employer_complaint': 'Complaint about employer/company',
            'application_issue': 'Application issue',
            'profile_account_issue': 'Profile/account issue',
            'other': 'Other',
          }
        : const {
            'billing': 'Billing',
            'payment': 'Payment',
            'direct_debit': 'Direct debit',
            'job_posting_issue': 'Job posting issue',
            'technical_issue': 'Technical issue',
            'profile_company_account_issue': 'Profile/company account issue',
            'other': 'Other',
          };
    final label = requestTypes[type] ?? type;
    final supportRef = _firestore.collection('support_requests').doc();
    final threadRef = _firestore.collection('message_threads').doc();
    final senderName = role == 'employer'
        ? (userData['companyName'] ?? userData['name'] ?? 'Company').toString()
        : (userData['name'] ?? userData['displayName'] ?? 'Worker').toString();
    final now = FieldValue.serverTimestamp();
    await supportRef.set({
      'userId': uid,
      'userRole': role,
      'role': role,
      'type': type,
      'requestType': type,
      'typeLabel': label,
      'requestTypeLabel': label,
      'subject': label,
      'message': message.trim(),
      'attachments': const <Map<String, dynamic>>[],
      'hasAttachments': false,
      'status': 'open',
      'adminVisible': true,
      'readByAdmin': false,
      'viewedByAdmin': false,
      'threadId': threadRef.id,
      'adminMessageThreadId': threadRef.id,
      'createdAt': now,
      'updatedAt': now,
    });
    final adminMessageRef = _firestore.collection('admin_messages').doc();
    await adminMessageRef.set({
      'threadId': threadRef.id,
      'direction': 'incoming',
      'senderId': uid,
      'senderName': senderName,
      'senderRole': role,
      'receiverId': 'admin',
      'receiverName': 'Admin',
      'receiverRole': 'admin',
      'recipientId': 'admin',
      'recipientRole': 'admin',
      'threadParticipants': [uid, 'admin'],
      'audienceType': 'specific_admin',
      'canReply': true,
      'subject': 'Support: $label',
      'message': message.trim(),
      'type': 'support_request',
      'supportRequestType': type,
      'relatedSupportRequestId': supportRef.id,
      'relatedTargetType': 'support_request',
      'relatedTargetId': supportRef.id,
      'readByAdmin': false,
      'readByReceiver': true,
      'important': false,
      'deletedByAdmin': false,
      'deletedByReceiver': false,
      'deletedBySender': false,
      'attachments': const <Map<String, dynamic>>[],
      'hasAttachments': false,
      'createdAt': now,
    });
    await threadRef.set({
      'subject': 'Support: $label',
      'participants': [uid, 'admin'],
      'createdBy': uid,
      'userId': uid,
      'userRole': role,
      'threadType': 'support_request',
      'lastMessage': message.trim(),
      'lastMessageAt': now,
      'lastSenderId': uid,
      'unreadForAdmin': 1,
      'relatedSupportRequestId': supportRef.id,
      'updatedAt': now,
    });
  }

  Stream<WebDataState<T>> poll<T>(
    Future<T> Function() load, {
    required T empty,
    Duration? interval,
    String logPrefix = 'WEB ACCOUNT LOAD ERROR',
  }) {
    return _poll(
      load,
      interval: interval ?? pollInterval,
      empty: empty,
      logPrefix: logPrefix,
    );
  }

  static String notificationTitle(Map<String, dynamic> data) {
    return WebNotificationsDataService.notificationTitle(data);
  }
}

class WebNotificationsDataService {
  static String notificationTitle(Map<String, dynamic> data) {
    final type = data['type']?.toString().trim().toLowerCase() ?? '';
    final title = data['title']?.toString().trim();
    if (title != null && title.isNotEmpty) return title;
    return switch (type) {
      'application' => 'New application received',
      'accepted' => 'You got accepted',
      'rejected' => 'Application rejected',
      'message' => 'New message',
      'job_alert' => 'New matching job',
      'application_status' => 'Application status updated',
      'offer' => 'New offer received',
      'offer_accepted' => 'Offer accepted',
      'offer_rejected' => 'Offer rejected',
      'offer_expiry' => 'Offer expiry reminder',
      'work_start' || 'work_start_reminder' => 'Work start reminder',
      'job_status' => 'Job status updated',
      'billing' => 'Billing update',
      'report' => 'Complaint update',
      'admin_message' => 'Admin message',
      'package_approval' => 'Package approval update',
      'support' => 'Support request update',
      _ => 'Notification',
    };
  }
}

int _compareAdminMessages(WebAdminMessage a, WebAdminMessage b) {
  return _timestampMs(a.data['createdAt'])
      .compareTo(_timestampMs(b.data['createdAt']));
}

int _timestampMs(dynamic value) {
  return value is Timestamp ? value.millisecondsSinceEpoch : 0;
}

Stream<WebDataState<T>> _poll<T>(
  Future<T> Function() load, {
  required Duration interval,
  required T empty,
  required String logPrefix,
}) {
  Timer? timer;
  var loading = false;
  var lastValue = empty;
  final controller = StreamController<WebDataState<T>>();

  Future<void> refresh() async {
    if (loading || controller.isClosed) return;
    loading = true;
    try {
      lastValue = await load();
      if (!controller.isClosed) controller.add(WebDataState.data(lastValue));
    } catch (error) {
      debugPrint('$logPrefix $error');
      if (!controller.isClosed) {
        controller.add(WebDataState.error(error, lastData: lastValue));
      }
    } finally {
      loading = false;
    }
  }

  controller.onListen = () {
    controller.add(const WebDataState.loading());
    unawaited(refresh());
    timer = Timer.periodic(interval, (_) => unawaited(refresh()));
  };
  controller.onCancel = () {
    timer?.cancel();
  };
  return controller.stream;
}
