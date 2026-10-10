import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

class WebSite {
  const WebSite({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;

  String get name => (data['name'] ?? '').toString();
  String get status => (data['status'] ?? 'active').toString();
  String get city => (data['city'] ?? '').toString();
  String get postcode => (data['postcode'] ?? '').toString();
}

class WebSitesService {
  WebSitesService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static String _normal(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String? exactVacancySiteMatch(
    Iterable<WebSite> sites, {
    required String employerId,
    required String name,
    required String addressLine1,
    required String postcode,
  }) {
    if (name.trim().isEmpty ||
        addressLine1.trim().isEmpty ||
        postcode.trim().isEmpty) {
      return null;
    }
    final matches = sites.where((site) =>
        site.data['employerContextId'] == employerId &&
        _normal(site.name) == _normal(name) &&
        _normal((site.data['addressLine1'] ?? '').toString()) ==
            _normal(addressLine1) &&
        _normal(site.postcode).replaceAll(' ', '') ==
            _normal(postcode).replaceAll(' ', ''));
    return matches.length == 1 ? matches.first.id : null;
  }

  static String vacancySiteId(
      String employerId, String name, String addressLine1, String postcode) {
    final identity =
        [employerId, name, addressLine1, postcode].map(_normal).join('|');
    return 'vacancy_${sha256.convert(utf8.encode(identity))}';
  }

  Future<({int linked, int created, int skipped})> linkLegacyVacancies(
      String employerId) async {
    final sites = await loadEmployerSites(employerId);
    final jobs = await _db
        .collection('jobs')
        .where('ownerId', isEqualTo: employerId)
        .get();
    final updates = <DocumentReference<Map<String, dynamic>>, String>{};
    final unresolved =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    final namePostcodeAddresses = <String, Set<String>>{};
    var skipped = 0;
    for (final job in jobs.docs) {
      final data = job.data();
      if ((data['siteId'] ?? '').toString().isNotEmpty) continue;
      final name = (data['site'] ?? '').toString();
      final address = (data['street'] ?? data['addressLine1'] ?? '').toString();
      final postcode = (data['postcode'] ?? '').toString();
      final city = (data['city'] ?? '').toString();
      if (name.trim().isEmpty ||
          address.trim().isEmpty ||
          postcode.trim().isEmpty ||
          city.trim().isEmpty) {
        skipped++;
        continue;
      }
      final match = exactVacancySiteMatch(sites,
          employerId: employerId,
          name: name,
          addressLine1: address,
          postcode: postcode);
      if (match == null) {
        final identity = vacancySiteId(employerId, name, address, postcode);
        unresolved.putIfAbsent(identity, () => []).add(job);
        final namePostcode =
            '${_normal(name)}|${_normal(postcode).replaceAll(' ', '')}';
        namePostcodeAddresses
            .putIfAbsent(namePostcode, () => {})
            .add(_normal(address));
        continue;
      }
      updates[job.reference] = match;
    }
    var created = 0;
    for (final group in unresolved.values) {
      final first = group.first.data();
      final name = (first['site'] ?? '').toString();
      final address =
          (first['street'] ?? first['addressLine1'] ?? '').toString();
      final postcode = (first['postcode'] ?? '').toString();
      final key = '${_normal(name)}|${_normal(postcode).replaceAll(' ', '')}';
      if ((namePostcodeAddresses[key]?.length ?? 0) != 1) {
        skipped += group.length;
        continue;
      }
      final id = await resolveOrCreateVacancySite(
        employerId,
        name: name,
        addressLine1: address,
        city: (first['city'] ?? '').toString(),
        postcode: postcode,
        region: (first['county'] ?? first['region'] ?? '').toString(),
        country: (first['country'] ?? 'United Kingdom').toString(),
        knownSites: sites,
      );
      if (id == null) {
        skipped += group.length;
        continue;
      }
      created++;
      sites.add(WebSite(id: id, data: {
        'employerContextId': employerId,
        'name': name,
        'addressLine1': address,
        'postcode': postcode,
      }));
      for (final job in group) {
        updates[job.reference] = id;
      }
    }
    for (var offset = 0; offset < updates.length; offset += 400) {
      final batch = _db.batch();
      for (final entry in updates.entries.skip(offset).take(400)) {
        batch.update(entry.key, {'siteId': entry.value});
      }
      await batch.commit();
    }
    return (linked: updates.length, created: created, skipped: skipped);
  }

  Future<String?> resolveOrCreateVacancySite(
    String employerId, {
    required String name,
    required String addressLine1,
    required String city,
    required String postcode,
    required String region,
    required String country,
    List<WebSite>? knownSites,
    Map<String, dynamic> additionalFields = const {},
  }) async {
    final existing = knownSites ?? await loadEmployerSites(employerId);
    final match = exactVacancySiteMatch(existing,
        employerId: employerId,
        name: name,
        addressLine1: addressLine1,
        postcode: postcode);
    if (match != null) return match;
    final possibleSameSite = existing.any((site) =>
        site.data['employerContextId'] == employerId &&
        _normal(site.postcode).replaceAll(' ', '') ==
            _normal(postcode).replaceAll(' ', '') &&
        (_normal(site.name) == _normal(name) ||
            _normal((site.data['addressLine1'] ?? '').toString()) ==
                _normal(addressLine1)));
    if (possibleSameSite ||
        _normal(name).length < 4 ||
        {'site', 'project', 'construction site', 'main site'}
            .contains(_normal(name)) ||
        addressLine1.trim().isEmpty ||
        city.trim().isEmpty ||
        postcode.trim().isEmpty) {
      return null;
    }
    final id = vacancySiteId(employerId, name, addressLine1, postcode);
    final ref = _db.collection('sites').doc(id);
    await _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      if (current.exists) {
        if (current.data()?['employerContextId'] != employerId) {
          throw StateError('Site identity belongs to another employer.');
        }
        return;
      }
      transaction.set(ref, {
        'siteId': id,
        'employerContextId': employerId,
        'ownerUid': employerId,
        'name': name.trim(),
        'status': 'active',
        'addressLine1': addressLine1.trim(),
        'addressLine2':
            (additionalFields['addressLine2'] ?? '').toString().trim(),
        'city': city.trim(),
        'region': region.trim(),
        'postcode': postcode.trim(),
        'country': country.trim().isEmpty ? 'United Kingdom' : country.trim(),
        'description':
            (additionalFields['description'] ?? '').toString().trim(),
        if (additionalFields['startDate'] is Timestamp)
          'startDate': additionalFields['startDate'],
        if (additionalFields['expectedEndDate'] is Timestamp)
          'expectedEndDate': additionalFields['expectedEndDate'],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return id;
  }

  Future<List<WebSite>> loadEmployerSites(String employerId) async {
    final snapshot = await _db
        .collection('sites')
        .where('employerContextId', isEqualTo: employerId)
        .get();
    return snapshot.docs
        .map((doc) => WebSite(id: doc.id, data: doc.data()))
        .toList();
  }

  Stream<List<WebSite>> watchEmployerSites(String employerId) => _db
          .collection('sites')
          .where('employerContextId', isEqualTo: employerId)
          .snapshots()
          .map((snapshot) {
        final sites = snapshot.docs
            .map((doc) => WebSite(id: doc.id, data: doc.data()))
            .toList();
        sites.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return sites;
      });

  Future<String> create(String employerId, Map<String, dynamic> fields) async {
    final doc = _db.collection('sites').doc();
    await doc.set({
      ...fields,
      'siteId': doc.id,
      'employerContextId': employerId,
      'ownerUid': employerId,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> update(WebSite site, Map<String, dynamic> fields) => _db
      .collection('sites')
      .doc(site.id)
      .update({...fields, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> setStatus(WebSite site, String status) =>
      _db.collection('sites').doc(site.id).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        if (status == 'archived') 'archivedAt': FieldValue.serverTimestamp(),
      });
}
