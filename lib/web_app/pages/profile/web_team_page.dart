import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/chat_service.dart';
import '../../services/web_profile_communication.dart';
import '../../services/web_profile_data_service.dart';
import '../../services/web_profile_edit_service.dart';
import '../../services/web_team_actions.dart';
import '../../theme/web_breakpoints.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_design_components.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_remote_image.dart';
import '../../widgets/web_report_dialog.dart';
import 'web_profile_gallery.dart';

class WebTeamPage extends StatefulWidget {
  const WebTeamPage({
    super.key,
    required this.teamId,
    required this.role,
    required this.onBack,
    required this.onProfile,
    required this.onChat,
  });

  final String teamId;
  final String role;
  final VoidCallback onBack;
  final void Function(String, String) onProfile;
  final ValueChanged<String> onChat;

  @override
  State<WebTeamPage> createState() => _WebTeamPageState();
}

class _WebTeamPageState extends State<WebTeamPage> {
  final service = WebProfileDataService();
  final actions = WebTeamActions();
  final editor = WebProfileEditService();
  late Future<WebTeamData?> future = service.loadTeam(widget.teamId);
  bool busy = false;

  @override
  void didUpdateWidget(covariant WebTeamPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId) {
      future = service.loadTeam(widget.teamId);
    }
  }

  Future<void> run(
    Future<void> Function() action, {
    String? confirmation,
    bool leave = false,
  }) async {
    if (busy) return;
    if (confirmation != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(confirmation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => busy = true);
    try {
      await action();
      if (!mounted) return;
      if (leave) {
        widget.onBack();
      } else {
        setState(() => future = service.loadTeam(widget.teamId));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WebTeamData?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const WebLoadingState(label: 'Loading team');
        }
        final team = snapshot.data;
        if (snapshot.hasError ||
            team == null ||
            WebProfileCommunication.unavailable(team.data)) {
          return WebErrorState(
            message: 'Team is no longer available.',
            onRetry: () =>
                setState(() => future = service.loadTeam(widget.teamId)),
          );
        }
        final leader = actions.leader(team.data);
        final member =
            WebTeamActions.memberIds(team.data).contains(actions.uid);
        final contactPhones = _contactPhones(team);
        return WebPageContainer(
          child: ListView(
            children: [
              _teamHeader(team),
              const SizedBox(height: WebSpacing.lg),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < WebBreakpoints.compactWidth;
                  final main = Column(
                    children: [
                      if (team.description.trim().isNotEmpty)
                        WebPanel(
                          child: _Section(
                            title: 'About the team',
                            child: Text(
                              team.description,
                              style: WebTypography.bodyLarge,
                            ),
                          ),
                        ),
                      if (team.description.trim().isNotEmpty)
                        const SizedBox(height: WebSpacing.lg),
                      WebPanel(
                        child: _members(team, leader),
                      ),
                      const SizedBox(height: WebSpacing.lg),
                      WebPanel(
                        child: _Section(
                          title: 'Photos',
                          action: leader
                              ? OutlinedButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => run(
                                            () => actions.addPhotos(team.id),
                                          ),
                                  icon: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                  ),
                                  label: const Text('Add photos'),
                                )
                              : null,
                          child: WebProfileGallery(urls: team.portfolio),
                        ),
                      ),
                    ],
                  );
                  final side = Column(
                    children: [
                      WebPanel(child: _actionsPanel(team, leader, member)),
                      const SizedBox(height: WebSpacing.lg),
                      WebPanel(child: _contacts(contactPhones)),
                    ],
                  );
                  if (compact) {
                    return Column(
                      children: [
                        side,
                        const SizedBox(height: WebSpacing.lg),
                        main,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: main),
                      const SizedBox(width: WebSpacing.lg),
                      Expanded(flex: 3, child: side),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Set<String> _contactPhones(WebTeamData team) {
    final phones = <String>{
      for (final key in const ['phone', 'contactPhone', 'teamPhone'])
        if ((team.data[key]?.toString().trim() ?? '').isNotEmpty)
          team.data[key].toString().trim(),
    };
    if (phones.isEmpty) {
      final profiles = team.members.where((item) => item.id == team.leaderId);
      if (profiles.isNotEmpty && profiles.first.phone.trim().isNotEmpty) {
        phones.add(profiles.first.phone.trim());
      }
    }
    return phones;
  }

  Widget _teamHeader(WebTeamData team) {
    return WebPanel(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 310,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (team.headerUrl.isNotEmpty)
              WebRemoteImage(url: team.headerUrl, fit: BoxFit.cover)
            else
              const ColoredBox(color: WebTheme.blueprint),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    WebTheme.deep.withValues(alpha: 0.08),
                    WebTheme.deep.withValues(alpha: 0.82),
                  ],
                ),
              ),
            ),
            Positioned(
              left: WebSpacing.lg,
              top: WebSpacing.lg,
              child: IconButton.filledTonal(
                tooltip: 'Back',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            Positioned(
              left: WebSpacing.xxl,
              right: WebSpacing.xxl,
              bottom: WebSpacing.xl,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  WebCircleImage(
                    url: team.avatarUrl,
                    size: 148,
                    fallbackIcon: Icons.groups_2_outlined,
                  ),
                  const SizedBox(width: WebSpacing.xl),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: WebSpacing.xs),
                        Text(
                          [
                            if (team.trade.trim().isNotEmpty) team.trade,
                            '${team.members.length} members',
                          ].join('  |  '),
                          style: WebTypography.bodyLarge.copyWith(
                            color: Colors.white.withValues(alpha: 0.86),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsPanel(WebTeamData team, bool leader, bool member) {
    return _Section(
      title: 'Team actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (leader) ...[
            OutlinedButton.icon(
              onPressed: busy ? null : () => _editDescription(team),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit description'),
            ),
            const SizedBox(height: WebSpacing.xs),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => run(() => editor.pickAndUploadTeamImage(
                        teamId: team.id,
                        header: false,
                      )),
              icon: const Icon(Icons.account_circle_outlined),
              label: const Text('Change avatar'),
            ),
            const SizedBox(height: WebSpacing.xs),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => run(() => editor.pickAndUploadTeamImage(
                        teamId: team.id,
                        header: true,
                      )),
              icon: const Icon(Icons.panorama_outlined),
              label: const Text('Change header'),
            ),
            const SizedBox(height: WebSpacing.xs),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _addWorker(team),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add worker'),
            ),
          ],
          if (widget.role == 'employer') ...[
            if (leader) const SizedBox(height: WebSpacing.xs),
            FilledButton.icon(
              onPressed: busy ? null : () => _messageTeam(team),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Message team'),
            ),
          ],
          if (member && !leader) ...[
            const SizedBox(height: WebSpacing.xs),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => run(
                        () => actions.changeMember(
                          team.id,
                          removeId: actions.uid,
                        ),
                        confirmation: 'Leave this team?',
                        leave: true,
                      ),
              icon: const Icon(Icons.logout),
              label: const Text('Leave team'),
            ),
          ],
          if (leader) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: WebSpacing.sm),
              child: Divider(height: 1),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: WebTheme.danger,
                side: const BorderSide(color: WebTheme.danger),
              ),
              onPressed: busy
                  ? null
                  : () => run(
                        () => actions.delete(team.id),
                        confirmation: 'Delete this team permanently?',
                        leave: true,
                      ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete Team'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contacts(Set<String> phones) {
    return _Section(
      title: 'Contacts',
      child: phones.isEmpty
          ? const Text(
              'No phone number available.',
              style: WebTypography.metadata,
            )
          : Column(
              children: [
                for (final phone in phones)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.phone_outlined),
                    title: Text(phone),
                    trailing: const Icon(Icons.open_in_new, size: 17),
                    onTap: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                  ),
              ],
            ),
    );
  }

  Widget _members(WebTeamData team, bool leader) {
    return _Section(
      title: 'Members',
      child: Column(
        children: [
          for (final person in team.members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: WebCircleImage(
                url: person.avatarUrl,
                size: 52,
                fallbackIcon: Icons.person_outline,
              ),
              title: Text(person.displayName),
              subtitle: Text(person.trade),
              onTap: () => widget.onProfile(person.id, 'worker'),
              trailing: leader && person.id != actions.uid
                  ? PopupMenuButton<String>(
                      tooltip: 'Member actions',
                      onSelected: (action) {
                        if (action == 'message') {
                          _messageWorker(person.id);
                        } else {
                          run(
                            () => actions.changeMember(
                              team.id,
                              removeId: person.id,
                            ),
                            confirmation:
                                'Are you sure you want to remove this worker from the team?',
                          );
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'message',
                          child: Text('Message'),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove from team'),
                        ),
                      ],
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  Future<void> _editDescription(WebTeamData team) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => WebTextDialog(
        title: 'Team description',
        label: 'Description',
        initial: team.description,
      ),
    );
    if (text != null && mounted) {
      await run(() => editor.saveTeam(
            teamId: team.id,
            updates: {'description': text},
          ));
    }
  }

  Future<void> _addWorker(WebTeamData team) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const WebTextDialog(
        title: 'Add worker',
        label: 'Phone or nickname',
      ),
    );
    if (text != null && mounted) {
      await run(() => actions.changeMember(team.id, search: text));
    }
  }

  Future<void> _messageTeam(WebTeamData team) async {
    await run(() async {
      final id = await ChatService.getOrCreateTeamChat(
        teamId: team.id,
        employerId: actions.uid,
        jobId: '',
        members: team.members.map((person) => person.id).toList(),
      );
      if (mounted) widget.onChat(id);
    });
  }

  Future<void> _messageWorker(String workerId) async {
    await run(() async {
      final id = await WebProfileCommunication().message(workerId);
      if (mounted) widget.onChat(id);
    });
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: WebTypography.sectionTitle)),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: WebSpacing.md),
        child,
      ],
    );
  }
}
