import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

TimeOfDay nearestWheelTime(TimeOfDay value) {
  final minutes =
      ((value.hour * 60 + value.minute + 2) ~/ 5 * 5).clamp(0, 23 * 60 + 55);
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

Future<TimeOfDay?> showMobileNumericTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  final initial = nearestWheelTime(initialTime);
  var hour = initial.hour;
  var minuteIndex = initial.minute ~/ 5;
  final hourController = FixedExtentScrollController(initialItem: hour);
  final minuteController =
      FixedExtentScrollController(initialItem: minuteIndex);

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: SizedBox(
        height: 290,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  Text('Time', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext,
                        TimeOfDay(hour: hour, minute: minuteIndex * 5)),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 96,
                    child: Semantics(
                      label: 'Hour, 24-hour format',
                      child: CupertinoPicker(
                        key: const Key('time-wheel-hour'),
                        scrollController: hourController,
                        itemExtent: 44,
                        selectionOverlay:
                            const CupertinoPickerDefaultSelectionOverlay(),
                        onSelectedItemChanged: (value) => hour = value,
                        children: [
                          for (var value = 0; value < 24; value++)
                            Center(
                                child: Text(value.toString().padLeft(2, '0'))),
                        ],
                      ),
                    ),
                  ),
                  const Text(':', style: TextStyle(fontSize: 24)),
                  SizedBox(
                    width: 96,
                    child: Semantics(
                      label: 'Minute, five-minute increments',
                      child: CupertinoPicker(
                        key: const Key('time-wheel-minute'),
                        scrollController: minuteController,
                        itemExtent: 44,
                        selectionOverlay:
                            const CupertinoPickerDefaultSelectionOverlay(),
                        onSelectedItemChanged: (value) => minuteIndex = value,
                        children: [
                          for (var value = 0; value < 60; value += 5)
                            Center(
                                child: Text(value.toString().padLeft(2, '0'))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ).whenComplete(() {
    hourController.dispose();
    minuteController.dispose();
  });
}
