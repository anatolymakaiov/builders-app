import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/ask_stroyka_service.dart';
import '../services/ask_stroyka_voice.dart';
import '../services/native_voice_capture.dart';

Future<AiFindJobIntent?> showAskStroykaVoice(BuildContext context) =>
    showModalBottomSheet<AiFindJobIntent>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AskStroykaVoiceSheet(
        controller: AskStroykaVoiceController(
          capture: NativeVoiceCaptureService(),
          transcription: FirebaseSpeechTranscriptionService(),
          session:
              AiAssistantSession(interpreter: FirebaseAiIntentInterpreter()),
        ),
        ownerUid: FirebaseAuth.instance.currentUser?.uid,
        accountUids:
            FirebaseAuth.instance.authStateChanges().map((user) => user?.uid),
      ),
    );

class AskStroykaVoiceSheet extends StatefulWidget {
  const AskStroykaVoiceSheet(
      {super.key, required this.controller, this.ownerUid, this.accountUids});
  final AskStroykaVoiceController controller;
  final String? ownerUid;
  final Stream<String?>? accountUids;

  @override
  State<AskStroykaVoiceSheet> createState() => _AskStroykaVoiceSheetState();
}

class _AskStroykaVoiceSheetState extends State<AskStroykaVoiceSheet>
    with WidgetsBindingObserver {
  StreamSubscription<String?>? _accountSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_refresh);
    widget.controller.checkPermission();
    if (widget.accountUids != null) {
      _accountSubscription = widget.accountUids!.listen((uid) {
        if (uid != widget.ownerUid && mounted) _close();
      });
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accountSubscription?.cancel();
    widget.controller.removeListener(_refresh);
    widget.controller.dispose();
    super.dispose();
  }

  void _close() => Navigator.pop(context);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) widget.controller.cancelTurn();
  }

  @override
  Widget build(BuildContext context) {
    final voice = widget.controller;
    final intent = voice.turn?.intent;
    final busy = voice.phase == VoicePhase.cancelling ||
        voice.phase == VoicePhase.transcribing ||
        voice.phase == VoicePhase.interpreting;
    final recording = voice.phase == VoicePhase.recording;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Expanded(
                child: Text('Ask STROYKA',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
            IconButton(
                tooltip: 'Close voice search',
                onPressed: _close,
                icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 8),
          if (voice.turn == null && voice.heard == null)
            const Text(
                "Hi, I'm your voice assistant. I can help you find jobs. "
                'Tell me the trade, where you want to work, and when you can start.',
                textAlign: TextAlign.center),
          if (voice.turn?.question != null || voice.prompt != null)
            Text(voice.turn?.question ?? voice.prompt!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          if (voice.heard != null) ...[
            const SizedBox(height: 8),
            Text('Heard: ${voice.heard}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
          ],
          if (intent != null) ...[
            const SizedBox(height: 16),
            Text('Trade: ${intent.trade.canonical}'),
            Text('Location: ${intent.location}'),
            if (intent.availableFrom != null)
              Text('Available from: ${intent.availableFrom!.day}/'
                  '${intent.availableFrom!.month}'),
            const SizedBox(height: 8),
            const Text('Is this correct?'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                final confirmed = voice.confirm();
                if (confirmed != null) Navigator.pop(context, confirmed);
              },
              icon: const Icon(Icons.search),
              label: const Text('Yes, find jobs'),
            ),
            TextButton(onPressed: voice.change, child: const Text('Change')),
          ],
          if (voice.error != null) ...[
            const SizedBox(height: 12),
            Text(voice.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (voice.phase == VoicePhase.error) ...[
            TextButton(onPressed: voice.retry, child: const Text('Try again')),
          ],
          if (voice.isClosed && intent == null)
            const Text('Voice session ended. Close and reopen to try again.'),
          const SizedBox(height: 18),
          if (busy) const CircularProgressIndicator(),
          if (!busy &&
              intent == null &&
              !voice.isClosed &&
              voice.turnsRemaining > 0) ...[
            Semantics(
              label: recording
                  ? 'Recording. Release to search'
                  : 'Hold microphone to speak',
              button: true,
              child: Listener(
                onPointerDown: (_) => voice.press(),
                onPointerUp: (_) => voice.release(),
                onPointerCancel: (_) => voice.cancelTurn(),
                onPointerMove: (event) {
                  if (event.localPosition.dx < 0 ||
                      event.localPosition.dx > 88 ||
                      event.localPosition.dy < 0 ||
                      event.localPosition.dy > 88) {
                    voice.cancelTurn();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: recording
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary),
                  child: const Icon(Icons.mic, color: Colors.white, size: 38),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(recording
                ? 'Recording · release to finish'
                : 'Hold to talk · max 30 sec'),
            if (recording)
              TextButton(
                  onPressed: voice.cancelTurn,
                  child: const Text('Cancel recording')),
          ],
          if (voice.turnsRemaining <= 0 && intent == null)
            const Text('Voice limit reached. Use normal job search.'),
          const SizedBox(height: 12),
          const Text(
              'Voice search is used only to understand your job search and is not saved.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12)),
          TextButton(
              onPressed: _close, child: const Text('Use normal job search')),
        ]),
      ),
    );
  }
}
