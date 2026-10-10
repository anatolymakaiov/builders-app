import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/services/ask_stroyka_service.dart';
import 'package:test_app/web_app/services/web_job_filters.dart';
import 'package:test_app/widgets/ask_stroyka_sheet.dart';

class _FakeInterpreter implements AiIntentInterpreter {
  _FakeInterpreter(this.answer);
  final Map<String, dynamic> Function(String) answer;
  Map<String, dynamic>? lastState;
  @override
  Future<Map<String, dynamic>> interpret(
      String text, Map<String, dynamic> state) async {
    lastState = state;
    return answer(text);
  }
}

Map<String, dynamic> result(
        {String? trade = 'dry liner',
        String? city = 'Manchester',
        String? date = '2026-10-14'}) =>
    {
      'intent': 'find_job',
      'tradePhrase': trade,
      'location': city,
      'availableFrom': date,
      'rateMin': null,
      'paymentType': null,
      'radiusMiles': null,
      'keywords': null,
    };

Job job(String id, DateTime? start, {int positions = 2, int filled = 0}) => Job(
      id: id,
      title: 'Dryliner',
      trade: 'Dryliner',
      site: 'Tower',
      location: 'Manchester',
      street: '',
      city: 'Manchester',
      postcode: 'M1 1AE',
      rate: 25,
      lat: 0,
      lng: 0,
      description: '',
      companyName: 'Company',
      photos: const [],
      jobType: 'hourly',
      duration: '3 weeks',
      startDate: start,
      employmentType: '',
      ownerId: 'employer',
      positions: positions,
      filledPositions: filled,
      moderationStatus: 'approved',
    );

void main() {
  test('canonical role, location and natural date become search intent',
      () async {
    final fake = _FakeInterpreter((_) => result());
    final session = AiAssistantSession(
        interpreter: fake, clock: () => DateTime(2026, 10, 10));
    final turn = await session.send('Dryliner in Manchester from 14 October');
    expect(turn.readyToSearch, isTrue);
    expect(turn.intent!.tradeId, 'dryliner');
    expect(turn.intent!.availableFrom, DateTime(2026, 10, 14));
    expect(turn.intent!.location, 'Manchester');
    expect(fake.lastState, isEmpty);
  });

  test('profile-filled request needs no questionnaire', () async {
    final session = AiAssistantSession(
        interpreter: _FakeInterpreter((_) => result(trade: 'dryliner')));
    final turn = await session.send('Find me work');
    expect(turn.readyToSearch, isTrue);
    expect(turn.question, isNull);
  });

  test('missing location asks one question, then follows up', () async {
    final fake = _FakeInterpreter((text) => result(
        trade: 'electrician',
        city: text == 'Manchester' ? text : null,
        date: null));
    final session = AiAssistantSession(interpreter: fake);
    expect((await session.send('Electrician')).question,
        'Where would you like to work?');
    expect((await session.send('Manchester')).readyToSearch, isTrue);
    expect(fake.lastState?['tradePhrase'], 'electrician');
    session.clear();
    await session.send('Again');
    expect(fake.lastState, isEmpty);
  });

  test('off-topic refocuses; ambiguous alias asks for a trade', () async {
    final fake = _FakeInterpreter((text) => text == 'weather'
        ? {'intent': 'out_of_scope'}
        : result(trade: 'partition installer'));
    final session = AiAssistantSession(interpreter: fake);
    expect((await session.send('weather')).offTopic, isTrue);
    final ambiguous = await session.send('partition installer');
    expect(ambiguous.readyToSearch, isFalse);
    expect(ambiguous.tradeChoices.length, greaterThan(1));
  });

  test('casual multiple locations ask one clarifying question', () async {
    final session = AiAssistantSession(
        interpreter: _FakeInterpreter(
            (_) => result(city: 'Manchester or Liverpool', date: null)));
    final turn = await session.send(
        'My supervisor is doing my head in, maybe Liverpool or Manchester');
    expect(turn.readyToSearch, isFalse);
    expect(turn.question, contains('Manchester or Liverpool'));
  });

  test('fixer, dry liner and board fixer use existing taxonomy', () async {
    for (final alias in ['fixer', 'dry liner', 'board fixer']) {
      final session = AiAssistantSession(
          interpreter: _FakeInterpreter((_) => result(trade: alias)));
      expect((await session.send(alias)).intent!.tradeId, 'dryliner');
    }
  });

  test('natural dates and started-but-open ranking', () {
    final now = DateTime(2026, 10, 10);
    expect(AiDateParser.parse('tomorrow', now: now), DateTime(2026, 10, 11));
    expect(AiDateParser.parse('next Monday', now: now), DateTime(2026, 10, 19));
    expect(AiDateParser.parse('14 October', now: now), DateTime(2026, 10, 14));
    expect(
        AiDateParser.parse('in two weeks', now: now), DateTime(2026, 10, 24));
    final available = DateTime(2026, 10, 14);
    expect(
        AiJobCompatibility.dateMatch(
            job('late', DateTime(2026, 10, 14)), available),
        AiJobDateMatch.bestMatch);
    expect(
        AiJobCompatibility.dateMatch(
            job('early', DateTime(2026, 10, 10)), available),
        AiJobDateMatch.mayStillSuit);
    expect(AiJobCompatibility.dateMatch(job('unknown', null), available),
        AiJobDateMatch.unknownDate);
    expect(
        AiJobCompatibility.dateMatch(
            job('filled', DateTime(2026, 10, 14), positions: 1, filled: 1),
            available),
        AiJobDateMatch.filled);
  });

  test('existing Jobs filter determines real zero count', () {
    const filters = WebJobFilters(city: 'Liverpool');
    expect(filters.apply([job('one', DateTime(2026, 10, 14))], ''), isEmpty);
  });

  testWidgets('sheet hints, follow-up, summary, CTA and close', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () => showAskStroyka(context,
              interpreter: _FakeInterpreter((text) => text == 'Electrician'
                  ? result(trade: 'electrician', city: null, date: null)
                  : result(
                      trade: 'electrician', city: 'Manchester', date: null))),
          child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not saved'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Electrician');
    await tester.tap(find.byTooltip('Send request'));
    await tester.pumpAndSettle();
    expect(find.text('Where would you like to work?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Manchester');
    await tester.tap(find.byTooltip('Send request'));
    await tester.pumpAndSettle();
    expect(find.text('Find jobs'), findsOneWidget);
    await tester.tap(find.text('Find jobs'));
    await tester.pumpAndSettle();
    expect(find.text('Ask STROYKA'), findsNothing);
  });

  for (final width in [360.0, 390.0]) {
    testWidgets('assistant sheet fits a ${width.toInt()}px browser',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAskStroyka(context,
              interpreter: _FakeInterpreter((_) => result())),
          child: const Text('Open'),
        ),
      ))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
          find.byType(TextField).last, 'Dryliner in Manchester');
      await tester.tap(find.byTooltip('Send request'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Find jobs'), findsOneWidget);
    });
  }
}
