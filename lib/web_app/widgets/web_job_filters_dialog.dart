import 'package:flutter/material.dart';

import '../../services/job_taxonomy_service.dart';
import '../services/web_job_filters.dart';

class WebJobFiltersDialog extends StatefulWidget {
  const WebJobFiltersDialog(
      {super.key, required this.current, this.rolesOnly = false});
  final WebJobFilters current;
  final bool rolesOnly;

  @override
  State<WebJobFiltersDialog> createState() => _WebJobFiltersDialogState();
}

class _WebJobFiltersDialogState extends State<WebJobFiltersDialog> {
  late final city = TextEditingController(text: widget.current.city);
  late final roles = [...widget.current.roles];
  late final types = {...widget.current.employmentTypes};
  late double distance = widget.current.distance;
  late RangeValues pay =
      RangeValues(widget.current.minPay, widget.current.maxPay);

  @override
  void dispose() {
    city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Filters'),
        content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Autocomplete<ConstructionRole>(
                  displayStringForOption: (role) => role.canonical,
                  optionsBuilder: (value) =>
                      JobTaxonomyService.suggestions(value.text),
                  onSelected: (role) => setState(() {
                    if (!roles.contains(role)) roles.add(role);
                  }),
                  fieldViewBuilder: (context, controller, focus, submit) =>
                      TextField(
                    controller: controller,
                    focusNode: focus,
                    decoration: const InputDecoration(
                        labelText: 'Trade / position',
                        suffixIcon: Icon(Icons.search)),
                  ),
                ),
                Wrap(
                    spacing: 6,
                    children: roles
                        .map((role) => InputChip(
                            label: Text(role.canonical),
                            onDeleted: () =>
                                setState(() => roles.remove(role))))
                        .toList()),
                if (!widget.rolesOnly) ...[
                  TextField(
                      controller: city,
                      decoration: const InputDecoration(labelText: 'City')),
                  const SizedBox(height: 12),
                  Text('Distance from city: ${distance.toInt()} miles'),
                  Slider(
                      min: 5,
                      max: 50,
                      divisions: 9,
                      value: distance,
                      onChanged: (value) => setState(() => distance = value)),
                  Text(
                      'Hourly pay: GBP ${pay.start.toInt()} - ${pay.end.toInt()}'),
                  RangeSlider(
                      min: 0,
                      max: 50,
                      divisions: 50,
                      values: pay,
                      onChanged: (value) => setState(() => pay = value)),
                  Wrap(
                      spacing: 8,
                      children: const {
                        'hourly': 'Daywork',
                        'price': 'Price work',
                        'negotiable': 'Negotiable'
                      }
                          .entries
                          .map((entry) => FilterChip(
                              label: Text(entry.value),
                              selected: types.contains(entry.key),
                              onSelected: (selected) => setState(() {
                                    selected
                                        ? types.add(entry.key)
                                        : types.remove(entry.key);
                                  })))
                          .toList()),
                ],
              ],
            ))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, const WebJobFilters()),
              child: const Text('Reset')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context,
                  WebJobFilters(
                      roles: roles,
                      city: city.text,
                      distance: distance,
                      minPay: pay.start,
                      maxPay: pay.end,
                      employmentTypes: types)),
              child: const Text('Apply filters')),
        ],
      );
}
