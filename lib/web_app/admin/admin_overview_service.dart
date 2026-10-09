import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/web_admin_profile_service.dart';

List<int> adminDailyBuckets(
    Iterable<DateTime> dates, DateTime start, int days) {
  final buckets = List<int>.filled(days, 0);
  for (final date in dates) {
    final day = DateTime(date.year, date.month, date.day);
    final index = day.difference(start).inDays;
    if (index >= 0 && index < days) buckets[index]++;
  }
  return buckets;
}

class AdminOverviewService {
  AdminOverviewService(
      {FirebaseFirestore? firestore, WebAdminProfileService? admin})
      : _db = firestore ?? FirebaseFirestore.instance,
        _admin = admin ?? WebAdminProfileService();

  final FirebaseFirestore _db;
  final WebAdminProfileService _admin;

  Future<Map<String, int?>> loadCounts(String uid) async {
    if (!await _admin.isAuthorized(uid)) {
      throw StateError('Administrator access required.');
    }
    final weekStart = DateTime.now().subtract(const Duration(days: 7));
    final queries = <String, Query<Map<String, dynamic>>>{
      'Users': _db.collection('users'),
      'Workers': _db.collection('users').where('role', isEqualTo: 'worker'),
      'Employers': _db
          .collection('users')
          .where('role', whereIn: const ['employer', 'company']),
      'Open vacancies': _db
          .collection('jobs')
          .where('moderationStatus', isEqualTo: 'approved')
          .where('status', whereIn: const ['active', 'published', 'open']),
      'Active sites':
          _db.collection('sites').where('status', isEqualTo: 'active'),
      'Active assignments':
          _db.collection('assignments').where('status', isEqualTo: 'active'),
      'Scheduled starts':
          _db.collection('assignments').where('status', isEqualTo: 'scheduled'),
      'Open reports':
          _db.collection('reports').where('status', isEqualTo: 'open'),
      'Suspended profiles':
          _db.collection('users').where('moderationHold', isEqualTo: true),
      'New users (7d)': _db.collection('users').where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart)),
      'Incomplete registrations': _db.collection('pending_registrations'),
      'Explicitly inactive users':
          _db.collection('users').where('active', isEqualTo: false),
      'Vacancies': _db.collection('jobs'),
      'Approved vacancies': _db
          .collection('jobs')
          .where('moderationStatus', isEqualTo: 'approved'),
      'Closed vacancies':
          _db.collection('jobs').where('status', isEqualTo: 'closed'),
      'Pending approval': _db
          .collection('jobs')
          .where('moderationStatus', isEqualTo: 'pending_review'),
      'Applications': _db.collection('applications'),
      'Pending applications':
          _db.collection('applications').where('status', isEqualTo: 'pending'),
      'Accepted offers': _db
          .collection('applications')
          .where('status', isEqualTo: 'offer_accepted'),
      'Negotiating': _db
          .collection('applications')
          .where('status', isEqualTo: 'negotiation'),
      'Offers sent': _db
          .collection('applications')
          .where('status', isEqualTo: 'offer_sent'),
      'Rejected applications':
          _db.collection('applications').where('status', isEqualTo: 'rejected'),
      'Support requests': _db.collection('support_requests'),
      'Open support requests':
          _db.collection('support_requests').where('status', isEqualTo: 'open'),
      'Unread admin messages': _db
          .collection('admin_messages')
          .where('readByAdmin', isEqualTo: false),
      'Billing requests': _db.collection('payment_requests'),
      'Active subscriptions': _db
          .collection('users')
          .where('billing.subscriptionStatus', isEqualTo: 'active'),
      'Starter plans': _db
          .collection('users')
          .where('billing.activePlanId', isEqualTo: 'starter'),
      'Growth plans': _db
          .collection('users')
          .where('billing.activePlanId', isEqualTo: 'growth'),
      'Pro plans': _db
          .collection('users')
          .where('billing.activePlanId', isEqualTo: 'pro'),
      'Trials': _db
          .collection('users')
          .where('billing.subscriptionStatus', isEqualTo: 'trial'),
      'Direct Debits configured': _db
          .collection('users')
          .where('billing.directDebitConfigured', isEqualTo: true),
      'Pending payments': _db
          .collection('payment_requests')
          .where('status', isEqualTo: 'pending'),
      'Paid requests':
          _db.collection('payment_requests').where('status', isEqualTo: 'paid'),
      'Failed requests': _db
          .collection('payment_requests')
          .where('status', isEqualTo: 'failed'),
    };
    final counts = <String, int?>{};
    await Future.wait(queries.entries.map((entry) async {
      try {
        counts[entry.key] = (await entry.value.count().get()).count;
      } catch (_) {
        counts[entry.key] = null;
      }
    }));

    return counts;
  }

  Future<List<AdminActivity>> loadRecentActivity(String uid) async {
    if (!await _admin.isAuthorized(uid)) {
      throw StateError('Administrator access required.');
    }
    final results = await Future.wait([
      _db
          .collection('users')
          .orderBy('createdAt', descending: true)
          .limit(6)
          .get(),
      _db
          .collection('jobs')
          .orderBy('createdAt', descending: true)
          .limit(6)
          .get(),
      _db
          .collection('assignments')
          .orderBy('createdAt', descending: true)
          .limit(6)
          .get(),
    ]);
    final activity = <AdminActivity>[
      for (final doc in results[0].docs)
        AdminActivity(
          type: doc.data()['role'] == 'worker'
              ? 'Worker joined'
              : const ['employer', 'company'].contains(doc.data()['role'])
                  ? 'Employer joined'
                  : 'Account created',
          title: (doc.data()['companyName'] ??
                  [doc.data()['firstName'], doc.data()['lastName']]
                      .whereType<String>()
                      .join(' '))
              .toString(),
          date: doc.data()['createdAt'] is Timestamp
              ? doc.data()['createdAt'] as Timestamp
              : null,
          userId: doc.id,
        ),
      for (final doc in results[1].docs)
        AdminActivity(
          type: 'Vacancy posted',
          title: (doc.data()['title'] ?? doc.data()['trade'] ?? 'Vacancy')
              .toString(),
          date: doc.data()['createdAt'] is Timestamp
              ? doc.data()['createdAt'] as Timestamp
              : null,
          jobId: doc.id,
        ),
      for (final doc in results[2].docs)
        AdminActivity(
          type: 'Assignment created',
          title: (doc.data()['workerDisplayName'] ?? 'Worker').toString(),
          date: doc.data()['createdAt'] is Timestamp
              ? doc.data()['createdAt'] as Timestamp
              : null,
          siteId: doc.data()['siteId']?.toString(),
        ),
    ];
    activity.sort((a, b) => (b.date?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.date?.millisecondsSinceEpoch ?? 0));
    return activity.take(12).toList(growable: false);
  }

  Future<Map<String, List<int>>> loadTrends(String uid, {int days = 30}) async {
    if (!await _admin.isAuthorized(uid)) {
      throw StateError('Administrator access required.');
    }
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: days - 1));
    final trends = <String, List<int>>{};
    await Future.wait(const <String, String>{
      'Registrations': 'users',
      'Vacancies': 'jobs',
      'Applications': 'applications',
      'Billing requests': 'payment_requests',
    }.entries.map((entry) async {
      try {
        final snapshot = await _db
            .collection(entry.value)
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .orderBy('createdAt', descending: true)
            .limit(250)
            .get();
        trends[entry.key] = adminDailyBuckets(
          snapshot.docs
              .map((doc) => doc.data()['createdAt'])
              .whereType<Timestamp>()
              .map((value) => value.toDate()),
          start,
          days,
        );
      } catch (_) {
        // Charts are secondary: a missing index must not hide the headline metrics.
      }
    }));
    return trends;
  }
}

class AdminActivity {
  const AdminActivity(
      {required this.type,
      required this.title,
      this.date,
      this.userId,
      this.jobId,
      this.siteId});

  final String type;
  final String title;
  final Timestamp? date;
  final String? userId;
  final String? jobId;
  final String? siteId;
}
