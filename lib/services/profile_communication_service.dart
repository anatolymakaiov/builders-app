import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/chat_screen.dart';
import '../widgets/phone_link.dart';
import 'chat_service.dart';

class ProfileCommunicationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static bool isUnavailable(Map<String, dynamic>? data) {
    if (data == null) return true;
    final status = data["status"]?.toString().trim().toLowerCase() ?? "";
    return data["deleted"] == true ||
        data["accountDeleted"] == true ||
        data["anonymised"] == true ||
        data["active"] == false ||
        status == "deleted" ||
        status == "inactive";
  }

  static Widget circleAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }

  static Future<void> openDirectProfileChat({
    required BuildContext context,
    required String targetUserId,
    required String targetRole,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid == targetUserId) return;

    final targetSnap = await _db.collection("users").doc(targetUserId).get();
    if (!context.mounted) return;
    if (!targetSnap.exists || isUnavailable(targetSnap.data())) {
      showUnavailable(context);
      return;
    }

    final currentSnap =
        await _db.collection("users").doc(currentUser.uid).get();
    if (!context.mounted) return;
    if (!currentSnap.exists || isUnavailable(currentSnap.data())) {
      showUnavailable(context);
      return;
    }

    final currentRole =
        currentSnap.data()?["role"]?.toString().toLowerCase() ?? "worker";
    final role = targetRole.toLowerCase();
    final chatId = await _findDirectChat(currentUser.uid, targetUserId) ??
        await _createProfileChat(
          currentUserId: currentUser.uid,
          currentRole: currentRole,
          targetUserId: targetUserId,
          targetRole: role,
        );

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)),
    );
  }

  static Future<void> openTeamProfileChat({
    required BuildContext context,
    required String teamId,
    required String teamName,
    required List<String> memberIds,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final teamSnap = await _db.collection("teams").doc(teamId).get();
    if (!context.mounted) return;
    if (!teamSnap.exists || isUnavailable(teamSnap.data())) {
      showUnavailable(context);
      return;
    }

    final currentSnap =
        await _db.collection("users").doc(currentUser.uid).get();
    final currentRole =
        currentSnap.data()?["role"]?.toString().toLowerCase() ?? "worker";

    final chatId = await _findTeamChat(currentUser.uid, teamId) ??
        (currentRole == "employer"
            ? await ChatService.getOrCreateTeamChat(
                teamId: teamId,
                employerId: currentUser.uid,
                jobId: "",
                members: memberIds,
              )
            : await ChatService.getOrCreateInternalTeamChat(
                teamId: teamId,
                teamName: teamName,
                members: memberIds.contains(currentUser.uid)
                    ? memberIds
                    : [currentUser.uid],
              ));

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)),
    );
  }

  static Future<void> callPhone(
    BuildContext context, {
    required Map<String, dynamic>? profileData,
    required String? phone,
  }) async {
    if (isUnavailable(profileData)) {
      showUnavailable(context);
      return;
    }

    final value = phone?.trim() ?? "";
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No phone number available.")),
      );
      return;
    }

    await PhoneLink.call(context, value);
  }

  static Future<String?> teamPhone(Map<String, dynamic> teamData) async {
    for (final key in const ["phone", "contactPhone", "teamPhone"]) {
      final value = teamData[key]?.toString().trim() ?? "";
      if (value.isNotEmpty) return value;
    }

    final leaderId = (teamData["leaderId"] ??
            teamData["ownerId"] ??
            teamData["createdBy"] ??
            "")
        .toString()
        .trim();
    if (leaderId.isEmpty) return null;

    final leaderSnap = await _db.collection("users").doc(leaderId).get();
    final leader = leaderSnap.data();
    if (isUnavailable(leader)) return null;
    return leader?["phone"]?.toString().trim();
  }

  static Future<String?> _findDirectChat(
      String currentId, String targetId) async {
    final snap = await _db
        .collection("chats")
        .where("participants", arrayContains: currentId)
        .limit(100)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final participants = _ids(data["participants"]) + _ids(data["members"]);
      if (participants.contains(targetId) ||
          data["workerId"]?.toString() == targetId ||
          data["employerId"]?.toString() == targetId) {
        return doc.id;
      }
    }

    return null;
  }

  static Future<String?> _findTeamChat(String currentId, String teamId) async {
    final snap = await _db
        .collection("chats")
        .where("participants", arrayContains: currentId)
        .limit(100)
        .get();

    for (final doc in snap.docs) {
      if (doc.data()["teamId"]?.toString() == teamId) return doc.id;
    }

    return null;
  }

  static Future<String> _createProfileChat({
    required String currentUserId,
    required String currentRole,
    required String targetUserId,
    required String targetRole,
  }) async {
    final currentIsEmployer = currentRole == "employer";
    final targetIsEmployer =
        targetRole == "employer" || targetRole == "company";

    if (currentIsEmployer == targetIsEmployer) {
      final participantIds = ChatService.uniqueParticipantIds([
        currentUserId,
        targetUserId,
      ]);
      final doc = await _db.collection("chats").add({
        "type": "direct",
        "participants": participantIds,
        "participantIds": participantIds,
        "members": participantIds,
        "participantRoles": {
          currentUserId: currentRole,
          targetUserId: targetRole,
        },
        "targetProfileId": targetUserId,
        "targetRole": targetRole,
        "lastMessage": "",
        "lastMessageType": "text",
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });
      return doc.id;
    }

    return ChatService.getOrCreateChat(
      workerId: currentIsEmployer ? targetUserId : currentUserId,
      employerId: currentIsEmployer ? currentUserId : targetUserId,
      jobId: "",
      jobTitle: "General",
    );
  }

  static List<String> _ids(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString())
        .where((id) => id.isNotEmpty)
        .toList();
  }

  static void showUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("This profile is no longer available.")),
    );
  }
}
