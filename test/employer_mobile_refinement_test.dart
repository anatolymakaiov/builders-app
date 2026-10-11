import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/screens/home_screen.dart';
import 'package:test_app/screens/employer_profile_screen.dart';
import 'package:test_app/screens/employer_calendar_screen.dart';
import 'package:test_app/screens/post_job_screen.dart';
import 'package:test_app/services/ask_stroyka_voice.dart';
import 'package:test_app/services/address_lookup_service.dart';
import 'package:test_app/services/operational_calendar.dart';
import 'package:test_app/theme/mobile_control_sizes.dart';
import 'package:test_app/widgets/employer_field_dictation_sheet.dart';

class _Capture implements VoiceCaptureService {
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  @override
  Future<VoicePermission> permission({bool request = false}) async =>
      VoicePermission.granted;
  @override
  Future<void> start() async => starts++;
  @override
  Future<VoiceClip?> stop() async {
    stops++;
    return VoiceClip(
        Uint8List.fromList(List.filled(512, 1)), const Duration(seconds: 60));
  }

  @override
  Future<void> cancel() async => cancels++;
  @override
  Future<void> dispose() async {}
}

class _Speech implements SpeechTranscriptionService {
  int calls = 0;
  bool fail = false;
  @override
  Future<String> transcribe(VoiceClip clip) async {
    calls++;
    if (fail) throw StateError('offline');
    return 'Install ceiling boards';
  }
}

class _Lookup extends AddressLookupService {
  @override
  String normalizePostcode(String value) => normalizeUkPostcode(value);
  @override
  bool isValidPostcode(String value) => isValidUkPostcode(value);
  @override
  Future<List<PostalAddress>> lookupAddresses(String postcode) async => [];
}

void main() {
  test('Post Job route is single-flight until popped', () async {
    final gate = SingleFlightNavigationGate();
    final route = Completer<void>();
    var opens = 0;
    Future<void> navigate() async {
      opens++;
      await route.future;
    }

    final first = gate.run(navigate);
    await gate.run(navigate);
    await gate.run(navigate);
    expect(opens, 1);
    expect(gate.active, true);
    route.complete();
    await first;
    expect(gate.active, false);
    await gate.run(() async => opens++);
    expect(opens, 2);
  });

  test('dictation appends and never silently replaces existing text', () {
    expect(appendDictation('Existing duties', 'New duties'),
        'Existing duties\nNew duties');
    expect(appendDictation('', ' New duties '), 'New duties');
    expect(appendDictation('Existing duties', '  '), 'Existing duties');
  });

  testWidgets('all four long fields dictate into their own controller',
      (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: PostJobScreen(
        onJobCreated: (_) {},
        postingAccessCheck: () async {},
        addressLookupService: _Lookup(),
        dictationLauncher: (_, name) async {
          calls.add(name);
          return 'Spoken $name';
        },
      ),
    ));
    await tester.pump();
    for (final name in [
      'Description',
      'Responsibilities',
      'Candidate requirements',
      'Additional information',
    ]) {
      final button = find.byTooltip('Dictate $name');
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      final field = tester.widget<TextField>(find.ancestor(
        of: button,
        matching: find.byType(TextField),
      ));
      expect(field.controller!.text, 'Spoken $name');
    }
    expect(calls.length, 4);
    expect(find.text('Post Job'), findsOneWidget);
  });

  testWidgets('Post Job renders before posting access finishes',
      (tester) async {
    final access = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: PostJobScreen(
      onJobCreated: (_) {},
      postingAccessCheck: () => access.future,
      addressLookupService: _Lookup(),
    )));
    await tester.pump();
    expect(find.text('Post Job'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    access.complete();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('60-second cap ends recording and inserts only transcript',
      (tester) async {
    final capture = _Capture();
    final speech = _Speech();
    String? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          result = await showModalBottomSheet<String>(
            context: context,
            builder: (_) => EmployerFieldDictationSheet(
              fieldName: 'Description',
              capture: capture,
              transcription: speech,
            ),
          );
        },
        child: const Text('Open'),
      ),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final gesture =
        await tester.startGesture(tester.getCenter(find.byIcon(Icons.mic)));
    await tester.pump();
    expect(capture.starts, 1);
    await tester.pump(employerDictationLimit);
    await tester.pumpAndSettle();
    expect(capture.stops, 1);
    expect(speech.calls, 1);
    expect(result, 'Install ceiling boards');
    await gesture.up();
  });

  testWidgets('transcription error keeps dictation form usable',
      (tester) async {
    final capture = _Capture();
    final speech = _Speech()..fail = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: EmployerFieldDictationSheet(
          fieldName: 'Description', capture: capture, transcription: speech),
    )));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byIcon(Icons.mic)));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.text('Could not transcribe. Try again or type it.'),
        findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('compact employer controls retain a 48px touch target', () {
    expect(mobileCompactControlHeight, 48);
  });

  test('employer profile reuses Calendar before Billing', () {
    expect(employerOwnProfileTabs.indexOf('Calendar') + 1,
        employerOwnProfileTabs.indexOf('Billing'));
  });

  testWidgets('employer calendar search uses compact control size',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: EmployerCalendarScreen(
        employerId: 'employer',
        embedded: true,
        loadEvents: (_) async => <CalendarEvent>[],
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search calendar'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(
        field.decoration!.constraints!.minHeight, mobileCompactControlHeight);
  });
}
