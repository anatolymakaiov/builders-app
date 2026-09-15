import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'web_data_state.dart';

class WebApplicationSummary {
  const WebApplicationSummary({
    required this.id,
    required this.data,
    this.jobData,
    this.profileData,
    this.teamData,
    this.memberProfiles = const <String, Map<String, dynamic>>{},
    this.jobUnavailable = false,
  });

  final String id;
  final Map<String, dynamic> data;
  final Map<String, dynamic>? jobData;
  final Map<String, dynamic>? profileData;
  final Map<String, dynamic>? teamData;
  final Map<String, Map<String, dynamic>> memberProfiles;
  final bool jobUnavailable;

  bool get isTeam {
    final type = (data['applicationType'] ?? data['type'] ?? '').toString();
    final teamId = data['teamId']?.toString() ?? '';
    return type == 'team' || teamId.isNotEmpty;
  }

  String get title => _firstText(
        isTeam ? teamData : profileData,
        const ['teamName', 'name', 'companyName', 'displayName', 'firstName'],
        _firstText(
          data,
          const ['teamName', 'workerName', 'applicantName', 'name'],
          isTeam ? 'Team application' : 'Application',
        ),
      );

  String get jobTitle => _firstText(
        data,
        const ['jobTitle', 'position', 'jobTrade'],
        _firstText(jobData, const ['title', 'position', 'trade'], 'Vacancy'),
      );

  String get companyName => _firstText(
        data,
        const ['companyName', 'employerName'],
        _firstText(jobData, const ['companyName', 'employerName'], 'Company'),
      );

  String get status =>
      _firstText(data, const ['status', 'applicationStatus'], 'submitted');

  Map<String, dynamic> get offer {
    final raw = data['offer'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  String get workerId =>
      (data['workerId'] ?? data['applicantId'])?.toString().trim() ?? '';

  String get employerId =>
      (data['employerId'] ?? data['ownerId'])?.toString().trim() ?? '';

  String get teamId => data['teamId']?.toString().trim() ?? '';

  String get trade => _firstText(
        data,
        const ['jobTrade', 'trade', 'position', 'jobType'],
        _firstText(jobData, const ['trade', 'position', 'jobType'], ''),
      );

  String get site => _firstText(
        data,
        const ['jobSite', 'site', 'siteAddress', 'fullAddress', 'location'],
        _firstText(jobData, const ['site', 'siteAddress', 'fullAddress'], ''),
      );

  String get message => _firstText(
        data,
        const ['message', 'coverLetter', 'applicationMessage', 'note'],
        '',
      );

  int get workersCount {
    final value = data['workersCount'];
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
    return memberIds.length;
  }

  List<String> get memberIds {
    final ids = <String>{};
    ids.addAll(_idsFromListValue(data['members']));
    ids.addAll(_idsFromListValue(data['memberIds']));
    return ids.toList();
  }

  List<String> get selectedWorkerIds {
    final raw = offer['selectedWorkerIds'] ?? data['selectedWorkerIds'];
    if (raw is! List) return const [];
    return raw
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  List<String> get selectedWorkerNames {
    final raw = offer['selectedWorkerNames'] ?? data['selectedWorkerNames'];
    if (raw is! List) return const [];
    return raw
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  bool unreadFor(String uid) {
    final unreadFor = data['unreadFor'];
    return unreadFor is List &&
        unreadFor.map((item) => item.toString()).contains(uid);
  }

  Timestamp? get activityAt {
    for (final key in const [
      'applicationActivityAt',
      'updatedAt',
      'createdAt',
    ]) {
      final value = data[key];
      if (value is Timestamp) return value;
    }
    return null;
  }

  String get avatarUrl => _firstText(
        isTeam && teamData != null ? teamData : profileData,
        const [
          'avatarUrl',
          'companyLogoUrl',
          'employerAvatarUrl',
          'photoUrl',
          'profilePhotoUrl',
          'photo',
          'companyLogo',
          'companyAvatarUrl',
          'teamLogo',
          'logo',
        ],
        _firstText(
          data,
          const [
            'companyLogoUrl',
            'employerAvatarUrl',
            'avatarUrl',
            'photoUrl',
            'profilePhotoUrl',
          ],
          '',
        ),
      );

  String get companyLogoUrl => _firstText(
        data,
        const ['companyLogoUrl', 'companyLogo', 'employerAvatarUrl'],
        _firstText(
          jobData,
          const ['companyLogoUrl', 'companyLogo', 'logo', 'avatarUrl'],
          '',
        ),
      );

  String memberName(String id) {
    return _firstText(
      memberProfiles[id],
      const ['name', 'displayName', 'firstName', 'email'],
      id,
    );
  }
}

class WebApplicationsDataService {
  WebApplicationsDataService({
    FirebaseFirestore? firestore,
    this.pollInterval = const Duration(seconds: 8),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration pollInterval;
  final _negativeEnrichmentCache = <String, DateTime>{};
  static const _negativeCacheTtl = Duration(minutes: 20);

  Stream<WebDataState<List<WebApplicationSummary>>> applications({
    required String uid,
    required String role,
  }) {
    return _poll(
      () => loadApplications(uid: uid, role: role),
      interval: pollInterval,
      empty: const <WebApplicationSummary>[],
      logPrefix: 'WEB APPLICATIONS LOAD ERROR',
    );
  }

  Stream<WebDataState<List<WebApplicationSummary>>> workerJobApplications(
    String uid,
  ) {
    return _poll(
      () => loadWorkerJobApplications(uid),
      interval: pollInterval,
      empty: const <WebApplicationSummary>[],
      logPrefix: 'WEB JOB APPLICATION PRESENCE LOAD ERROR',
    );
  }

  Future<List<WebApplicationSummary>> loadWorkerJobApplications(
    String uid,
  ) async {
    final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final queryErrors = <Object>[];
    final single = await _runApplicationQuery(
      source: 'worker_job_presence_single',
      query: _firestore
          .collection('applications')
          .where('workerId', isEqualTo: uid),
    );
    _mergeDocs(docsById, single.docs);
    if (single.error != null) queryErrors.add(single.error!);

    final teams = await _loadWorkerTeams(uid);
    for (final team in teams) {
      final result = await _runApplicationQuery(
        source: 'worker_job_presence_team:${team.id}',
        query: _firestore
            .collection('applications')
            .where('teamId', isEqualTo: team.id),
      );
      _mergeDocs(
        docsById,
        result.docs.where(
          (doc) => _isRelevantTeamApplication(doc.data(), team.id),
        ),
      );
      if (result.error != null) queryErrors.add(result.error!);
    }
    if (docsById.isEmpty && queryErrors.isNotEmpty) {
      throw queryErrors.first;
    }
    return docsById.values
        .map((doc) => WebApplicationSummary(id: doc.id, data: doc.data()))
        .toList();
  }

  Future<List<WebApplicationSummary>> loadApplications({
    required String uid,
    required String role,
  }) async {
    final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final queryErrors = <Object>[];

    if (role == 'employer') {
      final primary = await _runApplicationQuery(
        source: 'employer_primary',
        query: _firestore
            .collection('applications')
            .where('employerId', isEqualTo: uid),
      );
      _mergeDocs(docsById, primary.docs);
      if (primary.error != null) queryErrors.add(primary.error!);

      final ownerFallback = await _runApplicationQuery(
        source: 'employer_owner',
        query: _firestore
            .collection('applications')
            .where('ownerId', isEqualTo: uid),
      );
      _mergeDocs(docsById, ownerFallback.docs);
      if (ownerFallback.error != null) {
        debugPrint('WEB APPLICATIONS ownerId fallback ignored after error');
        if (primary.docs.isEmpty) queryErrors.add(ownerFallback.error!);
      }
    } else {
      final single = await _runApplicationQuery(
        source: 'worker_single',
        query: _firestore
            .collection('applications')
            .where('workerId', isEqualTo: uid),
      );
      _mergeDocs(docsById, single.docs);
      if (single.error != null) queryErrors.add(single.error!);

      final teams = await _loadWorkerTeams(uid);
      for (final team in teams) {
        final result = await _runApplicationQuery(
          source: 'team:${team.id}',
          query: _firestore
              .collection('applications')
              .where('teamId', isEqualTo: team.id),
        );
        final teamDocs = result.docs.where((doc) {
          return _isRelevantTeamApplication(doc.data(), team.id);
        }).toList();
        _mergeDocs(docsById, teamDocs);
        if (result.error != null) queryErrors.add(result.error!);
      }
    }

    if (docsById.isEmpty && queryErrors.isNotEmpty) {
      throw queryErrors.first;
    }

    final applications = <WebApplicationSummary>[];
    for (final doc in docsById.values) {
      applications.add(await _summary(doc.id, doc.data()));
    }
    applications.sort((a, b) {
      final aTime = a.activityAt;
      final bTime = b.activityAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return applications;
  }

  Future<_QueryResult> _runApplicationQuery({
    required String source,
    required Query<Map<String, dynamic>> query,
  }) async {
    try {
      final snapshot = await query.get();
      debugPrint('WEB APPLICATIONS $source loaded=${snapshot.docs.length}');
      return _QueryResult(docs: snapshot.docs);
    } on FirebaseException catch (error) {
      debugPrint(
        'WEB APPLICATIONS QUERY ERROR source=$source code=${error.code}',
      );
      return _QueryResult(docs: const [], error: error);
    } catch (error) {
      debugPrint('WEB APPLICATIONS QUERY ERROR source=$source error=$error');
      return _QueryResult(docs: const [], error: error);
    }
  }

  Future<List<_WorkerTeam>> _loadWorkerTeams(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('teams')
          .where(Filter.or(
            Filter('members', arrayContains: uid),
            Filter('memberIds', arrayContains: uid),
            Filter('ownerId', isEqualTo: uid),
            Filter('createdBy', isEqualTo: uid),
            Filter('leaderId', isEqualTo: uid),
            Filter('memberStatuses.$uid',
                whereIn: ['active', 'pending', 'accepted']),
            Filter('membersStatus.$uid',
                whereIn: ['active', 'pending', 'accepted']),
          ))
          .get();
      final teams = snapshot.docs
          .where((doc) => _isUserTeam(doc.data(), uid))
          .map((doc) => _WorkerTeam(id: doc.id, data: doc.data()))
          .toList();
      debugPrint(
        'WEB APPLICATIONS WORKER TEAMS loaded=${teams.length} '
        'candidates=${snapshot.docs.length}',
      );
      return teams;
    } on FirebaseException catch (error) {
      debugPrint(
        'WEB APPLICATIONS QUERY ERROR source=worker_teams code=${error.code}',
      );
      return const [];
    } catch (error) {
      debugPrint(
          'WEB APPLICATIONS QUERY ERROR source=worker_teams error=$error');
      return const [];
    }
  }

  bool _isUserTeam(Map<String, dynamic> data, String uid) {
    if (_isInactive(data)) return false;
    for (final key in const ['ownerId', 'createdBy', 'leaderId']) {
      if (data[key]?.toString() == uid) return true;
    }
    return _teamMemberIds(data).contains(uid);
  }

  bool _isRelevantTeamApplication(Map<String, dynamic> data, String teamId) {
    final type = (data['applicationType'] ?? data['type'] ?? '').toString();
    final status = data['status']?.toString().toLowerCase().trim();
    final appTeamId = data['teamId']?.toString();
    return type == 'team' &&
        appTeamId == teamId &&
        status != 'withdrawn' &&
        status != 'cancelled' &&
        status != 'deleted';
  }

  bool _isInactive(Map<String, dynamic> data) {
    final status = data['status']?.toString().toLowerCase().trim();
    return data['deleted'] == true ||
        data['accountDeleted'] == true ||
        data['active'] == false ||
        status == 'deleted' ||
        status == 'suspended' ||
        status == 'on_hold';
  }

  List<String> _teamMemberIds(Map<String, dynamic> data) {
    final ids = <String>{};
    ids.addAll(_idsFromListValue(data['members']));
    ids.addAll(_idsFromListValue(data['memberIds']));
    _addStatusMemberIds(ids, data['membersStatus']);
    _addStatusMemberIds(ids, data['memberStatuses']);
    return ids.toList();
  }

  void _addStatusMemberIds(Set<String> ids, dynamic value) {
    if (value is! Map) return;
    value.forEach((key, status) {
      final id = key?.toString().trim() ?? '';
      if (id.isEmpty) return;
      final normalized = status?.toString().toLowerCase().trim() ?? '';
      if (normalized == 'removed' ||
          normalized == 'deleted' ||
          normalized == 'inactive' ||
          normalized == 'left' ||
          normalized == 'rejected') {
        return;
      }
      ids.add(id);
    });
  }

  void _mergeDocs(
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> target,
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final doc in docs) {
      target[doc.id] = doc;
    }
  }

  Future<WebApplicationSummary> _summary(
    String id,
    Map<String, dynamic> data,
  ) async {
    final jobId = data['jobId']?.toString() ?? '';
    final workerId =
        (data['workerId'] ?? data['applicantId'])?.toString() ?? '';
    final teamId = data['teamId']?.toString() ?? '';
    final jobData = await _safeGet('jobs', jobId);
    final profileData = await _safeGet('users', workerId);
    final teamData = await _safeGet('teams', teamId);
    final memberProfiles = <String, Map<String, dynamic>>{};
    final isTeam =
        (data['applicationType'] ?? data['type'] ?? '').toString() == 'team' ||
            teamId.isNotEmpty;
    if (isTeam) {
      for (final memberId in _teamMemberIds({
        ...?teamData,
        ...data,
      })) {
        final memberData = await _safeGet('users', memberId);
        if (memberData != null) memberProfiles[memberId] = memberData;
      }
    }
    return WebApplicationSummary(
      id: id,
      data: data,
      jobData: jobData,
      profileData: profileData,
      teamData: teamData,
      memberProfiles: memberProfiles,
      jobUnavailable: jobId.isNotEmpty && jobData == null,
    );
  }

  Future<Map<String, dynamic>?> _safeGet(String collection, String id) async {
    if (id.isEmpty) return null;
    final cacheKey = '$collection/$id';
    final cachedAt = _negativeEnrichmentCache[cacheKey];
    if (cachedAt != null &&
        DateTime.now().difference(cachedAt) < _negativeCacheTtl) {
      return null;
    }
    try {
      final doc = await _firestore.collection(collection).doc(id).get();
      if (!doc.exists) {
        _negativeEnrichmentCache[cacheKey] = DateTime.now();
        return null;
      }
      return doc.data();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' || error.code == 'not-found') {
        _negativeEnrichmentCache[cacheKey] = DateTime.now();
      }
      debugPrint(
        'WEB APPLICATION ENRICH ERROR $collection/$id code=${error.code}',
      );
      return null;
    } catch (error) {
      debugPrint('WEB APPLICATION ENRICH ERROR $collection/$id $error');
      return null;
    }
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
    controller.onCancel = () => timer?.cancel();
    return controller.stream;
  }
}

List<String> _idsFromListValue(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) {
        if (item is String) return item;
        if (item is Map) {
          return (item['userId'] ??
                  item['uid'] ??
                  item['workerId'] ??
                  item['id'])
              ?.toString();
        }
        return null;
      })
      .whereType<String>()
      .where((id) => id.trim().isNotEmpty)
      .toSet()
      .toList();
}

class _QueryResult {
  const _QueryResult({
    required this.docs,
    this.error,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final Object? error;
}

class _WorkerTeam {
  const _WorkerTeam({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, dynamic> data;
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
