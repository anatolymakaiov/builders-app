import 'package:flutter/material.dart';

import '../theme/web_theme.dart';

enum WebSection {
  jobs('Jobs', Icons.work_outline),
  map('Map', Icons.map_outlined),
  applications('Applications', Icons.assignment_outlined),
  chats('Chats', Icons.chat_bubble_outline);

  const WebSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class WebTopNavigation extends StatelessWidget {
  const WebTopNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.role,
    required this.avatar,
    required this.onPostJob,
    required this.onProfile,
    required this.onSignOut,
  });

  final WebSection selected;
  final ValueChanged<WebSection> onSelected;
  final String role;
  final Widget avatar;
  final VoidCallback onPostJob;
  final VoidCallback onProfile;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WebTheme.surface,
      elevation: 0,
      child: Container(
        height: 72,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: WebTheme.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            children: [
              const Text(
                'STROYKA',
                style: TextStyle(
                  color: WebTheme.deep,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: 42),
              for (final section in WebSection.values) ...[
                _WebNavItem(
                  section: section,
                  selected: section == selected,
                  onTap: () => onSelected(section),
                ),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              if (role == 'employer') ...[
                FilledButton.icon(
                  onPressed: onPostJob,
                  icon: const Icon(Icons.add),
                  label: const Text('Post a job'),
                ),
                const SizedBox(width: 14),
              ],
              IconButton(
                tooltip: 'Notifications',
                onPressed: () {},
                icon: const Icon(Icons.notifications_none),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Profile menu',
                onSelected: (value) {
                  if (value == 'profile') onProfile();
                  if (value == 'signOut') onSignOut();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'profile',
                    child: Text('Profile'),
                  ),
                  PopupMenuItem(
                    value: 'signOut',
                    child: Text('Sign out'),
                  ),
                ],
                child: avatar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebNavItem extends StatelessWidget {
  const _WebNavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final WebSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? WebTheme.greenSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: selected ? Border.all(color: WebTheme.green) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              section.icon,
              size: 18,
              color: selected ? WebTheme.green : WebTheme.muted,
            ),
            const SizedBox(width: 8),
            Text(
              section.label,
              style: TextStyle(
                color: selected ? WebTheme.green : WebTheme.ink,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
