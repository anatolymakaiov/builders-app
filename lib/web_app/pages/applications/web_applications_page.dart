import 'package:flutter/material.dart';

import '../../../services/application_activity_service.dart';
import '../../../services/application_status_utils.dart';
import '../../services/web_application_actions_service.dart';
import '../../services/web_applications_data_service.dart';
import '../../services/web_data_state.dart';
import '../../theme/web_breakpoints.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_remote_image.dart';

class WebApplicationsPage extends StatefulWidget {
  const WebApplicationsPage({
    super.key,
    required this.userId,
    required this.role,
    this.onOpenProfile,
    this.onOpenChat,
  });

  final String userId;
  final String role;
  final void Function(String userId, String role)? onOpenProfile;
  final ValueChanged<String>? onOpenChat;

  @override
  State<WebApplicationsPage> createState() => _WebApplicationsPageState();
}

class _WebApplicationsPageState extends State<WebApplicationsPage> {
  final service = WebApplicationsDataService();
  final actionsService = WebApplicationActionsService();
  late Stream<WebDataState<List<WebApplicationSummary>>> applicationsStream;
  String? selectedApplicationId;
  bool showTeamApplications = false;
  String statusFilter = ApplicationStatusUtils.allFilter;
  String searchFilter = '';
  String? lastReadKey;

  bool get isWorker => widget.role == 'worker';

  @override
  void initState() {
    super.initState();
    applicationsStream = service.applications(
      uid: widget.userId,
      role: widget.role,
    );
  }

  @override
  void didUpdateWidget(covariant WebApplicationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || oldWidget.role != widget.role) {
      applicationsStream = service.applications(
        uid: widget.userId,
        role: widget.role,
      );
      selectedApplicationId = null;
      showTeamApplications = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebDataState<List<WebApplicationSummary>>>(
      stream: applicationsStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || state.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        final loadedApplications =
            state.data ?? const <WebApplicationSummary>[];
        final applications = _filterApplications(isWorker
            ? loadedApplications
                .where((item) => item.isTeam == showTeamApplications)
                .toList()
            : loadedApplications);
        if (selectedApplicationId == null && applications.isNotEmpty) {
          selectedApplicationId = applications.first.id;
        }
        if (selectedApplicationId != null &&
            applications.every((item) => item.id != selectedApplicationId)) {
          selectedApplicationId =
              applications.isEmpty ? null : applications.first.id;
        }
        WebApplicationSummary? selected;
        for (final application in applications) {
          if (application.id == selectedApplicationId) {
            selected = application;
            break;
          }
        }
        _markSelectedRead(selected);

        return WebPageContainer(
          child: Column(
            children: [
              if (state.error != null)
                _ErrorBanner(
                  message: 'Could not refresh applications: ${state.error}',
                ),
              if (isWorker) ...[
                _WorkerApplicationToggle(
                  showTeamApplications: showTeamApplications,
                  singleCount:
                      loadedApplications.where((item) => !item.isTeam).length,
                  teamCount:
                      loadedApplications.where((item) => item.isTeam).length,
                  onChanged: (value) {
                    setState(() {
                      showTeamApplications = value;
                      selectedApplicationId = null;
                    });
                  },
                ),
                const SizedBox(height: 14),
              ],
              _ApplicationFilters(
                role: widget.role,
                statusFilter: statusFilter,
                searchFilter: searchFilter,
                onStatusChanged: (value) {
                  setState(() {
                    statusFilter = value;
                    selectedApplicationId = null;
                  });
                },
                onSearchChanged: (value) {
                  setState(() {
                    searchFilter = value;
                    selectedApplicationId = null;
                  });
                },
              ),
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < WebBreakpoints.compactWidth;
                    final list = WebPanel(
                      padding: EdgeInsets.zero,
                      child: _ApplicationList(
                        applications: applications,
                        selectedId: selectedApplicationId,
                        userId: widget.userId,
                        role: widget.role,
                        onSelected: (id) {
                          setState(() => selectedApplicationId = id);
                        },
                      ),
                    );
                    final detail = WebPanel(
                      child: _ApplicationDetail(
                        application: selected,
                        currentUserId: widget.userId,
                        role: widget.role,
                        actionService: actionsService,
                        onOpenProfile: widget.onOpenProfile,
                        onOpenChat: widget.onOpenChat,
                        onChanged: () => setState(() {}),
                      ),
                    );
                    if (compact) {
                      return Column(
                        children: [
                          SizedBox(height: 360, child: list),
                          const SizedBox(height: 18),
                          SizedBox(height: 620, child: detail),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(width: 390, child: list),
                        const SizedBox(width: 22),
                        Expanded(child: detail),
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

  List<WebApplicationSummary> _filterApplications(
    List<WebApplicationSummary> applications,
  ) {
    final query = searchFilter.trim().toLowerCase();
    return applications.where((item) {
      if (!ApplicationStatusUtils.isStatusInFilter(item.status, statusFilter)) {
        return false;
      }
      if (query.isEmpty) return true;
      return [
        item.title,
        item.jobTitle,
        item.companyName,
        item.trade,
        item.site,
        item.status,
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  void _markSelectedRead(WebApplicationSummary? application) {
    if (application == null) return;
    final activityKey =
        application.activityAt?.toDate().millisecondsSinceEpoch.toString() ??
            'none';
    final key = '${application.id}:$activityKey';
    if (lastReadKey == key) return;
    lastReadKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await actionsService.markReadOnce(application);
      if (widget.role == 'employer') {
        await actionsService.markViewedByEmployerOnce(application);
      }
    });
  }
}

class _ApplicationFilters extends StatelessWidget {
  const _ApplicationFilters({
    required this.role,
    required this.statusFilter,
    required this.searchFilter,
    required this.onStatusChanged,
    required this.onSearchChanged,
  });

  final String role;
  final String statusFilter;
  final String searchFilter;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    const filters = [
      ApplicationStatusUtils.allFilter,
      ApplicationStatusUtils.reviewFilter,
      ApplicationStatusUtils.negotiationFilter,
      ApplicationStatusUtils.offerFilter,
      ApplicationStatusUtils.hiredFilter,
      ApplicationStatusUtils.rejectedFilter,
      ApplicationStatusUtils.withdrawnFilter,
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            for (final filter in filters)
              ButtonSegment(
                value: filter,
                label: Text(_filterLabel(filter, role)),
              ),
          ],
          selected: {statusFilter},
          onSelectionChanged: (value) => onStatusChanged(value.first),
        ),
        SizedBox(
          width: 260,
          child: TextField(
            controller: TextEditingController(text: searchFilter)
              ..selection = TextSelection.collapsed(
                offset: searchFilter.length,
              ),
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Job, trade or site',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  String _filterLabel(String filter, String role) {
    switch (filter) {
      case ApplicationStatusUtils.reviewFilter:
        return 'In Review';
      case ApplicationStatusUtils.negotiationFilter:
        return 'Negotiation';
      case ApplicationStatusUtils.offerFilter:
        return 'Offers';
      case ApplicationStatusUtils.hiredFilter:
        return role == 'employer' ? 'Hired' : 'Accepted';
      case ApplicationStatusUtils.rejectedFilter:
        return 'Rejected';
      case ApplicationStatusUtils.withdrawnFilter:
        return 'Withdrawn';
      default:
        return 'All';
    }
  }
}

class _WorkerApplicationToggle extends StatelessWidget {
  const _WorkerApplicationToggle({
    required this.showTeamApplications,
    required this.singleCount,
    required this.teamCount,
    required this.onChanged,
  });

  final bool showTeamApplications;
  final int singleCount;
  final int teamCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: false,
            label: Text('Single ($singleCount)'),
            icon: const Icon(Icons.person_outline),
          ),
          ButtonSegment(
            value: true,
            label: Text('Team ($teamCount)'),
            icon: const Icon(Icons.groups_2_outlined),
          ),
        ],
        selected: {showTeamApplications},
        onSelectionChanged: (value) => onChanged(value.first),
      ),
    );
  }
}

class _ApplicationList extends StatelessWidget {
  const _ApplicationList({
    required this.applications,
    required this.selectedId,
    required this.userId,
    required this.role,
    required this.onSelected,
  });

  final List<WebApplicationSummary> applications;
  final String? selectedId;
  final String userId;
  final String role;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return const Center(child: Text('No applications yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: applications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final application = applications[index];
        final selected = application.id == selectedId;
        return InkWell(
          onTap: () => onSelected(application.id),
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
                  url: role == 'worker'
                      ? application.companyLogoUrl
                      : application.avatarUrl,
                  size: 44,
                  fallbackIcon: role == 'worker'
                      ? Icons.business_outlined
                      : application.isTeam
                          ? Icons.groups_2_outlined
                          : Icons.person_outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        application.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        application.jobTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: WebTheme.muted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (role == 'worker') application.companyName,
                          if (application.trade.isNotEmpty) application.trade,
                          if (application.site.isNotEmpty) application.site,
                          if (application.activityAt != null)
                            _formatDate(application.activityAt!.toDate()),
                        ].where((part) => part.trim().isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WebTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (application.unreadFor(userId)) ...[
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: WebTheme.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _StatusChip(status: application.status, role: role),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ApplicationDetail extends StatelessWidget {
  const _ApplicationDetail({
    required this.application,
    required this.currentUserId,
    required this.role,
    required this.actionService,
    this.onOpenProfile,
    this.onOpenChat,
    this.onChanged,
  });

  final WebApplicationSummary? application;
  final String currentUserId;
  final String role;
  final WebApplicationActionsService actionService;
  final void Function(String userId, String role)? onOpenProfile;
  final ValueChanged<String>? onOpenChat;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final item = application;
    if (item == null) {
      return const Center(child: Text('Select an application.'));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ApplicationHeader(
              item: item, role: role, currentUserId: currentUserId),
          const SizedBox(height: 18),
          _ApplicationActions(
            application: item,
            currentUserId: currentUserId,
            role: role,
            actionService: actionService,
            onOpenProfile: onOpenProfile,
            onOpenChat: onOpenChat,
            onChanged: onChanged,
          ),
          const SizedBox(height: 20),
          if (item.offer.isNotEmpty) ...[
            _OfferCard(application: item, role: role),
            const SizedBox(height: 20),
          ],
          _DetailSection(
            title: 'Application snapshot',
            children: [
              _InfoRow(label: 'Vacancy', value: item.jobTitle),
              if (role == 'worker')
                _InfoRow(label: 'Company', value: item.companyName),
              _InfoRow(label: 'Applicant', value: item.title),
              _InfoRow(label: 'Type', value: item.isTeam ? 'Team' : 'Single'),
              if (item.trade.isNotEmpty)
                _InfoRow(label: 'Trade', value: item.trade),
              if (item.site.isNotEmpty)
                _InfoRow(label: 'Site', value: item.site),
              if (item.message.isNotEmpty)
                _InfoRow(label: 'Application message', value: item.message),
              if (item.jobUnavailable)
                const _NoticeRow(
                  icon: Icons.info_outline,
                  text:
                      'Vacancy details are unavailable. Showing saved application data.',
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (item.isTeam)
            _DetailSection(
              title: 'Team',
              children: [
                if (item.teamId.isNotEmpty)
                  _InfoRow(label: 'Team ID', value: item.teamId),
                _InfoRow(
                  label: 'Workers',
                  value: item.workersCount <= 0
                      ? item.memberIds.length.toString()
                      : item.workersCount.toString(),
                ),
                if (item.memberIds.isNotEmpty) _MembersBlock(application: item),
              ],
            ),
          if (!item.isTeam && item.profileData != null)
            _DetailSection(
              title: role == 'employer' ? 'Worker details' : 'Company details',
              children: [
                _InfoRow(
                  label: 'Name',
                  value: item.title,
                ),
                _InfoRow(
                  label: 'Trade / role',
                  value: _firstText(
                    item.profileData,
                    const ['trade', 'position', 'registrationPosition'],
                    '',
                  ),
                ),
                _InfoRow(
                  label: 'Location',
                  value: _firstText(
                    item.profileData,
                    const ['location', 'city', 'town', 'postcode'],
                    '',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ApplicationHeader extends StatelessWidget {
  const _ApplicationHeader({
    required this.item,
    required this.role,
    required this.currentUserId,
  });

  final WebApplicationSummary item;
  final String role;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = role == 'worker' ? item.companyLogoUrl : item.avatarUrl;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WebCircleImage(
          url: avatarUrl,
          size: 72,
          fallbackIcon: role == 'worker'
              ? Icons.business_outlined
              : item.isTeam
                  ? Icons.groups_2_outlined
                  : Icons.person_outline,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                item.jobTitle,
                style: const TextStyle(
                  color: WebTheme.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (item.activityAt != null)
                    _MetaChip(
                      icon: Icons.schedule_outlined,
                      label:
                          'Updated ${_formatDate(item.activityAt!.toDate())}',
                    ),
                  if (item.unreadFor(currentUserId))
                    const _MetaChip(
                      icon: Icons.mark_email_unread_outlined,
                      label: 'Unread',
                    ),
                  if (item.jobUnavailable)
                    const _MetaChip(
                      icon: Icons.block_outlined,
                      label: 'Vacancy unavailable',
                    ),
                ],
              ),
            ],
          ),
        ),
        _StatusChip(status: item.status, role: role),
      ],
    );
  }
}

class _ApplicationActions extends StatefulWidget {
  const _ApplicationActions({
    required this.application,
    required this.currentUserId,
    required this.role,
    required this.actionService,
    this.onOpenProfile,
    this.onOpenChat,
    this.onChanged,
  });

  final WebApplicationSummary application;
  final String currentUserId;
  final String role;
  final WebApplicationActionsService actionService;
  final void Function(String userId, String role)? onOpenProfile;
  final ValueChanged<String>? onOpenChat;
  final VoidCallback? onChanged;

  @override
  State<_ApplicationActions> createState() => _ApplicationActionsState();
}

class _ApplicationActionsState extends State<_ApplicationActions> {
  String? running;

  WebApplicationSummary get application => widget.application;
  bool get busy => running != null;

  @override
  Widget build(BuildContext context) {
    final status = ApplicationStatusUtils.normalizeStatus(application.status);
    final actions = <Widget>[
      if (widget.role == 'employer' && application.workerId.isNotEmpty)
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () =>
                  widget.onOpenProfile?.call(application.workerId, 'worker'),
          icon: const Icon(Icons.person_outline),
          label: const Text('View worker profile'),
        ),
      if (widget.role == 'worker' && application.employerId.isNotEmpty)
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () => widget.onOpenProfile
                  ?.call(application.employerId, 'employer'),
          icon: const Icon(Icons.business_outlined),
          label: const Text('View company profile'),
        ),
      if (application.isTeam)
        OutlinedButton.icon(
          onPressed: busy ? null : () => _showTeamDetails(context),
          icon: const Icon(Icons.groups_2_outlined),
          label: const Text('Team details'),
        ),
      if (_canMessage(status))
        OutlinedButton.icon(
          onPressed: busy ? null : () => _run('message', _message),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Message'),
        ),
      if (widget.role == 'employer') ..._employerActions(status),
      if (widget.role == 'worker') ..._workerActions(status),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 10, runSpacing: 10, children: actions);
  }

  List<Widget> _employerActions(String status) {
    if (status == 'rejected') {
      return [
        _actionButton(
          keyName: 'reopen',
          icon: Icons.replay_outlined,
          label: 'Reopen Application',
          run: () => widget.actionService.setStatus(
            application: application,
            status: 'negotiation',
            unreadFor:
                ApplicationActivityService.workerRecipients(application.data),
          ),
        ),
      ];
    }
    if (status == 'pending' ||
        status == 'negotiation' ||
        status == 'offer_withdrawn' ||
        status == 'offer_rejected') {
      return [
        if (status != 'negotiation')
          _actionButton(
            keyName: 'negotiation',
            icon: Icons.forum_outlined,
            label: 'Message / Negotiation',
            run: () async {
              await widget.actionService.setStatus(
                application: application,
                status: 'negotiation',
                unreadFor: ApplicationActivityService.workerRecipients(
                    application.data),
              );
              await _message();
            },
          ),
        _actionButton(
          keyName: 'offer',
          icon: Icons.local_offer_outlined,
          label: 'Make Offer',
          run: _makeOffer,
        ),
        _actionButton(
          keyName: 'reject',
          icon: Icons.close,
          label: 'Reject',
          danger: true,
          confirm: 'Reject this application?',
          run: () => widget.actionService.setStatus(
            application: application,
            status: 'rejected',
            unreadFor:
                ApplicationActivityService.workerRecipients(application.data),
          ),
        ),
      ];
    }
    if (status == 'offer_sent') {
      return [
        _actionButton(
          keyName: 'withdraw_offer',
          icon: Icons.undo,
          label: 'Withdraw Offer',
          danger: true,
          confirm: 'Withdraw this offer?',
          run: () => widget.actionService.setStatus(
            application: application,
            status: 'offer_withdrawn',
            unreadFor:
                ApplicationActivityService.workerRecipients(application.data),
          ),
        ),
      ];
    }
    return const <Widget>[];
  }

  List<Widget> _workerActions(String status) {
    if (status == 'pending') {
      return [
        _actionButton(
          keyName: 'withdraw',
          icon: Icons.undo,
          label: 'Withdraw Application',
          confirm: 'Withdraw this application?',
          run: () => widget.actionService.withdrawApplication(application),
        ),
      ];
    }
    if (status == 'offer_sent' && _canCurrentWorkerActOnOffer()) {
      return [
        _actionButton(
          keyName: 'accept',
          icon: Icons.check_circle_outline,
          label: 'Accept Offer',
          run: () => widget.actionService.acceptOffer(application),
        ),
        _actionButton(
          keyName: 'reject_offer',
          icon: Icons.cancel_outlined,
          label: 'Reject Offer',
          danger: true,
          confirm: 'Reject this offer?',
          run: () => widget.actionService.rejectOffer(application),
        ),
      ];
    }
    return const <Widget>[];
  }

  Widget _actionButton({
    required String keyName,
    required IconData icon,
    required String label,
    required Future<dynamic> Function() run,
    bool danger = false,
    String? confirm,
  }) {
    final content = running == keyName
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon);
    final onPressed = busy
        ? null
        : () async {
            if (confirm != null && !await _confirm(confirm)) return;
            await _run(keyName, run);
          };
    if (danger) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: content,
        label: Text(label),
        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: content,
      label: Text(label),
    );
  }

  bool _canMessage(String status) {
    return status == 'negotiation' ||
        status == 'offer_sent' ||
        status == 'offer_accepted' ||
        status == 'offer_rejected' ||
        status == 'offer_withdrawn' ||
        status == 'rejected' ||
        status == 'withdrawn';
  }

  bool _canCurrentWorkerActOnOffer() {
    final selected = application.selectedWorkerIds;
    return selected.isEmpty || selected.contains(widget.currentUserId);
  }

  Future<void> _makeOffer() async {
    final selected = application.isTeam
        ? await showDialog<List<String>>(
            context: context,
            builder: (_) =>
                _TeamWorkerSelectionDialog(application: application),
          )
        : const <String>[];
    if (application.isTeam && (selected == null || selected.isEmpty)) return;
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _WebMakeOfferDialog(application: application),
    );
    if (result == null) return;
    final selectedIds = selected ?? const <String>[];
    await widget.actionService.sendOffer(
      application: application,
      result: result,
      selectedWorkerIds: selectedIds,
      selectedWorkerNames: selectedIds.map(application.memberName).toList(),
    );
  }

  Future<void> _message() async {
    final chatId = await widget.actionService.chatIdForApplication(application);
    if (chatId == null) throw StateError('Chat is unavailable.');
    widget.onOpenChat?.call(chatId);
  }

  Future<void> _run(String key, Future<dynamic> Function() action) async {
    if (busy) return;
    setState(() => running = key);
    try {
      await action();
      widget.onChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application updated')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update application: $error')),
      );
    } finally {
      if (mounted) setState(() => running = null);
    }
  }

  Future<bool> _confirm(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm action'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showTeamDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(application.title),
        content: SizedBox(
          width: 520,
          child: _MembersBlock(application: application),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.role});

  final String status;
  final String role;

  @override
  Widget build(BuildContext context) {
    final normalized = ApplicationStatusUtils.normalizeStatus(status);
    final color = switch (normalized) {
      'pending' => const Color(0xFF2563EB),
      'negotiation' => const Color(0xFF7C3AED),
      'offer_sent' => const Color(0xFFB45309),
      'offer_accepted' => const Color(0xFF217A42),
      'offer_rejected' || 'offer_withdrawn' || 'withdrawn' => WebTheme.muted,
      'rejected' => Colors.red,
      _ => WebTheme.green,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        ApplicationStatusUtils.getStatusDisplayLabel(status, role),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.application, required this.role});

  final WebApplicationSummary application;
  final String role;

  @override
  Widget build(BuildContext context) {
    final offer = application.offer;
    final rows = <MapEntry<String, String>>[
      MapEntry('Work format',
          _firstText(offer, const ['workFormat', 'jobType'], '')),
      MapEntry('Rate / price', _firstText(offer, const ['rate'], '')),
      MapEntry('Work period', _firstText(offer, const ['workPeriod'], '')),
      MapEntry('Hours per week', _firstText(offer, const ['weeklyHours'], '')),
      MapEntry('Schedule', _firstText(offer, const ['schedule'], '')),
      MapEntry('Start date',
          _firstText(offer, const ['startDateTime', 'startDate'], '')),
      MapEntry(
        'Site address',
        _firstText(offer, const ['siteAddress', 'fullAddress'], ''),
      ),
      MapEntry(
        'Required on first day',
        _firstText(offer, const ['firstDayRequirements'], ''),
      ),
      MapEntry('Description',
          _firstText(offer, const ['description', 'message'], '')),
      MapEntry('Valid until', _firstText(offer, const ['validUntil'], '')),
    ].where((row) => row.value.trim().isNotEmpty).toList();
    return _DetailSection(
      title: role == 'worker' ? 'Offer' : 'Offer details',
      children: [
        _StatusChip(status: application.status, role: role),
        const SizedBox(height: 12),
        if (application.selectedWorkerIds.isNotEmpty)
          _InfoRow(
            label: 'Selected workers',
            value: application.selectedWorkerNames.isNotEmpty
                ? application.selectedWorkerNames.join(', ')
                : application.selectedWorkerIds
                    .map(application.memberName)
                    .join(', '),
          ),
        for (final row in rows) _InfoRow(label: row.key, value: row.value),
      ],
    );
  }
}

class _MembersBlock extends StatelessWidget {
  const _MembersBlock({required this.application});

  final WebApplicationSummary application;

  @override
  Widget build(BuildContext context) {
    final ids = application.memberIds;
    if (ids.isEmpty) {
      return const Text('No team members are listed.');
    }
    final selected = application.selectedWorkerIds.toSet();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: ids.map((id) {
        final profile = application.memberProfiles[id];
        final selectedForOffer = selected.contains(id);
        return Chip(
          avatar: WebCircleImage(
            url: _firstText(
              profile,
              const ['avatarUrl', 'photoUrl', 'profilePhotoUrl', 'photo'],
              '',
            ),
            size: 28,
            fallbackIcon: Icons.person_outline,
          ),
          label: Text(
            selectedForOffer
                ? '${application.memberName(id)} · selected'
                : application.memberName(id),
          ),
        );
      }).toList(),
    );
  }
}

class _TeamWorkerSelectionDialog extends StatefulWidget {
  const _TeamWorkerSelectionDialog({required this.application});

  final WebApplicationSummary application;

  @override
  State<_TeamWorkerSelectionDialog> createState() =>
      _TeamWorkerSelectionDialogState();
}

class _TeamWorkerSelectionDialogState
    extends State<_TeamWorkerSelectionDialog> {
  late Set<String> selected;

  @override
  void initState() {
    super.initState();
    selected = widget.application.memberIds.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.application.memberIds;
    return AlertDialog(
      title: const Text('Select workers'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              value: selected.length == ids.length && ids.isNotEmpty,
              onChanged: (_) {
                setState(() {
                  selected =
                      selected.length == ids.length ? <String>{} : ids.toSet();
                });
              },
              title: const Text('Select all'),
            ),
            const Divider(),
            for (final id in ids)
              CheckboxListTile(
                value: selected.contains(id),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      selected.add(id);
                    } else {
                      selected.remove(id);
                    }
                  });
                },
                title: Text(widget.application.memberName(id)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(selected.toList()),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _WebMakeOfferDialog extends StatefulWidget {
  const _WebMakeOfferDialog({required this.application});

  final WebApplicationSummary application;

  @override
  State<_WebMakeOfferDialog> createState() => _WebMakeOfferDialogState();
}

class _WebMakeOfferDialogState extends State<_WebMakeOfferDialog> {
  String jobType = 'hourly';
  final rate = TextEditingController();
  final workPeriod = TextEditingController();
  final weeklyHours = TextEditingController();
  final schedule = TextEditingController();
  final startDateTime = TextEditingController();
  final siteAddress = TextEditingController();
  final siteLine2 = TextEditingController();
  final siteLine3 = TextEditingController();
  final siteCity = TextEditingController();
  final siteCounty = TextEditingController();
  final sitePostcode = TextEditingController();
  final siteCountry = TextEditingController(text: 'United Kingdom');
  final firstDayRequirements = TextEditingController();
  final description = TextEditingController();
  final validUntil = TextEditingController();

  @override
  void initState() {
    super.initState();
    final data = widget.application.data;
    siteAddress.text = _firstText(
      data,
      const ['siteStreet', 'siteAddressLine1', 'siteAddress', 'fullAddress'],
      '',
    );
    siteLine2.text = _firstText(data, const ['siteAddressLine2'], '');
    siteLine3.text = _firstText(data, const ['siteAddressLine3'], '');
    siteCity.text = _firstText(data, const ['siteCity', 'city', 'town'], '');
    siteCounty.text = _firstText(data, const ['siteCounty', 'county'], '');
    sitePostcode.text =
        _firstText(data, const ['sitePostcode', 'postcode'], '');
    siteCountry.text =
        _firstText(data, const ['siteCountry', 'country'], 'United Kingdom');
  }

  @override
  void dispose() {
    for (final controller in [
      rate,
      workPeriod,
      weeklyHours,
      schedule,
      startDateTime,
      siteAddress,
      siteLine2,
      siteLine3,
      siteCity,
      siteCounty,
      sitePostcode,
      siteCountry,
      firstDayRequirements,
      description,
      validUntil,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Make offer'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 350,
                child: DropdownButtonFormField<String>(
                  initialValue: jobType,
                  decoration: const InputDecoration(
                    labelText: 'Work format',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'hourly', child: Text('Daywork')),
                    DropdownMenuItem(value: 'price', child: Text('Price')),
                    DropdownMenuItem(
                      value: 'negotiable',
                      child: Text('Negotiable'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => jobType = value);
                  },
                ),
              ),
              _input(rate, jobType == 'price' ? 'Price (£)' : 'Rate (£)'),
              _input(workPeriod, 'Work period'),
              _input(weeklyHours, 'Hours per week'),
              _input(schedule, 'Work schedule'),
              _input(startDateTime, 'Start date and time'),
              _input(siteAddress, 'Site Address Line 1'),
              _input(siteLine2, 'Site Address Line 2'),
              _input(siteLine3, 'Site Address Line 3'),
              _input(siteCity, 'Town / City'),
              _input(siteCounty, 'County'),
              _input(sitePostcode, 'Postcode'),
              _input(siteCountry, 'Country'),
              _input(firstDayRequirements, 'Required on first day', width: 350),
              _input(description, 'Offer description', width: 712, lines: 3),
              _input(validUntil, 'Offer valid until'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Send offer'),
        ),
      ],
    );
  }

  Widget _input(
    TextEditingController controller,
    String label, {
    double width = 350,
    int lines = 1,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  void _submit() {
    if (startDateTime.text.trim().isEmpty ||
        siteAddress.text.trim().isEmpty ||
        siteCity.text.trim().isEmpty ||
        siteCountry.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Start date, site address, city and country are required.'),
        ),
      );
      return;
    }
    final address = [
      siteAddress.text.trim(),
      siteLine2.text.trim(),
      siteLine3.text.trim(),
      siteCity.text.trim(),
      siteCounty.text.trim(),
      sitePostcode.text.trim(),
      siteCountry.text.trim(),
    ].where((part) => part.isNotEmpty).join(', ');
    Navigator.of(context).pop({
      'jobType': jobType,
      'rate': rate.text.trim(),
      'workPeriod': workPeriod.text.trim(),
      'weeklyHours': weeklyHours.text.trim(),
      'schedule': schedule.text.trim(),
      'startDateTime': startDateTime.text.trim(),
      'siteStreet': siteAddress.text.trim(),
      'siteAddressLine1': siteAddress.text.trim(),
      'siteAddressLine2': siteLine2.text.trim(),
      'siteAddressLine3': siteLine3.text.trim(),
      'siteCity': siteCity.text.trim(),
      'sitePostcode': sitePostcode.text.trim(),
      'siteCounty': siteCounty.text.trim(),
      'siteCountry': siteCountry.text.trim(),
      'siteAddress': address,
      'firstDayRequirements': firstDayRequirements.text.trim(),
      'description': description.text.trim(),
      'validUntil': validUntil.text.trim(),
    });
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: WebTheme.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15, height: 1.35)),
        ],
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: WebTheme.muted, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(color: WebTheme.muted)),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WebTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: WebTheme.muted),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _firstText(
  Map<String, dynamic>? data,
  List<String> keys,
  String fallback,
) {
  if (data == null) return fallback;
  for (final key in keys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return fallback;
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
