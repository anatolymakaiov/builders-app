import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_preferences_service.dart';
import '../services/registration_validation_service.dart';
import 'password_recovery_screen.dart';
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
  final registrationNameController = TextEditingController();
  final phoneController = TextEditingController();
  final authPreferences = AuthPreferencesService();
  final registrationValidation = RegistrationValidationService();

  String role = "worker";
  String? selectedAction;
  bool isLogin = true;
  bool loading = false;
  bool usePasswordFallback = false;

  bool get hasValidSession => FirebaseAuth.instance.currentUser != null;

  bool get hasRegistrationDraft =>
      registrationNameController.text.trim().isNotEmpty ||
      emailController.text.trim().isNotEmpty ||
      passwordController.text.trim().isNotEmpty ||
      phoneController.text.trim().isNotEmpty;

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
    if (widget.sessionMode != null) {
      selectedAction = widget.sessionMode == AuthPreferenceMethod.biometric
          ? "biometric"
          : "password";
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    registrationNameController.dispose();
    phoneController.dispose();
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

  Future<void> showBiometricFailureDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Biometric authentication failed."),
          content: const Text(
            "Try again or use the standard login method.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                enterWithBiometric();
              },
              child: const Text("Try Again"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                openPasswordLogin();
              },
              child: const Text("Use Login"),
            ),
          ],
        );
      },
    );
  }

  Future<void> enterWithBiometric() async {
    setState(() => loading = true);
    try {
      final ok = await authPreferences.authenticateBiometricLogin();
      if (!mounted) return;
      if (ok) {
        widget.onSessionUnlocked?.call();
      } else {
        setState(() {
          selectedAction = null;
          usePasswordFallback = false;
        });
        await showBiometricFailureDialog();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        selectedAction = null;
        usePasswordFallback = false;
      });
      await showBiometricFailureDialog();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> returnToAuthenticationMethods() async {
    if (!isLogin && hasRegistrationDraft) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text("Leave registration?"),
            content: const Text("Your entered information will not be saved."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Stay"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Leave"),
              ),
            ],
          );
        },
      );
      if (leave != true || !mounted) return;
      registrationNameController.clear();
      passwordController.clear();
      phoneController.clear();
    }

    if (!mounted) return;
    setState(() {
      selectedAction = null;
      isLogin = true;
      usePasswordFallback = false;
      loading = false;
    });
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
        final password = passwordController.text.trim();
        final registrationName = registrationNameController.text.trim();
        final phone = phoneController.text.trim();
        final normalizedPhone =
            RegistrationValidationService.normalizePhone(phone);

        if (registrationName.isEmpty ||
            email.isEmpty ||
            phone.isEmpty ||
            password.isEmpty) {
          if (!mounted) return;
          setState(() => loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Enter name, email, phone and password"),
            ),
          );
          return;
        }

        final validation = await registrationValidation.validate(
          email: email,
          phone: phone,
        );
        if (validation.hasErrors) {
          if (!mounted) return;
          setState(() => loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(validation.message)),
          );
          return;
        }

        final pendingDetails = PendingRegistrationDetails(
          email: email,
          role: role,
          registrationName: registrationName,
          phone: phone,
          normalizedPhone: normalizedPhone,
        );
        RegistrationValidationService.rememberPending(pendingDetails);

        UserCredential result;
        try {
          result = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } on FirebaseAuthException catch (error) {
          RegistrationValidationService.clearPending(email);
          if (!mounted) return;
          setState(() => loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                RegistrationValidationService.firebaseAuthErrorMessage(error),
              ),
            ),
          );
          return;
        }
        await result.user?.sendEmailVerification();

        await FirebaseFirestore.instance
            .collection("users")
            .doc(result.user!.uid)
            .set({
          "role": role,
          "email": email,
          "registrationName": registrationName,
          "phone": phone,
          "normalizedPhone": normalizedPhone,
          "emailVerified": result.user?.emailVerified ?? false,
          "phoneVerified": false,
          "phoneVerificationRequired": false,
          "phoneVerificationProviderConfigured": false,
          "legalAccepted": false,
          "onboardingLegalStepComplete": false,
          "profileComplete": false,
          "onboardingComplete": false,
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
            "emailVerificationSentAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
          },
          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        });
        RegistrationValidationService.clearPending(email);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not create account. Please try again."),
        ),
      );
    }

    if (!mounted) return;
    setState(() => loading = false);
  }

  Future<void> openPasswordRecovery() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PasswordRecoveryScreen()),
    );
  }

  Future<void> openPasswordLogin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PasswordLoginScreen(
          initialEmail: emailController.text,
          onSessionUnlocked: widget.onSessionUnlocked,
        ),
      ),
    );
  }

  Widget buildStartChoices() {
    Widget actionButton({
      required String label,
      required VoidCallback onPressed,
    }) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            side: BorderSide(
              color: AppColors.blueprintLine.withValues(alpha: 0.92),
              width: 1.4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
            shadowColor: Colors.transparent,
          ),
          child: Text(label),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        actionButton(
          label: "Login",
          onPressed: openPasswordLogin,
        ),
        const SizedBox(height: 12),
        actionButton(
          label: "Biometric",
          onPressed: hasValidSession
              ? () {
                  setState(() {
                    selectedAction = "biometric";
                    isLogin = true;
                    usePasswordFallback = false;
                  });
                  enterWithBiometric();
                }
              : () {
                  showBiometricFailureDialog();
                },
        ),
        const SizedBox(height: 12),
        actionButton(
          label: "Registration",
          onPressed: () {
            setState(() {
              selectedAction = "register";
              isLogin = false;
              usePasswordFallback = true;
            });
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionTitle = widget.sessionMode == AuthPreferenceMethod.biometric
        ? "Biometric login"
        : "Simple Enter";
    final sessionSubtitle = widget.sessionMode == AuthPreferenceMethod.biometric
        ? "Use Face ID / Touch ID to enter your saved STROYKA session."
        : "Enter with your saved Firebase session. Password is required if the session is not valid.";
    final isStartChoice = !showSessionGate && selectedAction == null;

    Widget authContent() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isStartChoice) ...[
            buildStartChoices(),
          ] else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: loading ? null : returnToAuthenticationMethods,
                icon: const Icon(Icons.arrow_back),
                label: const Text("Back"),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (showSessionGate) ...[
            Icon(
              widget.sessionMode == AuthPreferenceMethod.biometric
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
              style: const TextStyle(color: AppColors.muted),
            ),
          ] else if (!isStartChoice) ...[
            if (!isLogin) ...[
              StroykaInputField(
                controller: registrationNameController,
                hintText: "First name / contact name",
                prefixIcon: Icons.person_outline,
              ),
              const SizedBox(height: 12),
            ],
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
              StroykaInputField(
                controller: phoneController,
                hintText: "Phone",
                prefixIcon: Icons.phone_outlined,
              ),
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
          if (selectedAction != null || showSessionGate) ...[
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: StroykaButton(
                onPressed: loading
                    ? null
                    : showSessionGate
                        ? (widget.sessionMode == AuthPreferenceMethod.biometric
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
                        ? (widget.sessionMode == AuthPreferenceMethod.biometric
                            ? "Use Face ID / Touch ID"
                            : "Enter")
                        : isLogin
                            ? "Sign in"
                            : "Create account"),
              ),
            ),
            const SizedBox(height: 8),
            if (isLogin && !showSessionGate)
              TextButton(
                onPressed: openPasswordRecovery,
                child: const Text("Forgot password?"),
              ),
            const SizedBox(height: 6),
            if (showSessionGate)
              TextButton(
                onPressed: openPasswordLogin,
                child: const Text("Use password instead"),
              ),
          ],
        ],
      );
    }

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
                        FractionalTranslation(
                          translation: const Offset(0, 0.08),
                          child: FractionallySizedBox(
                            widthFactor: 0.88,
                            child: isStartChoice
                                ? authContent()
                                : StroykaSurface(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 24, 20, 20),
                                    texture:
                                        "assets/branding/texture_light_cloud.jpg",
                                    child: authContent(),
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

class PasswordLoginScreen extends StatefulWidget {
  final String initialEmail;
  final VoidCallback? onSessionUnlocked;

  const PasswordLoginScreen({
    super.key,
    this.initialEmail = "",
    this.onSessionUnlocked,
  });

  @override
  State<PasswordLoginScreen> createState() => _PasswordLoginScreenState();
}

class _PasswordLoginScreenState extends State<PasswordLoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final authPreferences = AuthPreferencesService();
  bool loading = false;

  @override
  void initState() {
    super.initState();
    emailController.text = widget.initialEmail;
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    final email = authPreferences.normalizeEmail(emailController.text);
    final password = passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter email and password")),
      );
      return;
    }

    setState(() => loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      widget.onSessionUnlocked?.call();
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not sign in. Please try again.")),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> openPasswordRecovery() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PasswordRecoveryScreen()),
    );
  }

  void returnToAuthenticationMethods() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          onSessionUnlocked: widget.onSessionUnlocked,
        ),
      ),
      (route) => false,
    );
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
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 6),
                child: IconButton(
                  onPressed: loading ? null : returnToAuthenticationMethods,
                  tooltip: "Authentication methods",
                  icon: const Icon(
                    Icons.exit_to_app,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    24 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 48,
                    ),
                    child: Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.88,
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
                              const SizedBox(height: 20),
                              StroykaButton(
                                onPressed: loading ? null : signIn,
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
                                    : const Text("Sign In"),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: openPasswordRecovery,
                                child: const Text("Forgot Password?"),
                              ),
                            ],
                          ),
                        ),
                      ),
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
