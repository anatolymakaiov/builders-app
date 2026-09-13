import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

class WebChatListItem {
  const WebChatListItem({
    required this.chat,
    required this.chatData,
    this.displayData,
    this.jobData,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> chat;
  final Map<String, dynamic> chatData;
  final Map<String, dynamic>? displayData;
  final Map<String, dynamic>? jobData;
}

class WebChatThreadData {
  const WebChatThreadData({
    required this.chat,
    required this.chatData,
    required this.messages,
    this.profileData,
    this.jobData,
  });

  final DocumentSnapshot<Map<String, dynamic>> chat;
  final Map<String, dynamic> chatData;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> messages;
  final Map<String, dynamic>? profileData;
  final Map<String, dynamic>? jobData;
}

class WebChatDataService {
  WebChatDataService({
    FirebaseFirestore? firestore,
    this.chatListInterval = const Duration(seconds: 5),
    this.chatThreadInterval = const Duration(seconds: 3),
    this.unreadInterval = const Duration(seconds: 10),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration chatListInterval;
  final Duration chatThreadInterval;
  final Duration unreadInterval;

  Stream<int> unreadChats(String uid) {
    return _poll(
      () async {
        final snapshot = await _firestore
            .collection("chats")
            .where("unreadFor", arrayContains: uid)
            .get();
        return snapshot.docs.where((doc) {
          final data = doc.data();
          final hiddenForUsers = data["hiddenForUsers"];
          return hiddenForUsers is! List || !hiddenForUsers.contains(uid);
        }).length;
      },
      interval: unreadInterval,
      fallback: 0,
    );
  }

  Stream<List<WebChatListItem>> chatList(String uid) {
    return _poll(
      () => _loadChatList(uid),
      interval: chatListInterval,
      fallback: const <WebChatListItem>[],
    );
  }

  Stream<WebChatThreadData?> chatThread(String chatId, String uid) {
    return _poll(
      () => _loadChatThread(chatId, uid),
      interval: chatThreadInterval,
      fallback: null,
    );
  }

  Stream<T> _poll<T>(
    Future<T> Function() load, {
    required Duration interval,
    required T fallback,
  }) {
    Timer? timer;
    var lastValue = fallback;
    var loading = false;
    final controller = StreamController<T>();

    Future<void> refresh() async {
      if (loading || controller.isClosed) return;
      loading = true;
      try {
        lastValue = await load();
        if (!controller.isClosed) controller.add(lastValue);
      } catch (_) {
        if (!controller.isClosed) controller.add(lastValue);
      } finally {
        loading = false;
      }
    }

    controller.onListen = () {
      unawaited(refresh());
      timer = Timer.periodic(interval, (_) {
        unawaited(refresh());
      });
    };
    controller.onCancel = () async {
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<List<WebChatListItem>> _loadChatList(String uid) async {
    final snapshot = await _firestore.collection("chats").get();
    final chats = snapshot.docs.where((doc) {
      return _chatBelongsToUser(doc.data(), uid);
    }).toList();

    chats.sort((a, b) {
      final aTime = a.data()["updatedAt"];
      final bTime = b.data()["updatedAt"];
      if (aTime is! Timestamp && bTime is! Timestamp) return 0;
      if (aTime is! Timestamp) return 1;
      if (bTime is! Timestamp) return -1;
      return bTime.compareTo(aTime);
    });

    final items = <WebChatListItem>[];
    for (final chat in chats) {
      final data = chat.data();
      final displayTarget = _displayTarget(data, uid);
      final displayData = displayTarget == null
          ? null
          : await _getDocumentData(displayTarget.collection, displayTarget.id);
      final jobId = data["jobId"]?.toString();
      final jobData = jobId == null || jobId.isEmpty
          ? null
          : await _getDocumentData("jobs", jobId);

      items.add(
        WebChatListItem(
          chat: chat,
          chatData: data,
          displayData: displayData,
          jobData: jobData,
        ),
      );
    }

    return items;
  }

  Future<WebChatThreadData?> _loadChatThread(String chatId, String uid) async {
    final chatDoc = await _firestore.collection("chats").doc(chatId).get();
    final chatData = chatDoc.data();
    if (!chatDoc.exists || chatData == null) return null;

    final displayTarget = _displayTarget(chatData, uid);
    final profileData = displayTarget == null
        ? null
        : await _getDocumentData(displayTarget.collection, displayTarget.id);
    final jobId = chatData["jobId"]?.toString();
    final jobData = jobId == null || jobId.isEmpty
        ? null
        : await _getDocumentData("jobs", jobId);
    final messageSnapshot = await _firestore
        .collection("chats")
        .doc(chatId)
        .collection("messages")
        .orderBy("createdAt", descending: true)
        .get();
    final messages = messageSnapshot.docs.where((doc) {
      final data = doc.data();
      final hiddenFor = data["hiddenFor"];
      return hiddenFor is! List || !hiddenFor.contains(uid);
    }).toList();

    return WebChatThreadData(
      chat: chatDoc,
      chatData: chatData,
      messages: messages,
      profileData: profileData,
      jobData: jobData,
    );
  }

  Future<Map<String, dynamic>?> _getDocumentData(
    String collection,
    String id,
  ) async {
    if (id.isEmpty || id == "__missing_profile__") return null;
    final doc = await _firestore.collection(collection).doc(id).get();
    return doc.data();
  }

  _DisplayTarget? _displayTarget(Map<String, dynamic> data, String uid) {
    final workerId = data["workerId"]?.toString();
    final employerId = data["employerId"]?.toString();
    final isInternalTeamChat = data["type"] == "internal_team";
    final isTeamChat = data["type"] == "team" || data["teamId"] != null;
    final showTeamAvatar =
        isInternalTeamChat || (isTeamChat && uid == employerId);
    if (showTeamAvatar) {
      final teamId = data["teamId"]?.toString();
      if (teamId == null || teamId.isEmpty) return null;
      return _DisplayTarget("teams", teamId);
    }

    final isWorker = uid == workerId;
    final otherUserId = isTeamChat
        ? employerId
        : (isWorker ? employerId : workerId ?? _otherParticipantId(data, uid));
    if (otherUserId == null || otherUserId.isEmpty) return null;
    return _DisplayTarget("users", otherUserId);
  }

  String? _otherParticipantId(Map<String, dynamic> data, String uid) {
    final targetProfileId = data["targetProfileId"]?.toString();
    if (targetProfileId != null &&
        targetProfileId.isNotEmpty &&
        targetProfileId != uid) {
      return targetProfileId;
    }

    for (final key in const ["participantIds", "participants", "members"]) {
      for (final id in _idsFrom(data[key])) {
        if (id != uid) return id;
      }
    }

    return null;
  }

  bool _chatBelongsToUser(Map<String, dynamic> data, String uid) {
    final hiddenForUsers = data["hiddenForUsers"];
    if (hiddenForUsers is List && hiddenForUsers.contains(uid)) {
      return false;
    }

    return data["workerId"]?.toString() == uid ||
        data["employerId"]?.toString() == uid ||
        _idsFrom(data["participants"]).contains(uid) ||
        _idsFrom(data["participantIds"]).contains(uid) ||
        _idsFrom(data["members"]).contains(uid);
  }

  List<String> _idsFrom(dynamic value) {
    if (value is List) {
      return value
          .map((item) {
            if (item is Map) return item["userId"]?.toString() ?? "";
            return item.toString();
          })
          .where((id) => id.isNotEmpty)
          .toList();
    }
    if (value is Map) {
      final ids = <String>[
        ...value.keys.map((key) => key.toString()),
        ...value.values.map((item) {
          if (item is Map) return item["userId"]?.toString() ?? "";
          return item is String ? item : "";
        }),
      ];
      return ids.where((id) => id.isNotEmpty).toSet().toList();
    }
    return [];
  }
}

class _DisplayTarget {
  const _DisplayTarget(this.collection, this.id);

  final String collection;
  final String id;
}
