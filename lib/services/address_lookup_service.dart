import 'dart:convert';

import 'package:http/http.dart' as http;

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
}

abstract class AddressLookupService {
  String normalizePostcode(String postcode);
  bool isValidPostcode(String postcode);
  Future<PostalAddress?> lookupPostcode(String postcode);
}

class PostcodesIoAddressLookupService implements AddressLookupService {
  const PostcodesIoAddressLookupService();

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

  @override
  Future<PostalAddress?> lookupPostcode(String postcode) async {
    final normalized = normalizePostcode(postcode);
    if (!isValidPostcode(normalized)) return null;

    try {
      final clean = normalized.replaceAll(" ", "");
      final response = await http.get(
        Uri.parse("https://api.postcodes.io/postcodes/$clean"),
      );
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded["status"] != 200 || decoded["result"] is! Map) return null;

      final result = Map<String, dynamic>.from(decoded["result"] as Map);
      final district = result["admin_district"]?.toString().trim() ?? "";
      final parish = result["parish"]?.toString().trim() ?? "";
      final county = result["admin_county"]?.toString().trim() ?? "";
      final country = result["country"]?.toString().trim() ?? "";

      return PostalAddress(
        postcode: normalized,
        townCity: district.isNotEmpty ? district : parish,
        county: county,
        country: country.isNotEmpty ? country : "United Kingdom",
        latitude: (result["latitude"] as num?)?.toDouble(),
        longitude: (result["longitude"] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
