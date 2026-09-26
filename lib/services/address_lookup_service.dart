import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

String normalizeUkPostcode(String postcode) {
  final clean = postcode.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  if (clean.length <= 3) return clean;
  return '${clean.substring(0, clean.length - 3)} '
      '${clean.substring(clean.length - 3)}';
}

bool isValidUkPostcode(String postcode) => RegExp(
      r'^[A-Z]{1,2}[0-9][0-9A-Z]?\s?[0-9][A-Z]{2}$',
      caseSensitive: false,
    ).hasMatch(normalizeUkPostcode(postcode));

class AddressLookupException implements Exception {
  const AddressLookupException(this.message);

  final String message;
}

class PostalAddress {
  final String postcode;
  final String addressLine1;
  final String addressLine2;
  final String addressLine3;
  final String townCity;
  final String county;
  final String country;
  final double? latitude;
  final double? longitude;
  final String uprn;

  const PostalAddress({
    this.postcode = "",
    this.addressLine1 = "",
    this.addressLine2 = "",
    this.addressLine3 = "",
    this.townCity = "",
    this.county = "",
    this.country = "",
    this.latitude,
    this.longitude,
    this.uprn = "",
  });

  String get singleLine {
    final addressParts = [
      addressLine1.trim(),
      addressLine2.trim(),
      addressLine3.trim(),
      townCity.trim(),
      county.trim(),
      postcode.trim(),
    ].where((part) => part.isNotEmpty).toList();
    if (addressParts.isEmpty) return "";
    final countryPart = country.trim();
    if (countryPart.isNotEmpty) addressParts.add(countryPart);
    return addressParts.join(", ");
  }

  String get selectionLabel {
    final parts = [
      addressLine1.trim(),
      addressLine2.trim(),
      addressLine3.trim(),
      townCity.trim(),
      postcode.trim(),
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? "Address" : parts.join(", ");
  }
}

abstract class AddressLookupService {
  String normalizePostcode(String postcode);
  bool isValidPostcode(String postcode);
  Future<List<PostalAddress>> lookupAddresses(String postcode);

  Future<PostalAddress?> lookupPostcode(String postcode) async {
    final addresses = await lookupAddresses(postcode);
    return addresses.isEmpty ? null : addresses.first;
  }
}

class IdealPostcodesAddressLookupService implements AddressLookupService {
  IdealPostcodesAddressLookupService({
    FirebaseFunctions? functions,
  }) : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  String normalizePostcode(String postcode) => normalizeUkPostcode(postcode);

  @override
  bool isValidPostcode(String postcode) => isValidUkPostcode(postcode);

  String _stringValue(dynamic value) => value?.toString().trim() ?? "";

  @override
  Future<List<PostalAddress>> lookupAddresses(String postcode) async {
    final normalized = normalizePostcode(postcode);
    if (!isValidPostcode(normalized)) return const [];

    final callable = _functions.httpsCallable("lookupIdealPostcodeAddresses");
    final result = await callable.call<Map<String, dynamic>>({
      "postcode": normalized,
    });
    final data = result.data;
    final rawAddresses = data["addresses"];
    if (rawAddresses is! List) return const [];

    return rawAddresses
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .map((raw) {
      final country = _stringValue(raw["country"]);
      return PostalAddress(
        postcode: normalizePostcode(
          _stringValue(raw["postcode"]).isNotEmpty
              ? _stringValue(raw["postcode"])
              : normalized,
        ),
        addressLine1: _stringValue(raw["line1"]),
        addressLine2: _stringValue(raw["line2"]),
        addressLine3: _stringValue(raw["line3"]),
        townCity: _stringValue(raw["town"]),
        county: _stringValue(raw["county"]),
        country: country.isNotEmpty ? country : "United Kingdom",
        latitude: (raw["latitude"] as num?)?.toDouble(),
        longitude: (raw["longitude"] as num?)?.toDouble(),
        uprn: _stringValue(raw["uprn"]),
      );
    }).toList();
  }

  @override
  Future<PostalAddress?> lookupPostcode(String postcode) async {
    final addresses = await lookupAddresses(postcode);
    return addresses.isEmpty ? null : addresses.first;
  }
}

/// Postcodes.io supplies postcode geography, not individual street addresses.
class PostcodesIoAddressLookupService extends AddressLookupService {
  PostcodesIoAddressLookupService({http.Client? client}) : _client = client;

  final http.Client? _client;

  @override
  String normalizePostcode(String postcode) => normalizeUkPostcode(postcode);

  @override
  bool isValidPostcode(String postcode) => isValidUkPostcode(postcode);

  @override
  Future<List<PostalAddress>> lookupAddresses(String postcode) async {
    final normalized = normalizePostcode(postcode);
    if (!isValidPostcode(normalized)) return const [];

    final compact = normalized.replaceAll(' ', '');
    final url = Uri.https('api.postcodes.io', '/postcodes/$compact');
    late final http.Response response;
    try {
      response = await (_client?.get(url) ?? http.get(url))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      throw const AddressLookupException(
        'Postcode lookup is unavailable. Enter address manually.',
      );
    }

    if (response.statusCode == 404) return const [];
    if (response.statusCode != 200) {
      throw const AddressLookupException(
        'Postcode lookup is unavailable. Enter address manually.',
      );
    }

    try {
      final body = jsonDecode(response.body);
      if (body is! Map || body['result'] is! Map) {
        throw const FormatException('Missing postcode result');
      }
      final result = body['result'] as Map;
      String value(String key) => result[key]?.toString().trim() ?? '';
      final region = value('region');
      final district = value('admin_district');
      final returnedPostcode = value('postcode');
      return [
        PostalAddress(
          postcode: returnedPostcode.isEmpty
              ? normalized
              : normalizePostcode(returnedPostcode),
          townCity: region == 'London' ? 'London' : district,
          county: value('admin_county'),
          country: 'United Kingdom',
          latitude: (result['latitude'] as num?)?.toDouble(),
          longitude: (result['longitude'] as num?)?.toDouble(),
        ),
      ];
    } catch (_) {
      throw const AddressLookupException(
        'Postcode lookup returned an invalid response. Enter address manually.',
      );
    }
  }
}

/// Registration precedes email/password authentication. Keep paid property
/// lookup behind Firebase Auth and use the free postcode data until then.
class RegistrationAddressLookupService extends AddressLookupService {
  RegistrationAddressLookupService({
    AddressLookupService? propertyLookup,
    AddressLookupService? postcodeLookup,
    bool Function()? isSignedIn,
  })  : _propertyLookup =
            propertyLookup ?? IdealPostcodesAddressLookupService(),
        _postcodeLookup = postcodeLookup ?? PostcodesIoAddressLookupService(),
        _isSignedIn =
            isSignedIn ?? (() => FirebaseAuth.instance.currentUser != null);

  final AddressLookupService _propertyLookup;
  final AddressLookupService _postcodeLookup;
  final bool Function() _isSignedIn;

  @override
  String normalizePostcode(String postcode) => normalizeUkPostcode(postcode);

  @override
  bool isValidPostcode(String postcode) => isValidUkPostcode(postcode);

  @override
  Future<List<PostalAddress>> lookupAddresses(String postcode) async {
    final normalized = normalizePostcode(postcode);
    if (!isValidPostcode(normalized)) return const [];
    if (_isSignedIn()) {
      try {
        final addresses = await _propertyLookup.lookupAddresses(normalized);
        if (addresses.isNotEmpty) return addresses;
      } catch (_) {
        // The free postcode lookup remains available if the property API fails.
      }
    }
    return _postcodeLookup.lookupAddresses(normalized);
  }
}
