import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/widgets/mobile_numeric_time_picker.dart';

void main() {
  testWidgets('mobile time picker opens numeric 24-hour entry only',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () => showMobileNumericTimePicker(
              context: context,
              initialTime: const TimeOfDay(hour: 9, minute: 30),
            ),
            child: const Text('Choose time'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Choose time'));
    await tester.pumpAndSettle();
    final picker =
        tester.widget<TimePickerDialog>(find.byType(TimePickerDialog));
    expect(picker.initialEntryMode, TimePickerEntryMode.inputOnly);
    expect(
        MediaQuery.of(tester.element(find.byType(TimePickerDialog)))
            .alwaysUse24HourFormat,
        isTrue);
  });

  for (final value in ['00:00', '09:30', '23:59']) {
    testWidgets('numeric picker accepts $value', (tester) async {
      TimeOfDay? selected;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return TextButton(
              onPressed: () async {
                selected = await showMobileNumericTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 9, minute: 30),
                );
              },
              child: const Text('Choose time'),
            );
          }),
        ),
      ));
      await tester.tap(find.text('Choose time'));
      await tester.pumpAndSettle();
      final parts = value.split(':');
      await tester.enterText(find.byType(TextFormField).at(0), parts[0]);
      await tester.enterText(find.byType(TextFormField).at(1), parts[1]);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
          selected,
          TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          ));
    });
  }

  testWidgets('numeric picker rejects 24:99', (tester) async {
    TimeOfDay? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              selected = await showMobileNumericTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 9, minute: 30),
              );
            },
            child: const Text('Choose time'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Choose time'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '24');
    await tester.enterText(find.byType(TextFormField).at(1), '99');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(selected, isNull);
  });
}
