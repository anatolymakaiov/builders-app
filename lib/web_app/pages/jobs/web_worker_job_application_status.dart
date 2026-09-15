import '../../../services/application_status_utils.dart';
import '../../services/web_applications_data_service.dart';
import '../../widgets/web_design_components.dart';

class WebWorkerJobApplicationStatus {
  const WebWorkerJobApplicationStatus({
    required this.normalizedStatus,
    required this.label,
    required this.tone,
  });

  final String normalizedStatus;
  final String label;
  final WebStatusTone tone;
}

Map<String, WebWorkerJobApplicationStatus> resolveWorkerJobStatuses(
  List<WebApplicationSummary> applications,
) {
  final latestByJob = <String, WebApplicationSummary>{};
  for (final application in applications) {
    final jobId = application.data['jobId']?.toString().trim() ?? '';
    if (jobId.isEmpty) continue;
    final current = latestByJob[jobId];
    if (current == null || _isNewer(application, current)) {
      latestByJob[jobId] = application;
    }
  }

  return {
    for (final entry in latestByJob.entries)
      entry.key: _statusFor(entry.value.status),
  };
}

bool _isNewer(
  WebApplicationSummary candidate,
  WebApplicationSummary current,
) {
  final candidateTime =
      ApplicationStatusUtils.getStatusSortTimestamp(candidate.data);
  final currentTime =
      ApplicationStatusUtils.getStatusSortTimestamp(current.data);
  final comparison = candidateTime.compareTo(currentTime);
  return comparison > 0 ||
      (comparison == 0 && candidate.id.compareTo(current.id) > 0);
}

WebWorkerJobApplicationStatus _statusFor(String rawStatus) {
  final normalized = ApplicationStatusUtils.normalizeStatus(rawStatus);
  return WebWorkerJobApplicationStatus(
    normalizedStatus: normalized,
    label: ApplicationStatusUtils.getStatusDisplayLabel(normalized, 'worker'),
    tone: switch (normalized) {
      'offer_accepted' || 'accepted' => WebStatusTone.success,
      'rejected' || 'offer_rejected' => WebStatusTone.danger,
      'withdrawn' || 'offer_withdrawn' => WebStatusTone.neutral,
      'pending' || 'negotiation' || 'offer_sent' => WebStatusTone.info,
      _ => WebStatusTone.neutral,
    },
  );
}
