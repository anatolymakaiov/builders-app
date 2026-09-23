import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../screens/login_screen.dart';
import '../../screens/edit_profile_screen.dart';
import '../../screens/password_recovery_screen.dart';
import '../../services/multi_account_service.dart';
import '../../services/auth_session_resolver.dart';
import '../../services/social_auth_service.dart';
import '../../widgets/auth_session_gate.dart';
import '../../widgets/legal_documents.dart';
import '../shell/web_shell.dart';
import '../theme/web_theme.dart';
import '../widgets/web_panel.dart';

class WebAuthGate extends StatefulWidget {
  const WebAuthGate({super.key});

  @override
  State<WebAuthGate> createState() => _WebAuthGateState();
}

class _WebAuthGateState extends State<WebAuthGate> {
  String? _lastReadyUid;

  @override
  Widget build(BuildContext context) {
    return AuthSessionGate(
      loading: const _WebAuthLoading(),
      signedOut: (_) {
        _lastReadyUid = null;
        return const WebLoginPage();
      },
      resolved: (context, user, resolution, refresh) {
        switch (resolution.destination) {
          case AuthSessionDestination.registration:
            return LoginScreen(
              key: ValueKey('web-registration:${user.uid}'),
              initialRegistration: true,
              resumeRegistration: true,
              postRegistrationHomeBuilder: (_) => const WebAuthGate(),
            );
          case AuthSessionDestination.legal:
            return LegalAcceptanceScreen(
              role: resolution.role,
              userId: user.uid,
              onAccepted: (_) async => refresh(),
            );
          case AuthSessionDestination.profile:
            return ProfileScreen(onProfileSaved: () async => refresh());
          case AuthSessionDestination.home:
            if (_lastReadyUid != user.uid) {
              _lastReadyUid = user.uid;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted ||
                    FirebaseAuth.instance.currentUser?.uid != user.uid) {
                  return;
                }
                MultiAccountState.markShellRefreshed(user.uid);
                MultiAccountService()
                    .completePendingNewAccountLink()
                    .catchError((_) {});
              });
            }
            return WebShell(
              key: ValueKey('web-shell:${user.uid}'),
              user: user,
              role: resolution.role,
              profile: resolution.profile,
            );
          case AuthSessionDestination.deleted:
            return const _WebAuthLoading();
        }
      },
    );
  }
}

class WebLoginPage extends StatefulWidget {
  const WebLoginPage({super.key});

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;
  bool entering = false;
  String? error;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      if (credential.user != null) {
        try {
          await SocialAuthService.linkAfterVerifiedPasswordSignIn(
              credential.user!);
        } catch (_) {
          // Optional linking cannot turn a successful password login into failure.
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        error = e.message ?? e.code;
      });
    } catch (e) {
      setState(() {
        error = 'Could not sign in. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> signInSocial(SocialProvider provider) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await SocialAuthService().signIn(provider);
    } catch (failure) {
      if (mounted) {
        setState(() => error =
            SocialAuthService.errorMessage(failure, provider: provider));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: WebPanel(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'STROYKA',
                  style: TextStyle(
                    color: WebTheme.deep,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to the Web workspace',
                  style: TextStyle(color: WebTheme.muted),
                ),
                const SizedBox(height: 24),
                if (entering) ...[
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    onSubmitted: (_) => signIn(),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => signIn(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: loading ? null : signIn,
                    child: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PasswordRecoveryScreen(
                                  initialEmail: emailController.text,
                                ),
                              ),
                            ),
                    child: const Text('Forgot password?'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      for (final provider in SocialProvider.values)
                        TextButton(
                          onPressed:
                              loading ? null : () => signInSocial(provider),
                          child: Text(switch (provider) {
                            SocialProvider.google => 'Google',
                            SocialProvider.apple => 'Apple ID',
                            SocialProvider.facebook => 'Facebook',
                          }),
                        ),
                    ],
                  ),
                  TextButton(
                    onPressed:
                        loading ? null : () => setState(() => entering = false),
                    child: const Text('Back'),
                  ),
                ] else
                  FilledButton(
                    onPressed: () => setState(() => entering = true),
                    child: const Text('Enter'),
                  ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: loading
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LoginScreen(
                                initialRegistration: true,
                                postRegistrationHomeBuilder: (_) =>
                                    const WebAuthGate(),
                              ),
                            ),
                          ),
                  child: const Text('Registration'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WebAuthLoading extends StatelessWidget {
  const _WebAuthLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
