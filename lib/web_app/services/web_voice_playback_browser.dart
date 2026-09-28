// @dart=3.3
import 'dart:js_interop';

@JS('Audio')
extension type _AudioElement._(JSObject _) implements JSObject {
  external factory _AudioElement();
  external set src(String value);
  external set preload(String value);
  external double get duration;
  external double get currentTime;
  external set currentTime(double value);
  external JSAny? get error;
  external JSPromise<JSAny?> play();
  external void pause();
  external void load();
  external void removeAttribute(String name);
  external void addEventListener(String event, JSFunction callback);
  external void removeEventListener(String event, JSFunction callback);
}

class WebVoicePlayback {
  WebVoicePlayback({required this.onChanged}) {
    _audio.preload = 'metadata';
    _listen('loadedmetadata', () {
      final seconds = _audio.duration;
      duration = seconds.isFinite
          ? Duration(milliseconds: (seconds * 1000).round())
          : null;
      loading = false;
      _notify();
    });
    _listen('timeupdate', () {
      position = Duration(milliseconds: (_audio.currentTime * 1000).round());
      _notify();
    });
    _listen('playing', () {
      loading = false;
      playing = true;
      _notify();
    });
    _listen('waiting', () {
      loading = true;
      _notify();
    });
    _listen('pause', () {
      playing = false;
      loading = false;
      _notify();
    });
    _listen('ended', () {
      playing = false;
      position = Duration.zero;
      _audio.currentTime = 0;
      _notify();
    });
    _listen('error', () {
      loading = false;
      playing = false;
      error = 'Voice message could not be played.';
      _notify();
    });
  }

  final void Function() onChanged;
  final _AudioElement _audio = _AudioElement();
  final List<(String, JSFunction)> _listeners = [];
  String? _url;
  bool _disposed = false;
  bool loading = false;
  bool playing = false;
  String? error;
  Duration position = Duration.zero;
  Duration? duration;

  void _listen(String event, void Function() callback) {
    final jsCallback = callback.toJS;
    _audio.addEventListener(event, jsCallback);
    _listeners.add((event, jsCallback));
  }

  Future<void> toggle(String url) async {
    if (playing) {
      _audio.pause();
      return;
    }
    if (loading) return;
    error = null;
    loading = true;
    _notify();
    try {
      if (_url != url || _audio.error != null) {
        _url = url;
        position = Duration.zero;
        duration = null;
        _audio.src = url;
        _audio.load();
      }
      await _audio.play().toDart;
    } catch (_) {
      loading = false;
      playing = false;
      error = 'Voice message could not be played. Try again.';
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) onChanged();
  }

  void dispose() {
    _disposed = true;
    _audio.pause();
    _audio.removeAttribute('src');
    _audio.load();
    for (final (event, callback) in _listeners) {
      _audio.removeEventListener(event, callback);
    }
  }
}
