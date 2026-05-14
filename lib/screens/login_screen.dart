import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_preferences_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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

  Future<UserCredential?> handleLogin() async {
    final email = authPreferences.normalizeEmail(emailController.text);
    final passwordOrLink = passwordController.text.trim();

    if (FirebaseAuth.instance.isSignInWithEmailLink(passwordOrLink)) {
      return authPreferences.signInWithEmailLink(
        email: email,
        emailLink: passwordOrLink,
      );
    }

    final preferredMethod = await authPreferences.methodForEmail(email);

    if (passwordOrLink.isEmpty &&
        preferredMethod != AuthPreferenceMethod.biometric) {
      await authPreferences.sendPasswordlessLink(email);
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Passwordless sign-in link sent. Open it from your email, or paste it into the password field.",
          ),
        ),
      );
      return null;
    }

    if (preferredMethod == AuthPreferenceMethod.biometric &&
        passwordOrLink.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Biometric login is enabled for this account. Use your password once on this device as a secure fallback.",
          ),
        ),
      );
      return null;
    }

    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: passwordOrLink,
    );
  }

  Future<void> submit() async {
    setState(() => loading = true);

    try {
      if (isLogin) {
        await handleLogin();
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
                                const SizedBox(height: 22),
                                SizedBox(
                                  width: double.infinity,
                                  child: StroykaButton(
                                    onPressed: loading ? null : submit,
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
                                        : Text(isLogin
                                            ? "Sign in"
                                            : "Create account"),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextButton(
                                  onPressed: () {
                                    setState(() => isLogin = !isLogin);
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
