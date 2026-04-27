import 'package:cloud_firestore/cloud_firestore.dart';

class ChatService {
  static final _firestore = FirebaseFirestore.instance;

  static Future<String> getOrCreateChat({
    required String workerId,
    required String employerId,
    required String jobId,
    String? jobTitle, // 🔥 optional (на будущее)
  }) async {
    /// 🔍 1. ищем существующий чат
    final query = await _firestore
        .collection("chats")
        .where("workerId", isEqualTo: workerId)
        .where("employerId", isEqualTo: employerId)
        .where("jobId", isEqualTo: jobId)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return query.docs.first.id;
    }

    /// 🚀 2. создаём новый чат
    final docRef = _firestore.collection("chats").doc();

    final data = {
      "workerId": workerId,
      "employerId": employerId,
      "jobId": jobId,

      /// 🔥 ВАЖНО (для будущего списка чатов)
      "participants": [workerId, employerId],

      /// 🔥 optional (удобно для UI)
      if (jobTitle != null) "jobTitle": jobTitle,

      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),

      "lastMessage": "",
      "lastMessageType": "text",

      "unreadCount_worker": 0,
      "unreadCount_employer": 0,

      "typing_worker": false,
      "typing_employer": false,
    };

    await docRef.set(data);

    return docRef.id;
  }

  static Future<String> getOrCreateTeamChat({
    required String teamId,
    required String employerId,
    required String jobId,
    required List<String> members,
  }) async {
    final chatsRef = FirebaseFirestore.instance.collection("chats");

    final existing = await chatsRef
        .where("teamId", isEqualTo: teamId)
        .where("jobId", isEqualTo: jobId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return existing.docs.first.id;
    }

    final doc = await chatsRef.add({
      "type": "team",
      "teamId": teamId,
      "members": [...members, employerId],
      "employerId": employerId,
      "jobId": jobId,
      "createdAt": FieldValue.serverTimestamp(),
    });

    return doc.id;
  }

  static Future<String> getOrCreateInternalTeamChat({
    required String teamId,
    required String teamName,
    required List<String> members,
  }) async {
    final chatsRef = FirebaseFirestore.instance.collection("chats");

    final existing = await chatsRef
        .where("type", isEqualTo: "internal_team")
        .where("teamId", isEqualTo: teamId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.set({
        "members": members,
        "participants": members,
        "teamName": teamName,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return existing.docs.first.id;
    }

    final anchorUser = members.isNotEmpty ? members.first : "";
    final doc = await chatsRef.add({
      "type": "internal_team",
      "teamId": teamId,
      "teamName": teamName,
      "members": members,
      "participants": members,
      "workerId": anchorUser,
      "employerId": anchorUser,
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
      "lastMessage": "",
      "lastMessageType": "text",
      "unreadCount_worker": 0,
      "unreadCount_employer": 0,
      "typing_worker": false,
      "typing_employer": false,
    });

    return doc.id;
  }
}
