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
      body: SafeArea(
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
                    Text(
                      "STROYKA",
                      textAlign: TextAlign.center,
                      style: AppTypography.title.copyWith(
                        fontSize: 46,
                        letterSpacing: 3.2,
                        shadows: [
                          Shadow(
                            color: AppColors.glow.withValues(alpha: 0.46),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Construction work platform",
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(
                        color: AppColors.blueprintLine,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 42),
                    StroykaSurface(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      texture: "assets/branding/texture_light_cloud.jpg",
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: emailController,
                            decoration: AppInputFields.decoration(
                              label: "Email",
                              icon: Icons.mail_outline,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: passwordController,
                            decoration: AppInputFields.decoration(
                              label: "Password",
                              icon: Icons.lock_outline,
                            ),
                            obscureText: true,
                          ),
                          if (!isLogin) ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: role,
                              decoration: AppInputFields.decoration(
                                label: "Account type",
                                icon: Icons.account_circle_outlined,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: "worker",
                                  child: Text("Worker"),
                                ),
                                DropdownMenuItem(
                                  value: "employer",
                                  child: Text("Employer"),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => role = value);
                              },
                            ),
                          ],
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: loading ? null : submit,
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
                                      isLogin ? "Sign in" : "Create account"),
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
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
