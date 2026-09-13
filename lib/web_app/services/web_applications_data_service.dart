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
  });

  final String id;
  final Map<String, dynamic> data;
  final Map<String, dynamic>? jobData;
  final Map<String, dynamic>? profileData;
  final Map<String, dynamic>? teamData;

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
        isTeam ? teamData : profileData,
        const [
          'avatarUrl',
          'photoUrl',
          'profilePhotoUrl',
          'companyLogo',
          'companyLogoUrl',
        ],
        '',
      );
}

class WebApplicationsDataService {
  WebApplicationsDataService({
    FirebaseFirestore? firestore,
    this.pollInterval = const Duration(seconds: 8),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration pollInterval;

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

  Future<List<WebApplicationSummary>> loadApplications({
    required String uid,
    required String role,
  }) async {
    final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final queries = role == 'employer'
        ? [
            _firestore.collection('applications').where(
                  'employerId',
                  isEqualTo: uid,
                ),
            _firestore.collection('applications').where(
                  'ownerId',
                  isEqualTo: uid,
                ),
          ]
        : [
            _firestore.collection('applications').where(
                  'workerId',
                  isEqualTo: uid,
                ),
            _firestore.collection('applications').where(
                  'members',
                  arrayContains: uid,
                ),
          ];

    for (final query in queries) {
      final snapshot = await query.get();
      for (final doc in snapshot.docs) {
        docsById[doc.id] = doc;
      }
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
    return WebApplicationSummary(
      id: id,
      data: data,
      jobData: jobData,
      profileData: profileData,
      teamData: teamData,
    );
  }

  Future<Map<String, dynamic>?> _safeGet(String collection, String id) async {
    if (id.isEmpty) return null;
    try {
      return (await _firestore.collection(collection).doc(id).get()).data();
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
