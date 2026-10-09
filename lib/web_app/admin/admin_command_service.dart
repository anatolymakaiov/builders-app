import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../services/web_admin_profile_service.dart';

enum AdminOperationalView { jobs, sites, assignments, subscriptions }

class AdminCommandPage {
  const AdminCommandPage(this.records, this.nextCursor);

  final List<WebAdminRecord> records;
  final String? nextCursor;
}

class AdminCommandService {
  AdminCommandService(
      {FirebaseFirestore? firestore,
      FirebaseFunctions? functions,
      WebAdminProfileService? admin})
      : _providedDb = firestore,
        _providedFunctions = functions,
        _providedAdmin = admin;

  final FirebaseFirestore? _providedDb;
  final FirebaseFunctions? _providedFunctions;
  final WebAdminProfileService? _providedAdmin;
  FirebaseFirestore get _db => _providedDb ?? FirebaseFirestore.instance;
  FirebaseFunctions get _functions =>
      _providedFunctions ?? FirebaseFunctions.instance;
  WebAdminProfileService get _admin =>
      _providedAdmin ?? WebAdminProfileService();

  Future<AdminCommandPage> load(
    String adminUid,
    AdminOperationalView view, {
    String? cursor,
    int pageSize = 25,
  }) async {
    if (!await _admin.isAuthorized(adminUid)) {
      throw StateError('Administrator access required.');
    }
    if (pageSize < 1 || pageSize > 50) {
      throw ArgumentError.value(pageSize, 'pageSize');
    }
    if (view == AdminOperationalView.subscriptions) {
      final result = await _functions
          .httpsCallable('listAdminSubscriptions')
          .call(<String, dynamic>{
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final records = (data['records'] as List? ?? const []).map((raw) {
        final record = Map<String, dynamic>.from(raw as Map);
        return WebAdminRecord(
          'users',
          record['id'].toString(),
          Map<String, dynamic>.from(record['data'] as Map),
        );
      }).toList();
      return AdminCommandPage(records, data['nextCursor'] as String?);
    }
    final collection = switch (view) {
      AdminOperationalView.jobs => 'jobs',
      AdminOperationalView.sites => 'sites',
      AdminOperationalView.assignments => 'assignments',
      AdminOperationalView.subscriptions => 'users',
    };
    Query<Map<String, dynamic>> query = _db.collection(collection);
    query = query.orderBy(FieldPath.documentId).limit(pageSize);
    if (cursor != null && cursor.isNotEmpty) {
      query = query.startAfter([cursor]);
    }
    final snapshot = await query.get();
    final rows = snapshot.docs
        .map((doc) => WebAdminRecord(collection, doc.id, doc.data()))
        .toList();
    if (view == AdminOperationalView.jobs ||
        view == AdminOperationalView.sites ||
        view == AdminOperationalView.assignments) {
      await _enrich(rows, view);
    }
    return AdminCommandPage(
      rows,
      snapshot.docs.length == pageSize ? snapshot.docs.last.id : null,
    );
  }

  Future<void> _enrich(
      List<WebAdminRecord> rows, AdminOperationalView view) async {
    final employerIds = <String>{};
    for (final row in rows) {
      final id = (row.data[view == AdminOperationalView.sites
                  ? 'employerContextId'
                  : 'ownerId'] ??
              row.data['employerContextId'])
          ?.toString();
      if (id != null && id.isNotEmpty) employerIds.add(id);
    }
    final employers = <String, Map<String, dynamic>>{};
    final ids = employerIds.toList();
    for (var offset = 0; offset < ids.length; offset += 30) {
      final group = ids.skip(offset).take(30).toList();
      final snapshot = await _db
          .collection('users')
          .where(FieldPath.documentId, whereIn: group)
          .get();
      for (final doc in snapshot.docs) {
        employers[doc.id] = doc.data();
      }
    }
    Map<String, int> vacancyCounts = {};
    Map<String, int> workforceCounts = {};
    if (view == AdminOperationalView.sites && rows.isNotEmpty) {
      final siteIds = rows.map((row) => row.id).toList();
      for (var offset = 0; offset < siteIds.length; offset += 30) {
        final group = siteIds.skip(offset).take(30).toList();
        final results = await Future.wait([
          _db.collection('jobs').where('siteId', whereIn: group).get(),
          _db.collection('assignments').where('siteId', whereIn: group).get(),
        ]);
        for (final doc in results[0].docs) {
          if (const {'active', 'published', 'open'}
              .contains(doc.data()['status'])) {
            final id = doc.data()['siteId']?.toString() ?? '';
            vacancyCounts[id] = (vacancyCounts[id] ?? 0) + 1;
          }
        }
        for (final doc in results[1].docs) {
          if (const {'scheduled', 'active'}.contains(doc.data()['status'])) {
            final id = doc.data()['siteId']?.toString() ?? '';
            workforceCounts[id] = (workforceCounts[id] ?? 0) + 1;
          }
        }
      }
    }
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final ownerId = (row.data[view == AdminOperationalView.sites
                  ? 'employerContextId'
                  : 'ownerId'] ??
              row.data['employerContextId'])
          ?.toString();
      final owner = employers[ownerId];
      rows[index] = WebAdminRecord(row.collection, row.id, {
        ...row.data,
        'adminEmployerName': owner?['companyName'] ??
            owner?['businessName'] ??
            row.data['companyName'] ??
            '',
        if (view == AdminOperationalView.sites) ...{
          'adminVacancyCount': vacancyCounts[row.id] ?? 0,
          'adminWorkforceCount': workforceCounts[row.id] ?? 0,
        },
      });
    }
  }
}
