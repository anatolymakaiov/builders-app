import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../../services/job_taxonomy_service.dart';
import '../../../services/vacancy_invitation_service.dart';
import '../../theme/web_theme.dart';
import '../../theme/web_breakpoints.dart';
import '../../widgets/web_apply_dialog.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_design_components.dart';
import '../../widgets/web_panel.dart';

class WebOpportunitiesPage extends StatefulWidget {
  const WebOpportunitiesPage(
      {super.key,
      required this.workerId,
      required this.onOpenJob,
      this.invitations,
      this.respondToInvitation,
      this.loadJob});
  final String workerId;
  final ValueChanged<String> onOpenJob;
  final Stream<List<VacancyInvitation>>? invitations;
  final Future<String> Function(VacancyInvitation invitation, String action)?
      respondToInvitation;
  final Future<Job?> Function(VacancyInvitation invitation)? loadJob;

  @override
  State<WebOpportunitiesPage> createState() => _WebOpportunitiesPageState();
}

class _WebOpportunitiesPageState extends State<WebOpportunitiesPage> {
  late final service = VacancyInvitationService();
  late Stream<List<VacancyInvitation>> stream;
  String? busyId;
  String? selectedId;
  bool compactDetailVisible = false;
  Future<Job?>? selectedJob;

  @override
  void initState() {
    super.initState();
    stream = widget.invitations ?? service.watchMine(widget.workerId);
  }

  @override
  void didUpdateWidget(covariant WebOpportunitiesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workerId != widget.workerId ||
        oldWidget.invitations != widget.invitations) {
      stream = widget.invitations ?? service.watchMine(widget.workerId);
      busyId = null;
      selectedId = null;
      selectedJob = null;
      compactDetailVisible = false;
    }
  }

  Future<Job?> _loadJob(VacancyInvitation invitation) async {
    if (widget.loadJob != null) return widget.loadJob!(invitation);
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

  void _select(VacancyInvitation invitation) {
    if (selectedId != invitation.id) {
      selectedJob =
          invitation.closed ? Future.value(null) : _loadJob(invitation);
    }
    setState(() {
      selectedId = invitation.id;
      compactDetailVisible = true;
    });
  }

  Future<void> _open(VacancyInvitation invitation,
      {required bool apply}) async {
    if (busyId != null) return;
    setState(() => busyId = invitation.id);
    try {
      final status =
          await (widget.respondToInvitation?.call(invitation, 'viewed') ??
              service.respond(invitation.id, 'viewed'));
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
      await (widget.respondToInvitation?.call(invitation, 'not_interested') ??
          service.respond(invitation.id, 'not_interested'));
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
  Widget build(BuildContext context) => StreamBuilder<List<VacancyInvitation>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load opportunities.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isNotEmpty &&
              (selectedId == null ||
                  items.every((item) => item.id != selectedId))) {
            selectedId = items.first.id;
            selectedJob =
                items.first.closed ? Future.value(null) : _loadJob(items.first);
            compactDetailVisible = false;
          }
          final selected =
              items.where((item) => item.id == selectedId).firstOrNull;
          return WebPageContainer(
            topPadding: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Opportunities',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                const Text('Vacancy invitations sent to you.'),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Expanded(
                    child: Center(child: Text('No vacancy invitations yet.')),
                  )
                else
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      final compact =
                          constraints.maxWidth < WebBreakpoints.compactWidth;
                      final list = WebPanel(
                        padding: EdgeInsets.zero,
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _OpportunityRow(
                              invitation: item,
                              selected: item.id == selectedId,
                              onTap: () => _select(item),
                            );
                          },
                        ),
                      );
                      final detail = WebPanel(
                        child: selected == null
                            ? const Center(
                                child: Text('Select an opportunity.'))
                            : _OpportunityDetail(
                                invitation: selected,
                                job: selectedJob,
                                busy: busyId != null,
                                onOpen: () => _open(selected, apply: false),
                                onApply: () => _open(selected, apply: true),
                                onDecline: () => _decline(selected),
                              ),
                      );
                      if (compact) {
                        return WebCompactDetailView(
                          showDetail: compactDetailVisible,
                          list: list,
                          detail: detail,
                          onBack: () =>
                              setState(() => compactDetailVisible = false),
                          backLabel: 'Back to opportunities',
                        );
                      }
                      return Row(children: [
                        SizedBox(
                          width: WebBreakpoints.masterPaneWidth(
                              constraints.maxWidth),
                          child: list,
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: detail),
                      ]);
                    }),
                  ),
              ],
            ),
          );
        },
      );
}

class _OpportunityRow extends StatelessWidget {
  const _OpportunityRow(
      {required this.invitation, required this.selected, required this.onTap});
  final VacancyInvitation invitation;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        selected: selected,
        onTap: onTap,
        title: Text(invitation.title,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(invitation.company),
          if (invitation.generalLocation.isNotEmpty)
            Text(invitation.generalLocation),
          if (invitation.createdAt != null)
            Text(
                'Received ${MaterialLocalizations.of(context).formatMediumDate(invitation.createdAt!.toLocal())}'),
        ]),
        trailing: Text(invitation.statusLabel,
            style: const TextStyle(color: WebTheme.accent)),
      );
}

class _OpportunityDetail extends StatelessWidget {
  const _OpportunityDetail(
      {required this.invitation,
      required this.job,
      required this.busy,
      required this.onOpen,
      required this.onApply,
      required this.onDecline});
  final VacancyInvitation invitation;
  final Future<Job?>? job;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onApply;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Text(invitation.title,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(invitation.company),
        const SizedBox(height: 12),
        _detail('Status', invitation.statusLabel),
        _detail(
            'Trade',
            JobTaxonomyService.roleFor(invitation.tradeId)?.canonical ??
                invitation.tradeId),
        _detail('Location', invitation.generalLocation),
        if (invitation.createdAt != null)
          _detail(
              'Received',
              MaterialLocalizations.of(context)
                  .formatMediumDate(invitation.createdAt!.toLocal())),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
              onPressed: busy ? null : onOpen,
              child: const Text('Open Vacancy')),
          if (invitation.actionable) ...[
            FilledButton(
                onPressed: busy ? null : onApply, child: const Text('Apply')),
            TextButton(
                onPressed: busy ? null : onDecline,
                child: const Text('Not interested')),
          ],
        ]),
        const SizedBox(height: 16),
        FutureBuilder<Job?>(
          future: job,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator());
            }
            final vacancy = snapshot.data;
            if (vacancy == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                    'Vacancy details are unavailable. The invitation summary remains visible.'),
              );
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detail('Site', vacancy.site),
                  _detail('Address', vacancy.location),
                  _detail('Rate', vacancy.rateText),
                  if (vacancy.startDate != null)
                    _detail(
                        'Start',
                        MaterialLocalizations.of(context)
                            .formatMediumDate(vacancy.startDate!.toLocal())),
                  _detail('Duration', vacancy.duration),
                  _detail('Weekly hours', vacancy.weeklyHours),
                  _detail('Description', vacancy.description),
                  _detail('Responsibilities', vacancy.responsibilities),
                  _detail('Requirements', vacancy.candidateRequirements),
                  _detail('Required documents', vacancy.requiredDocuments),
                  _detail(
                      'Additional information', vacancy.additionalInformation),
                ]);
          },
        ),
      ]);

  Widget _detail(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: WebTheme.muted, fontSize: 12)),
        Text(value),
      ]),
    );
  }
}
