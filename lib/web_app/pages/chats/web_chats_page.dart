import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/web_chats_data_service.dart';
import '../../services/web_data_state.dart';
import '../../theme/web_breakpoints.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_remote_image.dart';

class WebChatsPage extends StatefulWidget {
  const WebChatsPage({
    super.key,
    required this.userId,
    required this.role,
  });

  final String userId;
  final String role;

  @override
  State<WebChatsPage> createState() => _WebChatsPageState();
}

class _WebChatsPageState extends State<WebChatsPage> {
  final service = WebChatsDataService();
  final messageController = TextEditingController();
  String? selectedChatId;
  bool sending = false;

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebDataState<List<WebChatSummary>>>(
      stream: service.chats(widget.userId),
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || state.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        final chats = state.data ?? const <WebChatSummary>[];
        if (selectedChatId == null && chats.isNotEmpty) {
          selectedChatId = chats.first.id;
        }
        if (selectedChatId != null &&
            chats.every((chat) => chat.id != selectedChatId)) {
          selectedChatId = chats.isEmpty ? null : chats.first.id;
        }

        return WebPageContainer(
          child: Column(
            children: [
              if (state.error != null)
                _ErrorBanner(
                  message: 'Could not refresh chats: ${state.error}',
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < WebBreakpoints.compactWidth;
                    final list = WebPanel(
                      padding: EdgeInsets.zero,
                      child: _ChatList(
                        chats: chats,
                        selectedChatId: selectedChatId,
                        userId: widget.userId,
                        onSelected: (id) => setState(() => selectedChatId = id),
                      ),
                    );
                    final thread = WebPanel(
                      padding: EdgeInsets.zero,
                      child: _ChatThread(
                        chatId: selectedChatId,
                        userId: widget.userId,
                        service: service,
                        controller: messageController,
                        sending: sending,
                        onSend: _sendMessage,
                      ),
                    );
                    if (compact) {
                      return Column(
                        children: [
                          SizedBox(height: 320, child: list),
                          const SizedBox(height: 18),
                          SizedBox(height: 640, child: thread),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(width: 390, child: list),
                        const SizedBox(width: 22),
                        Expanded(child: thread),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    if (selectedChatId == null || sending) return;
    final text = messageController.text;
    if (text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      await service.sendText(
        chatId: selectedChatId!,
        uid: widget.userId,
        text: text,
      );
      messageController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send message: $error')),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }
}

class _ChatList extends StatelessWidget {
  const _ChatList({
    required this.chats,
    required this.selectedChatId,
    required this.userId,
    required this.onSelected,
  });

  final List<WebChatSummary> chats;
  final String? selectedChatId;
  final String userId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (chats.isEmpty) {
      return const Center(child: Text('No chats yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: chats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final chat = chats[index];
        final selected = chat.id == selectedChatId;
        return InkWell(
          onTap: () => onSelected(chat.id),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFFFF6E9) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? WebTheme.green : WebTheme.border,
              ),
            ),
            child: Row(
              children: [
                WebCircleImage(
                  url: chat.avatarFor(userId),
                  size: 42,
                  fallbackIcon: Icons.person_outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chat.lastMessage.isEmpty
                            ? chat.lastMessageType
                            : chat.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: WebTheme.muted),
                      ),
                    ],
                  ),
                ),
                if (chat.unreadFor(userId))
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: WebTheme.green,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChatThread extends StatelessWidget {
  const _ChatThread({
    required this.chatId,
    required this.userId,
    required this.service,
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final String? chatId;
  final String userId;
  final WebChatsDataService service;
  final TextEditingController controller;
  final bool sending;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    if (chatId == null) {
      return const Center(child: Text('Select a conversation.'));
    }
    return StreamBuilder<WebDataState<WebChatThread?>>(
      stream: service.chatThread(chatId!, userId),
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || state.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        final thread = state.data;
        if (thread == null) {
          return const Center(child: Text('Conversation is unavailable.'));
        }
        unawaited(service.markRead(chatId!, userId));
        return Column(
          children: [
            _ThreadHeader(thread: thread, userId: userId),
            if (state.error != null)
              _ErrorBanner(
                  message: 'Could not refresh messages: ${state.error}'),
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(18),
                itemCount: thread.messages.length,
                itemBuilder: (context, index) {
                  final message = thread.messages[index];
                  final isMine = message.data['senderId'] == userId;
                  return Align(
                    alignment:
                        isMine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 520),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isMine ? WebTheme.green : const Color(0xFFF4F6F8),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        (message.data['text'] ?? '').toString(),
                        style: TextStyle(
                          color: isMine ? Colors.white : WebTheme.ink,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Write a message',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: sending ? null : onSend,
                    icon: sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: const Text('Send'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({
    required this.thread,
    required this.userId,
  });

  final WebChatThread thread;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: WebTheme.border)),
      ),
      child: Row(
        children: [
          WebCircleImage(
            url: thread.chat.avatarFor(userId),
            size: 44,
            fallbackIcon: Icons.person_outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread.chat.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                if (thread.chat.jobData != null)
                  Text(
                    (thread.chat.jobData!['title'] ??
                            thread.chat.jobData!['position'] ??
                            '')
                        .toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: WebTheme.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message),
    );
  }
}
