import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../services/job_taxonomy_service.dart';
import '../../../models/job.dart';
import '../../../services/vacancy_invitation_service.dart';
import '../../../services/worker_availability_service.dart';
import '../../services/web_talent_service.dart';
import '../../services/web_employer_entitlements_service.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_remote_image.dart';
import '../../services/workforce_talent_request.dart';

class TalentInviteChoice {
  const TalentInviteChoice(this.job, this.allowRelevanceMismatch);
  final Job job;
  final bool allowRelevanceMismatch;
}

class TalentInviteAssessment {
  const TalentInviteAssessment(this.hardBlock, this.warnings);
  final String? hardBlock;
  final List<String> warnings;
  bool get recommended => hardBlock == null && warnings.isEmpty;
}

TalentInviteAssessment assessTalentInvite(
    Iterable<WebTalentCandidate> workers, Job job, DateTime now) {
  final warnings = <String>{};
  for (final worker in workers) {
    if (!worker.allowsInvites) {
      return const TalentInviteAssessment('Vacancy invitations disabled', []);
    }
    if (worker.confirmedAt == null ||
        worker.availability == WorkerAvailability.unknown ||
        worker.availability == WorkerAvailability.notLooking) {
      return const TalentInviteAssessment(
          'Worker is not open to invitations', []);
    }
    final roleId = JobTaxonomyService.roleFor(job.canonicalRoleId)?.id ??
        JobTaxonomyService.bestRoleFor(job.trade)?.id;
    if (roleId == null || !worker.tradeIds.contains(roleId)) {
      warnings.add('Trade does not match candidate profile');
    }
    if (!worker.isRecentlyConfirmed(now)) {
      warnings.add('Availability not recently confirmed');
    }
    if (!worker.availableBy(job.startDate ?? now, now)) {
      warnings.add('Worker may not be available by vacancy start');
    }
  }
  return TalentInviteAssessment(null, warnings.toList());
}

class WebTalentPage extends StatefulWidget {
  const WebTalentPage(
      {super.key,
      required this.employerId,
      this.onOpenBilling,
      this.workforceRequest,
      this.navigationRequestId = 0});

  final String employerId;
  final VoidCallback? onOpenBilling;
  final WorkforceTalentRequest? workforceRequest;
  final int navigationRequestId;

  @override
  State<WebTalentPage> createState() => _WebTalentPageState();
}

class _WebTalentPageState extends State<WebTalentPage> {
  final service = WebTalentService();
  final tradeController = TextEditingController();
  final nameController = TextEditingController();
  final locationController = TextEditingController();
  Set<String> saved = {};
  final Set<String> selectedWorkerIds = {};
  final invitationService = VacancyInvitationService();
  final entitlementService = WebEmployerEntitlementsService();
  Timer? entitlementRefresh;
  WebEmployerEntitlements? entitlements;
  bool entitlementFailed = false;
  bool inviting = false;
  bool poolMode = false;
  bool loading = false;
  bool hasMore = false;
  bool searched = false;
  bool invitesOnly = false;
  WorkerAvailability? availability;
  DateTime? availableBy;
  WebTalentFilters? filters;
  String? error;
  String? selectedId;
  List<WebTalentCandidate> candidates = [];
  QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
  int requestId = 0;
  bool prefillNeedsSearch = false;

  @override
  void initState() {
    super.initState();
    _applyWorkforceRequest();
    _loadEntitlements();
    entitlementRefresh =
        Timer.periodic(const Duration(minutes: 1), (_) => _loadEntitlements());
  }

  Future<void> _loadEntitlements() async {
    final uid = widget.employerId;
    try {
      final value = await entitlementService.load();
      if (mounted && uid == widget.employerId) {
        setState(() {
          entitlements = value;
          entitlementFailed = false;
          if (poolMode ? !value.talentPool : !value.candidateSearch) {
            candidates = [];
            selectedWorkerIds.clear();
            selectedId = null;
            requestId++;
          }
        });
        if (prefillNeedsSearch && value.candidateSearch) {
          prefillNeedsSearch = false;
          unawaited(_search());
        }
      }
    } catch (_) {
      if (mounted && uid == widget.employerId) {
        setState(() => entitlementFailed = true);
      }
    }
  }

  @override
  void didUpdateWidget(covariant WebTalentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employerId != widget.employerId) {
      saved = {};
      availableBy = null;
      selectedWorkerIds.clear();
      nameController.clear();
      candidates = [];
      cursor = null;
      selectedId = null;
      searched = false;
      loading = false;
      requestId++;
      entitlements = null;
      entitlementFailed = false;
      _applyWorkforceRequest();
      _loadEntitlements();
    } else if (oldWidget.navigationRequestId != widget.navigationRequestId) {
      _applyWorkforceRequest();
      if (entitlements?.candidateSearch == true) {
        prefillNeedsSearch = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_search());
        });
      }
    }
  }

  void _applyWorkforceRequest() {
    final request = widget.workforceRequest;
    if (request == null) return;
    tradeController.text =
        JobTaxonomyService.roleFor(request.tradeId)?.canonical ?? '';
    locationController.text = request.location;
    availableBy = request.availableBy;
    poolMode = false;
    prefillNeedsSearch = true;
  }

  @override
  void dispose() {
    requestId++;
    entitlementRefresh?.cancel();
    tradeController.dispose();
    nameController.dispose();
    locationController.dispose();
    super.dispose();
  }

  Future<void> _search({bool more = false}) async {
    if (entitlements == null ||
        (poolMode
            ? !entitlements!.talentPool
            : !entitlements!.candidateSearch)) {
      return;
    }
    final enteredTrade = tradeController.text.trim();
    final selectedTrade = more ? filters?.tradeId ?? '' : enteredTrade;
    final role = selectedTrade.isEmpty
        ? null
        : JobTaxonomyService.bestRoleFor(selectedTrade);
    if (!poolMode && role == null) {
      setState(() => error = 'Choose a construction trade to search.');
      return;
    }
    final nextFilters = more
        ? filters!
        : WebTalentFilters(
            tradeId: role?.id ?? '',
            name: poolMode ? nameController.text : '',
            location: locationController.text,
            availability: availability,
            invitesOnly: invitesOnly,
            availableBy: availableBy,
          );
    final employerId = widget.employerId;
    final currentRequest = ++requestId;
    setState(() {
      loading = true;
      error = null;
      if (!more) {
        selectedWorkerIds.clear();
        candidates = [];
        cursor = null;
        hasMore = false;
        selectedId = null;
      }
      searched = true;
      filters = nextFilters;
    });
    try {
      if (poolMode) {
        final page = await service.savedWorkerIds(employerId,
            after: more ? cursor : null);
        final loaded = await service.loadSavedCandidates(page.items);
        if (!mounted || requestId != currentRequest) return;
        final visible = page.items
            .map((id) => loaded[id])
            .whereType<WebTalentCandidate>()
            .where((item) =>
                (role == null || item.tradeIds.contains(role.id)) &&
                item.matches(nextFilters, DateTime.now()))
            .toList();
        setState(() {
          saved.addAll(page.items);
          candidates = mergeTalentCandidates(more ? candidates : [], visible);
          cursor = page.lastDocument;
          hasMore = page.hasMore;
        });
      } else {
        final page =
            await service.findWorkers(nextFilters, after: more ? cursor : null);
        final pageSaved = await service.savedWorkerIdsFor(
            employerId, page.items.map((item) => item.id).toList());
        if (!mounted || requestId != currentRequest) return;
        setState(() {
          saved.addAll(pageSaved);
          candidates =
              mergeTalentCandidates(more ? candidates : [], page.items);
          cursor = page.lastDocument;
          hasMore = page.hasMore;
        });
      }
    } catch (_) {
      if (mounted && requestId == currentRequest) {
        setState(() => error = 'Could not load workers. Please try again.');
      }
    } finally {
      if (mounted && requestId == currentRequest) {
        setState(() => loading = false);
      }
    }
  }

  void _switchMode(bool pool) {
    setState(() {
      poolMode = pool;
      searched = false;
      candidates = [];
      cursor = null;
      hasMore = false;
      selectedId = null;
      selectedWorkerIds.clear();
      error = null;
      loading = false;
      requestId++;
    });
    if (pool && entitlements?.talentPool == true) _search();
  }

  Future<void> _toggleSave(WebTalentCandidate candidate) async {
    final wasSaved = saved.contains(candidate.id);
    setState(() {
      if (wasSaved) {
        saved.remove(candidate.id);
      } else {
        saved.add(candidate.id);
      }
    });
    try {
      if (wasSaved) {
        await service.unsave(widget.employerId, candidate.id);
        if (poolMode && mounted) {
          setState(
              () => candidates.removeWhere((item) => item.id == candidate.id));
        }
      } else {
        await service.save(widget.employerId, candidate.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasSaved) {
          saved.add(candidate.id);
        } else {
          saved.remove(candidate.id);
        }
        error = 'Could not update Talent Pool. Please try again.';
      });
    }
  }

  bool _selectable(WebTalentCandidate candidate) =>
      candidate.allowsInvites &&
      candidate.confirmedAt != null &&
      candidate.availability != WorkerAvailability.unknown &&
      candidate.availability != WorkerAvailability.notLooking;

  Future<List<Job>> _invitableJobs() async {
    final jobs = FirebaseFirestore.instance.collection('jobs');
    final snapshot = await jobs
        .where('ownerId', isEqualTo: widget.employerId)
        .where('status', whereIn: ['active', 'published', 'open']).get();
    final visible = snapshot.docs
        .map((doc) => Job.fromFirestore(doc.id, doc.data()))
        .toList();
    final requestedId = widget.workforceRequest?.vacancyId;
    visible.removeWhere((job) =>
        job.ownerId != widget.employerId ||
        !job.isPubliclyVisible ||
        job.remainingPositions <= 0);
    if (requestedId != null) {
      visible.sort((a, b) =>
          (b.id == requestedId ? 1 : 0).compareTo(a.id == requestedId ? 1 : 0));
    }
    return visible;
  }

  Future<void> _inviteSelected() async {
    if (entitlements?.vacancyInvites != true ||
        entitlements!.invitationUsed >= entitlements!.invitationLimit) {
      setState(() => error = 'Monthly invitation allowance reached.');
      return;
    }
    final chosen = candidates
        .where((item) => selectedWorkerIds.contains(item.id))
        .toList(growable: false);
    if (chosen.isEmpty || inviting) return;
    final inviteJobsFuture = _invitableJobs();
    final choice = await showDialog<TalentInviteChoice>(
      context: context,
      builder: (dialogContext) => FutureBuilder(
        future: inviteJobsFuture,
        builder: (context, snapshot) {
          final jobs = snapshot.data ?? const <Job>[];
          final now = DateTime.now();
          final recommended = jobs
              .where((job) => assessTalentInvite(chosen, job, now).recommended)
              .toList();
          final others = jobs
              .where((job) => !assessTalentInvite(chosen, job, now).recommended)
              .toList();
          Widget vacancyTile(Job job) {
            final assessment = assessTalentInvite(chosen, job, now);
            final details = [
              JobTaxonomyService.canonicalFor(job.canonicalRoleId.isNotEmpty
                  ? job.canonicalRoleId
                  : job.trade),
              job.site,
              job.city,
              if (job.startDate != null)
                'Starts ${MaterialLocalizations.of(context).formatMediumDate(job.startDate!)}',
              '${job.remainingPositions} positions left',
            ].where((part) => part.trim().isNotEmpty).join(' · ');
            return ListTile(
              title: Text(job.displayTitle),
              subtitle: Text([
                details,
                ...assessment.warnings,
                if (assessment.hardBlock != null) assessment.hardBlock!
              ].join('\n')),
              isThreeLine: assessment.warnings.isNotEmpty ||
                  assessment.hardBlock != null,
              enabled: assessment.hardBlock == null,
              onTap: assessment.hardBlock != null
                  ? null
                  : () async {
                      if (!assessment.recommended) {
                        final confirmed = await showDialog<bool>(
                          context: dialogContext,
                          builder: (confirmContext) => AlertDialog(
                            title: const Text('Invite despite mismatch?'),
                            content: Text(assessment.warnings.join('\n')),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(confirmContext, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(confirmContext, true),
                                  child: const Text('Invite anyway')),
                            ],
                          ),
                        );
                        if (confirmed != true || !dialogContext.mounted) return;
                      }
                      Navigator.pop(dialogContext,
                          TalentInviteChoice(job, !assessment.recommended));
                    },
            );
          }

          return AlertDialog(
            title: const Text('Invite selected workers'),
            content: SizedBox(
              width: 450,
              height: 350,
              child: snapshot.hasError
                  ? const Center(child: Text('Could not load vacancies.'))
                  : !snapshot.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : jobs.isEmpty
                          ? const Center(
                              child: Text('No active vacancies available.'))
                          : ListView(children: [
                              const ListTile(
                                  title: Text('Recommended vacancies')),
                              if (recommended.isEmpty)
                                const ListTile(
                                    title: Text(
                                        'No close matches. You can still choose an active vacancy below.')),
                              for (final job in recommended) vacancyTile(job),
                              const Divider(),
                              const ListTile(
                                  title: Text('Other active vacancies')),
                              for (final job in others) vacancyTile(job),
                            ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'))
            ],
          );
        },
      ),
    );
    if (!mounted || choice == null) return;
    setState(() => inviting = true);
    try {
      final result = await invitationService.invite(
          choice.job.id, chosen.map((item) => item.id).toList(),
          allowRelevanceMismatch: choice.allowRelevanceMismatch);
      if (!mounted) return;
      final created = (result['created'] as num?)?.toInt() ?? 0;
      final outcomes = (result['results'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => item['result']?.toString() ?? '')
          .where((item) => item != 'invited')
          .toSet();
      if (created > 0) setState(selectedWorkerIds.clear);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
        '$created invitation(s) sent.'
        '${outcomes.isEmpty ? '' : ' Skipped: ${outcomes.join(', ').replaceAll('_', ' ')}.'}',
      )));
      if (created > 0) _loadEntitlements();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not send invitations. Please try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => inviting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (entitlements == null) {
      return Center(
        child: entitlementFailed
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Could not load plan access.'),
                TextButton(
                    onPressed: _loadEntitlements, child: const Text('Retry')),
              ])
            : const CircularProgressIndicator(),
      );
    }
    final locked =
        poolMode ? !entitlements!.talentPool : !entitlements!.candidateSearch;
    final selected = selectedId == null
        ? null
        : candidates.where((item) => item.id == selectedId).firstOrNull;
    return SingleChildScrollView(
      child: WebPageContainer(
        topPadding: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Talent', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('Find Workers'),
                    icon: Icon(Icons.search)),
                ButtonSegment(
                    value: true,
                    label: Text('My Talent Pool'),
                    icon: Icon(Icons.bookmark_outline)),
              ],
              selected: {poolMode},
              onSelectionChanged: (value) => _switchMode(value.first),
            ),
            const SizedBox(height: 16),
            if (locked) ...[
              Text(poolMode
                  ? 'Talent Pool is available on Growth and Pro.'
                  : 'Candidate Search is available on Growth and Pro.'),
              if (widget.onOpenBilling != null)
                TextButton.icon(
                  onPressed: widget.onOpenBilling,
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('View plans'),
                ),
            ] else ...[
              Text('Vacancy invitations: ${entitlements!.invitationUsed} / '
                  '${entitlements!.invitationLimit} this month'),
              const SizedBox(height: 8),
              Text(entitlements!.talentOutreach
                  ? 'Talent Outreach add-on: ${entitlements!.outreachUsed} / '
                      '${entitlements!.outreachLimit} credits reserved. '
                      'Messaging is not available yet.'
                  : 'Talent Outreach: add-on required. Messaging is not available yet.'),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, bounds) {
                final width = bounds.maxWidth < 640 ? bounds.maxWidth : 245.0;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (poolMode)
                      SizedBox(
                        width: width,
                        height: WebToolbar.controlHeight,
                        child: TextField(
                          controller: nameController,
                          onSubmitted: (_) => _search(),
                          decoration: const InputDecoration(
                            hintText: 'Search saved workers by name',
                            prefixIcon: Icon(Icons.person_search_outlined),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: width,
                      height: WebToolbar.controlHeight,
                      child: Autocomplete<ConstructionRole>(
                        key: ValueKey(
                            'talent-trade:${widget.employerId}:${widget.navigationRequestId}'),
                        initialValue:
                            TextEditingValue(text: tradeController.text),
                        displayStringForOption: (role) => role.canonical,
                        optionsBuilder: (value) => value.text.trim().isEmpty
                            ? const Iterable<ConstructionRole>.empty()
                            : JobTaxonomyService.suggestions(value.text),
                        onSelected: (role) =>
                            tradeController.text = role.canonical,
                        fieldViewBuilder:
                            (context, controller, focusNode, onSubmit) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            onChanged: (value) => tradeController.text = value,
                            onSubmitted: (_) => _search(),
                            decoration: InputDecoration(
                              hintText: poolMode
                                  ? 'Trade (optional)'
                                  : 'Trade, e.g. fixer',
                              prefixIcon:
                                  const Icon(Icons.construction_outlined),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: width,
                      height: WebToolbar.controlHeight,
                      child: TextField(
                        controller: locationController,
                        onSubmitted: (_) => _search(),
                        decoration: const InputDecoration(
                          hintText: 'City or region',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      height: WebToolbar.controlHeight,
                      child: DropdownButtonFormField<WorkerAvailability?>(
                        initialValue: availability,
                        decoration:
                            const InputDecoration(labelText: 'Availability'),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(
                              value: WorkerAvailability.availableNow,
                              child: Text('Available now')),
                          DropdownMenuItem(
                              value: WorkerAvailability.availableFrom,
                              child: Text('Available from')),
                          DropdownMenuItem(
                              value: WorkerAvailability.busy,
                              child: Text('Busy')),
                          DropdownMenuItem(
                              value: WorkerAvailability.notLooking,
                              child: Text('Not looking')),
                          DropdownMenuItem(
                              value: WorkerAvailability.unknown,
                              child: Text('Unknown / stale')),
                        ],
                        onChanged: (value) =>
                            setState(() => availability = value),
                      ),
                    ),
                    SizedBox(
                      height: WebToolbar.controlHeight,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: availableBy ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 730)),
                          );
                          if (date != null && mounted) {
                            setState(() => availableBy = date);
                          }
                        },
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text(availableBy == null
                            ? 'Available by'
                            : 'Available by ${availableBy!.day}/${availableBy!.month}/${availableBy!.year}'),
                      ),
                    ),
                    if (availableBy != null)
                      IconButton(
                        tooltip: 'Clear available-by date',
                        onPressed: () => setState(() => availableBy = null),
                        icon: const Icon(Icons.close),
                      ),
                    FilterChip(
                      label: const Text('Allows vacancy invitations'),
                      selected: invitesOnly,
                      onSelected: (value) =>
                          setState(() => invitesOnly = value),
                    ),
                    SizedBox(
                      height: WebToolbar.controlHeight,
                      child: FilledButton.icon(
                        onPressed: loading ? null : () => _search(),
                        icon: const Icon(Icons.search),
                        label: const Text('Search'),
                      ),
                    ),
                  ],
                );
              }),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: WebTheme.danger)),
              ],
              if (loading) const LinearProgressIndicator(),
              if (candidates.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${selectedWorkerIds.length} selected'),
                    TextButton(
                        onPressed: () => setState(() {
                              selectedWorkerIds.clear();
                              for (final candidate in candidates) {
                                if (_selectable(candidate) &&
                                    selectedWorkerIds.length < 20) {
                                  selectedWorkerIds.add(candidate.id);
                                }
                              }
                            }),
                        child: const Text('Select visible eligible')),
                    TextButton(
                        onPressed: selectedWorkerIds.isEmpty
                            ? null
                            : () => setState(selectedWorkerIds.clear),
                        child: const Text('Clear')),
                    FilledButton.icon(
                      onPressed: selectedWorkerIds.isEmpty ||
                              inviting ||
                              !entitlements!.vacancyInvites ||
                              entitlements!.invitationUsed >=
                                  entitlements!.invitationLimit
                          ? null
                          : _inviteSelected,
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Invite to vacancy'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 16),
              if (!searched)
                Text(
                    poolMode
                        ? 'Your saved workers appear here.'
                        : 'Choose a trade to find workers.',
                    style: const TextStyle(color: WebTheme.muted)),
              if (searched && candidates.isEmpty && !loading)
                Text(
                    hasMore
                        ? 'No matches in this batch. Load more to continue.'
                        : 'No workers match these filters.',
                    style: const TextStyle(color: WebTheme.muted)),
              if (candidates.isNotEmpty)
                LayoutBuilder(
                    builder: (context, bounds) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: Column(children: [
                              for (final candidate in candidates)
                                _CandidateCard(
                                  candidate: candidate,
                                  checked:
                                      selectedWorkerIds.contains(candidate.id),
                                  selectable: _selectable(candidate) &&
                                      (selectedWorkerIds.length < 20 ||
                                          selectedWorkerIds
                                              .contains(candidate.id)),
                                  onChecked: (checked) => setState(() {
                                    if (checked == true) {
                                      selectedWorkerIds.add(candidate.id);
                                    } else {
                                      selectedWorkerIds.remove(candidate.id);
                                    }
                                  }),
                                  saved: saved.contains(candidate.id),
                                  selected: selectedId == candidate.id,
                                  onOpen: () => bounds.maxWidth < 800
                                      ? _showDetail(candidate)
                                      : setState(
                                          () => selectedId = candidate.id),
                                  onSave: () => _toggleSave(candidate),
                                ),
                            ])),
                            if (bounds.maxWidth >= 800 && selected != null) ...[
                              const SizedBox(width: 16),
                              SizedBox(
                                  width: 340,
                                  child: _CandidateDetail(
                                    candidate: selected,
                                    saved: saved.contains(selected.id),
                                    onSave: () => _toggleSave(selected),
                                  )),
                            ],
                          ],
                        )),
              if (hasMore)
                TextButton.icon(
                  onPressed: loading ? null : () => _search(more: true),
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Load more'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetail(WebTalentCandidate candidate) => showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, refresh) => Dialog(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _CandidateDetail(
                        candidate: candidate,
                        saved: saved.contains(candidate.id),
                        onSave: () async {
                          await _toggleSave(candidate);
                          if (context.mounted) refresh(() {});
                        },
                      ),
                    ),
                  ),
                )),
      );
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard(
      {required this.candidate,
      required this.checked,
      required this.selectable,
      required this.onChecked,
      required this.saved,
      required this.selected,
      required this.onOpen,
      required this.onSave});
  final WebTalentCandidate candidate;
  final bool checked;
  final bool selectable;
  final ValueChanged<bool?> onChecked;
  final bool saved;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Card(
        color: selected ? WebTheme.selected : WebTheme.surface,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: selected ? WebTheme.accent : WebTheme.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Checkbox(value: checked, onChanged: selectable ? onChecked : null),
            ClipOval(
                child: WebRemoteImage(
                    url: candidate.avatarUrl,
                    width: 50,
                    height: 50,
                    fallbackIcon: Icons.person_outline)),
            const SizedBox(width: 12),
            Expanded(
                child: InkWell(
                    onTap: onOpen,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(candidate.name,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(candidate.tradeLabel,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                            [candidate.area, candidate.region]
                                .where((value) => value.isNotEmpty)
                                .join(', '),
                            style: const TextStyle(color: WebTheme.muted)),
                        Text(candidate.availabilityLabel(DateTime.now()),
                            style: const TextStyle(color: WebTheme.accent)),
                      ],
                    ))),
            IconButton(
              tooltip:
                  saved ? 'Remove from Talent Pool' : 'Save to Talent Pool',
              onPressed: onSave,
              icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline),
            ),
          ]),
        ),
      );
}

class _CandidateDetail extends StatelessWidget {
  const _CandidateDetail(
      {required this.candidate, required this.saved, required this.onSave});
  final WebTalentCandidate candidate;
  final bool saved;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClipOval(
                  child: WebRemoteImage(
                      url: candidate.avatarUrl,
                      width: 64,
                      height: 64,
                      fallbackIcon: Icons.person_outline)),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(candidate.name,
                      style: Theme.of(context).textTheme.titleLarge)),
            ]),
            const SizedBox(height: 14),
            Text(candidate.tradeLabel),
            Text([candidate.area, candidate.region]
                .where((value) => value.isNotEmpty)
                .join(', ')),
            Text('${candidate.experienceYears} years experience'),
            if (candidate.ratingCount > 0)
              Text('★ ${candidate.rating.toStringAsFixed(1)} '
                  '(${candidate.ratingCount} reviews)'),
            const SizedBox(height: 12),
            Text(candidate.availabilityLabel(DateTime.now())),
            if (candidate.confirmedAt != null)
              Text(
                  'Confirmed ${candidate.confirmedAt!.day}/'
                  '${candidate.confirmedAt!.month}/${candidate.confirmedAt!.year}',
                  style: const TextStyle(color: WebTheme.muted)),
            Text(candidate.allowsInvites
                ? 'Allows vacancy invitations'
                : 'Vacancy invitations off'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onSave,
              icon: Icon(saved
                  ? Icons.bookmark_remove_outlined
                  : Icons.bookmark_add_outlined),
              label: Text(
                  saved ? 'Remove from Talent Pool' : 'Save to Talent Pool'),
            ),
          ]),
        ),
      );
}
