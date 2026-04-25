import 'package:add_2_calendar/add_2_calendar.dart';

class CalendarService {
  static DateTime? parseOfferDate(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;

    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;

    final numeric = RegExp(
      r'(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?(?:\s+(\d{1,2}):(\d{2}))?',
    ).firstMatch(text);
    if (numeric != null) {
      final day = int.parse(numeric.group(1)!);
      final month = int.parse(numeric.group(2)!);
      final year = _normaliseYear(numeric.group(3));
      final hour = int.tryParse(numeric.group(4) ?? "") ?? 8;
      final minute = int.tryParse(numeric.group(5) ?? "") ?? 0;
      return DateTime(year, month, day, hour, minute);
    }

    final named = RegExp(
      r'(\d{1,2})\s+([A-Za-z]+)(?:\s+(\d{4}))?(?:,?\s+(\d{1,2}):(\d{2}))?',
      caseSensitive: false,
    ).firstMatch(text);
    if (named != null) {
      final month = _monthNumber(named.group(2)!);
      if (month == null) return null;

      final day = int.parse(named.group(1)!);
      final year = _normaliseYear(named.group(3));
      final hour = int.tryParse(named.group(4) ?? "") ?? 8;
      final minute = int.tryParse(named.group(5) ?? "") ?? 0;
      return DateTime(year, month, day, hour, minute);
    }

    return null;
  }

  static Future<bool> addOfferToCalendar({
    required String title,
    required Map<String, dynamic> offer,
    String? fallbackLocation,
  }) async {
    final start = parseOfferDate(offer["startDateTime"] ?? offer["startDate"]);
    if (start == null) return false;

    final hours = int.tryParse(offer["weeklyHours"]?.toString() ?? "");
    final end =
        start.add(Duration(hours: hours == null ? 8 : hours.clamp(1, 12)));
    final location = offer["siteAddress"]?.toString().trim();

    final event = Event(
      title: title,
      description: _description(offer),
      location:
          location == null || location.isEmpty ? fallbackLocation : location,
      startDate: start,
      endDate: end,
      iosParams: const IOSParams(reminder: Duration(hours: 1)),
    );

    return Add2Calendar.addEvent2Cal(event);
  }

  static String _description(Map<String, dynamic> offer) {
    final rows = <String>[];

    void add(String label, dynamic value) {
      final text = value?.toString().trim() ?? "";
      if (text.isNotEmpty) rows.add("$label: $text");
    }

    add("Work format", offer["workFormat"]);
    add("Rate / price", offer["rate"]);
    add("Work period", offer["workPeriod"]);
    add("Schedule", offer["schedule"]);
    add("Required on first day", offer["firstDayRequirements"]);
    add("Description", offer["description"] ?? offer["message"]);
    add("Valid until", offer["validUntil"]);

    return rows.join("\n");
  }

  static int _normaliseYear(String? year) {
    if (year == null || year.isEmpty) return DateTime.now().year;

    final parsed = int.parse(year);
    return parsed < 100 ? 2000 + parsed : parsed;
  }

  static int? _monthNumber(String month) {
    const months = {
      "jan": 1,
      "january": 1,
      "feb": 2,
      "february": 2,
      "mar": 3,
      "march": 3,
      "apr": 4,
      "april": 4,
      "may": 5,
      "jun": 6,
      "june": 6,
      "jul": 7,
      "july": 7,
      "aug": 8,
      "august": 8,
      "sep": 9,
      "sept": 9,
      "september": 9,
      "oct": 10,
      "october": 10,
      "nov": 11,
      "november": 11,
      "dec": 12,
      "december": 12,
    };

    return months[month.toLowerCase()];
  }
}
