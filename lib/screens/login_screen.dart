import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  String role = "worker";
  bool isLogin = true;
  bool loading = false;

  Future<void> submit() async {
    setState(() => loading = true);

    try {
      UserCredential result;

      if (isLogin) {
        /// LOGIN
        result = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      } else {
        /// REGISTER
        result = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );

        await FirebaseFirestore.instance
            .collection("users")
            .doc(result.user!.uid)
            .set({
          "role": role,
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
                                  child: Opacity(
                                    opacity: loading ? 0.48 : 1,
                                    child: BlueprintFrame(
                                      height: 48,
                                      onTap: loading ? null : submit,
                                      child: loading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(
                                              isLogin
                                                  ? "Sign in"
                                                  : "Create account",
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1.1,
                                              ),
                                            ),
                                    ),
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
