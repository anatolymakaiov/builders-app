import 'package:cloud_firestore/cloud_firestore.dart';

class ChatService {
  static final _firestore = FirebaseFirestore.instance;

  static String firstText(
    Map<String, dynamic>? data,
    List<String> keys, {
    String fallback = "",
  }) {
    if (data == null) return fallback;
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  static String jobTitle(
    Map<String, dynamic> chatData,
    Map<String, dynamic>? jobData,
  ) {
    return firstText(
      chatData,
      ["jobTitle", "position", "canonicalRoleName"],
      fallback: firstText(
        jobData,
        ["title", "jobTitle", "position", "canonicalRoleName", "trade"],
        fallback: "Job",
      ),
    );
  }

  static String chatDisplayName({
    required Map<String, dynamic> chatData,
    required Map<String, dynamic>? participantData,
    required Map<String, dynamic>? jobData,
    required bool currentUserIsWorker,
    required bool isInternalTeamChat,
    required bool showTeamAvatar,
  }) {
    final title = jobTitle(chatData, jobData);

    if (isInternalTeamChat) {
      final teamName = firstText(
        chatData,
        ["teamName"],
        fallback: firstText(participantData, ["name"], fallback: "Team"),
      );
      return "${teamName}_$title";
    }

    if (showTeamAvatar) {
      final teamName = firstText(
        participantData,
        ["name", "teamName"],
        fallback: firstText(chatData, ["teamName"], fallback: "Team"),
      );
      return "${teamName}_$title";
    }

    final participantName = currentUserIsWorker
        ? firstText(
            participantData,
            ["companyName", "name", "displayName"],
            fallback: firstText(
              chatData,
              ["companyName", "employerName"],
              fallback: "Company",
            ),
          )
        : firstText(
            participantData,
            ["name", "displayName", "workerName"],
            fallback: firstText(
              chatData,
              ["workerName", "applicantName"],
              fallback: "Worker",
            ),
          );

    return "${participantName}_$title";
  }

  static Future<String> getOrCreateChat({
    required String workerId,
    required String employerId,
    required String jobId,
    String? applicationId,
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
      await query.docs.first.reference.set({
        "type": "single",
        if (applicationId != null) "applicationId": applicationId,
        "participants": [workerId, employerId],
        "members": [workerId, employerId],
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return query.docs.first.id;
    }

    /// 🚀 2. создаём новый чат
    final docRef = _firestore.collection("chats").doc();

    final data = {
      "workerId": workerId,
      "employerId": employerId,
      "jobId": jobId,
      "type": "single",
      if (applicationId != null) "applicationId": applicationId,

      /// 🔥 ВАЖНО (для будущего списка чатов)
      "participants": [workerId, employerId],
      "members": [workerId, employerId],

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
    String? applicationId,
  }) async {
    final chatsRef = FirebaseFirestore.instance.collection("chats");

    final existing = await chatsRef
        .where("teamId", isEqualTo: teamId)
        .where("employerId", isEqualTo: employerId)
        .where("jobId", isEqualTo: jobId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.set({
        if (applicationId != null) "applicationId": applicationId,
        "members": [...members, employerId],
        "participants": [...members, employerId],
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return existing.docs.first.id;
    }

    final doc = await chatsRef.add({
      "type": "team",
      "teamId": teamId,
      if (applicationId != null) "applicationId": applicationId,
      "members": [...members, employerId],
      "participants": [...members, employerId],
      "employerId": employerId,
      "jobId": jobId,
      "lastMessage": "",
      "lastMessageType": "text",
      "unreadCount_worker": 0,
      "unreadCount_employer": 0,
      "typing_worker": false,
      "typing_employer": false,
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
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
