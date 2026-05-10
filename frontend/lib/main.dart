import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' show Point;
import 'models/preferences.dart';
import 'services/geocoding_service.dart';
import 'utils/maps_utils.dart';
import 'widgets/control_panel.dart';
import 'widgets/directions_panel.dart';
import 'widgets/waypoint_search.dart';

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

  // Route courante
  List<dynamic> _maneuvers = [];
  List<LatLng> _routeCoords = [];
  double _routeDistanceM = 0;
  int _routeTimeS = 0;

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
    _determinePosition();
  }

  Future<void> _determinePosition() async {
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
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(lat - eps, lon - eps),
          northeast: LatLng(lat + eps, lon + eps),
        ),
        left: 0, top: 0, right: 0, bottom: _panelBottomInset,
      ),
    );
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

  void _drawRoute(Map<String, dynamic> geojson) async {
    if (_mapController == null) return;
    await _mapController!.clearLines();
    final coords = (geojson['geometry']['coordinates'] as List)
        .map((c) => LatLng(c[1] as double, c[0] as double))
        .toList();
    if (_routeCoords.isEmpty) return;
    await _mapController!.addLine(LineOptions(
      geometry: _routeCoords,
      lineColor: '#4CAF50',
      lineWidth: 6.0,
      lineOpacity: 0.85,
    ));
    _frameRoute();
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

  /// BUG FIX #3 — Construit l'URL Google Maps avec jusqu'à 23 waypoints
  /// extraits régulièrement du tracé Valhalla pour mieux l'approximer.
  /// Délégué à l'utilitaire partagé maps_utils.dart (même logique que DirectionsPanel).
  Future<void> _launchMaps() async {
    if (_currentPosition == null) return;
    final url = buildGoogleMapsUrl(
      originLat: _currentPosition!.latitude,
      originLon: _currentPosition!.longitude,
      routeCoords: _routeCoords,
      userWaypoints: _waypoints,
    );
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) _showSnackBar('Impossible d\'ouvrir l\'application de cartes.');
    }
  }

  void _onRouteGenerated(Map<String, dynamic> data) {
    if (data['status'] == 'downloading') {
      _showSnackBar(data['message'] as String, color: Colors.blueAccent, duration: 5);
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
    _showSnackBar('Itinéraire généré : $km km', color: Colors.green);
  }

  void _showSnackBar(String msg, {Color color = Colors.red, int duration = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: Duration(seconds: duration),
    ));
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
              myLocationTrackingMode: MyLocationTrackingMode.tracking,
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

          // ── 4. Panneau de contrôle en bas ────────────────────────────
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
                onError: (msg) => _showSnackBar(msg),
                onLoadingStart: () => setState(() => _isLoading = true),
                onLoadingEnd: () => setState(() => _isLoading = false),
                hasRoute: _maneuvers.isNotEmpty,
                isCollapsed: _isPanelCollapsed,
                onToggleCollapse: _togglePanelCollapse,
                onShowDirections: _launchMaps,
                onShowSteps: _showDirectionsPanel,
                routeDistanceM: _routeDistanceM,
                routeTimeS: _routeTimeS,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
