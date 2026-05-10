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

  // Google Maps app (mobile) limite généralement le nombre de waypoints à 9-10.
  // Si on envoie plus, l'application tronque le trajet, le rendant plus court.
  final int maxSafeWaypoints = maxWaypoints > 8 ? 8 : maxWaypoints;

  // L'origine et la destination doivent correspondre au début et à la fin réels du tracé
  double startLat = originLat;
  double startLon = originLon;
  double destLat = originLat;
  double destLon = originLon;

  if (routeCoords.isNotEmpty) {
    startLat = routeCoords.first.latitude;
    startLon = routeCoords.first.longitude;
    destLat = routeCoords.last.latitude;
    destLon = routeCoords.last.longitude;
    
    if (routeCoords.length > 4) {
      final int step = (routeCoords.length / (maxSafeWaypoints + 1)).ceil();
      for (int i = step; i < routeCoords.length - 1; i += step) {
        waypointStrs.add('${routeCoords[i].latitude},${routeCoords[i].longitude}');
        if (waypointStrs.length >= maxSafeWaypoints) break;
      }
    }
  } else if (userWaypoints.isNotEmpty) {
    waypointStrs = userWaypoints.map((w) => '${w.lat},${w.lon}').take(maxSafeWaypoints).toList();
    if (userWaypoints.isNotEmpty) {
      destLat = userWaypoints.last.lat;
      destLon = userWaypoints.last.lon;
    }
  }

  final wps = waypointStrs.join('|');
  return 'https://www.google.com/maps/dir/?api=1'
      '&origin=$startLat,$startLon'
      '&destination=$destLat,$destLon'
      '${wps.isNotEmpty ? "&waypoints=$wps" : ""}'
      '&travelmode=walking';
}
