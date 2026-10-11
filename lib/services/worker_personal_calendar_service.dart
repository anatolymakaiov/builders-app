import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WorkerPersonalCalendarService {
  static const allowedAlertMinutes = {
    0,
    5,
    10,
    15,
    30,
    60,
    120,
    1440,
    2880,
    10080,
  };
  WorkerPersonalCalendarService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  void _assertOwner(String workerId) {
    if (FirebaseAuth.instance.currentUser?.uid != workerId) {
      throw StateError('Personal calendar is limited to its owner.');
    }
  }

  CollectionReference<Map<String, dynamic>> _events(String workerId) =>
      _db.collection('users').doc(workerId).collection('calendar_events');

  Future<void> create(
    String workerId, {
    required String title,
    required DateTime start,
    required DateTime end,
    required bool reminder,
    required List<int> reminderOffsetsMinutes,
    String description = '',
  }) async {
    _assertOwner(workerId);
    final name = title.trim();
    if (name.isEmpty ||
        name.length > 120 ||
        end.isBefore(start) ||
        description.length > 1000 ||
        reminderOffsetsMinutes.length > 1 ||
        reminderOffsetsMinutes
            .any((value) => !allowedAlertMinutes.contains(value))) {
      throw ArgumentError('Check the event title, dates and alert.');
    }
    final ref = _events(workerId).doc();
    await ref.set({
      'eventId': ref.id,
      'workerId': workerId,
      'title': name,
      'eventType': reminder ? 'reminder' : 'event',
      'startDateTime': Timestamp.fromDate(start),
      'endDateTime': Timestamp.fromDate(end),
      'description': description.trim(),
      'reminderOffsetsMinutes': reminderOffsetsMinutes,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> update(
    String workerId,
    String eventId, {
    required String title,
    required DateTime start,
    required DateTime end,
    required bool reminder,
    required List<int> reminderOffsetsMinutes,
    String description = '',
  }) async {
    _assertOwner(workerId);
    final ref = _events(workerId).doc(eventId);
    final before = await ref.get();
    _assertOwner(workerId);
    if (!before.exists || before.data()?['workerId'] != workerId) {
      throw StateError('Calendar entry is not owned by this worker.');
    }
    final name = title.trim();
    if (name.isEmpty ||
        name.length > 120 ||
        end.isBefore(start) ||
        description.length > 1000 ||
        reminderOffsetsMinutes.length > 1 ||
        reminderOffsetsMinutes
            .any((value) => !allowedAlertMinutes.contains(value))) {
      throw ArgumentError('Check the event title, dates and alert.');
    }
    await ref.update({
      'title': name,
      'eventType': reminder ? 'reminder' : 'event',
      'startDateTime': Timestamp.fromDate(start),
      'endDateTime': Timestamp.fromDate(end),
      'description': description.trim(),
      'reminderOffsetsMinutes': reminderOffsetsMinutes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
