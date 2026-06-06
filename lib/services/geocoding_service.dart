import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class GeocodingService {
  String normalizeUKPostcode(String postcode) {
    final clean =
        postcode.replaceAll(RegExp(r'[^A-Za-z0-9]'), "").trim().toUpperCase();
    if (clean.length <= 3) return clean;
    return "${clean.substring(0, clean.length - 3)} "
        "${clean.substring(clean.length - 3)}";
  }

  bool isValidUKPostcode(String postcode) {
    final normalized = normalizeUKPostcode(postcode);
    final regex = RegExp(
      r'^[A-Z]{1,2}[0-9][0-9A-Z]?\s?[0-9][A-Z]{2}$',
      caseSensitive: false,
    );
    return regex.hasMatch(normalized);
  }

  Future<({String postcode, double lat, double lng})?> lookupUKPostcode(
    String postcode,
  ) async {
    final normalized = normalizeUKPostcode(postcode);
    if (!isValidUKPostcode(normalized)) return null;

    try {
      final clean = normalized.replaceAll(" ", "");
      final response = await http.get(
        Uri.parse("https://api.postcodes.io/postcodes/$clean"),
      );
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data["status"] != 200 || data["result"] is! Map) return null;

      final result = Map<String, dynamic>.from(data["result"] as Map);
      final lat = (result["latitude"] as num?)?.toDouble();
      final lng = (result["longitude"] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      return (postcode: normalized, lat: lat, lng: lng);
    } catch (_) {
      return null;
    }
  }

  Future<LatLng?> getCoordinates(String location) async {
    final url = Uri.parse(
      "https://nominatim.openstreetmap.org/search?q=$location&format=json&limit=1",
    );

    final response = await http.get(
      url,
      headers: {"User-Agent": "flutter-job-app"},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data.isNotEmpty) {
        final lat = double.parse(data[0]["lat"]);
        final lon = double.parse(data[0]["lon"]);

        return LatLng(lat, lon);
      }
    }

    return null;
  }
}
