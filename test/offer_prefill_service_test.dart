import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/offer_prefill_service.dart';

void main() {
  test('vacancy and site fields become an editable offer draft snapshot', () {
    final vacancy = <String, dynamic>{
      'canonicalRoleName': 'Dryliner',
      'jobType': 'hourly',
      'rate': 25,
      'duration': '2 weeks',
      'weeklyHours': '40',
      'workStartTime': '07:00',
      'workEndTime': '17:00',
      'startDateMillis': DateTime(2026, 11, 12).millisecondsSinceEpoch,
      'siteStreet': '12 High Street',
      'siteCity': 'Manchester',
      'sitePostcode': 'M1 1AA',
      'candidateRequirements': 'Bring PPE',
      'requiredDocuments': 'CSCS card',
    };
    final offer = OfferPrefillService.fromSources(vacancy: vacancy);
    expect(offer.trade, 'Dryliner');
    expect(offer.rate, '25');
    expect(offer.workPeriod, '2 weeks');
    expect(offer.weeklyHours, '40');
    expect(offer.workStart, const TimeOfDay(hour: 7, minute: 0));
    expect(offer.workEnd, const TimeOfDay(hour: 17, minute: 0));
    expect(offer.startDate, DateTime(2026, 11, 12));
    expect(offer.address['siteCity'], 'Manchester');
    expect(offer.address['siteAddress'], contains('M1 1AA'));
    expect(offer.firstDayRequirements, contains('Bring PPE'));
    expect(offer.firstDayRequirements, contains('CSCS card'));
    vacancy['rate'] = 50;
    expect(offer.rate, '25');
  });

  test('legacy and incomplete vacancy fields remain safe', () {
    final offer = OfferPrefillService.fromSources(
      vacancy: {'title': 'Electrician', 'siteId': 'site-1'},
      site: {
        'addressLine1': 'Site Lane',
        'city': 'Leeds',
        'startDate': DateTime(2026, 12, 1),
      },
    );
    expect(offer.trade, isNotEmpty);
    expect(offer.address['siteStreet'], 'Site Lane');
    expect(offer.startDate, DateTime(2026, 12, 1));
    expect(offer.workStart, isNull);
    expect(offer.workEnd, isNull);
    expect(offer.firstDayRequirements, isEmpty);
  });
}
