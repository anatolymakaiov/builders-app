import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/pages/applications/web_offer_snapshot.dart';

void main() {
  test('saved offer exposes operational terms without vacancy fallback', () {
    final rows = Map.fromEntries(webOfferSnapshotRows({
      'trade': 'Dryliner',
      'rate': '£25/hour',
      'startDateTime': '14/10/2026 07:00',
      'workStartTime': '07:00',
      'workEndTime': '17:00',
      'siteAddress': '1 Site Street, Manchester',
      'tools': 'Hand tools',
      'ppe': 'Hard hat',
      'certificates': ['CSCS'],
      'qualifications': 'NVQ Level 2',
      'induction': 'Report to the site office',
      'inductionTime': '06:45',
      'firstDayRequirements': 'Bring CSCS card',
      'description': 'Ask for the foreman',
    }));
    expect(rows['Start date'], '14/10/2026 07:00');
    expect(rows['Work starts'], '07:00');
    expect(rows['Work ends'], '17:00');
    expect(rows['Rate / price'], '£25/hour');
    expect(rows['Site address'], '1 Site Street, Manchester');
    expect(rows['Tools / equipment'], 'Hand tools');
    expect(rows['PPE'], 'Hard hat');
    expect(rows['Certificates'], 'CSCS');
    expect(rows['Qualifications / licences'], 'NVQ Level 2');
    expect(rows['Induction'], 'Report to the site office');
    expect(rows['Induction time'], '06:45');
    expect(rows['Required on first day'], 'Bring CSCS card');
    expect(rows['Description'], 'Ask for the foreman');
  });

  test('legacy saved offer omits absent values and assembles address', () {
    final rows = Map.fromEntries(webOfferSnapshotRows({
      'rate': '£180/day',
      'siteStreet': 'Main Road',
      'siteCity': 'Leeds',
      'sitePostcode': 'LS1 1AA',
    }));
    expect(rows['Site address'], 'Main Road, Leeds, LS1 1AA');
    expect(rows['Work starts'], isNull);
    expect(rows['PPE'], isNull);
    expect(rows.length, 2);
  });
}
