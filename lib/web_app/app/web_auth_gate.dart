import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../screens/login_screen.dart';
import '../../screens/edit_profile_screen.dart';
import '../../screens/password_recovery_screen.dart';
import '../../services/multi_account_service.dart';
import '../../services/auth_session_resolver.dart';
import '../../widgets/auth_session_gate.dart';
import '../../widgets/legal_documents.dart';
import '../services/web_password_sign_in.dart';
import '../shell/web_shell.dart';
import '../portrait/portrait_web_auth.dart';
import '../portrait/portrait_web_layout.dart';
import '../portrait/portrait_web_shell.dart';
import '../theme/web_theme.dart';
import '../widgets/web_panel.dart';
import '../widgets/web_auth_page_frame.dart';

Widget _frameAuthPage(Widget page) {
  if (page is LoginScreen || page is PasswordLoginScreen) {
    return WebAuthPageFrame(
      maxWidth: 640,
      backdrop: WebAuthBackdrop.login,
      child: page,
    );
  }
  if (page is PasswordRecoveryScreen) {
    return WebAuthPageFrame(
      maxWidth: 600,
      backdrop: WebAuthBackdrop.recovery,
      child: page,
    );
  }
  return WebAuthPageFrame(
    maxWidth: page is LegalAcceptanceScreen ? 680 : 640,
    child: page,
  );
}

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
      loading: WebPresentationDispatcher(
        desktop: const _WebAuthLoading(),
        portrait: portraitWebAuthPage(const _WebAuthLoading()),
      ),
      signedOut: (_) {
        _lastReadyUid = null;
        return WebPresentationDispatcher(
          desktop: const WebLoginPage(),
          portrait: PortraitWebLanding(
            homeBuilder: (_) => const WebAuthGate(),
          ),
        );
      },
      resolved: (context, user, resolution, refresh) {
        switch (resolution.destination) {
          case AuthSessionDestination.registration:
            return WebPresentationDispatcher(
              desktop: _frameAuthPage(LoginScreen(
                key: ValueKey('web-registration:${user.uid}'),
                initialRegistration: true,
                resumeRegistration: true,
                authPageBuilder: _frameAuthPage,
                postRegistrationHomeBuilder: (_) => const WebAuthGate(),
              )),
              portrait: PortraitWebRegistration(
                key: ValueKey('portrait-registration:${user.uid}'),
                resume: true,
                homeBuilder: (_) => const WebAuthGate(),
              ),
            );
          case AuthSessionDestination.legal:
            return WebPresentationDispatcher(
              desktop: _frameAuthPage(LegalAcceptanceScreen(
                role: resolution.role,
                userId: user.uid,
                onAccepted: (_) async => refresh(),
              )),
              portrait: portraitWebAuthPage(LegalAcceptanceScreen(
                role: resolution.role,
                userId: user.uid,
                onAccepted: (_) async => refresh(),
              )),
            );
          case AuthSessionDestination.profile:
            return WebPresentationDispatcher(
              desktop: _frameAuthPage(
                ProfileScreen(onProfileSaved: () async => refresh()),
              ),
              portrait: portraitWebAuthPage(
                ProfileScreen(onProfileSaved: () async => refresh()),
              ),
            );
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
            return WebPresentationDispatcher(
              key: ValueKey('web-presentation:${user.uid}'),
              desktop: WebShell(
                key: ValueKey('web-shell:${user.uid}'),
                user: user,
                role: resolution.role,
                profile: resolution.profile,
              ),
              portrait: PortraitWebShell(
                key: ValueKey('portrait-web-shell:${user.uid}'),
                user: user,
                role: resolution.role,
                profile: resolution.profile,
              ),
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
      await const WebPasswordSignIn()(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
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
                      : () {
                          setState(() => error = null);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  _frameAuthPage(PasswordRecoveryScreen(
                                initialEmail: emailController.text,
                                webFramed: true,
                              )),
                            ),
                          );
                        },
                  child: const Text('Forgot password?'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: loading
                      ? null
                      : () {
                          setState(() => error = null);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _frameAuthPage(LoginScreen(
                                initialRegistration: true,
                                authPageBuilder: _frameAuthPage,
                                postRegistrationHomeBuilder: (_) =>
                                    const WebAuthGate(),
                              )),
                            ),
                          );
                        },
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
