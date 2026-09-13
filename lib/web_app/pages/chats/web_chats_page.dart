import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/web_chat_media_service.dart';
import '../../services/web_chats_data_service.dart';
import '../../services/web_data_state.dart';
import '../../theme/web_breakpoints.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_remote_image.dart';
import 'web_chat_media_widgets.dart';

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
  final mediaService = WebChatMediaService();
  final messageController = TextEditingController();
  final messagesController = ScrollController();
  late Stream<WebDataState<List<WebChatSummary>>> chatsStream;
  Stream<WebDataState<WebChatThread?>>? threadStream;
  WebChatThread? lastThread;
  String? selectedChatId;
  String? lastMarkedReadKey;
  int lastMessageCount = 0;
  bool sending = false;
  bool uploading = false;
  final pendingAttachments = <WebPendingChatAttachment>[];

  @override
  void initState() {
    super.initState();
    chatsStream = service.chats(widget.userId);
  }

  @override
  void didUpdateWidget(covariant WebChatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      chatsStream = service.chats(widget.userId);
      selectedChatId = null;
      threadStream = null;
      lastThread = null;
      lastMarkedReadKey = null;
    }
  }

  @override
  void dispose() {
    messageController.dispose();
    messagesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebDataState<List<WebChatSummary>>>(
      stream: chatsStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final chats = state?.data ?? const <WebChatSummary>[];
        if ((state == null || state.loading) && chats.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        _ensureSelectedChat(chats);

        return WebPageContainer(
          child: Column(
            children: [
              if (state?.error != null)
                _ErrorBanner(
                    message: 'Could not refresh chats: ${state!.error}'),
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
                        onSelected: _selectChat,
                      ),
                    );
                    final thread = WebPanel(
                      padding: EdgeInsets.zero,
                      child: _ThreadStreamView(
                        stream: threadStream,
                        lastThread: lastThread,
                        userId: widget.userId,
                        controller: messagesController,
                        messageController: messageController,
                        sending: sending || uploading,
                        pendingAttachments: pendingAttachments,
                        onThreadUpdated: _onThreadUpdated,
                        onSend: _sendMessage,
                        onAttach: _openAttachmentMenu,
                        onRemoveAttachment: _removePendingAttachment,
                      ),
                    );
                    if (compact) {
                      return Column(
                        children: [
                          SizedBox(height: 320, child: list),
                          const SizedBox(height: 18),
                          SizedBox(height: 700, child: thread),
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

  void _ensureSelectedChat(List<WebChatSummary> chats) {
    if (selectedChatId == null && chats.isNotEmpty) {
      _setSelectedChat(chats.first.id);
      return;
    }
    if (selectedChatId != null &&
        chats.every((chat) => chat.id != selectedChatId)) {
      _setSelectedChat(chats.isEmpty ? null : chats.first.id);
    }
  }

  void _selectChat(String chatId) {
    if (chatId == selectedChatId) return;
    setState(() => _setSelectedChat(chatId));
  }

  void _setSelectedChat(String? chatId) {
    selectedChatId = chatId;
    lastThread = null;
    lastMessageCount = 0;
    lastMarkedReadKey = null;
    threadStream =
        chatId == null ? null : service.chatThread(chatId, widget.userId);
    if (chatId != null) {
      unawaited(service.markRead(chatId, widget.userId));
      lastMarkedReadKey = '$chatId:selected';
    }
  }

  void _onThreadUpdated(WebChatThread? thread) {
    if (thread == null) return;
    final wasNearNewest =
        !messagesController.hasClients || messagesController.offset < 96;
    final grew = thread.messages.length > lastMessageCount;
    lastThread = thread;
    lastMessageCount = thread.messages.length;
    final updatedAtKey = thread.chat.updatedAt?.millisecondsSinceEpoch ?? 0;
    final readKey = '${thread.chat.id}:$updatedAtKey';
    if (thread.chat.unreadFor(widget.userId) && lastMarkedReadKey != readKey) {
      unawaited(service.markRead(thread.chat.id, widget.userId));
      lastMarkedReadKey = readKey;
    }
    if (grew && wasNearNewest) _scrollToNewest();
  }

  Future<void> _sendMessage() async {
    if (selectedChatId == null || sending || uploading) return;
    final text = messageController.text;
    if (text.trim().isEmpty && pendingAttachments.isEmpty) return;
    setState(() {
      sending = true;
      uploading = pendingAttachments.isNotEmpty;
    });
    try {
      final messageId = service.newMessageId(selectedChatId!);
      final uploaded = await mediaService.uploadAttachments(
        chatId: selectedChatId!,
        messageId: messageId,
        senderId: widget.userId,
        attachments: List<WebPendingChatAttachment>.from(pendingAttachments),
      );
      await service.sendMessage(
        chatId: selectedChatId!,
        messageId: messageId,
        uid: widget.userId,
        text: text,
        attachments: uploaded,
      );
      messageController.clear();
      pendingAttachments.clear();
      _scrollToNewest();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send message: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          sending = false;
          uploading = false;
        });
      }
    }
  }

  Future<void> _openAttachmentMenu() async {
    final action = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(32, 500, 32, 0),
      items: const [
        PopupMenuItem(value: 'photo', child: Text('Photo')),
        PopupMenuItem(value: 'video', child: Text('Video')),
        PopupMenuItem(value: 'file', child: Text('File')),
      ],
    );
    if (action == null) return;
    try {
      final picked = switch (action) {
        'photo' => await mediaService.pickImages(),
        'video' => await mediaService.pickVideos(),
        _ => await mediaService.pickFiles(),
      };
      if (!mounted || picked.isEmpty) return;
      setState(() => pendingAttachments.addAll(picked));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not attach file: $error')),
      );
    }
  }

  void _removePendingAttachment(int index) {
    if (index < 0 || index >= pendingAttachments.length) return;
    setState(() => pendingAttachments.removeAt(index));
  }

  void _scrollToNewest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!messagesController.hasClients) return;
      messagesController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
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
    if (chats.isEmpty) return const Center(child: Text('No chats yet.'));
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
                  size: 50,
                  fallbackIcon: chat.data['type'] == 'team'
                      ? Icons.groups_2_outlined
                      : Icons.person_outline,
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
                        chat.lastMessage,
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

class _ThreadStreamView extends StatelessWidget {
  const _ThreadStreamView({
    required this.stream,
    required this.lastThread,
    required this.userId,
    required this.controller,
    required this.messageController,
    required this.sending,
    required this.pendingAttachments,
    required this.onThreadUpdated,
    required this.onSend,
    required this.onAttach,
    required this.onRemoveAttachment,
  });

  final Stream<WebDataState<WebChatThread?>>? stream;
  final WebChatThread? lastThread;
  final String userId;
  final ScrollController controller;
  final TextEditingController messageController;
  final bool sending;
  final List<WebPendingChatAttachment> pendingAttachments;
  final ValueChanged<WebChatThread?> onThreadUpdated;
  final Future<void> Function() onSend;
  final VoidCallback onAttach;
  final ValueChanged<int> onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final currentStream = stream;
    if (currentStream == null) {
      return const Center(child: Text('Select a conversation.'));
    }
    return StreamBuilder<WebDataState<WebChatThread?>>(
      stream: currentStream,
      initialData: lastThread == null ? null : WebDataState.data(lastThread),
      builder: (context, snapshot) {
        final state = snapshot.data;
        final thread = state?.data ?? lastThread;
        if ((state == null || state.loading) && thread == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (thread == null) {
          return const Center(child: Text('Conversation is unavailable.'));
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onThreadUpdated(thread);
        });
        return Column(
          children: [
            _ThreadHeader(thread: thread, userId: userId),
            if (state?.error != null)
              _ErrorBanner(
                  message: 'Could not refresh messages: ${state!.error}'),
            Expanded(
              child: ListView.builder(
                controller: controller,
                reverse: true,
                padding: const EdgeInsets.all(18),
                itemCount: thread.messages.length,
                itemBuilder: (context, index) {
                  final message = thread.messages[index];
                  return _MessageBubble(message: message, userId: userId);
                },
              ),
            ),
            WebPendingAttachmentsPreview(
              attachments: pendingAttachments,
              onRemove: onRemoveAttachment,
            ),
            _Composer(
              controller: messageController,
              sending: sending,
              onSend: onSend,
              onAttach: onAttach,
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
            size: 58,
            fallbackIcon: thread.chat.data['type'] == 'team'
                ? Icons.groups_2_outlined
                : Icons.person_outline,
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
                            thread.chat.jobData!['trade'] ??
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.userId,
  });

  final WebMessageItem message;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final isMine = message.data['senderId'] == userId;
    final attachments = message.attachments;
    final deleted = message.deletedForEveryone;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? WebTheme.green : const Color(0xFFF4F6F8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (_hasReply(message.data)) _ReplyPreview(data: message.data),
            if (deleted)
              Text(
                'Message deleted',
                style:
                    TextStyle(color: isMine ? Colors.white70 : WebTheme.muted),
              )
            else ...[
              if (message.text.trim().isNotEmpty)
                Text(
                  message.text,
                  style: TextStyle(
                    color: isMine ? Colors.white : WebTheme.ink,
                  ),
                ),
              WebChatAttachmentsView(attachments: attachments, isMine: isMine),
              if (message.edited)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'edited',
                    style: TextStyle(
                      fontSize: 11,
                      color: isMine ? Colors.white70 : WebTheme.muted,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasReply(Map<String, dynamic> data) {
    return (data['replyToTextPreview']?.toString().trim().isNotEmpty ??
            false) ||
        (data['replyToAttachmentPreview']?.toString().trim().isNotEmpty ??
            false);
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final sender = data['replyToSenderName']?.toString().trim() ?? '';
    final text = data['replyToTextPreview']?.toString().trim() ??
        data['replyToAttachmentPreview']?.toString().trim() ??
        '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        [sender, text].where((part) => part.isNotEmpty).join(': '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool sending;
  final Future<void> Function() onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconButton.outlined(
            onPressed: sending ? null : onAttach,
            icon: const Icon(Icons.attach_file),
            tooltip: 'Attach',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
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
