import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_preferences_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class LoginScreen extends StatefulWidget {
  final String? sessionMode;
  final VoidCallback? onSessionUnlocked;

  const LoginScreen({
    super.key,
    this.sessionMode,
    this.onSessionUnlocked,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final authPreferences = AuthPreferencesService();

  String role = "worker";
  bool isLogin = true;
  bool loading = false;
  bool usePasswordFallback = false;

  bool get hasValidSession => FirebaseAuth.instance.currentUser != null;

  bool get showSessionGate =>
      isLogin &&
      !usePasswordFallback &&
      hasValidSession &&
      (widget.sessionMode == AuthPreferenceMethod.biometric ||
          widget.sessionMode == AuthPreferenceMethod.simpleEnter);

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && emailController.text.trim().isEmpty) {
      emailController.text = user.email ?? "";
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<UserCredential?> handleLogin() async {
    final email = authPreferences.normalizeEmail(emailController.text);
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter email and password")),
      );
      return null;
    }

    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> enterWithSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => usePasswordFallback = true);
      return;
    }
    widget.onSessionUnlocked?.call();
  }

  Future<void> enterWithBiometric() async {
    setState(() => loading = true);
    try {
      final ok = await authPreferences.authenticateBiometricLogin();
      if (!mounted) return;
      if (ok) {
        widget.onSessionUnlocked?.call();
      } else {
        setState(() => usePasswordFallback = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Biometric login unavailable. Use password instead."),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => usePasswordFallback = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Biometric login failed. Use password instead."),
        ),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> submit() async {
    setState(() => loading = true);

    try {
      if (isLogin) {
        final credential = await handleLogin();
        if (credential != null) {
          widget.onSessionUnlocked?.call();
        }
      } else {
        /// REGISTER
        final email = authPreferences.normalizeEmail(emailController.text);
        final result =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: passwordController.text.trim(),
        );

        await FirebaseFirestore.instance
            .collection("users")
            .doc(result.user!.uid)
            .set({
          "role": role,
          "email": email,
          "authMethod": AuthPreferenceMethod.password,
          "settings": {
            "authMethod": AuthPreferenceMethod.password,
            "updatedAt": FieldValue.serverTimestamp(),
          },
          "authPreferences": {
            "activeMethod": AuthPreferenceMethod.password,
            "passwordLoginEnabled": true,
            "passwordlessLoginEnabled": false,
            "biometricLoginEnabled": false,
            "email": email,
            "emailVerified": result.user?.emailVerified ?? false,
            "updatedAt": FieldValue.serverTimestamp(),
          },
          "createdAt": FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }

    if (!mounted) return;
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final sessionTitle = widget.sessionMode == AuthPreferenceMethod.biometric
        ? "Biometric login"
        : "Simple Enter";
    final sessionSubtitle = widget.sessionMode == AuthPreferenceMethod.biometric
        ? "Use Face ID / Touch ID to enter your saved STROYKA session."
        : "Enter with your saved Firebase session. Password is required if the session is not valid.";

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            "assets/branding/login_background_stroyka.png",
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 58,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: const Offset(0, 18),
                          child: StroykaSurface(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                            texture: "assets/branding/texture_light_cloud.jpg",
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showSessionGate) ...[
                                  Icon(
                                    widget.sessionMode ==
                                            AuthPreferenceMethod.biometric
                                        ? Icons.fingerprint
                                        : Icons.login,
                                    size: 44,
                                    color: AppColors.greenDark,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    sessionTitle,
                                    style: const TextStyle(
                                      color: AppColors.ink,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    sessionSubtitle,
                                    textAlign: TextAlign.center,
                                    style:
                                        const TextStyle(color: AppColors.muted),
                                  ),
                                ] else ...[
                                  StroykaInputField(
                                    controller: emailController,
                                    hintText: "Email",
                                    prefixIcon: Icons.mail_outline,
                                  ),
                                  const SizedBox(height: 12),
                                  StroykaInputField(
                                    controller: passwordController,
                                    hintText: "Password",
                                    prefixIcon: Icons.lock_outline,
                                    isPassword: true,
                                  ),
                                  if (!isLogin) ...[
                                    const SizedBox(height: 12),
                                    StroykaDropdown(
                                      value: role,
                                      items: const ["worker", "employer"],
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setState(() => role = value);
                                      },
                                    ),
                                  ],
                                ],
                                const SizedBox(height: 22),
                                SizedBox(
                                  width: double.infinity,
                                  child: StroykaButton(
                                    onPressed: loading
                                        ? null
                                        : showSessionGate
                                            ? (widget.sessionMode ==
                                                    AuthPreferenceMethod
                                                        .biometric
                                                ? enterWithBiometric
                                                : enterWithSession)
                                            : submit,
                                    width: double.infinity,
                                    child: loading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(showSessionGate
                                            ? (widget.sessionMode ==
                                                    AuthPreferenceMethod
                                                        .biometric
                                                ? "Use Face ID / Touch ID"
                                                : "Enter")
                                            : isLogin
                                                ? "Sign in"
                                                : "Create account"),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (showSessionGate)
                                  TextButton(
                                    onPressed: () {
                                      setState(
                                          () => usePasswordFallback = true);
                                    },
                                    child: const Text("Use password instead"),
                                  )
                                else
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        isLogin = !isLogin;
                                        usePasswordFallback = false;
                                      });
                                    },
                                    child: Text(
                                      isLogin
                                          ? "No account? Create one"
                                          : "Already have an account? Sign in",
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
