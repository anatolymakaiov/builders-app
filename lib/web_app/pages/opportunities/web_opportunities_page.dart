import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../../services/vacancy_invitation_service.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_apply_dialog.dart';
import '../../widgets/web_page_container.dart';

class WebOpportunitiesPage extends StatefulWidget {
  const WebOpportunitiesPage(
      {super.key, required this.workerId, required this.onOpenJob});
  final String workerId;
  final ValueChanged<String> onOpenJob;

  @override
  State<WebOpportunitiesPage> createState() => _WebOpportunitiesPageState();
}

class _WebOpportunitiesPageState extends State<WebOpportunitiesPage> {
  final service = VacancyInvitationService();
  late Stream<List<VacancyInvitation>> stream;
  String? busyId;

  @override
  void initState() {
    super.initState();
    stream = service.watchMine(widget.workerId);
  }

  @override
  void didUpdateWidget(covariant WebOpportunitiesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workerId != widget.workerId) {
      stream = service.watchMine(widget.workerId);
      busyId = null;
    }
  }

  Future<Job?> _loadJob(VacancyInvitation invitation) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(invitation.vacancyId)
          .get();
      if (!snapshot.exists) return null;
      return Job.fromFirestore(snapshot.id, snapshot.data()!);
    } catch (_) {
      return null;
    }
  }

  Future<void> _open(VacancyInvitation invitation,
      {required bool apply}) async {
    if (busyId != null) return;
    setState(() => busyId = invitation.id);
    try {
      final status = await service.respond(invitation.id, 'viewed');
      if (!mounted) return;
      if (status == 'vacancy_closed' || status == 'vacancy_filled') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('This opportunity is no longer available.')),
        );
        return;
      }
      if (!apply) {
        widget.onOpenJob(invitation.vacancyId);
        return;
      }
      final job = await _loadJob(invitation);
      if (!mounted) return;
      if (job == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vacancy details are unavailable.')),
        );
        return;
      }
      await showWebApplyDialog(context, userId: widget.workerId, job: job);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this opportunity.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busyId = null);
      }
    }
  }

  Future<void> _decline(VacancyInvitation invitation) async {
    if (busyId != null) return;
    setState(() => busyId = invitation.id);
    try {
      await service.respond(invitation.id, 'not_interested');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this opportunity.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busyId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: WebPageContainer(
          topPadding: 18,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Opportunities',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            StreamBuilder<List<VacancyInvitation>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Could not load opportunities.');
                }
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return const Text('No vacancy invitations yet.');
                }
                return Column(children: [
                  for (final item in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title,
                                style: Theme.of(context).textTheme.titleMedium),
                            Text(item.company),
                            if (item.generalLocation.isNotEmpty)
                              Text(item.generalLocation),
                            const SizedBox(height: 6),
                            Text(item.statusLabel,
                                style: const TextStyle(color: WebTheme.accent)),
                            if (item.actionable)
                              Wrap(spacing: 8, children: [
                                OutlinedButton(
                                    onPressed: busyId == null
                                        ? () => _open(item, apply: false)
                                        : null,
                                    child: const Text('View vacancy')),
                                FilledButton(
                                    onPressed: busyId == null
                                        ? () => _open(item, apply: true)
                                        : null,
                                    child: const Text('Apply')),
                                TextButton(
                                    onPressed: busyId == null
                                        ? () => _decline(item)
                                        : null,
                                    child: const Text('Not interested')),
                              ]),
                          ],
                        ),
                      ),
                    ),
                ]);
              },
            ),
          ]),
        ),
      );
}
