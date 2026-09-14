import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/chat_service.dart';
import '../../services/moderation_hold_service.dart';

class WebProfileCommunication {
  static bool unavailable(Map<String, dynamic>? data) =>
      data == null ||
      data['deleted'] == true ||
      data['accountDeleted'] == true ||
      data['active'] == false ||
      data['anonymised'] == true ||
      ['deleted', 'inactive'].contains(data['status']) ||
      ModerationHoldService.isProfileHeld(data);

  Future<String> message(String targetId) async {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    if (uid == targetId) throw StateError('Cannot message yourself.');
    final current = (await db.collection('users').doc(uid).get()).data();
    final target = (await db.collection('users').doc(targetId).get()).data();
    if (unavailable(current) || unavailable(target)) {
      throw StateError('This profile is no longer available.');
    }
    final role = current!['role']?.toString() ?? 'worker';
    final targetRole = target!['role']?.toString() ?? 'worker';
    final chats = await db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get();
    for (final doc in chats.docs) {
      final data = doc.data();
      final participants = data['participants'];
      if (data['type'] != 'team' &&
          data['type'] != 'internal_team' &&
          participants is List &&
          participants.contains(targetId)) {
        return doc.id;
      }
    }
    if ((role == 'employer') != (targetRole == 'employer')) {
      return ChatService.getOrCreateChat(
          workerId: role == 'employer' ? targetId : uid,
          employerId: role == 'employer' ? uid : targetId,
          jobId: '',
          jobTitle: 'General');
    }
    final doc = await db.collection('chats').add({
      'type': 'direct',
      'participants': [uid, targetId],
      'participantIds': [uid, targetId],
      'members': [uid, targetId],
      'participantRoles': {uid: role, targetId: targetRole},
      'targetProfileId': targetId,
      'targetRole': targetRole,
      'lastMessage': '',
      'lastMessageType': 'text',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }
}
