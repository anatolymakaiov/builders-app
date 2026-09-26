import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/auth_session_resolver.dart';
import 'package:test_app/services/registration_lifecycle.dart';
import 'package:test_app/web_app/portrait/portrait_web_auth.dart';

void main() {
  test('Worker requires email but not phone; employer requires both', () {
    expect(
      RegistrationLifecycle.canComplete(
        role: 'worker',
        emailVerified: true,
        phoneVerified: false,
      ),
      isTrue,
    );
    expect(
      RegistrationLifecycle.canComplete(
        role: 'worker',
        emailVerified: false,
        phoneVerified: true,
      ),
      isFalse,
    );
    expect(
      RegistrationLifecycle.canComplete(
        role: 'employer',
        emailVerified: true,
        phoneVerified: false,
      ),
      isFalse,
    );
    expect(
      RegistrationLifecycle.canComplete(
        role: 'employer',
        emailVerified: true,
        phoneVerified: true,
      ),
      isTrue,
    );
  });

  test('Incomplete registration stays in onboarding', () {
    final resolution = AuthSessionResolver.classify(
      draft: {'role': 'employer', 'registrationFormComplete': false},
    );
    expect(resolution.destination, AuthSessionDestination.registration);
  });

  testWidgets('Portrait landing opens email login and Back returns',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: PortraitWebLanding(homeBuilder: (_) => const SizedBox()),
    ));

    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('Registration'), findsOneWidget);
    expect(find.textContaining('Google'), findsNothing);
    expect(find.textContaining('Apple'), findsNothing);
    expect(find.textContaining('Facebook'), findsNothing);

    await tester.tap(find.text('Enter'));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('Password'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Portrait password failure stays on login and can recover',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: PortraitWebPasswordLogin(
        homeBuilder: (_) => const SizedBox(),
        authenticate: (_, __) async => throw FirebaseAuthException(
          code: 'wrong-password',
          message: 'Invalid credentials',
        ),
      ),
    ));

    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Invalid credentials'), findsOneWidget);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Password recovery'), findsOneWidget);
    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Invalid credentials'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Successful Portrait login returns to root auth gate',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => PortraitWebPasswordLogin(
                      homeBuilder: (_) => const SizedBox(),
                      authenticate: (_, __) async {},
                    ),
                  )),
                  child: const Text('Open login'),
                ),
              )),
    ));
    await tester.tap(find.text('Open login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Open login'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });
}
