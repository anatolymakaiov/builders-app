import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/chat_service.dart';
import '../../services/web_team_actions.dart';
import '../../services/web_profile_data_service.dart';
import '../../services/web_profile_edit_service.dart';
import '../../services/web_profile_communication.dart';
import '../../widgets/web_remote_image.dart';
import '../../widgets/web_report_dialog.dart';
import 'web_profile_gallery.dart';

class WebTeamPage extends StatefulWidget {
  const WebTeamPage(
      {super.key,
      required this.teamId,
      required this.role,
      required this.onBack,
      required this.onProfile,
      required this.onChat});
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

  Future<void> run(Future<void> Function() action,
      {String? confirmation, bool leave = false}) async {
    if (busy) return;
    if (confirmation != null) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) =>
              AlertDialog(title: Text(confirmation), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Yes')),
              ]));
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
  Widget build(BuildContext context) => FutureBuilder<WebTeamData?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final team = snapshot.data;
        if (snapshot.hasError ||
            team == null ||
            WebProfileCommunication.unavailable(team.data)) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Team is no longer available.'),
            TextButton(onPressed: widget.onBack, child: const Text('Back')),
            TextButton(
                onPressed: () =>
                    setState(() => future = service.loadTeam(widget.teamId)),
                child: const Text('Retry')),
          ]));
        }
        final leader = actions.leader(team.data);
        final member =
            WebTeamActions.memberIds(team.data).contains(actions.uid);
        final contactPhones = <String>{
          for (final key in const ['phone', 'contactPhone', 'teamPhone'])
            if ((team.data[key]?.toString().trim() ?? '').isNotEmpty)
              team.data[key].toString().trim(),
        };
        if (contactPhones.isEmpty) {
          final leaderProfiles =
              team.members.where((profile) => profile.id == team.leaderId);
          if (leaderProfiles.isNotEmpty &&
              leaderProfiles.first.phone.trim().isNotEmpty) {
            contactPhones.add(leaderProfiles.first.phone.trim());
          }
        }
        return ListView(padding: const EdgeInsets.all(24), children: [
          Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back')),
          if (team.headerUrl.isNotEmpty)
            SizedBox(
                height: 180,
                child: WebRemoteImage(url: team.headerUrl, fit: BoxFit.cover)),
          ListTile(
              leading: WebCircleImage(
                  url: team.avatarUrl, size: 56, fallbackIcon: Icons.groups),
              title: Text(team.name),
              subtitle: Text(team.trade)),
          Text(team.description),
          Wrap(spacing: 8, children: [
            if (leader) ...[
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                            final text = await showDialog<String>(
                                context: context,
                                builder: (_) => WebTextDialog(
                                    title: 'Team description',
                                    label: 'Description',
                                    initial: team.description));
                            if (text != null) {
                              await editor.saveTeam(
                                  teamId: team.id,
                                  updates: {'description': text});
                            }
                          }),
                  child: const Text('Edit description')),
              IconButton(
                  tooltip: 'Change avatar',
                  onPressed: busy
                      ? null
                      : () => run(() async {
                            await editor.pickAndUploadTeamImage(
                                teamId: team.id, header: false);
                          }),
                  icon: const Icon(Icons.account_circle)),
              IconButton(
                  tooltip: 'Change header',
                  onPressed: busy
                      ? null
                      : () => run(() async {
                            await editor.pickAndUploadTeamImage(
                                teamId: team.id, header: true);
                          }),
                  icon: const Icon(Icons.panorama)),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                            final text = await showDialog<String>(
                                context: context,
                                builder: (_) => const WebTextDialog(
                                    title: 'Add worker',
                                    label: 'Phone or nickname'));
                            if (text != null) {
                              await actions.changeMember(team.id, search: text);
                            }
                          }),
                  child: const Text('Add worker')),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() => actions.delete(team.id),
                          confirmation: 'Delete this team permanently?',
                          leave: true),
                  child: const Text('Delete Team')),
            ],
            if (member && !leader)
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(
                          () => actions.changeMember(team.id,
                              removeId: actions.uid),
                          confirmation: 'Leave this team?',
                          leave: true),
                  child: const Text('Leave team')),
            if (widget.role == 'employer')
              OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                            final id = await ChatService.getOrCreateTeamChat(
                                teamId: team.id,
                                employerId: actions.uid,
                                jobId: '',
                                members:
                                    team.members.map((p) => p.id).toList());
                            if (mounted) widget.onChat(id);
                          }),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Message')),
          ]),
          const SizedBox(height: 16),
          Text('Contacts', style: Theme.of(context).textTheme.titleLarge),
          if (contactPhones.isEmpty) const Text('No phone number available.'),
          for (final phone in contactPhones)
            TextButton(
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                child: Text(phone)),
          const SizedBox(height: 16),
          Text('Members', style: Theme.of(context).textTheme.titleLarge),
          for (final person in team.members)
            ListTile(
                leading: WebCircleImage(
                    url: person.avatarUrl,
                    size: 40,
                    fallbackIcon: Icons.person_outline),
                title: Text(person.displayName),
                subtitle: Text(person.trade),
                onTap: () => widget.onProfile(person.id, 'worker'),
                trailing: leader && person.id != actions.uid
                    ? PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'message') {
                            run(() async {
                              final id = await WebProfileCommunication()
                                  .message(person.id);
                              if (mounted) widget.onChat(id);
                            });
                          } else {
                            run(
                                () => actions.changeMember(team.id,
                                    removeId: person.id),
                                confirmation:
                                    'Are you sure you want to remove this worker from the team?');
                          }
                        },
                        itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'message', child: Text('Message')),
                              PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remove from team'))
                            ])
                    : null),
          const SizedBox(height: 16),
          if (leader)
            Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => run(() => actions.addPhotos(team.id)),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Add photos'))),
          WebProfileGallery(urls: team.portfolio),
        ]);
      });
}
