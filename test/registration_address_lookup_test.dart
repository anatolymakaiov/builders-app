import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test_app/services/address_lookup_service.dart';
import 'package:test_app/services/registration_wizard_steps.dart';
import 'package:test_app/widgets/uk_postal_address_form.dart';

class _FakeLookup extends AddressLookupService {
  _FakeLookup(this.load);

  final Future<List<PostalAddress>> Function(String) load;
  final requests = <String>[];

  @override
  String normalizePostcode(String postcode) => normalizeUkPostcode(postcode);

  @override
  bool isValidPostcode(String postcode) => isValidUkPostcode(postcode);

  @override
  Future<List<PostalAddress>> lookupAddresses(String postcode) {
    requests.add(postcode);
    return load(postcode);
  }
}

class _AddressFields {
  final postcode = TextEditingController();
  final line1 = TextEditingController();
  final line2 = TextEditingController();
  final line3 = TextEditingController();
  final town = TextEditingController();
  final county = TextEditingController();
  final country = TextEditingController(text: 'United Kingdom');

  UkPostalAddressControllers get controllers => UkPostalAddressControllers(
        postcode: postcode,
        addressLine1: line1,
        addressLine2: line2,
        addressLine3: line3,
        townCity: town,
        county: county,
        country: country,
      );

  void dispose() {
    for (final controller in [
      postcode,
      line1,
      line2,
      line3,
      town,
      county,
      country,
    ]) {
      controller.dispose();
    }
  }
}

void main() {
  test('free postcode provider normalizes and maps only known geography',
      () async {
    final service = PostcodesIoAddressLookupService(
      client: MockClient((request) async {
        expect(request.url.toString(),
            'https://api.postcodes.io/postcodes/SW1A1AA');
        return http.Response('''{
          "status": 200,
          "result": {
            "postcode": "SW1A 1AA",
            "region": "London",
            "admin_district": "Westminster",
            "admin_county": null,
            "country": "England",
            "latitude": 51.501,
            "longitude": -0.141
          }
        }''', 200);
      }),
    );

    final addresses = await service.lookupAddresses(' sw1a1aa ');
    expect(addresses, hasLength(1));
    expect(addresses.single.postcode, 'SW1A 1AA');
    expect(addresses.single.townCity, 'London');
    expect(addresses.single.country, 'United Kingdom');
    expect(addresses.single.addressLine1, isEmpty);
  });

  test('invalid and unknown postcodes do not crash', () async {
    var requests = 0;
    final service = PostcodesIoAddressLookupService(
      client: MockClient((_) async {
        requests++;
        return http.Response('{"status":404,"result":null}', 404);
      }),
    );
    expect(await service.lookupAddresses('invalid'), isEmpty);
    expect(requests, 0);
    expect(await service.lookupAddresses('SW1A 1AA'), isEmpty);
    expect(requests, 1);
  });

  test('postcode API failure has a distinct manual-entry error', () async {
    final service = PostcodesIoAddressLookupService(
      client: MockClient((_) async => http.Response('Unavailable', 503)),
    );
    expect(
      () => service.lookupAddresses('SW1A 1AA'),
      throwsA(isA<AddressLookupException>()),
    );
  });

  test('registration uses free lookup before auth and property lookup after',
      () async {
    var signedIn = false;
    final property = _FakeLookup((_) async => [
          const PostalAddress(addressLine1: '10 Downing Street'),
        ]);
    final free = _FakeLookup((_) async => [
          const PostalAddress(postcode: 'SW1A 1AA', townCity: 'London'),
        ]);
    final service = RegistrationAddressLookupService(
      propertyLookup: property,
      postcodeLookup: free,
      isSignedIn: () => signedIn,
    );

    expect((await service.lookupAddresses('SW1A1AA')).single.addressLine1,
        isEmpty);
    expect(property.requests, isEmpty);
    signedIn = true;
    expect((await service.lookupAddresses('SW1A1AA')).single.addressLine1,
        '10 Downing Street');
    expect(property.requests, ['SW1A 1AA']);
  });

  test('property service failure falls back to free postcode lookup', () async {
    final service = RegistrationAddressLookupService(
      propertyLookup: _FakeLookup((_) async => throw StateError('unavailable')),
      postcodeLookup: _FakeLookup((_) async => [
            const PostalAddress(postcode: 'SW1A 1AA', townCity: 'London'),
          ]),
      isSignedIn: () => true,
    );
    expect(
        (await service.lookupAddresses('SW1A1AA')).single.townCity, 'London');
  });

  testWidgets('postcode suggestion populates address without inventing street',
      (tester) async {
    final fields = _AddressFields();
    addTearDown(fields.dispose);
    fields.line1.text = 'Existing street';
    final lookup = _FakeLookup((_) async => [
          const PostalAddress(postcode: 'SW1A 1AA', townCity: 'London'),
        ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: UkPostalAddressForm(
            controllers: fields.controllers,
            lookupService: lookup,
            autoLookup: true,
            showManualEntryShortcut: true,
          ),
        ),
      ),
    ));

    await tester.enterText(
        find.widgetWithText(TextField, 'Postcode'), 'sw1a1aa');
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();
    expect(lookup.requests, ['SW1A 1AA']);
    await tester.tap(find.text('London, SW1A 1AA').first);
    await tester.pumpAndSettle();

    expect(fields.postcode.text, 'SW1A 1AA');
    expect(fields.line1.text, 'Existing street');
    expect(fields.town.text, 'London');
    expect(find.textContaining('Enter Address Line 1'), findsOneWidget);
  });

  testWidgets('property suggestion fills all supplied address fields',
      (tester) async {
    final fields = _AddressFields();
    addTearDown(fields.dispose);
    final lookup = _FakeLookup((_) async => [
          const PostalAddress(
            postcode: 'SW1A 1AA',
            addressLine1: '10 Downing Street',
            addressLine2: 'Westminster',
            townCity: 'London',
            county: 'Greater London',
            country: 'United Kingdom',
          ),
        ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: UkPostalAddressForm(
            controllers: fields.controllers,
            lookupService: lookup,
          ),
        ),
      ),
    ));

    await tester.enterText(
        find.widgetWithText(TextField, 'Postcode'), 'SW1A 1AA');
    await tester.tap(find.byTooltip('Search postcode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 Downing Street').first);
    await tester.pumpAndSettle();

    expect(fields.line1.text, '10 Downing Street');
    expect(fields.line2.text, 'Westminster');
    expect(fields.town.text, 'London');
    expect(fields.county.text, 'Greater London');
    expect(fields.country.text, 'United Kingdom');
  });

  testWidgets('lookup failure leaves manual registration valid',
      (tester) async {
    final fields = _AddressFields();
    addTearDown(fields.dispose);
    final lookup = _FakeLookup((_) async => throw const AddressLookupException(
          'Postcode lookup is unavailable. Enter address manually.',
        ));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: UkPostalAddressForm(
            controllers: fields.controllers,
            lookupService: lookup,
            showManualEntryShortcut: true,
          ),
        ),
      ),
    ));
    await tester.enterText(
        find.widgetWithText(TextField, 'Postcode'), 'SW1A 1AA');
    await tester.tap(find.byTooltip('Search postcode'));
    await tester.pumpAndSettle();
    expect(find.textContaining('lookup is unavailable'), findsOneWidget);
    await tester.tap(find.text('Enter address manually'));
    await tester.pump();

    fields.line1.text = '10 Downing Street';
    fields.town.text = 'London';
    expect(
      RegistrationWizardSteps.validate(
        RegistrationWizardStep.address,
        role: 'worker',
        addressLine1: fields.line1.text,
        townCity: fields.town.text,
        postcode: fields.postcode.text,
        country: fields.country.text,
      ),
      isNull,
    );
  });

  testWidgets('invalid postcode shows a clear message without an API request',
      (tester) async {
    final fields = _AddressFields();
    addTearDown(fields.dispose);
    final lookup = _FakeLookup((_) async => const []);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: UkPostalAddressForm(
            controllers: fields.controllers,
            lookupService: lookup,
            showManualEntryShortcut: true,
          ),
        ),
      ),
    ));

    await tester.enterText(find.widgetWithText(TextField, 'Postcode'), 'BAD');
    await tester.tap(find.byTooltip('Search postcode'));
    await tester.pump();
    expect(find.textContaining('Invalid UK postcode'), findsOneWidget);
    expect(lookup.requests, isEmpty);
    expect(find.text('Enter address manually'), findsOneWidget);
  });

  testWidgets('late response cannot replace newer postcode selection',
      (tester) async {
    final fields = _AddressFields();
    addTearDown(fields.dispose);
    final first = Completer<List<PostalAddress>>();
    final lookup = _FakeLookup((postcode) {
      if (postcode == 'SW1A 1AA') return first.future;
      return Future.value([
        const PostalAddress(
          postcode: 'W1A 1AA',
          addressLine1: 'New address',
          townCity: 'London',
        ),
      ]);
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: UkPostalAddressForm(
            controllers: fields.controllers,
            lookupService: lookup,
          ),
        ),
      ),
    ));

    await tester.enterText(
        find.widgetWithText(TextField, 'Postcode'), 'SW1A 1AA');
    await tester.tap(find.byTooltip('Search postcode'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Postcode'), 'W1A 1AA');
    await tester.tap(find.byTooltip('Search postcode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New address').first);
    await tester.pumpAndSettle();

    first.complete([
      const PostalAddress(
        postcode: 'SW1A 1AA',
        addressLine1: 'Old address',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(fields.postcode.text, 'W1A 1AA');
    expect(fields.line1.text, 'New address');
    expect(find.text('Old address'), findsNothing);
  });
}
