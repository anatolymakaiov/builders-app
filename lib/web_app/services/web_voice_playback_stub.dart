class WebVoicePlayback {
  WebVoicePlayback({required this.onChanged});

  final void Function() onChanged;
  bool loading = false;
  bool playing = false;
  String? error;
  Duration position = Duration.zero;
  Duration? duration;

  Future<void> toggle(String url) async {
    error = 'Voice playback is only available in a browser.';
    onChanged();
  }

  void dispose() {}
}
