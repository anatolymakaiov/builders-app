import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum WorkerAvailability {
  unknown,
  availableNow,
  availableFrom,
  busy,
  notLooking
}

class WorkerAvailabilitySelection {
  const WorkerAvailabilitySelection({
    required this.status,
    required this.allowVacancyInvites,
    this.availableFrom,
  });

  final WorkerAvailability status;
  final DateTime? availableFrom;
  final bool allowVacancyInvites;
}

class WorkerAvailabilityService {
  static const field = 'availabilityStatus';
  static const dateField = 'availableFrom';
  static const invitesField = 'allowVacancyInvites';
  static const confirmedField = 'availabilityConfirmedAt';
  static const updatedField = 'availabilityUpdatedAt';

  static const choices = [
    WorkerAvailability.availableNow,
    WorkerAvailability.availableFrom,
    WorkerAvailability.busy,
    WorkerAvailability.notLooking,
  ];

  static WorkerAvailability fromProfile(Map<String, dynamic> profile) {
    switch (profile[field]) {
      case 'available_now':
        return WorkerAvailability.availableNow;
      case 'open_to_work':
        // Earlier registration wrote this value automatically, so it is not consent.
        return WorkerAvailability.unknown;
      case 'available_from':
        return WorkerAvailability.availableFrom;
      case 'busy':
        return WorkerAvailability.busy;
      case 'not_looking':
        return WorkerAvailability.notLooking;
      default:
        return WorkerAvailability.unknown;
    }
  }

  static String value(WorkerAvailability availability) =>
      switch (availability) {
        WorkerAvailability.availableNow => 'available_now',
        WorkerAvailability.availableFrom => 'available_from',
        WorkerAvailability.busy => 'busy',
        WorkerAvailability.notLooking => 'not_looking',
        WorkerAvailability.unknown => 'unknown',
      };

  static String label(WorkerAvailability availability, {DateTime? from}) =>
      switch (availability) {
        WorkerAvailability.availableNow => 'Available now',
        WorkerAvailability.availableFrom => from == null
            ? 'Available from (date needed)'
            : 'Available from ${_displayDate(from)}',
        WorkerAvailability.busy => 'Busy',
        WorkerAvailability.notLooking => 'Not looking for work',
        WorkerAvailability.unknown => 'Availability not confirmed',
      };

  static String profileLabel(Map<String, dynamic> profile) => label(
        fromProfile(profile),
        from: availableFrom(profile),
      );

  static bool allowsInvites(Map<String, dynamic> profile) =>
      profile[invitesField] == true;

  static DateTime? availableFrom(Map<String, dynamic> profile) {
    final raw = profile[dateField];
    if (raw is Timestamp) return raw.toDate().toUtc();
    if (raw is DateTime) return raw.toUtc();
    if (raw is String) return DateTime.tryParse(raw)?.toUtc();
    return null;
  }

  static DateTime? confirmedAt(Map<String, dynamic> profile) {
    final raw = profile[confirmedField];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  static DateTime dateOnly(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  static Map<String, dynamic> updateFields(
    WorkerAvailabilitySelection selection, {
    required DateTime now,
  }) {
    if (selection.status == WorkerAvailability.unknown) {
      throw ArgumentError('Choose an availability status.');
    }
    final day = selection.availableFrom == null
        ? null
        : dateOnly(selection.availableFrom!);
    if (selection.status == WorkerAvailability.availableFrom &&
        (day == null || day.isBefore(dateOnly(now)))) {
      throw ArgumentError('Choose today or a future date.');
    }
    return {
      field: value(selection.status),
      dateField: selection.status == WorkerAvailability.availableFrom
          ? Timestamp.fromDate(day!)
          : null,
      invitesField: selection.allowVacancyInvites,
      confirmedField: Timestamp.fromDate(now),
      updatedField: Timestamp.fromDate(now),
    };
  }

  static bool shouldPrompt(Map<String, dynamic> profile, DateTime now) {
    final status = fromProfile(profile);
    final confirmed = confirmedAt(profile);
    if (status == WorkerAvailability.unknown || confirmed == null) return true;
    final elapsed = now.difference(confirmed);
    switch (status) {
      case WorkerAvailability.availableNow:
        return elapsed >= const Duration(days: 7);
      case WorkerAvailability.busy:
        return elapsed >= const Duration(days: 10);
      case WorkerAvailability.notLooking:
        return elapsed >= const Duration(days: 30);
      case WorkerAvailability.availableFrom:
        final from = availableFrom(profile);
        if (from == null) return true;
        if (from.isAfter(dateOnly(now))) {
          return from.difference(dateOnly(now)).inDays <= 3 &&
              elapsed >= const Duration(days: 3);
        }
        return elapsed >= const Duration(days: 1);
      case WorkerAvailability.unknown:
        return true;
    }
  }

  Future<Map<String, dynamic>> updateOwnAvailability(
    String workerId,
    WorkerAvailabilitySelection selection,
  ) async {
    if (FirebaseAuth.instance.currentUser?.uid != workerId) {
      throw StateError('Only the profile owner can change availability.');
    }
    final fields = updateFields(selection, now: DateTime.now());
    final ref = FirebaseFirestore.instance.collection('users').doc(workerId);
    final profile = await ref.get();
    if (!profile.exists || profile.data()?['role'] != 'worker') {
      throw StateError('Availability can only be changed on a worker profile.');
    }
    await ref.update({
      ...fields,
      confirmedField: FieldValue.serverTimestamp(),
      updatedField: FieldValue.serverTimestamp(),
    });
    return fields;
  }

  static String _displayDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
