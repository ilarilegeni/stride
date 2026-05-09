import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/preferences.dart';

class ApiService {
  static const String _baseUrl = 'http://127.0.0.1:8000';

  static Future<Map<String, dynamic>> generateRoute({
    required double lat,
    required double lon,
    required DistanceUnit unit,
    required double value,
    required UserProfile userProfile,
    required RoutePreferences preferences,
    required List<WaypointModel> waypoints,
  }) async {
    final body = <String, dynamic>{
      'lat': lat,
      'lon': lon,
      'preferences': preferences.toJson(),
      'waypoints': waypoints
          .map((w) => {'lat': w.lat, 'lon': w.lon, 'name': w.name})
          .toList(),
    };

    switch (unit) {
      case DistanceUnit.steps:
        body['steps'] = value.round();
        body['step_length_m'] = userProfile.stepLengthM;
      case DistanceUnit.kilometers:
        body['distance_km'] = value;
      case DistanceUnit.time:
        body['time_minutes'] = value;
        // On envoie la vitesse de marche pour que le backend calcule la bonne distance
        body['walking_speed_kmh'] = userProfile.walkingSpeedKmh;
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/api/routes/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Erreur API: ${response.statusCode} - ${response.body}');
  }
}
