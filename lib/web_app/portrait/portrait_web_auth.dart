import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../screens/login_screen.dart';
import '../../screens/password_recovery_screen.dart';
import '../../theme/app_theme.dart';
import '../../theme/stroyka_background.dart';
import '../services/web_password_sign_in.dart';

Widget portraitWebAuthPage(Widget page) => PortraitWebAuthFrame(
      backdrop: page is LoginScreen,
      child: page,
    );

class PortraitWebAuthFrame extends StatelessWidget {
  const PortraitWebAuthFrame(
      {super.key, required this.child, this.backdrop = false});

  final Widget child;
  final bool backdrop;

  @override
  Widget build(BuildContext context) => Theme(
        data: AppTheme.light,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              if (backdrop)
                Image.asset(
                  'assets/branding/login_background_stroyka.png',
                  fit: BoxFit.cover,
                )
              else
                const StroykaBackground(
                  asset: AppAssets.backgroundWorkersCity,
                  child: SizedBox.expand(),
                ),
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: math.min(560, constraints.maxWidth),
                  height: constraints.maxHeight,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      );
}

class PortraitWebRegistration extends StatelessWidget {
  const PortraitWebRegistration(
      {super.key, required this.homeBuilder, this.resume = false});

  final WidgetBuilder homeBuilder;
  final bool resume;

  @override
  Widget build(BuildContext context) => portraitWebAuthPage(LoginScreen(
        key: ValueKey(
            resume ? 'portrait-registration-resume' : 'portrait-registration'),
        initialRegistration: true,
        resumeRegistration: resume,
        authPageBuilder: portraitWebAuthPage,
        postRegistrationHomeBuilder: homeBuilder,
      ));
}

class PortraitWebLanding extends StatelessWidget {
  const PortraitWebLanding({super.key, required this.homeBuilder});

  final WidgetBuilder homeBuilder;

  void _open(BuildContext context, Widget page) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      );

  @override
  Widget build(BuildContext context) => Theme(
        data: AppTheme.light,
        child: Scaffold(
          body: StroykaBackground(
            asset: AppAssets.backgroundCranesYard,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('STROYKA',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            )),
                        const SizedBox(height: 42),
                        _LandingAction(
                          label: 'Enter',
                          onPressed: () => _open(
                              context,
                              PortraitWebPasswordLogin(
                                  homeBuilder: homeBuilder)),
                        ),
                        const SizedBox(height: 12),
                        _LandingAction(
                          label: 'Registration',
                          onPressed: () => _open(
                              context,
                              PortraitWebRegistration(
                                  homeBuilder: homeBuilder)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _LandingAction extends StatelessWidget {
  const _LandingAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            side: const BorderSide(color: AppColors.blueprintLine, width: 1.4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          child: Text(label),
        ),
      );
}

class PortraitWebPasswordLogin extends StatefulWidget {
  const PortraitWebPasswordLogin({
    super.key,
    required this.homeBuilder,
    this.authenticate,
  });

  final WidgetBuilder homeBuilder;
  final Future<void> Function(String email, String password)? authenticate;

  @override
  State<PortraitWebPasswordLogin> createState() =>
      _PortraitWebPasswordLoginState();
}

class _PortraitWebPasswordLoginState extends State<PortraitWebPasswordLogin> {
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

  Future<void> _signIn() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (widget.authenticate != null) {
        await widget.authenticate!(
            emailController.text, passwordController.text);
      } else {
        await const WebPasswordSignIn()(
          email: emailController.text,
          password: passwordController.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (exception) {
      if (mounted) setState(() => error = exception.message ?? exception.code);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not sign in. Please try again.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _openRecovery() {
    setState(() => error = null);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => portraitWebAuthPage(PasswordRecoveryScreen(
        initialEmail: emailController.text,
        webFramed: true,
      )),
    ));
  }

  void _openRegistration() {
    setState(() => error = null);
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => PortraitWebRegistration(homeBuilder: widget.homeBuilder),
    ));
  }

  @override
  Widget build(BuildContext context) => PortraitWebAuthFrame(
        backdrop: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minHeight: math.max(0, constraints.maxHeight - 44)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back'),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 20),
                      StroykaSurface(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Enter',
                                style: TextStyle(
                                    fontSize: 23, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 20),
                            TextField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration:
                                  const InputDecoration(labelText: 'Email'),
                              onSubmitted: (_) => _signIn(),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: passwordController,
                              obscureText: true,
                              autofillHints: const [AutofillHints.password],
                              decoration:
                                  const InputDecoration(labelText: 'Password'),
                              onSubmitted: (_) => _signIn(),
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              Text(error!,
                                  style:
                                      const TextStyle(color: AppColors.danger)),
                            ],
                            const SizedBox(height: 22),
                            StroykaButton(
                              onPressed: loading ? null : _signIn,
                              width: double.infinity,
                              child: loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Sign in'),
                            ),
                            TextButton(
                              onPressed: loading ? null : _openRecovery,
                              child: const Text('Forgot password?'),
                            ),
                            OutlinedButton(
                              onPressed: loading ? null : _openRegistration,
                              child: const Text('Registration'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
