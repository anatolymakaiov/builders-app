import 'package:flutter/material.dart';
import '../../models/job.dart';
import '../services/web_jobs_data_service.dart';
import '../services/web_profile_data_service.dart';

Future<bool> showWebApplyDialog(BuildContext context,
    {required String userId, required Job job}) async {
  return await showDialog<bool>(
          context: context,
          builder: (_) => _ApplyDialog(userId: userId, job: job)) ??
      false;
}

class _ApplyDialog extends StatefulWidget {
  const _ApplyDialog({required this.userId, required this.job});
  final String userId;
  final Job job;
  @override
  State<_ApplyDialog> createState() => _ApplyDialogState();
}

class _ApplyDialogState extends State<_ApplyDialog> {
  final service = WebJobsDataService();
  late final teams = WebProfileDataService().loadWorkerTeams(widget.userId);
  String type = 'single';
  String? teamId;
  bool busy = false;
  String? error;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Apply: ${widget.job.displayTitle}'),
        content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'single',
                          label: Text('Worker'),
                          icon: Icon(Icons.person_outline)),
                      ButtonSegment(
                          value: 'team',
                          label: Text('Team'),
                          icon: Icon(Icons.groups_outlined)),
                    ],
                    selected: {
                      type
                    },
                    onSelectionChanged: busy
                        ? null
                        : (value) => setState(() => type = value.first)),
                if (type == 'team')
                  FutureBuilder<List<WebTeamData>>(
                      future: teams,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Text(
                              'Could not load your teams. Close and retry.');
                        }
                        if (!snapshot.hasData) {
                          return const LinearProgressIndicator();
                        }
                        final values = snapshot.data!;
                        if (values.isEmpty) {
                          return const Padding(
                              padding: EdgeInsets.all(12),
                              child:
                                  Text('You do not belong to an active team.'));
                        }
                        return DropdownButtonFormField<String>(
                          initialValue: teamId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Team'),
                          items: values
                              .map((team) => DropdownMenuItem(
                                  value: team.id,
                                  child: Text(
                                      '${team.name} (${team.members.length} members)',
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: busy
                              ? null
                              : (value) => setState(() => teamId = value),
                        );
                      }),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ],
            ))),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed:
                  busy || (type == 'team' && teamId == null) ? null : _submit,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Apply')),
        ],
      );

  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (type == 'team') {
        await service.applyAsTeam(
            userId: widget.userId, job: widget.job, teamId: teamId!);
      } else {
        await service.applyAsSingle(userId: widget.userId, job: widget.job);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().contains('already_applied')
            ? 'You already applied.'
            : e.toString());
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
