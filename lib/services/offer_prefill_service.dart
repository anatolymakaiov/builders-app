import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'job_taxonomy_service.dart';

class OfferPrefill {
  const OfferPrefill({
    required this.address,
    this.trade = '',
    this.jobType = 'hourly',
    this.rate = '',
    this.workPeriod = '',
    this.weeklyHours = '',
    this.schedule = '',
    this.startDate,
    this.workStart,
    this.workEnd,
    this.firstDayRequirements = '',
  });

  final Map<String, String> address;
  final String trade;
  final String jobType;
  final String rate;
  final String workPeriod;
  final String weeklyHours;
  final String schedule;
  final DateTime? startDate;
  final TimeOfDay? workStart;
  final TimeOfDay? workEnd;
  final String firstDayRequirements;
}

class OfferPrefillService {
  OfferPrefillService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<OfferPrefill> load(Map<String, dynamic> application) async {
    Map<String, dynamic> vacancy = const {};
    Map<String, dynamic> site = const {};
    final jobId = (application['jobId'] ?? '').toString().trim();
    if (jobId.isNotEmpty) {
      try {
        final job = await _db.collection('jobs').doc(jobId).get();
        vacancy = job.data() ?? const {};
      } on FirebaseException {
        // Older applications can outlive a readable vacancy.
      }
    }
    final siteId = (vacancy['siteId'] ?? '').toString().trim();
    if (siteId.isNotEmpty) {
      try {
        final doc = await _db.collection('sites').doc(siteId).get();
        final data = doc.data();
        if (data != null &&
            data['employerContextId'] ==
                (vacancy['ownerId'] ?? application['employerId'])) {
          site = data;
        }
      } on FirebaseException {
        // The vacancy's own address still provides the offer default.
      }
    }
    return fromSources(vacancy: vacancy, site: site, application: application);
  }

  static OfferPrefill fromSources({
    Map<String, dynamic> vacancy = const {},
    Map<String, dynamic> site = const {},
    Map<String, dynamic> application = const {},
  }) {
    String pick(List<Object?> values) => values
        .map((value) => value?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    final street = pick([
      vacancy['siteStreet'],
      vacancy['street'],
      vacancy['addressLine1'],
      site['addressLine1'],
      application['siteStreet'],
      application['street'],
    ]);
    final line2 = pick([
      vacancy['siteAddressLine2'],
      vacancy['addressLine2'],
      site['addressLine2'],
      application['siteAddressLine2'],
    ]);
    final line3 = pick([
      vacancy['siteAddressLine3'],
      vacancy['addressLine3'],
      site['addressLine3'],
      application['siteAddressLine3'],
    ]);
    final city = pick([
      vacancy['siteCity'],
      vacancy['city'],
      site['city'],
      application['siteCity'],
      application['city'],
    ]);
    final county = pick([
      vacancy['siteCounty'],
      vacancy['county'],
      site['region'],
      application['siteCounty'],
      application['county'],
    ]);
    final postcode = pick([
      vacancy['sitePostcode'],
      vacancy['postcode'],
      site['postcode'],
      application['sitePostcode'],
      application['postcode'],
    ]);
    final country = pick([
      vacancy['siteCountry'],
      vacancy['country'],
      site['country'],
      application['siteCountry'],
      application['country'],
    ]);
    final composed = [street, line2, line3, city, county, postcode, country]
        .where((part) => part.isNotEmpty)
        .join(', ');
    final siteName = pick([vacancy['site'], site['name']]).toLowerCase();
    final fullAddress = [
      vacancy['siteAddress'],
      vacancy['fullAddress'],
      vacancy['location'],
      application['siteAddress'],
      application['fullAddress'],
    ].map((value) => value?.toString().trim() ?? '').firstWhere(
        (value) => value.isNotEmpty && value.toLowerCase() != siteName,
        orElse: () => composed);

    final rawType = pick([vacancy['jobType'], application['jobType']]);
    final jobType = {'hourly', 'price', 'negotiable'}.contains(rawType)
        ? rawType
        : 'hourly';
    final rawRate = vacancy['rate'] ?? application['rate'];
    final rate = rawRate is num
        ? (rawRate > 0 ? rawRate.toString() : '')
        : pick([rawRate]);
    final role = pick([
      vacancy['canonicalRoleName'],
      vacancy['trade'],
      vacancy['title'],
      application['trade'],
      application['jobTitle'],
    ]);
    final requirements = <String>[
      if (pick([vacancy['candidateRequirements']]).isNotEmpty)
        'Job requirements: ${pick([vacancy['candidateRequirements']])}',
      if (pick([vacancy['requiredDocuments']]).isNotEmpty)
        'Required documents/certificates/tools: ${pick([
              vacancy['requiredDocuments']
            ])}',
    ];
    return OfferPrefill(
      address: {
        'siteStreet': street.isNotEmpty ? street : fullAddress,
        'siteAddressLine2': line2,
        'siteAddressLine3': line3,
        'siteCity': city,
        'siteCounty': county,
        'sitePostcode': postcode,
        'siteCountry': country,
        'siteAddress': fullAddress,
      },
      trade: JobTaxonomyService.canonicalFor(role),
      jobType: jobType,
      rate: jobType == 'negotiable' ? '' : rate,
      workPeriod: pick([vacancy['duration'], application['duration']]),
      weeklyHours: pick([vacancy['weeklyHours'], application['weeklyHours']]),
      schedule: pick([vacancy['schedule'], application['schedule']]),
      startDate: _date(vacancy['startDateMillis']) ??
          _date(vacancy['startDate']) ??
          _date(site['startDate']),
      workStart: _time(vacancy['workStartTime']),
      workEnd: _time(vacancy['workEndTime']),
      firstDayRequirements: requirements.join('\n'),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  static TimeOfDay? _time(Object? value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$')
        .firstMatch(value?.toString().trim() ?? '');
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }
}
