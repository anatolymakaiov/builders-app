import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/chat_service.dart';
import 'web_profile_communication.dart';
import 'web_profile_data_service.dart';

class WebChatRecipient {
  const WebChatRecipient({
    required this.id,
    required this.role,
    required this.name,
    required this.avatarUrl,
    required this.context,
    this.memberIds = const [],
  });

  final String id;
  final String role;
  final String name;
  final String avatarUrl;
  final String context;
  final List<String> memberIds;
}

class WebChatRecipientSearchService {
  WebChatRecipientSearchService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<WebChatRecipient>> search({
    required String query,
    required String currentUserId,
    required String currentRole,
  }) async {
    final needle = _normalize(query);
    if (needle.length < 2) return const [];

    final isEmployer = _isEmployer(currentRole);
    final results = <WebChatRecipient>[];
    final roles = isEmployer ? const ['worker'] : const ['employer', 'company'];

    for (final role in roles) {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: role)
          .limit(150)
          .get();
      for (final doc in snapshot.docs) {
        if (doc.id == currentUserId) continue;
        final data = doc.data();
        if (WebProfileCommunication.unavailable(data)) continue;
        final profile = WebProfileData(id: doc.id, data: data);
        if (!_matches(needle, [
          profile.displayName,
          profile.trade,
          profile.location,
          profile.city,
          profile.postcode,
        ])) {
          continue;
        }
        final details = isEmployer
            ? [profile.trade, profile.location]
            : [profile.location, profile.city, profile.postcode];
        results.add(WebChatRecipient(
          id: doc.id,
          role: isEmployer ? 'worker' : 'employer',
          name: profile.displayName,
          avatarUrl: profile.avatarUrl,
          context: details.where((item) => item.isNotEmpty).toSet().join(' · '),
        ));
      }
    }

    final teams = await _firestore.collection('teams').limit(150).get();
    for (final doc in teams.docs) {
      final data = doc.data();
      if (WebProfileCommunication.unavailable(data)) continue;
      final team = WebTeamData(id: doc.id, data: data);
      final memberIds = _memberIds(data);
      if (memberIds.isEmpty ||
          (!isEmployer && !memberIds.contains(currentUserId))) {
        continue;
      }
      if (!_matches(needle, [team.name, team.trade, team.description])) {
        continue;
      }
      final memberLabel =
          '${memberIds.length} member${memberIds.length == 1 ? '' : 's'}';
      results.add(WebChatRecipient(
        id: doc.id,
        role: 'team',
        name: team.name,
        avatarUrl: team.avatarUrl,
        context: [team.trade, memberLabel]
            .where((item) => item.isNotEmpty)
            .join(' · '),
        memberIds: memberIds,
      ));
    }

    results.sort((a, b) {
      final aStarts = _normalize(a.name).startsWith(needle);
      final bStarts = _normalize(b.name).startsWith(needle);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return results.take(25).toList();
  }

  Future<String> openOrCreate({
    required String currentUserId,
    required String currentRole,
    required WebChatRecipient recipient,
  }) async {
    final existing = await _existingChat(currentUserId, recipient);
    if (existing != null) return existing;

    if (recipient.role == 'team') {
      if (!_isEmployer(currentRole)) {
        return ChatService.getOrCreateInternalTeamChat(
          teamId: recipient.id,
          teamName: recipient.name,
          members: recipient.memberIds,
        );
      }
      return ChatService.getOrCreateTeamChat(
        teamId: recipient.id,
        employerId: currentUserId,
        jobId: '',
        members: recipient.memberIds,
      );
    }

    final isEmployer = _isEmployer(currentRole);
    return ChatService.getOrCreateChat(
      workerId: isEmployer ? recipient.id : currentUserId,
      employerId: isEmployer ? currentUserId : recipient.id,
      jobId: '',
      jobTitle: 'General',
    );
  }

  Future<String?> _existingChat(
    String currentUserId,
    WebChatRecipient recipient,
  ) async {
    final snapshot = await _firestore
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .limit(100)
        .get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (recipient.role == 'team') {
        if (data['teamId']?.toString() == recipient.id) return doc.id;
        continue;
      }
      if (data['type'] == 'team' || data['type'] == 'internal_team') continue;
      final participants = <String>{
        ..._ids(data['participants']),
        ..._ids(data['participantIds']),
        ..._ids(data['members']),
      };
      if (participants.contains(recipient.id) ||
          data['workerId']?.toString() == recipient.id ||
          data['employerId']?.toString() == recipient.id) {
        return doc.id;
      }
    }
    return null;
  }

  bool _matches(String needle, Iterable<String> values) => values
      .map(_normalize)
      .any((value) => value.isNotEmpty && value.contains(needle));

  bool _isEmployer(String role) =>
      role.toLowerCase() == 'employer' || role.toLowerCase() == 'company';

  String _normalize(String value) => value.trim().toLowerCase();

  List<String> _memberIds(Map<String, dynamic> data) {
    final ids = <String>{};
    for (final key in const ['members', 'memberIds']) {
      final value = data[key];
      if (value is! List) continue;
      for (final item in value) {
        if (item is String && item.trim().isNotEmpty) ids.add(item.trim());
        if (item is Map) {
          final id =
              (item['userId'] ?? item['uid'] ?? item['id'])?.toString().trim();
          if (id != null && id.isNotEmpty) ids.add(id);
        }
      }
    }
    for (final key in const ['ownerId', 'createdBy', 'leaderId']) {
      final id = data[key]?.toString().trim();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    return ids.toList();
  }

  List<String> _ids(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((id) => id.isNotEmpty)
          .toList();
    }
    if (value is Map) return value.keys.map((key) => key.toString()).toList();
    return const [];
  }
}
