import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../../services/job_taxonomy_service.dart';
import '../../../services/vacancy_invitation_service.dart';
import '../jobs/web_job_display.dart';
import '../jobs/web_worker_vacancy_card.dart';
import '../../services/web_jobs_data_service.dart';
import '../../services/web_company_branding.dart';
import '../../services/web_profile_data_service.dart';
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
      this.loadWorkerFirstName,
      this.invitations,
      this.respondToInvitation,
      this.loadJob});
  final String workerId;
  final ValueChanged<String> onOpenJob;
  final Future<String?> Function(String workerId)? loadWorkerFirstName;
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
  final Map<String, Future<String?>> recipientFirstNames = {};
  final Map<String, Future<Job?>> jobCache = {};

  @override
  void initState() {
    super.initState();
    stream = widget.invitations ?? service.watchMine(widget.workerId);
  }

  Future<String?> _loadWorkerFirstName(String workerId) async {
    if (widget.loadWorkerFirstName != null) {
      return widget.loadWorkerFirstName!(workerId);
    }
    try {
      final profile = await WebProfileDataService().loadProfile(workerId);
      if (profile == null) throw StateError('Recipient profile is unavailable');
      return profile.firstName;
    } catch (error) {
      debugPrint(
          'WEB OPPORTUNITY RECIPIENT PROFILE LOAD ERROR: ${error.runtimeType}');
      rethrow;
    }
  }

  Future<String?> _firstNameFor(VacancyInvitation invitation) =>
      recipientFirstNames.putIfAbsent(
          invitation.workerId, () => _loadWorkerFirstName(invitation.workerId));

  @override
  void didUpdateWidget(covariant WebOpportunitiesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workerId != widget.workerId ||
        oldWidget.invitations != widget.invitations ||
        oldWidget.loadWorkerFirstName != widget.loadWorkerFirstName) {
      stream = widget.invitations ?? service.watchMine(widget.workerId);
      recipientFirstNames.clear();
      busyId = null;
      selectedId = null;
      selectedJob = null;
      jobCache.clear();
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
      final jobs = [
        Job.fromFirestore(
            snapshot.id, webJobWithoutSnapshotBranding(snapshot.data()!))
      ];
      await WebJobsDataService().enrichCompanyIdentity(jobs);
      return jobs.single;
    } catch (_) {
      return null;
    }
  }

  Future<Job?> _jobFor(VacancyInvitation invitation) => jobCache.putIfAbsent(
      invitation.vacancyId.isEmpty ? invitation.id : invitation.vacancyId,
      () => _loadJob(invitation));

  void _select(VacancyInvitation invitation) {
    if (selectedId != invitation.id) {
      selectedJob = _jobFor(invitation);
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
      final job = selectedId == invitation.id && selectedJob != null
          ? await selectedJob
          : await _jobFor(invitation);
      if (!mounted) return;
      if (job == null || invitation.closed || invitation.vacancyId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vacancy details are unavailable.')),
        );
        return;
      }
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
            selectedJob = _jobFor(items.first);
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
                      final compact = constraints.maxWidth < 740;
                      final list = WebPanel(
                        padding: EdgeInsets.zero,
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _OpportunityRow(
                              invitation: item,
                              job: _jobFor(item),
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
                                recipientFirstName:
                                    selected.message?.trim().isNotEmpty ?? false
                                        ? Future.value(null)
                                        : _firstNameFor(selected),
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
                          width: constraints.maxWidth < WebBreakpoints.desktop
                              ? 300
                              : WebBreakpoints.masterPaneWidth(
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
      {required this.invitation,
      required this.job,
      required this.selected,
      required this.onTap});
  final VacancyInvitation invitation;
  final Future<Job?> job;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final trade = JobTaxonomyService.roleFor(invitation.tradeId)?.canonical ??
        invitation.tradeId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: FutureBuilder<Job?>(
        future: job,
        builder: (context, snapshot) {
          final vacancy = snapshot.data;
          if (vacancy != null) {
            final trade =
                JobTaxonomyService.roleFor(invitation.tradeId)?.canonical ??
                    vacancy.trade;
            return WebWorkerVacancyCard(
              key: ValueKey('opportunity:${invitation.id}'),
              job: vacancy,
              titleOverride:
                  trade.trim().isEmpty ? vacancy.displayTitle : trade,
              selected: selected,
              saved: false,
              compact: true,
              showApplicationStatus: false,
              onTap: onTap,
            );
          }
          return InkWell(
            key: ValueKey('opportunity:${invitation.id}'),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? WebTheme.accentSoft : WebTheme.surface,
                borderRadius: BorderRadius.circular(WebRadii.card),
                border: Border.all(
                  color: selected ? WebTheme.accent : WebTheme.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trade.trim().isEmpty ? invitation.title : trade,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: WebTheme.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(invitation.company,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: WebTheme.muted)),
                  if (invitation.generalLocation.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(invitation.generalLocation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: WebTheme.muted)),
                  ],
                  const SizedBox(height: 7),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    Text(invitation.statusLabel,
                        style: const TextStyle(
                            color: WebTheme.accent,
                            fontWeight: FontWeight.w700)),
                    if (invitation.createdAt != null)
                      Text(
                        'Received ${MaterialLocalizations.of(context).formatMediumDate(invitation.createdAt!.toLocal())}',
                        style: const TextStyle(
                            color: WebTheme.subtleText, fontSize: 12),
                      ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String webOpportunityInvitationText(VacancyInvitation invitation,
    {String? firstName}) {
  final saved = invitation.message;
  if (saved != null && saved.trim().isNotEmpty) return saved;
  final first = firstName?.trim() ?? '';
  if (first.isEmpty ||
      const {'worker', 'user', 'unknown', 'null', 'undefined'}
          .contains(first.toLowerCase())) {
    return "Hi,\n\nI'd like to invite you to consider this vacancy.";
  }
  return "Hi $first,\n\nI'd like to invite you to consider this vacancy.";
}

class _OpportunityDetail extends StatelessWidget {
  const _OpportunityDetail(
      {required this.invitation,
      required this.job,
      required this.recipientFirstName,
      required this.busy,
      required this.onOpen,
      required this.onApply,
      required this.onDecline});
  final VacancyInvitation invitation;
  final Future<Job?>? job;
  final Future<String?> recipientFirstName;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onApply;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) => FutureBuilder<Job?>(
        future: job,
        builder: (context, snapshot) {
          final loaded = snapshot.connectionState == ConnectionState.done;
          final vacancy = snapshot.data;
          final canOpen = !busy &&
              !invitation.closed &&
              invitation.vacancyId.isNotEmpty &&
              vacancy != null;
          return ListView(children: [
            Text('Invitation', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (invitation.message?.trim().isNotEmpty ?? false)
              Text(invitation.message!)
            else
              FutureBuilder<String?>(
                future: recipientFirstName,
                builder: (context, name) {
                  if (name.hasError) {
                    return const Text('Could not load recipient name.');
                  }
                  if (name.connectionState != ConnectionState.done) {
                    return const Text('Loading invitation...');
                  }
                  return Text(webOpportunityInvitationText(
                    invitation,
                    firstName: name.data,
                  ));
                },
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: canOpen ? onOpen : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Vacancy'),
              ),
            ),
            if (!loaded && !invitation.closed)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (loaded && vacancy == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    invitation.closed
                        ? 'This opportunity is no longer available.'
                        : 'Vacancy details are unavailable.',
                    style: const TextStyle(color: WebTheme.muted)),
              ),
            const SizedBox(height: 20),
            Text('Opportunity Summary',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (invitation.createdAt != null)
              _detail(
                  context,
                  'Received',
                  '${MaterialLocalizations.of(context).formatMediumDate(invitation.createdAt!.toLocal())}, '
                      '${TimeOfDay.fromDateTime(invitation.createdAt!.toLocal()).format(context)}'),
            _detail(
                context, 'Company', vacancy?.companyName ?? invitation.company),
            _detail(
                context,
                'Trade',
                JobTaxonomyService.roleFor(invitation.tradeId)?.canonical ??
                    invitation.tradeId),
            _detail(context, 'Address',
                vacancy?.fullAddress ?? invitation.generalLocation),
            if (vacancy != null) ...[
              _detail(context, 'Pay', webJobRate(vacancy) ?? ''),
              if (vacancy.startDate != null)
                _detail(
                    context,
                    'Start',
                    MaterialLocalizations.of(context)
                        .formatMediumDate(vacancy.startDate!.toLocal())),
              _detail(
                  context,
                  'Working hours',
                  vacancy.weeklyHours.trim().isEmpty
                      ? ''
                      : '${vacancy.weeklyHours} hours/week'),
              _detail(context, 'Duration', vacancy.duration),
            ],
            _detail(context, 'Status', invitation.statusLabel),
            if (invitation.actionable) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton(
                    onPressed: canOpen ? onApply : null,
                    child: const Text('Apply')),
                TextButton(
                    onPressed: busy ? null : onDecline,
                    child: const Text('Not interested')),
              ]),
            ],
          ]);
        },
      );

  Widget _detail(BuildContext context, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: WebTheme.muted, fontSize: 12)),
        Text(value),
      ]),
    );
  }
}
