import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'ask_stroyka_service.dart';

enum VoicePhase {
  idle,
  recording,
  cancelling,
  transcribing,
  interpreting,
  clarifying,
  confirming,
  error
}

enum VoicePermission { notRequested, granted, denied, permanentlyDenied }

class VoiceClip {
  const VoiceClip(this.bytes, this.duration);
  final Uint8List bytes;
  final Duration duration;
}

abstract class VoiceCaptureService {
  Future<VoicePermission> permission({bool request = false});
  Future<void> start();
  Future<VoiceClip?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

abstract class SpeechTranscriptionService {
  Future<String> transcribe(VoiceClip clip);
}

class FirebaseSpeechTranscriptionService implements SpeechTranscriptionService {
  FirebaseSpeechTranscriptionService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<String> transcribe(VoiceClip clip) async {
    final response =
        await _functions.httpsCallable('transcribeAskStroykaVoice').call({
      'audioBase64': base64Encode(clip.bytes),
      'mimeType': 'audio/mp4',
      'durationMs': clip.duration.inMilliseconds,
    });
    return ((response.data as Map)['text'] ?? '').toString().trim();
  }
}

class AskStroykaVoiceController extends ChangeNotifier {
  AskStroykaVoiceController({
    required this.capture,
    required this.transcription,
    required this.session,
    this.maxDuration = const Duration(seconds: 30),
    this.sessionLifetime = const Duration(minutes: 5),
    this.maxTurns = 5,
  }) {
    _renewExpiry();
  }

  final VoiceCaptureService capture;
  final SpeechTranscriptionService transcription;
  final AiAssistantSession session;
  final Duration maxDuration;
  final Duration sessionLifetime;
  final int maxTurns;
  Timer? _expiry;
  Timer? _recordingLimit;
  bool _pressed = false;
  bool _closed = false;
  bool _disposed = false;
  int _turns = 0;
  VoicePhase phase = VoicePhase.idle;
  VoicePermission permissionState = VoicePermission.notRequested;
  AiAssistantTurn? turn;
  String? heard;
  String? error;
  String? prompt;

  int get turnsRemaining => maxTurns - _turns;
  bool get isClosed => _closed;

  void _renewExpiry() {
    _expiry?.cancel();
    _expiry = Timer(sessionLifetime, close);
  }

  Future<void> checkPermission() async {
    try {
      final permission = await capture.permission();
      if (_closed) return;
      permissionState = permission;
      notifyListeners();
    } catch (_) {
      if (_closed) return;
      permissionState = VoicePermission.denied;
      notifyListeners();
    }
  }

  Future<void> press() async {
    if (_closed ||
        _pressed ||
        phase == VoicePhase.recording ||
        phase == VoicePhase.cancelling ||
        phase == VoicePhase.transcribing ||
        phase == VoicePhase.interpreting ||
        turnsRemaining <= 0) {
      return;
    }
    _pressed = true;
    _renewExpiry();
    error = null;
    try {
      permissionState = await capture.permission(request: true);
      if (_closed || !_pressed) return;
      if (permissionState != VoicePermission.granted) {
        phase = VoicePhase.error;
        error = permissionState == VoicePermission.permanentlyDenied
            ? 'Microphone access is blocked. Enable it in Settings.'
            : 'Allow microphone access to use voice search.';
        notifyListeners();
        return;
      }
      await capture.start();
      if (_closed || !_pressed) {
        await capture.cancel();
        return;
      }
      phase = VoicePhase.recording;
      notifyListeners();
      final cutoffMs = maxDuration.inMilliseconds > 500
          ? maxDuration.inMilliseconds - 500
          : maxDuration.inMilliseconds;
      _recordingLimit = Timer(Duration(milliseconds: cutoffMs), release);
    } catch (_) {
      await capture.cancel();
      if (_closed) return;
      phase = VoicePhase.error;
      error = 'Could not start recording. Try again or use normal job search.';
      notifyListeners();
    }
  }

  Future<void> release() async {
    _pressed = false;
    if (_closed || phase != VoicePhase.recording) return;
    _recordingLimit?.cancel();
    phase = VoicePhase.transcribing;
    if (!_disposed) notifyListeners();
    try {
      final clip = await capture.stop();
      if (_closed) return;
      if (clip == null ||
          clip.bytes.isEmpty ||
          clip.duration < const Duration(milliseconds: 500)) {
        phase = VoicePhase.error;
        error = "I didn't catch that. Hold the button and try again.";
        notifyListeners();
        return;
      }
      _turns++;
      final transcript = (await transcription.transcribe(clip)).trim();
      if (_closed) return;
      if (transcript.isEmpty) {
        phase = VoicePhase.error;
        error = "I didn't catch that. Hold the button and try again.";
        notifyListeners();
        return;
      }
      heard = transcript;
      prompt = null;
      phase = VoicePhase.interpreting;
      notifyListeners();
      turn = await session.send(transcript);
      if (_closed) return;
      phase =
          turn!.readyToSearch ? VoicePhase.confirming : VoicePhase.clarifying;
      _renewExpiry();
      notifyListeners();
    } catch (_) {
      if (_closed) return;
      phase = VoicePhase.error;
      error =
          'Voice search is temporarily unavailable. Try again or use normal job search.';
      notifyListeners();
    }
  }

  Future<void> cancelTurn() async {
    _pressed = false;
    _recordingLimit?.cancel();
    if (phase != VoicePhase.recording) return;
    phase = VoicePhase.cancelling;
    if (!_disposed) notifyListeners();
    try {
      await capture.cancel();
    } catch (_) {
      // Cancellation is best-effort; the native service still deletes its file.
    }
    if (_closed) return;
    phase = VoicePhase.idle;
    if (!_disposed) notifyListeners();
  }

  void change() {
    if (_closed ||
        (phase != VoicePhase.confirming && phase != VoicePhase.clarifying)) {
      return;
    }
    prompt = turn?.readyToSearch == true
        ? 'What would you like to change?'
        : turn?.question;
    turn = null;
    heard = null;
    phase = VoicePhase.idle;
    _renewExpiry();
    if (!_disposed) notifyListeners();
  }

  void retry() {
    if (_closed || phase != VoicePhase.error) return;
    error = null;
    prompt = 'Hold the microphone to try again.';
    phase = VoicePhase.idle;
    _renewExpiry();
    if (!_disposed) notifyListeners();
  }

  AiFindJobIntent? confirm() {
    if (_closed || phase != VoicePhase.confirming) return null;
    final intent = turn?.intent;
    if (intent != null) unawaited(close());
    return intent;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pressed = false;
    _expiry?.cancel();
    _recordingLimit?.cancel();
    session.clear();
    turn = null;
    heard = null;
    prompt = null;
    try {
      if (phase == VoicePhase.recording) await capture.cancel();
      await capture.dispose();
    } catch (_) {
      // Teardown must not surface a recorder error after the sheet closes.
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}
