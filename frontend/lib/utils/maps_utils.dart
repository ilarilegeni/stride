import 'package:maplibre_gl/maplibre_gl.dart';
import '../models/preferences.dart';

/// Construit l'URL Google Maps Walking pour le trajet en boucle.
///
/// Prélève jusqu'à [maxWaypoints] points régulièrement répartis sur
/// [routeCoords] pour que Google Maps suive le tracé Valhalla aussi fidèlement
/// que possible (Google Maps URL accepte max 23 waypoints intermédiaires).
/// Si [routeCoords] est vide, repli sur les [userWaypoints] de l'utilisateur.
String buildGoogleMapsUrl({
  required double originLat,
  required double originLon,
  required List<LatLng> routeCoords,
  required List<WaypointModel> userWaypoints,
  int maxWaypoints = 23,
}) {
  List<String> waypointStrs = [];

  if (routeCoords.length > 4) {
    final int step = (routeCoords.length / (maxWaypoints + 1)).ceil();
    for (int i = step; i < routeCoords.length - 1; i += step) {
      waypointStrs.add('${routeCoords[i].latitude},${routeCoords[i].longitude}');
      if (waypointStrs.length >= maxWaypoints) break;
    }
  } else if (userWaypoints.isNotEmpty) {
    waypointStrs = userWaypoints.map((w) => '${w.lat},${w.lon}').toList();
  }

  final wps = waypointStrs.join('|');
  return 'https://www.google.com/maps/dir/?api=1'
      '&origin=$originLat,$originLon'
      '&destination=$originLat,$originLon'
      '${wps.isNotEmpty ? "&waypoints=$wps" : ""}'
      '&travelmode=walking';
}
