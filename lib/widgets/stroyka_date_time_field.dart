import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StroykaDateTimeValue {
  final DateTime? date;
  final TimeOfDay? time;

  const StroykaDateTimeValue({
    this.date,
    this.time,
  });

  DateTime? get dateTime {
    final selectedDate = date;
    if (selectedDate == null) return null;
    final selectedTime = time;
    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime?.hour ?? 0,
      selectedTime?.minute ?? 0,
    );
  }

  String get displayText {
    final selectedDate = date;
    if (selectedDate == null) return "";
    final dateText = StroykaDateTimeFormat.formatDate(selectedDate);
    final selectedTime = time;
    if (selectedTime == null) return dateText;
    return "$dateText ${StroykaDateTimeFormat.formatTime(selectedTime)}";
  }

  StroykaDateTimeValue copyWith({
    DateTime? date,
    TimeOfDay? time,
  }) {
    return StroykaDateTimeValue(
      date: date ?? this.date,
      time: time ?? this.time,
    );
  }
}

class StroykaDateTimeFormat {
  static String formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, "0")}/"
        "${date.month.toString().padLeft(2, "0")}/"
        "${date.year}";
  }

  static String formatTime(TimeOfDay time) {
    return "${time.hour.toString().padLeft(2, "0")}:"
        "${time.minute.toString().padLeft(2, "0")}";
  }
}

class StroykaDateTimeField extends StatelessWidget {
  final String label;
  final StroykaDateTimeValue value;
  final ValueChanged<StroykaDateTimeValue> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool requireTime;

  const StroykaDateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.requireTime = true,
  });

  Future<void> pickDate(BuildContext context) async {
    final now = DateTime.now();
    final minimum = firstDate ?? DateTime(now.year - 1);
    final maximum = lastDate ?? DateTime(now.year + 5);
    final selected = await showDatePicker(
      context: context,
      initialDate: value.date ?? now,
      firstDate: DateTime(minimum.year, minimum.month, minimum.day),
      lastDate: DateTime(maximum.year, maximum.month, maximum.day),
    );
    if (selected == null) return;
    onChanged(value.copyWith(date: selected));
  }

  Future<void> pickTime(BuildContext context) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: value.time ?? TimeOfDay.now(),
    );
    if (selected == null) return;
    onChanged(value.copyWith(time: selected));
  }

  @override
  Widget build(BuildContext context) {
    final dateText = value.date == null
        ? "Date"
        : StroykaDateTimeFormat.formatDate(value.date!);
    final timeText = value.time == null
        ? "Time"
        : StroykaDateTimeFormat.formatTime(value.time!);

    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const StroykaInputBorder(),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => pickDate(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        dateText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: value.date == null
                              ? AppColors.muted
                              : AppColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (requireTime) ...[
            Container(
              width: 1,
              height: 28,
              color: AppColors.muted.withValues(alpha: 0.22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => pickTime(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_outlined, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          timeText,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: value.time == null
                                ? AppColors.muted
                                : AppColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
