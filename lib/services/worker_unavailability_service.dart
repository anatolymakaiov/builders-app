import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WorkerUnavailablePeriod {
  const WorkerUnavailablePeriod(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  DateTime get start => (data['startDate'] as Timestamp).toDate();
  DateTime get end => (data['endDate'] as Timestamp).toDate();
  String get type => (data['type'] ?? 'other').toString();
  String get note => (data['note'] ?? '').toString();
}

class WorkerUnavailabilityService {
  WorkerUnavailabilityService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  static bool validPeriod(
      DateTime start, DateTime end, String type, String note, DateTime now) {
    final from = DateTime.utc(start.year, start.month, start.day);
    final to = DateTime.utc(end.year, end.month, end.day);
    return !from.isAfter(to) &&
        !to.isBefore(now.toUtc().subtract(const Duration(days: 1))) &&
        to.difference(from).inDays <= 730 &&
        const ['holiday', 'personal', 'external_work', 'other']
            .contains(type) &&
        note.length <= 500;
  }

  Stream<List<WorkerUnavailablePeriod>> watchOwn(String workerId) => _db
      .collection('worker_unavailability')
      .where('workerId', isEqualTo: workerId)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => WorkerUnavailablePeriod(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start)));

  Future<void> save({
    required String workerId,
    String? id,
    required DateTime start,
    required DateTime end,
    required String type,
    String note = '',
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != workerId) {
      throw StateError('Only the worker can edit unavailable periods.');
    }
    final from = DateTime.utc(start.year, start.month, start.day);
    final to = DateTime.utc(end.year, end.month, end.day);
    if (!validPeriod(from, to, type, note, DateTime.now())) {
      throw ArgumentError('Check the dates, type and note.');
    }
    final ref = id == null
        ? _db.collection('worker_unavailability').doc()
        : _db.collection('worker_unavailability').doc(id);
    await ref.set({
      'workerId': workerId,
      'startDate': Timestamp.fromDate(from),
      'endDate': Timestamp.fromDate(to),
      'type': type,
      'note': note.trim(),
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: id != null));
  }

  Future<void> delete(String workerId, String id) async {
    if (FirebaseAuth.instance.currentUser?.uid != workerId) {
      throw StateError('Only the worker can delete unavailable periods.');
    }
    await _db.collection('worker_unavailability').doc(id).delete();
  }
}
