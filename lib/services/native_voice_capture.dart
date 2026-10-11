import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'ask_stroyka_voice.dart';

class NativeVoiceCaptureService implements VoiceCaptureService {
  NativeVoiceCaptureService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;
  DateTime? _started;
  bool _permissionRequested = false;

  @override
  Future<VoicePermission> permission({bool request = false}) async {
    final granted = await _recorder.hasPermission(request: request);
    if (granted) return VoicePermission.granted;
    if (!request && !_permissionRequested) return VoicePermission.notRequested;
    _permissionRequested = true;
    // iOS cannot present its system prompt again after the first denial.
    return Platform.isIOS
        ? VoicePermission.permanentlyDenied
        : VoicePermission.denied;
  }

  @override
  Future<void> start() async {
    if (_path != null) throw StateError('Recording already active');
    final directory = await getTemporaryDirectory();
    _path =
        '${directory.path}/ask_stroyka_${DateTime.now().microsecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: _path!,
      );
      _started = DateTime.now();
    } catch (_) {
      await _deleteFile();
      rethrow;
    }
  }

  @override
  Future<VoiceClip?> stop() async {
    final started = _started;
    final path = _path;
    _started = null;
    try {
      await _recorder.stop();
      if (path == null || started == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      return VoiceClip(
          await file.readAsBytes(), DateTime.now().difference(started));
    } finally {
      await _deleteFile();
    }
  }

  @override
  Future<void> cancel() async {
    _started = null;
    try {
      await _recorder.cancel();
    } finally {
      await _deleteFile();
    }
  }

  Future<void> _deleteFile() async {
    final path = _path;
    _path = null;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> dispose() async {
    if (_path != null) await cancel();
    await _recorder.dispose();
  }
}
