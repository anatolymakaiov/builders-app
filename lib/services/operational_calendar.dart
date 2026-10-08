import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'calendar_export.dart';
import 'worker_assignment_service.dart';

enum CalendarEventType {
  vacancyStart,
  assignmentStart,
  assignmentOngoing,
  assignmentFinish,
  unavailable,
  siteStart,
  siteFinish,
  manual,
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
    this.description = '',
    this.end,
    this.allDay = true,
    this.eventType = '',
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
  final String description;
  final DateTime? end;
  final bool allDay;
  final String eventType;

  String get typeLabel => switch (type) {
        CalendarEventType.vacancyStart => 'Vacancy',
        CalendarEventType.assignmentStart => 'Start',
        CalendarEventType.assignmentOngoing => 'Ongoing',
        CalendarEventType.assignmentFinish => 'Finish',
        CalendarEventType.unavailable => 'Unavailable',
        CalendarEventType.siteStart => 'Project starts',
        CalendarEventType.siteFinish => 'Expected completion',
        CalendarEventType.manual => 'Site event',
      };
}

List<CalendarEvent> siteMilestoneEvents(
    String id, Map<String, dynamic> data, CalendarRange range) {
  final name = (data['name'] ?? 'Site').toString();
  final events = <CalendarEvent>[];
  for (final (field, type, label) in [
    ('startDate', CalendarEventType.siteStart, 'Project starts'),
    ('expectedEndDate', CalendarEventType.siteFinish, 'Expected completion'),
  ]) {
    final date = calendarDate(data[field]);
    if (date == null || !range.contains(date)) continue;
    events.add(CalendarEvent(
      id: 'site:$id:$field',
      type: type,
      date: date,
      title: '$label — $name',
      sourceId: id,
      vacancyId: '',
      siteId: id,
      siteName: name,
      trade: '',
      status: (data['status'] ?? '').toString(),
    ));
  }
  return events;
}

List<CalendarEvent> manualSiteCalendarEvents(
    String id, Map<String, dynamic> data, CalendarRange range) {
  final start = calendarDate(data['startDateTime']);
  if (start == null || !range.contains(start)) return const [];
  return [
    CalendarEvent(
      id: 'manual:$id',
      type: CalendarEventType.manual,
      date: start,
      title: (data['title'] ?? 'Event').toString(),
      sourceId: id,
      vacancyId: '',
      siteId: (data['siteId'] ?? '').toString(),
      siteName: (data['siteName'] ?? '').toString(),
      trade: '',
      status: '',
      description: (data['description'] ?? '').toString(),
      end: calendarDate(data['endDateTime']),
      allDay: data['allDay'] == true,
      eventType: (data['eventType'] ?? 'other').toString(),
    )
  ];
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

List<CalendarEvent> unavailableCalendarEvents(
    String id, Map<String, dynamic> data, CalendarRange range) {
  final start = calendarDate(data['startDate']);
  final end = calendarDate(data['endDate']);
  if (start == null || end == null || end.isBefore(start)) return const [];
  final events = <CalendarEvent>[];
  for (var date = range.start;
      date.isBefore(range.end);
      date = date.add(const Duration(days: 1))) {
    if (CalendarRange.day(date)
            .start
            .isBefore(CalendarRange.day(start).start) ||
        CalendarRange.day(date).start.isAfter(CalendarRange.day(end).start)) {
      continue;
    }
    events.add(CalendarEvent(
      id: 'unavailable:$id:${date.year}-${date.month}-${date.day}',
      type: CalendarEventType.unavailable,
      date: date,
      title: 'Unavailable',
      sourceId: id,
      vacancyId: '',
      siteId: '',
      siteName: (data['note'] ?? '').toString(),
      trade: (data['type'] ?? '').toString().replaceAll('_', ' '),
      status: 'unavailable',
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

  Future<List<CalendarEvent>> loadSiteUpcoming({
    required String employerId,
    required String siteId,
    required Map<String, dynamic> siteData,
    DateTime? now,
  }) async {
    final today = now ?? DateTime.now();
    final start = CalendarRange.day(today).start;
    final range = CalendarRange(start, start.add(const Duration(days: 91)));
    final lower = Timestamp.fromDate(
        range.start.toUtc().subtract(const Duration(days: 1)));
    final upper =
        Timestamp.fromDate(range.end.toUtc().add(const Duration(days: 1)));
    final jobs = _db
        .collection('jobs')
        .where('ownerId', isEqualTo: employerId)
        .where('siteId', isEqualTo: siteId)
        .where('startDate', isGreaterThanOrEqualTo: lower)
        .where('startDate', isLessThan: upper)
        .get();
    final assignments = _db.collection('assignments');
    final assignmentReads = Future.wait([
      for (final field in ['startDate', 'expectedEndDate', 'actualEndDate'])
        assignments
            .where('employerContextId', isEqualTo: employerId)
            .where('siteId', isEqualTo: siteId)
            .where(field, isGreaterThanOrEqualTo: lower)
            .where(field, isLessThan: upper)
            .get(),
    ]);
    final manual = _db
        .collection('site_events')
        .where('employerContextId', isEqualTo: employerId)
        .where('siteId', isEqualTo: siteId)
        .where('startDateTime', isGreaterThanOrEqualTo: lower)
        .where('startDateTime', isLessThan: upper)
        .get();
    final events = siteMilestoneEvents(siteId, siteData, range);
    for (final doc in (await jobs).docs) {
      events.addAll(vacancyCalendarEvents(doc.id, doc.data(), range));
    }
    final unique = <String, Map<String, dynamic>>{};
    for (final snapshot in await assignmentReads) {
      for (final doc in snapshot.docs) {
        unique[doc.id] = doc.data();
      }
    }
    for (final entry in unique.entries) {
      events.addAll(assignmentCalendarEvents(entry.key, entry.value, range));
    }
    for (final doc in (await manual).docs) {
      events.addAll(manualSiteCalendarEvents(doc.id, doc.data(), range));
    }
    events.sort((a, b) => a.date.compareTo(b.date));
    return events.take(8).toList();
  }

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

  Future<List<WorkerAssignment>> loadEmployerPlanningAssignments(
      String employerId, CalendarRange range) async {
    final lower = Timestamp.fromDate(
        range.start.toUtc().subtract(const Duration(days: 1)));
    final upper =
        Timestamp.fromDate(range.end.toUtc().add(const Duration(days: 1)));
    final unique = await _assignmentData(employerId, true, lower, upper);
    return [
      for (final entry in unique.entries)
        if (entry.value['employerContextId'] == employerId &&
            {'active', 'scheduled'}.contains(entry.value['status']))
          WorkerAssignment(entry.key, entry.value),
    ];
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
    final unique = await _assignmentData(uid, employer, lower, upper);
    final events = <CalendarEvent>[
      for (final entry in unique.entries)
        ...assignmentCalendarEvents(entry.key, entry.value, range),
      for (final entry in unique.entries)
        ...assignmentPeriodEvents(entry.key, entry.value, range),
    ];
    if (employer) {
      final siteFuture = _siteData(uid, lower, upper);
      final manualFuture = _manualData(uid, lower, upper);
      final jobs = await _db
          .collection('jobs')
          .where('ownerId', isEqualTo: uid)
          .where('startDate', isGreaterThanOrEqualTo: lower)
          .where('startDate', isLessThan: upper)
          .get();
      for (final doc in jobs.docs) {
        events.addAll(vacancyCalendarEvents(doc.id, doc.data(), range));
      }
      for (final entry in (await siteFuture).entries) {
        events.addAll(siteMilestoneEvents(entry.key, entry.value, range));
      }
      for (final entry in (await manualFuture).entries) {
        events.addAll(manualSiteCalendarEvents(entry.key, entry.value, range));
      }
    } else {
      final periods = await _db
          .collection('worker_unavailability')
          .where('workerId', isEqualTo: uid)
          .where('endDate', isGreaterThanOrEqualTo: lower)
          .get();
      for (final doc in periods.docs) {
        events.addAll(unavailableCalendarEvents(doc.id, doc.data(), range));
      }
    }
    events.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.type.index.compareTo(b.type.index);
    });
    return events;
  }

  Future<Map<String, Map<String, dynamic>>> _assignmentData(
      String uid, bool employer, Timestamp lower, Timestamp upper) async {
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
    return unique;
  }

  Future<Map<String, Map<String, dynamic>>> _siteData(
      String uid, Timestamp lower, Timestamp upper) async {
    final sites = _db.collection('sites');
    final snapshots = await Future.wait([
      sites
          .where('employerContextId', isEqualTo: uid)
          .where('startDate', isGreaterThanOrEqualTo: lower)
          .where('startDate', isLessThan: upper)
          .get(),
      sites
          .where('employerContextId', isEqualTo: uid)
          .where('expectedEndDate', isGreaterThanOrEqualTo: lower)
          .where('expectedEndDate', isLessThan: upper)
          .get(),
    ]);
    return {
      for (final snapshot in snapshots)
        for (final doc in snapshot.docs) doc.id: doc.data()
    };
  }

  Future<Map<String, Map<String, dynamic>>> _manualData(
      String uid, Timestamp lower, Timestamp upper) async {
    final snapshot = await _db
        .collection('site_events')
        .where('employerContextId', isEqualTo: uid)
        .where('startDateTime', isGreaterThanOrEqualTo: lower)
        .where('startDateTime', isLessThan: upper)
        .get();
    return {for (final doc in snapshot.docs) doc.id: doc.data()};
  }

  Future<List<CalendarExportEvent>> loadExport({
    required String uid,
    required bool employer,
    required CalendarRange range,
    String? siteId,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Calendar export is limited to the signed-in account.');
    }
    if (!range.start.isBefore(range.end) ||
        range.end.difference(range.start).inDays > 370) {
      throw ArgumentError('Calendar export range must be at most 12 months.');
    }
    final lower = Timestamp.fromDate(
        range.start.toUtc().subtract(const Duration(days: 1)));
    final upper =
        Timestamp.fromDate(range.end.toUtc().add(const Duration(days: 1)));
    final assignments = await _assignmentData(uid, employer, lower, upper);
    final exported = <CalendarExportEvent>[
      for (final entry in assignments.entries)
        if (assignmentExportEvent(entry.key, entry.value,
                uid: uid, employer: employer, range: range)
            case final event?)
          event,
    ];
    if (employer) {
      final siteFuture = _siteData(uid, lower, upper);
      final manualFuture = _manualData(uid, lower, upper);
      final jobs = await _db
          .collection('jobs')
          .where('ownerId', isEqualTo: uid)
          .where('startDate', isGreaterThanOrEqualTo: lower)
          .where('startDate', isLessThan: upper)
          .get();
      for (final doc in jobs.docs) {
        final event = vacancyExportEvent(doc.id, doc.data(),
            employerId: uid, range: range);
        if (event != null) exported.add(event);
      }
      for (final entry in (await siteFuture).entries) {
        exported.addAll(siteMilestoneExportEvents(entry.key, entry.value,
            employerId: uid, range: range));
      }
      for (final entry in (await manualFuture).entries) {
        final event = manualSiteExportEvent(entry.key, entry.value,
            employerId: uid, range: range);
        if (event != null) exported.add(event);
      }
    } else {
      final periods = await _db
          .collection('worker_unavailability')
          .where('workerId', isEqualTo: uid)
          .where('endDate', isGreaterThanOrEqualTo: lower)
          .get();
      for (final doc in periods.docs) {
        final event = unavailabilityExportEvent(doc.id, doc.data(),
            workerId: uid, range: range);
        if (event != null) exported.add(event);
      }
    }
    final filtered = filterCalendarExportBySite(exported, siteId);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('The signed-in account changed during calendar export.');
    }
    filtered.sort((a, b) => a.start.compareTo(b.start));
    return filtered;
  }

  Future<CalendarExportEvent?> loadSingleAssignmentExport({
    required String workerId,
    required String assignmentId,
    required CalendarRange range,
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != workerId) {
      throw StateError('Calendar export is limited to the signed-in worker.');
    }
    final doc = await _db.collection('assignments').doc(assignmentId).get();
    if (FirebaseAuth.instance.currentUser?.uid != workerId || !doc.exists) {
      return null;
    }
    return assignmentExportEvent(doc.id, doc.data()!,
        uid: workerId, employer: false, range: range);
  }
}
