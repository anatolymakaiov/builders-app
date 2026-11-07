import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/widgets/mobile_numeric_time_picker.dart';

void main() {
  test('historical values round only when the wheel is opened', () {
    expect(nearestWheelTime(const TimeOfDay(hour: 7, minute: 3)),
        const TimeOfDay(hour: 7, minute: 5));
    expect(nearestWheelTime(const TimeOfDay(hour: 23, minute: 59)),
        const TimeOfDay(hour: 23, minute: 55));
  });

  testWidgets('wheel has 24 hours and twelve five-minute values',
      (tester) async {
    TimeOfDay? selected;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: TextButton(
            onPressed: () async => selected = await showMobileNumericTimePicker(
              context: context,
              initialTime: const TimeOfDay(hour: 7, minute: 0),
            ),
            child: const Text('Open'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final hour = tester
        .widget<CupertinoPicker>(find.byKey(const Key('time-wheel-hour')));
    final minute = tester
        .widget<CupertinoPicker>(find.byKey(const Key('time-wheel-minute')));
    expect(hour.scrollController!.selectedItem, 7);
    expect(minute.scrollController!.selectedItem, 0);
    hour.scrollController!.jumpToItem(23);
    minute.scrollController!.jumpToItem(11);
    await tester.pumpAndSettle();
    expect(hour.scrollController!.selectedItem, 23);
    expect(minute.scrollController!.selectedItem, 11);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(selected, const TimeOfDay(hour: 23, minute: 55));
  });
}
