import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/widgets/account_switch_shell_gate.dart';

void main() {
  Future<void> verifySwitchDirection(
    WidgetTester tester, {
    required String sourceUid,
    required String targetUid,
  }) async {
    final quiescedTargets = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: AccountSwitchShellGate(
          authenticatedUid: sourceUid,
          switchTargetUid: null,
          onShellQuiesced: quiescedTargets.add,
          child: ColoredBox(
            key: ValueKey('home:$sourceUid'),
            color: Colors.white,
          ),
        ),
      ),
    );
    expect(find.byKey(ValueKey('home:$sourceUid')), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: AccountSwitchShellGate(
          authenticatedUid: sourceUid,
          switchTargetUid: targetUid,
          onShellQuiesced: quiescedTargets.add,
          child: ColoredBox(
            key: ValueKey('home:$sourceUid'),
            color: Colors.white,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(ValueKey('home:$sourceUid')), findsNothing);
    expect(
        find.byKey(const ValueKey('account-switch-loading')), findsOneWidget);
    expect(quiescedTargets, [targetUid]);

    await tester.pumpWidget(
      MaterialApp(
        home: AccountSwitchShellGate(
          authenticatedUid: targetUid,
          switchTargetUid: targetUid,
          onShellQuiesced: quiescedTargets.add,
          child: ColoredBox(
            key: ValueKey('home:$targetUid'),
            color: Colors.white,
          ),
        ),
      ),
    );

    expect(find.byKey(ValueKey('home:$targetUid')), findsOneWidget);
    expect(find.byKey(ValueKey('home:$sourceUid')), findsNothing);
  }

  testWidgets('Worker to Employer quiesces the old shell before rebuilding',
      (tester) async {
    await verifySwitchDirection(
      tester,
      sourceUid: 'worker-a',
      targetUid: 'employer-b',
    );
  });

  testWidgets('Employer to Worker quiesces the old shell before rebuilding',
      (tester) async {
    await verifySwitchDirection(
      tester,
      sourceUid: 'employer-b',
      targetUid: 'worker-a',
    );
  });
}
