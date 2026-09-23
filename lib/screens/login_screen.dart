import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_preferences_service.dart';
import '../services/post_registration_refresh_service.dart';
import '../services/multi_account_service.dart';
import '../services/registration_validation_service.dart';
import '../services/social_auth_service.dart';
import '../services/registration_wizard_steps.dart';
import '../widgets/legal_documents.dart';
import '../widgets/uk_postal_address_form.dart';
import 'edit_profile_screen.dart';
import 'home_screen.dart';
import 'password_recovery_screen.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class LoginScreen extends StatefulWidget {
  final String? sessionMode;
  final VoidCallback? onSessionUnlocked;
  final WidgetBuilder? postRegistrationHomeBuilder;
  final bool initialRegistration;
  final bool resumeRegistration;

  const LoginScreen({
    super.key,
    this.sessionMode,
    this.onSessionUnlocked,
    this.postRegistrationHomeBuilder,
    this.initialRegistration = false,
    this.resumeRegistration = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final registrationNameController = TextEditingController();
  final registrationLastNameController = TextEditingController();
  final registrationTradeController = TextEditingController();
  final registrationCompanyController = TextEditingController();
  final registrationPostcodeController = TextEditingController();
  final registrationAddressLine1Controller = TextEditingController();
  final registrationAddressLine2Controller = TextEditingController();
  final registrationAddressLine3Controller = TextEditingController();
  final registrationTownCityController = TextEditingController();
  final registrationCountyController = TextEditingController();
  final registrationCountryController =
      TextEditingController(text: 'United Kingdom');
  final phoneController = TextEditingController();
  final authPreferences = AuthPreferencesService();
  final registrationValidation = RegistrationValidationService();
  final postRegistrationRefresh = PostRegistrationRefreshService();

  String role = "worker";
  String? selectedAction;
  bool isLogin = true;
  bool loading = false;
  bool usePasswordFallback = false;
  int registrationStep = 0;
  bool registrationMethodSelected = false;
  bool registrationDraftLoading = false;
  SocialProvider? registrationProvider;
  bool providerEmailVerified = false;
  String registrationPhotoUrl = '';
  final socialAuth = SocialAuthService();

  bool get hasValidSession => FirebaseAuth.instance.currentUser != null;

  bool get hasRegistrationDraft =>
      registrationNameController.text.trim().isNotEmpty ||
      registrationLastNameController.text.trim().isNotEmpty ||
      registrationTradeController.text.trim().isNotEmpty ||
      registrationCompanyController.text.trim().isNotEmpty ||
      registrationAddressLine1Controller.text.trim().isNotEmpty ||
      emailController.text.trim().isNotEmpty ||
      passwordController.text.trim().isNotEmpty ||
      phoneController.text.trim().isNotEmpty;

  bool get showSessionGate =>
      isLogin &&
      !usePasswordFallback &&
      hasValidSession &&
      selectedAction == 'session';

  UkPostalAddressControllers registrationAddressControllers() =>
      UkPostalAddressControllers(
        postcode: registrationPostcodeController,
        addressLine1: registrationAddressLine1Controller,
        addressLine2: registrationAddressLine2Controller,
        addressLine3: registrationAddressLine3Controller,
        townCity: registrationTownCityController,
        county: registrationCountyController,
        country: registrationCountryController,
      );

  PendingRegistrationDetails registrationDetails() {
    final firstName = registrationNameController.text.trim();
    final lastName = registrationLastNameController.text.trim();
    final phone = phoneController.text.trim();
    return PendingRegistrationDetails(
      email: authPreferences.normalizeEmail(emailController.text),
      role: role,
      registrationName: '$firstName $lastName'.trim(),
      phone: phone,
      normalizedPhone: RegistrationValidationService.normalizePhone(phone),
      firstName: firstName,
      lastName: lastName,
      trade: registrationTradeController.text.trim(),
      companyName: registrationCompanyController.text.trim(),
      address: registrationAddressControllers().value(),
      emailVerified: providerEmailVerified &&
          authPreferences.normalizeEmail(emailController.text) ==
              authPreferences.normalizeEmail(
                  FirebaseAuth.instance.currentUser?.email ?? ''),
      phoneVerified: phoneController.text.trim().isNotEmpty &&
          RegistrationValidationService.normalizePhone(phoneController.text) ==
              RegistrationValidationService.normalizePhone(
                  FirebaseAuth.instance.currentUser?.phoneNumber ?? ''),
      photoUrl: registrationPhotoUrl,
    );
  }

  String? validateRegistrationStep(RegistrationWizardStep step) =>
      RegistrationWizardSteps.validate(
        step,
        role: role,
        firstName: registrationNameController.text,
        lastName: registrationLastNameController.text,
        trade: registrationTradeController.text,
        companyName: registrationCompanyController.text,
        addressLine1: registrationAddressLine1Controller.text,
        townCity: registrationTownCityController.text,
        postcode: registrationPostcodeController.text,
        country: registrationCountryController.text,
        email: emailController.text,
        phone: phoneController.text,
        password: passwordController.text,
      );

  String? validateRegistrationDetails({bool requirePassword = true}) {
    for (final step in RegistrationWizardStep.values) {
      if ((!requirePassword || registrationProvider != null) &&
          step == RegistrationWizardStep.credentials) {
        continue;
      }
      final error = validateRegistrationStep(step);
      if (error != null) return error;
    }
    return null;
  }

  void nextRegistrationStep() {
    if (loading) return;
    final step = RegistrationWizardStep.values[registrationStep];
    final error = registrationProvider != null &&
            step == RegistrationWizardStep.credentials
        ? null
        : validateRegistrationStep(step);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (registrationStep < RegistrationWizardSteps.count - 1) {
      setState(() => registrationStep++);
    } else {
      submit();
    }
  }

  Future<void> enrollBiometricAfterPasswordLogin({
    required User user,
    required String email,
    required String password,
  }) async {
    if (kIsWeb) return;
    try {
      await authPreferences.enrollBiometricLoginForPasswordSession(
        user: user,
        email: email,
        password: password,
      );
    } catch (error) {
      debugPrint("Biometric enrollment skipped after password login: $error");
    }
  }

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && emailController.text.trim().isEmpty) {
      emailController.text = user.email ?? "";
    }
    if (widget.initialRegistration) {
      isLogin = false;
      selectedAction = 'register';
      registrationMethodSelected = widget.resumeRegistration;
      if (widget.resumeRegistration) {
        registrationDraftLoading = true;
        loadRegistrationDraft();
      }
    }
  }

  Future<void> loadRegistrationDraft() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snapshot = await FirebaseFirestore.instance
          .collection('pending_registrations')
          .doc(user.uid)
          .get();
      final data = snapshot.data() ?? <String, dynamic>{};
      final provider = SocialProvider.values.where(
        (candidate) => candidate.name == data['authMethod'],
      );
      final storedName = (data['registrationName'] ?? '').toString().trim();
      final name =
          storedName.isEmpty ? (user.displayName ?? '').trim() : storedName;
      final parts = name.split(RegExp(r'\s+'));
      if (!mounted) return;
      setState(() {
        role = data['role'] == 'employer' ? 'employer' : 'worker';
        registrationProvider = provider.isEmpty
            ? SocialAuthService.providerFromIds(
                user.providerData.map((identity) => identity.providerId))
            : provider.first;
        providerEmailVerified = user.emailVerified;
        registrationNameController.text =
            (data['registrationFirstName'] ?? parts.first).toString();
        registrationLastNameController.text = (data['registrationLastName'] ??
                (parts.length > 1 ? parts.skip(1).join(' ') : ''))
            .toString();
        registrationTradeController.text =
            (data['registrationPosition'] ?? '').toString();
        registrationCompanyController.text =
            (data['registrationCompanyName'] ?? '').toString();
        registrationAddressLine1Controller.text =
            (data['addressLine1'] ?? '').toString();
        registrationAddressLine2Controller.text =
            (data['addressLine2'] ?? '').toString();
        registrationAddressLine3Controller.text =
            (data['addressLine3'] ?? '').toString();
        registrationTownCityController.text =
            (data['townCity'] ?? '').toString();
        registrationCountyController.text = (data['county'] ?? '').toString();
        registrationPostcodeController.text =
            (data['postcode'] ?? '').toString();
        registrationCountryController.text =
            (data['country'] ?? 'United Kingdom').toString();
        final storedEmail = (data['email'] ?? '').toString().trim();
        emailController.text =
            storedEmail.isEmpty ? user.email ?? '' : storedEmail;
        final storedPhone = (data['phone'] ?? '').toString().trim();
        phoneController.text =
            storedPhone.isEmpty ? user.phoneNumber ?? '' : storedPhone;
        final storedPhoto = (data['photo'] ?? '').toString().trim();
        registrationPhotoUrl =
            storedPhoto.isEmpty ? user.photoURL ?? '' : storedPhoto;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not restore registration. Please try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => registrationDraftLoading = false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    registrationNameController.dispose();
    registrationLastNameController.dispose();
    registrationTradeController.dispose();
    registrationCompanyController.dispose();
    registrationPostcodeController.dispose();
    registrationAddressLine1Controller.dispose();
    registrationAddressLine2Controller.dispose();
    registrationAddressLine3Controller.dispose();
    registrationTownCityController.dispose();
    registrationCountyController.dispose();
    registrationCountryController.dispose();
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
      try {
        await SocialAuthService.linkAfterVerifiedPasswordSignIn(user);
      } catch (error) {
        debugPrint('Optional social account link failed: $error');
      }
      await enrollBiometricAfterPasswordLogin(
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

  Future<void> enter() async {
    if (hasValidSession) {
      setState(() => selectedAction = 'session');
      if (widget.sessionMode == AuthPreferenceMethod.biometric) {
        await enterWithBiometric();
      } else {
        await enterWithSession();
      }
      return;
    }
    await enterWithBiometric();
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

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BiometricFallbackDialog(
        result: result,
        onRetry: () {
          Navigator.pop(dialogContext);
          enterWithBiometric();
        },
        onBack: () {
          Navigator.pop(dialogContext);
          returnToAuthenticationMethods();
        },
        onPassword: () {
          Navigator.pop(dialogContext);
          openPasswordLogin();
        },
      ),
    );
  }

  Future<void> enterWithBiometric() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => loading = true);
      try {
        final result = await authPreferences.restoreBiometricSession();
        if (result.success) {
          widget.onSessionUnlocked?.call();
          return;
        }
        if (!mounted) return;

        if (result.needsPasswordLogin) {
          await openPasswordLogin();
          return;
        }
        await showBiometricFailureDialog(result);
      } catch (_) {
        if (!mounted) return;
        await showBiometricFailureDialog(const BiometricLoginResult(
          success: false,
          message:
              'Could not restore your secure session. Sign in with email and password.',
        ));
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
          await openPasswordLogin();
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
          await openPasswordLogin();
          return;
        }

        widget.onSessionUnlocked?.call();
      } else {
        await showBiometricFailureDialog(result);
      }
    } catch (error) {
      if (!mounted) return;
      await showBiometricFailureDialog(const BiometricLoginResult(
        success: false,
        message: 'Biometric sign-in could not be completed. Try your password.',
      ));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> returnToAuthenticationMethods() async {
    if (!isLogin && hasRegistrationDraft) {
      final hasSocialDraft = registrationProvider != null;
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text("Leave registration?"),
            content: Text(hasSocialDraft
                ? 'You can return to this registration by signing in with the same provider.'
                : 'Your entered information will not be saved.'),
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
      registrationLastNameController.clear();
      registrationTradeController.clear();
      registrationCompanyController.clear();
      registrationPostcodeController.clear();
      registrationAddressLine1Controller.clear();
      registrationAddressLine2Controller.clear();
      registrationAddressLine3Controller.clear();
      registrationTownCityController.clear();
      registrationCountyController.clear();
      registrationCountryController.text = 'United Kingdom';
      passwordController.clear();
      phoneController.clear();
      RegistrationValidationService.clearPending(emailController.text);
    }

    if (registrationProvider != null) {
      await FirebaseAuth.instance.signOut();
    }

    if (!mounted) return;
    setState(() {
      selectedAction = null;
      isLogin = true;
      usePasswordFallback = false;
      loading = false;
      registrationStep = 0;
      registrationMethodSelected = false;
      registrationProvider = null;
      providerEmailVerified = false;
      registrationPhotoUrl = '';
    });
  }

  Future<void> createPendingRegistration({
    required User user,
    required PendingRegistrationDetails details,
    SocialProvider? socialProvider,
    bool formComplete = true,
  }) async {
    debugPrint(
        "REGISTRATION STAGE START: pending_registration uid=${user.uid}");
    final document = details.toUserDocument();
    if (socialProvider != null) {
      document['authMethod'] = socialProvider.name;
      document['emailVerified'] = details.emailVerified;
      document['settings'] = {
        ...Map<String, dynamic>.from(document['settings'] as Map),
        'authMethod': socialProvider.name,
      };
      document['authPreferences'] = {
        ...Map<String, dynamic>.from(document['authPreferences'] as Map),
        'activeMethod': socialProvider.name,
        'passwordLoginEnabled': false,
        'emailVerified': details.emailVerified,
      };
    }
    await FirebaseFirestore.instance
        .collection("pending_registrations")
        .doc(user.uid)
        .set({
      ...document,
      "uid": user.uid,
      "active": false,
      "draft": true,
      "pendingRegistration": true,
      'registrationFormComplete': formComplete,
      "deleted": false,
      "accountDeleted": false,
      "anonymised": false,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint("Initial pending registration document created");
  }

  Future<void> rollbackCreatedRegistration({
    required User? user,
    required String email,
    required String reason,
  }) async {
    debugPrint("ROLLBACK START: uid=${user?.uid ?? "none"} reason=$reason");
    RegistrationValidationService.clearPending(email);
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection("pending_registrations")
            .doc(user.uid)
            .delete();
      } catch (error) {
        debugPrint(
            "Could not remove pending registration during rollback: $error");
      }
      try {
        await user.delete();
      } catch (error) {
        debugPrint("Could not delete auth user during rollback: $error");
        await FirebaseAuth.instance.signOut();
      }
    }
    debugPrint("ROLLBACK SUCCESS: uid=${user?.uid ?? "none"}");
  }

  Future<void> submit() async {
    if (loading) return;
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
        final details = registrationDetails();
        final phone = details.phone;
        debugPrint("Registration submit started");

        final stepError = validateRegistrationDetails();
        if (stepError != null) {
          if (!mounted) return;
          setState(() => loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(stepError),
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

        if (registrationProvider != null) {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) {
            throw StateError(
                'Your provider session has expired. Sign in again.');
          }
          await createPendingRegistration(
            user: user,
            details: details,
            socialProvider: registrationProvider,
          );
          await continueRegistrationOnboarding(uid: user.uid, role: role);
          return;
        }

        final pendingDetails = details;
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
              final currentPhoneAvailability =
                  await registrationValidation.checkPhoneAvailability(phone);
              if (!currentPhoneAvailability.available) {
                RegistrationValidationService.clearPending(email);
                if (!mounted) return;
                setState(() => loading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      currentPhoneAvailability.blockingMessage ??
                          "An active account with this phone number already exists.",
                    ),
                  ),
                );
                return;
              }
              await createPendingRegistration(
                user: currentUser,
                details: pendingDetails,
              );
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

        final postAuthPhoneAvailability =
            await registrationValidation.checkPhoneAvailability(phone);
        if (!postAuthPhoneAvailability.available) {
          await rollbackCreatedRegistration(
            user: result.user,
            email: email,
            reason: "duplicate_phone_after_auth",
          );
          if (!mounted) return;
          setState(() => loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                postAuthPhoneAvailability.blockingMessage ??
                    "An active account with this phone number already exists.",
              ),
            ),
          );
          return;
        }

        try {
          await createPendingRegistration(
            user: result.user!,
            details: pendingDetails,
          );
        } catch (error) {
          await rollbackCreatedRegistration(
            user: result.user,
            email: email,
            reason: "pending_registration_write_failed",
          );
          rethrow;
        }
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
                  onProfileSaved: () async {
                    debugPrint("Next onboarding route: dashboard");
                    await postRegistrationRefresh.refreshAfterRegistration(uid);
                    try {
                      await MultiAccountService()
                          .completePendingNewAccountLink();
                    } catch (error) {
                      debugPrint(
                        "Pending account link could not be completed: $error",
                      );
                    }
                    navigator.pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: widget.postRegistrationHomeBuilder ??
                            (_) => const HomeScreen(),
                      ),
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

  Future<void> signInSocial(SocialProvider provider) async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final result = await socialAuth.signIn(provider);
      if (result.cancelled) return;
      final user = result.credential?.user;
      if (user == null) throw StateError('Sign-in did not return an account.');
      if (isLogin) {
        widget.onSessionUnlocked?.call();
        return;
      }

      final existing = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (existing.exists) {
        widget.onSessionUnlocked?.call();
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
        return;
      }
      if (user.emailVerified && (user.email ?? '').trim().isNotEmpty) {
        try {
          final availability =
              await registrationValidation.checkEmailAvailability(user.email!);
          if (!availability.available) {
            final linkCredential = result.credential?.credential;
            final verifiedEmail = user.email;
            if (result.credential?.additionalUserInfo?.isNewUser == true) {
              try {
                await user.delete();
              } catch (_) {
                await FirebaseAuth.instance.signOut();
                throw StateError(
                  'This email already has an account. Sign in to the existing account before linking this provider.',
                );
              }
              SocialAuthService.rememberVerifiedProviderForLink(
                credential: linkCredential,
                email: verifiedEmail,
              );
            } else {
              await FirebaseAuth.instance.signOut();
            }
            throw StateError(
              'This email already has an account. Sign in with its existing verified account to link this provider.',
            );
          }
        } on FirebaseException catch (error) {
          if (error.code != 'permission-denied') rethrow;
        }
      }
      final draft = await FirebaseFirestore.instance
          .collection('pending_registrations')
          .doc(user.uid)
          .get();
      if (draft.exists && draft.data()?['registrationFormComplete'] != false) {
        await continueRegistrationOnboarding(
          uid: user.uid,
          role: draft.data()?['role'] == 'employer' ? 'employer' : 'worker',
        );
        return;
      }
      if (!draft.exists) {
        final prefill = PendingRegistrationDetails.fromSocialIdentity(
          email: user.email,
          displayName: user.displayName,
          photoUrl: user.photoURL,
          verifiedPhoneNumber: user.phoneNumber,
          emailVerified: user.emailVerified,
        );
        await createPendingRegistration(
          user: user,
          details: prefill,
          socialProvider: provider,
          formComplete: false,
        );
      }
      if (!mounted) return;
      setState(() {
        registrationProvider = provider;
        registrationMethodSelected = true;
      });
      await loadRegistrationDraft();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error is StateError
            ? error.message.toString()
            : SocialAuthService.errorMessage(error)),
      ));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget socialActions() => Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          for (final provider in SocialProvider.values)
            if (SocialAuthService.available(provider))
              TextButton(
                onPressed: loading ? null : () => signInSocial(provider),
                child: Text(switch (provider) {
                  SocialProvider.google => 'Google',
                  SocialProvider.apple => 'Apple ID',
                  SocialProvider.facebook => 'Facebook',
                }),
              ),
        ],
      );

  Widget buildRegistrationMethodChoices() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Create your account',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          for (final provider in SocialProvider.values)
            if (SocialAuthService.available(provider)) ...[
              OutlinedButton(
                onPressed: loading ? null : () => signInSocial(provider),
                child: Text(switch (provider) {
                  SocialProvider.google => 'Continue with Google',
                  SocialProvider.apple => 'Continue with Apple',
                  SocialProvider.facebook => 'Continue with Facebook',
                }),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 4),
          OutlinedButton(
            onPressed: loading
                ? null
                : () => setState(() => registrationMethodSelected = true),
            child: const Text('Register with email'),
          ),
        ],
      );

  Widget buildRegistrationWizardFields() {
    final step = RegistrationWizardStep.values[registrationStep];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Step ${registrationStep + 1} of ${RegistrationWizardSteps.count}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: (registrationStep + 1) / RegistrationWizardSteps.count,
        ),
        const SizedBox(height: 18),
        Text(
          RegistrationWizardSteps.title(step, role),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        switch (step) {
          RegistrationWizardStep.accountType => DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Account type'),
              items: const [
                DropdownMenuItem(value: 'worker', child: Text('Worker')),
                DropdownMenuItem(value: 'employer', child: Text('Employer')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => role = value);
              },
            ),
          RegistrationWizardStep.identity => Column(children: [
              StroykaInputField(
                controller: registrationNameController,
                hintText: 'First name',
                prefixIcon: Icons.person_outline,
              ),
              const SizedBox(height: 12),
              StroykaInputField(
                controller: registrationLastNameController,
                hintText: 'Last name',
              ),
            ]),
          RegistrationWizardStep.professionOrCompany => StroykaInputField(
              controller: role == 'employer'
                  ? registrationCompanyController
                  : registrationTradeController,
              hintText:
                  role == 'employer' ? 'Company name' : 'Profession or trade',
              prefixIcon: role == 'employer'
                  ? Icons.business_outlined
                  : Icons.handyman_outlined,
            ),
          RegistrationWizardStep.address => UkPostalAddressForm(
              controllers: registrationAddressControllers(),
              postcodeLabel: 'Postcode',
              addressLine1Label: 'Address Line 1',
            ),
          RegistrationWizardStep.email => StroykaInputField(
              controller: emailController,
              hintText: 'Email address',
              prefixIcon: Icons.mail_outline,
            ),
          RegistrationWizardStep.phone => StroykaInputField(
              controller: phoneController,
              hintText: 'Phone number',
              prefixIcon: Icons.phone_outlined,
            ),
          RegistrationWizardStep.credentials => registrationProvider != null
              ? Text('Continue with your ${registrationProvider!.name} account.'
                  ' No password is needed for this registration.')
              : StroykaInputField(
                  controller: passwordController,
                  hintText: 'Password',
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                ),
        },
      ],
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
          label: "Enter",
          onPressed: enter,
        ),
        const SizedBox(height: 12),
        actionButton(
          label: "Registration",
          onPressed: () {
            setState(() {
              selectedAction = "register";
              isLogin = false;
              usePasswordFallback = true;
              registrationMethodSelected = false;
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
                onPressed: loading
                    ? null
                    : !isLogin &&
                            registrationMethodSelected &&
                            registrationStep > 0
                        ? () => setState(() => registrationStep--)
                        : !isLogin &&
                                registrationMethodSelected &&
                                registrationProvider == null
                            ? () => setState(
                                () => registrationMethodSelected = false)
                            : returnToAuthenticationMethods,
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
            if (!isLogin)
              registrationDraftLoading
                  ? const Center(child: CircularProgressIndicator())
                  : registrationMethodSelected
                      ? buildRegistrationWizardFields()
                      : buildRegistrationMethodChoices()
            else ...[
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
            ],
          ],
          if ((selectedAction != null || showSessionGate) &&
              (isLogin ||
                  (registrationMethodSelected &&
                      !registrationDraftLoading))) ...[
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
                        : isLogin
                            ? submit
                            : nextRegistrationStep,
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
                            : registrationStep <
                                    RegistrationWizardSteps.count - 1
                                ? 'Next'
                                : 'Create account'),
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
                child: const Text('Sign in with email and password'),
              ),
            if (isLogin && !showSessionGate) socialActions(),
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
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: !isLogin ? 500 : double.infinity,
                              ),
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

class BiometricFallbackDialog extends StatelessWidget {
  const BiometricFallbackDialog({
    super.key,
    required this.result,
    required this.onRetry,
    required this.onBack,
    required this.onPassword,
  });

  final BiometricLoginResult result;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final VoidCallback onPassword;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Biometric sign-in unavailable'),
        content: Text(result.message),
        actions: [
          if (result.canRetry)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          TextButton(onPressed: onBack, child: const Text('Back')),
          TextButton(
            onPressed: onPassword,
            child: const Text('Sign in with email and password'),
          ),
        ],
      );
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

  Future<void> signInSocial(SocialProvider provider) async {
    setState(() => loading = true);
    try {
      final result = await SocialAuthService().signIn(provider);
      if (result.cancelled) return;
      if (result.credential?.user == null) {
        throw StateError('Sign-in did not return an account.');
      }
      widget.onSessionUnlocked?.call();
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SocialAuthService.errorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

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

  Future<void> enrollBiometricAfterPasswordLogin({
    required User user,
    required String email,
    required String password,
  }) async {
    if (kIsWeb) return;
    try {
      await authPreferences.enrollBiometricLoginForPasswordSession(
        user: user,
        email: email,
        password: password,
      );
    } catch (error) {
      debugPrint("Biometric enrollment skipped after password login: $error");
    }
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
        try {
          await SocialAuthService.linkAfterVerifiedPasswordSignIn(user);
        } catch (error) {
          debugPrint('Optional social account link failed: $error');
        }
        await enrollBiometricAfterPasswordLogin(
          user: user,
          email: email,
          password: password,
        );
      }
      widget.onSessionUnlocked?.call();
      await Future<void>.delayed(Duration.zero);
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
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                children: [
                                  for (final provider in SocialProvider.values)
                                    if (SocialAuthService.available(provider))
                                      TextButton(
                                        onPressed: loading
                                            ? null
                                            : () => signInSocial(provider),
                                        child: Text(switch (provider) {
                                          SocialProvider.google => 'Google',
                                          SocialProvider.apple => 'Apple ID',
                                          SocialProvider.facebook => 'Facebook',
                                        }),
                                      ),
                                ],
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
