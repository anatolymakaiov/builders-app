import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:test_app/services/ask_stroyka_service.dart';
import 'package:test_app/services/ask_stroyka_voice.dart';
import 'package:test_app/services/native_voice_capture.dart';
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

class FileWritingRecorder implements AudioRecorder {
  FileWritingRecorder(this.audio);

  final List<int> audio;
  String? path;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    this.path = path;
    await File(path).writeAsBytes(audio);
  }

  @override
  Future<String?> stop() async => path;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DelayedPermissionCapture extends FakeCapture {
  final Completer<VoicePermission> permissionResult = Completer();

  @override
  Future<VoicePermission> permission({bool request = false}) =>
      permissionResult.future;
}

class FailingStopCapture extends FakeCapture {
  @override
  Future<VoiceClip?> stop() async => throw const FileSystemException();
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
      'tradePhrase': state['tradePhrase'] ?? 'dryliner',
      'location': text == 'Dryliner'
          ? null
          : text.contains('Liverpool')
              ? 'Liverpool'
              : state['location'] ?? 'Manchester',
      'availableFrom': text.contains('14 October') ||
              text.contains('14 октября') ||
              text.contains('14 października') ||
              text.contains('14 жовтня')
          ? '2026-10-14'
          : text.contains('Monday')
              ? '2026-10-12'
              : state['availableFrom'],
    };
  }
}

class LocalizedInterpreter implements AiIntentInterpreter {
  @override
  Future<Map<String, dynamic>> interpret(
          String text, Map<String, dynamic> state) async =>
      {
        'intent': 'find_job',
        'tradePhrase': 'драйлайнером',
        'location': 'Манчестере',
        'availableFrom': '2026-10-14',
      };
}

AskStroykaVoiceController controller(
        FakeCapture capture, FakeSpeech speech, FakeInterpreter interpreter,
        {Duration? maxDuration, Duration? sessionLifetime}) =>
    AskStroykaVoiceController(
      capture: capture,
      transcription: speech,
      session: AiAssistantSession(
          interpreter: interpreter, clock: () => DateTime(2026, 10, 10)),
      maxDuration: maxDuration ?? const Duration(seconds: 30),
      sessionLifetime: sessionLifetime ?? const Duration(minutes: 5),
    );

void main() {
  test('finalized recording is read before its temporary file is deleted',
      () async {
    final directory = await Directory.systemTemp.createTemp('stroyka-voice-');
    final validMp4 = Uint8List(512);
    final header = ByteData.sublistView(validMp4);
    header.setUint32(0, 16);
    validMp4.setRange(4, 8, 'ftyp'.codeUnits);
    header.setUint32(16, 36);
    validMp4.setRange(20, 24, 'moov'.codeUnits);
    header.setUint32(24, 28);
    validMp4.setRange(28, 32, 'mvhd'.codeUnits);
    header.setUint32(52, 460);
    validMp4.setRange(56, 60, 'mdat'.codeUnits);
    final recorder = FileWritingRecorder(validMp4);
    final capture = NativeVoiceCaptureService(
      recorder: recorder,
      temporaryDirectory: () async => directory,
    );
    try {
      await capture.start();
      await Future<void>.delayed(const Duration(milliseconds: 510));
      final clip = await capture.stop();
      expect(clip?.bytes, validMp4);
      expect(await File(recorder.path!).exists(), isFalse);
    } finally {
      await capture.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('finalized audio rejects missing, empty, and invalid files', () async {
    final directory = await Directory.systemTemp.createTemp('stroyka-voice-');
    try {
      final path = '${directory.path}/voice.m4a';
      expect(await readFinalizedVoiceClip(path, const Duration(seconds: 2)),
          isNull);
      await File(path).writeAsBytes([]);
      expect(await readFinalizedVoiceClip(path, const Duration(seconds: 2)),
          isNull);
      await File(path).writeAsBytes(List.filled(512, 0));
      expect(await readFinalizedVoiceClip(path, const Duration(seconds: 2)),
          isNull);
      final validMp4 = Uint8List(512);
      final header = ByteData.sublistView(validMp4);
      header.setUint32(0, 16);
      validMp4.setRange(4, 8, 'ftyp'.codeUnits);
      header.setUint32(16, 36);
      validMp4.setRange(20, 24, 'moov'.codeUnits);
      header.setUint32(24, 28);
      validMp4.setRange(28, 32, 'mvhd'.codeUnits);
      header.setUint32(52, 460);
      validMp4.setRange(56, 60, 'mdat'.codeUnits);
      await File(path).writeAsBytes(validMp4);
      expect(
          await readFinalizedVoiceClip(path, const Duration(milliseconds: 200)),
          isNull);
      expect(
          (await readFinalizedVoiceClip(path, const Duration(seconds: 1)))
              ?.bytes
              .length,
          512);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('short or empty capture never starts transcription', () async {
    final capture = FakeCapture()
      ..clip = VoiceClip(Uint8List(0), const Duration(seconds: 1));
    final speech = FakeSpeech();
    final voice = controller(capture, speech, FakeInterpreter());
    await voice.press();
    await voice.release();
    expect(voice.phase, VoicePhase.error);
    expect(speech.calls, 0);
    expect(voice.error, contains('too short'));
    voice.dispose();
  });

  test('local recording failure is not reported as a connection failure',
      () async {
    final speech = FakeSpeech();
    final voice = controller(FailingStopCapture(), speech, FakeInterpreter());
    await voice.press();
    await voice.release();
    expect(voice.phase, VoicePhase.error);
    expect(voice.error, contains('recording could not be processed'));
    expect(speech.calls, 0);
    voice.dispose();
  });

  test('voice callable failures identify the stage without provider details',
      () {
    expect(
        voiceCallableFailureMessage(
            'invalid-argument', VoicePhase.transcribing),
        contains('recording'));
    expect(voiceCallableFailureMessage('unavailable', VoicePhase.interpreting),
        contains('interpretation'));
    expect(
        voiceCallableFailureMessage('unauthenticated', VoicePhase.transcribing),
        contains('Sign in'));
    expect(
        voiceCallableFailureMessage(
            'resource-exhausted', VoicePhase.transcribing),
        contains('limit'));
  });

  test('Russian voice transcript reaches canonical search confirmation',
      () async {
    final speech = FakeSpeech()
      ..text = 'Ищу работу драйлайнером в Манчестере с 14 октября';
    final voice = AskStroykaVoiceController(
      capture: FakeCapture(),
      transcription: speech,
      session: AiAssistantSession(
        interpreter: LocalizedInterpreter(),
        clock: () => DateTime(2026, 10, 12),
      ),
    );
    await voice.press();
    await voice.release();
    expect(voice.phase, VoicePhase.confirming);
    expect(voice.turn!.intent!.tradeId, 'dryliner');
    expect(voice.turn!.intent!.location, 'Manchester');
    expect(voice.turn!.intent!.availableFrom, DateTime(2026, 10, 14));
    expect(voice.confirm()!.tradeId, 'dryliner');
    voice.dispose();
  });

  test('quick release during permission cannot start a second recording',
      () async {
    final capture = DelayedPermissionCapture();
    final speech = FakeSpeech();
    final interpreter = FakeInterpreter();
    final voice = controller(capture, speech, interpreter);
    final first = voice.press();
    await voice.release();
    await voice.press();
    capture.permissionResult.complete(VoicePermission.granted);
    await first;
    expect(capture.starts, 1);
    expect(capture.stops, 1);
    expect(speech.calls, 1);
    expect(interpreter.calls, 1);
    expect(voice.phase, VoicePhase.confirming);
    voice.dispose();
  });

  test('permission cancellation recovers without recording', () async {
    final capture = DelayedPermissionCapture();
    final voice = controller(capture, FakeSpeech(), FakeInterpreter());
    final pending = voice.press();
    await voice.cancelTurn();
    capture.permissionResult.complete(VoicePermission.granted);
    await pending;
    expect(capture.starts, 0);
    expect(voice.phase, VoicePhase.idle);
    voice.dispose();
  });

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
    speech.text = 'Manchester';
    await voice.press();
    await voice.release();
    expect(interpreter.lastState?['tradePhrase'], 'dryliner');
    expect(voice.turn!.readyToSearch, isTrue);
    voice.dispose();
  });

  test('voice correction keeps trade and date while changing location',
      () async {
    final capture = FakeCapture();
    final speech = FakeSpeech();
    final interpreter = FakeInterpreter();
    final voice = controller(capture, speech, interpreter);
    await voice.press();
    await voice.release();
    voice.change();
    expect(voice.prompt, 'What would you like to change?');
    speech.text = 'Make it Liverpool';
    await voice.press();
    await voice.release();
    expect(interpreter.lastState?['tradePhrase'], 'dryliner');
    expect(interpreter.lastState?['availableFrom'], '2026-10-14');
    expect(voice.turn!.intent!.location, 'Liverpool');
    expect(voice.turn!.intent!.availableFrom, DateTime(2026, 10, 14));
    voice.dispose();
  });

  test('multilingual and mixed transcripts use the same canonical intent path',
      () async {
    const requests = [
      'Dryliner in Manchester from 14 October',
      'Ищу работу драйлайнером в Манчестере с 14 октября',
      'Szukam pracy jako dryliner w Manchesterze od 14 października',
      'Шукаю роботу драйлайнером у Манчестері з 14 жовтня',
      'Dryliner работа Manchester с Monday',
    ];
    for (final request in requests) {
      final capture = FakeCapture();
      final speech = FakeSpeech()..text = request;
      final interpreter = FakeInterpreter();
      final voice = controller(capture, speech, interpreter);
      await voice.press();
      await voice.release();
      expect(voice.turn!.intent!.tradeId, 'dryliner');
      expect(voice.turn!.intent!.location, 'Manchester');
      expect(
          voice.turn!.intent!.availableFrom,
          request.contains('Monday')
              ? DateTime(2026, 10, 12)
              : DateTime(2026, 10, 14));
      expect(interpreter.calls, 1);
      voice.dispose();
    }
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
    voice.retry();
    expect(voice.phase, VoicePhase.idle);
    expect(voice.error, isNull);
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

  testWidgets('voice sheet closes and discards state when account changes',
      (tester) async {
    final accounts = StreamController<String?>.broadcast();
    final voice = controller(FakeCapture(), FakeSpeech(), FakeInterpreter());
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => AskStroykaVoiceSheet(
                      controller: voice,
                      ownerUid: 'worker-one',
                      accountUids: accounts.stream)),
              child: const Text('Open')));
    })));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Ask STROYKA'), findsOneWidget);
    accounts.add('worker-two');
    await tester.pumpAndSettle();
    expect(find.text('Ask STROYKA'), findsNothing);
    expect(voice.isClosed, isTrue);
    await accounts.close();
  });

  testWidgets('session timeout closes idle search without persistence',
      (tester) async {
    final voice = controller(FakeCapture(), FakeSpeech(), FakeInterpreter(),
        sessionLifetime: const Duration(seconds: 3));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AskStroykaVoiceSheet(controller: voice))));
    await tester.pump(const Duration(seconds: 3));
    expect(voice.isClosed, isTrue);
    expect(find.text('Voice session ended. Close and reopen to try again.'),
        findsOneWidget);
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
