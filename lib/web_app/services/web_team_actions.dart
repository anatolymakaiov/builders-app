import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'web_profile_communication.dart';

class WebTeamActions {
  final db = FirebaseFirestore.instance;
  String get uid => FirebaseAuth.instance.currentUser!.uid;

  static List<String> memberIds(Map<String, dynamic> data) {
    final ids = <String>{};
    for (final field in const ['members', 'memberIds']) {
      final value = data[field];
      if (value is! List) continue;
      for (final item in value) {
        final id = item is String
            ? item
            : item is Map
                ? (item['userId'] ??
                        item['uid'] ??
                        item['workerId'] ??
                        item['id'])
                    ?.toString()
                : null;
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    for (final field in const ['memberStatuses', 'membersStatus']) {
      final statuses = data[field];
      if (statuses is! Map) continue;
      statuses.forEach((key, value) {
        final status = value?.toString().toLowerCase().trim() ?? '';
        if (!const {'removed', 'deleted', 'inactive', 'left', 'rejected'}
            .contains(status)) {
          ids.add(key.toString());
        }
      });
    }
    return ids.where((id) => id.isNotEmpty).toList();
  }

  bool leader(Map<String, dynamic> data) => const [
        'ownerId',
        'createdBy',
        'leaderId',
      ].any((field) => data[field]?.toString() == uid);

  Future<void> changeMember(String teamId,
      {String? removeId, String? search}) async {
    String? addId;
    final current = (await db.collection('users').doc(uid).get()).data();
    if (WebProfileCommunication.unavailable(current)) {
      throw StateError(
          'Your profile is temporarily suspended. Please contact Administrator.');
    }
    if (search != null) {
      for (final field in ['phone', 'nickname', 'nickName', 'username']) {
        final result = await db
            .collection('users')
            .where(field, isEqualTo: search.trim())
            .limit(1)
            .get();
        if (result.docs.isEmpty) continue;
        final worker = result.docs.first;
        if (worker.data()['role'] != 'worker' ||
            WebProfileCommunication.unavailable(worker.data())) {
          throw StateError('Worker is unavailable.');
        }
        addId = worker.id;
        break;
      }
      if (addId == null) throw StateError('Worker not found.');
    }
    final ref = db.collection('teams').doc(teamId);
    await db.runTransaction((tx) async {
      final team = (await tx.get(ref)).data();
      if (WebProfileCommunication.unavailable(team)) {
        throw StateError('Team is no longer available.');
      }
      final isLeader = leader(team!);
      final members = memberIds(team);
      final leaving = removeId == uid;
      if ((!isLeader && !leaving) || (isLeader && leaving)) {
        throw StateError('Only the team leader can manage team members.');
      }
      final id = addId ?? removeId;
      if (id == null) return;
      if (addId != null && members.contains(id)) {
        throw StateError('Worker is already in this team.');
      }
      if (removeId != null && !members.contains(id)) {
        throw StateError('This worker is no longer in the team.');
      }
      addId != null ? members.add(id) : members.remove(id);
      tx.update(ref, {
        'members': members,
        if (team.containsKey('memberIds')) 'memberIds': members,
        'memberCount': members.length,
        'memberStatuses.$id': addId != null ? 'active' : FieldValue.delete(),
        if (team.containsKey('membersStatus'))
          'membersStatus.$id': addId != null ? 'active' : FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp()
      });
    });
  }

  Future<void> delete(String teamId) async {
    await _ensureCurrentUserActive();
    final ref = db.collection('teams').doc(teamId);
    final data = (await ref.get()).data();
    if (data == null) throw StateError('Team is no longer available.');
    if (!leader(data)) {
      throw StateError('Only the team leader can delete the team.');
    }
    final portfolio = await ref.collection('portfolio').get();
    final batch = db.batch();
    for (final doc in portfolio.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(ref);
    await batch.commit();
  }

  Future<void> addPhotos(String teamId) async {
    await _ensureCurrentUserActive();
    final team = (await db.collection('teams').doc(teamId).get()).data();
    if (team == null || !leader(team)) {
      throw StateError('Only the team leader can edit the team.');
    }
    final files = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    for (final file in files?.files ?? <PlatformFile>[]) {
      if (file.bytes == null) continue;
      final name = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final ref = FirebaseStorage.instance.ref(
          'team_portfolio/$teamId/${DateTime.now().microsecondsSinceEpoch}_$name');
      await ref.putData(file.bytes!);
      final url = await ref.getDownloadURL();
      await db.collection('teams').doc(teamId).collection('portfolio').add({
        'image': url,
        'imageUrl': url,
        'createdAt': FieldValue.serverTimestamp()
      });
    }
  }

  Future<void> _ensureCurrentUserActive() async {
    final current = (await db.collection('users').doc(uid).get()).data();
    if (WebProfileCommunication.unavailable(current)) {
      throw StateError(
        'Your profile is temporarily suspended. Please contact Administrator.',
      );
    }
  }
}
