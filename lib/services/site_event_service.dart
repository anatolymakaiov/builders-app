import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'operational_calendar.dart';

const siteEventTypes = <String, String>{
  'site_induction': 'Site induction',
  'inspection': 'Inspection',
  'material_delivery': 'Material delivery',
  'meeting': 'Meeting',
  'client_visit': 'Client visit',
  'safety_briefing': 'Safety briefing',
  'deadline': 'Deadline',
  'milestone': 'Milestone',
  'reminder': 'Reminder',
  'other': 'Other',
};

const siteReminderChoices = <int, String>{
  0: 'At event time',
  60: '1 hour before',
  1440: '1 day before',
  2880: '2 days before',
};

class SiteEvent {
  const SiteEvent(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  String get title => (data['title'] ?? '').toString();
  String get type => (data['eventType'] ?? 'other').toString();
  String get siteId => (data['siteId'] ?? '').toString();
  String get description => (data['description'] ?? '').toString();
  bool get allDay => data['allDay'] == true;
  DateTime? get start => calendarDate(data['startDateTime']);
  DateTime? get end => calendarDate(data['endDateTime']);
  List<int> get reminderOffsetsMinutes =>
      (data['reminderOffsetsMinutes'] as List<dynamic>? ?? const [])
          .whereType<int>()
          .toList();
}

class SiteEventService {
  SiteEventService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  void _assertOwner(String employerId) {
    if (FirebaseAuth.instance.currentUser?.uid != employerId) {
      throw StateError('Only the signed-in employer can manage site events.');
    }
  }

  Future<List<SiteEvent>> loadRange(
      String employerId, CalendarRange range) async {
    _assertOwner(employerId);
    final lower = Timestamp.fromDate(
        range.start.toUtc().subtract(const Duration(days: 1)));
    final upper =
        Timestamp.fromDate(range.end.toUtc().add(const Duration(days: 1)));
    final snapshot = await _db
        .collection('site_events')
        .where('employerContextId', isEqualTo: employerId)
        .where('startDateTime', isGreaterThanOrEqualTo: lower)
        .where('startDateTime', isLessThan: upper)
        .get();
    _assertOwner(employerId);
    return snapshot.docs
        .map((doc) => SiteEvent(doc.id, doc.data()))
        .where((event) => event.start != null && range.contains(event.start!))
        .toList();
  }

  Future<SiteEvent?> getOwn(String employerId, String eventId) async {
    _assertOwner(employerId);
    final doc = await _db.collection('site_events').doc(eventId).get();
    _assertOwner(employerId);
    if (!doc.exists || doc.data()?['employerContextId'] != employerId) {
      return null;
    }
    return SiteEvent(doc.id, doc.data()!);
  }

  Future<List<SiteEvent>> loadUpcomingForSite(
      String employerId, String siteId, DateTime from,
      {int limit = 8}) async {
    _assertOwner(employerId);
    final snapshot = await _db
        .collection('site_events')
        .where('employerContextId', isEqualTo: employerId)
        .where('siteId', isEqualTo: siteId)
        .where('startDateTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .orderBy('startDateTime')
        .limit(limit)
        .get();
    _assertOwner(employerId);
    return snapshot.docs.map((doc) => SiteEvent(doc.id, doc.data())).toList();
  }

  Future<String> create(
    String employerId, {
    required String title,
    required String type,
    required DateTime start,
    DateTime? end,
    required bool allDay,
    String siteId = '',
    String description = '',
    List<int> reminderOffsetsMinutes = const [],
  }) async {
    _assertOwner(employerId);
    _validate(title, type, start, end, description);
    _validateReminders(reminderOffsetsMinutes);
    final ref = _db.collection('site_events').doc();
    await ref.set({
      'eventId': ref.id,
      'employerContextId': employerId,
      'siteId': siteId,
      'title': title.trim(),
      'eventType': type,
      'startDateTime': Timestamp.fromDate(start),
      if (end != null) 'endDateTime': Timestamp.fromDate(end),
      'allDay': allDay,
      'description': description.trim(),
      'reminderOffsetsMinutes': reminderOffsetsMinutes,
      'createdBy': employerId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> update(
    String employerId,
    SiteEvent event, {
    required String title,
    required String type,
    required DateTime start,
    DateTime? end,
    required bool allDay,
    String siteId = '',
    String description = '',
    List<int> reminderOffsetsMinutes = const [],
  }) async {
    _assertOwner(employerId);
    if (event.data['employerContextId'] != employerId) {
      throw StateError('Cannot edit another employer event.');
    }
    _validate(title, type, start, end, description);
    _validateReminders(reminderOffsetsMinutes);
    await _db.collection('site_events').doc(event.id).update({
      'siteId': siteId,
      'title': title.trim(),
      'eventType': type,
      'startDateTime': Timestamp.fromDate(start),
      'endDateTime':
          end == null ? FieldValue.delete() : Timestamp.fromDate(end),
      'allDay': allDay,
      'description': description.trim(),
      'reminderOffsetsMinutes': reminderOffsetsMinutes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String employerId, SiteEvent event) async {
    _assertOwner(employerId);
    if (event.data['employerContextId'] != employerId) {
      throw StateError('Cannot delete another employer event.');
    }
    await _db.collection('site_events').doc(event.id).delete();
  }

  static void _validate(String title, String type, DateTime start,
      DateTime? end, String description) {
    if (title.trim().isEmpty ||
        title.trim().length > 120 ||
        !siteEventTypes.containsKey(type) ||
        description.trim().length > 1000 ||
        (end != null && end.isBefore(start))) {
      throw ArgumentError('Check the event title, type and dates.');
    }
  }

  static void _validateReminders(List<int> offsets) {
    if (offsets.length > 5 ||
        offsets.toSet().length != offsets.length ||
        offsets.any((minutes) => minutes < 0 || minutes > 43200)) {
      throw ArgumentError('Choose up to five reminders within 30 days.');
    }
  }
}
