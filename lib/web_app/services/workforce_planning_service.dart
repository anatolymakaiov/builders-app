import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/job.dart';
import '../../services/job_taxonomy_service.dart';
import '../../services/operational_calendar.dart';
import '../../services/worker_assignment_service.dart';
import 'web_sites_service.dart';

DateTime planningDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);
DateTime planningDayPlus(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

class PlanningWindow {
  const PlanningWindow(this.start, this.end);

  final DateTime start;
  final DateTime end; // Exclusive calendar day.

  factory PlanningWindow.nextDays(DateTime now, int days) {
    final start = planningDay(now);
    return PlanningWindow(start, planningDayPlus(start, days));
  }

  bool contains(DateTime date) {
    final day = planningDay(date);
    return !day.isBefore(start) && day.isBefore(end);
  }

  bool overlaps(DateTime startDate, DateTime? endDate) {
    final first = planningDay(startDate);
    final last = endDate == null ? null : planningDay(endDate);
    return first.isBefore(end) && (last == null || !last.isBefore(start));
  }

  CalendarRange get calendarRange => CalendarRange(start, end);
}

class PlanningChange {
  const PlanningChange(this.assignment, this.date);
  final WorkerAssignment assignment;
  final DateTime date;
}

class AssignmentConflict {
  const AssignmentConflict(
      this.first, this.second, this.overlapStart, this.overlapEnd);
  final WorkerAssignment first;
  final WorkerAssignment second;
  final DateTime overlapStart;
  final DateTime overlapEnd;
  String get workerName =>
      (first.data['workerDisplayName'] ?? 'Worker').toString();
}

class StaffingGap {
  const StaffingGap(
      {required this.siteId,
      required this.tradeId,
      required this.remainingPositions,
      required this.currentWorkers,
      required this.starting,
      required this.finishing,
      required this.projectedWorkers,
      required this.vacancies,
      required this.needDate});

  final String siteId;
  final String tradeId;
  final int remainingPositions;
  final int currentWorkers;
  final int starting;
  final int finishing;
  final int projectedWorkers;
  final List<Job> vacancies;
  final DateTime needDate;

  // Accepted offers already increment filledPositions and create assignments.
  // Subtracting assignments again would understate demand.
  int get gapCount => remainingPositions;
  String get tradeName =>
      JobTaxonomyService.roleFor(tradeId)?.canonical ?? tradeId;
}

class SiteWorkforceSummary {
  const SiteWorkforceSummary(
      {required this.siteId,
      required this.name,
      required this.city,
      required this.region,
      required this.status,
      required this.currentWorkers,
      required this.openVacancies,
      required this.starting,
      required this.finishing,
      required this.openPositions,
      required this.projectedWorkers});

  final String siteId;
  final String name;
  final String city;
  final String region;
  final String status;
  final int currentWorkers;
  final int openVacancies;
  final int starting;
  final int finishing;
  final int openPositions;
  final int projectedWorkers;
}

class TradeWorkforceSummary {
  const TradeWorkforceSummary(
      {required this.tradeId,
      required this.currentWorkers,
      required this.openPositions,
      required this.starting,
      required this.finishing,
      required this.projectedWorkers});
  final String tradeId;
  final int currentWorkers;
  final int openPositions;
  final int starting;
  final int finishing;
  final int projectedWorkers;
  String get tradeName =>
      JobTaxonomyService.roleFor(tradeId)?.canonical ?? tradeId;
}

class WorkforcePlan {
  const WorkforcePlan(
      {required this.sites,
      required this.siteSummaries,
      required this.tradeSummaries,
      required this.gaps,
      required this.assignments,
      required this.starts,
      required this.finishes,
      required this.conflicts,
      required this.activeSites,
      required this.activeWorkers,
      required this.activeAtRangeStart,
      required this.projectedAtRangeEnd,
      required this.startingThisWeek,
      required this.finishingThisWeek,
      required this.openVacancies});

  final List<WebSite> sites;
  final List<SiteWorkforceSummary> siteSummaries;
  final List<TradeWorkforceSummary> tradeSummaries;
  final List<StaffingGap> gaps;
  final List<WorkerAssignment> assignments;
  final List<PlanningChange> starts;
  final List<PlanningChange> finishes;
  final List<AssignmentConflict> conflicts;
  final int activeSites;
  final int activeWorkers;
  final int activeAtRangeStart;
  final int projectedAtRangeEnd;
  final int startingThisWeek;
  final int finishingThisWeek;
  final int openVacancies;

  int get gapCount => gaps.fold(0, (total, gap) => total + gap.gapCount);
}

DateTime? _end(WorkerAssignment assignment) =>
    assignment.actualEndDate ?? assignment.expectedEndDate;

String _jobRoleId(Job job) =>
    JobTaxonomyService.roleFor(job.canonicalRoleId)?.id ??
    JobTaxonomyService.bestRoleFor(job.trade)?.id ??
    JobTaxonomyService.bestRoleFor(job.title)?.id ??
    '';

bool _workingOn(WorkerAssignment assignment, DateTime day) {
  final start = assignment.startDate;
  if (start == null || planningDay(start).isAfter(planningDay(day))) {
    return false;
  }
  final end = _end(assignment);
  return end == null || !planningDay(end).isBefore(planningDay(day));
}

int _uniqueWorkers(Iterable<WorkerAssignment> assignments, DateTime day) =>
    assignments
        .where((item) => _workingOn(item, day))
        .map((item) => item.data['workerId'])
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;

List<AssignmentConflict> _conflicts(
    List<WorkerAssignment> assignments, PlanningWindow window) {
  final byWorker = <String, List<WorkerAssignment>>{};
  for (final item in assignments) {
    final id = (item.data['workerId'] ?? '').toString();
    if (id.isNotEmpty) {
      byWorker.putIfAbsent(id, () => []).add(item);
    }
  }
  final result = <AssignmentConflict>[];
  for (final group in byWorker.values) {
    group.sort((a, b) => a.startDate!.compareTo(b.startDate!));
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        final first = group[i];
        final second = group[j];
        final secondStart = planningDay(second.startDate!);
        final overlapStart =
            secondStart.isAfter(window.start) ? secondStart : window.start;
        final firstEnd = _end(first);
        final secondEnd = _end(second);
        final overlapEnd = [
          if (firstEnd != null) planningDay(firstEnd),
          if (secondEnd != null) planningDay(secondEnd),
          planningDayPlus(window.end, -1),
        ].reduce((a, b) => a.isBefore(b) ? a : b);
        if (!overlapEnd.isBefore(overlapStart) &&
            window.overlaps(overlapStart, overlapEnd)) {
          result
              .add(AssignmentConflict(first, second, overlapStart, overlapEnd));
        }
      }
    }
  }
  return result;
}

WorkforcePlan deriveWorkforcePlan(
    {required String employerId,
    required List<WebSite> sites,
    required List<Job> jobs,
    required List<WorkerAssignment> assignments,
    required PlanningWindow window,
    required DateTime now,
    String? siteId,
    String? tradeId}) {
  final ownSites = sites
      .where((site) => site.data['employerContextId'] == employerId)
      .toList();
  final siteById = {for (final site in ownSites) site.id: site};
  final visibleJobs = jobs
      .where((job) =>
          job.ownerId == employerId &&
          job.isPubliclyVisible &&
          job.remainingPositions > 0 &&
          (siteId == null || job.siteId == siteId) &&
          (tradeId == null || _jobRoleId(job) == tradeId))
      .toList();
  final demandJobs = visibleJobs
      .where((job) =>
          job.startDate == null ||
          planningDay(job.startDate!).isBefore(window.end))
      .toList();
  final allActiveAssignments = assignments
      .where((item) =>
          item.data['employerContextId'] == employerId &&
          {'active', 'scheduled'}.contains(item.status) &&
          item.startDate != null)
      .toList();
  final activeAssignments = allActiveAssignments
      .where((item) =>
          (siteId == null || item.data['siteId'] == siteId) &&
          (tradeId == null || item.tradeId == tradeId))
      .toList();
  final inRange = activeAssignments
      .where((item) => window.overlaps(item.startDate!, _end(item)))
      .toList();
  final allInRange = allActiveAssignments
      .where((item) => window.overlaps(item.startDate!, _end(item)))
      .toList();
  final starts = [
    for (final item in inRange)
      if (window.contains(item.startDate!))
        PlanningChange(item, item.startDate!)
  ];
  final finishes = [
    for (final item in inRange)
      if (_end(item) case final end?)
        if (window.contains(end)) PlanningChange(item, end)
  ];
  starts.sort((a, b) => a.date.compareTo(b.date));
  finishes.sort((a, b) => a.date.compareTo(b.date));
  final week = CalendarRange.week(now);
  final thisWeek = PlanningWindow(week.start, week.end);
  final relevantSiteIds = <String>{
    ...ownSites.where((site) => site.status == 'active').map((site) => site.id),
    ...visibleJobs.map((job) => job.siteId),
    ...inRange.map((item) => (item.data['siteId'] ?? '').toString()),
  };
  if (siteId != null) relevantSiteIds.retainWhere((id) => id == siteId);
  final siteSummaries = <SiteWorkforceSummary>[];
  for (final id in relevantSiteIds) {
    final site = siteById[id];
    final siteAssignments = inRange.where((item) => item.data['siteId'] == id);
    final siteJobs = visibleJobs.where((job) => job.siteId == id).toList();
    siteSummaries.add(SiteWorkforceSummary(
      siteId: id,
      name: site?.name ?? (id.isEmpty ? 'No Site / Legacy' : 'Site'),
      city: site?.city ?? '',
      region: (site?.data['region'] ?? '').toString(),
      status: site?.status ?? 'legacy',
      currentWorkers: _uniqueWorkers(
          activeAssignments.where((item) => item.data['siteId'] == id), now),
      openVacancies: siteJobs.length,
      starting: starts
          .where((change) => change.assignment.data['siteId'] == id)
          .length,
      finishing: finishes
          .where((change) => change.assignment.data['siteId'] == id)
          .length,
      openPositions: demandJobs
          .where((job) => job.siteId == id)
          .fold(0, (total, job) => total + job.remainingPositions),
      projectedWorkers:
          _uniqueWorkers(siteAssignments, planningDayPlus(window.end, -1)),
    ));
  }
  siteSummaries.sort((a, b) => a.name.compareTo(b.name));
  final tradeIds = <String>{
    ...demandJobs.map(_jobRoleId).where((id) => id.isNotEmpty),
    ...inRange.map((item) => item.tradeId).where((id) => id.isNotEmpty),
  };
  final tradeSummaries = <TradeWorkforceSummary>[];
  for (final id in tradeIds) {
    final relevant = inRange.where((item) => item.tradeId == id);
    tradeSummaries.add(TradeWorkforceSummary(
        tradeId: id,
        currentWorkers: _uniqueWorkers(
            activeAssignments.where((item) => item.tradeId == id), now),
        openPositions: demandJobs
            .where((job) => _jobRoleId(job) == id)
            .fold(0, (total, job) => total + job.remainingPositions),
        starting:
            starts.where((change) => change.assignment.tradeId == id).length,
        finishing:
            finishes.where((change) => change.assignment.tradeId == id).length,
        projectedWorkers:
            _uniqueWorkers(relevant, planningDayPlus(window.end, -1))));
  }
  tradeSummaries.sort((a, b) => a.tradeName.compareTo(b.tradeName));
  final groupedJobs = <String, List<Job>>{};
  for (final job in demandJobs) {
    final roleId = _jobRoleId(job);
    if (roleId.isEmpty) continue;
    groupedJobs.putIfAbsent('${job.siteId}\u0000$roleId', () => []).add(job);
  }
  final gaps = <StaffingGap>[];
  for (final entry in groupedJobs.entries) {
    final vacancy = entry.value.first;
    final sameGroup = inRange.where((item) =>
        item.data['siteId'] == vacancy.siteId &&
        item.tradeId == _jobRoleId(vacancy));
    final dates = entry.value
        .map((job) => job.startDate)
        .whereType<DateTime>()
        .toList()
      ..sort();
    gaps.add(StaffingGap(
      siteId: vacancy.siteId,
      tradeId: _jobRoleId(vacancy),
      remainingPositions:
          entry.value.fold(0, (total, job) => total + job.remainingPositions),
      currentWorkers: _uniqueWorkers(sameGroup, now),
      starting: starts
          .where((change) =>
              change.assignment.data['siteId'] == vacancy.siteId &&
              change.assignment.tradeId == _jobRoleId(vacancy))
          .length,
      finishing: finishes
          .where((change) =>
              change.assignment.data['siteId'] == vacancy.siteId &&
              change.assignment.tradeId == _jobRoleId(vacancy))
          .length,
      projectedWorkers:
          _uniqueWorkers(sameGroup, planningDayPlus(window.end, -1)),
      vacancies: entry.value,
      needDate: dates.isEmpty || dates.first.isBefore(planningDay(now))
          ? planningDay(now)
          : dates.first,
    ));
  }
  gaps.sort((a, b) => b.gapCount.compareTo(a.gapCount));
  final conflicts = _conflicts(allInRange, window).where((conflict) {
    bool matches(WorkerAssignment item) =>
        (siteId == null || item.data['siteId'] == siteId) &&
        (tradeId == null || item.tradeId == tradeId);
    return matches(conflict.first) || matches(conflict.second);
  }).toList();
  return WorkforcePlan(
    sites: ownSites,
    siteSummaries: siteSummaries,
    tradeSummaries: tradeSummaries,
    gaps: gaps,
    assignments: inRange,
    starts: starts,
    finishes: finishes,
    conflicts: conflicts,
    activeSites: ownSites
        .where((site) =>
            site.status == 'active' && (siteId == null || site.id == siteId))
        .length,
    activeWorkers: _uniqueWorkers(activeAssignments, now),
    activeAtRangeStart: _uniqueWorkers(activeAssignments, window.start),
    projectedAtRangeEnd:
        _uniqueWorkers(activeAssignments, planningDayPlus(window.end, -1)),
    startingThisWeek: activeAssignments
        .where((item) => thisWeek.contains(item.startDate!))
        .length,
    finishingThisWeek: activeAssignments
        .where((item) => _end(item) != null && thisWeek.contains(_end(item)!))
        .length,
    openVacancies: visibleJobs.length,
  );
}

class WorkforcePlanningService {
  WorkforcePlanningService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Future<WorkforcePlan> load(
      {required String employerId,
      required PlanningWindow window,
      required DateTime now,
      String? siteId,
      String? tradeId}) async {
    if (FirebaseAuth.instance.currentUser?.uid != employerId) {
      throw StateError('Only the signed-in employer can load planning.');
    }
    final week = CalendarRange.week(now);
    final fetchStart =
        window.start.isBefore(week.start) ? window.start : week.start;
    final fetchEnd = window.end.isAfter(week.end) ? window.end : week.end;
    final sitesFuture =
        WebSitesService(firestore: _db).loadEmployerSites(employerId);
    final jobsFuture = _db
        .collection('jobs')
        .where('ownerId', isEqualTo: employerId)
        .where('status', whereIn: ['active', 'published', 'open']).get();
    final assignmentFuture = OperationalCalendarService(firestore: _db)
        .loadEmployerPlanningAssignments(
            employerId, CalendarRange(fetchStart, fetchEnd));
    final sites = await sitesFuture;
    final jobs = (await jobsFuture)
        .docs
        .map((doc) => Job.fromFirestore(doc.id, doc.data()))
        .toList();
    final assignments = await assignmentFuture;
    if (FirebaseAuth.instance.currentUser?.uid != employerId) {
      throw StateError('Account changed while loading planning.');
    }
    return deriveWorkforcePlan(
        employerId: employerId,
        sites: sites,
        jobs: jobs,
        assignments: assignments,
        window: window,
        now: now,
        siteId: siteId,
        tradeId: tradeId);
  }
}
