import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'web_chat_media_service.dart';
import 'web_data_state.dart';

class WebChatSummary {
  const WebChatSummary({
    required this.id,
    required this.data,
    this.displayData,
    this.jobData,
  });

  final String id;
  final Map<String, dynamic> data;
  final Map<String, dynamic>? displayData;
  final Map<String, dynamic>? jobData;

  String get title {
    final isTeam = data['type'] == 'team' || data['type'] == 'internal_team';
    if (isTeam) {
      return _firstText(displayData, const ['name', 'teamName'], 'Team');
    }
    return _firstText(
      displayData,
      const [
        'companyName',
        'name',
        'displayName',
        'firstName',
        'workerName',
      ],
      'User',
    );
  }

  String get lastMessage {
    final text = (data['lastMessage'] ?? '').toString().trim();
    if (text.isNotEmpty) return text;
    final type = lastMessageType;
    if (type == 'image') return 'Photo';
    if (type == 'video') return 'Video';
    if (type == 'audio') return 'Voice message';
    if (type == 'attachments') return 'Attachments';
    return '';
  }

  String get lastMessageType => (data['lastMessageType'] ?? 'text').toString();
  Timestamp? get updatedAt => data['updatedAt'] is Timestamp
      ? data['updatedAt'] as Timestamp
      : data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : null;

  String avatarFor(String uid) {
    return _firstText(
      displayData,
      const [
        'avatarUrl',
        'profilePhotoUrl',
        'photoUrl',
        'photo',
        'companyLogo',
        'companyLogoUrl',
        'companyAvatarUrl',
        'teamLogo',
        'logo',
      ],
      '',
    );
  }

  bool unreadFor(String uid) {
    final unreadFor = data['unreadFor'];
    return unreadFor is List && unreadFor.contains(uid);
  }
}

class WebMessageItem {
  const WebMessageItem({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, dynamic> data;

  bool get deletedForEveryone => data['deletedForEveryone'] == true;
  bool get edited => data['editedAt'] != null;
  String get type => (data['type'] ?? 'text').toString();
  String get text => (data['text'] ?? '').toString();
  List<WebChatAttachment> get attachments => normalizeWebChatAttachments(data);
}

class WebChatThread {
  const WebChatThread({
    required this.chat,
    required this.messages,
  });

  final WebChatSummary chat;
  final List<WebMessageItem> messages;
}

class WebChatsDataService {
  WebChatsDataService({
    FirebaseFirestore? firestore,
    this.pollInterval = const Duration(seconds: 4),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration pollInterval;
  final _profileCache = <String, Map<String, dynamic>?>{};
  final _teamCache = <String, Map<String, dynamic>?>{};
  final _jobCache = <String, Map<String, dynamic>?>{};

  Stream<WebDataState<List<WebChatSummary>>> chats(String uid) {
    return _poll(
      () => loadChats(uid),
      interval: pollInterval,
      empty: const <WebChatSummary>[],
      logPrefix: 'WEB CHATS LOAD ERROR',
    );
  }

  Stream<WebDataState<WebChatThread?>> chatThread(String chatId, String uid) {
    return _poll(
      () => loadThread(chatId, uid),
      interval: const Duration(seconds: 3),
      empty: null,
      logPrefix: 'WEB CHATS LOAD ERROR',
    );
  }

  Future<List<WebChatSummary>> loadChats(String uid) async {
    final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final query in [
      _firestore.collection('chats').where('workerId', isEqualTo: uid),
      _firestore.collection('chats').where('employerId', isEqualTo: uid),
      _firestore.collection('chats').where('senderId', isEqualTo: uid),
      _firestore.collection('chats').where('receiverId', isEqualTo: uid),
      _firestore.collection('chats').where('targetProfileId', isEqualTo: uid),
      _firestore.collection('chats').where('participants', arrayContains: uid),
      _firestore
          .collection('chats')
          .where('participantIds', arrayContains: uid),
      _firestore.collection('chats').where('members', arrayContains: uid),
    ]) {
      final snapshot = await query.get();
      for (final doc in snapshot.docs) {
        docsById[doc.id] = doc;
      }
    }

    final chats = <WebChatSummary>[];
    for (final doc in docsById.values) {
      final data = doc.data();
      if (_isHiddenFor(data, uid)) continue;
      chats.add(await _summary(doc.id, data, uid));
    }
    chats.sort((a, b) {
      final aTime = a.updatedAt;
      final bTime = b.updatedAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return chats;
  }

  Future<WebChatThread?> loadThread(String chatId, String uid) async {
    final chatDoc = await _firestore.collection('chats').doc(chatId).get();
    final chatData = chatDoc.data();
    if (!chatDoc.exists || chatData == null || _isHiddenFor(chatData, uid)) {
      return null;
    }

    final messageSnapshot = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .get();
    final messages = messageSnapshot.docs.where((doc) {
      final hiddenFor = doc.data()['hiddenFor'];
      return hiddenFor is! List || !hiddenFor.contains(uid);
    }).map((doc) {
      return WebMessageItem(id: doc.id, data: doc.data());
    }).toList();

    return WebChatThread(
      chat: await _summary(chatId, chatData, uid),
      messages: messages,
    );
  }

  Future<void> sendMessage({
    required String chatId,
    String? messageId,
    required String uid,
    required String text,
    List<WebChatAttachment> attachments = const [],
  }) async {
    final clean = text.trim();
    if (clean.isEmpty && attachments.isEmpty) return;

    final chatRef = _firestore.collection('chats').doc(chatId);
    final chatDoc = await chatRef.get();
    final chatData = chatDoc.data();
    if (chatData == null) {
      throw StateError('Chat is no longer available.');
    }
    final recipients =
        _participantIds(chatData).where((id) => id != uid).toSet().toList();
    final isWorker = chatData['workerId']?.toString() == uid;
    final messageRef = messageId == null
        ? chatRef.collection('messages').doc()
        : chatRef.collection('messages').doc(messageId);
    final firstAttachment = attachments.isNotEmpty ? attachments.first : null;
    final messageType = attachments.isEmpty
        ? 'text'
        : attachments.length == 1 && firstAttachment?.type != 'file'
            ? firstAttachment!.type
            : 'attachments';
    final preview = clean.isNotEmpty
        ? clean
        : attachments.isNotEmpty
            ? webChatAttachmentPreview(attachments)
            : '';

    final batch = _firestore.batch();
    batch.set(messageRef, {
      'messageId': messageRef.id,
      'chatId': chatId,
      'type': messageType,
      'text': clean,
      'attachments': attachments.map((item) => item.toMap()).toList(),
      if (firstAttachment != null) 'mediaUrl': firstAttachment.url,
      if (firstAttachment?.type == 'image') 'imageUrl': firstAttachment!.url,
      if (firstAttachment?.type == 'video') 'videoUrl': firstAttachment!.url,
      if (firstAttachment?.type == 'audio') 'audioUrl': firstAttachment!.url,
      if (firstAttachment != null) 'fileName': firstAttachment.fileName,
      'senderId': uid,
      'senderRole': isWorker ? 'worker' : 'employer',
      'createdAt': FieldValue.serverTimestamp(),
      'readBy': [uid],
    });
    batch.update(chatRef, {
      'lastMessage': preview,
      'lastMessageType': messageType,
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadFor': FieldValue.arrayUnion(recipients),
      if (isWorker)
        'unreadCount_employer': FieldValue.increment(1)
      else
        'unreadCount_worker': FieldValue.increment(1),
      'typing_worker': false,
      'typing_employer': false,
    });
    await batch.commit();
  }

  Future<void> sendText({
    required String chatId,
    required String uid,
    required String text,
  }) {
    return sendMessage(chatId: chatId, uid: uid, text: text);
  }

  String newMessageId(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc()
        .id;
  }

  Future<void> markRead(String chatId, String uid) async {
    await _firestore.collection('chats').doc(chatId).set({
      'unreadFor': FieldValue.arrayRemove([uid]),
    }, SetOptions(merge: true));
  }

  Future<WebChatSummary> _summary(
    String id,
    Map<String, dynamic> data,
    String uid,
  ) async {
    final displayTarget = _displayTarget(data, uid);
    final displayData = displayTarget == null
        ? null
        : await _getCachedData(displayTarget.collection, displayTarget.id);
    final jobId = data['jobId']?.toString();
    final jobData = jobId == null || jobId.isEmpty
        ? null
        : await _getCachedData('jobs', jobId);
    return WebChatSummary(
      id: id,
      data: data,
      displayData: displayData,
      jobData: jobData,
    );
  }

  _DisplayTarget? _displayTarget(Map<String, dynamic> data, String uid) {
    final workerId = data['workerId']?.toString();
    final employerId = data['employerId']?.toString();
    final teamId = data['teamId']?.toString();
    final isTeam = data['type'] == 'team' || data['type'] == 'internal_team';
    if (isTeam && teamId != null && teamId.isNotEmpty) {
      return _DisplayTarget('teams', teamId);
    }
    final targetProfileId = data['targetProfileId']?.toString();
    if (targetProfileId != null &&
        targetProfileId.isNotEmpty &&
        targetProfileId != uid) {
      return _DisplayTarget('users', targetProfileId);
    }
    final otherId = uid == workerId ? employerId : workerId;
    final fallback = otherId ??
        _participantIds(data).firstWhere(
          (id) => id != uid,
          orElse: () => '',
        );
    if (fallback.isEmpty) return null;
    return _DisplayTarget('users', fallback);
  }

  Future<Map<String, dynamic>?> _getCachedData(
    String collection,
    String id,
  ) async {
    if (id.isEmpty) return null;
    final cache = switch (collection) {
      'teams' => _teamCache,
      'jobs' => _jobCache,
      _ => _profileCache,
    };
    if (cache.containsKey(id)) return cache[id];
    try {
      final data =
          (await _firestore.collection(collection).doc(id).get()).data();
      cache[id] = data;
      return data;
    } catch (error) {
      debugPrint('WEB CHAT ENRICH ERROR $collection/$id $error');
      cache[id] = null;
      return null;
    }
  }

  bool _isHiddenFor(Map<String, dynamic> data, String uid) {
    final hiddenFor = data['hiddenForUsers'];
    return hiddenFor is List && hiddenFor.contains(uid);
  }

  List<String> _participantIds(Map<String, dynamic> data) {
    final ids = <String>{};
    for (final key in const [
      'workerId',
      'employerId',
      'senderId',
      'receiverId',
      'targetProfileId',
    ]) {
      final id = data[key]?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    for (final key in const ['members', 'participants', 'participantIds']) {
      final value = data[key];
      if (value is List) {
        ids.addAll(
          value.map((item) => item.toString()).where((id) => id.isNotEmpty),
        );
      }
      if (value is Map) {
        ids.addAll(value.keys.map((key) => key.toString()));
      }
    }
    return ids.toList();
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
}

String _firstText(
  Map<String, dynamic>? data,
  List<String> keys,
  String fallback,
) {
  if (data == null) return fallback;
  for (final key in keys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return fallback;
}

class _DisplayTarget {
  const _DisplayTarget(this.collection, this.id);

  final String collection;
  final String id;
}
