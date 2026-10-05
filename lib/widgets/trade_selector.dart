import 'package:flutter/material.dart';

import '../services/job_taxonomy_service.dart';

/// Shared worker trade picker for native and browser registration/profile UI.
class TradeSelector extends StatefulWidget {
  const TradeSelector({
    super.key,
    required this.tradeIds,
    required this.onChanged,
    this.legacyTrade = '',
  });

  final List<String> tradeIds;
  final ValueChanged<List<String>> onChanged;
  final String legacyTrade;

  @override
  State<TradeSelector> createState() => _TradeSelectorState();
}

class _TradeSelectorState extends State<TradeSelector> {
  TextEditingController? _searchController;

  @override
  Widget build(BuildContext context) {
    final selected = widget.tradeIds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected.isEmpty &&
            widget.legacyTrade.trim().isNotEmpty &&
            JobTaxonomyService.roleFor(widget.legacyTrade) == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Previous trade: ${widget.legacyTrade}. Select a catalog trade to update it.',
            ),
          ),
        if (selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final id in selected)
                  InputChip(
                    label: Text(JobTaxonomyService.roleFor(id)!.canonical),
                    onDeleted: () => widget.onChanged(
                      selected.where((item) => item != id).toList(),
                    ),
                  ),
              ],
            ),
          ),
        if (selected.length < 3)
          Autocomplete<ConstructionRole>(
            displayStringForOption: (role) => role.canonical,
            optionsBuilder: (value) => JobTaxonomyService.suggestions(
              value.text,
              limit: 12,
            ).where((role) => !selected.contains(role.id)),
            onSelected: (role) {
              widget.onChanged([...selected, role.id]);
              _searchController?.clear();
            },
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
              _searchController = controller;
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  labelText: selected.isEmpty ? 'Primary trade' : 'Add trade',
                  hintText: 'Search construction trades',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
              );
            },
          ),
      ],
    );
  }
}
