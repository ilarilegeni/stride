import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' show Point;
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'models/preferences.dart';
import 'services/geocoding_service.dart';
import 'services/navigation_notification_service.dart';
import 'widgets/control_panel.dart';
import 'widgets/directions_panel.dart';
import 'widgets/waypoint_search.dart';

/// ─── DEBUG : Forcer une localisation initiale (null = utiliser le GPS réel) ───
/// Pour débugger, décommente et modifie les coordonnées ci-dessous :
// const _kDebugLocation = {'lat': 48.8566, 'lon': 2.3522}; // Paris
const Map<String, double>? _kDebugLocation = null;

class AppNotification {
  final String message;
  final DateTime time;
  final Color color;
  AppNotification(this.message, this.time, this.color);
}

void main() => runApp(const StrideApp());

class StrideApp extends StatelessWidget {
  const StrideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stride',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MapLibreMapController? _mapController;
  Position? _currentPosition;
  bool _locationError = false;
  bool _isLoading = false;
  bool _isNavigating = false;
  MyLocationTrackingMode _trackingMode = MyLocationTrackingMode.tracking;

  StreamSubscription<Position>? _positionStream;
  bool _isOffRoute = false;

  final List<AppNotification> _notificationsList = [];
  AppNotification? _currentActiveNotification;
  Timer? _notificationTimer;
  bool _showNotificationsHistory = false;

  // Route courante
  List<dynamic> _maneuvers = [];
  List<LatLng> _routeCoords = [];
  double _routeDistanceM = 0;
  int _routeTimeS = 0;

  // Navigation en cours — état temps réel
  int _currentManeuverIndex = 0;   // index de la prochaine manœuvre
  double _remainingDistanceM = 0;  // distance restante sur le parcours
  int _remainingTimeS = 0;         // temps restant estimé
  int _remainingSteps = 0;         // pas restants estimés
  int _distanceToNextM = 0;        // mètres avant le prochain virage

  // Polylines : tracé futur (vert) + tracé passé (gris)
  Line? _futureRouteLine;
  Line? _passedRouteLine;
  int _lastPassedIndex = 0;        // dernier point passé dans _routeCoords

  // Profil utilisateur courant (pour calculer les pas)
  final UserProfile _userProfile = UserProfile();

  final List<WaypointModel> _waypoints = [];
  final Map<String, Circle> _waypointCircles = {};

  bool _isAddingWaypointMode = false;
  bool _isReverseGeocoding = false;

  bool _isPanelCollapsed = false;
  final GlobalKey _panelKey = GlobalKey();

  // Calcule la hauteur réelle du panneau de contrôle pour centrer la carte parfaitement.
  double get _panelBottomInset {
    if (_panelKey.currentContext != null) {
      final RenderBox box = _panelKey.currentContext!.findRenderObject() as RenderBox;
      // On ajoute 40.0 pour inclure le Positioned(bottom: 20) et laisser une marge visuelle
      return box.size.height + 40.0; 
    }
    return _isPanelCollapsed ? 150.0 : 360.0;
  }

  @override
  void initState() {
    super.initState();
    NavigationNotificationService.initialize();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    // ─── DEBUG : position forcée ───────────────────────────────────────────
    if (_kDebugLocation != null) {
      final fakeLat = _kDebugLocation!['lat']!;
      final fakeLon = _kDebugLocation!['lon']!;
      setState(() {
        _currentPosition = Position(
          latitude: fakeLat, longitude: fakeLon,
          timestamp: DateTime.now(), accuracy: 1,
          altitude: 0, heading: 0, speed: 0,
          speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
        );
        _locationError = false;
      });
      _animateCameraToPoint(fakeLat, fakeLon);
      return;
    }
    // ─── GPS réel ─────────────────────────────────────────────────────────
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _locationError = true);
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      setState(() => _locationError = true);
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    setState(() => _currentPosition = pos);
    _animateCameraToPoint(pos.latitude, pos.longitude);
  }

  /// Centre la caméra sur [lat, lon] en tenant compte du panneau bas.
  /// newLatLngBounds avec un epsilon + padding bottom pousse le focal
  /// point vers le haut, donc le marqueur GPS reste visible au-dessus
  /// du ControlPanel (remplacement de contentInsets, absent en v0.26.0).
  void _animateCameraToPoint(double lat, double lon) {
    const double eps = 0.001; // ~110 m — assez petit pour rester à zoom ~14
    
    // BUG FIX: On attend 400ms pour s'assurer que le rendu iOS de la carte a bien une hauteur > 0.
    // Sinon, appliquer un 'bottom padding' de 360px sur une hauteur de 0px génère une erreur mathématique
    // dans le moteur C++ (std::domain_error) car la zone d'affichage devient négative.
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _mapController == null) return;
      try {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(lat - eps, lon - eps),
              northeast: LatLng(lat + eps, lon + eps),
            ),
            left: 0, top: 0, right: 0, bottom: _panelBottomInset,
          ),
        );
      } catch (e) {
        debugPrint("Erreur animateCamera: $e");
      }
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    if (_currentPosition != null) {
      _animateCameraToPoint(_currentPosition!.latitude, _currentPosition!.longitude);
    }
  }

  /// BUG FIX #2 — Utilise le callback natif onMapClick de MapLibre.
  /// MapLibre fournit directement le LatLng correspondant au tap, sans aucune
  /// conversion pixel → LatLng côté Dart. Ça évite le problème de device
  /// pixel ratio qui décalait le point placé sur tablette Android.
  Future<void> _onMapClick(Point<double> point, LatLng latLng) async {
    // N'agit que si le mode "ajout de waypoint" est actif
    if (!_isAddingWaypointMode || _isReverseGeocoding) return;

    setState(() {
      _isAddingWaypointMode = false;
      _isReverseGeocoding = true;
    });

    try {
      final name = await GeocodingService.reverseGeocode(latLng.latitude, latLng.longitude);
      await _addWaypoint(WaypointModel(lat: latLng.latitude, lon: latLng.longitude, name: name));
    } finally {
      if (mounted) setState(() => _isReverseGeocoding = false);
    }
  }

  Future<void> _addWaypoint(WaypointModel wp) async {
    setState(() => _waypoints.add(wp));
    if (_mapController == null) return;
    final circle = await _mapController!.addCircle(CircleOptions(
      geometry: LatLng(wp.lat, wp.lon),
      circleColor: '#FF5722',
      circleRadius: 9.0,
      circleStrokeWidth: 2.5,
      circleStrokeColor: '#FFFFFF',
    ));
    _waypointCircles[wp.id] = circle;
  }

  Future<void> _removeWaypoint(String wpId) async {
    setState(() => _waypoints.removeWhere((w) => w.id == wpId));
    final circle = _waypointCircles.remove(wpId);
    if (circle != null) await _mapController?.removeCircle(circle);
  }

  /// Dessine le tracé complet (vert). Appelé une seule fois à la génération.
  Future<void> _drawRoute(Map<String, dynamic> geojson) async {
    if (_mapController == null || _routeCoords.isEmpty) return;
    await _mapController!.clearLines();
    _futureRouteLine = await _mapController!.addLine(LineOptions(
      geometry: _routeCoords,
      lineColor: '#4CAF50',
      lineWidth: 6.0,
      lineOpacity: 0.85,
    ));
    _passedRouteLine = null;
    _lastPassedIndex = 0;
    _frameRoute();
  }

  /// Met à jour les deux polylines selon la position courante.
  Future<void> _updateRouteSegments(int closestIndex) async {
    if (_mapController == null || _routeCoords.isEmpty) return;
    if (closestIndex <= _lastPassedIndex && _lastPassedIndex > 0) return;
    _lastPassedIndex = closestIndex;

    final passed = _routeCoords.sublist(0, closestIndex + 1);
    final future = _routeCoords.sublist(closestIndex);

    if (passed.length >= 2) {
      if (_passedRouteLine == null) {
        _passedRouteLine = await _mapController!.addLine(LineOptions(
          geometry: passed, lineColor: '#9E9E9E', lineWidth: 6.0, lineOpacity: 0.7,
        ));
      } else {
        await _mapController!.updateLine(_passedRouteLine!, LineOptions(geometry: passed));
      }
    }
    if (future.length >= 2 && _futureRouteLine != null) {
      await _mapController!.updateLine(_futureRouteLine!, LineOptions(geometry: future));
    }
  }

  void _frameRoute() {
    if (_routeCoords.isEmpty || _mapController == null) return;
    double minLat = _routeCoords[0].latitude;
    double maxLat = _routeCoords[0].latitude;
    double minLon = _routeCoords[0].longitude;
    double maxLon = _routeCoords[0].longitude;
    for (var c in _routeCoords) {
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLon) minLon = c.longitude;
      if (c.longitude > maxLon) maxLon = c.longitude;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLon), northeast: LatLng(maxLat, maxLon)),
        left: 40, top: 80, right: 40, bottom: _panelBottomInset,
      ),
    );
  }

  void _togglePanelCollapse() {
    setState(() {
      _isPanelCollapsed = !_isPanelCollapsed;
    });
    // On attend un peu plus longtemps (200ms) pour être sûr que l'animation/re-layout
    // du ControlPanel est terminée avant de mesurer sa nouvelle taille.
    Future.delayed(const Duration(milliseconds: 200), _frameRoute);
  }

  void _startNavigation() {
    NavigationNotificationService.requestPermission();
    setState(() {
      _isNavigating = true;
      _isPanelCollapsed = true;
      _trackingMode = MyLocationTrackingMode.trackingCompass;
      _currentManeuverIndex = 0;
      _remainingDistanceM = _routeDistanceM;
      _remainingTimeS = _routeTimeS;
      _remainingSteps = _stepsFromDistance(_remainingDistanceM);
      _lastPassedIndex = 0;
    });

    if (_currentPosition != null) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            zoom: 19.5, tilt: 60.0,
          ),
        ),
      );
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position pos) {
      if (mounted) {
        setState(() => _currentPosition = pos);
        _checkOffRoute(pos);
        _updateNavigationState(pos);
      }
    });
  }

  /// Calcule le nombre de pas depuis une distance en mètres.
  int _stepsFromDistance(double distM) =>
      (distM / _userProfile.stepLengthM).round();

  /// Met à jour l'ETA, les pas restants, la manœuvre suivante et les notifications.
  void _updateNavigationState(Position pos) {
    if (_routeCoords.isEmpty || _maneuvers.isEmpty) return;

    // Trouve le point le plus proche sur le tracé
    int closestIndex = 0;
    double minDist = double.infinity;
    for (int i = 0; i < _routeCoords.length; i++) {
      final d = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        _routeCoords[i].latitude, _routeCoords[i].longitude,
      );
      if (d < minDist) { minDist = d; closestIndex = i; }
    }

    // Distance restante = somme des segments depuis closestIndex
    double remDist = 0;
    for (int i = closestIndex; i < _routeCoords.length - 1; i++) {
      remDist += Geolocator.distanceBetween(
        _routeCoords[i].latitude, _routeCoords[i].longitude,
        _routeCoords[i + 1].latitude, _routeCoords[i + 1].longitude,
      );
    }

    // Prochaine manœuvre — on avance l'index quand on dépasse son point de déclenchement
    int manIdx = _currentManeuverIndex;
    if (manIdx < _maneuvers.length - 1) {
      final nextDist = (_maneuvers[manIdx]['length_m'] as num?)?.toDouble() ?? 0;
      if (remDist < _remainingDistanceM - nextDist + 20) {
        manIdx = (manIdx + 1).clamp(0, _maneuvers.length - 1);
      }
    }

    // Distance avant le prochain virage = distance cumulée jusqu'à la manœuvre suivante
    final distToNext = (_maneuvers[manIdx]['length_m'] as num?)?.toInt() ?? 0;
    final nextInstruction = (_maneuvers[manIdx]['instruction'] as String?) ?? '';
    final remTimeS = _routeTimeS > 0
        ? (remDist / _routeDistanceM * _routeTimeS).round()
        : 0;

    setState(() {
      _currentManeuverIndex = manIdx;
      _remainingDistanceM = remDist;
      _remainingTimeS = remTimeS;
      _remainingSteps = _stepsFromDistance(remDist);
      _distanceToNextM = distToNext;
    });

    // Mise à jour polylines (asynchrone, pas de setState)
    _updateRouteSegments(closestIndex);

    // Notification système
    NavigationNotificationService.showNavigationNotification(
      nextManeuver: nextInstruction,
      distanceToNextM: distToNext,
      remainingKm: remDist / 1000,
      etaMinutes: remTimeS ~/ 60,
      remainingSteps: _remainingSteps,
    );
  }

  void _checkOffRoute(Position pos) {
    if (_routeCoords.isEmpty || !_isNavigating) return;
    
    double minDistance = double.infinity;
    for (final p in _routeCoords) {
      double dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, p.latitude, p.longitude);
      if (dist < minDistance) minDistance = dist;
    }
    
    if (minDistance > 40.0) { // Si écart > 40m
      if (!_isOffRoute) {
        _isOffRoute = true;
        HapticFeedback.heavyImpact(); // Vibration forte !
        _showNotification("Attention, tu t'éloignes de l'itinéraire !", color: Colors.orange);
      }
    } else if (minDistance < 20.0) { // Si on revient à < 20m
      if (_isOffRoute) {
        _isOffRoute = false;
        HapticFeedback.lightImpact();
        _showNotification("Te revoilà sur le bon chemin !", color: Colors.green);
      }
    }
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
      _isPanelCollapsed = false;
      _trackingMode = MyLocationTrackingMode.tracking;
    });
    _positionStream?.cancel();
    _isOffRoute = false;
    NavigationNotificationService.cancelNavigationNotification();
    // Remet le tracé complet en vert
    _drawRoute({'geometry': {'type': 'LineString', 'coordinates': _routeCoords.map((p) => [p.longitude, p.latitude]).toList()}});
    _frameRoute();
  }

  Future<void> _exportGpx() async {
    if (_routeCoords.isEmpty) return;
    _showNotification('Création du fichier GPX...', color: Colors.blueAccent);
    
    try {
      final buffer = StringBuffer();
      buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      buffer.writeln('<gpx version="1.1" creator="Stride">');
      buffer.writeln('  <trk>');
      buffer.writeln('    <name>Mon Itinéraire Stride</name>');
      buffer.writeln('    <trkseg>');
      for (final p in _routeCoords) {
        buffer.writeln('      <trkpt lat="${p.latitude}" lon="${p.longitude}"></trkpt>');
      }
      buffer.writeln('    </trkseg>');
      buffer.writeln('  </trk>');
      buffer.writeln('</gpx>');

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/stride_route.gpx');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles([XFile(file.path)], text: 'Voici mon itinéraire de marche généré par Stride !');
    } catch (e) {
      _showNotification('Erreur lors de l\'export: $e');
    }
  }

  void _onRouteGenerated(Map<String, dynamic> data) {
    if (data['status'] == 'downloading') {
      _showNotification(data['message'] as String, color: Colors.blueAccent, duration: 5);
      return;
    }
    final geojson = data['geojson'];
    if (geojson != null) {
      final coords = (geojson['geometry']['coordinates'] as List)
          .map((c) => LatLng(c[1] as double, c[0] as double))
          .toList();
      setState(() {
        _routeCoords = coords;
        _isPanelCollapsed = true;
      });
      // On attend que le panneau se replie (changement d'état UI) pour récupérer sa nouvelle taille
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _drawRoute(geojson as Map<String, dynamic>);
      });
    }
    setState(() {
      _routeDistanceM = ((data['estimated_distance_m'] ?? 0) as num).toDouble();
      _routeTimeS = ((data['estimated_time_s'] ?? 0) as num).toInt();
      _maneuvers = (data['maneuvers'] as List<dynamic>?) ?? [];
    });
    final km = (_routeDistanceM / 1000).toStringAsFixed(2);
    final steps = _stepsFromDistance(_routeDistanceM);
    final mins = _routeTimeS ~/ 60;
    final timeStr = mins < 60 ? '$mins min' : '${mins ~/ 60}h${(mins % 60).toString().padLeft(2,'0')}';
    _showNotification('$km km · ~$steps pas · $timeStr', color: Colors.green, duration: 5);
  }

  void _showNotification(String msg, {Color color = Colors.red, int duration = 3}) {
    if (!mounted) return;
    
    final notif = AppNotification(msg, DateTime.now(), color);
    setState(() {
      _notificationsList.add(notif);
      _currentActiveNotification = notif;
    });

    _notificationTimer?.cancel();
    _notificationTimer = Timer(Duration(seconds: duration), () {
      if (mounted) {
        setState(() {
          if (_currentActiveNotification == notif) {
            _currentActiveNotification = null;
          }
        });
      }
    });
  }

  void _showDirectionsPanel() {
    if (_maneuvers.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DirectionsPanel(
        maneuvers: _maneuvers,
        distanceM: _routeDistanceM,
        timeS: _routeTimeS,
        startLat: _currentPosition?.latitude,
        startLon: _currentPosition?.longitude,
        routeCoords: _routeCoords,
        waypoints: _waypoints,
      ),
    );
  }

  /// Icône de manœuvre selon l'index courant dans _maneuvers.
  IconData _maneuverIconData(int idx) {
    if (_maneuvers.isEmpty || idx >= _maneuvers.length) return Icons.navigation;
    final type = (_maneuvers[idx]['type'] as num?)?.toInt() ?? 0;
    return switch (type) {
      1 || 2 || 3 => Icons.play_arrow,
      4 || 5 || 6 => Icons.flag,
      8 => Icons.straight,
      9 => Icons.turn_slight_right,
      10 => Icons.turn_right,
      11 => Icons.turn_sharp_right,
      12 || 13 => Icons.u_turn_right,
      14 => Icons.turn_sharp_left,
      15 => Icons.turn_left,
      16 => Icons.turn_slight_left,
      _ => Icons.navigation,
    };
  }

  /// Widget stat dans la barre ETA navigation.
  Widget _navStat(IconData icon, Color color, String value, String label) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Stride'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          // ── 0. Carte MapLibre (fond) ──────────────────────────────────
          // onMapClick gère maintenant l'ajout de waypoints (cf. BUG FIX #2).
          // contentInsets.bottom = hauteur du panneau → MapLibre décale son
          // centre focal vers le haut (BUG FIX #1).
          Positioned.fill(
            child: MapLibreMap(
              onMapCreated: _onMapCreated,
              onMapClick: _onMapClick,
              styleString: 'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json',
              initialCameraPosition: const CameraPosition(target: LatLng(20.0, 0.0), zoom: 2.0),
              myLocationEnabled: true,
              myLocationTrackingMode: _trackingMode,
              compassEnabled: true,
            ),
          ),

          // ── 1. Bannière mode ajout waypoint ──────────────────────────
          // Plus besoin d'un GestureDetector overlay grâce à onMapClick.
          if (_isAddingWaypointMode || _isReverseGeocoding)
            Positioned(
              top: _locationError ? 70 : 12, left: 16, right: 72,
              child: Material(
                borderRadius: BorderRadius.circular(12),
                color: Colors.orange.shade50,
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    if (_isReverseGeocoding)
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      const Icon(Icons.touch_app, color: Colors.orange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      _isReverseGeocoding
                          ? 'Identification du lieu...'
                          : 'Appuyez sur la carte pour placer un point',
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                    )),
                  ]),
                ),
              ),
            ),

          // ── 2. Bannière erreur GPS ────────────────────────────────────
          if (_locationError)
            Positioned(
              top: 12, left: 16, right: 16,
              child: Material(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Row(children: [
                        Icon(Icons.location_off, color: Colors.red),
                        SizedBox(width: 8),
                        Expanded(child: Text('GPS non disponible.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
                      ]),
                      const SizedBox(height: 10),
                      WaypointSearch(
                        hintText: 'Entrez votre adresse de départ...',
                        onWaypointSelected: (wp) {
                          setState(() {
                            _currentPosition = Position(
                              latitude: wp.lat,
                              longitude: wp.lon,
                              timestamp: DateTime.now(),
                              accuracy: 1,
                              altitude: 0,
                              heading: 0,
                              speed: 0,
                              speedAccuracy: 0,
                              altitudeAccuracy: 0,
                              headingAccuracy: 0,
                            );
                            _locationError = false;
                          });
                          _mapController?.animateCamera(
                            CameraUpdate.newLatLngZoom(LatLng(wp.lat, wp.lon), 14.0),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 3. FAB waypoint ──────────────────────────────────────────
          Positioned(
            top: 12, left: 12,
            child: FloatingActionButton.small(
              heroTag: 'add_waypoint_fab',
              tooltip: _isAddingWaypointMode ? 'Annuler' : 'Placer un point sur la carte',
              backgroundColor: _isAddingWaypointMode ? Colors.orange : Colors.white,
              elevation: 4,
              onPressed: () => setState(() => _isAddingWaypointMode = !_isAddingWaypointMode),
              child: Icon(
                _isAddingWaypointMode ? Icons.close : Icons.add_location_alt,
                color: _isAddingWaypointMode ? Colors.white : Colors.grey[700],
              ),
            ),
          ),

          // ── 4. Panneau de contrôle en bas (Caché si navigation en cours) ──
          if (!_isNavigating)
            Positioned(
              bottom: 20, left: 16, right: 16,
              child: SingleChildScrollView(
                child: ControlPanel(
                  key: _panelKey,
                  currentPosition: _currentPosition,
                  isLoading: _isLoading,
                  waypoints: _waypoints,
                  onWaypointAdded: _addWaypoint,
                  onWaypointRemoved: _removeWaypoint,
                  onRouteGenerated: _onRouteGenerated,
                  onError: (msg) => _showNotification(msg),
                  onLoadingStart: () => setState(() => _isLoading = true),
                  onLoadingEnd: () => setState(() => _isLoading = false),
                  hasRoute: _maneuvers.isNotEmpty,
                  isCollapsed: _isPanelCollapsed,
                  onToggleCollapse: _togglePanelCollapse,
                  onShowDirections: _startNavigation,
                  onExportGpx: _exportGpx,
                  onShowSteps: _showDirectionsPanel,
                  routeDistanceM: _routeDistanceM,
                  routeTimeS: _routeTimeS,
                  userProfile: _userProfile,
                ),
              ),
            ),

          // ── 5. HUD Navigation (ETA + prochain virage) ─────────────────
          if (_isNavigating) ...[
            // Carte du prochain virage (haut de l'écran)
            if (_maneuvers.isNotEmpty)
              Positioned(
                top: 12, left: 12, right: 12,
                child: Material(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.black.withOpacity(0.82),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        Icon(
                          _maneuverIconData(_currentManeuverIndex),
                          color: Colors.white, size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              _distanceToNextM >= 1000
                                  ? 'Dans ${(_distanceToNextM / 1000).toStringAsFixed(1)} km'
                                  : 'Dans $_distanceToNextM m',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            Text(
                              (_maneuvers[_currentManeuverIndex]['instruction'] as String?) ?? '',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                            ),
                          ]),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),

            // Barre ETA en bas
            Positioned(
              bottom: 110, left: 16, right: 16,
              child: Material(
                borderRadius: BorderRadius.circular(16),
                color: Colors.black.withOpacity(0.82),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _navStat(
                        Icons.timer_outlined, Colors.greenAccent,
                        _remainingTimeS < 3600
                            ? '${_remainingTimeS ~/ 60} min'
                            : '${_remainingTimeS ~/ 3600}h${((_remainingTimeS % 3600) ~/ 60).toString().padLeft(2,'0')}',
                        'ETA',
                      ),
                      _navStat(
                        Icons.straighten, Colors.cyanAccent,
                        '${(_remainingDistanceM / 1000).toStringAsFixed(2)} km',
                        'Restant',
                      ),
                      _navStat(
                        Icons.directions_walk, Colors.orangeAccent,
                        '~$_remainingSteps',
                        'Pas',
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bouton arrêter
            Positioned(
              bottom: 40, left: 0, right: 0,
              child: Center(
                child: FloatingActionButton.extended(
                  onPressed: _stopNavigation,
                  backgroundColor: Colors.red[600],
                  elevation: 8,
                  icon: const Icon(Icons.stop_circle, color: Colors.white),
                  label: const Text('Arrêter', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],

          // ── 6. Bouton Historique Notifications (Haut Droite) ───────────
          Positioned(
            top: 12, right: 16,
            child: FloatingActionButton.small(
              heroTag: 'notif_history_fab',
              backgroundColor: Colors.white,
              elevation: 4,
              onPressed: () => setState(() => _showNotificationsHistory = !_showNotificationsHistory),
              child: Icon(
                _showNotificationsHistory ? Icons.close : Icons.notifications,
                color: _notificationsList.isEmpty ? Colors.grey[400] : Colors.blueAccent,
              ),
            ),
          ),

          // ── 7. Panneau Historique Notifications ─────────────────────────
          if (_showNotificationsHistory)
            Positioned(
              top: 70, right: 16, bottom: 200,
              width: 280,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withOpacity(0.98),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
                      child: const Row(
                        children: [
                          Icon(Icons.history, size: 18),
                          SizedBox(width: 8),
                          Text('Historique', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _notificationsList.isEmpty 
                        ? const Center(child: Text('Aucune notification', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _notificationsList.length,
                          itemBuilder: (ctx, i) {
                            final n = _notificationsList.reversed.toList()[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: n.color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: n.color.withOpacity(0.5)),
                              ),
                              child: Text(n.message, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            );
                          },
                        ),
                    ),
                  ],
                ),
              ),
            ),

          // ── 8. Toast de Notification Active (Haut Droite) ───────────────
          if (_currentActiveNotification != null && !_showNotificationsHistory)
            Positioned(
              top: 70, right: 16,
              child: Material(
                color: Colors.transparent,
                child: AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _currentActiveNotification!.color.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                    ),
                    child: Text(
                      _currentActiveNotification!.message,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
