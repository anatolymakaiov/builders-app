import 'package:flutter/material.dart';

import '../services/ask_stroyka_service.dart';

Future<AiFindJobIntent?> showAskStroyka(BuildContext context,
        {AiIntentInterpreter? interpreter}) =>
    showModalBottomSheet<AiFindJobIntent>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AskStroykaSheet(
        session: AiAssistantSession(
            interpreter: interpreter ?? FirebaseAiIntentInterpreter()),
      ),
    );

class AskStroykaSheet extends StatefulWidget {
  const AskStroykaSheet({super.key, required this.session});
  final AiAssistantSession session;

  @override
  State<AskStroykaSheet> createState() => _AskStroykaSheetState();
}

class _AskStroykaSheetState extends State<AskStroykaSheet> {
  final controller = TextEditingController();
  AiAssistantTurn? turn;
  String? error;
  bool loading = false;

  @override
  void dispose() {
    widget.session.clear();
    controller.dispose();
    super.dispose();
  }

  Future<void> _send([String? selected]) async {
    final message = (selected ?? controller.text).trim();
    if (message.isEmpty || loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.session.send(message);
      if (!mounted) return;
      setState(() {
        turn = next;
        controller.clear();
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Ask STROYKA is temporarily unavailable. '
            'You can still use job filters.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final intent = turn?.intent;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Expanded(
                      child: Text('Ask STROYKA',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700))),
                  IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ]),
                const Text('Ask STROYKA helps you search jobs. '
                    'This conversation is not saved.'),
                const SizedBox(height: 12),
                if (turn == null)
                  const Text('Tell me what job you are looking for, '
                      'where, and when you can start.'),
                if (turn?.question != null)
                  Text(turn!.question!,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                if (turn?.tradeChoices.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final role in turn!.tradeChoices)
                      ActionChip(
                          label: Text(role.canonical),
                          onPressed: () => _send(role.canonical)),
                  ]),
                ],
                if (intent != null) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Chip(label: Text(intent.trade.canonical)),
                    Chip(label: Text(intent.location)),
                    if (intent.availableFrom != null)
                      Chip(
                          label: Text('From ${intent.availableFrom!.day}/'
                              '${intent.availableFrom!.month}')),
                  ]),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, intent),
                    icon: const Icon(Icons.search),
                    label: const Text('Find jobs'),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: TextField(
                    controller: controller,
                    maxLength: 500,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Dryliner in Manchester from 14 October',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  )),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send request',
                    onPressed: loading ? null : _send,
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.arrow_upward),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
