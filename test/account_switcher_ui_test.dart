import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/widgets/account_switcher.dart';

void main() {
  Future<void> pumpControl(
    WidgetTester tester, {
    required bool employer,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: AccountIdentityButton(
              name: employer ? 'Company' : 'Worker',
              isEmployer: employer,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('mobile Worker header shows account identity control',
      (tester) async {
    await pumpControl(tester, employer: false);

    expect(
      find.byKey(const ValueKey('account-identity-switcher')),
      findsOneWidget,
    );
    expect(find.text('Worker'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsNothing);
  });

  testWidgets('mobile Employer header shows account identity control',
      (tester) async {
    await pumpControl(tester, employer: true);

    expect(
      find.byKey(const ValueKey('account-identity-switcher')),
      findsOneWidget,
    );
    expect(find.text('Company'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    expect(find.byIcon(Icons.business_outlined), findsNothing);
  });
}
