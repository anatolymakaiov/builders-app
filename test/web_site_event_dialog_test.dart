import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/pages/calendar/web_site_event_dialog.dart';

void main() {
  testWidgets('manual event form validates title and returns canonical draft',
      (tester) async {
    SiteEventDraft? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          result = await showDialog<SiteEventDraft>(context: context,
            builder: (_) => WebSiteEventDialog(
              sites: const [], initialDate: DateTime(2026, 10, 20)));
        }, child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Add event'), findsOneWidget);
    expect(find.text('Company-wide event'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Safety meeting');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.title, 'Safety meeting');
    expect(result!.type, 'meeting');
    expect(result!.siteId, '');
  });
}
