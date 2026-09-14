import 'package:flutter/material.dart';

import '../../services/web_account_data_service.dart';
import '../../services/web_data_state.dart';
import '../../theme/web_theme.dart';
import '../../theme/web_breakpoints.dart';
import '../../widgets/web_design_components.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';

class WebNotificationsPage extends StatefulWidget {
  const WebNotificationsPage({
    super.key,
    required this.userId,
    required this.role,
    required this.onClose,
    required this.onRoute,
  });

  final String userId;
  final String role;
  final VoidCallback onClose;
  final void Function(WebNotificationItem notification) onRoute;

  @override
  State<WebNotificationsPage> createState() => _WebNotificationsPageState();
}

class _WebNotificationsPageState extends State<WebNotificationsPage> {
  final service = WebAccountDataService();
  late Stream<WebDataState<List<WebNotificationItem>>> stream;
  WebNotificationItem? selected;
  bool markingAll = false;
  bool compactDetailVisible = false;

  @override
  void initState() {
    super.initState();
    stream = service.poll(
      () => service.loadNotifications(widget.userId),
      empty: const <WebNotificationItem>[],
      logPrefix: 'WEB NOTIFICATIONS LOAD ERROR',
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebPageContainer(
      child: StreamBuilder<WebDataState<List<WebNotificationItem>>>(
        stream: stream,
        builder: (context, snapshot) {
          final state = snapshot.data;
          final notifications = state?.data ?? const <WebNotificationItem>[];
          selected ??= notifications.isEmpty ? null : notifications.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                title: 'Notifications',
                onClose: widget.onClose,
                action: notifications.any((item) => !item.read)
                    ? OutlinedButton.icon(
                        onPressed: markingAll ? null : _markAllRead,
                        icon: markingAll
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.done_all),
                        label: const Text('Mark all as read'),
                      )
                    : null,
              ),
              if (state?.error != null)
                const _ErrorBanner(
                  message: 'Could not refresh notifications.',
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < WebBreakpoints.compactWidth;
                    final list = WebPanel(
                      padding: EdgeInsets.zero,
                      child: _NotificationList(
                        loading: state == null || state.loading,
                        notifications: notifications,
                        selectedId: selected?.id,
                        onSelected: _openNotification,
                      ),
                    );
                    final detail = WebPanel(
                      child: selected == null
                          ? const WebEmptyState(
                              icon: Icons.notifications_none,
                              title: 'No notifications yet',
                            )
                          : _NotificationDetail(
                              notification: selected!,
                              onOpen: () => _routeSelected(selected!),
                            ),
                    );
                    if (compact) {
                      return WebCompactDetailView(
                        showDetail: compactDetailVisible && selected != null,
                        list: list,
                        detail: detail,
                        onBack: () => setState(
                          () => compactDetailVisible = false,
                        ),
                        backLabel: 'Back to notifications',
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(
                          width: WebBreakpoints.masterPaneWidth(
                            constraints.maxWidth,
                          ),
                          child: list,
                        ),
                        const SizedBox(width: WebSpacing.lg),
                        Expanded(child: detail),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openNotification(WebNotificationItem item) async {
    setState(() {
      selected = item;
      compactDetailVisible = true;
    });
    if (!item.read) {
      await service.markNotificationRead(widget.userId, item.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _routeSelected(WebNotificationItem item) async {
    if (!item.read) {
      await service.markNotificationRead(widget.userId, item.id);
    }
    if (!mounted) return;
    widget.onRoute(item);
  }

  Future<void> _markAllRead() async {
    setState(() => markingAll = true);
    try {
      await service.markAllNotificationsRead(widget.userId);
      stream = service.poll(
        () => service.loadNotifications(widget.userId),
        empty: const <WebNotificationItem>[],
      );
    } finally {
      if (mounted) setState(() => markingAll = false);
    }
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.loading,
    required this.notifications,
    required this.selectedId,
    required this.onSelected,
  });

  final bool loading;
  final List<WebNotificationItem> notifications;
  final String? selectedId;
  final ValueChanged<WebNotificationItem> onSelected;

  @override
  Widget build(BuildContext context) {
    if (loading && notifications.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (notifications.isEmpty) {
      return const Center(child: Text('No notifications yet'));
    }
    return ListView.separated(
      itemCount: notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = notifications[index];
        final selected = item.id == selectedId;
        return ListTile(
          selected: selected,
          selectedTileColor: WebTheme.greenSoft,
          leading: Icon(_iconFor(item), color: WebTheme.green),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: item.read ? FontWeight.w600 : FontWeight.w900,
            ),
          ),
          subtitle: Text(
            item.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: item.read
              ? null
              : const Icon(Icons.circle, size: 10, color: WebTheme.green),
          onTap: () => onSelected(item),
        );
      },
    );
  }

  IconData _iconFor(WebNotificationItem item) {
    final type = item.type;
    if (type.contains('offer')) return Icons.local_offer_outlined;
    if (type.contains('message')) return Icons.chat_bubble_outline;
    if (type.contains('application') || type == 'accepted') {
      return Icons.assignment_outlined;
    }
    if (type.contains('billing')) return Icons.receipt_long_outlined;
    if (type.contains('job')) return Icons.work_outline;
    if (type.contains('admin')) return Icons.admin_panel_settings_outlined;
    return Icons.notifications_none;
  }
}

class _NotificationDetail extends StatelessWidget {
  const _NotificationDetail({
    required this.notification,
    required this.onOpen,
  });

  final WebNotificationItem notification;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final created = notification.createdAt?.toDate();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                notification.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open'),
            ),
          ],
        ),
        if (created != null) ...[
          const SizedBox(height: 8),
          Text(_formatDate(created)),
        ],
        const SizedBox(height: 18),
        Text(notification.body.isEmpty
            ? 'No details provided.'
            : notification.body),
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Meta('Type', notification.type),
            _Meta('Category', notification.category),
            if (notification.data['targetType'] != null)
              _Meta('Target', notification.data['targetType'].toString()),
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onClose,
    this.action,
  });

  final String title;
  final VoidCallback onClose;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return WebPageHeader(
      title: title,
      subtitle: 'Updates about applications, offers, work and your account.',
      leading: IconButton(
        tooltip: 'Back',
        onPressed: onClose,
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [if (action != null) action!],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: ${value.isEmpty ? 'n/a' : value}'),
      backgroundColor: WebTheme.surfaceAlt,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message),
    );
  }
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${two(value.day)} ${months[value.month - 1]} ${value.year}, '
      '${two(value.hour)}:${two(value.minute)}';
}
