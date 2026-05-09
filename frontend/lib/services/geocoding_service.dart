import 'package:http/http.dart' as http;
import 'dart:convert';

class GeocodeResult {
  final double lat;
  final double lon;
  final String displayName;
  final String shortName;

  const GeocodeResult({
    required this.lat,
    required this.lon,
    required this.displayName,
    required this.shortName,
  });

  factory GeocodeResult.fromJson(Map<String, dynamic> json) {
    final display = json['display_name'] as String;
    return GeocodeResult(
      lat: double.parse(json['lat'] as String),
      lon: double.parse(json['lon'] as String),
      displayName: display,
      shortName: display.split(',').first.trim(),
    );
  }
}

/// Service de géocodage + géocodage inverse via Nominatim (OpenStreetMap).
/// Politique d'usage : max 1 req/s — toujours utiliser avec un debounce.
class GeocodingService {
  static const _base = 'https://nominatim.openstreetmap.org';
  static const _headers = {'User-Agent': 'StrideApp/1.0 (contact@stride.app)'};

  /// Recherche des lieux correspondant à [query]. Retourne jusqu'à 5 résultats.
  static Future<List<GeocodeResult>> search(String query) async {
    if (query.trim().length < 3) return [];
    final uri = Uri.parse('$_base/search').replace(queryParameters: {
      'q': query,
      'format': 'json',
      'limit': '5',
      'addressdetails': '0',
    });
    try {
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map((e) => GeocodeResult.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Géocodage inverse : retourne le nom du lieu aux coordonnées [lat], [lon].
  /// Utilise un zoom 17 (niveau quartier / rue).
  static Future<String> reverseGeocode(double lat, double lon) async {
    final uri = Uri.parse('$_base/reverse').replace(queryParameters: {
      'lat': lat.toString(),
      'lon': lon.toString(),
      'format': 'json',
      'zoom': '17',
      'addressdetails': '0',
    });
    try {
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final display = data['display_name'] as String? ?? '';
        return display.split(',').first.trim();
      }
    } catch (_) {}
    return '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
  }
}
