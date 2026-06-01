import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final emailController = TextEditingController();
  bool loading = false;
  String channel = "email";

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  bool get isEmail => channel == "email";

  Future<void> sendReset() async {
    if (!isEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "SMS password recovery is not configured yet. Use email recovery.",
          ),
        ),
      );
      return;
    }

    final email = emailController.text.trim().toLowerCase();
    if (!RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$").hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid email address")),
      );
      return;
    }

    setState(() => loading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Password reset email sent. Follow the secure Firebase link to set a new password.",
          ),
        ),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Could not send reset email")),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StroykaBackground(
      asset: AppAssets.backgroundWorkersCity,
      child: Scaffold(
        appBar: AppBar(title: const Text("Password recovery")),
        body: StroykaScreenBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              StroykaSurface(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "Restore access",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Email recovery uses Firebase secure password reset. SMS recovery will be enabled when a phone verification provider is configured.",
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 18),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: "email",
                          icon: Icon(Icons.mail_outline),
                          label: Text("Email"),
                        ),
                        ButtonSegment(
                          value: "phone",
                          icon: Icon(Icons.sms_outlined),
                          label: Text("SMS"),
                        ),
                      ],
                      selected: {channel},
                      onSelectionChanged: (value) {
                        setState(() => channel = value.first);
                      },
                    ),
                    const SizedBox(height: 16),
                    StroykaInputField(
                      controller: emailController,
                      hintText: isEmail ? "Email" : "Phone",
                      prefixIcon:
                          isEmail ? Icons.mail_outline : Icons.phone_outlined,
                    ),
                    if (!isEmail) ...[
                      const SizedBox(height: 8),
                      const Text(
                        "SMS verification provider is not configured yet.",
                        style: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    StroykaButton(
                      onPressed: loading ? null : sendReset,
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(isEmail ? "Send reset email" : "Send SMS"),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
