import 'package:flutter/material.dart';

import 'portrait_web_section.dart';

class PortraitWebNavigation extends StatelessWidget {
  const PortraitWebNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
    this.isEmployer = false,
    this.applicationCount = 0,
    this.chatCount = 0,
  });

  final PortraitWebSection selected;
  final ValueChanged<PortraitWebSection> onSelected;
  final bool isEmployer;
  final int applicationCount;
  final int chatCount;

  @override
  Widget build(BuildContext context) {
    final visible = PortraitWebSection.values
        .where((section) =>
            (section != PortraitWebSection.talent || isEmployer) &&
            (section != PortraitWebSection.sites || isEmployer) &&
            (section != PortraitWebSection.opportunities || !isEmployer))
        .toList();
    return NavigationBar(
      height: 68,
      selectedIndex: visible.indexOf(selected).clamp(0, visible.length - 1),
      onDestinationSelected: (index) => onSelected(visible[index]),
      destinations: [
        for (final section in visible)
          NavigationDestination(
            key: ValueKey('portrait-nav-${section.name}'),
            icon: Badge(
              isLabelVisible: _count(section) > 0,
              label: Text('${_count(section)}'),
              child: Icon(section.icon),
            ),
            label: section.label,
          ),
      ],
    );
  }

  int _count(PortraitWebSection section) => switch (section) {
        PortraitWebSection.applications => applicationCount,
        PortraitWebSection.chats => chatCount,
        _ => 0,
      };
}
