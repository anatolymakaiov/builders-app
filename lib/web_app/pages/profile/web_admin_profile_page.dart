import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../../services/moderation_hold_service.dart';
import '../jobs/web_job_details_panel.dart';
import '../../pages/chats/web_chat_media_widgets.dart';
import '../../services/web_admin_inbox_media_service.dart';
import '../../services/web_admin_profile_service.dart';
import '../../services/web_admin_report_summary.dart';
import '../../services/web_chat_media_service.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';

enum WebAdminSection { inbox, search, jobs, requests, reports }

class WebAdminProfileAccessGate extends StatelessWidget {
  const WebAdminProfileAccessGate({
    super.key,
    required this.access,
    required this.onClose,
    required this.child,
  });

  final Future<bool> access;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: access,
        builder: (context, auth) {
          if (!auth.hasData) {
            if (!auth.hasError) {
              return const Center(child: CircularProgressIndicator());
            }
          }
          if (auth.data == true) return child;
          return Center(
              child: WebPanel(
                  child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(auth.hasError
                  ? 'Could not verify administrator access.'
                  : 'Administrator access required.'),
              TextButton(onPressed: onClose, child: const Text('Back')),
            ],
          )));
        },
      );
}

class WebAdminProfilePage extends StatefulWidget {
  const WebAdminProfilePage({
    super.key,
    required this.uid,
    required this.profile,
    required this.onClose,
    required this.onOpenProfile,
    this.service,
  });

  final String uid;
  final Map<String, dynamic> profile;
  final VoidCallback onClose;
  final void Function(String, String) onOpenProfile;
  final WebAdminProfileService? service;

  @override
  State<WebAdminProfilePage> createState() => _WebAdminProfilePageState();
}

class _WebAdminProfilePageState extends State<WebAdminProfilePage> {
  late WebAdminProfileService service;
  late Future<bool> access;
  late Future<List<WebAdminRecord>> records;
  WebAdminSection section = WebAdminSection.inbox;
  String query = '';
  String inboxView = 'Incoming';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    service = widget.service ?? WebAdminProfileService();
    access = service.isAuthorized(widget.uid);
    records = access
        .then((allowed) async => allowed ? await _load() : <WebAdminRecord>[]);
  }

  @override
  void didUpdateWidget(covariant WebAdminProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      service = widget.service ?? WebAdminProfileService();
      access = service.isAuthorized(widget.uid);
      records = access.then(
          (allowed) async => allowed ? await _load() : <WebAdminRecord>[]);
    }
  }

  Future<List<WebAdminRecord>> _load() {
    switch (section) {
      case WebAdminSection.inbox:
        return service.load('admin_messages');
      case WebAdminSection.search:
        return service.loadMany(['users', 'jobs']);
      case WebAdminSection.jobs:
        return service.loadMany(['jobs', 'vacancy_edit_reviews']);
      case WebAdminSection.requests:
        return service
            .loadMany(['support_requests', 'reports', 'payment_requests']);
      case WebAdminSection.reports:
        return service.loadMany([
          'users',
          'jobs',
          'applications',
          'support_requests',
          'reports',
          'payment_requests',
          'plans',
        ]);
    }
  }

  void _select(WebAdminSection next) {
    setState(() {
      section = next;
      query = '';
      _reloadAuthorized();
    });
  }

  void _reloadAuthorized() {
    access = service.isAuthorized(widget.uid);
    records = access
        .then((allowed) async => allowed ? await _load() : <WebAdminRecord>[]);
  }

  void _refresh() => setState(_reloadAuthorized);

  Future<void> _act(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $error')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _ask(String title, {bool required = true}) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: required ? 'Message (required)' : 'Message (optional)',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (required && value.isEmpty) return;
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebAdminProfileAccessGate(
      access: access,
      onClose: widget.onClose,
      child: SingleChildScrollView(
        child: WebPageContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: WebSpacing.lg),
              _tabs(),
              const SizedBox(height: WebSpacing.lg),
              FutureBuilder<List<WebAdminRecord>>(
                future: records,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return WebPanel(
                        child: Column(children: [
                      const Text('Could not load administrator data.'),
                      TextButton(
                          onPressed: _refresh, child: const Text('Retry')),
                    ]));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _section(snapshot.data!);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final name = (widget.profile['name'] ??
            widget.profile['displayName'] ??
            'Administrator')
        .toString();
    final email = (widget.profile['email'] ?? '').toString();
    return Row(children: [
      IconButton(
          onPressed: widget.onClose,
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back)),
      const SizedBox(width: WebSpacing.sm),
      const CircleAvatar(
          radius: 24,
          backgroundColor: WebTheme.accentSoft,
          child: Icon(Icons.admin_panel_settings_outlined,
              color: WebTheme.accent)),
      const SizedBox(width: WebSpacing.md),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name,
            style: WebTypography.pageTitle, overflow: TextOverflow.ellipsis),
        Text(email.isEmpty ? 'Administrator' : email,
            style: WebTypography.metadata),
      ])),
      IconButton(
          onPressed: _refresh,
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh)),
    ]);
  }

  Widget _tabs() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<WebAdminSection>(
          segments: const [
            ButtonSegment(
                value: WebAdminSection.inbox,
                label: Text('Inbox'),
                icon: Icon(Icons.mail_outline)),
            ButtonSegment(
                value: WebAdminSection.search,
                label: Text('Search'),
                icon: Icon(Icons.search)),
            ButtonSegment(
                value: WebAdminSection.jobs,
                label: Text('Jobs'),
                icon: Icon(Icons.work_outline)),
            ButtonSegment(
                value: WebAdminSection.requests,
                label: Text('Support & Billing'),
                icon: Icon(Icons.support_agent)),
            ButtonSegment(
                value: WebAdminSection.reports,
                label: Text('Reports'),
                icon: Icon(Icons.bar_chart)),
          ],
          selected: {section},
          onSelectionChanged: (value) => _select(value.first),
        ),
      );

  Widget _section(List<WebAdminRecord> all) {
    switch (section) {
      case WebAdminSection.inbox:
        return _inbox(all);
      case WebAdminSection.search:
        return _search(all);
      case WebAdminSection.jobs:
        return _jobs(all);
      case WebAdminSection.requests:
        return _requests(all);
      case WebAdminSection.reports:
        return _reports(all);
    }
  }

  Widget _title(String label, {Widget? action}) => Row(children: [
        Expanded(child: Text(label, style: WebTypography.sectionTitle)),
        if (action != null) action,
      ]);

  Widget _empty(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: WebSpacing.xl),
        child: Text(label, style: WebTypography.metadata),
      );

  Widget _record(WebAdminRecord item, {List<Widget> actions = const []}) {
    final heading = item.title.isNotEmpty ? item.title : item.id;
    final subtitle = item.text.isNotEmpty ? item.text : item.status;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebSpacing.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(heading, style: WebTypography.cardTitle),
        if (subtitle.isNotEmpty)
          Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
        if (item.status.isNotEmpty)
          Text(item.status, style: WebTypography.metadata),
        if (actions.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 4, children: actions),
        const Divider(height: 16),
      ]),
    );
  }

  Widget _inbox(List<WebAdminRecord> all) {
    final messages = all.where((item) {
      final data = item.data;
      if (inboxView == 'Deleted') return data['deletedByAdmin'] == true;
      if (data['deletedByAdmin'] == true) return false;
      return inboxView == 'Sent'
          ? data['direction'] == 'outgoing'
          : data['direction'] != 'outgoing';
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return WebPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Inbox',
          action: FilledButton.icon(
              onPressed: busy ? null : _compose,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('New message'))),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'Incoming', label: Text('Incoming')),
          ButtonSegment(value: 'Sent', label: Text('Sent')),
          ButtonSegment(value: 'Deleted', label: Text('Deleted'))
        ],
        selected: {inboxView},
        onSelectionChanged: (value) => setState(() => inboxView = value.first),
      ),
      if (messages.isEmpty)
        _empty('No messages.')
      else
        for (final item in messages)
          _record(item, actions: [
            TextButton(
                onPressed: () => _openMail(item, all),
                child: const Text('Open')),
            IconButton(
              tooltip: item.data['important'] == true
                  ? 'Remove important'
                  : 'Mark important',
              onPressed: busy
                  ? null
                  : () => _act(() => service.setMailFlag(
                      item.id, 'important', item.data['important'] != true)),
              icon: Icon(item.data['important'] == true
                  ? Icons.star
                  : Icons.star_border),
            ),
            IconButton(
              tooltip: inboxView == 'Deleted' ? 'Restore' : 'Delete',
              onPressed: busy
                  ? null
                  : () => _act(() => service.setMailFlag(
                      item.id, 'deletedByAdmin', inboxView != 'Deleted')),
              icon: Icon(inboxView == 'Deleted'
                  ? Icons.restore_from_trash
                  : Icons.delete_outline),
            ),
          ]),
    ]));
  }

  Future<void> _compose({WebAdminRecord? reply}) async {
    final recipient = TextEditingController(
        text: reply == null
            ? ''
            : (reply.data['direction'] == 'outgoing'
                        ? reply.data['receiverId']
                        : reply.data['senderId'])
                    ?.toString() ??
                '');
    final subject =
        TextEditingController(text: reply?.data['subject']?.toString() ?? '');
    final message = TextEditingController();
    final selected = <WebPendingChatAttachment>[];
    try {
      final send = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, updateDialog) => AlertDialog(
                    title: Text(reply == null ? 'New admin message' : 'Reply'),
                    content: SizedBox(
                        width: 480,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextField(
                                  controller: recipient,
                                  decoration: const InputDecoration(
                                      labelText: 'Recipient user ID')),
                              const SizedBox(height: 8),
                              TextField(
                                  controller: subject,
                                  decoration: const InputDecoration(
                                      labelText: 'Subject')),
                              const SizedBox(height: 8),
                              TextField(
                                  controller: message,
                                  maxLines: 5,
                                  decoration: const InputDecoration(
                                      labelText: 'Message')),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                  onPressed: () async {
                                    try {
                                      final picked =
                                          await WebAdminInboxMediaService()
                                              .pickAttachments();
                                      if (dialogContext.mounted) {
                                        updateDialog(
                                            () => selected.addAll(picked));
                                      }
                                    } catch (error) {
                                      if (dialogContext.mounted) {
                                        ScaffoldMessenger.of(dialogContext)
                                            .showSnackBar(SnackBar(
                                                content: Text(
                                                    'Could not select files: $error')));
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.attach_file),
                                  label: const Text('Attach files')),
                              WebPendingAttachmentsPreview(
                                  attachments: selected,
                                  onRemove: (index) => updateDialog(
                                      () => selected.removeAt(index))),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Send')),
                    ],
                  )));
      if (send != true || !mounted) return;
      final uid = recipient.text.trim();
      final role = reply == null
          ? ''
          : (reply.data['direction'] == 'outgoing'
                      ? reply.data['receiverRole']
                      : reply.data['senderRole'])
                  ?.toString() ??
              '';
      await _act(() async {
        final files = selected.isEmpty
            ? <Map<String, dynamic>>[]
            : await WebAdminInboxMediaService()
                .upload(uid: widget.uid, attachments: selected);
        await service.sendMessage(
          receiverId: uid,
          receiverRole: role,
          subject: subject.text,
          message: message.text,
          attachments: files,
          threadId: reply?.data['threadId']?.toString(),
        );
      });
    } finally {
      recipient.dispose();
      subject.dispose();
      message.dispose();
    }
  }

  Future<void> _openMail(WebAdminRecord item, List<WebAdminRecord> all) async {
    if (item.data['readByAdmin'] != true) {
      await _act(() => service.setMailFlag(item.id, 'readByAdmin', true));
    }
    if (!mounted) return;
    final threadId = item.data['threadId'];
    final thread = (threadId == null
        ? [item]
        : all
            .where((message) =>
                message.data['threadId'] == threadId &&
                message.data['deletedByAdmin'] != true)
            .toList())
      ..sort((a, b) => a.date.compareTo(b.date));
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(item.data['subject']?.toString() ?? 'Message'),
              content: SizedBox(
                  width: 560,
                  height: 420,
                  child: ListView(children: [
                    for (final message in thread)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  message.data['senderName']?.toString() ??
                                      'User',
                                  style: WebTypography.cardTitle),
                              const SizedBox(height: 4),
                              Text(message.text),
                              WebChatAttachmentsView(
                                  attachments:
                                      normalizeWebChatAttachments(message.data),
                                  isMine:
                                      message.data['direction'] == 'outgoing'),
                            ]),
                      ),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close')),
                if (item.data['canReply'] != false)
                  FilledButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _compose(reply: item);
                      },
                      child: const Text('Reply')),
              ],
            ));
  }

  Widget _search(List<WebAdminRecord> all) {
    final matches = query.trim().isEmpty
        ? <WebAdminRecord>[]
        : all
            .where((item) => webAdminSearchMatches(item, query))
            .take(80)
            .toList();
    return WebPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Search people and vacancies'),
      const SizedBox(height: 12),
      TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Name, email, phone, company or vacancy')),
      if (query.trim().isEmpty)
        _empty('Enter a search term.')
      else if (matches.isEmpty)
        _empty('No results.')
      else
        for (final item in matches)
          _record(item,
              actions: item.collection == 'users'
                  ? _userActions(item)
                  : _jobActions(item)),
    ]));
  }

  List<Widget> _userActions(WebAdminRecord item) {
    final role = item.data['role']?.toString() ?? 'worker';
    final held = ModerationHoldService.isProfileHeld(item.data);
    return [
      TextButton(
          onPressed: () => widget.onOpenProfile(item.id, role),
          child: const Text('View profile')),
      if (item.id != widget.uid)
        TextButton(
            onPressed: busy
                ? null
                : () async {
                    if (held) {
                      await _act(() => service.restoreUser(item.id));
                      return;
                    }
                    final reason = await _ask('Hold profile');
                    if (reason != null) {
                      await _act(() => service.holdUser(item, reason));
                    }
                  },
            child: Text(held ? 'Restore profile' : 'Hold profile')),
      if (item.id != widget.uid)
        TextButton(
            onPressed: busy ? null : () => _composeForUser(item),
            child: const Text('Message')),
    ];
  }

  Future<void> _composeForUser(WebAdminRecord item) async {
    final message =
        await _ask('Message ${item.title.isEmpty ? item.id : item.title}');
    if (message == null) return;
    await _act(() => service.sendMessage(
        receiverId: item.id,
        receiverRole: item.data['role']?.toString() ?? '',
        subject: 'Message from Administrator',
        message: message));
  }

  List<Widget> _jobActions(WebAdminRecord item) => [
        TextButton(
            onPressed: () => _viewVacancy(item),
            child: const Text('View vacancy')),
        if (item.data['moderationStatus'] == 'pending_review')
          TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final note =
                          await _ask('Approve vacancy', required: false);
                      if (note != null) {
                        await _act(() => service.approveJob(item, note));
                      }
                    },
              child: const Text('Approve')),
        if (item.data['moderationStatus'] == 'pending_review')
          TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final reason = await _ask('Reject vacancy');
                      if (reason != null) {
                        await _act(() => service.rejectJob(item, reason));
                      }
                    },
              child: const Text('Reject')),
        if (ModerationHoldService.isJobHeld(item.data))
          TextButton(
              onPressed:
                  busy ? null : () => _act(() => service.restoreJob(item.id)),
              child: const Text('Restore vacancy'))
        else
          TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final reason = await _ask('Hold vacancy');
                      if (reason != null) {
                        await _act(() => service.holdJob(item, reason));
                      }
                    },
              child: const Text('Hold vacancy')),
      ];

  Future<void> _viewVacancy(WebAdminRecord item) async {
    final job = Job.fromFirestore(item.id, item.data);
    await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final size = MediaQuery.sizeOf(dialogContext);
          return Dialog(
              child: SizedBox(
            width: (size.width * 0.92).clamp(0.0, 920.0),
            height: (size.height * 0.85).clamp(0.0, 780.0),
            child: Column(children: [
              Row(children: [
                const SizedBox(width: 16),
                const Expanded(
                    child: Text('Vacancy details',
                        style: WebTypography.panelTitle)),
                IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close)),
              ]),
              Expanded(child: WebJobDetailsPanel(job: job)),
            ]),
          ));
        });
  }

  Widget _jobs(List<WebAdminRecord> all) {
    final jobs = all.where((item) => item.collection == 'jobs').toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final edits = all
        .where((item) =>
            item.collection == 'vacancy_edit_reviews' &&
            item.data['reviewStatus'] == 'pending')
        .toList();
    return WebPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Vacancy moderation'),
      if (edits.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('Pending edits', style: WebTypography.panelTitle),
        for (final edit in edits)
          _record(edit, actions: [
            TextButton(
                onPressed: busy
                    ? null
                    : () => _act(() => service.reviewEdit(edit.id, 'approve')),
                child: const Text('Approve edit')),
            TextButton(
                onPressed: busy
                    ? null
                    : () => _act(() => service.reviewEdit(edit.id, 'reject')),
                child: const Text('Reject edit')),
            TextButton(
                onPressed: busy
                    ? null
                    : () =>
                        _act(() => service.reviewEdit(edit.id, 'treat_as_new')),
                child: const Text('Review as new')),
          ]),
      ],
      if (jobs.isEmpty)
        _empty('No vacancies.')
      else
        for (final job in jobs) _record(job, actions: _jobActions(job)),
    ]));
  }

  Widget _requests(List<WebAdminRecord> all) {
    final items = [...all]..sort((a, b) => b.date.compareTo(a.date));
    return WebPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Support & Billing'),
      if (items.isEmpty)
        _empty('No requests.')
      else
        for (final item in items)
          _record(item, actions: [
            Text(item.collection.replaceAll('_', ' '),
                style: WebTypography.metadata),
            TextButton(
                onPressed: () => _openRequest(item), child: const Text('Open')),
            PopupMenuButton<String>(
              tooltip: 'Change status',
              enabled: !busy,
              onSelected: (status) =>
                  _act(() => service.updateRequest(item, status)),
              itemBuilder: (_) => [
                for (final status in item.collection == 'payment_requests'
                    ? const [
                        'pending',
                        'approved',
                        'failed',
                        'on_hold',
                        'cancelled',
                        'rejected',
                        'pending_user_reply'
                      ]
                    : const [
                        'open',
                        'in_progress',
                        'pending_user_reply',
                        'resolved',
                        'closed'
                      ])
                  PopupMenuItem(
                      value: status, child: Text(status.replaceAll('_', ' '))),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text('Change status',
                    style: TextStyle(color: WebTheme.accent)),
              ),
            ),
            if ((item.data['userId'] ??
                        item.data['fromUserId'] ??
                        item.data['employerId'])
                    ?.toString()
                    .isNotEmpty ==
                true)
              TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final uid = (item.data['userId'] ??
                                  item.data['fromUserId'] ??
                                  item.data['employerId'])
                              .toString();
                          final reply = await _ask('Reply to request');
                          if (reply != null) {
                            await _act(() => service.sendMessage(
                                receiverId: uid,
                                receiverRole:
                                    item.data['userRole']?.toString() ??
                                        item.data['role']?.toString() ??
                                        '',
                                subject: 'Support request',
                                message: reply,
                                relatedTargetType: item.collection,
                                relatedTargetId: item.id));
                          }
                        },
                  child: const Text('Reply')),
          ]),
    ]));
  }

  Future<void> _openRequest(WebAdminRecord item) async {
    if (item.data['readByAdmin'] != true) {
      await _act(() => service.markRequestRead(item));
      if (!mounted) return;
    }
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(item.title.isEmpty
                  ? item.collection.replaceAll('_', ' ')
                  : item.title),
              content: SizedBox(
                  width: 560,
                  height: 360,
                  child: ListView(children: [
                    Text(item.text.isEmpty ? 'No message.' : item.text),
                    const SizedBox(height: 16),
                    for (final field in [
                      'status',
                      'userId',
                      'fromUserId',
                      'employerId',
                      'jobId',
                      'planName'
                    ])
                      if (item.data[field]?.toString().isNotEmpty == true)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text('$field: ${item.data[field]}',
                                style: WebTypography.metadata)),
                    WebChatAttachmentsView(
                      attachments: normalizeWebChatAttachments(item.data),
                      isMine: false,
                    ),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'))
              ],
            ));
  }

  Widget _reports(List<WebAdminRecord> all) {
    final financial = WebAdminReportSummary.fromRecords(all);
    int count(String collection, [bool Function(WebAdminRecord)? where]) => all
        .where((item) =>
            item.collection == collection && (where == null || where(item)))
        .length;
    final totals = <String, int>{
      'Workers': count('users', (item) => item.data['role'] == 'worker'),
      'Employers': count('users', (item) => item.data['role'] == 'employer'),
      'Active vacancies': count(
          'jobs',
          (item) =>
              item.data['status'] == 'active' &&
              item.data['moderationStatus'] == 'approved'),
      'Pending vacancies': count(
          'jobs', (item) => item.data['moderationStatus'] == 'pending_review'),
      'Applications': count('applications'),
      'Support requests': count('support_requests'),
      'Reports': count('reports'),
      'Billing requests': count('payment_requests'),
      'Active workers': financial.activeWorkers,
      'Active employers': financial.activeEmployers,
      'Billable companies': financial.billableCompanies,
      'Direct Debit companies': financial.directDebitCompanies,
      'Pending payment requests': financial.pendingPaymentRequests,
    };
    return WebPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Reports'),
      const SizedBox(height: 16),
      LayoutBuilder(
          builder: (context, constraints) => Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  for (final entry in totals.entries)
                    SizedBox(
                      width: constraints.maxWidth < 520
                          ? constraints.maxWidth
                          : 220,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${entry.value}',
                                style: WebTypography.sectionTitle),
                            Text(entry.key, style: WebTypography.metadata),
                          ]),
                    )
                ],
              )),
      const SizedBox(height: 24),
      const Text('Financial reports', style: WebTypography.panelTitle),
      const SizedBox(height: 12),
      Wrap(spacing: 24, runSpacing: 12, children: [
        Text(
            'Expected monthly revenue: GBP ${financial.expectedMonthlyRevenue.toStringAsFixed(2)}'),
        Text(
            'Received this month: GBP ${financial.receivedMonthlyRevenue.toStringAsFixed(2)}'),
      ]),
      const SizedBox(height: 24),
      const Text('Monthly performance', style: WebTypography.panelTitle),
      const SizedBox(height: 8),
      Text('New users this month: ${financial.currentMonthUsers}'),
      Text('New users previous month: ${financial.previousMonthUsers}'),
    ]));
  }
}
