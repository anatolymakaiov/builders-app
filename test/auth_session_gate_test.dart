import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/auth_session_resolver.dart';
import 'package:test_app/services/multi_account_service.dart';
import 'package:test_app/widgets/auth_session_gate.dart';

class _TestUser extends Fake implements User {
  _TestUser(this.uid);

  @override
  final String uid;
}

AuthSessionResolution _ready([String role = 'worker']) => AuthSessionResolution(
      destination: AuthSessionDestination.home,
      role: role,
      profile: {'role': role, 'profileComplete': true},
    );

void main() {
  tearDown(MultiAccountState.resetForTesting);

  test('completed worker and employer profiles route to Home', () {
    for (final role in ['worker', 'employer']) {
      final name = role == 'worker' ? 'Worker' : 'Company';
      final data = {'role': role, 'name': name, 'companyName': name};
      final route = AuthSessionResolver.classify(
        profile: data,
        hasAcceptedLegal: (_, __) => true,
      );
      expect(route.destination, AuthSessionDestination.home);
      expect(route.role, role);
    }
  });

  test('incomplete registration never routes to Home', () {
    final route = AuthSessionResolver.classify(
      draft: {'role': 'worker', 'registrationFormComplete': false},
      hasAcceptedLegal: (_, __) => false,
    );
    expect(route.destination, AuthSessionDestination.registration);
    expect(route.hasDraft, isTrue);

    final partialProfile = AuthSessionResolver.classify(
      profile: {'role': 'worker'},
      hasAcceptedLegal: (_, __) => true,
    );
    expect(partialProfile.destination, AuthSessionDestination.profile);

    final namedButIncomplete = AuthSessionResolver.classify(
      profile: {'role': 'worker', 'name': 'Alex', 'profileComplete': false},
      hasAcceptedLegal: (_, __) => true,
    );
    expect(namedButIncomplete.destination, AuthSessionDestination.profile);
  });

  test('inactive accounts do not enter Home, but moderated owners keep access',
      () {
    final inactive = AuthSessionResolver.classify(
      profile: {
        'role': 'worker',
        'profileComplete': true,
        'active': false,
      },
      hasAcceptedLegal: (_, __) => true,
    );
    expect(inactive.destination, AuthSessionDestination.profile);

    final held = AuthSessionResolver.classify(
      profile: {
        'role': 'worker',
        'profileComplete': true,
        'active': false,
        'profileHold': true,
      },
      hasAcceptedLegal: (_, __) => true,
    );
    expect(held.destination, AuthSessionDestination.home);
  });

  test('missing legal acceptance and deleted profiles stay out of Home', () {
    expect(
      AuthSessionResolver.classify(
        profile: {'role': 'employer', 'profileComplete': true},
        hasAcceptedLegal: (_, __) => false,
      ).destination,
      AuthSessionDestination.legal,
    );
    expect(
      AuthSessionResolver.classify(
        profile: {'role': 'worker', 'accountDeleted': true},
      ).destination,
      AuthSessionDestination.deleted,
    );
  });

  Future<void> verifyPlatformRoute(WidgetTester tester, String platform) async {
    final changes = StreamController<User?>();
    addTearDown(changes.close);
    await tester.pumpWidget(MaterialApp(
      home: AuthSessionGate(
        authChanges: changes.stream,
        resolve: (_) async => _ready(),
        signedOut: (_) => Text('$platform landing'),
        resolved: (_, user, resolution, __) =>
            Text('$platform home ${user.uid}'),
      ),
    ));
    expect(find.text('$platform landing'), findsNothing);

    changes.add(_TestUser('worker-a'));
    await tester.pumpAndSettle();
    expect(find.text('$platform home worker-a'), findsOneWidget);
    expect(find.text('$platform landing'), findsNothing);

    changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text('$platform landing'), findsOneWidget);
    expect(find.text('$platform home worker-a'), findsNothing);
  }

  testWidgets('Mobile completed session opens Home; sign-out opens Landing',
      (tester) => verifyPlatformRoute(tester, 'mobile'));

  testWidgets('Web completed session opens workspace; sign-out opens login',
      (tester) => verifyPlatformRoute(tester, 'web'));

  testWidgets('incomplete authenticated profile opens registration, not Home',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AuthSessionGate(
        authChanges: Stream<User?>.value(_TestUser('incomplete')),
        resolve: (_) async => const AuthSessionResolution(
          destination: AuthSessionDestination.registration,
          role: 'worker',
          profile: {},
        ),
        signedOut: (_) => const Text('Landing'),
        resolved: (_, __, route, ___) => Text(route.destination.name),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('registration'), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('cold start without Firebase user shows Landing', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AuthSessionGate(
        authChanges: Stream<User?>.value(null),
        resolve: (_) async => _ready(),
        signedOut: (_) => const Text('Landing'),
        resolved: (_, __, ___, ____) => const Text('Home'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Landing'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('invalidated session returns to authentication', (tester) async {
    final changes = StreamController<User?>();
    addTearDown(changes.close);
    await tester.pumpWidget(MaterialApp(
      home: AuthSessionGate(
        authChanges: changes.stream,
        resolve: (_) async => _ready(),
        signedOut: (_) => const Text('Login'),
        resolved: (_, __, ___, ____) => const Text('Home'),
      ),
    ));
    changes.add(_TestUser('worker-a'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('switch tears down old shell before showing target shell',
      (tester) async {
    final changes = StreamController<User?>();
    addTearDown(changes.close);
    await tester.pumpWidget(MaterialApp(
      home: AuthSessionGate(
        authChanges: changes.stream,
        resolve: (_) async => _ready(),
        signedOut: (_) => const Text('Landing'),
        resolved: (_, user, __, ___) => Text('home ${user.uid}'),
      ),
    ));
    changes.add(_TestUser('worker-a'));
    await tester.pumpAndSettle();
    MultiAccountState.beginSwitch('employer-b');
    await tester.pump();
    expect(find.text('home worker-a'), findsNothing);
    expect(find.text('Landing'), findsNothing);
    expect(
        find.byKey(const ValueKey('account-switch-loading')), findsOneWidget);

    changes.add(null);
    await tester.pump();
    expect(find.text('Landing'), findsNothing);
    expect(
        find.byKey(const ValueKey('account-switch-loading')), findsOneWidget);

    changes.add(_TestUser('employer-b'));
    await tester.pumpAndSettle();
    expect(find.text('home employer-b'), findsOneWidget);
    expect(find.text('home worker-a'), findsNothing);
    MultiAccountState.markShellRefreshed('employer-b');
  });

  testWidgets('profile read failure offers retry instead of false sign-out',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: AuthSessionGate(
        authChanges: Stream<User?>.value(_TestUser('worker-a')),
        resolve: (_) async {
          attempts++;
          if (attempts == 1) throw StateError('offline');
          return _ready();
        },
        signedOut: (_) => const Text('Landing'),
        resolved: (_, __, ___, ____) => const Text('Home'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Landing'), findsNothing);
    await tester.tap(find.text('Could not load your account. Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });
}
