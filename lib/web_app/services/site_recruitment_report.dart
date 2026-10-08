import '../../models/job.dart';
import '../../services/job_taxonomy_service.dart';
import '../../services/worker_assignment_service.dart';

class SiteTradeReport {
  const SiteTradeReport({
    required this.tradeId,
    required this.required,
    required this.filled,
    required this.starting,
    required this.active,
    required this.finishing,
    required this.remaining,
    required this.vacancies,
  });

  final String tradeId;
  final int required;
  final int filled;
  final int starting;
  final int active;
  final int finishing;
  final int remaining;
  final List<Job> vacancies;

  String get tradeName =>
      JobTaxonomyService.roleFor(tradeId)?.canonical ?? tradeId;
}

List<SiteTradeReport> siteRecruitmentReport(
    List<Job> jobs, List<WorkerAssignment> assignments, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final horizon = DateTime(today.year, today.month, today.day + 14);
  final tradeIds = <String>{};
  String jobTrade(Job job) =>
      JobTaxonomyService.roleFor(job.canonicalRoleId)?.id ??
      JobTaxonomyService.bestRoleFor(job.trade)?.id ??
      '';
  final vacancies =
      jobs.where((job) => job.isPubliclyVisible && job.positions > 0).toList();
  tradeIds.addAll(vacancies.map(jobTrade).where((id) => id.isNotEmpty));
  final operating = assignments
      .where((item) => {'scheduled', 'active'}.contains(item.status))
      .toList();
  String assignmentTrade(WorkerAssignment item) =>
      JobTaxonomyService.roleFor(item.tradeId)?.id ??
      JobTaxonomyService.bestRoleFor(item.tradeName)?.id ??
      '';
  tradeIds.addAll(operating.map(assignmentTrade).where((id) => id.isNotEmpty));
  bool inHorizon(DateTime? date) =>
      date != null &&
      !DateTime(date.year, date.month, date.day).isBefore(today) &&
      DateTime(date.year, date.month, date.day).isBefore(horizon);
  final result = <SiteTradeReport>[];
  for (final tradeId in tradeIds) {
    final tradeJobs =
        vacancies.where((job) => jobTrade(job) == tradeId).toList();
    final tradeAssignments =
        operating.where((item) => assignmentTrade(item) == tradeId);
    final active = tradeAssignments
        .where((item) {
          final start = item.startDate;
          final end = item.actualEndDate ?? item.expectedEndDate;
          return start != null &&
              !start.isAfter(now) &&
              (end == null || !end.isBefore(today));
        })
        .map((item) => item.data['workerId'])
        .whereType<String>()
        .toSet()
        .length;
    result.add(SiteTradeReport(
      tradeId: tradeId,
      required: tradeJobs.fold(0, (sum, job) => sum + job.positions),
      filled: tradeJobs.fold(0, (sum, job) => sum + job.filledPositions),
      starting:
          tradeAssignments.where((item) => inHorizon(item.startDate)).length,
      active: active,
      finishing: tradeAssignments
          .where(
              (item) => inHorizon(item.actualEndDate ?? item.expectedEndDate))
          .length,
      remaining: tradeJobs.fold(0, (sum, job) => sum + job.remainingPositions),
      vacancies: tradeJobs,
    ));
  }
  result.sort((a, b) => a.tradeName.compareTo(b.tradeName));
  return result;
}
