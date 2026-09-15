import '../../../models/job.dart';

String webJobWorkFormat(Job job) {
  switch (job.jobType.trim().toLowerCase()) {
    case 'price':
      return 'Price';
    case 'negotiable':
      return 'Negotiable';
    default:
      return 'Day Work';
  }
}

String? webJobRate(Job job) {
  if (job.rate <= 0) return null;
  final type = job.jobType.trim().toLowerCase();
  final amount = job.rate == job.rate.roundToDouble()
      ? job.rate.toInt().toString()
      : job.rate
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(
            RegExp(r'\.$'),
            '',
          );
  if (type == 'price') return '£$amount';
  if (type == 'negotiable') return null;
  return '£$amount/hour';
}

String? webJobPostedLabel(Job job, {DateTime? now}) {
  final date = job.postedAt ?? job.createdAt;
  if (date == null) return null;
  final today = now ?? DateTime.now();
  final postedDay = DateTime(date.year, date.month, date.day);
  final currentDay = DateTime(today.year, today.month, today.day);
  final days = currentDay.difference(postedDay).inDays;
  if (days <= 0) return 'Posted today';
  if (days == 1) return 'Posted yesterday';
  if (days < 14) return 'Posted $days days ago';
  return 'Posted ${date.day.toString().padLeft(2, '0')} '
      '${_month(date.month)} ${date.year}';
}

String _month(int month) => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][month - 1];
