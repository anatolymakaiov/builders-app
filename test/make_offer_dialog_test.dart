import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/address_lookup_service.dart';
import 'package:test_app/services/offer_prefill_service.dart';
import 'package:test_app/widgets/make_offer_dialog.dart';

void main() {
  testWidgets('offer shows and submits editable vacancy terms', (tester) async {
    Map<String, dynamic>? sent;
    final prefill = OfferPrefill(
      trade: 'Dryliner',
      rate: '25',
      workPeriod: '2 weeks',
      weeklyHours: '40',
      startDate: DateTime(2030, 11, 12),
      workStart: const TimeOfDay(hour: 7, minute: 0),
      workEnd: const TimeOfDay(hour: 17, minute: 0),
      firstDayRequirements: 'Bring CSCS card',
      address: const {
        'siteStreet': '12 High Street',
        'siteCity': 'Manchester',
        'sitePostcode': 'M1 1AA',
        'siteCountry': 'United Kingdom',
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              sent = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => MakeOfferDialog(
                  prefill: prefill,
                  addressLookupService: _Lookup(),
                ),
              );
            },
            child: const Text('Open offer'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Open offer'));
    await tester.pumpAndSettle();
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.any((field) => field.controller?.text == 'Dryliner'), isTrue);
    expect(fields.any((field) => field.controller?.text == '25'), isTrue);
    expect(find.text('07:00'), findsWidgets);
    expect(find.text('17:00'), findsWidgets);
    final rateField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller?.text == '25',
    );
    await tester.ensureVisible(rateField);
    await tester.enterText(rateField, '30');
    await tester.tap(find.text('Send offer'));
    await tester.pumpAndSettle();
    expect(sent, isNotNull);
    expect(sent!['trade'], 'Dryliner');
    expect(sent!['workStartTime'], '07:00');
    expect(sent!['workEndTime'], '17:00');
    expect(sent!['rate'], '30');
    expect(sent!['siteAddress'], contains('Manchester'));
    expect(sent!['firstDayRequirements'], 'Bring CSCS card');
  });

  testWidgets('same-day work end before start blocks sending', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () => showDialog<Map<String, dynamic>>(
            context: context,
            builder: (_) => MakeOfferDialog(
              prefill: OfferPrefill(
                address: const {
                  'siteStreet': '12 High Street',
                  'siteCity': 'Manchester',
                  'siteCountry': 'United Kingdom',
                },
                startDate: DateTime(2030, 11, 12),
                workStart: const TimeOfDay(hour: 17, minute: 0),
                workEnd: const TimeOfDay(hour: 7, minute: 0),
              ),
              addressLookupService: _Lookup(),
            ),
          ),
          child: const Text('Open offer'),
        );
      })),
    ));
    await tester.tap(find.text('Open offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send offer'));
    await tester.pumpAndSettle();
    expect(find.text('Work end must be after work start.'), findsOneWidget);
    expect(find.text('Make offer'), findsOneWidget);
  });
}

class _Lookup extends AddressLookupService {
  @override
  String normalizePostcode(String postcode) => postcode;

  @override
  bool isValidPostcode(String postcode) => true;

  @override
  Future<List<PostalAddress>> lookupAddresses(String postcode) async => [];
}
