import 'package:flutter/material.dart';

import '../theme/web_breakpoints.dart';
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
    required this.onNotifications,
    required this.onAccountDestination,
    required this.onProfile,
    required this.onSignOut,
    this.notificationCount = 0,
    this.chatCount = 0,
    this.applicationCount = 0,
    this.adminInboxCount = 0,
  });

  final WebSection selected;
  final ValueChanged<WebSection> onSelected;
  final String role;
  final Widget avatar;
  final VoidCallback onPostJob;
  final VoidCallback onNotifications;
  final ValueChanged<String> onAccountDestination;
  final VoidCallback onProfile;
  final VoidCallback onSignOut;
  final int notificationCount;
  final int chatCount;
  final int applicationCount;
  final int adminInboxCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WebTheme.deep,
      child: SizedBox(
        height: 84,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Image.network(
                  'stroyka_nav_banner.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerLeft,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: WebTheme.deep),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        WebTheme.deep.withValues(alpha: 0.22),
                        WebTheme.deep.withValues(alpha: 0.42),
                        WebTheme.deep.withValues(alpha: 0.58),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final showLabels =
                    WebBreakpoints.isLargeDesktop(constraints.maxWidth);
                final gutter = WebBreakpoints.gutter(constraints.maxWidth);
                final brandSpace = showLabels
                    ? 350.0
                    : constraints.maxWidth >= WebBreakpoints.desktop
                        ? 220.0
                        : constraints.maxWidth >= 640
                            ? 120.0
                            : 0.0;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: WebBreakpoints.desktopMaxWidth,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: gutter),
                      child: Row(
                        children: [
                          if (brandSpace > 0)
                            Semantics(
                              image: true,
                              label: 'STROYKA',
                              child: SizedBox(width: brandSpace),
                            ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: showLabels
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.center,
                              children: [
                                for (final section in WebSection.values)
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: constraints.maxWidth < 640
                                          ? 0
                                          : WebSpacing.xxs,
                                    ),
                                    child: _WebNavItem(
                                      section: section,
                                      selected: section == selected,
                                      showLabel: showLabels,
                                      onTap: () => onSelected(section),
                                      badgeCount: switch (section) {
                                        WebSection.applications =>
                                          applicationCount,
                                        WebSection.chats => chatCount,
                                        _ => 0,
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (role == 'employer') ...[
                            if (showLabels)
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFEAF5FC),
                                  foregroundColor: WebTheme.deep,
                                  overlayColor: const Color(0xFFD4EBF8),
                                ),
                                onPressed: onPostJob,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Post a job'),
                              )
                            else
                              IconButton(
                                tooltip: 'Post a job',
                                style: _headerIconButtonStyle(),
                                onPressed: onPostJob,
                                icon: const Icon(Icons.add_business_outlined),
                              ),
                            const SizedBox(width: WebSpacing.xs),
                          ],
                          IconButton(
                            tooltip: 'Notifications',
                            style: _headerIconButtonStyle(),
                            onPressed: onNotifications,
                            icon: Badge(
                              isLabelVisible: notificationCount > 0,
                              label: Text(_badgeLabel(notificationCount)),
                              child: const Icon(Icons.notifications_none),
                            ),
                          ),
                          const SizedBox(width: WebSpacing.xs),
                          _accountMenu(context),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Profile and account',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 250, maxWidth: 290),
      onSelected: (value) {
        if (value == 'profile') onProfile();
        if (value == 'signOut') onSignOut();
        if (value.startsWith('account:')) {
          onAccountDestination(value.substring('account:'.length));
        }
      },
      itemBuilder: (context) => [
        _MenuGroup('PROFILE'),
        const PopupMenuItem(
          value: 'profile',
          child: _MenuRow(Icons.account_circle_outlined, 'Profile'),
        ),
        const PopupMenuItem(
          value: 'account:account',
          child: _MenuRow(Icons.manage_accounts_outlined, 'My Account'),
        ),
        const PopupMenuDivider(),
        _MenuGroup('WORK'),
        if (role == 'worker')
          const PopupMenuItem(
            value: 'account:savedJobs',
            child: _MenuRow(Icons.favorite_border, 'Saved Jobs'),
          ),
        if (role == 'worker')
          const PopupMenuItem(
            value: 'account:subscriptions',
            child: _MenuRow(Icons.work_history_outlined, 'Job Subscriptions'),
          ),
        if (role == 'employer')
          const PopupMenuItem(
            value: 'account:billing',
            child: _MenuRow(
              Icons.receipt_long_outlined,
              'Billing / Subscription',
            ),
          ),
        const PopupMenuDivider(),
        _MenuGroup('COMMUNICATION'),
        PopupMenuItem(
          value: 'account:adminInbox',
          child: _MenuRow(
            Icons.mark_email_unread_outlined,
            'Inbox from Admin',
            badgeCount: adminInboxCount,
          ),
        ),
        const PopupMenuItem(
          value: 'account:support',
          child: _MenuRow(Icons.support_agent_outlined, 'Support'),
        ),
        const PopupMenuDivider(),
        _MenuGroup('SYSTEM'),
        const PopupMenuItem(
          value: 'account:settings',
          child: _MenuRow(Icons.settings_outlined, 'Settings'),
        ),
        const PopupMenuItem(
          value: 'account:about',
          child: _MenuRow(Icons.info_outline, 'About / Legal'),
        ),
        const PopupMenuDivider(),
        _MenuGroup('SESSION'),
        const PopupMenuItem(
          value: 'signOut',
          child: _MenuRow(Icons.logout, 'Sign out'),
        ),
        const PopupMenuItem(
          value: 'account:deleteAccount',
          child: _MenuRow(
            Icons.delete_forever_outlined,
            'Delete Account',
            destructive: true,
          ),
        ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: 'Open profile and account menu',
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.72),
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: avatar,
            ),
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
    required this.showLabel,
    required this.onTap,
    required this.badgeCount,
  });

  final WebSection section;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final content = InkWell(
      borderRadius: BorderRadius.circular(WebRadii.button),
      hoverColor: Colors.white.withValues(alpha: 0.12),
      splashColor: Colors.white.withValues(alpha: 0.14),
      onTap: onTap,
      child: Container(
        height: 48,
        padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 10),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(WebRadii.button),
          border: Border(
            bottom: BorderSide(
              color: selected ? const Color(0xFFBFE8FF) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: badgeCount > 0 && !showLabel,
              label: Text(_badgeLabel(badgeCount)),
              child: Icon(
                section.icon,
                size: 20,
                color: selected ? Colors.white : const Color(0xFFE4F2FA),
              ),
            ),
            if (showLabel) ...[
              const SizedBox(width: WebSpacing.xs),
              Text(
                section.label,
                style: WebTypography.button.copyWith(
                  color: selected ? Colors.white : const Color(0xFFE4F2FA),
                ),
              ),
              if (badgeCount > 0) ...[
                const SizedBox(width: WebSpacing.xs),
                Badge(label: Text(_badgeLabel(badgeCount))),
              ],
            ],
          ],
        ),
      ),
    );
    return Tooltip(message: section.label, child: content);
  }
}

class _MenuGroup extends PopupMenuItem<String> {
  _MenuGroup(String label)
      : super(
          enabled: false,
          height: 30,
          child: Text(
            label,
            style: const TextStyle(
              color: WebTheme.subtleText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(
    this.icon,
    this.label, {
    this.badgeCount = 0,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final int badgeCount;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? WebTheme.danger : WebTheme.ink;
    return Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: WebSpacing.sm),
        Expanded(child: Text(label, style: TextStyle(color: color))),
        if (badgeCount > 0) Badge(label: Text(_badgeLabel(badgeCount))),
      ],
    );
  }
}

String _badgeLabel(int count) => count > 99 ? '99+' : count.toString();

ButtonStyle _headerIconButtonStyle() => IconButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.transparent,
      hoverColor: Colors.white.withValues(alpha: 0.12),
      highlightColor: Colors.white.withValues(alpha: 0.14),
    );
