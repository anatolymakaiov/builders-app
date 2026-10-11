import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/ask_stroyka_service.dart';
import 'package:test_app/services/ask_stroyka_voice.dart';
import 'package:test_app/widgets/ask_stroyka_voice_sheet.dart';

class FakeCapture implements VoiceCaptureService {
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  bool disposed = false;
  VoicePermission currentPermission = VoicePermission.granted;
  VoiceClip? clip = VoiceClip(
      Uint8List.fromList(List.filled(512, 1)), const Duration(seconds: 2));

  @override
  Future<VoicePermission> permission({bool request = false}) async =>
      currentPermission;
  @override
  Future<void> start() async => starts++;
  @override
  Future<VoiceClip?> stop() async {
    stops++;
    return clip;
  }

  @override
  Future<void> cancel() async => cancels++;
  @override
  Future<void> dispose() async => disposed = true;
}

class FakeSpeech implements SpeechTranscriptionService {
  String text = 'Dryliner in Manchester from 14 October';
  int calls = 0;
  @override
  Future<String> transcribe(VoiceClip clip) async {
    calls++;
    return text;
  }
}

class FakeInterpreter implements AiIntentInterpreter {
  int calls = 0;
  Map<String, dynamic>? lastState;
  @override
  Future<Map<String, dynamic>> interpret(
      String text, Map<String, dynamic> state) async {
    calls++;
    lastState = state;
    return {
      'intent': 'find_job',
      'tradePhrase': 'dryliner',
      'location': text == 'Dryliner' ? null : 'Manchester',
      'availableFrom': text.contains('14 October') ? '2026-10-14' : null,
    };
  }
}

AskStroykaVoiceController controller(
        FakeCapture capture, FakeSpeech speech, FakeInterpreter interpreter,
        {Duration? maxDuration}) =>
    AskStroykaVoiceController(
      capture: capture,
      transcription: speech,
      session: AiAssistantSession(
          interpreter: interpreter, clock: () => DateTime(2026, 10, 10)),
      maxDuration: maxDuration ?? const Duration(seconds: 30),
    );

void main() {
  test('hold starts once, release transcribes once, confirmation gates search',
      () async {
    final capture = FakeCapture();
    final speech = FakeSpeech();
    final interpreter = FakeInterpreter();
    final voice = controller(capture, speech, interpreter);
    await voice.press();
    await voice.press();
    expect(capture.starts, 1);
    expect(voice.phase, VoicePhase.recording);
    expect(voice.confirm(), isNull);
    await voice.release();
    expect(capture.stops, 1);
    expect(speech.calls, 1);
    expect(interpreter.calls, 1);
    expect(voice.phase, VoicePhase.confirming);
    expect(voice.turn!.intent!.tradeId, 'dryliner');
    expect(voice.turn!.intent!.location, 'Manchester');
    expect(voice.turn!.intent!.availableFrom, DateTime(2026, 10, 14));
    expect(voice.confirm()!.tradeId, 'dryliner');
    await voice.close();
    expect(capture.disposed, isTrue);
    voice.dispose();
  });

  test('missing location asks follow-up and preserves first trade', () async {
    final capture = FakeCapture();
    final speech = FakeSpeech()..text = 'Dryliner';
    final interpreter = FakeInterpreter();
    final voice = controller(capture, speech, interpreter);
    await voice.press();
    await voice.release();
    expect(voice.turn!.question, 'Where would you like to work?');
    voice.change();
    speech.text = 'Manchester';
    await voice.press();
    await voice.release();
    expect(interpreter.lastState?['tradePhrase'], 'dryliner');
    expect(voice.turn!.readyToSearch, isTrue);
    voice.dispose();
  });

  test('cancel drops recording; empty speech never calls interpreter',
      () async {
    final capture = FakeCapture();
    final speech = FakeSpeech()..text = '  ';
    final interpreter = FakeInterpreter();
    final voice = controller(capture, speech, interpreter);
    await voice.press();
    await voice.cancelTurn();
    expect(capture.cancels, 1);
    expect(speech.calls, 0);
    await voice.press();
    await voice.release();
    expect(interpreter.calls, 0);
    expect(voice.phase, VoicePhase.error);
    voice.dispose();
  });

  testWidgets('30-second cap auto-stops and permission denial keeps exit',
      (tester) async {
    final capture = FakeCapture();
    final speech = FakeSpeech();
    final voice = controller(capture, speech, FakeInterpreter(),
        maxDuration: const Duration(seconds: 30));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AskStroykaVoiceSheet(controller: voice))));
    await voice.press();
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(capture.stops, 1);
    expect(voice.phase, VoicePhase.confirming);
    expect(find.text('Yes, find jobs'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(capture.disposed, isTrue);

    final denied = FakeCapture()..currentPermission = VoicePermission.denied;
    final deniedVoice = controller(denied, FakeSpeech(), FakeInterpreter());
    await deniedVoice.press();
    expect(deniedVoice.phase, VoicePhase.error);
    expect(denied.starts, 0);
    deniedVoice.dispose();
  });

  testWidgets('holding the microphone records; release shows confirmation',
      (tester) async {
    final capture = FakeCapture();
    final voice = controller(capture, FakeSpeech(), FakeInterpreter());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AskStroykaVoiceSheet(controller: voice))));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byIcon(Icons.mic)));
    await tester.pump();
    expect(voice.phase, VoicePhase.recording);
    expect(find.text('Yes, find jobs'), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(capture.stops, 1);
    expect(find.text('Yes, find jobs'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('five turns per sheet, then recording is unavailable', () async {
    final capture = FakeCapture();
    final speech = FakeSpeech()..text = 'Dryliner';
    final voice = controller(capture, speech, FakeInterpreter());
    for (var turn = 0; turn < 5; turn++) {
      await voice.press();
      await voice.release();
      voice.change();
    }
    expect(voice.turnsRemaining, 0);
    await voice.press();
    expect(capture.starts, 5);
    voice.dispose();
  });
}
