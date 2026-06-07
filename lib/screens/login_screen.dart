import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_preferences_service.dart';
import '../services/registration_validation_service.dart';
import '../widgets/legal_documents.dart';
import 'edit_profile_screen.dart';
import 'home_screen.dart';
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
      widget.sessionMode == AuthPreferenceMethod.simpleEnter;

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

    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      await authPreferences.enrollBiometricLoginForPasswordSession(
        user: user,
        email: email,
        password: password,
      );
    }
    return credential;
  }

  Future<void> enterWithSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => usePasswordFallback = true);
      return;
    }
    widget.onSessionUnlocked?.call();
  }

  Future<void> showBiometricUnavailableDialog({
    String message =
        "Biometric login is not set up for this account. Please sign in with Login first.",
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Biometric login is not set up."),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                returnToAuthenticationMethods();
              },
              child: const Text("Back"),
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

  Future<void> showBiometricFailureDialog(
    BiometricLoginResult result,
  ) async {
    if (!mounted) return;

    if (result.cancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      returnToAuthenticationMethods();
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Biometric authentication failed."),
          content: Text(result.message),
          actions: [
            if (result.canRetry)
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
                returnToAuthenticationMethods();
              },
              child: const Text("Back"),
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
    void showStartBiometricFailure() {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Biometric login unsuccessful. Please sign in using Login.",
          ),
        ),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => loading = true);
      try {
        final result = await authPreferences.restoreBiometricSession();
        if (!mounted) return;
        if (result.success) {
          widget.onSessionUnlocked?.call();
          return;
        }

        setState(() {
          selectedAction = null;
          usePasswordFallback = false;
        });
        showStartBiometricFailure();
      } finally {
        if (mounted) setState(() => loading = false);
      }
      return;
    }

    setState(() => loading = true);
    try {
      final result = await authPreferences.authenticateBiometricLoginResult();
      if (!mounted) return;

      if (result.success) {
        await user.reload();
        final refreshedUser = FirebaseAuth.instance.currentUser;
        if (refreshedUser == null) {
          setState(() {
            selectedAction = null;
            usePasswordFallback = false;
          });
          showStartBiometricFailure();
          return;
        }

        final userDoc = await FirebaseFirestore.instance
            .collection("users")
            .doc(refreshedUser.uid)
            .get();
        final userData = userDoc.data();
        final staleDeletedSession = !userDoc.exists ||
            userData?["deleted"] == true ||
            userData?["accountDeleted"] == true ||
            userData?["active"] == false;
        if (staleDeletedSession) {
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          setState(() {
            selectedAction = null;
            usePasswordFallback = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Saved biometric session is no longer valid. Please sign in with Login.",
              ),
            ),
          );
          return;
        }

        widget.onSessionUnlocked?.call();
      } else {
        setState(() {
          selectedAction = null;
          usePasswordFallback = false;
        });
        showStartBiometricFailure();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        selectedAction = null;
        usePasswordFallback = false;
      });
      showStartBiometricFailure();
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
        debugPrint("Registration submit started");

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
          debugPrint("Firebase Auth user created: uid=${result.user?.uid}");
        } on FirebaseAuthException catch (error) {
          RegistrationValidationService.clearPending(email);
          if (!mounted) return;
          setState(() => loading = false);
          var message =
              RegistrationValidationService.firebaseAuthErrorMessage(error);
          if (RegistrationValidationService.isEmailAlreadyInUse(error)) {
            debugPrint(
              "Firebase Auth returned email-already-in-use for: $email",
            );
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null &&
                authPreferences.normalizeEmail(currentUser.email ?? "") ==
                    email) {
              await FirebaseFirestore.instance
                  .collection("users")
                  .doc(currentUser.uid)
                  .set({
                ...pendingDetails.toUserDocument(),
                "uid": currentUser.uid,
              }, SetOptions(merge: true));
              debugPrint("Initial user document created");
              RegistrationValidationService.clearPending(email);
              await continueRegistrationOnboarding(
                uid: currentUser.uid,
                role: role,
              );
              return;
            }
            try {
              final activeProfile =
                  await registrationValidation.hasActiveAccountForEmail(email);
              if (!mounted) return;
              if (!activeProfile) {
                debugPrint(
                  "Firebase Auth orphan detected for email: $email. No active Firestore profile found.",
                );
                message =
                    "This email is linked to an unfinished or deleted authentication record. Please contact support or run cleanup.";
              }
            } on FirebaseException catch (lookupError) {
              debugPrint(
                "Could not check active Firestore profile for duplicate email: ${lookupError.code}",
              );
              if (lookupError.code == "permission-denied") {
                message =
                    "This email is linked to an unfinished or deleted authentication record. Please contact support or run cleanup.";
              }
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
            ),
          );
          return;
        }

        await FirebaseFirestore.instance
            .collection("users")
            .doc(result.user!.uid)
            .set({
          "uid": result.user!.uid,
          "role": role,
          "email": email,
          "normalizedEmail": email,
          "registrationName": registrationName,
          "phone": phone,
          "normalizedPhone": normalizedPhone,
          "emailVerified": false,
          "phoneVerified": false,
          "phoneVerificationRequired": false,
          "phoneVerificationProviderConfigured": false,
          "legalAccepted": false,
          "onboardingLegalStepComplete": false,
          "profileComplete": false,
          "onboardingComplete": false,
          "onboardingStatus": "registration_started",
          "registrationStarted": true,
          "active": true,
          "deleted": false,
          "accountDeleted": false,
          "anonymised": false,
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
            "emailVerified": false,
            "updatedAt": FieldValue.serverTimestamp(),
          },
          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        });
        await authPreferences.enrollBiometricLoginForPasswordSession(
          user: result.user!,
          email: email,
          password: password,
        );
        debugPrint("Initial user document created");
        RegistrationValidationService.clearPending(email);
        await continueRegistrationOnboarding(
          uid: result.user!.uid,
          role: role,
        );
        return;
      }
    } catch (e) {
      debugPrint("Registration submit failed: $e");
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

  Future<void> continueRegistrationOnboarding({
    required String uid,
    required String role,
  }) async {
    if (!mounted) return;
    debugPrint("Next onboarding route: legal_consent");
    final navigator = Navigator.of(context);
    setState(() {
      selectedAction = null;
      loading = false;
    });
    widget.onSessionUnlocked?.call();
    await navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LegalAcceptanceScreen(
          role: role,
          userId: uid,
          onAccepted: (_) async {
            debugPrint("Next onboarding route: profile_creation");
            await navigator.pushReplacement(
              MaterialPageRoute(
                builder: (_) => ProfileScreen(
                  onProfileSaved: () {
                    debugPrint("Next onboarding route: dashboard");
                    navigator.pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (route) => false,
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
      (route) => false,
    );
    debugPrint("Navigation completed");
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
          label: "Face ID",
          onPressed: enterWithBiometric,
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
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        await authPreferences.enrollBiometricLoginForPasswordSession(
          user: user,
          email: email,
          password: password,
        );
      }
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
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
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
        ],
      ),
    );
  }
}
