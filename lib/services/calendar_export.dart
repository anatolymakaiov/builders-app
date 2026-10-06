import 'dart:convert';

import 'operational_calendar.dart';

enum ExternalCalendarProvider { native, ics, google, outlook }

class CalendarProviderCapability {
  const CalendarProviderCapability(this.provider, {required this.available});

  final ExternalCalendarProvider provider;
  final bool available;
}

abstract class ExternalCalendarService {
  List<CalendarProviderCapability> get providerCapabilities;
  String exportEvents(Iterable<CalendarExportEvent> events);
  String singleEvent(CalendarExportEvent event);
}

class CalendarExportEvent {
  const CalendarExportEvent({
    required this.sourceType,
    required this.sourceId,
    required this.title,
    required this.start,
    this.end,
    this.allDay = true,
    this.description = '',
    this.location = '',
    this.siteId = '',
    this.status,
  });

  final String sourceType;
  final String sourceId;
  final String title;
  final DateTime start;
  // Inclusive for all-day source records; the writer makes DTEND exclusive.
  final DateTime? end;
  final bool allDay;
  final String description;
  final String location;
  final String siteId;
  final String? status;

  String get uid => '$sourceType-$sourceId@stroyka.uk';
}

bool _overlaps(CalendarRange range, DateTime start, DateTime? end) {
  final first = DateTime(start.year, start.month, start.day);
  final last = end == null ? first : DateTime(end.year, end.month, end.day);
  return first.isBefore(range.end) && !last.isBefore(range.start);
}

CalendarExportEvent? assignmentExportEvent(
  String id,
  Map<String, dynamic> data, {
  required String uid,
  required bool employer,
  required CalendarRange range,
}) {
  if ((data[employer ? 'employerContextId' : 'workerId'] ?? '') != uid ||
      (data['status'] ?? '').toString().toLowerCase() == 'cancelled') {
    return null;
  }
  final start = calendarDate(data['startDate']);
  if (start == null) return null;
  final end = calendarDate(data['actualEndDate']) ??
      calendarDate(data['expectedEndDate']);
  final validEnd = end != null && !end.isBefore(start) ? end : null;
  if (!_overlaps(range, start, validEnd)) return null;
  final trade = (data['tradeName'] ?? data['tradeId'] ?? 'Work').toString();
  final site = (data['siteName'] ?? '').toString();
  final person =
      (data[employer ? 'workerDisplayName' : 'employerName'] ?? '').toString();
  final lines = <String>[
    'STROYKA Assignment',
    if (person.isNotEmpty) '${employer ? 'Worker' : 'Employer'}: $person',
    if (trade.isNotEmpty) 'Trade: $trade',
    if (site.isNotEmpty) 'Site: $site',
    'Assignment reference: $id',
  ];
  return CalendarExportEvent(
    sourceType: 'assignment',
    sourceId: id,
    title: site.isEmpty ? 'STROYKA — $trade' : 'STROYKA — $trade at $site',
    start: start,
    end: validEnd,
    description: lines.join('\n'),
    location: site,
    siteId: (data['siteId'] ?? '').toString(),
    status: 'CONFIRMED',
  );
}

CalendarExportEvent? vacancyExportEvent(String id, Map<String, dynamic> data,
    {required String employerId, required CalendarRange range}) {
  if (data['ownerId'] != employerId) return null;
  if (vacancyCalendarEvents(id, data, range).isEmpty) return null;
  final start = calendarDate(data['startDate'])!;
  final trade =
      (data['canonicalRoleName'] ?? data['trade'] ?? data['title'] ?? 'Vacancy')
          .toString();
  final site = (data['site'] ?? '').toString();
  return CalendarExportEvent(
    sourceType: 'vacancy',
    sourceId: id,
    title: 'STROYKA vacancy starts — $trade',
    start: start,
    description: [
      'STROYKA Vacancy',
      'Trade: $trade',
      if (site.isNotEmpty) 'Site: $site'
    ].join('\n'),
    location: site,
    siteId: (data['siteId'] ?? '').toString(),
    status: 'CONFIRMED',
  );
}

CalendarExportEvent? unavailabilityExportEvent(
    String id, Map<String, dynamic> data,
    {required String workerId, required CalendarRange range}) {
  if (data['workerId'] != workerId) return null;
  final start = calendarDate(data['startDate']);
  final end = calendarDate(data['endDate']);
  if (start == null ||
      end == null ||
      end.isBefore(start) ||
      !_overlaps(range, start, end)) {
    return null;
  }
  final type = (data['type'] ?? '').toString();
  final title = switch (type) {
    'holiday' => 'Holiday',
    'personal' => 'Personal',
    _ => 'Unavailable',
  };
  return CalendarExportEvent(
      sourceType: 'unavailability',
      sourceId: id,
      title: title,
      start: start,
      end: end);
}

List<CalendarExportEvent> siteMilestoneExportEvents(
    String id, Map<String, dynamic> data,
    {required String employerId, required CalendarRange range}) {
  if (data['employerContextId'] != employerId) return const [];
  return siteMilestoneEvents(id, data, range)
      .map((event) => CalendarExportEvent(
            sourceType: 'site',
            sourceId:
                '${event.sourceId}-${event.type == CalendarEventType.siteStart ? 'start' : 'finish'}',
            title: event.title,
            start: event.date,
            siteId: id,
            location: event.siteName,
            description: event.typeLabel,
            status: 'CONFIRMED',
          ))
      .toList();
}

CalendarExportEvent? manualSiteExportEvent(String id, Map<String, dynamic> data,
    {required String employerId, required CalendarRange range}) {
  if (data['employerContextId'] != employerId) return null;
  final events = manualSiteCalendarEvents(id, data, range);
  if (events.isEmpty) return null;
  final event = events.first;
  return CalendarExportEvent(
    sourceType: 'site-event',
    sourceId: id,
    title: event.title,
    start: event.date,
    end: event.end,
    allDay: event.allDay,
    siteId: event.siteId,
    location: event.siteName,
    description: [event.eventType.replaceAll('_', ' '), event.description]
        .where((text) => text.isNotEmpty)
        .join('\n'),
    status: 'CONFIRMED',
  );
}

List<CalendarExportEvent> filterCalendarExportBySite(
    Iterable<CalendarExportEvent> events, String? siteId) {
  if (siteId == null) return events.toList();
  return events.where((event) => event.siteId == siteId).toList();
}

class IcsCalendarProvider implements ExternalCalendarService {
  const IcsCalendarProvider();

  @override
  String singleEvent(CalendarExportEvent event) => exportEvents([event]);

  @override
  List<CalendarProviderCapability> get providerCapabilities => const [
        CalendarProviderCapability(ExternalCalendarProvider.ics,
            available: true),
        CalendarProviderCapability(ExternalCalendarProvider.google,
            available: false),
        CalendarProviderCapability(ExternalCalendarProvider.outlook,
            available: false),
      ];

  @override
  String exportEvents(Iterable<CalendarExportEvent> events, {DateTime? now}) {
    final stamp = _utc(now ?? DateTime.now());
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//STROYKA//Operational Calendar//EN',
      'CALSCALE:GREGORIAN',
    ];
    for (final event in events) {
      if (event.sourceId.isEmpty || event.sourceType.isEmpty) continue;
      lines.addAll(
          ['BEGIN:VEVENT', 'UID:${_escape(event.uid)}', 'DTSTAMP:$stamp']);
      if (event.allDay) {
        lines.add('DTSTART;VALUE=DATE:${_date(event.start)}');
        final last = event.end ?? event.start;
        final exclusive = DateTime(last.year, last.month, last.day + 1);
        lines.add('DTEND;VALUE=DATE:${_date(exclusive)}');
      } else {
        lines.add('DTSTART:${_utc(event.start)}');
        if (event.end != null) lines.add('DTEND:${_utc(event.end!)}');
      }
      lines.add('SUMMARY:${_escape(event.title)}');
      if (event.description.isNotEmpty) {
        lines.add('DESCRIPTION:${_escape(event.description)}');
      }
      if (event.location.isNotEmpty) {
        lines.add('LOCATION:${_escape(event.location)}');
      }
      if (const {'TENTATIVE', 'CONFIRMED', 'CANCELLED'}
          .contains(event.status)) {
        lines.add('STATUS:${event.status}');
      }
      lines.add('END:VEVENT');
    }
    lines.add('END:VCALENDAR');
    return '${lines.map(_fold).join('\r\n')}\r\n';
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';

  static String _utc(DateTime value) {
    final utc = value.toUtc();
    return '${_date(utc)}T${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }

  static String _escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', '\\n')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;');

  static String _fold(String line) {
    final result = StringBuffer();
    var length = 0;
    for (final scalar in line.runes) {
      final character = String.fromCharCode(scalar);
      final bytes = utf8.encode(character).length;
      if (length + bytes > 75) {
        result.write('\r\n ');
        length = 1;
      }
      result.write(character);
      length += bytes;
    }
    return result.toString();
  }
}
