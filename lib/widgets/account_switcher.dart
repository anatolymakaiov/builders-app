import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/multi_account_service.dart';
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
  });

  final String name;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.keyboard_arrow_down),
      label: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
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

  @override
  void initState() {
    super.initState();
    accounts = service.linkedAccounts();
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
                      onPressed: () => setState(
                        () => accounts = service.linkedAccounts(),
                      ),
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
                    final current =
                        FirebaseAuth.instance.currentUser?.uid == account.uid;
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
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await service.switchTo(uid);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not switch account. Please try again.';
        });
      }
    }
  }

  Future<void> _showAddAccount() async {
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
    final linked = await showDialog<bool>(
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
              onPressed:
                  submitting ? null : () => Navigator.pop(dialogContext, false),
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
                        await service.linkExistingAccount(
                          email: email.text,
                          password: password.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
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
    if (linked == true && mounted) {
      setState(() => accounts = service.linkedAccounts());
    }
  }
}
