import 'package:cloud_functions/cloud_functions.dart';

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
  String normalizePostcode(String postcode) {
    final clean =
        postcode.replaceAll(RegExp(r"[^A-Za-z0-9]"), "").trim().toUpperCase();
    if (clean.length <= 3) return clean;
    return "${clean.substring(0, clean.length - 3)} "
        "${clean.substring(clean.length - 3)}";
  }

  @override
  bool isValidPostcode(String postcode) {
    final normalized = normalizePostcode(postcode);
    final regex = RegExp(
      r"^[A-Z]{1,2}[0-9][0-9A-Z]?\s?[0-9][A-Z]{2}$",
      caseSensitive: false,
    );
    return regex.hasMatch(normalized);
  }

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
