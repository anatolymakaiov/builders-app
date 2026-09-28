import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../services/moderation_hold_service.dart';
import '../../services/registration_lifecycle.dart';
import '../services/web_admin_profile_service.dart';

class AdminSearchService {
  AdminSearchService(
      {FirebaseFirestore? firestore, WebAdminProfileService? admin})
      : _db = firestore ?? FirebaseFirestore.instance,
        _admin = admin ?? WebAdminProfileService();

  final FirebaseFirestore _db;
  final WebAdminProfileService _admin;

  Future<List<WebAdminRecord>> search(String adminUid, String input) async {
    if (!await _admin.isAuthorized(adminUid)) {
      throw StateError('Administrator access required.');
    }
    final query = input.trim();
    if (query.length < 2) return const [];
    final variants = <String>{
      query.toLowerCase(),
      '${query[0].toUpperCase()}${query.substring(1)}',
    };
    final firstTerm = query.split(RegExp(r'\s+')).first;
    if (firstTerm != query) {
      variants.add(firstTerm.toLowerCase());
      variants.add('${firstTerm[0].toUpperCase()}${firstTerm.substring(1)}');
    }
    final isEmail = query.contains('@');
    final isPhone = RegExp(r'^[+\d\s()-]+$').hasMatch(query);
    if (isPhone) {
      final digits = query.replaceAll(RegExp(r'\D'), '');
      if (digits.isNotEmpty) {
        variants.add(digits);
        variants.add('+$digits');
      }
    }
    final userFields = isEmail
        ? const ['email', 'normalizedEmail']
        : isPhone
            ? const ['phone', 'normalizedPhone']
            : const [
                'name',
                'displayName',
                'firstName',
                'lastName',
                'companyName'
              ];
    final jobFields = isEmail || isPhone
        ? const <String>[]
        : const ['title', 'trade', 'companyName', 'site', 'postcode'];
    final results = <String, WebAdminRecord>{};
    Future<void> addId(String collection) async {
      try {
        final doc = await _db.collection(collection).doc(query).get();
        if (doc.exists && doc.data() != null) {
          results['$collection/${doc.id}'] =
              WebAdminRecord(collection, doc.id, doc.data()!);
        }
      } catch (error) {
        debugPrint('ADMIN SEARCH ID READ ERROR collection=$collection $error');
      }
    }

    Future<void> addPrefix(
        String collection, String field, String value) async {
      try {
        final snapshot = await _db
            .collection(collection)
            .orderBy(field)
            .startAt([value])
            .endAt(['$value\uf8ff'])
            .limit(12)
            .get();
        for (final doc in snapshot.docs) {
          results['$collection/${doc.id}'] =
              WebAdminRecord(collection, doc.id, doc.data());
        }
      } catch (error) {
        debugPrint(
            'ADMIN SEARCH FIELD ERROR collection=$collection field=$field $error');
      }
    }

    await Future.wait([
      addId('users'),
      addId('jobs'),
      for (final value in variants) ...[
        for (final field in userFields) addPrefix('users', field, value),
        for (final field in jobFields) addPrefix('jobs', field, value),
      ],
    ]);
    return results.values
        .where((record) => webAdminSearchMatches(record, query))
        .take(80)
        .toList();
  }

  Future<WebAdminRecord?> user(String adminUid, String userId) async {
    if (!await _admin.isAuthorized(adminUid)) {
      throw StateError('Administrator access required.');
    }
    final doc = await _db.collection('users').doc(userId).get();
    return doc.data() == null
        ? null
        : WebAdminRecord('users', doc.id, doc.data()!);
  }

  Future<List<WebAdminRecord>> employerJobs(
      String adminUid, String employerId) async {
    if (!await _admin.isAuthorized(adminUid)) {
      throw StateError('Administrator access required.');
    }
    final snapshot = await _db
        .collection('jobs')
        .where('ownerId', isEqualTo: employerId)
        .limit(30)
        .get();
    return snapshot.docs
        .map((doc) => WebAdminRecord('jobs', doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<List<WebAdminRecord>> publicPreviewJobs(String adminUid) async {
    if (!await _admin.isAuthorized(adminUid)) {
      throw StateError('Administrator access required.');
    }
    final snapshot = await _db
        .collection('jobs')
        .where('moderationStatus', isEqualTo: 'approved')
        .where('status', whereIn: const ['active', 'published', 'open'])
        .limit(60)
        .get();
    return snapshot.docs
        .where((doc) => const {'active', 'published', 'open'}
            .contains(doc.data()['status']))
        .map((doc) => WebAdminRecord('jobs', doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<List<WebAdminRecord>> previewProfiles(
      String adminUid, String role) async {
    if (!await _admin.isAuthorized(adminUid)) {
      throw StateError('Administrator access required.');
    }
    if (role != 'worker' && role != 'employer') return const [];
    final snapshot = await _db
        .collection('users')
        .where('role', isEqualTo: role)
        .limit(40)
        .get();
    return snapshot.docs
        .where((doc) =>
            doc.data()['active'] != false &&
            doc.data()['deleted'] != true &&
            doc.data()['accountDeleted'] != true &&
            !ModerationHoldService.isProfileHeld(doc.data()) &&
            RegistrationLifecycle.isComplete(doc.data()))
        .map((doc) => WebAdminRecord('users', doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<List<WebAdminRecord>> previewApplications(String adminUid) async {
    if (!await _admin.isAuthorized(adminUid)) {
      throw StateError('Administrator access required.');
    }
    final snapshot = await _db
        .collection('applications')
        .orderBy('createdAt', descending: true)
        .limit(40)
        .get();
    return snapshot.docs
        .map((doc) => WebAdminRecord('applications', doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<List<WebAdminRecord>> previewRecords(
      String adminUid, String targetUid, String role) async {
    if (!await _admin.isAuthorized(adminUid)) {
      throw StateError('Administrator access required.');
    }
    if (role != 'worker' && role != 'employer') return const [];
    final field = role == 'worker' ? 'workerId' : 'employerId';
    final reads = await Future.wait([
      _db
          .collection('applications')
          .where(field, isEqualTo: targetUid)
          .limit(30)
          .get(),
      _db
          .collection('chats')
          .where(field, isEqualTo: targetUid)
          .limit(20)
          .get(),
    ]);
    final records = <WebAdminRecord>[
      for (final doc in reads[0].docs)
        WebAdminRecord('applications', doc.id, doc.data()),
      for (final doc in reads[1].docs)
        WebAdminRecord('chats', doc.id, doc.data()),
    ];
    final jobs = role == 'employer'
        ? await _db
            .collection('jobs')
            .where('ownerId', isEqualTo: targetUid)
            .limit(30)
            .get()
        : await _db
            .collection('jobs')
            .where('moderationStatus', isEqualTo: 'approved')
            .limit(30)
            .get();
    records.addAll(jobs.docs
        .where((doc) =>
            role == 'employer' ||
            const ['active', 'published', 'open']
                .contains(doc.data()['status']))
        .map((doc) => WebAdminRecord('jobs', doc.id, doc.data())));
    return records;
  }
}
