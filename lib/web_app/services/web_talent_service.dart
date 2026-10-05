import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/job_taxonomy_service.dart';
import '../../services/worker_availability_service.dart';

class WebTalentCandidate {
  const WebTalentCandidate({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.tradeIds,
    required this.area,
    required this.region,
    required this.experienceYears,
    required this.rating,
    required this.ratingCount,
    required this.availability,
    required this.availableFrom,
    required this.confirmedAt,
    required this.allowsInvites,
  });

  final String id;
  final String name;
  final String avatarUrl;
  final List<String> tradeIds;
  final String area;
  final String region;
  final int experienceYears;
  final double rating;
  final int ratingCount;
  final WorkerAvailability availability;
  final DateTime? availableFrom;
  final DateTime? confirmedAt;
  final bool allowsInvites;

  factory WebTalentCandidate.fromDocument(
      DocumentSnapshot<Map<String, dynamic>> document) {
    return WebTalentCandidate.fromMap(
        document.id, document.data() ?? const <String, dynamic>{});
  }

  factory WebTalentCandidate.fromMap(String id, Map<String, dynamic> data) {
    final status = WorkerAvailabilityService.fromProfile(data);
    return WebTalentCandidate(
      id: id,
      name: (data['displayNameShort'] as String?)?.trim().isNotEmpty == true
          ? (data['displayNameShort'] as String).trim()
          : 'Worker',
      avatarUrl: (data['avatarUrl'] as String?) ?? '',
      tradeIds: (data['tradeIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      area: (data['generalArea'] as String?) ?? '',
      region: (data['region'] as String?) ?? '',
      experienceYears: (data['experienceYears'] as num?)?.toInt() ?? 0,
      rating: (data['rating'] as num?)?.toDouble() ?? 0,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
      availability: status,
      availableFrom: WorkerAvailabilityService.availableFrom(data),
      confirmedAt: WorkerAvailabilityService.confirmedAt(data) ??
          DateTime.tryParse(data['availabilityConfirmedAt']?.toString() ?? ''),
      allowsInvites: WorkerAvailabilityService.allowsInvites(data),
    );
  }

  bool isRecentlyConfirmed(DateTime now) {
    if (confirmedAt == null || availability == WorkerAvailability.unknown) {
      return false;
    }
    return !WorkerAvailabilityService.shouldPrompt({
      WorkerAvailabilityService.field:
          WorkerAvailabilityService.value(availability),
      WorkerAvailabilityService.dateField: availableFrom,
      WorkerAvailabilityService.confirmedField:
          Timestamp.fromDate(confirmedAt!),
    }, now);
  }

  String availabilityLabel(DateTime now) {
    if (!isRecentlyConfirmed(now)) return 'Availability not recently confirmed';
    return WorkerAvailabilityService.label(availability, from: availableFrom);
  }

  String get tradeLabel => tradeIds
      .map((id) => JobTaxonomyService.roleFor(id)?.canonical ?? id)
      .join(' · ');

  bool matches(WebTalentFilters filters, DateTime now) {
    final nameQuery = filters.name.trim().toLowerCase();
    if (nameQuery.isNotEmpty && !name.toLowerCase().contains(nameQuery)) {
      return false;
    }
    final location = filters.location.trim().toLowerCase();
    if (location.isNotEmpty &&
        !area.toLowerCase().contains(location) &&
        !region.toLowerCase().contains(location)) {
      return false;
    }
    if (filters.invitesOnly && !allowsInvites) return false;
    if (filters.availability == null) return true;
    if (filters.availability == WorkerAvailability.unknown) {
      return !isRecentlyConfirmed(now);
    }
    return availability == filters.availability && isRecentlyConfirmed(now);
  }
}

class WebTalentFilters {
  const WebTalentFilters({
    required this.tradeId,
    this.name = '',
    this.location = '',
    this.availability,
    this.invitesOnly = false,
  });

  final String tradeId;
  final String name;
  final String location;
  final WorkerAvailability? availability;
  final bool invitesOnly;
}

class WebTalentPageResult<T> {
  const WebTalentPageResult(
      {required this.items, required this.lastDocument, required this.hasMore});
  final List<T> items;
  final QueryDocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}

List<WebTalentCandidate> mergeTalentCandidates(
    List<WebTalentCandidate> previous, List<WebTalentCandidate> next) {
  final byId = <String, WebTalentCandidate>{};
  for (final item in previous) {
    byId[item.id] = item;
  }
  for (final item in next) {
    byId[item.id] = item;
  }
  return byId.values.toList(growable: false);
}

class WebTalentService {
  WebTalentService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const pageSize = 25;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _pool(String employerId) =>
      _firestore
          .collection('employer_talent_pools')
          .doc(employerId)
          .collection('workers');

  Future<WebTalentPageResult<WebTalentCandidate>> findWorkers(
    WebTalentFilters filters, {
    QueryDocumentSnapshot<Map<String, dynamic>>? after,
  }) async {
    if (JobTaxonomyService.roleFor(filters.tradeId)?.id != filters.tradeId) {
      throw ArgumentError('Choose a trade before searching.');
    }
    Query<Map<String, dynamic>> query = _firestore
        .collection('worker_discovery')
        .where('discoveryVisible', isEqualTo: true)
        .where('tradeIds', arrayContains: filters.tradeId)
        .limit(pageSize);
    if (after != null) query = query.startAfterDocument(after);
    final snapshot = await query.get();
    final now = DateTime.now();
    return WebTalentPageResult(
      items: snapshot.docs
          .map(WebTalentCandidate.fromDocument)
          .where((candidate) => candidate.matches(filters, now))
          .toList(growable: false),
      lastDocument: snapshot.docs.isEmpty ? after : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  Future<WebTalentPageResult<String>> savedWorkerIds(
    String employerId, {
    QueryDocumentSnapshot<Map<String, dynamic>>? after,
  }) async {
    Query<Map<String, dynamic>> query =
        _pool(employerId).orderBy('savedAt', descending: true).limit(pageSize);
    if (after != null) query = query.startAfterDocument(after);
    final snapshot = await query.get();
    return WebTalentPageResult(
      items: snapshot.docs.map((doc) => doc.id).toList(growable: false),
      lastDocument: snapshot.docs.isEmpty ? after : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  Future<Map<String, WebTalentCandidate>> loadSavedCandidates(
      List<String> workerIds) async {
    final result = <String, WebTalentCandidate>{};
    for (var offset = 0; offset < workerIds.length; offset += 10) {
      final ids = workerIds.skip(offset).take(10).toList();
      final snapshot = await _firestore
          .collection('worker_discovery')
          .where('discoveryVisible', isEqualTo: true)
          .where(FieldPath.documentId, whereIn: ids)
          .limit(25)
          .get();
      for (final doc in snapshot.docs) {
        result[doc.id] = WebTalentCandidate.fromDocument(doc);
      }
    }
    return result;
  }

  Future<Set<String>> savedWorkerIdsFor(
      String employerId, List<String> workerIds) async {
    final saved = <String>{};
    for (var offset = 0; offset < workerIds.length; offset += 10) {
      final ids = workerIds.skip(offset).take(10).toList();
      final snapshot = await _pool(employerId)
          .where(FieldPath.documentId, whereIn: ids)
          .limit(10)
          .get();
      saved.addAll(snapshot.docs.map((doc) => doc.id));
    }
    return saved;
  }

  Future<void> save(String employerId, String workerId) async {
    final ref = _pool(employerId).doc(workerId);
    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      if (!current.exists) {
        transaction.set(ref, {
          'workerId': workerId,
          'savedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> unsave(String employerId, String workerId) =>
      _pool(employerId).doc(workerId).delete();
}
