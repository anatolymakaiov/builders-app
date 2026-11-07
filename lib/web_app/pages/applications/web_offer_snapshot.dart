import 'package:cloud_firestore/cloud_firestore.dart';

String _offerDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

List<MapEntry<String, String>> webOfferSnapshotRows(
    Map<String, dynamic> offer) {
  String value(List<String> keys) {
    for (final key in keys) {
      final raw = offer[key];
      if (raw == null) continue;
      final text = switch (raw) {
        Timestamp timestamp => _offerDate(timestamp.toDate()),
        DateTime date => _offerDate(date),
        List items => items
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .join(', '),
        _ => raw.toString().trim(),
      };
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  final address = value(['siteAddress', 'fullAddress']).isNotEmpty
      ? value(['siteAddress', 'fullAddress'])
      : [
          value(['siteStreet', 'siteAddressLine1']),
          value(['siteAddressLine2']),
          value(['siteAddressLine3']),
          value(['siteCity']),
          value(['siteCounty']),
          value(['sitePostcode']),
          value(['siteCountry']),
        ].where((part) => part.isNotEmpty).join(', ');

  return [
    MapEntry('Trade / role', value(['trade'])),
    MapEntry('Work format', value(['workFormat', 'jobType'])),
    MapEntry('Rate / price', value(['rate'])),
    MapEntry('Work period', value(['workPeriod', 'duration'])),
    MapEntry('End date', value(['endDate', 'endDateTime'])),
    MapEntry('Hours per week', value(['weeklyHours'])),
    MapEntry('Schedule', value(['schedule'])),
    MapEntry('Start date',
        value(['startDateTime', 'startDate', 'startDateTimestamp'])),
    MapEntry('Work starts', value(['workStartTime'])),
    MapEntry('Work ends', value(['workEndTime'])),
    MapEntry('Site address', address),
    MapEntry('Tools / equipment',
        value(['tools', 'toolsRequired', 'requiredTools'])),
    MapEntry('PPE', value(['ppe', 'ppeRequired', 'requiredPpe'])),
    MapEntry('Certificates', value(['certificates', 'requiredCertificates'])),
    MapEntry('Qualifications / licences',
        value(['qualifications', 'requiredQualifications', 'licences'])),
    MapEntry('Induction', value(['induction', 'inductionInformation'])),
    MapEntry('Induction time', value(['inductionTime'])),
    MapEntry('Required on first day', value(['firstDayRequirements'])),
    MapEntry('Description', value(['description', 'message'])),
    MapEntry('Valid until', value(['validUntil', 'validUntilTimestamp'])),
  ].where((row) => row.value.isNotEmpty).toList(growable: false);
}
