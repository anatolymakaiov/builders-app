import 'package:cloud_firestore/cloud_firestore.dart';
import 'worker_assignment_service.dart';

enum CalendarEventType {
  vacancyStart,
  assignmentStart,
  assignmentOngoing,
  assignmentFinish
}

class CalendarRange {
  const CalendarRange(this.start, this.end);

  final DateTime start;
  final DateTime end; // Exclusive.

  static CalendarRange month(DateTime date) {
    final first = DateTime(date.year, date.month);
    final monday = first.subtract(Duration(days: first.weekday - 1));
    final next = DateTime(date.year, date.month + 1);
    final last = next.subtract(const Duration(days: 1));
    return CalendarRange(monday, last.add(Duration(days: 8 - last.weekday)));
  }

  static CalendarRange week(DateTime date) {
    final monday = DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - 1));
    return CalendarRange(monday, monday.add(const Duration(days: 7)));
  }

  static CalendarRange day(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    return CalendarRange(start, start.add(const Duration(days: 1)));
  }

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(start) && day.isBefore(end);
  }
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.type,
    required this.date,
    required this.title,
    required this.sourceId,
    required this.vacancyId,
    required this.siteId,
    required this.siteName,
    required this.trade,
    required this.status,
  });

  final String id;
  final CalendarEventType type;
  final DateTime date;
  final String title;
  final String sourceId;
  final String vacancyId;
  final String siteId;
  final String siteName;
  final String trade;
  final String status;

  String get typeLabel => switch (type) {
        CalendarEventType.vacancyStart => 'Vacancy',
        CalendarEventType.assignmentStart => 'Start',
        CalendarEventType.assignmentOngoing => 'Ongoing',
        CalendarEventType.assignmentFinish => 'Finish',
      };
}

DateTime? calendarDate(dynamic value) {
  if (value is Timestamp) return value.toDate().toLocal();
  if (value is DateTime) return value.toLocal();
  return null;
}

List<CalendarEvent> vacancyCalendarEvents(
    String id, Map<String, dynamic> data, CalendarRange range) {
  final date = calendarDate(data['startDate']);
  final status = (data['status'] ?? '').toString().toLowerCase();
  final moderation = (data['moderationStatus'] ?? '').toString().toLowerCase();
  if (date == null ||
      !range.contains(date) ||
      data['deleted'] == true ||
      data['isDeleted'] == true ||
      data['active'] == false ||
      data['isActive'] == false ||
      (moderation.isNotEmpty && moderation != 'approved') ||
      !{'active', 'published', 'open', 'closed', 'filled'}.contains(status)) {
    return const [];
  }
  if ({'closed', 'filled'}.contains(status) && !date.isBefore(DateTime.now())) {
    return const [];
  }
  final trade =
      (data['canonicalRoleName'] ?? data['trade'] ?? data['title'] ?? 'Vacancy')
          .toString();
  return [
    CalendarEvent(
      id: 'vacancy:$id:start',
      type: CalendarEventType.vacancyStart,
      date: date,
      title: 'Vacancy starts — $trade',
      sourceId: id,
      vacancyId: id,
      siteId: (data['siteId'] ?? '').toString(),
      siteName: (data['site'] ?? '').toString(),
      trade: trade,
      status: status,
    )
  ];
}

List<CalendarEvent> assignmentCalendarEvents(
    String id, Map<String, dynamic> data, CalendarRange range) {
  final status = (data['status'] ?? 'scheduled').toString().toLowerCase();
  if (status == 'cancelled') return const [];
  final start = calendarDate(data['startDate']);
  final end = calendarDate(data['actualEndDate']) ??
      calendarDate(data['expectedEndDate']);
  final name = (data['workerDisplayName'] ?? 'Worker').toString();
  final trade = (data['tradeName'] ?? data['tradeId'] ?? '').toString();
  final siteId = (data['siteId'] ?? '').toString();
  final siteName = (data['siteName'] ?? '').toString();
  final events = <CalendarEvent>[];
  if (start != null && range.contains(start)) {
    events.add(CalendarEvent(
      id: 'assignment:$id:start',
      type: CalendarEventType.assignmentStart,
      date: start,
      title: '$name starts — $trade',
      sourceId: id,
      vacancyId: (data['vacancyId'] ?? '').toString(),
      siteId: siteId,
      siteName: siteName,
      trade: trade,
      status: status,
    ));
  }
  if (end != null &&
      range.contains(end) &&
      (start == null || !CalendarRange.day(start).contains(end))) {
    events.add(CalendarEvent(
      id: 'assignment:$id:finish',
      type: CalendarEventType.assignmentFinish,
      date: end,
      title: '$name finishes — $trade',
      sourceId: id,
      vacancyId: (data['vacancyId'] ?? '').toString(),
      siteId: siteId,
      siteName: siteName,
      trade: trade,
      status: status,
    ));
  }
  return events;
}

bool assignmentSpansDate(Map<String, dynamic> data, DateTime date) {
  final status = (data['status'] ?? '').toString().toLowerCase();
  if (status != 'active' && status != 'completed') return false;
  final start = calendarDate(data['startDate']);
  if (start == null) return false;
  final end = calendarDate(data['actualEndDate']) ??
      calendarDate(data['expectedEndDate']);
  final day = CalendarRange.day(date);
  return !CalendarRange.day(start).start.isAfter(day.start) &&
      (end == null
          ? status == 'active'
          : !CalendarRange.day(end).start.isBefore(day.start));
}

List<CalendarEvent> assignmentPeriodEvents(
    String id, Map<String, dynamic> data, CalendarRange range) {
  final start = calendarDate(data['startDate']);
  if (start == null) return const [];
  final end = calendarDate(data['actualEndDate']) ??
      calendarDate(data['expectedEndDate']);
  final name = (data['workerDisplayName'] ?? 'Worker').toString();
  final trade = (data['tradeName'] ?? data['tradeId'] ?? '').toString();
  final events = <CalendarEvent>[];
  for (var day = range.start;
      day.isBefore(range.end);
      day = day.add(const Duration(days: 1))) {
    if (CalendarRange.day(start).contains(day) ||
        (end != null && CalendarRange.day(end).contains(day)) ||
        !assignmentSpansDate(data, day)) {
      continue;
    }
    events.add(CalendarEvent(
      id: 'assignment:$id:ongoing:${day.year}-${day.month}-${day.day}',
      type: CalendarEventType.assignmentOngoing,
      date: day,
      title: '$name — $trade',
      sourceId: id,
      vacancyId: (data['vacancyId'] ?? '').toString(),
      siteId: (data['siteId'] ?? '').toString(),
      siteName: (data['siteName'] ?? '').toString(),
      trade: trade,
      status: (data['status'] ?? '').toString(),
    ));
  }
  return events;
}

List<CalendarEvent> filterCalendarEventsBySite(
    List<CalendarEvent> events, String? siteId) {
  if (siteId == null) return events;
  return events.where((event) => event.siteId == siteId).toList();
}

({WorkerAssignment assignment, bool current})? currentOrNextAssignment(
    List<WorkerAssignment> assignments,
    {DateTime? now}) {
  final today = now ?? DateTime.now();
  final todayStart = CalendarRange.day(today).start;
  final dated = assignments.where((item) => item.startDate != null).toList()
    ..sort((a, b) => a.startDate!.compareTo(b.startDate!));
  for (final item in dated) {
    final end = item.actualEndDate ?? item.expectedEndDate;
    if (item.status == 'active' &&
        !CalendarRange.day(item.startDate!).start.isAfter(todayStart) &&
        (end == null || !CalendarRange.day(end).start.isBefore(todayStart))) {
      return (assignment: item, current: true);
    }
  }
  for (final item in dated) {
    if (CalendarRange.day(item.startDate!).start.isAfter(todayStart)) {
      return (assignment: item, current: false);
    }
  }
  return null;
}

class OperationalCalendarService {
  OperationalCalendarService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<List<WorkerAssignment>> loadCurrentNext(String workerId) async {
    final snapshot = await _db
        .collection('assignments')
        .where('workerId', isEqualTo: workerId)
        .where('status', whereIn: ['active', 'scheduled']).get();
    final assignments = snapshot.docs
        .map((doc) => WorkerAssignment(doc.id, doc.data()))
        .where((item) => item.startDate != null)
        .toList();
    assignments.sort((a, b) => a.startDate!.compareTo(b.startDate!));
    return assignments;
  }

  Future<List<CalendarEvent>> load({
    required String uid,
    required bool employer,
    required CalendarRange range,
  }) async {
    // One day of query padding accommodates date-only timestamps written at
    // local midnight without shifting their displayed UK calendar date.
    final lower = Timestamp.fromDate(
        range.start.toUtc().subtract(const Duration(days: 1)));
    final upper =
        Timestamp.fromDate(range.end.toUtc().add(const Duration(days: 1)));
    final field = employer ? 'employerContextId' : 'workerId';
    final assignments = _db.collection('assignments');
    final reads = await Future.wait([
      assignments
          .where(field, isEqualTo: uid)
          .where('startDate', isGreaterThanOrEqualTo: lower)
          .where('startDate', isLessThan: upper)
          .get(),
      assignments
          .where(field, isEqualTo: uid)
          .where('expectedEndDate', isGreaterThanOrEqualTo: lower)
          .where('expectedEndDate', isLessThan: upper)
          .get(),
      assignments
          .where(field, isEqualTo: uid)
          .where('actualEndDate', isGreaterThanOrEqualTo: lower)
          .where('actualEndDate', isLessThan: upper)
          .get(),
      assignments
          .where(field, isEqualTo: uid)
          .where('expectedEndDate', isGreaterThanOrEqualTo: lower)
          .where('startDate', isLessThan: upper)
          .orderBy('expectedEndDate')
          .orderBy('startDate')
          .get(),
      assignments
          .where(field, isEqualTo: uid)
          .where('actualEndDate', isGreaterThanOrEqualTo: lower)
          .where('startDate', isLessThan: upper)
          .orderBy('actualEndDate')
          .orderBy('startDate')
          .get(),
      assignments
          .where(field, isEqualTo: uid)
          .where('status', isEqualTo: 'active')
          .where('startDate', isLessThan: upper)
          .get(),
    ]);
    final unique = <String, Map<String, dynamic>>{};
    for (final snapshot in reads) {
      for (final doc in snapshot.docs) {
        unique[doc.id] = doc.data();
      }
    }
    final events = <CalendarEvent>[
      for (final entry in unique.entries)
        ...assignmentCalendarEvents(entry.key, entry.value, range),
      for (final entry in unique.entries)
        ...assignmentPeriodEvents(entry.key, entry.value, range),
    ];
    if (employer) {
      final jobs = await _db
          .collection('jobs')
          .where('ownerId', isEqualTo: uid)
          .where('startDate', isGreaterThanOrEqualTo: lower)
          .where('startDate', isLessThan: upper)
          .get();
      for (final doc in jobs.docs) {
        events.addAll(vacancyCalendarEvents(doc.id, doc.data(), range));
      }
    }
    events.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.type.index.compareTo(b.type.index);
    });
    return events;
  }
}
