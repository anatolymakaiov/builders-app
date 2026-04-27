import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class GeocodingService {
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
