import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/web_chat_media_service.dart';
import '../../services/web_chat_recipient_search_service.dart';
import '../../services/web_chats_data_service.dart';
import '../../services/web_data_state.dart';
import '../../services/web_voice_recorder.dart';
import '../../widgets/web_report_dialog.dart';
import '../../theme/web_breakpoints.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_design_components.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_remote_image.dart';
import 'web_chat_media_widgets.dart';

class WebChatsPage extends StatefulWidget {
  const WebChatsPage({
    super.key,
    required this.userId,
    required this.role,
    this.initialChatId,
    this.navigationRequestId = 0,
    this.onOpenProfile,
    this.onOpenJob,
  });

  final String userId;
  final String role;
  final String? initialChatId;
  final int navigationRequestId;
  final void Function(String, String)? onOpenProfile;
  final ValueChanged<String>? onOpenJob;

  @override
  State<WebChatsPage> createState() => _WebChatsPageState();
}

class _WebChatsPageState extends State<WebChatsPage> {
  final service = WebChatsDataService();
  final mediaService = WebChatMediaService();
  final recipientSearchService = WebChatRecipientSearchService();
  final conversationSearchController = TextEditingController();
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
  final recorder = WebVoiceRecorder();
  WebMessageItem? reply;
  bool recording = false;
  bool recorderBusy = false;
  Timer? recordingLimit;
  Timer? typingTimer;
  bool typing = false;
  bool compactThreadVisible = false;

  @override
  void initState() {
    super.initState();
    selectedChatId = widget.initialChatId;
    compactThreadVisible = widget.initialChatId != null;
    if (selectedChatId != null) {
      threadStream = service.chatThread(selectedChatId!, widget.userId);
    }
    chatsStream = service.chats(widget.userId);
  }

  @override
  void didUpdateWidget(covariant WebChatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.userId != widget.userId || oldWidget.role != widget.role;
    if (identityChanged) {
      chatsStream = service.chats(widget.userId);
    }
    if (identityChanged ||
        oldWidget.navigationRequestId != widget.navigationRequestId ||
        oldWidget.initialChatId != widget.initialChatId) {
      selectedChatId = widget.initialChatId;
      compactThreadVisible = widget.initialChatId != null;
      threadStream = null;
      lastThread = null;
      lastMarkedReadKey = null;
      if (selectedChatId != null) {
        threadStream = service.chatThread(selectedChatId!, widget.userId);
      }
    }
  }

  @override
  void dispose() {
    recordingLimit?.cancel();
    typingTimer?.cancel();
    unawaited(recorder.dispose());
    conversationSearchController.dispose();
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
          return const WebLoadingState(label: 'Loading conversations');
        }
        _ensureSelectedChat(chats);
        final conversationQuery =
            conversationSearchController.text.trim().toLowerCase();
        final visibleChats = conversationQuery.isEmpty
            ? chats
            : chats
                .where((chat) =>
                    chat.title.toLowerCase().contains(conversationQuery) ||
                    chat.lastMessage.toLowerCase().contains(conversationQuery))
                .toList();

        return WebPageContainer(
          child: Column(
            children: [
              WebPageHeader(
                title: 'Chats',
                subtitle: 'Conversations about work, teams and vacancies.',
                actions: [
                  SizedBox(
                    width: 300,
                    child: TextField(
                      controller: conversationSearchController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Search conversations........',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _openNewMessage,
                    icon: const Icon(Icons.edit_square),
                    label: const Text('New message'),
                  ),
                ],
              ),
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
                        chats: visibleChats,
                        emptySearch: conversationQuery.isNotEmpty,
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
                        onMessageAction: _messageAction,
                        onOpenProfile: () {
                          final thread = lastThread;
                          if (thread == null) return;
                          final target =
                              service.profileTarget(thread.chat, widget.userId);
                          if (target != null) {
                            widget.onOpenProfile?.call(target.id, target.role);
                          }
                        },
                        onOpenJob: () {
                          final id = lastThread?.chat.data['jobId']?.toString();
                          if (id != null && id.isNotEmpty) {
                            widget.onOpenJob?.call(id);
                          }
                        },
                        reply: reply,
                        onCancelReply: () => setState(() => reply = null),
                        recording: recording,
                        onRecord: recorderBusy ? null : _toggleRecording,
                        onTyping: _typingChanged,
                        onOlder: _loadOlder,
                      ),
                    );
                    if (compact) {
                      return WebCompactDetailView(
                        showDetail:
                            compactThreadVisible && selectedChatId != null,
                        list: list,
                        detail: thread,
                        onBack: () => setState(
                          () => compactThreadVisible = false,
                        ),
                        backLabel: 'Back to conversations',
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(
                          width: WebBreakpoints.masterPaneWidth(
                            constraints.maxWidth,
                          ),
                          child: list,
                        ),
                        const SizedBox(width: WebSpacing.lg),
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
    String? nextId;
    var shouldUpdate = false;
    if (selectedChatId == null && chats.isNotEmpty) {
      nextId = chats.first.id;
      shouldUpdate = true;
    }
    if (selectedChatId != null &&
        chats.every((chat) => chat.id != selectedChatId)) {
      nextId = chats.isEmpty ? null : chats.first.id;
      shouldUpdate = true;
    }
    if (shouldUpdate && nextId != selectedChatId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || selectedChatId == nextId) return;
        setState(() => _setSelectedChat(nextId));
      });
    }
  }

  void _selectChat(String chatId) {
    if (sending || uploading || recording || recorderBusy) {
      return;
    }
    if (chatId == selectedChatId) {
      setState(() => compactThreadVisible = true);
      return;
    }
    setState(() {
      _setSelectedChat(chatId);
      compactThreadVisible = true;
    });
  }

  Future<void> _openNewMessage() async {
    final chatId = await showDialog<String>(
      context: context,
      builder: (_) => _NewMessageDialog(
        service: recipientSearchService,
        userId: widget.userId,
        role: widget.role,
      ),
    );
    if (!mounted || chatId == null || chatId.isEmpty) return;
    setState(() {
      chatsStream = service.chats(widget.userId);
      _setSelectedChat(chatId);
      compactThreadVisible = true;
    });
  }

  void _setSelectedChat(String? chatId) {
    reply = null;
    pendingAttachments.clear();
    messageController.clear();
    selectedChatId = chatId;
    lastThread = null;
    lastMessageCount = 0;
    lastMarkedReadKey = null;
    threadStream =
        chatId == null ? null : service.chatThread(chatId, widget.userId);
    if (chatId != null) {
      unawaited(service.markRead(chatId, widget.userId).catchError(
          (Object error) => debugPrint('WEB CHAT READ ERROR $error')));
      lastMarkedReadKey = '$chatId:selected';
    }
  }

  void _onThreadUpdated(WebChatThread? thread) {
    if (!mounted || thread == null || thread.chat.id != selectedChatId) return;
    final wasNearNewest =
        !messagesController.hasClients || messagesController.offset < 96;
    final grew = thread.messages.length > lastMessageCount;
    lastThread = thread;
    lastMessageCount = thread.messages.length;
    final updatedAtKey = thread.chat.updatedAt?.millisecondsSinceEpoch ?? 0;
    final readKey = '${thread.chat.id}:$updatedAtKey';
    if (thread.chat.unreadFor(widget.userId) && lastMarkedReadKey != readKey) {
      unawaited(service.markRead(thread.chat.id, widget.userId).catchError(
          (Object error) => debugPrint('WEB CHAT READ ERROR $error')));
      lastMarkedReadKey = readKey;
    }
    if (grew && wasNearNewest) _scrollToNewest();
  }

  Future<void> _sendMessage() async {
    if (selectedChatId == null || sending || uploading) return;
    final text = messageController.text;
    final chatId = selectedChatId!;
    if (text.trim().isEmpty && pendingAttachments.isEmpty) return;
    setState(() {
      sending = true;
      uploading = pendingAttachments.isNotEmpty;
    });
    try {
      final messageId = service.newMessageId(chatId);
      final uploaded = await mediaService.uploadAttachments(
        chatId: chatId,
        messageId: messageId,
        senderId: widget.userId,
        attachments: List<WebPendingChatAttachment>.from(pendingAttachments),
      );
      await service.sendMessage(
        chatId: chatId,
        messageId: messageId,
        uid: widget.userId,
        text: text,
        attachments: uploaded,
        contextFields: reply == null
            ? const {}
            : {
                'replyToMessageId': reply!.id,
                'replyToSenderId': reply!.data['senderId'],
                'replyToSenderName': reply!.data['senderName'] ?? '',
                'replyToTextPreview': reply!.text,
                'replyToAttachmentPreview':
                    webChatAttachmentPreview(reply!.attachments),
              },
      );
      if (!mounted || selectedChatId != chatId) return;
      reply = null;
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

  Future<void> _loadOlder() async {
    final thread = lastThread;
    if (thread == null || thread.messages.isEmpty) return;
    try {
      final count = await service.loadOlder(
          thread.chat.id, thread.messages.last.id, widget.userId);
      if (mounted && count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No older messages.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load older messages: $error')));
      }
    }
  }

  void _typingChanged(String text) {
    final id = selectedChatId;
    if (id == null) return;
    final next = text.trim().isNotEmpty;
    if (next != typing) {
      typing = next;
      unawaited(service
          .setTyping(id, widget.userId, next)
          .catchError((Object e) => debugPrint('WEB TYPING ERROR $e')));
    }
    typingTimer?.cancel();
    if (next) {
      typingTimer = Timer(const Duration(seconds: 2), () {
        typing = false;
        unawaited(service
            .setTyping(id, widget.userId, false)
            .catchError((Object e) => debugPrint('WEB TYPING ERROR $e')));
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (recorderBusy || sending || selectedChatId == null) return;
    setState(() => recorderBusy = true);
    try {
      if (recording) {
        recordingLimit?.cancel();
        final file = await recorder.stop();
        if (mounted) {
          setState(() {
            recording = false;
            if (file != null) pendingAttachments.add(file);
          });
        }
      } else {
        await recorder.start();
        if (!mounted) {
          await recorder.cancel();
          return;
        }
        setState(() => recording = true);
        recordingLimit = Timer(
            const Duration(minutes: 3), () => unawaited(_toggleRecording()));
      }
    } catch (error) {
      if (mounted) setState(() => recording = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not record: $error')));
      }
    } finally {
      if (mounted) setState(() => recorderBusy = false);
    }
  }

  Future<void> _messageAction(WebMessageItem message, String action) async {
    final chatId = selectedChatId;
    if (chatId == null) return;
    try {
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: message.text));
        return;
      }
      if (action == 'reply') {
        setState(() => reply = message);
        return;
      }
      if (action == 'edit') {
        final text = await showDialog<String>(
            context: context,
            builder: (_) => WebTextDialog(
                title: 'Edit message',
                label: 'Message',
                initial: message.text));
        if (text != null) {
          await service.messageAction(chatId, message, widget.userId, action,
              text: text);
        }
        return;
      }
      if (action == 'forward') {
        final chats = await service.loadChats(widget.userId);
        if (!mounted) return;
        final target = await showDialog<String>(
            context: context,
            builder: (context) =>
                SimpleDialog(title: const Text('Forward to'), children: [
                  for (final chat in chats)
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, chat.id),
                        child: Text(chat.title)),
                ]));
        if (target != null) {
          await service.sendMessage(
              chatId: target,
              uid: widget.userId,
              text: message.text,
              attachments: message.attachments,
              contextFields: {
                'forwarded': true,
                'forwardedFromMessageId': message.id,
                'forwardedFromChatId': chatId,
                'forwardedFromSenderId': message.data['senderId'],
                'forwardedFromSenderName': message.data['senderName'] ?? ''
              });
        }
        return;
      }
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(action == 'delete'
                    ? 'Delete for everyone?'
                    : 'Delete for me?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'))
                ],
              ));
      if (confirmed == true) {
        await service.messageAction(chatId, message, widget.userId, action);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update message: $error')));
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
    required this.emptySearch,
    required this.selectedChatId,
    required this.userId,
    required this.onSelected,
  });

  final List<WebChatSummary> chats;
  final bool emptySearch;
  final String? selectedChatId;
  final String userId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (chats.isEmpty) {
      return WebEmptyState(
        icon: Icons.chat_bubble_outline,
        title:
            emptySearch ? 'No matching conversations' : 'No conversations yet',
        message: emptySearch
            ? 'Try another name or message.'
            : 'Your work conversations will appear here.',
      );
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
          borderRadius: BorderRadius.circular(WebRadii.card),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? WebTheme.selected : WebTheme.surface,
              borderRadius: BorderRadius.circular(WebRadii.card),
              border: Border.all(
                color: selected ? WebTheme.accent : WebTheme.border,
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
                      color: WebTheme.accent,
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

class _NewMessageDialog extends StatefulWidget {
  const _NewMessageDialog({
    required this.service,
    required this.userId,
    required this.role,
  });

  final WebChatRecipientSearchService service;
  final String userId;
  final String role;

  @override
  State<_NewMessageDialog> createState() => _NewMessageDialogState();
}

class _NewMessageDialogState extends State<_NewMessageDialog> {
  final controller = TextEditingController();
  Timer? debounce;
  List<WebChatRecipient> results = const [];
  bool searching = false;
  String? openingId;
  String? error;
  int request = 0;

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      request++;
      setState(() {
        searching = false;
        results = const [];
        error = null;
      });
      return;
    }
    debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    final currentRequest = ++request;
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final found = await widget.service.search(
        query: query,
        currentUserId: widget.userId,
        currentRole: widget.role,
      );
      if (!mounted || currentRequest != request) return;
      setState(() {
        results = found;
        searching = false;
      });
    } catch (searchError) {
      if (!mounted || currentRequest != request) return;
      setState(() {
        searching = false;
        error = 'Could not search recipients. Please try again.';
      });
    }
  }

  Future<void> _open(WebChatRecipient recipient) async {
    if (openingId != null) return;
    setState(() {
      openingId = recipient.id;
      error = null;
    });
    try {
      final chatId = await widget.service.openOrCreate(
        currentUserId: widget.userId,
        currentRole: widget.role,
        recipient: recipient,
      );
      if (mounted) Navigator.of(context).pop(chatId);
    } catch (openError) {
      if (!mounted) return;
      setState(() {
        openingId = null;
        error = 'Could not open this conversation. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = controller.text.trim().length >= 2;
    return AlertDialog(
      title: const Text('New message'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              onChanged: _changed,
              decoration: const InputDecoration(
                labelText: 'Search people or companies',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: WebSpacing.md),
            if (searching) const LinearProgressIndicator(),
            if (error != null) ...[
              Text(error!, style: const TextStyle(color: WebTheme.danger)),
              const SizedBox(height: WebSpacing.sm),
            ],
            Expanded(
              child: !hasQuery
                  ? const WebEmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'Search by name, trade or location',
                    )
                  : !searching && results.isEmpty
                      ? const WebEmptyState(
                          icon: Icons.search_off,
                          title: 'No available recipients found',
                        )
                      : ListView.separated(
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final result = results[index];
                            final opening = openingId == result.id;
                            return ListTile(
                              enabled: openingId == null,
                              onTap: () => _open(result),
                              leading: WebCircleImage(
                                url: result.avatarUrl,
                                size: 48,
                                fallbackIcon: result.role == 'team'
                                    ? Icons.groups_2_outlined
                                    : result.role == 'employer'
                                        ? Icons.business_outlined
                                        : Icons.person_outline,
                              ),
                              title: Text(result.name),
                              subtitle: Text(
                                [
                                  result.role == 'team'
                                      ? 'Team'
                                      : result.role == 'employer'
                                          ? 'Company'
                                          : 'Worker',
                                  result.context,
                                ].where((item) => item.isNotEmpty).join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: opening
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.arrow_forward),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: openingId == null ? () => Navigator.pop(context) : null,
          child: const Text('Cancel'),
        ),
      ],
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
    required this.onMessageAction,
    required this.onOpenProfile,
    required this.onOpenJob,
    required this.reply,
    required this.onCancelReply,
    required this.recording,
    required this.onRecord,
    required this.onTyping,
    required this.onOlder,
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
  final void Function(WebMessageItem, String) onMessageAction;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenJob;
  final WebMessageItem? reply;
  final VoidCallback onCancelReply;
  final bool recording;
  final VoidCallback? onRecord;
  final ValueChanged<String> onTyping;
  final VoidCallback onOlder;

  @override
  Widget build(BuildContext context) {
    final currentStream = stream;
    if (currentStream == null) {
      return const WebEmptyState(
        icon: Icons.forum_outlined,
        title: 'Select a conversation',
      );
    }
    return StreamBuilder<WebDataState<WebChatThread?>>(
      stream: currentStream,
      initialData: lastThread == null ? null : WebDataState.data(lastThread),
      builder: (context, snapshot) {
        final state = snapshot.data;
        final thread = state?.data ?? lastThread;
        if ((state == null || state.loading) && thread == null) {
          return const WebLoadingState(label: 'Loading messages');
        }
        if (thread == null) {
          return const WebEmptyState(
            icon: Icons.forum_outlined,
            title: 'Conversation is unavailable',
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onThreadUpdated(thread);
        });
        return Column(
          children: [
            _ThreadHeader(
                thread: thread,
                userId: userId,
                onOpenProfile: onOpenProfile,
                onOpenJob: onOpenJob),
            if (thread.chat.data[thread.chat.data['workerId'] == userId
                    ? 'typing_employer'
                    : 'typing_worker'] ==
                true)
              const Text('Typing...'),
            TextButton(
                onPressed: onOlder, child: const Text('Load older messages')),
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
                  return _MessageBubble(
                      key: ValueKey(message.id),
                      message: message,
                      userId: userId,
                      onAction: (action) => onMessageAction(message, action));
                },
              ),
            ),
            WebPendingAttachmentsPreview(
              attachments: pendingAttachments,
              onRemove: onRemoveAttachment,
            ),
            if (reply != null)
              ListTile(
                  title: const Text('Reply'),
                  subtitle: Text(
                      reply!.text.isEmpty
                          ? webChatAttachmentPreview(reply!.attachments)
                          : reply!.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                      onPressed: onCancelReply,
                      tooltip: 'Cancel reply',
                      icon: const Icon(Icons.close))),
            Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                    tooltip:
                        recording ? 'Stop recording' : 'Record voice message',
                    onPressed: onRecord,
                    icon:
                        Icon(recording ? Icons.stop_circle : Icons.mic_none))),
            _Composer(
              controller: messageController,
              sending: sending,
              onSend: onSend,
              onAttach: onAttach,
              onTyping: onTyping,
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
    required this.onOpenProfile,
    required this.onOpenJob,
  });

  final WebChatThread thread;
  final String userId;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenJob;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: WebTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpenProfile,
              borderRadius: BorderRadius.circular(WebRadii.card),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
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
              ),
            ),
          ),
          if ((thread.chat.data['jobId']?.toString() ?? '').isNotEmpty)
            IconButton(
              tooltip: 'View vacancy',
              onPressed: onOpenJob,
              icon: const Icon(Icons.work_outline),
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.userId,
    required this.onAction,
  });

  final WebMessageItem message;
  final String userId;
  final ValueChanged<String> onAction;

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
          color: isMine ? WebTheme.accent : const Color(0xFFF4F6F8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            PopupMenuButton<String>(
                tooltip: 'Message actions',
                onSelected: onAction,
                itemBuilder: (_) => [
                      if (!deleted)
                        const PopupMenuItem(
                            value: 'reply', child: Text('Reply')),
                      if (!deleted && message.text.isNotEmpty)
                        const PopupMenuItem(value: 'copy', child: Text('Copy')),
                      if (!deleted)
                        const PopupMenuItem(
                            value: 'forward', child: Text('Forward')),
                      if (isMine && !deleted && message.type == 'text')
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                          value: 'hide', child: Text('Delete for me')),
                      if (isMine && !deleted)
                        const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete for everyone')),
                    ]),
            if (message.data['forwarded'] == true)
              const Text('Forwarded', style: TextStyle(fontSize: 11)),
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
    required this.onTyping,
  });

  final TextEditingController controller;
  final bool sending;
  final Future<void> Function() onSend;
  final VoidCallback onAttach;
  final ValueChanged<String> onTyping;

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
              onChanged: onTyping,
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
