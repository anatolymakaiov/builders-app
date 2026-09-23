import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_session_resolver.dart';
import '../services/multi_account_service.dart';
import 'account_switch_shell_gate.dart';

typedef SessionContentBuilder = Widget Function(
  BuildContext context,
  User user,
  AuthSessionResolution resolution,
  VoidCallback refresh,
);

class AuthSessionGate extends StatefulWidget {
  const AuthSessionGate({
    super.key,
    required this.signedOut,
    required this.resolved,
    this.authChanges,
    this.resolve,
    this.loading,
    this.onDeleted,
  });

  final WidgetBuilder signedOut;
  final SessionContentBuilder resolved;
  final Stream<User?>? authChanges;
  final Future<AuthSessionResolution> Function(User)? resolve;
  final Widget? loading;
  final Future<void> Function(String uid)? onDeleted;

  @override
  State<AuthSessionGate> createState() => _AuthSessionGateState();
}

class _AuthSessionGateState extends State<AuthSessionGate> {
  late final Stream<User?> _authChanges =
      widget.authChanges ?? FirebaseAuth.instance.authStateChanges();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authChanges,
      builder: (context, authSnapshot) => ValueListenableBuilder<String?>(
        valueListenable: MultiAccountState.switchTargetUid,
        builder: (context, targetUid, _) => AccountSwitchShellGate(
          authenticatedUid: authSnapshot.data?.uid,
          switchTargetUid: targetUid,
          onShellQuiesced: MultiAccountState.markShellQuiesced,
          child: authSnapshot.connectionState == ConnectionState.waiting
              ? widget.loading ?? const _SessionLoading()
              : authSnapshot.data == null
                  ? widget.signedOut(context)
                  : _ResolvedSession(
                      key: ValueKey('auth-session:${authSnapshot.data!.uid}'),
                      user: authSnapshot.data!,
                      resolve: widget.resolve ?? AuthSessionResolver().resolve,
                      resolved: widget.resolved,
                      loading: widget.loading ?? const _SessionLoading(),
                      onDeleted: widget.onDeleted,
                    ),
        ),
      ),
    );
  }
}

class _ResolvedSession extends StatefulWidget {
  const _ResolvedSession({
    super.key,
    required this.user,
    required this.resolve,
    required this.resolved,
    required this.loading,
    this.onDeleted,
  });

  final User user;
  final Future<AuthSessionResolution> Function(User) resolve;
  final SessionContentBuilder resolved;
  final Widget loading;
  final Future<void> Function(String uid)? onDeleted;

  @override
  State<_ResolvedSession> createState() => _ResolvedSessionState();
}

class _ResolvedSessionState extends State<_ResolvedSession> {
  late Future<AuthSessionResolution> _resolution;
  bool _signingOutDeleted = false;

  @override
  void initState() {
    super.initState();
    _resolution = widget.resolve(widget.user);
  }

  void refresh() {
    if (!mounted) return;
    final nextResolution = widget.resolve(widget.user);
    setState(() {
      _resolution = nextResolution;
    });
  }

  Future<void> signOutDeleted() async {
    if (_signingOutDeleted) return;
    _signingOutDeleted = true;
    if (widget.onDeleted != null) {
      await widget.onDeleted!(widget.user.uid);
    } else if (FirebaseAuth.instance.currentUser?.uid == widget.user.uid) {
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthSessionResolution>(
      future: _resolution,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.loading;
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: TextButton.icon(
                onPressed: refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Could not load your account. Retry'),
              ),
            ),
          );
        }
        final resolution = snapshot.data!;
        if (resolution.destination == AuthSessionDestination.deleted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) signOutDeleted();
          });
          return widget.loading;
        }
        return widget.resolved(context, widget.user, resolution, refresh);
      },
    );
  }
}

class _SessionLoading extends StatelessWidget {
  const _SessionLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
