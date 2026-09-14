import 'dart:js_interop';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'web_chat_media_service.dart';

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(JSString url);

class WebVoiceRecorder {
  final _recorder = AudioRecorder();
  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission is required.');
    }
    final encoder = await _recorder.isEncoderSupported(AudioEncoder.aacLc)
        ? AudioEncoder.aacLc
        : AudioEncoder.opus;
    if (!await _recorder.isEncoderSupported(encoder)) {
      throw StateError('Voice recording is not supported by this browser.');
    }
    await _recorder.start(RecordConfig(encoder: encoder), path: 'voice');
  }

  Future<WebPendingChatAttachment?> stop() async {
    final url = await _recorder.stop();
    if (url == null) return null;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw StateError('Could not read voice recording.');
      }
      final mime = response.headers['content-type'] ?? 'audio/webm';
      final extension = mime.contains('mp4')
          ? 'm4a'
          : mime.contains('ogg')
              ? 'ogg'
              : 'webm';
      return WebPendingChatAttachment(
          type: 'audio',
          fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.$extension',
          bytes: response.bodyBytes,
          sizeBytes: response.bodyBytes.length,
          mimeType: mime);
    } finally {
      if (url.startsWith('blob:')) _revokeObjectUrl(url.toJS);
    }
  }

  Future<void> cancel() => _recorder.cancel();
  Future<void> dispose() => _recorder.dispose();
}
