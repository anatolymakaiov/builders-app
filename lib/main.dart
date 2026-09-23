import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'services/app_navigation.dart';
import 'services/notification_service.dart';
import 'services/multi_account_service.dart';
import 'services/post_registration_refresh_service.dart';
import 'services/auth_session_resolver.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'theme/stroyka_background.dart';
import 'widgets/legal_documents.dart';
import 'widgets/auth_session_gate.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
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
      navigatorObservers: [KeyboardDismissNavigatorObserver()],
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: StroykaBackground(
            child: child ?? const SizedBox(),
          ),
        );
      },
      home: const AuthGate(),
    );
  }
}

class KeyboardDismissNavigatorObserver extends NavigatorObserver {
  void dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    dismissKeyboard();
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    dismissKeyboard();
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    dismissKeyboard();
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    dismissKeyboard();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final postRegistrationRefresh = PostRegistrationRefreshService();
  String? _lastReadyUid;

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

    try {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .update({
        "isOnline": isOnline,
        "lastSeen": FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // New registrations may not have a Firestore profile document yet.
    }
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
    return AuthSessionGate(
      signedOut: (_) {
        _lastReadyUid = null;
        return LoginScreen(
          postRegistrationHomeBuilder: (_) => const AuthGate(),
        );
      },
      resolved: (context, user, resolution, refresh) {
        switch (resolution.destination) {
          case AuthSessionDestination.registration:
            return LoginScreen(
              key: ValueKey('registration:${user.uid}'),
              initialRegistration: true,
              resumeRegistration: true,
              postRegistrationHomeBuilder: (_) => const AuthGate(),
            );
          case AuthSessionDestination.legal:
            return LegalAcceptanceScreen(
              role: resolution.role,
              userId: user.uid,
              onAccepted: (_) async => refresh(),
            );
          case AuthSessionDestination.profile:
            return ProfileScreen(
              onProfileSaved: () async {
                await postRegistrationRefresh
                    .refreshAfterRegistration(user.uid);
                refresh();
              },
            );
          case AuthSessionDestination.home:
            if (_lastReadyUid != user.uid) {
              _lastReadyUid = user.uid;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted ||
                    FirebaseAuth.instance.currentUser?.uid != user.uid) {
                  return;
                }
                updateStatus(true);
                MultiAccountState.markShellRefreshed(user.uid);
                MultiAccountService()
                    .completePendingNewAccountLink()
                    .catchError((error) => debugPrint(
                          'Pending account link could not be completed: $error',
                        ));
              });
            }
            return HomeScreen(key: ValueKey('home:${user.uid}'));
          case AuthSessionDestination.deleted:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
        }
      },
    );
  }
}
