import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/job.dart';
import '../services/job_taxonomy_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class JobSearchFilters {
  final double distance;
  final double minPay;
  final double maxPay;
  final String city;
  final Set<String> employmentTypes;

  const JobSearchFilters({
    this.distance = 50,
    this.minPay = 0,
    this.maxPay = 50,
    this.city = "",
    this.employmentTypes = const {},
  });

  int get activeCount {
    var count = 0;
    if (city.trim().isNotEmpty) count++;
    if (city.trim().isNotEmpty && distance < 50) count++;
    if (minPay > 0 || maxPay < 50) count++;
    count += employmentTypes.length;
    return count;
  }

  JobSearchFilters copyWith({
    double? distance,
    double? minPay,
    double? maxPay,
    String? city,
    Set<String>? employmentTypes,
  }) {
    return JobSearchFilters(
      distance: distance ?? this.distance,
      minPay: minPay ?? this.minPay,
      maxPay: maxPay ?? this.maxPay,
      city: city ?? this.city,
      employmentTypes: employmentTypes ?? this.employmentTypes,
    );
  }
}

class SmartJobSearchValue {
  final List<ConstructionRole> roles;
  final String query;
  final JobSearchFilters filters;
  final bool showOnlyMyJobs;

  const SmartJobSearchValue({
    required this.roles,
    required this.query,
    required this.filters,
    this.showOnlyMyJobs = false,
  });
}

class SmartJobSearchField extends StatelessWidget {
  final List<ConstructionRole> selectedRoles;
  final String query;
  final JobSearchFilters filters;
  final List<Job> jobs;
  final ValueChanged<SmartJobSearchValue> onChanged;
  final String hintText;
  final bool showJobScopeToggle;
  final bool showJobScopeToggleInField;
  final bool showOnlyMyJobs;
  final String? currentUserId;

  const SmartJobSearchField({
    super.key,
    required this.selectedRoles,
    required this.query,
    required this.filters,
    required this.jobs,
    required this.onChanged,
    this.hintText = "Search position or company",
    this.showJobScopeToggle = false,
    bool? showJobScopeToggleInField,
    this.showOnlyMyJobs = false,
    this.currentUserId,
  }) : showJobScopeToggleInField =
            showJobScopeToggleInField ?? showJobScopeToggle;

  List<Job> _jobsForScope(bool onlyMine) {
    if (!onlyMine || currentUserId == null) return jobs;
    return jobs.where((job) => job.ownerId == currentUserId).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StroykaSurface(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          if (showJobScopeToggleInField) ...[
            JobScopeToggle(
              showOnlyMyJobs: showOnlyMyJobs,
              onChanged: (value) {
                onChanged(
                  SmartJobSearchValue(
                    roles: selectedRoles,
                    query: query,
                    filters: filters,
                    showOnlyMyJobs: value,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openSearch(context),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.search, color: AppColors.ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final role in selectedRoles)
                        _SearchChip(
                          label: role.canonical,
                          onDeleted: () {
                            final next = [...selectedRoles]..remove(role);
                            onChanged(
                              SmartJobSearchValue(
                                roles: next,
                                query: query,
                                filters: filters,
                                showOnlyMyJobs: showOnlyMyJobs,
                              ),
                            );
                          },
                        ),
                      if (selectedRoles.isEmpty && query.trim().isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Text(
                            hintText,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (query.trim().isNotEmpty)
                        _SearchChip(
                          label: query.trim(),
                          icon: Icons.business_outlined,
                          onDeleted: () {
                            onChanged(
                              SmartJobSearchValue(
                                roles: selectedRoles,
                                query: "",
                                filters: filters,
                                showOnlyMyJobs: showOnlyMyJobs,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                _FilterIconButton(
                  count: filters.activeCount,
                  onPressed: () => _openFilters(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    final result = await showModalBottomSheet<SmartJobSearchValue>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SmartSearchModal(
        initialRoles: selectedRoles,
        initialQuery: query,
        initialFilters: filters,
        jobs: jobs,
        showJobScopeToggle: showJobScopeToggle,
        showOnlyMyJobs: showOnlyMyJobs,
        currentUserId: currentUserId,
      ),
    );

    if (result != null) onChanged(result);
  }

  Future<void> _openFilters(BuildContext context) async {
    final result = await showModalBottomSheet<JobSearchFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SmartJobFilterSheet(
        current: filters,
        jobs: _jobsForScope(showOnlyMyJobs),
        resultCountBuilder: (next) =>
            _jobsForScope(showOnlyMyJobs).where((job) {
          return jobMatchesSearch(
            job,
            roles: selectedRoles,
            query: query,
            filters: next,
            originJobs: _jobsForScope(showOnlyMyJobs),
          );
        }).length,
      ),
    );

    if (result != null) {
      onChanged(
        SmartJobSearchValue(
          roles: selectedRoles,
          query: query,
          filters: result,
          showOnlyMyJobs: showOnlyMyJobs,
        ),
      );
    }
  }
}

class SmartRolePickerField extends StatefulWidget {
  final String initialValue;
  final ValueChanged<ConstructionRole> onSelected;
  final ValueChanged<String>? onChanged;
  final String labelText;
  final String hintText;
  final String helperText;

  const SmartRolePickerField({
    super.key,
    required this.initialValue,
    required this.onSelected,
    this.onChanged,
    this.labelText = "Trade / role",
    this.hintText = "Start typing, e.g. dry, fix, carp",
    this.helperText =
        "This field is important so workers can find your vacancy correctly.",
  });

  @override
  State<SmartRolePickerField> createState() => _SmartRolePickerFieldState();
}

class _SmartRolePickerFieldState extends State<SmartRolePickerField> {
  late final TextEditingController controller;
  final focusNode = FocusNode();
  List<ConstructionRole> suggestions = [];

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialValue);
    suggestions = JobTaxonomyService.suggestions(widget.initialValue, limit: 5);
    focusNode.addListener(_refresh);
  }

  @override
  void dispose() {
    focusNode.removeListener(_refresh);
    focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      suggestions = focusNode.hasFocus
          ? JobTaxonomyService.suggestions(controller.text, limit: 5)
          : const [];
    });
  }

  void _select(ConstructionRole role) {
    controller.text = role.canonical;
    widget.onSelected(role);
    focusNode.unfocus();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final showNoResults = focusNode.hasFocus &&
        controller.text.trim().isNotEmpty &&
        suggestions.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: AppInputFields.decoration(
            label: widget.labelText,
            hint: widget.hintText,
            icon: Icons.work_outline,
          ),
          onChanged: (value) {
            widget.onChanged?.call(value);
            _refresh();
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: suggestions.isEmpty
              ? const SizedBox.shrink()
              : _SuggestionPanel(
                  suggestions: suggestions,
                  onSelected: _select,
                ),
        ),
        if (showNoResults)
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4),
            child: Text(
              "Check spelling or try another trade",
              style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            widget.helperText,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SmartSearchModal extends StatefulWidget {
  final List<ConstructionRole> initialRoles;
  final String initialQuery;
  final JobSearchFilters initialFilters;
  final List<Job> jobs;
  final bool showJobScopeToggle;
  final bool showOnlyMyJobs;
  final String? currentUserId;

  const _SmartSearchModal({
    required this.initialRoles,
    required this.initialQuery,
    required this.initialFilters,
    required this.jobs,
    this.showJobScopeToggle = false,
    this.showOnlyMyJobs = false,
    this.currentUserId,
  });

  @override
  State<_SmartSearchModal> createState() => _SmartSearchModalState();
}

class _SmartSearchModalState extends State<_SmartSearchModal> {
  late final TextEditingController controller;
  late List<ConstructionRole> selectedRoles;
  late JobSearchFilters filters;
  late bool showOnlyMyJobs;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialQuery);
    selectedRoles = [...widget.initialRoles];
    filters = widget.initialFilters;
    showOnlyMyJobs = widget.showOnlyMyJobs;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  List<ConstructionRole> get suggestions {
    return JobTaxonomyService.suggestions(controller.text, limit: 5)
        .where(
          (role) => !selectedRoles.any(
            (selected) => selected.canonicalRoleId == role.canonicalRoleId,
          ),
        )
        .toList(growable: false);
  }

  List<Job> get scopedJobs {
    if (!showOnlyMyJobs || widget.currentUserId == null) return widget.jobs;
    return widget.jobs
        .where((job) => job.ownerId == widget.currentUserId)
        .toList();
  }

  int get resultCount => scopedJobs.where((job) {
        return jobMatchesSearch(
          job,
          roles: selectedRoles,
          query: controller.text,
          filters: filters,
          originJobs: scopedJobs,
        );
      }).length;

  void _select(ConstructionRole role) {
    setState(() {
      selectedRoles.add(role);
      controller.clear();
    });
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<JobSearchFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SmartJobFilterSheet(
        current: filters,
        jobs: scopedJobs,
        resultCountBuilder: (next) => scopedJobs.where((job) {
          return jobMatchesSearch(
            job,
            roles: selectedRoles,
            query: controller.text,
            filters: next,
            originJobs: scopedJobs,
          );
        }).length,
      ),
    );
    if (result != null && mounted) setState(() => filters = result);
  }

  @override
  Widget build(BuildContext context) {
    final noResults = controller.text.trim().isNotEmpty && suggestions.isEmpty;
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.88;
    final keyboardBottom = media.viewInsets.bottom;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardBottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Enter position or company you want to find",
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                if (widget.showJobScopeToggle) ...[
                  JobScopeToggle(
                    showOnlyMyJobs: showOnlyMyJobs,
                    onChanged: (value) =>
                        setState(() => showOnlyMyJobs = value),
                  ),
                  const SizedBox(height: 12),
                ],
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: AppInputFields.decoration(
                            hint: "Search role or company",
                            icon: Icons.search,
                          ).copyWith(
                            suffixIcon: _FilterIconButton(
                              count: filters.activeCount,
                              onPressed: _openFilters,
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (selectedRoles.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final role in selectedRoles)
                                _SearchChip(
                                  label: role.canonical,
                                  onDeleted: () => setState(
                                    () => selectedRoles.remove(role),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          child: suggestions.isEmpty
                              ? const SizedBox.shrink()
                              : _SuggestionPanel(
                                  suggestions: suggestions,
                                  onSelected: _select,
                                ),
                        ),
                        if (noResults)
                          const Padding(
                            padding: EdgeInsets.only(top: 8, left: 4),
                            child: Text(
                              "Check spelling or try another trade",
                              style: TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        SmartJobSearchValue(
                          roles: selectedRoles,
                          query: controller.text.trim(),
                          filters: filters,
                          showOnlyMyJobs: showOnlyMyJobs,
                        ),
                      );
                    },
                    child: Text("Show $resultCount jobs"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SmartJobFilterSheet extends StatefulWidget {
  final JobSearchFilters current;
  final List<Job> jobs;
  final int Function(JobSearchFilters filters) resultCountBuilder;

  const SmartJobFilterSheet({
    super.key,
    required this.current,
    required this.jobs,
    required this.resultCountBuilder,
  });

  @override
  State<SmartJobFilterSheet> createState() => _SmartJobFilterSheetState();
}

class _SmartJobFilterSheetState extends State<SmartJobFilterSheet> {
  late JobSearchFilters filters;
  late final TextEditingController cityController;

  @override
  void initState() {
    super.initState();
    filters = widget.current;
    cityController = TextEditingController(text: filters.city);
  }

  @override
  void dispose() {
    cityController.dispose();
    super.dispose();
  }

  void _setEmploymentType(String value, bool selected) {
    final next = {...filters.employmentTypes};
    if (selected) {
      next.add(value);
    } else {
      next.remove(value);
    }
    setState(() => filters = filters.copyWith(employmentTypes: next));
  }

  void _resetFilters() {
    cityController.clear();
    setState(() => filters = const JobSearchFilters());
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.resultCountBuilder(filters);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Filters",
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text("Reset"),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _FilterSection(
              title: "City",
              child: TextField(
                controller: cityController,
                decoration: AppInputFields.decoration(
                  hint: "City",
                  icon: Icons.location_city_outlined,
                ),
                onChanged: (value) {
                  setState(() => filters = filters.copyWith(city: value));
                },
              ),
            ),
            _FilterSection(
              title: "Distance from city",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${filters.distance.toInt()} miles"),
                  const SizedBox(height: 4),
                  Text(
                    filters.city.trim().isEmpty
                        ? "Enter a city first to use distance."
                        : "Radius from ${filters.city.trim()}",
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Slider(
                    min: 5,
                    max: 50,
                    divisions: 9,
                    value: filters.distance,
                    onChanged: (value) {
                      setState(
                        () => filters = filters.copyWith(distance: value),
                      );
                    },
                  ),
                ],
              ),
            ),
            _FilterSection(
              title: "Salary / Pay",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Select pay range per hour"),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 70,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _PayHistogramPainter(widget.jobs),
                    ),
                  ),
                  RangeSlider(
                    min: 0,
                    max: 50,
                    divisions: 50,
                    values: RangeValues(filters.minPay, filters.maxPay),
                    labels: RangeLabels(
                      "£${filters.minPay.toInt()}",
                      "£${filters.maxPay.toInt()}",
                    ),
                    onChanged: (values) {
                      setState(() {
                        filters = filters.copyWith(
                          minPay: values.start,
                          maxPay: values.end,
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
            _FilterSection(
              title: "Employment Type",
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  ("hourly", "Daywork"),
                  ("price", "Price Work"),
                  ("negotiable", "Negotiable"),
                ].map((item) {
                  return FilterChip(
                    label: Text(item.$2),
                    selected: filters.employmentTypes.contains(item.$1),
                    onSelected: (selected) =>
                        _setEmploymentType(item.$1, selected),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, filters),
                child: Text("Show $count jobs"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _FilterSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  final List<ConstructionRole> suggestions;
  final ValueChanged<ConstructionRole> onSelected;

  const _SuggestionPanel({
    required this.suggestions,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      constraints: BoxConstraints(
        maxHeight: (suggestions.length.clamp(1, 5) * 54).toDouble(),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.blueprintLine.withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: AppColors.blueprintLine.withValues(alpha: 0.08),
        ),
        itemBuilder: (context, index) {
          final role = suggestions[index];
          return ListTile(
            dense: true,
            title: Text(
              role.canonical,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(role.category),
            onTap: () => onSelected(role),
          );
        },
      ),
    );
  }
}

class _SearchChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onDeleted;

  const _SearchChip({
    required this.label,
    required this.onDeleted,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      avatar: icon == null ? null : Icon(icon, size: 16),
      onDeleted: onDeleted,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
      visualDensity: VisualDensity.compact,
    );
  }
}

class JobScopeToggle extends StatelessWidget {
  final bool showOnlyMyJobs;
  final ValueChanged<bool> onChanged;

  const JobScopeToggle({
    super.key,
    required this.showOnlyMyJobs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _JobScopeButton(
            label: "All jobs",
            selected: !showOnlyMyJobs,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _JobScopeButton(
            label: "My jobs",
            selected: showOnlyMyJobs,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _JobScopeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _JobScopeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.blueprintLine : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _FilterIconButton extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;

  const _FilterIconButton({
    required this.count,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: "Filters",
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count.toString()),
        child: const Icon(Icons.tune, color: AppColors.ink),
      ),
    );
  }
}

class _PayHistogramPainter extends CustomPainter {
  final List<Job> jobs;

  const _PayHistogramPainter(this.jobs);

  @override
  void paint(Canvas canvas, Size size) {
    final buckets = List<int>.filled(10, 0);
    for (final job in jobs) {
      if (job.jobType != "hourly" || job.rate <= 0) continue;
      final index = (job.rate.clamp(0, 49.99) / 5).floor();
      buckets[index]++;
    }

    final maxCount =
        buckets.fold<int>(1, (max, value) => value > max ? value : max);
    final barWidth = size.width / buckets.length;
    final paint = Paint()
      ..color = AppColors.blueprintLine.withValues(alpha: 0.55);

    for (var i = 0; i < buckets.length; i++) {
      final height = size.height * (buckets[i] / maxCount);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * barWidth + 3,
          size.height - height,
          barWidth - 6,
          height,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PayHistogramPainter oldDelegate) {
    return oldDelegate.jobs != jobs;
  }
}

bool jobMatchesSearch(
  Job job, {
  required List<ConstructionRole> roles,
  required String query,
  required JobSearchFilters filters,
  List<Job>? originJobs,
}) {
  if (!JobTaxonomyService.matchesAnyRole(job, roles)) return false;

  if (query.trim().isNotEmpty && !JobTaxonomyService.matchesJob(job, query)) {
    return false;
  }

  if (filters.employmentTypes.isNotEmpty &&
      !filters.employmentTypes.contains(job.jobType)) {
    return false;
  }

  final cityQuery = filters.city.trim();
  if (cityQuery.isNotEmpty) {
    final origin = _cityOrigin(cityQuery, originJobs ?? const <Job>[]);
    if (origin != null && _hasCoordinates(job)) {
      final distance = _distanceMiles(
        origin.lat,
        origin.lng,
        job.lat,
        job.lng,
      );
      if (distance > filters.distance) {
        return false;
      }
    } else if (!_jobMatchesCity(job, cityQuery)) {
      return false;
    }
  }

  if (job.jobType == "hourly" && job.rate > 0) {
    if (job.rate < filters.minPay || job.rate > filters.maxPay) {
      return false;
    }
  }

  return true;
}

({double lat, double lng})? _cityOrigin(String city, List<Job> jobs) {
  final matches = jobs.where((job) {
    return _jobMatchesCity(job, city) && _hasCoordinates(job);
  }).toList();

  if (matches.isEmpty) return null;

  final lat =
      matches.map((job) => job.lat).reduce((a, b) => a + b) / matches.length;
  final lng =
      matches.map((job) => job.lng).reduce((a, b) => a + b) / matches.length;
  return (lat: lat, lng: lng);
}

bool _jobMatchesCity(Job job, String city) {
  final query = city.toLowerCase().trim();
  if (query.isEmpty) return true;

  return [
    job.city,
    job.location,
    job.fullAddress,
    job.postcode,
  ].any((value) => value.toLowerCase().contains(query));
}

bool _hasCoordinates(Job job) {
  return job.lat != 0 && job.lng != 0;
}

double _distanceMiles(
  double startLat,
  double startLng,
  double endLat,
  double endLng,
) {
  const earthRadiusMiles = 3958.8;
  final dLat = _degreesToRadians(endLat - startLat);
  final dLng = _degreesToRadians(endLng - startLng);
  final a = _sinSquared(dLat / 2) +
      math.cos(_degreesToRadians(startLat)) *
          math.cos(_degreesToRadians(endLat)) *
          _sinSquared(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMiles * c;
}

double _degreesToRadians(double degrees) => degrees * 0.017453292519943295;

double _sinSquared(double value) {
  final sin = math.sin(value);
  return sin * sin;
}
