import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../widgets/web_design_components.dart';

class WebVacancyLifecycleStatus {
  const WebVacancyLifecycleStatus({
    required this.label,
    required this.tone,
  });

  final String label;
  final WebStatusTone tone;
}

WebVacancyLifecycleStatus webVacancyLifecycleStatus(Job job) {
  final moderation = _normalize(job.moderationStatus);
  final status = _normalize(job.status);

  if (moderation == 'rejected' || status == 'rejected') {
    return const WebVacancyLifecycleStatus(
      label: 'Rejected',
      tone: WebStatusTone.danger,
    );
  }
  if (moderation == 'pending_review' ||
      moderation == 'pending' ||
      moderation == 'pending_approval') {
    return const WebVacancyLifecycleStatus(
      label: 'Pending review',
      tone: WebStatusTone.warning,
    );
  }
  if (moderation == 'suspended' || status == 'suspended') {
    return const WebVacancyLifecycleStatus(
      label: 'Suspended',
      tone: WebStatusTone.danger,
    );
  }
  if (moderation == 'on_hold' || status == 'on_hold') {
    return const WebVacancyLifecycleStatus(
      label: 'On hold',
      tone: WebStatusTone.warning,
    );
  }
  if (moderation == 'draft' || status == 'draft') {
    return const WebVacancyLifecycleStatus(
      label: 'Draft',
      tone: WebStatusTone.neutral,
    );
  }

  final liveStatus = status.isEmpty ||
      status == 'active' ||
      status == 'published' ||
      status == 'open';
  if (moderation == 'approved' && liveStatus && job.active && !job.deleted) {
    return const WebVacancyLifecycleStatus(
      label: 'Active',
      tone: WebStatusTone.success,
    );
  }

  final inactiveStatus = status == 'closed' ||
      status == 'inactive' ||
      status == 'deactivated' ||
      status == 'completed' ||
      status == 'archived' ||
      status == 'cancelled' ||
      status == 'expired' ||
      status == 'deleted';
  if (moderation == 'approved' ||
      inactiveStatus ||
      !job.active ||
      job.deleted) {
    return const WebVacancyLifecycleStatus(
      label: 'Inactive',
      tone: WebStatusTone.neutral,
    );
  }

  // Legacy vacancies without moderation data retain their usable lifecycle
  // meaning without exposing raw backend status values.
  if (liveStatus && job.active) {
    return const WebVacancyLifecycleStatus(
      label: 'Active',
      tone: WebStatusTone.success,
    );
  }
  return const WebVacancyLifecycleStatus(
    label: 'Inactive',
    tone: WebStatusTone.neutral,
  );
}

Widget webVacancyLifecycleBadge(Job job) {
  final lifecycle = webVacancyLifecycleStatus(job);
  return WebStatusChip(label: lifecycle.label, tone: lifecycle.tone);
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
