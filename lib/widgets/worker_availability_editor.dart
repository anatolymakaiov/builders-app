import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/worker_availability_service.dart';

Future<WorkerAvailabilitySelection?> showWorkerAvailabilityEditor(
  BuildContext context, {
  required Map<String, dynamic> profile,
  bool checkIn = false,
}) async {
  var status = WorkerAvailabilityService.fromProfile(profile);
  var from = WorkerAvailabilityService.availableFrom(profile);
  var invites = WorkerAvailabilityService.allowsInvites(profile);
  final today = DateUtils.dateOnly(DateTime.now());
  if (from != null &&
      from.isBefore(WorkerAvailabilityService.dateOnly(today))) {
    from = null;
  }
  return showDialog<WorkerAvailabilitySelection>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(checkIn ? 'Confirm availability' : 'Availability'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (checkIn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                        WorkerAvailabilityService.fromProfile(profile) ==
                                WorkerAvailability.availableFrom
                            ? 'Is your planned availability date still correct?'
                            : 'Are you still available for work?'),
                  ),
                DropdownButtonFormField<WorkerAvailability>(
                  isExpanded: true,
                  initialValue:
                      status == WorkerAvailability.unknown ? null : status,
                  decoration: const InputDecoration(
                    labelText: 'Work availability',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final choice in WorkerAvailabilityService.choices)
                      DropdownMenuItem(
                        value: choice,
                        child: Text(WorkerAvailabilityService.label(choice)),
                      ),
                  ],
                  onChanged: (next) {
                    if (next != null) setDialogState(() => status = next);
                  },
                ),
                if (status == WorkerAvailability.availableFrom) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: from?.toLocal().isBefore(today) == false
                            ? from!.toLocal()
                            : today,
                        firstDate: today,
                        lastDate: DateTime(today.year + 5, 12, 31),
                      );
                      if (picked != null) {
                        setDialogState(() => from = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(from == null
                        ? 'Choose available date'
                        : WorkerAvailabilityService.label(status, from: from)),
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Allow verified employers to send me relevant vacancy invitations through STROYKA',
                  ),
                  value: invites,
                  onChanged: (value) => setDialogState(() => invites = value),
                ),
                const Text(
                  'Invitations stay inside STROYKA. Your phone, email and exact address are not shared.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(checkIn ? 'Later' : 'Cancel'),
          ),
          FilledButton(
            onPressed: status == WorkerAvailability.unknown ||
                    (status == WorkerAvailability.availableFrom && from == null)
                ? null
                : () => Navigator.pop(
                      dialogContext,
                      WorkerAvailabilitySelection(
                        status: status,
                        availableFrom:
                            status == WorkerAvailability.availableFrom
                                ? from
                                : null,
                        allowVacancyInvites: invites,
                      ),
                    ),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

class WorkerAvailabilityCheckIn {
  static final _shownForSession = <String>{};

  static Future<void> maybePrompt(
    BuildContext context, {
    required String workerId,
    required Map<String, dynamic> profile,
  }) async {
    if (!context.mounted ||
        FirebaseAuth.instance.currentUser?.uid != workerId ||
        !WorkerAvailabilityService.shouldPrompt(profile, DateTime.now()) ||
        !_shownForSession.add(workerId)) {
      return;
    }
    final selection = await showWorkerAvailabilityEditor(
      context,
      profile: profile,
      checkIn: true,
    );
    if (selection == null) return;
    try {
      await WorkerAvailabilityService()
          .updateOwnAvailability(workerId, selection);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not save availability. Try again from Profile.'),
        ));
      }
    }
  }
}
