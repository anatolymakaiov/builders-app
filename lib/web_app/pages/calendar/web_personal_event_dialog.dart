import 'package:flutter/material.dart';

class WebPersonalEventDraft {
  const WebPersonalEventDraft({
    required this.title,
    required this.start,
    required this.end,
    required this.reminder,
    required this.alertMinutes,
    required this.description,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final bool reminder;
  final int alertMinutes;
  final String description;
}

class WebPersonalEventDialog extends StatefulWidget {
  const WebPersonalEventDialog({super.key, required this.initialDate});

  final DateTime initialDate;

  @override
  State<WebPersonalEventDialog> createState() => _WebPersonalEventDialogState();
}

class _WebPersonalEventDialogState extends State<WebPersonalEventDialog> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  late DateTime day = DateTime(widget.initialDate.year,
      widget.initialDate.month, widget.initialDate.day);
  late DateTime endDay = day;
  TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay endTime = const TimeOfDay(hour: 10, minute: 0);
  bool reminder = false;
  int alertMinutes = -1;

  static const alertChoices = <int, String>{
    -1: 'None',
    0: 'At event time',
    5: '5 minutes before',
    10: '10 minutes before',
    15: '15 minutes before',
    30: '30 minutes before',
    60: '1 hour before',
    120: '2 hours before',
    1440: '1 day before',
    2880: '2 days before',
    10080: '1 week before',
  };

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  DateTime _at(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  Future<void> _pickDate({bool ending = false}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: ending ? endDay : day,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        if (ending) {
          endDay = picked;
        } else {
          day = picked;
          if (endDay.isBefore(day)) endDay = picked;
        }
      });
    }
  }

  Future<void> _pickTime({required bool ending}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: ending ? endTime : startTime,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (ending) {
        endTime = picked;
      } else {
        startTime = picked;
      }
    });
  }

  void _submit() {
    if (formKey.currentState?.validate() != true) return;
    final start = _at(day, startTime);
    final end = _at(endDay, endTime);
    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End must be after start.')),
      );
      return;
    }
    Navigator.of(context).pop(WebPersonalEventDraft(
      title: title.text.trim(),
      start: start,
      end: end,
      reminder: reminder,
      alertMinutes: alertMinutes,
      description: description.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New calendar entry'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Event')),
                    ButtonSegment(value: true, label: Text('Reminder')),
                  ],
                  selected: {reminder},
                  onSelectionChanged: (value) =>
                      setState(() => reminder = value.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: title,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (value) =>
                      (value?.trim().isEmpty ?? true) ? 'Enter a title' : null,
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                      'Starts ${MaterialLocalizations.of(context).formatMediumDate(day)}'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(ending: true),
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                      'Ends ${MaterialLocalizations.of(context).formatMediumDate(endDay)}'),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  OutlinedButton(
                    onPressed: () => _pickTime(ending: false),
                    child: Text('Starts ${startTime.format(context)}'),
                  ),
                  OutlinedButton(
                    onPressed: () => _pickTime(ending: true),
                    child: Text('Ends ${endTime.format(context)}'),
                  ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: alertMinutes,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Alert'),
                  items: [
                    for (final choice in alertChoices.entries)
                      DropdownMenuItem(
                        value: choice.key,
                        child: Text(choice.value),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => alertMinutes = value ?? -1),
                ),
                TextFormField(
                  controller: description,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      );
}
