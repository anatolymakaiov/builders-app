import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/worker_availability_service.dart';
import '../services/worker_unavailability_service.dart';

class WorkerUnavailabilityPanel extends StatelessWidget {
  const WorkerUnavailabilityPanel(
      {super.key, required this.workerId, required this.profile});

  final String workerId;
  final Map<String, dynamic> profile;

  String _date(BuildContext context, DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value);

  String _effectiveLabel(Map<String, dynamic> data, BuildContext context) {
    final status =
        (data['effectiveAvailabilityStatus'] ?? 'unknown').toString();
    final from = WorkerAvailabilityService.availableFrom({
      WorkerAvailabilityService.dateField: data['effectiveAvailableFrom'],
    });
    return switch (status) {
      'available_now' => 'Available now',
      'available_from' => from == null
          ? 'Available later'
          : 'Available from ${_date(context, from)}',
      'busy' => from == null
          ? 'Busy'
          : 'Busy until ${_date(context, from.subtract(const Duration(days: 1)))}',
      'unavailable' => from == null
          ? 'Unavailable'
          : 'Unavailable until ${_date(context, from.subtract(const Duration(days: 1)))}',
      'not_looking' => 'Not looking for work',
      _ => 'Availability not confirmed',
    };
  }

  Future<void> _edit(
      BuildContext context, WorkerUnavailablePeriod? period) async {
    var start = period?.start ?? DateTime.now();
    var end = period?.end ?? start;
    var type = period?.type ?? 'holiday';
    final note = TextEditingController(text: period?.note ?? '');
    final service = WorkerUnavailabilityService();
    try {
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                    title: Text(period == null
                        ? 'Add unavailable period'
                        : 'Edit unavailable period'),
                    content: SizedBox(
                        width: 400,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                        context: dialogContext,
                                        initialDate: start,
                                        firstDate: DateTime.now()
                                            .subtract(const Duration(days: 1)),
                                        lastDate: DateTime.now()
                                            .add(const Duration(days: 730)));
                                    if (picked != null) {
                                      setDialogState(() {
                                        start = picked;
                                        if (end.isBefore(start)) end = start;
                                      });
                                    }
                                  },
                                  icon:
                                      const Icon(Icons.calendar_today_outlined),
                                  label:
                                      Text('From: ${_date(context, start)}')),
                              OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                        context: dialogContext,
                                        initialDate:
                                            end.isBefore(start) ? start : end,
                                        firstDate: start,
                                        lastDate: start
                                            .add(const Duration(days: 730)));
                                    if (picked != null) {
                                      setDialogState(() => end = picked);
                                    }
                                  },
                                  icon: const Icon(Icons.event_outlined),
                                  label: Text('To: ${_date(context, end)}')),
                              DropdownButtonFormField<String>(
                                  initialValue: type,
                                  decoration:
                                      const InputDecoration(labelText: 'Type'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'holiday',
                                        child: Text('Holiday')),
                                    DropdownMenuItem(
                                        value: 'personal',
                                        child: Text('Personal')),
                                    DropdownMenuItem(
                                        value: 'external_work',
                                        child: Text('External work')),
                                    DropdownMenuItem(
                                        value: 'other', child: Text('Other')),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setDialogState(() => type = value);
                                    }
                                  }),
                              TextField(
                                  controller: note,
                                  maxLength: 500,
                                  decoration: const InputDecoration(
                                      labelText: 'Optional note')),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () async {
                            try {
                              await service.save(
                                  workerId: workerId,
                                  id: period?.id,
                                  start: start,
                                  end: end,
                                  type: type,
                                  note: note.text);
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            } catch (_) {
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext)
                                    .showSnackBar(const SnackBar(
                                        content: Text(
                                            'Could not save unavailable period.')));
                              }
                            }
                          },
                          child: const Text('Save')),
                    ],
                  )));
    } finally {
      note.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = WorkerUnavailabilityService();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          'Your preference: ${WorkerAvailabilityService.profileLabel(profile)}'),
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('worker_discovery')
              .doc(workerId)
              .snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data();
            if (data == null) {
              return const Text('Checking current availability...');
            }
            final source = data['effectiveAvailabilityReason'];
            return Text('Current status: ${_effectiveLabel(data, context)}'
                '${source == 'assignment' ? ' · Scheduled work' : ''}');
          }),
      const SizedBox(height: 12),
      Row(children: [
        const Expanded(
            child: Text('Unavailable periods',
                style: TextStyle(fontWeight: FontWeight.w700))),
        IconButton(
            tooltip: 'Add unavailable period',
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add)),
      ]),
      StreamBuilder<List<WorkerUnavailablePeriod>>(
          stream: service.watchOwn(workerId),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('Could not load periods.');
            final periods = snapshot.data ?? const <WorkerUnavailablePeriod>[];
            if (periods.isEmpty) return const Text('No unavailable periods');
            return Column(children: [
              for (final period in periods)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${_date(context, period.start)} – ${_date(context, period.end)}'),
                    subtitle: Text([
                      period.type.replaceAll('_', ' '),
                      period.note
                    ].where((text) => text.isNotEmpty).join(' · ')),
                    trailing: Wrap(children: [
                      IconButton(
                          tooltip: 'Edit period',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _edit(context, period)),
                      IconButton(
                          tooltip: 'Delete period',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final yes = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                        title: const Text(
                                            'Delete unavailable period?'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancel')),
                                          FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Delete')),
                                        ]));
                            if (yes != true) return;
                            try {
                              await service.delete(workerId, period.id);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Could not delete period.')));
                              }
                            }
                          }),
                    ])),
            ]);
          }),
    ]);
  }
}
