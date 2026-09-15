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
    final userFields = isEmployer
        ? const [
            'name',
            'displayName',
            'firstName',
            'lastName',
            'trade',
            'position',
          ]
        : const [
            'companyName',
            'businessName',
            'displayName',
            'name',
          ];
    final userDocs = await _prefixDocuments('users', userFields, query);
    for (final doc in userDocs.values) {
      if (doc.id == currentUserId) continue;
      final data = doc.data();
      if (WebProfileCommunication.unavailable(data)) continue;
      final role = data['role']?.toString().toLowerCase() ?? '';
      final allowedRole = isEmployer
          ? role == 'worker'
          : role == 'employer' || role == 'company';
      if (!allowedRole) continue;
      final profile = WebProfileData(id: doc.id, data: data);
      final searchableValues = [for (final field in userFields) data[field]];
      if (!_hasPrefix(needle, searchableValues)) continue;
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

    const teamFields = [
      'nameLower',
      'name',
      'teamName',
      'trade',
      'specialization',
    ];
    final teamDocs = await _prefixDocuments('teams', teamFields, query);
    for (final doc in teamDocs.values) {
      final data = doc.data();
      if (WebProfileCommunication.unavailable(data)) continue;
      final team = WebTeamData(id: doc.id, data: data);
      final memberIds = _memberIds(data);
      if (memberIds.isEmpty ||
          (!isEmployer && !memberIds.contains(currentUserId))) {
        continue;
      }
      if (!_hasPrefix(
        needle,
        [for (final field in teamFields) data[field]],
      )) {
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
    final existing = await _existingChat(
      currentUserId,
      currentRole,
      recipient,
    );
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
    String currentRole,
    WebChatRecipient recipient,
  ) async {
    final currentIsEmployer = _isEmployer(currentRole);
    final primary = recipient.role == 'team' && !currentIsEmployer
        ? _firestore
            .collection('chats')
            .where('participants', arrayContains: currentUserId)
        : _firestore.collection('chats').where(
              currentIsEmployer ? 'employerId' : 'workerId',
              isEqualTo: currentUserId,
            );
    final primarySnapshot = await primary.get();
    final primaryMatch = _matchingChat(primarySnapshot.docs, recipient);
    if (primaryMatch != null) return primaryMatch;

    if (recipient.role == 'team' && !currentIsEmployer) return null;
    final legacySnapshot = await _firestore
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .get();
    return _matchingChat(legacySnapshot.docs, recipient);
  }

  String? _matchingChat(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    WebChatRecipient recipient,
  ) {
    for (final doc in docs) {
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

  Future<Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>>
      _prefixDocuments(
    String collection,
    List<String> fields,
    String rawQuery,
  ) async {
    final documents = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final prefixes = _prefixVariants(rawQuery);
    final requests = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (final field in fields) {
      for (final prefix in prefixes) {
        requests.add(
          _firestore
              .collection(collection)
              .orderBy(field)
              .startAt([prefix])
              .endAt(['$prefix\uf8ff'])
              .limit(12)
              .get(),
        );
      }
    }
    for (final snapshot in await Future.wait(requests)) {
      for (final doc in snapshot.docs) {
        documents[doc.id] = doc;
      }
    }
    return documents;
  }

  Set<String> _prefixVariants(String value) {
    final trimmed = value.trim();
    final lower = trimmed.toLowerCase();
    final title = lower.isEmpty
        ? lower
        : '${lower[0].toUpperCase()}${lower.substring(1)}';
    return {trimmed, lower, title, trimmed.toUpperCase()};
  }

  bool _hasPrefix(String needle, Iterable<dynamic> values) => values.any(
        (value) => _normalize(value?.toString() ?? '').startsWith(needle),
      );

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
