import '../../services/web_support_attachments.dart';
import '../../services/web_chat_media_service.dart';
import '../../services/web_admin_inbox_media_service.dart';
import '../chats/web_chat_media_widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/account_deletion_service.dart';
import '../../../services/address_lookup_service.dart';
import '../../../services/billing_service.dart';
import '../../../services/job_taxonomy_service.dart';
import '../../services/web_account_data_service.dart';
import '../../services/web_data_state.dart';
import '../../services/web_role_identity_service.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';
import '../../widgets/web_design_components.dart';
import '../../theme/web_breakpoints.dart';

enum WebAccountDestination {
  account('My Account', Icons.account_circle_outlined),
  billing('Billing / Subscription', Icons.receipt_long_outlined),
  adminInbox('Inbox from Admin', Icons.mark_email_unread_outlined),
  subscriptions('Job Subscriptions', Icons.work_history_outlined),
  settings('Settings', Icons.settings_outlined),
  support('Support', Icons.support_agent_outlined),
  about('About / Legal', Icons.info_outline),
  deleteAccount('Delete Account', Icons.delete_forever_outlined);

  const WebAccountDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}

class WebAccountPage extends StatefulWidget {
  const WebAccountPage({
    super.key,
    required this.user,
    required this.role,
    required this.profile,
    required this.initialDestination,
    required this.onClose,
    required this.onSignedOut,
  });

  final User user;
  final String role;
  final Map<String, dynamic> profile;
  final WebAccountDestination initialDestination;
  final VoidCallback onClose;
  final VoidCallback onSignedOut;

  @override
  State<WebAccountPage> createState() => _WebAccountPageState();
}

class _WebAccountPageState extends State<WebAccountPage> {
  final service = WebAccountDataService();
  final identityResolver = WebRoleIdentityResolver();
  late WebAccountDestination selected = widget.initialDestination;
  WebRoleIdentity? identity;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  @override
  void didUpdateWidget(covariant WebAccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDestination != widget.initialDestination) {
      selected = widget.initialDestination;
    }
    if (oldWidget.user.uid != widget.user.uid ||
        oldWidget.role != widget.role) {
      _loadIdentity();
    }
  }

  Future<void> _loadIdentity() async {
    final resolved = await identityResolver.resolve(
      userId: widget.user.uid,
      role: widget.role,
      profile: widget.profile,
    );
    if (mounted) setState(() => identity = resolved);
  }

  @override
  Widget build(BuildContext context) {
    return WebPageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(title: selected.label, onClose: widget.onClose),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < WebBreakpoints.compactWidth;
                final navigation = WebPanel(
                  padding: EdgeInsets.zero,
                  child: ListView(
                    children: [
                      if (identity != null) _IdentityTile(identity: identity!),
                      const Divider(height: 1),
                      const _AccountGroupLabel('PROFILE'),
                      _accountDestination(WebAccountDestination.account),
                      const _AccountGroupLabel('WORK'),
                      if (widget.role == 'employer')
                        _accountDestination(WebAccountDestination.billing),
                      if (widget.role == 'worker')
                        _accountDestination(
                          WebAccountDestination.subscriptions,
                        ),
                      const _AccountGroupLabel('COMMUNICATION'),
                      _accountDestination(WebAccountDestination.adminInbox),
                      _accountDestination(WebAccountDestination.support),
                      const _AccountGroupLabel('SYSTEM'),
                      _accountDestination(WebAccountDestination.settings),
                      _accountDestination(WebAccountDestination.about),
                      const _AccountGroupLabel('SESSION'),
                      _accountDestination(
                        WebAccountDestination.deleteAccount,
                        destructive: true,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: const Text(
                          'Logout',
                          style: TextStyle(color: Colors.red),
                        ),
                        onTap: _logout,
                      ),
                    ],
                  ),
                );
                final content = WebPanel(child: _content());
                if (compact) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child:
                                DropdownButtonFormField<WebAccountDestination>(
                              key: ValueKey(selected),
                              initialValue: selected,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Account section',
                              ),
                              items: _availableDestinations()
                                  .map(
                                    (destination) => DropdownMenuItem(
                                      value: destination,
                                      child: Text(
                                        destination.label,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: destination ==
                                                  WebAccountDestination
                                                      .deleteAccount
                                              ? WebTheme.danger
                                              : null,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (destination) {
                                if (destination != null) {
                                  setState(() => selected = destination);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: WebSpacing.sm),
                          IconButton(
                            tooltip: 'Logout',
                            onPressed: _logout,
                            icon: const Icon(
                              Icons.logout,
                              color: WebTheme.danger,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: WebSpacing.md),
                      Expanded(child: content),
                    ],
                  );
                }
                return Row(
                  children: [
                    SizedBox(width: 280, child: navigation),
                    const SizedBox(width: WebSpacing.lg),
                    Expanded(child: content),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountDestination(
    WebAccountDestination destination, {
    bool destructive = false,
  }) {
    final color = destructive ? WebTheme.danger : null;
    return ListTile(
      leading: Icon(destination.icon, color: color),
      selected: destination == selected,
      selectedTileColor: WebTheme.selected,
      title: Text(destination.label, style: TextStyle(color: color)),
      onTap: () => setState(() => selected = destination),
    );
  }

  List<WebAccountDestination> _availableDestinations() => [
        WebAccountDestination.account,
        if (widget.role == 'employer') WebAccountDestination.billing,
        if (widget.role == 'worker') WebAccountDestination.subscriptions,
        WebAccountDestination.adminInbox,
        WebAccountDestination.support,
        WebAccountDestination.settings,
        WebAccountDestination.about,
        WebAccountDestination.deleteAccount,
      ];

  Widget _content() {
    return switch (selected) {
      WebAccountDestination.account => _MyAccountView(
          user: widget.user,
          role: widget.role,
          identity: identity,
          profile: widget.profile,
        ),
      WebAccountDestination.billing => _BillingView(profile: widget.profile),
      WebAccountDestination.adminInbox => _AdminInboxView(
          userId: widget.user.uid,
          role: widget.role,
          senderName: identity?.displayName ?? 'User',
        ),
      WebAccountDestination.subscriptions => _SubscriptionsView(
          userId: widget.user.uid,
        ),
      WebAccountDestination.settings => _SettingsView(
          userId: widget.user.uid,
          profile: widget.profile,
        ),
      WebAccountDestination.support => _SupportView(
          userId: widget.user.uid,
          role: widget.role,
          userData: widget.profile,
        ),
      WebAccountDestination.about => const _AboutLegalView(),
      WebAccountDestination.deleteAccount => _DeleteAccountView(
          onDeleted: widget.onSignedOut,
        ),
    };
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    widget.onSignedOut();
  }
}

class _MyAccountView extends StatelessWidget {
  const _MyAccountView({
    required this.user,
    required this.role,
    required this.identity,
    required this.profile,
  });

  final User user;
  final String role;
  final WebRoleIdentity? identity;
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final billing = BillingService.billingFromUserData(profile);
    return ListView(
      children: [
        Text(
          role == 'employer' ? 'Employer account' : 'Worker account',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 18),
        _InfoRow('Account type', role == 'employer' ? 'Employer' : 'Worker'),
        _InfoRow(role == 'employer' ? 'Company name' : 'Name',
            identity?.displayName ?? ''),
        _InfoRow('Email', user.email ?? profile['email']?.toString() ?? ''),
        if (role == 'worker')
          _InfoRow('Trade / position', identity?.subtitle ?? ''),
        if (role == 'employer') ...[
          _InfoRow('Company type', identity?.subtitle ?? ''),
          const SizedBox(height: 16),
          Text('Billing summary',
              style: Theme.of(context).textTheme.titleLarge),
          _InfoRow(
              'Current plan',
              (billing['planName'] ?? billing['activePlanName'] ?? '')
                  .toString()),
          _InfoRow(
            'Plan status',
            BillingService.formatLabel(
              (billing['status'] ?? billing['billingPlanStatus'] ?? 'not_set')
                  .toString(),
            ),
          ),
          _InfoRow(
            'Payment method',
            BillingService.formatLabel(
              (billing['paymentMethod'] ?? billing['paymentMode'] ?? 'not_set')
                  .toString(),
            ),
          ),
        ],
      ],
    );
  }
}

class _BillingView extends StatefulWidget {
  const _BillingView({required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<_BillingView> createState() => _BillingViewState();
}

class _BillingViewState extends State<_BillingView> {
  final service = WebAccountDataService();
  Map<String, dynamic>? overrideBilling;
  bool busy = false;
  String? changingPlan;

  Map<String, dynamic> get billing =>
      overrideBilling ?? BillingService.billingFromUserData(widget.profile);

  @override
  Widget build(BuildContext context) {
    final configured = BillingService.isDirectDebitConfigured(billing);
    final plans = BillingService.plansFromBilling(billing);
    final currentPlan = BillingService.currentPlanId(billing);
    return ListView(
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Billing / Subscription',
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
            WebStatusChip(
              label: configured ? 'Direct Debit active' : 'Setup required',
              tone: configured ? WebStatusTone.success : WebStatusTone.warning,
            ),
            const SizedBox(width: WebSpacing.sm),
            OutlinedButton.icon(
              onPressed: busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _InfoRow(
            'Current plan',
            (billing['planName'] ?? billing['activePlanName'] ?? currentPlan)
                .toString()),
        _InfoRow(
          'Monthly price',
          _priceLabel(billing['planAmountPence'] ?? billing['monthlyPrice']),
        ),
        _InfoRow(
            'Vacancy slot limit',
            (billing['vacancySlotLimit'] ?? billing['includedJobSlots'] ?? '')
                .toString()),
        _InfoRow('Direct Debit', configured ? 'Active' : 'Set up'),
        _InfoRow(
          'Trial status',
          BillingService.formatLabel((billing['trialStatus'] ?? '').toString()),
        ),
        _InfoRow(
            'Trial end date',
            BillingService.formatDate(
                billing['trialEndsAt'] ?? billing['trialEndDate'])),
        _InfoRow('First payment date',
            BillingService.formatDate(billing['firstPaymentDate'])),
        const SizedBox(height: 18),
        if (!configured)
          FilledButton.icon(
            onPressed: busy ? null : () => _startSetup(currentPlan),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Set up Direct Debit'),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => _startSetup(currentPlan),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Replace Direct Debit'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : _cancelSubscription,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel Direct Debit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: WebTheme.danger,
                  side: const BorderSide(color: WebTheme.danger),
                ),
              ),
            ],
          ),
        const SizedBox(height: 24),
        Text('Change plan', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final plan in plans)
              _PlanCard(
                plan: plan,
                selected: (plan['id'] ?? '').toString() == currentPlan,
                busy: busy || changingPlan != null,
                onTap: () => _changePlan((plan['id'] ?? '').toString()),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _refresh() async {
    setState(() => busy = true);
    try {
      overrideBilling = await service.loadBillingStatus();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _startSetup(String planId) async {
    setState(() => busy = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createGoCardlessDirectDebitSetup')
          .call({'planId': planId.isEmpty ? 'starter' : planId});
      final data = result.data;
      final url = data is Map ? data['authorisationUrl']?.toString() : null;
      if (url == null || url.isEmpty) throw StateError('missing_url');
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _changePlan(String planId) async {
    if (planId.isEmpty) return;
    setState(() => changingPlan = planId);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('changeGoCardlessPlan')
          .call({'planId': planId});
      if (result.data is Map) {
        overrideBilling = Map<String, dynamic>.from(result.data as Map);
      }
    } finally {
      if (mounted) setState(() => changingPlan = null);
    }
  }

  Future<void> _cancelSubscription() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel subscription?'),
        content: const Text(
          'New vacancy publishing will pause while Direct Debit is restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => busy = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('cancelGoCardlessSubscription')
          .call();
      if (result.data is Map) {
        overrideBilling = Map<String, dynamic>.from(result.data as Map);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _priceLabel(dynamic value) {
    final amount = BillingService.readInt(value);
    if (amount <= 0) return '';
    return 'GBP ${(amount / 100).toStringAsFixed(0)}/month';
  }
}

class _AdminInboxView extends StatefulWidget {
  const _AdminInboxView({
    required this.userId,
    required this.role,
    required this.senderName,
  });

  final String userId;
  final String role;
  final String senderName;

  @override
  State<_AdminInboxView> createState() => _AdminInboxViewState();
}

class _AdminInboxViewState extends State<_AdminInboxView> {
  final service = WebAccountDataService();
  final mediaService = WebAdminInboxMediaService();
  final replyController = TextEditingController();
  final pendingAttachments = <WebPendingChatAttachment>[];
  late Stream<WebDataState<List<WebAdminMessageThread>>> stream;
  WebAdminMessageThread? selected;
  bool compactDetailVisible = false;
  bool sending = false;
  bool actionBusy = false;

  @override
  void initState() {
    super.initState();
    stream = _stream();
  }

  @override
  void dispose() {
    replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebDataState<List<WebAdminMessageThread>>>(
      stream: stream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final threads = state?.data ?? const <WebAdminMessageThread>[];
        final selectedKey = selected?.key;
        selected = selectedKey == null
            ? null
            : threads.cast<WebAdminMessageThread?>().firstWhere(
                  (thread) => thread?.key == selectedKey,
                  orElse: () => null,
                );
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < WebBreakpoints.narrow;
            final list = _ThreadList(
              loading: state == null || state.loading,
              threads: threads,
              selectedKey: selected?.key,
              onSelected: _selectThread,
            );
            final detail = selected == null
                ? WebEmptyState(
                    icon: Icons.mark_email_unread_outlined,
                    title: threads.isEmpty
                        ? 'No admin messages yet'
                        : 'Select a message',
                  )
                : _AdminThreadDetail(
                    thread: selected!,
                    controller: replyController,
                    sending: sending || actionBusy,
                    pendingAttachments: pendingAttachments,
                    onAttach: _pickAttachments,
                    onRemoveAttachment: (index) => setState(
                      () => pendingAttachments.removeAt(index),
                    ),
                    onSend: _sendReply,
                    onToggleImportant: _toggleImportant,
                    onToggleRead: _toggleRead,
                    onDelete: _deleteThread,
                  );
            if (compact) {
              return WebCompactDetailView(
                showDetail: compactDetailVisible && selected != null,
                list: list,
                detail: detail,
                onBack: () => setState(() => compactDetailVisible = false),
                backLabel: 'Back to Admin Inbox',
              );
            }
            return Row(
              children: [
                SizedBox(width: 340, child: list),
                const VerticalDivider(width: WebSpacing.lg),
                Expanded(child: detail),
              ],
            );
          },
        );
      },
    );
  }

  Stream<WebDataState<List<WebAdminMessageThread>>> _stream() {
    return service.poll(
      () => service.loadAdminInbox(widget.userId),
      empty: const <WebAdminMessageThread>[],
      logPrefix: 'WEB ADMIN INBOX LOAD ERROR',
    );
  }

  Future<void> _selectThread(WebAdminMessageThread thread) async {
    setState(() {
      selected = thread;
      compactDetailVisible = true;
      replyController.clear();
      pendingAttachments.clear();
    });
    try {
      await service.markAdminThreadRead(widget.userId, thread);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mark message read: $error')),
        );
      }
    }
  }

  Future<void> _sendReply() async {
    final thread = selected;
    if (thread == null || sending) return;
    if (replyController.text.trim().isEmpty && pendingAttachments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write a message or attach a file.')),
      );
      return;
    }
    setState(() => sending = true);
    try {
      final attachments = await mediaService.upload(
        uid: widget.userId,
        attachments: List.of(pendingAttachments),
      );
      await service.replyToAdminThread(
        uid: widget.userId,
        role: widget.role,
        thread: thread,
        message: replyController.text,
        senderName: widget.senderName,
        attachments: attachments,
      );
      if (!mounted) return;
      replyController.clear();
      pendingAttachments.clear();
      setState(() => stream = _stream());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send reply: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _pickAttachments() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final picked = await mediaService.pickAttachments();
      if (!mounted) return;
      final existing = pendingAttachments
          .map((item) => '${item.fileName}:${item.sizeBytes}')
          .toSet();
      setState(() => pendingAttachments.addAll(picked.where(
            (item) => existing.add('${item.fileName}:${item.sizeBytes}'),
          )));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not select attachments: $error')),
        );
      }
    }
  }

  Future<void> _toggleImportant() async {
    final thread = selected;
    if (thread == null || actionBusy) return;
    await _runAction(() => service.toggleAdminMessageImportant(
          thread.latest,
          thread.important,
        ));
  }

  Future<void> _toggleRead() async {
    final thread = selected;
    if (thread == null || actionBusy) return;
    await _runAction(() => thread.unread
        ? service.markAdminThreadRead(widget.userId, thread)
        : service.markAdminMessageUnread(thread.latest));
  }

  Future<void> _deleteThread() async {
    final thread = selected;
    if (thread == null || actionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runAction(() => service.deleteAdminThread(widget.userId, thread),
        clearSelection: true);
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    bool clearSelection = false,
  }) async {
    setState(() => actionBusy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() {
        if (clearSelection) selected = null;
        stream = _stream();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update message: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }
}

class _SubscriptionsView extends StatefulWidget {
  const _SubscriptionsView({required this.userId});

  final String userId;

  @override
  State<_SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends State<_SubscriptionsView> {
  final service = WebAccountDataService();
  final postcodeLookup = IdealPostcodesAddressLookupService();
  final postcode = TextEditingController();
  String trade = 'All';
  String jobType = 'All';
  double distance = 50;
  late Stream<WebDataState<List<WebJobAlertItem>>> stream;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    stream = _stream();
  }

  @override
  void dispose() {
    postcode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebDataState<List<WebJobAlertItem>>>(
      stream: stream,
      builder: (context, snapshot) {
        final alerts = snapshot.data?.data ?? const <WebJobAlertItem>[];
        return ListView(
          children: [
            Text('Job Subscriptions',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: trade,
                    isExpanded: true,
                    items: <String>{
                      'All',
                      ...JobTaxonomyService.canonicalRoles,
                    }
                        .map(
                          (role) => DropdownMenuItem(
                            value: role,
                            child: Text(role, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => trade = value ?? 'All'),
                    decoration: const InputDecoration(labelText: 'Trade'),
                  ),
                ),
                SizedBox(
                    width: 180,
                    child: TextField(
                        controller: postcode,
                        decoration:
                            const InputDecoration(labelText: 'Postcode'))),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: jobType,
                    items: const [
                      DropdownMenuItem(value: 'All', child: Text('All')),
                      DropdownMenuItem(value: 'hourly', child: Text('Hourly')),
                      DropdownMenuItem(value: 'price', child: Text('Price')),
                      DropdownMenuItem(
                          value: 'negotiable', child: Text('Negotiable')),
                    ],
                    onChanged: (value) =>
                        setState(() => jobType = value ?? 'All'),
                    decoration: const InputDecoration(labelText: 'Work format'),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Distance: ${distance.toStringAsFixed(0)} mi'),
                      Slider(
                        value: distance,
                        min: 5,
                        max: 50,
                        divisions: 9,
                        onChanged: (value) => setState(() => distance = value),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: const Icon(Icons.add),
                  label: const Text('Create'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if ((snapshot.data == null || snapshot.data!.loading) &&
                alerts.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (alerts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No job subscriptions yet'),
              )
            else
              for (final alert in alerts)
                ListTile(
                  leading: const Icon(Icons.work_history_outlined),
                  title: Text((alert.data['trade'] ?? 'All trades').toString()),
                  subtitle: Text(_subscriptionSubtitle(alert.data)),
                  trailing: IconButton(
                    tooltip: 'Delete subscription',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _delete(alert.id),
                  ),
                ),
          ],
        );
      },
    );
  }

  Stream<WebDataState<List<WebJobAlertItem>>> _stream() {
    return service.poll(
      () => service.loadJobAlerts(widget.userId),
      empty: const <WebJobAlertItem>[],
      logPrefix: 'WEB JOB ALERTS LOAD ERROR',
    );
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final normalized = postcodeLookup.normalizePostcode(postcode.text);
      final found = await postcodeLookup.lookupPostcode(normalized);
      if (found?.latitude == null || found?.longitude == null) {
        throw StateError('Enter a valid UK postcode.');
      }
      await service.saveJobAlert(
        uid: widget.userId,
        trade: trade,
        jobType: jobType,
        distance: distance,
        postcode: normalized,
        lat: found!.latitude!,
        lng: found.longitude!,
      );
      postcode.clear();
      if (mounted) {
        setState(() {
          trade = 'All';
          jobType = 'All';
          distance = 50;
          stream = _stream();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create subscription: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _delete(String alertId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete subscription?'),
        content: const Text(
          'This job subscription will stop sending matching job alerts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await service.deleteJobAlert(widget.userId, alertId);
      if (!mounted) return;
      setState(() => stream = _stream());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subscription deleted')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete subscription: $error')),
        );
      }
    }
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({required this.userId, required this.profile});
  final String userId;
  final Map<String, dynamic> profile;
  @override
  Widget build(BuildContext context) {
    final settings = profile['settings'];
    final raw = settings is Map && settings['notifications'] is Map
        ? settings['notifications']
        : profile['notificationPreferences'];
    final preferences =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return ListView(children: [
      Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
      for (final entry in const {
        'enabled': 'All notifications',
        'jobAlerts': 'Job alerts',
        'applicationUpdates': 'Application updates',
        'offers': 'Offers',
        'messages': 'Messages and chats',
        'adminMessages': 'Admin messages',
        'billing': 'Billing notifications',
        'supportReplies': 'Support replies',
        'policyUpdates': 'Policy/document updates',
        'sound': 'Sound',
        'badges': 'Badge counts',
      }.entries)
        _SwitchSetting(
            key: ValueKey(entry.key),
            userId: userId,
            settings: preferences,
            field: entry.key,
            title: entry.value),
    ]);
  }
}

class _SupportView extends StatefulWidget {
  const _SupportView({
    required this.userId,
    required this.role,
    required this.userData,
  });

  final String userId;
  final String role;
  final Map<String, dynamic> userData;

  @override
  State<_SupportView> createState() => _SupportViewState();
}

class _SupportViewState extends State<_SupportView> {
  final service = WebAccountDataService();
  final message = TextEditingController();
  final media = WebChatMediaService();
  final attachments = <WebPendingChatAttachment>[];
  String type = 'technical_issue';
  bool submitting = false;

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final types = widget.role == 'worker'
        ? webWorkerSupportTypes
        : webEmployerSupportTypes;
    if (!types.containsKey(type)) type = types.keys.first;
    return ListView(
      children: [
        Text('Support', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: type,
          items: [
            for (final entry in types.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (value) =>
              setState(() => type = value ?? types.keys.first),
          decoration: const InputDecoration(labelText: 'Request type'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: message,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Message'),
        ),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
              onPressed: submitting ? null : () => _pick('photo'),
              icon: const Icon(Icons.photo),
              label: const Text('Photos')),
          OutlinedButton.icon(
              onPressed: submitting ? null : () => _pick('video'),
              icon: const Icon(Icons.videocam_outlined),
              label: const Text('Videos')),
          OutlinedButton.icon(
              onPressed: submitting ? null : () => _pick('file'),
              icon: const Icon(Icons.attach_file),
              label: const Text('Files')),
        ]),
        WebPendingAttachmentsPreview(
            attachments: attachments,
            onRemove: (index) {
              if (!submitting) setState(() => attachments.removeAt(index));
            }),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: submitting ? null : _submit,
          icon: const Icon(Icons.send),
          label: const Text('Submit support request'),
        ),
      ],
    );
  }

  Future<void> _pick(String kind) async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final picked = switch (kind) {
        'photo' => await media.pickImages(),
        'video' => await media.pickVideos(),
        _ => await media.pickFiles(),
      };
      if (mounted) setState(() => attachments.addAll(picked));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not select attachments: $error')));
      }
    }
  }

  Future<void> _submit() async {
    if ((message.text.trim().isEmpty && attachments.isEmpty) || submitting) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => submitting = true);
    try {
      final uploaded = await WebSupportAttachments()
          .upload(widget.userId, List.of(attachments));
      await service.submitSupportRequest(
        uid: widget.userId,
        role: widget.role,
        userData: widget.userData,
        type: type,
        message: message.text,
        attachments: uploaded,
      );
      if (!mounted) return;
      message.clear();
      attachments.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Support request sent')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not submit support request: $error')));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }
}

class _AboutLegalView extends StatefulWidget {
  const _AboutLegalView();

  @override
  State<_AboutLegalView> createState() => _AboutLegalViewState();
}

class _AboutLegalViewState extends State<_AboutLegalView> {
  String? selectedAsset = _legalDocuments.first.assetPath;
  String body = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _legalDocuments
        .where((doc) => doc.assetPath == selectedAsset)
        .cast<_WebLegalDocument?>()
        .firstOrNull;
    final document = ListView(
      children: [
        Text(selected?.title ?? 'About STROYKA',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(body.isEmpty ? 'Loading...' : body),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < WebBreakpoints.narrow) {
          return Column(
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(selectedAsset),
                initialValue: selectedAsset,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Document'),
                items: [
                  for (final doc in _legalDocuments)
                    DropdownMenuItem(
                      value: doc.assetPath,
                      child: Text(
                        '${doc.title} · v${doc.version}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (asset) {
                  if (asset == null) return;
                  setState(() {
                    selectedAsset = asset;
                    _load();
                  });
                },
              ),
              const SizedBox(height: WebSpacing.md),
              Expanded(child: document),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(
              width: 320,
              child: ListView(
                children: [
                  for (final doc in _legalDocuments)
                    ListTile(
                      selected: doc.assetPath == selectedAsset,
                      title: Text(doc.title),
                      subtitle: Text('Version ${doc.version}'),
                      onTap: () => setState(() {
                        selectedAsset = doc.assetPath;
                        _load();
                      }),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 28),
            Expanded(child: document),
          ],
        );
      },
    );
  }

  Future<void> _load() async {
    final asset = selectedAsset;
    if (asset == null) return;
    try {
      final text = await rootBundle.loadString(asset);
      if (mounted) setState(() => body = text);
    } catch (_) {
      if (mounted) setState(() => body = 'Document unavailable.');
    }
  }
}

class _DeleteAccountView extends StatefulWidget {
  const _DeleteAccountView({required this.onDeleted});

  final VoidCallback onDeleted;

  @override
  State<_DeleteAccountView> createState() => _DeleteAccountViewState();
}

class _DeleteAccountViewState extends State<_DeleteAccountView> {
  final password = TextEditingController();
  bool deleting = false;

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text('Delete Account',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        const Text(
          'This action cannot be undone. Your profile and related data will be permanently removed or anonymised according to the data retention policy.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password for recent-login confirmation',
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: deleting ? null : _delete,
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Delete Account'),
        ),
      ],
    );
  }

  Future<void> _delete() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null || password.text.trim().isEmpty) return;
    setState(() => deleting = true);
    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password.text.trim(),
      );
      await user.reauthenticateWithCredential(credential);
      await AccountDeletionService().deleteCurrentAccount();
      widget.onDeleted();
    } on AccountDeletionRequiresRecentLogin {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again before deleting.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete account: $error')),
      );
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }
}

class _IdentityTile extends StatelessWidget {
  const _IdentityTile({required this.identity});

  final WebRoleIdentity identity;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: WebTheme.accentSoft,
        child: identity.avatarUrl.isEmpty
            ? const Icon(Icons.person_outline, color: WebTheme.accent)
            : ClipOval(
                child: Image.network(
                  identity.avatarUrl,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.person_outline, color: WebTheme.accent),
                ),
              ),
      ),
      title: Text(identity.displayName),
      subtitle: Text(identity.subtitle),
    );
  }
}

class _AccountGroupLabel extends StatelessWidget {
  const _AccountGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebSpacing.md,
        WebSpacing.md,
        WebSpacing.md,
        WebSpacing.xs,
      ),
      child: Text(
        label,
        style: WebTypography.caption.copyWith(
          color: WebTheme.subtleText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return WebPageHeader(
      title: title,
      subtitle: 'Manage your profile, work preferences and account services.',
      leading: IconButton(
        tooltip: 'Back',
        onPressed: onClose,
        icon: const Icon(Icons.arrow_back),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label,
                style: const TextStyle(
                  color: WebTheme.muted,
                  fontWeight: FontWeight.w700,
                )),
          ),
          Expanded(child: Text(value.isEmpty ? 'Not set' : value)),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final Map<String, dynamic> plan;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amount = BillingService.readInt(plan['amountPence']);
    return InkWell(
      onTap: busy || selected ? null : onTap,
      borderRadius: BorderRadius.circular(WebRadii.card),
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(WebRadii.card),
          border:
              Border.all(color: selected ? WebTheme.accent : WebTheme.border),
          color: selected ? WebTheme.accentSoft : WebTheme.surfaceAlt,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(BillingService.planDisplayName(plan),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('GBP ${(amount / 100).toStringAsFixed(0)}/month'),
            Text('${BillingService.readInt(plan['vacancySlotLimit'])} slots'),
          ],
        ),
      ),
    );
  }
}

class _ThreadList extends StatelessWidget {
  const _ThreadList({
    required this.loading,
    required this.threads,
    required this.selectedKey,
    required this.onSelected,
  });

  final bool loading;
  final List<WebAdminMessageThread> threads;
  final String? selectedKey;
  final ValueChanged<WebAdminMessageThread> onSelected;

  @override
  Widget build(BuildContext context) {
    if (loading && threads.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (threads.isEmpty) {
      return const Center(child: Text('No admin messages yet'));
    }
    return ListView.separated(
      itemCount: threads.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final thread = threads[index];
        return ListTile(
          selected: thread.key == selectedKey,
          selectedTileColor: WebTheme.accentSoft,
          leading: Icon(
            thread.important
                ? Icons.star
                : thread.unread
                    ? Icons.mark_email_unread_outlined
                    : Icons.mark_email_read_outlined,
            color: thread.important ? Colors.amber.shade700 : WebTheme.accent,
          ),
          title: Text(thread.latest.subject),
          subtitle: Text(thread.latest.message,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => onSelected(thread),
        );
      },
    );
  }
}

class _AdminThreadDetail extends StatelessWidget {
  const _AdminThreadDetail({
    required this.thread,
    required this.controller,
    required this.sending,
    required this.pendingAttachments,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onToggleImportant,
    required this.onToggleRead,
    required this.onDelete,
  });

  final WebAdminMessageThread thread;
  final TextEditingController controller;
  final bool sending;
  final List<WebPendingChatAttachment> pendingAttachments;
  final VoidCallback onAttach;
  final ValueChanged<int> onRemoveAttachment;
  final VoidCallback onSend;
  final VoidCallback onToggleImportant;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text(thread.latest.subject,
                style: Theme.of(context).textTheme.headlineMedium),
          ),
          IconButton(
            tooltip: thread.important ? 'Remove important' : 'Mark important',
            onPressed: sending ? null : onToggleImportant,
            icon: Icon(thread.important ? Icons.star : Icons.star_border),
            color: thread.important ? Colors.amber.shade700 : null,
          ),
          PopupMenuButton<String>(
            enabled: !sending,
            onSelected: (value) {
              if (value == 'read') onToggleRead();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'read',
                child: Text(thread.unread ? 'Mark as read' : 'Mark unread'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            children: [
              for (final message in thread.messages)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: message.data['senderId'] == 'admin'
                        ? WebTheme.accentSoft
                        : WebTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message.senderName,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(message.message),
                      WebChatAttachmentsView(
                        attachments: _adminMessageAttachments(message),
                        isMine: message.data['senderId'] != 'admin',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (thread.canReply) ...[
          TextField(
            controller: controller,
            enabled: !sending,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Reply to Admin'),
          ),
          WebPendingAttachmentsPreview(
            attachments: pendingAttachments,
            onRemove: onRemoveAttachment,
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton.icon(
              onPressed: sending ? null : onAttach,
              icon: const Icon(Icons.attach_file),
              label: const Text('Attach'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(sending ? 'Sending...' : 'Send'),
            ),
          ]),
        ] else
          const Text('Informational message. Reply is not available.'),
      ],
    );
  }
}

List<WebChatAttachment> _adminMessageAttachments(WebAdminMessage message) {
  final normalized = message.attachments.map((attachment) {
    return {
      ...attachment,
      'url': (attachment['url'] ?? attachment['fileUrl'])?.toString() ?? '',
      'fileName': (attachment['fileName'] ?? attachment['name'])?.toString() ??
          'Attachment',
      'mimeType': attachment['mimeType']?.toString(),
      'sizeBytes': attachment['sizeBytes'] ?? attachment['size'],
    };
  }).toList();
  return normalizeWebChatAttachments({'attachments': normalized});
}

class _SwitchSetting extends StatefulWidget {
  const _SwitchSetting({
    super.key,
    required this.userId,
    required this.settings,
    required this.field,
    required this.title,
  });

  final String userId;
  final Map<String, dynamic> settings;
  final String field;
  final String title;

  @override
  State<_SwitchSetting> createState() => _SwitchSettingState();
}

class _SwitchSettingState extends State<_SwitchSetting> {
  late bool value = widget.settings[widget.field] != false;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      title: Text(widget.title),
      onChanged: (next) async {
        setState(() => value = next);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .set({
          'settings': {
            'notifications': {widget.field: next},
            'updatedAt': FieldValue.serverTimestamp()
          },
          'notificationPreferences': {widget.field: next},
        }, SetOptions(merge: true));
      },
    );
  }
}

class _WebLegalDocument {
  const _WebLegalDocument(this.title, this.assetPath, this.version);

  final String title;
  final String assetPath;
  final String version;
}

const _legalDocuments = [
  _WebLegalDocument(
    'Privacy Policy / Privacy Notice',
    'assets/legal/privacy_policy.md',
    '2026-05-20',
  ),
  _WebLegalDocument(
      'Terms and Conditions', 'assets/legal/terms_of_use.md', '2026-05-20'),
  _WebLegalDocument(
      'Worker Terms', 'assets/legal/worker_terms.md', '2026-05-20'),
  _WebLegalDocument(
      'Employer Terms', 'assets/legal/employer_terms.md', '2026-05-20'),
  _WebLegalDocument('Billing & Payment Terms',
      'assets/legal/billing_payment_terms.md', '2026-05-20'),
  _WebLegalDocument('Account Deletion Notice',
      'assets/legal/account_deletion_policy.md', '2026-05-20'),
  _WebLegalDocument('Company Information',
      'assets/legal/company_information.md', '2026-05-20'),
];

String _subscriptionSubtitle(Map<String, dynamic> data) {
  final type = (data['jobType'] ?? 'All').toString();
  final postcode = (data['postcode'] ?? '').toString();
  final distance = data['distance']?.toString() ?? '50';
  return [
    if (postcode.isNotEmpty) 'Postcode: $postcode',
    'Type: ${BillingService.formatLabel(type)}',
    'Distance: $distance mi',
  ].join(' • ');
}
