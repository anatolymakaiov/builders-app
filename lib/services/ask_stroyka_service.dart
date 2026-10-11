import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/job.dart';
import 'job_taxonomy_service.dart';

enum AiAssistantIntent {
  findJob,
  findWorkers,
  createVacancy,
  workforceQuery,
  siteQuery
}

class AskStroykaFeature {
  static const enabled = !kIsWeb &&
      bool.fromEnvironment('ASK_STROYKA_ENABLED', defaultValue: true);
}

class AiFindJobIntent {
  const AiFindJobIntent(
      {required this.tradeId,
      required this.location,
      this.availableFrom,
      this.rateMin,
      this.paymentType,
      this.radiusMiles,
      this.keywords = ''});

  final String tradeId;
  final String location;
  final DateTime? availableFrom;
  final double? rateMin;
  final String? paymentType;
  final double? radiusMiles;
  final String keywords;

  ConstructionRole get trade => JobTaxonomyService.roleFor(tradeId)!;
}

class AiAssistantTurn {
  const AiAssistantTurn(
      {this.intent,
      this.question,
      this.offTopic = false,
      this.tradeChoices = const []});

  final AiFindJobIntent? intent;
  final String? question;
  final bool offTopic;
  final List<ConstructionRole> tradeChoices;
  bool get readyToSearch => intent != null;
}

abstract class AiIntentInterpreter {
  Future<Map<String, dynamic>> interpret(
      String text, Map<String, dynamic> state);
}

class FirebaseAiIntentInterpreter implements AiIntentInterpreter {
  FirebaseAiIntentInterpreter({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, dynamic>> interpret(
      String text, Map<String, dynamic> state) async {
    final localNow = DateTime.now();
    final response = await _functions.httpsCallable('interpretAskStroyka').call(
      {
        'intent': 'find_job',
        'text': text,
        'state': state,
        'clientLocalDate': '${localNow.year.toString().padLeft(4, '0')}-'
            '${localNow.month.toString().padLeft(2, '0')}-'
            '${localNow.day.toString().padLeft(2, '0')}',
        'utcOffsetMinutes': localNow.timeZoneOffset.inMinutes,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}

class AiAssistantSession {
  AiAssistantSession({required this.interpreter, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AiIntentInterpreter interpreter;
  final DateTime Function() _clock;
  Map<String, dynamic> _state = {};

  void clear() => _state = {};

  Future<AiAssistantTurn> send(String message) async {
    final result = await interpreter.interpret(message, Map.of(_state));
    if (result['intent'] == 'out_of_scope') {
      return const AiAssistantTurn(
          offTopic: true,
          question:
              'I can help you find work on STROYKA. What trade or location?');
    }
    if (result['intent'] != 'find_job') {
      throw const FormatException('Unsupported assistant intent');
    }
    final next = <String, dynamic>{};
    for (final key in const [
      'tradePhrase',
      'location',
      'availableFrom',
      'rateMin',
      'paymentType',
      'radiusMiles',
      'keywords'
    ]) {
      final value = result[key];
      if (value != null) next[key] = value;
    }
    _state = next;
    final phrase = (next['tradePhrase'] ?? '').toString().trim();
    if (phrase.isEmpty) {
      return const AiAssistantTurn(question: 'What trade are you looking for?');
    }
    final normalized = JobTaxonomyService.normalise(phrase);
    final exact = JobTaxonomyService.roles
        .where((role) =>
            role.searchableTerms.any(
                (term) => JobTaxonomyService.normalise(term) == normalized) ||
            JobTaxonomyService.normalise(role.id) == normalized)
        .toList();
    if (exact.length > 1) {
      return AiAssistantTurn(
          question: 'Which trade do you mean?',
          tradeChoices: exact.take(3).toList());
    }
    final role = exact.singleOrNull;
    if (role == null) {
      final choices = JobTaxonomyService.suggestions(phrase, limit: 3);
      return AiAssistantTurn(
          question: choices.isEmpty
              ? 'What construction trade do you mean?'
              : 'Which trade do you mean?',
          tradeChoices: choices);
    }
    final location = (next['location'] ?? '').toString().trim();
    if (location.isEmpty) {
      return const AiAssistantTurn(question: 'Where would you like to work?');
    }
    if (RegExp(r'\s+or\s+', caseSensitive: false).hasMatch(location)) {
      return AiAssistantTurn(
          question:
              'Should I search around ${location.replaceFirst(RegExp(r'\s+or\s+', caseSensitive: false), ' or ')}?');
    }
    if (location.length > 80) throw const FormatException('Invalid location');
    final rawDate = next['availableFrom']?.toString();
    final parsedLocalDate = AiDateParser.parse(message, now: _clock());
    final serverDate = rawDate == null ? null : DateTime.tryParse(rawDate);
    final date = parsedLocalDate ?? serverDate;
    if (date != null &&
        date.isBefore(DateTime(_clock().year, _clock().month, _clock().day))) {
      _state.remove('availableFrom');
      return const AiAssistantTurn(
          question: 'Did you mean a future start date?');
    }
    if (AiDateParser.mentionsDate(message) && parsedLocalDate == null) {
      _state.remove('availableFrom');
      return const AiAssistantTurn(question: 'Which future date did you mean?');
    }
    if (rawDate != null && date == null) {
      _state.remove('availableFrom');
      return const AiAssistantTurn(question: 'When can you start?');
    }
    if (date != null) {
      _state['availableFrom'] = '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
    }
    final rate = next['rateMin'];
    final radius = next['radiusMiles'];
    if (rate != null && (rate is! num || rate < 0 || rate > 10000)) {
      throw const FormatException('Invalid rate');
    }
    if (radius != null && (radius is! num || radius < 1 || radius > 200)) {
      throw const FormatException('Invalid radius');
    }
    final payment = next['paymentType']?.toString();
    if (payment != null &&
        !{'hourly', 'price', 'negotiable'}.contains(payment)) {
      throw const FormatException('Invalid payment type');
    }
    return AiAssistantTurn(
        intent: AiFindJobIntent(
            tradeId: role.id,
            location: location,
            availableFrom: date,
            rateMin: (rate as num?)?.toDouble(),
            paymentType: payment,
            radiusMiles: (radius as num?)?.toDouble(),
            keywords: (next['keywords'] ?? '').toString()));
  }
}

class AiDateParser {
  static bool mentionsDate(String input) => RegExp(
        r'\b(?:today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next week|in (?:\d{1,2}|one|two|three|four) weeks?|january|february|march|april|may|june|july|august|september|october|november|december)\b|'
        r'сегодня|завтра|понедельник|понедельника|недел|тижн|понеділ|сьогодні|dziś|jutro|poniedział|tydzień|tygodn|październik|октябр|жовтн|\b\d{1,2}[./]\d{1,2}',
        caseSensitive: false,
      ).hasMatch(input);

  static DateTime? parse(String input, {required DateTime now}) {
    final text = input.toLowerCase();
    final today = DateTime(now.year, now.month, now.day);
    if (RegExp(r'\btoday\b|сегодня|сьогодні|\bdziś\b').hasMatch(text)) {
      return today;
    }
    if (RegExp(r'\btomorrow\b|завтра|\bjutro\b').hasMatch(text)) {
      return DateTime(today.year, today.month, today.day + 1);
    }
    if (RegExp(
            r'\bnext week\b|на следующей неделе|наступного тижня|w przyszłym tygodniu')
        .hasMatch(text)) {
      final delta = (DateTime.monday - today.weekday + 7) % 7;
      return DateTime(today.year, today.month,
          today.day + (delta == 0 ? 7 : delta));
    }
    final inWeeks = RegExp(
      r'\bin (\d{1,2}|one|two|three|four) weeks?\b',
    ).firstMatch(text);
    if (inWeeks != null) {
      const words = {'one': 1, 'two': 2, 'three': 3, 'four': 4};
      final count =
          int.tryParse(inWeeks.group(1)!) ?? words[inWeeks.group(1)!]!;
      return DateTime(today.year, today.month, today.day + 7 * count);
    }
    const weekdays = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday'
    ];
    for (var index = 0; index < weekdays.length; index++) {
      final day = weekdays[index];
      if (RegExp('\\b(?:(?:next|this) )?$day\\b').hasMatch(text) ||
          (day == 'monday' &&
              RegExp('понедельник|понедельника|понеділ|poniedział')
                  .hasMatch(text))) {
        var delta = (index + 1 - today.weekday + 7) % 7;
        if (delta == 0) delta = 7;
        return DateTime(today.year, today.month, today.day + delta);
      }
    }
    const months = [
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december'
    ];
    final dayMonth = RegExp(r'\b(?:from (?:the )?)?(\d{1,2})(?:st|nd|rd|th)?\s+'
            r'(january|february|march|april|may|june|july|august|september|october|november|december)\b')
        .firstMatch(text);
    if (dayMonth != null) {
      final day = int.parse(dayMonth.group(1)!);
      final month = months.indexOf(dayMonth.group(2)!) + 1;
      var date = DateTime(today.year, month, day);
      if (date.month != month || date.day != day) return null;
      if (date.isBefore(today)) date = DateTime(today.year + 1, month, day);
      return date;
    }
    final localizedOctober = RegExp(
      r'(\d{1,2})\s+(?:октября|жовтня|października)',
    ).firstMatch(text);
    if (localizedOctober != null) {
      final day = int.parse(localizedOctober.group(1)!);
      var date = DateTime(today.year, 10, day);
      if (date.month != 10 || date.day != day) return null;
      if (date.isBefore(today)) date = DateTime(today.year + 1, 10, day);
      return date;
    }
    final numeric =
        RegExp(r'\b(\d{1,2})[./](\d{1,2})(?:[./](\d{4}))?\b').firstMatch(text);
    if (numeric != null) {
      final day = int.parse(numeric.group(1)!);
      final month = int.parse(numeric.group(2)!);
      final year = int.tryParse(numeric.group(3) ?? '') ?? today.year;
      var date = DateTime(year, month, day);
      if (date.year != year || date.month != month || date.day != day) {
        return null;
      }
      if (numeric.group(3) == null && date.isBefore(today)) {
        date = DateTime(year + 1, month, day);
      }
      return date;
    }
    return null;
  }
}

enum AiJobDateMatch { bestMatch, mayStillSuit, unknownDate, filled }

class AiJobCompatibility {
  static AiJobDateMatch dateMatch(Job job, DateTime? availableFrom) {
    if (job.remainingPositions <= 0) return AiJobDateMatch.filled;
    if (job.startDate == null || availableFrom == null) {
      return AiJobDateMatch.unknownDate;
    }
    final start =
        DateTime(job.startDate!.year, job.startDate!.month, job.startDate!.day);
    final available =
        DateTime(availableFrom.year, availableFrom.month, availableFrom.day);
    return start.isBefore(available)
        ? AiJobDateMatch.mayStillSuit
        : AiJobDateMatch.bestMatch;
  }

  static int compare(Job a, Job b, DateTime? availableFrom) =>
      dateMatch(a, availableFrom)
          .index
          .compareTo(dateMatch(b, availableFrom).index);
}
