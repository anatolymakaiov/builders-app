DateTime jobDateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool isHistoricalJobStartDate(DateTime value, {DateTime? today}) {
  return jobDateOnly(value).isBefore(jobDateOnly(today ?? DateTime.now()));
}

int jobStartDateStorageMillis(DateTime value) {
  final date = jobDateOnly(value);
  return DateTime.utc(date.year, date.month, date.day, 12)
      .millisecondsSinceEpoch;
}

String formatJobStartDate(DateTime? value) {
  if (value == null) return 'Not specified';
  const months = <String>[
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
  ];
  final date = jobDateOnly(value);
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
