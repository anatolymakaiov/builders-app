import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? webChatLocalTime(dynamic createdAt) {
  if (createdAt is Timestamp) return createdAt.toDate().toLocal();
  if (createdAt is DateTime) return createdAt.toLocal();
  return null;
}

List<bool> webChatDateHeadings(List<DateTime?> newestFirst) {
  final headings = List<bool>.filled(newestFirst.length, false);
  DateTime? previous;
  for (var index = newestFirst.length - 1; index >= 0; index--) {
    final current = newestFirst[index];
    if (current == null) continue;
    headings[index] = previous == null ||
        current.year != previous.year ||
        current.month != previous.month ||
        current.day != previous.day;
    previous = current;
  }
  return headings;
}

String webChatTimeLabel(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String webChatDateLabel(DateTime date, {DateTime? now}) {
  final localNow = now ?? DateTime.now();
  final days = DateTime(localNow.year, localNow.month, localNow.day)
      .difference(DateTime(date.year, date.month, date.day))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return '${date.day}.${date.month}.${date.year}';
}
