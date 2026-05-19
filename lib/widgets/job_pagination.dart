import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class JobPagination extends StatelessWidget {
  final int currentPage;
  final int totalItems;
  final int itemsPerPage;
  final ValueChanged<int> onPageChanged;

  const JobPagination({
    super.key,
    required this.currentPage,
    required this.totalItems,
    required this.itemsPerPage,
    required this.onPageChanged,
  });

  int get totalPages => (totalItems / itemsPerPage).ceil();

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();

    final pages = _visiblePages();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _NavButton(
                label: "Previous",
                enabled: currentPage > 1,
                onTap: () => onPageChanged(currentPage - 1),
              ),
              const SizedBox(width: 6),
              for (final page in pages) ...[
                if (page == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      "...",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  _PageButton(
                    page: page,
                    selected: page == currentPage,
                    onTap: () => onPageChanged(page),
                  ),
                const SizedBox(width: 6),
              ],
              _NavButton(
                label: "Next",
                enabled: currentPage < totalPages,
                onTap: () => onPageChanged(currentPage + 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<int?> _visiblePages() {
    if (totalPages <= 7) {
      return List<int>.generate(totalPages, (index) => index + 1);
    }

    final pages = <int?>[1];
    final start = (currentPage - 2).clamp(2, totalPages - 4);
    final end = (currentPage + 2).clamp(5, totalPages - 1);

    if (start > 2) pages.add(null);
    for (var page = start; page <= end; page++) {
      pages.add(page);
    }
    if (end < totalPages - 1) pages.add(null);
    pages.add(totalPages);
    return pages;
  }
}

class _PageButton extends StatelessWidget {
  final int page;
  final bool selected;
  final VoidCallback onTap;

  const _PageButton({
    required this.page,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 38),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.blueprintLine.withValues(alpha: 0.22)
              : AppColors.deep.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.blueprintLine
                : AppColors.blueprintLine.withValues(alpha: 0.42),
          ),
        ),
        child: Text(
          "$page",
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _NavButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.deep.withValues(alpha: enabled ? 0.72 : 0.34),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.blueprintLine.withValues(
              alpha: enabled ? 0.42 : 0.16,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: enabled ? 1 : 0.42),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
