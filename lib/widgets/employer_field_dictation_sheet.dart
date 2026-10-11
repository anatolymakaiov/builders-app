import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ask_stroyka_voice.dart';
import '../services/native_voice_capture.dart';

const employerDictationLimit = Duration(seconds: 60);

String appendDictation(String existing, String spoken) {
  final addition = spoken.trim();
  if (addition.isEmpty) return existing;
  if (existing.trim().isEmpty) return addition;
  return '${existing.trimRight()}\n$addition';
}

Future<String?> showEmployerFieldDictation(BuildContext context,
        {required String fieldName}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EmployerFieldDictationSheet(
        fieldName: fieldName,
        capture: NativeVoiceCaptureService(),
        transcription:
            FirebaseSpeechTranscriptionService(mode: 'employer_dictation'),
      ),
    );

class EmployerFieldDictationSheet extends StatefulWidget {
  const EmployerFieldDictationSheet({
    super.key,
    required this.fieldName,
    required this.capture,
    required this.transcription,
    this.maxDuration = employerDictationLimit,
  });

  final String fieldName;
  final VoiceCaptureService capture;
  final SpeechTranscriptionService transcription;
  final Duration maxDuration;

  @override
  State<EmployerFieldDictationSheet> createState() =>
      _EmployerFieldDictationSheetState();
}

class _EmployerFieldDictationSheetState
    extends State<EmployerFieldDictationSheet> with WidgetsBindingObserver {
  bool _starting = false;
  bool _recording = false;
  bool _processing = false;
  bool _releaseRequested = false;
  bool _cancelRequested = false;
  Timer? _limit;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _press() async {
    if (_starting || _recording || _processing) return;
    setState(() {
      _starting = true;
      _releaseRequested = false;
      _cancelRequested = false;
      _error = null;
    });
    try {
      final permission = await widget.capture.permission(request: true);
      if (!mounted || _cancelRequested) return;
      if (permission != VoicePermission.granted) {
        setState(
            () => _error = 'Allow microphone access to dictate this field.');
        return;
      }
      await widget.capture.start();
      if (!mounted || _cancelRequested) {
        await widget.capture.cancel();
        return;
      }
      setState(() => _recording = true);
      final cutoff = widget.maxDuration > const Duration(milliseconds: 500)
          ? widget.maxDuration - const Duration(milliseconds: 500)
          : widget.maxDuration;
      _limit = Timer(cutoff, _release);
      if (_releaseRequested) {
        _starting = false;
        await _release();
      }
    } catch (_) {
      try {
        await widget.capture.cancel();
      } catch (_) {}
      if (mounted) {
        setState(() => _error = 'Could not start recording. Try again.');
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _release() async {
    if (_starting) {
      _releaseRequested = true;
      return;
    }
    if (!_recording || _processing) return;
    _limit?.cancel();
    setState(() {
      _recording = false;
      _processing = true;
    });
    try {
      final clip = await widget.capture.stop();
      if (!mounted) return;
      if (clip == null ||
          clip.bytes.isEmpty ||
          clip.duration < const Duration(milliseconds: 500)) {
        throw StateError('Recording too short');
      }
      final spoken = (await widget.transcription.transcribe(clip)).trim();
      if (!mounted) return;
      if (spoken.isEmpty) throw StateError('No speech');
      Navigator.pop(context, spoken);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not transcribe. Try again or type it.');
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _cancel() async {
    _cancelRequested = true;
    _limit?.cancel();
    if (_recording) {
      setState(() => _recording = false);
      try {
        await widget.capture.cancel();
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _limit?.cancel();
    unawaited(widget.capture.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Dictate ${widget.fieldName}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          const Text(
              'Hold the microphone, then release to insert editable text.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (_processing) const CircularProgressIndicator(),
          if (!_processing)
            Semantics(
              label: _recording
                  ? 'Recording. Release to insert text'
                  : 'Hold microphone to dictate',
              button: true,
              child: Listener(
                onPointerDown: (_) => _press(),
                onPointerUp: (_) => _release(),
                onPointerCancel: (_) => _cancel(),
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _recording
                        ? Colors.red
                        : Theme.of(context).colorScheme.primary,
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 38),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(_processing
              ? 'Transcribing...'
              : _recording
                  ? 'Recording · release to finish'
                  : 'Up to 60 seconds'),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
        ]),
      );
}
