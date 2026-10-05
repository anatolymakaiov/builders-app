import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/worker_availability_service.dart';
import 'package:test_app/widgets/worker_availability_editor.dart';

void main() {
  testWidgets('Worker can select status and invitation preference together',
      (tester) async {
    WorkerAvailabilitySelection? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              selected = await showWorkerAvailabilityEditor(
                context,
                profile: const {},
              );
            },
            child: const Text('Edit availability'),
          );
        }),
      ),
    ));

    await tester.tap(find.text('Edit availability'));
    await tester.pumpAndSettle();
    expect(
      find.text(
          'Allow verified employers to send me relevant vacancy invitations through STROYKA'),
      findsOneWidget,
    );
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<WorkerAvailability>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Busy').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(selected?.status, WorkerAvailability.busy);
    expect(selected?.allowVacancyInvites, isTrue);
    expect(selected?.availableFrom, isNull);
  });

  testWidgets('Available from cannot be saved without a date', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () => showWorkerAvailabilityEditor(
              context,
              profile: const {},
            ),
            child: const Text('Edit availability'),
          );
        }),
      ),
    ));

    await tester.tap(find.text('Edit availability'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<WorkerAvailability>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Available from (date needed)').last);
    await tester.pumpAndSettle();
    expect(find.text('Choose available date'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull);
  });
}
