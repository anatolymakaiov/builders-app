import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../services/multi_account_service.dart';
import '../theme/app_theme.dart';
import 'app_cached_image.dart';

Future<void> showAccountSwitcher(
  BuildContext context, {
  required bool web,
  required Future<void> Function() onCreateNewAccount,
}) async {
  final content = _AccountSwitcher(
    web: web,
    onCreateNewAccount: onCreateNewAccount,
  );
  if (web) {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
          child: content,
        ),
      ),
    );
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(child: content),
    );
  }
}

class AccountIdentityButton extends StatelessWidget {
  const AccountIdentityButton({
    super.key,
    required this.name,
    required this.onPressed,
    this.avatarUrl = '',
    this.isEmployer = false,
  });

  final String name;
  final String avatarUrl;
  final bool isEmployer;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 230, minHeight: 44),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.blueprintLine.withValues(alpha: 0.78),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppCachedCircleAvatar(
                  imageUrl: avatarUrl,
                  fallbackIcon: isEmployer
                      ? Icons.business_outlined
                      : Icons.person_outline,
                  radius: 14,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.blueprintLine,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: AppColors.blueprintLine,
                  size: 21,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CurrentAccountIdentityButton extends StatelessWidget {
  const CurrentAccountIdentityButton({
    super.key,
    required this.fallbackName,
    required this.isEmployer,
    required this.onPressed,
  });

  final String fallbackName;
  final bool isEmployer;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final name = _firstText(
            data,
            isEmployer
                ? const ['companyName', 'name', 'displayName', 'username']
                : const ['name', 'fullName', 'displayName', 'username']);
        final avatar = _firstText(
            data,
            isEmployer
                ? const [
                    'companyLogo',
                    'companyLogoUrl',
                    'companyAvatarUrl',
                    'avatarUrl',
                    'photoUrl',
                  ]
                : const [
                    'photo',
                    'photoUrl',
                    'profilePhotoUrl',
                    'avatarUrl',
                  ]);
        return AccountIdentityButton(
          name: name.isEmpty ? fallbackName : name,
          avatarUrl: avatar,
          isEmployer: isEmployer,
          onPressed: onPressed,
        );
      },
    );
  }

  String _firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}

class _AccountSwitcher extends StatefulWidget {
  const _AccountSwitcher({
    required this.web,
    required this.onCreateNewAccount,
  });

  final bool web;
  final Future<void> Function() onCreateNewAccount;

  @override
  State<_AccountSwitcher> createState() => _AccountSwitcherState();
}

class _AccountSwitcherState extends State<_AccountSwitcher> {
  final service = MultiAccountService();
  late Future<List<LinkedAccountIdentity>> accounts;
  bool busy = false;
  String? error;
  List<LinkedAccountIdentity> loadedAccounts = const [];

  @override
  void initState() {
    super.initState();
    accounts = _loadAccounts();
    MultiAccountState.revision.addListener(_handleAccountStateChange);
  }

  @override
  void dispose() {
    MultiAccountState.revision.removeListener(_handleAccountStateChange);
    super.dispose();
  }

  void _handleAccountStateChange() {
    if (!mounted || busy) return;
    setState(() => accounts = _loadAccounts());
  }

  Future<List<LinkedAccountIdentity>> _loadAccounts() async {
    final loaded = await service.linkedAccounts();
    loadedAccounts = loaded;
    return loaded;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Switch account',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: busy ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: FutureBuilder<List<LinkedAccountIdentity>>(
              future: accounts,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => accounts = _loadAccounts()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Could not load accounts. Retry'),
                    ),
                  );
                }
                final items = snapshot.data ?? const [];
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final account = items[index];
                    final current = isCurrentLinkedAccount(
                      FirebaseAuth.instance.currentUser?.uid,
                      account.uid,
                    );
                    return ListTile(
                      enabled: !busy,
                      onTap: current ? null : () => _switch(account.uid),
                      leading: AppCachedCircleAvatar(
                        imageUrl: account.avatarUrl,
                        fallbackIcon: account.isEmployer
                            ? Icons.business_outlined
                            : Icons.person_outline,
                        radius: 24,
                      ),
                      title: Text(
                        account.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text([
                        if (account.username.isNotEmpty) '@${account.username}',
                        account.isEmployer ? 'Employer' : 'Worker',
                      ].join(' · ')),
                      trailing: current
                          ? const Icon(Icons.check_circle, color: Colors.blue)
                          : const Icon(Icons.chevron_right),
                    );
                  },
                );
              },
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],
          const Divider(height: 24),
          OutlinedButton.icon(
            onPressed: busy ? null : _showAddAccount,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Add another account'),
          ),
        ],
      ),
    );
  }

  Future<void> _switch(String uid) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await service.switchTo(uid);
      if (mounted) Navigator.pop(context);
    } catch (switchError) {
      if (mounted) {
        setState(() {
          busy = false;
          error = _switchErrorMessage(switchError);
        });
      }
    }
  }

  Future<void> _showAddAccount() async {
    if (busy) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add another account'),
        content: const Text(
          'Sign in to an existing STROYKA account or create a new one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'existing'),
            child: const Text('Log in to existing account'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'new'),
            child: const Text('Create new account'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'existing') {
      await _linkExisting();
      return;
    }
    setState(() => busy = true);
    try {
      await widget.onCreateNewAccount();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not start account creation. Please try again.';
        });
      }
    }
  }

  Future<void> _linkExisting() async {
    final email = TextEditingController();
    final password = TextEditingController();
    String? dialogError;
    var submitting = false;
    final linked = await showDialog<LinkedAccountIdentity>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Log in to existing account'),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: email,
                  enabled: !submitting,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  enabled: !submitting,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    dialogError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      setDialogState(() {
                        submitting = true;
                        dialogError = null;
                      });
                      try {
                        final identity = await service.linkExistingAccount(
                          email: email.text,
                          password: password.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, identity);
                        }
                      } on FirebaseAuthException catch (authError) {
                        setDialogState(() {
                          submitting = false;
                          dialogError = authError.code == 'wrong-password' ||
                                  authError.code == 'invalid-credential'
                              ? 'Email or password is incorrect.'
                              : authError.message ??
                                  'Could not authenticate this account.';
                        });
                      } catch (_) {
                        setDialogState(() {
                          submitting = false;
                          dialogError =
                              'Could not link this account. Please try again.';
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Log in and link'),
            ),
          ],
        ),
      ),
    );
    email.dispose();
    password.dispose();
    if (linked != null && mounted) {
      final merged = mergeLinkedAccountIdentity(loadedAccounts, linked);
      setState(() {
        loadedAccounts = merged;
        accounts = Future.value(merged);
        error = null;
      });
      try {
        final refreshed = await _loadAccounts();
        if (mounted) {
          setState(() => accounts = Future.value(refreshed));
        }
      } catch (_) {
        // The authoritative link succeeded; retain its returned safe identity.
      }
    }
  }

  String _switchErrorMessage(Object error) {
    final code = error is FirebaseFunctionsException
        ? error.code
        : error is FirebaseAuthException
            ? error.code
            : '';
    return switch (code) {
      'permission-denied' =>
        'This account is no longer linked to your current account.',
      'unauthenticated' ||
      'user-token-expired' =>
        'Your session expired. Please sign in again.',
      'user-disabled' ||
      'failed-precondition' =>
        'This account is currently unavailable.',
      'network-request-failed' ||
      'unavailable' =>
        'Check your internet connection and try again.',
      'account-switch-target-mismatch' =>
        'The requested account could not be activated.',
      _ => 'Could not switch account. Please try again.',
    };
  }
}
