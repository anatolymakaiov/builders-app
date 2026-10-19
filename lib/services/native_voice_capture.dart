import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'ask_stroyka_voice.dart';

Future<VoiceClip?> readFinalizedVoiceClip(
    String? path, Duration duration) async {
  if (path == null ||
      path.isEmpty ||
      duration < const Duration(milliseconds: 500)) {
    return null;
  }
  final file = File(path);
  if (!await file.exists() || await file.length() < 128) return null;
  final bytes = await file.readAsBytes();
  if (!isFinalizedMp4(bytes)) return null;
  return VoiceClip(bytes, duration);
}

bool isFinalizedMp4(List<int> bytes) {
  if (bytes.length < 128) return false;
  int uint32(int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  var offset = 0;
  var hasFtyp = false;
  var hasMoov = false;
  var hasMdat = false;
  while (offset + 8 <= bytes.length) {
    final declaredSize = uint32(offset);
    final headerSize = declaredSize == 1 ? 16 : 8;
    if (offset + headerSize > bytes.length) return false;
    var size = declaredSize == 0 ? bytes.length - offset : declaredSize;
    if (declaredSize == 1) {
      size = 0;
      for (var i = offset + 8; i < offset + 16; i++) {
        size = (size << 8) | bytes[i];
      }
    }
    if (size < headerSize || offset + size > bytes.length) return false;
    final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    if (offset == 0 && type != 'ftyp') return false;
    hasFtyp |= type == 'ftyp';
    hasMoov |= type == 'moov';
    hasMdat |= type == 'mdat' && size > headerSize;
    offset += size;
  }
  return offset == bytes.length && hasFtyp && hasMoov && hasMdat;
}

class NativeVoiceCaptureService implements VoiceCaptureService {
  NativeVoiceCaptureService({
    AudioRecorder? recorder,
    Future<Directory> Function()? temporaryDirectory,
  })  : _recorder = recorder ?? AudioRecorder(),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final AudioRecorder _recorder;
  final Future<Directory> Function() _temporaryDirectory;
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
    final directory = await _temporaryDirectory();
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
      final recordedDuration =
          started == null ? Duration.zero : DateTime.now().difference(started);
      final finalizedPath = await _recorder.stop();
      if (path == null || started == null) return null;
      return await readFinalizedVoiceClip(finalizedPath, recordedDuration);
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
