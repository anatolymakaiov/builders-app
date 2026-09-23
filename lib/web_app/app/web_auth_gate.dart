import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../screens/login_screen.dart';
import '../../screens/edit_profile_screen.dart';
import '../../services/multi_account_service.dart';
import '../../services/social_auth_service.dart';
import '../../widgets/legal_documents.dart';
import '../shell/web_shell.dart';
import '../theme/web_theme.dart';
import '../widgets/web_panel.dart';

class WebAuthGate extends StatelessWidget {
  const WebAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _WebAuthLoading();
        }

        final user = authSnapshot.data;
        if (user == null) {
          return const WebLoginPage();
        }
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const _WebAuthLoading();
            }

            if (profileSnapshot.data?.exists != true) {
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
                    .collection('pending_registrations')
                    .doc(user.uid)
                    .get(),
                builder: (context, draftSnapshot) {
                  if (draftSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const _WebAuthLoading();
                  }
                  final draft = draftSnapshot.data?.data();
                  if (draft == null) {
                    final socialProvider = SocialAuthService.providerFromIds(
                      user.providerData.map((identity) => identity.providerId),
                    );
                    return LoginScreen(
                      initialRegistration: true,
                      resumeRegistration: socialProvider != null,
                      postRegistrationHomeBuilder: (_) => const WebAuthGate(),
                    );
                  }
                  final role =
                      draft['role'] == 'employer' ? 'employer' : 'worker';
                  if (draft['registrationFormComplete'] == false) {
                    return LoginScreen(
                      key: ValueKey('registration:${user.uid}'),
                      initialRegistration: true,
                      resumeRegistration: true,
                      postRegistrationHomeBuilder: (_) => const WebAuthGate(),
                    );
                  }
                  void openProfile() {
                    final navigator = Navigator.of(context);
                    navigator.pushReplacement(MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        onProfileSaved: () async {
                          navigator.pushAndRemoveUntil(
                            MaterialPageRoute(
                                builder: (_) => const WebAuthGate()),
                            (_) => false,
                          );
                        },
                      ),
                    ));
                  }

                  if (!LegalDocuments.hasAcceptedCurrentVersion(draft, role)) {
                    return LegalAcceptanceScreen(
                      role: role,
                      userId: user.uid,
                      onAccepted: (_) async => openProfile(),
                    );
                  }
                  final navigator = Navigator.of(context);
                  return ProfileScreen(
                    onProfileSaved: () async {
                      navigator.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const WebAuthGate()),
                        (_) => false,
                      );
                    },
                  );
                },
              );
            }

            final profile = profileSnapshot.data?.data() ?? {};
            if (profileSnapshot.data?.exists == true) {
              MultiAccountService()
                  .completePendingNewAccountLink()
                  .catchError((_) {});
            }
            final role = (profile['role'] ?? '').toString();
            MultiAccountState.markShellRefreshed(user.uid);
            return WebShell(
              key: ValueKey('web-shell:${user.uid}'),
              user: user,
              role: role.isEmpty ? 'worker' : role,
              profile: profile,
            );
          },
        );
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
        setState(() => error = SocialAuthService.errorMessage(failure));
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
