import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/job.dart';
import 'web_jobs_data_service.dart';
import 'web_data_state.dart';

class WebProfileData {
  const WebProfileData({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, dynamic> data;

  String get displayName {
    if (role == 'employer' || role == 'company') {
      return _firstText(data, const ['companyName', 'name'], 'Company');
    }
    final name = _firstText(data, const ['name', 'displayName'], '');
    if (name.isNotEmpty) return name;
    final first = _firstText(data, const ['firstName'], '');
    final last = _firstText(data, const ['lastName'], '');
    final fullName =
        [first, last].where((part) => part.trim().isNotEmpty).join(' ').trim();
    if (fullName.isNotEmpty) return fullName;
    return _firstText(
      data,
      const ['companyName', 'name', 'displayName', 'firstName', 'email'],
      'Profile',
    );
  }

  String get avatarUrl {
    if (role == 'employer' || role == 'company') {
      return _firstText(
        data,
        const [
          'companyLogo',
          'companyLogoUrl',
          'companyAvatarUrl',
          'logo',
          'avatarUrl',
          'profilePhotoUrl',
          'photoUrl',
          'photo',
        ],
        '',
      );
    }
    final photo = _firstText(data, const ['photo'], '');
    if (photo.isNotEmpty) return photo;
    return _firstText(
      data,
      const [
        'avatarUrl',
        'photoUrl',
        'profilePhotoUrl',
        'photo',
        'companyLogo',
        'companyLogoUrl',
        'companyAvatarUrl',
        'logo',
      ],
      '',
    );
  }

  String get headerUrl {
    return _firstText(
      data,
      const [
        'profileHeaderImage',
        'headerImage',
        'headerImageUrl',
        'backgroundImageUrl',
        'coverPhotoUrl',
        'companyHeaderUrl',
        'backgroundUrl',
        'backgroundImage',
      ],
      '',
    );
  }

  String get role => _firstText(data, const ['role', 'userRole'], '');
  String get email => _firstText(data, const ['email'], '');
  String get phone => _firstText(data, const ['phone', 'phoneNumber'], '');
  String get trade => _firstText(
        data,
        const ['trade', 'position', 'registrationPosition', 'profession'],
        '',
      );
  String get location => _firstText(data, const ['location', 'address'], '');
  String get addressLine1 => _firstText(data, const ['addressLine1'], '');
  String get addressLine2 => _firstText(data, const ['addressLine2'], '');
  String get addressLine3 => _firstText(data, const ['addressLine3'], '');
  String get city => _firstText(data, const ['city', 'town'], '');
  String get county => _firstText(data, const ['county'], '');
  String get postcode => _firstText(data, const ['postcode', 'postCode'], '');
  String get country => _firstText(data, const ['country'], '');
  String get bio => _firstText(data, const ['bio', 'description', 'about'], '');
  String get website => _firstText(data, const ['website', 'websiteUrl'], '');

  String get experience {
    final text = _firstText(data, const ['experience'], '');
    if (text.isNotEmpty) return text;
    final years = _firstText(data, const ['experienceYears'], '');
    final months = _firstText(data, const ['experienceMonths'], '');
    return [
      if (years.isNotEmpty) '$years years',
      if (months.isNotEmpty) '$months months'
    ].join(' ').trim();
  }

  List<String> listField(List<String> keys) {
    final values = <String>[];
    for (final key in keys) {
      final raw = data[key];
      if (raw is Iterable) {
        values.addAll(raw
            .map((item) => item?.toString().trim() ?? '')
            .where((item) => item.isNotEmpty));
      } else {
        final text = raw?.toString().trim() ?? '';
        if (text.isNotEmpty) values.add(text);
      }
    }
    return values.toSet().toList();
  }

  List<String> get companyPhotos => listField(const ['companyPhotos']);
  List<String> get portfolioUrls =>
      listField(const ['portfolio', 'portfolioUrls']);

  List<Map<String, String>> get references {
    final raw = data['references'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) {
          final value = Map<String, dynamic>.from(item);
          return {
            for (final key in const ['name', 'company', 'phone', 'email'])
              key: value[key]?.toString().trim() ?? '',
          };
        })
        .where((item) => item.values.any((value) => value.isNotEmpty))
        .toList();
  }
}

class WebPortfolioItem {
  const WebPortfolioItem({
    required this.id,
    required this.url,
    required this.data,
  });

  final String id;
  final String url;
  final Map<String, dynamic> data;
}

class WebTeamData {
  const WebTeamData({
    required this.id,
    required this.data,
    this.members = const <WebProfileData>[],
    this.portfolio = const <String>[],
  });

  final String id;
  final Map<String, dynamic> data;
  final List<WebProfileData> members;
  final List<String> portfolio;

  String get name => _firstText(data, const ['name', 'teamName'], 'Team');
  String get description => _firstText(data, const ['description', 'bio'], '');
  String get trade => _firstText(data, const ['trade', 'specialization'], '');
  String get avatarUrl => _firstText(
        data,
        const ['avatarUrl', 'photoUrl', 'photo', 'teamLogo', 'logo'],
        '',
      );
  String get headerUrl => _firstText(
        data,
        const [
          'profileHeaderImage',
          'headerImageUrl',
          'headerImage',
          'backgroundUrl',
          'backgroundImage',
        ],
        '',
      );
  String get ownerId => _firstText(data, const ['ownerId', 'createdBy'], '');
  String get leaderId => _firstText(data, const ['leaderId', 'ownerId'], '');
  int get memberCount => memberIds.length;

  List<String> get memberIds => _teamMemberIds(data);
}

class WebProfileDataService {
  WebProfileDataService({
    FirebaseFirestore? firestore,
    this.pollInterval = const Duration(seconds: 12),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration pollInterval;
  final _profileCache = <String, WebProfileData?>{};

  Stream<WebDataState<WebProfileData?>> profile(String uid) {
    Timer? timer;
    var loading = false;
    WebProfileData? lastValue;
    final controller = StreamController<WebDataState<WebProfileData?>>();

    Future<void> refresh() async {
      if (loading || controller.isClosed) return;
      loading = true;
      try {
        lastValue = await loadProfile(uid);
        if (!controller.isClosed) controller.add(WebDataState.data(lastValue));
      } catch (error) {
        debugPrint('WEB PROFILE LOAD ERROR $error');
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
      timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
    };
    controller.onCancel = () => timer?.cancel();
    return controller.stream;
  }

  Future<WebProfileData?> loadProfile(String uid) async {
    if (uid.trim().isEmpty) return null;
    final snapshot = await _firestore.collection('users').doc(uid).get();
    final data = snapshot.data();
    final profile = data == null ? null : WebProfileData(id: uid, data: data);
    _profileCache[uid] = profile;
    return profile;
  }

  Future<List<WebPortfolioItem>> loadWorkerPortfolio(String uid) async {
    final profileUrls = (_profileCache[uid]?.portfolioUrls ?? const <String>[]);
    final itemsByUrl = <String, WebPortfolioItem>{
      for (final url in profileUrls)
        url: WebPortfolioItem(id: url, url: url, data: const {}),
    };
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('portfolio')
          .get();
      for (final doc in snapshot.docs) {
        final url = _firstText(
            doc.data(), const ['imageUrl', 'image', 'url', 'photoUrl'], '');
        if (url.isNotEmpty) {
          itemsByUrl[url] =
              WebPortfolioItem(id: doc.id, url: url, data: doc.data());
        }
      }
    } catch (error) {
      debugPrint('WEB PROFILE PORTFOLIO LOAD ERROR $error');
    }
    final flat = await _firestore
        .collection('portfolio')
        .where('userId', isEqualTo: uid)
        .get();
    for (final doc in flat.docs) {
      final url =
          _firstText(doc.data(), const ['imageUrl', 'image', 'url'], '');
      if (url.isNotEmpty) {
        itemsByUrl[url] =
            WebPortfolioItem(id: doc.id, url: url, data: doc.data());
      }
    }
    return itemsByUrl.values.toList();
  }

  Future<List<WebTeamData>> loadWorkerTeams(String uid) async {
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
    final teams = <WebTeamData>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (_isInactive(data)) continue;
      if (!_isWorkerInTeam(data, uid)) continue;
      teams.add(await _hydrateTeam(doc.id, data));
    }
    teams.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return teams;
  }

  Future<WebTeamData?> loadTeam(String teamId) async {
    if (teamId.trim().isEmpty) return null;
    final doc = await _firestore.collection('teams').doc(teamId).get();
    final data = doc.data();
    if (data == null) return null;
    return _hydrateTeam(doc.id, data);
  }

  Future<List<Job>> loadCompanyJobs({
    required String ownerId,
    required bool ownProfile,
  }) {
    return WebJobsDataService(firestore: _firestore).loadCompanyJobs(
      ownerId: ownerId,
      ownProfile: ownProfile,
    );
  }

  Future<WebTeamData> _hydrateTeam(String id, Map<String, dynamic> data) async {
    final memberProfiles = <WebProfileData>[];
    for (final memberId in _teamMemberIds(data)) {
      final profile = _profileCache[memberId] ?? await loadProfile(memberId);
      if (profile == null || _isInactive(profile.data)) continue;
      memberProfiles.add(profile);
    }
    final portfolio = <String>[];
    try {
      final snapshot = await _firestore
          .collection('teams')
          .doc(id)
          .collection('portfolio')
          .get();
      for (final doc in snapshot.docs) {
        final url = _firstText(
          doc.data(),
          const ['url', 'imageUrl', 'image', 'photoUrl'],
          '',
        );
        if (url.isNotEmpty) portfolio.add(url);
      }
    } catch (error) {
      debugPrint('WEB TEAM PORTFOLIO LOAD ERROR $id $error');
    }
    return WebTeamData(
      id: id,
      data: data,
      members: memberProfiles,
      portfolio: portfolio.toSet().toList(),
    );
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

bool _isInactive(Map<String, dynamic> data) {
  final status = data['status']?.toString().toLowerCase().trim();
  return data['deleted'] == true ||
      data['accountDeleted'] == true ||
      data['active'] == false ||
      status == 'deleted' ||
      status == 'suspended' ||
      status == 'on_hold';
}

bool _isWorkerInTeam(Map<String, dynamic> data, String uid) {
  for (final key in const ['ownerId', 'createdBy', 'leaderId']) {
    if (data[key]?.toString() == uid) return true;
  }
  return _teamMemberIds(data).contains(uid);
}

List<String> _teamMemberIds(Map<String, dynamic> data) {
  final ids = <String>{};
  ids.addAll(_idsFromList(data['members']));
  ids.addAll(_idsFromList(data['memberIds']));
  _addStatusMemberIds(ids, data['membersStatus']);
  _addStatusMemberIds(ids, data['memberStatuses']);
  return ids.toList();
}

List<String> _idsFromList(dynamic value) {
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
