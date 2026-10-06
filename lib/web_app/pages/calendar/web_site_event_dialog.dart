import 'package:flutter/material.dart';

import '../../../services/site_event_service.dart';
import '../../services/web_sites_service.dart';

class SiteEventDraft {
  const SiteEventDraft(
      {required this.title,
      required this.type,
      required this.start,
      required this.end,
      required this.allDay,
      required this.siteId,
      required this.description});

  final String title;
  final String type;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final String siteId;
  final String description;
}

class WebSiteEventDialog extends StatefulWidget {
  const WebSiteEventDialog(
      {super.key,
      required this.sites,
      this.initial,
      this.initialSiteId,
      this.initialDate});

  final List<WebSite> sites;
  final SiteEvent? initial;
  final String? initialSiteId;
  final DateTime? initialDate;

  @override
  State<WebSiteEventDialog> createState() => _WebSiteEventDialogState();
}

class _WebSiteEventDialogState extends State<WebSiteEventDialog> {
  final formKey = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.initial?.title ?? '');
  late final description =
      TextEditingController(text: widget.initial?.description ?? '');
  late String type = widget.initial?.type ?? 'meeting';
  late String siteId = widget.initial?.siteId ?? widget.initialSiteId ?? '';
  late bool allDay = widget.initial?.allDay ?? false;
  late DateTime day =
      widget.initial?.start ?? widget.initialDate ?? DateTime.now();
  late TimeOfDay time =
      TimeOfDay.fromDateTime(widget.initial?.start ?? DateTime.now());
  late DateTime? end = widget.initial?.end;

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  String dateText(DateTime date) => '${date.day}/${date.month}/${date.year}';

  DateTime get start => allDay
      ? DateTime.utc(day.year, day.month, day.day)
      : DateTime(day.year, day.month, day.day, time.hour, time.minute);

  Future<void> pickDate({bool ending = false}) async {
    final picked = await showDatePicker(
        context: context,
        initialDate: ending ? (end ?? day) : day,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (picked == null || !mounted) return;
    setState(() {
      if (ending) {
        end = allDay
            ? DateTime.utc(picked.year, picked.month, picked.day)
            : DateTime(picked.year, picked.month, picked.day,
                end?.hour ?? time.hour, end?.minute ?? time.minute);
      } else {
        day = picked;
      }
    });
  }

  Future<void> pickTime({bool ending = false}) async {
    final picked = await showTimePicker(
        context: context,
        initialTime:
            ending && end != null ? TimeOfDay.fromDateTime(end!) : time);
    if (picked == null || !mounted) return;
    setState(() {
      if (ending) {
        final date = end ?? day;
        end = DateTime(
            date.year, date.month, date.day, picked.hour, picked.minute);
      } else {
        time = picked;
      }
    });
  }

  void submit() {
    if (formKey.currentState?.validate() != true) return;
    if (end != null && end!.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End must be after start.')));
      return;
    }
    Navigator.pop(
        context,
        SiteEventDraft(
            title: title.text.trim(),
            type: type,
            start: start,
            end: end,
            allDay: allDay,
            siteId: siteId,
            description: description.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.initial == null ? 'Add event' : 'Edit event'),
        content: SizedBox(
            width: 480,
            child: Form(
                key: formKey,
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(
                      controller: title,
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: 'Title'),
                      validator: (value) =>
                          (value?.trim().isEmpty ?? true) ? 'Required' : null),
                  DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration:
                          const InputDecoration(labelText: 'Event type'),
                      items: [
                        for (final entry in siteEventTypes.entries)
                          DropdownMenuItem(
                              value: entry.key, child: Text(entry.value))
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => type = value);
                      }),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                      initialValue: siteId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Site'),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('Company-wide event')),
                        for (final site in widget.sites)
                          DropdownMenuItem(
                              value: site.id,
                              child: Text(site.name,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => siteId = value);
                      }),
                  SwitchListTile(
                      title: const Text('All day'),
                      value: allDay,
                      onChanged: (value) => setState(() {
                            allDay = value;
                            if (end != null) {
                              end = value
                                  ? DateTime.utc(
                                      end!.year, end!.month, end!.day)
                                  : DateTime(end!.year, end!.month, end!.day,
                                      time.hour, time.minute);
                            }
                          })),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton.icon(
                            onPressed: pickDate,
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text(dateText(day)))),
                    if (!allDay) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                          onPressed: pickTime,
                          child: Text(time.format(context))),
                    ],
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton.icon(
                            onPressed: () => pickDate(ending: true),
                            icon: const Icon(Icons.event_outlined),
                            label: Text(end == null
                                ? 'Optional end date'
                                : dateText(end!)))),
                    if (end != null) ...[
                      if (!allDay)
                        OutlinedButton(
                            onPressed: () => pickTime(ending: true),
                            child: Text(
                                TimeOfDay.fromDateTime(end!).format(context))),
                      IconButton(
                          tooltip: 'Clear end',
                          onPressed: () => setState(() => end = null),
                          icon: const Icon(Icons.close)),
                    ],
                  ]),
                  TextFormField(
                      controller: description,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Description (optional)')),
                ])))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: const Text('Save')),
        ],
      );
}
