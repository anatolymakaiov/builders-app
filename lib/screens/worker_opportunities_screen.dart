import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/job.dart';
import '../services/vacancy_invitation_service.dart';
import 'job_details_screen.dart';

class WorkerOpportunitiesScreen extends StatefulWidget {
  const WorkerOpportunitiesScreen({super.key, required this.workerId});
  final String workerId;

  @override
  State<WorkerOpportunitiesScreen> createState() =>
      _WorkerOpportunitiesScreenState();
}

class _WorkerOpportunitiesScreenState extends State<WorkerOpportunitiesScreen> {
  final service = VacancyInvitationService();
  late Stream<List<VacancyInvitation>> invitations;
  String? busyId;

  @override
  void initState() {
    super.initState();
    invitations = service.watchMine(widget.workerId);
  }

  Future<void> _open(VacancyInvitation invitation) async {
    if (busyId != null) return;
    setState(() => busyId = invitation.id);
    try {
      final status = await service.respond(invitation.id, 'viewed');
      if (!mounted) return;
      if (status == 'vacancy_closed' || status == 'vacancy_filled') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This opportunity is no longer available.'),
        ));
        return;
      }
      final snapshot = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(invitation.vacancyId)
          .get();
      if (!mounted) return;
      if (!snapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Vacancy details are unavailable.'),
        ));
        return;
      }
      final job = Job.fromFirestore(snapshot.id, snapshot.data()!);
      await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobDetailScreen(job: job),
          ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open this opportunity.'),
        ));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not update this opportunity.'),
        ));
      }
    } finally {
      if (mounted) {
        setState(() => busyId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Opportunities')),
        body: StreamBuilder<List<VacancyInvitation>>(
          stream: invitations,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Could not load opportunities.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data!;
            if (items.isEmpty) {
              return const Center(child: Text('No vacancy invitations yet.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(item.company),
                        if (item.generalLocation.isNotEmpty)
                          Text(item.generalLocation),
                        const SizedBox(height: 4),
                        Text(item.statusLabel),
                        if (item.actionable)
                          Wrap(spacing: 8, children: [
                            FilledButton(
                                onPressed:
                                    busyId == null ? () => _open(item) : null,
                                child: const Text('View vacancy / Apply')),
                            TextButton(
                                onPressed: busyId == null
                                    ? () => _decline(item)
                                    : null,
                                child: const Text('Not interested')),
                          ]),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
}
