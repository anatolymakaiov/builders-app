import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/pages/sites/web_sites_page.dart';

void main() {
  testWidgets('site form requires a name and operational address',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: Builder(
          builder: (context) => TextButton(
                onPressed: () => showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => const WebSiteFormDialog(),
                ),
                child: const Text('Open'),
              )),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsWidgets);
    expect(find.byType(WebSiteFormDialog), findsOneWidget);
  });
}
