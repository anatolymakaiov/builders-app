import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/job_taxonomy_service.dart';
import '../theme/web_theme.dart';

class WebSmartJobSearchField extends StatefulWidget {
  const WebSmartJobSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search jobs, trades, companies',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  State<WebSmartJobSearchField> createState() => _WebSmartJobSearchFieldState();
}

class _WebSmartJobSearchFieldState extends State<WebSmartJobSearchField> {
  final FocusNode focusNode = FocusNode();

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<ConstructionRole>(
      textEditingController: widget.controller,
      focusNode: focusNode,
      displayStringForOption: (role) => role.canonical,
      optionsBuilder: (value) {
        final query = value.text.trim();
        if (query.isEmpty) return const Iterable<ConstructionRole>.empty();
        return JobTaxonomyService.suggestions(query, limit: 8);
      },
      onSelected: (role) {
        final value = role.canonical;
        widget.controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
        widget.onChanged(value);
      },
      fieldViewBuilder: (context, controller, focus, onSubmitted) => TextField(
        controller: controller,
        focusNode: focus,
        onChanged: widget.onChanged,
        onSubmitted: (_) => onSubmitted(),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: widget.hintText,
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) {
        final items = options.toList(growable: false);
        final width = math.min(360.0, MediaQuery.sizeOf(context).width - 32);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            color: WebTheme.surface,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final role = items[index];
                  final highlighted =
                      AutocompleteHighlightedOption.of(context) == index;
                  return ListTile(
                    dense: true,
                    selected: highlighted,
                    selectedTileColor: WebTheme.accentSoft,
                    leading: const Icon(Icons.work_outline, size: 19),
                    title: Text(role.canonical),
                    subtitle: role.category == role.canonical
                        ? null
                        : Text(role.category),
                    onTap: () => onSelected(role),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
