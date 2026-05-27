import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'services/app_navigation.dart';
import 'services/auth_preferences_service.dart';
import 'services/notification_service.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'theme/stroyka_background.dart';
import 'widgets/legal_documents.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await NotificationService().init();

  runApp(const JobApp());
}

class JobApp extends StatelessWidget {
  const JobApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STROYKA',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) {
        return StroykaBackground(
          child: child ?? const SizedBox(),
        );
      },
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  bool sessionUnlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 🔥 ONLINE / OFFLINE
  Future<void> updateStatus(bool isOnline) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection("users").doc(user.uid).update({
      "isOnline": isOnline,
      "lastSeen": FieldValue.serverTimestamp(),
    });
  }

  /// 🔥 lifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      updateStatus(true); // 🟢 online
    } else {
      updateStatus(false); // 🔴 offline
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData) {
          sessionUnlocked = false;
          return const LoginScreen();
        }

        final user = snapshot.data!;

        updateStatus(true);

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection("users")
              .doc(user.uid)
              .get(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                FirebaseAuth.instance.signOut();
              });
              return const LoginScreen();
            }

            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
            if (userData?["accountDeleted"] == true) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                FirebaseAuth.instance.signOut();
              });
              return const LoginScreen();
            }

            final authMethod =
                AuthPreferencesService().methodFromUserData(userData ?? {});
            final requiresSessionGate =
                authMethod == AuthPreferenceMethod.biometric ||
                    authMethod == AuthPreferenceMethod.simpleEnter;
            if (requiresSessionGate && !sessionUnlocked) {
              return LoginScreen(
                sessionMode: authMethod,
                onSessionUnlocked: () {
                  if (!mounted) return;
                  setState(() => sessionUnlocked = true);
                },
              );
            }

            final role = userData?["role"]?.toString() == "admin" ||
                    userData?["role"]?.toString() == "employer"
                ? userData!["role"].toString()
                : "worker";

            if (role != "admin" &&
                !LegalDocuments.hasAcceptedCurrentVersion(userData, role)) {
              return LegalAcceptanceScreen(
                role: role,
                userId: user.uid,
                onAccepted: (_) async {
                  if (!mounted) return;
                  setState(() {});
                },
              );
            }

            final hasCompletedProfile = userData?["profileComplete"] == true ||
                userData?["onboardingComplete"] == true ||
                userData?["profileCreated"] == true ||
                (role == "worker" &&
                    (userData?["name"]?.toString().trim() ?? "").isNotEmpty) ||
                (role == "employer" &&
                    (userData?["companyName"]?.toString().trim() ?? "")
                        .isNotEmpty);

            if (role != "admin" && !hasCompletedProfile) {
              return ProfileScreen(
                onProfileSaved: () {
                  if (!mounted) return;
                  setState(() {});
                },
              );
            }

            return const HomeScreen();
          },
        );
      },
    );
  }
}
