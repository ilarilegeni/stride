import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' show Point;
import 'models/preferences.dart';
import 'services/geocoding_service.dart';
import 'widgets/control_panel.dart';
import 'widgets/directions_panel.dart';

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
  double _routeDistanceM = 0;
  int _routeTimeS = 0;

  final List<WaypointModel> _waypoints = [];
  final Map<String, Circle> _waypointCircles = {};

  bool _isAddingWaypointMode = false;
  bool _isReverseGeocoding = false;

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
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 14.0),
    );
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    if (_currentPosition != null) {
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 14.0,
        ),
      );
    }
  }

  /// Gère le tap sur le GestureDetector transparent posé sur la carte.
  /// N'est actif que quand [_isAddingWaypointMode] est vrai.
  Future<void> _handleMapTap(TapUpDetails details) async {
    if (_mapController == null) return;

    // Désactive immédiatement le mode pour éviter les double-taps
    setState(() {
      _isAddingWaypointMode = false;
      _isReverseGeocoding = true;
    });

    try {
      // Convertit les coordonnées écran → LatLng via le controller MapLibre
      final pos = details.localPosition;
      final latLng = await _mapController!.toLatLng(Point(pos.dx, pos.dy));

      // Reverse geocoding pour obtenir un nom de lieu lisible
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
    if (coords.isEmpty) return;
    await _mapController!.addLine(LineOptions(
      geometry: coords,
      lineColor: '#4CAF50',
      lineWidth: 6.0,
      lineOpacity: 0.85,
    ));
    _mapController!.animateCamera(CameraUpdate.newLatLng(coords.first));
  }

  void _onRouteGenerated(Map<String, dynamic> data) {
    if (data['status'] == 'downloading') {
      _showSnackBar(data['message'] as String, color: Colors.blueAccent, duration: 5);
      return;
    }
    final geojson = data['geojson'];
    if (geojson != null) _drawRoute(geojson as Map<String, dynamic>);
    setState(() {
      _routeDistanceM = (data['estimated_distance_m'] ?? 0).toDouble();
      _routeTimeS = (data['estimated_time_s'] ?? 0) as int;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stride'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          // ── 0. Carte MapLibre (fond) ──────────────────────────────────
          // IMPORTANT : pas de onMapClick ici. Le GestureDetector au-dessus
          // gère les taps pour éviter que MapLibre capture aussi les taps du FAB.
          Positioned.fill(
            child: MapLibreMap(
              onMapCreated: _onMapCreated,
              styleString: 'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json',
              initialCameraPosition: const CameraPosition(target: LatLng(20.0, 0.0), zoom: 2.0),
              myLocationEnabled: true,
              myLocationTrackingMode: MyLocationTrackingMode.tracking,
              compassEnabled: true,
            ),
          ),

          // ── 1. Overlay transparent (actif en mode ajout de waypoint) ──
          // Positionné SOUS les boutons/panneaux dans le Stack pour que
          // ceux-ci restent cliquables normalement.
          // HitTestBehavior.opaque : capture les taps même sur fond transparent.
          if (_isAddingWaypointMode && !_isReverseGeocoding)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _handleMapTap,
                child: const SizedBox.expand(),
              ),
            ),

          // ── 2. Bannière erreur GPS ────────────────────────────────────
          if (_locationError)
            Positioned(
              top: 12, left: 16, right: 16,
              child: Material(
                borderRadius: BorderRadius.circular(12),
                color: Colors.red.shade100,
                elevation: 2,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.location_off, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(child: Text('GPS non disponible.')),
                  ]),
                ),
              ),
            ),

          // ── 3. Bannière mode ajout waypoint ──────────────────────────
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

          // ── 4. FAB pour activer/désactiver le mode tap ────────────────
          Positioned(
            top: 12, right: 12,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FloatingActionButton.small(
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
              if (_maneuvers.isNotEmpty) ...[const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'directions_fab',
                  tooltip: 'Voir les directions',
                  backgroundColor: Colors.white,
                  elevation: 4,
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => DirectionsPanel(
                      maneuvers: _maneuvers,
                      distanceM: _routeDistanceM,
                      timeS: _routeTimeS,
                      startLat: _currentPosition?.latitude,
                      startLon: _currentPosition?.longitude,
                      waypoints: _waypoints,
                    ),
                  ),
                  child: const Icon(Icons.turn_right_alt, color: Colors.green),
                ),
              ],
            ]),
          ),

          // ── 5. Panneau de contrôle en bas ────────────────────────────
          Positioned(
            bottom: 20, left: 16, right: 16,
            child: SingleChildScrollView(
              child: ControlPanel(
                currentPosition: _currentPosition,
                isLoading: _isLoading,
                waypoints: _waypoints,
                onWaypointAdded: _addWaypoint,
                onWaypointRemoved: _removeWaypoint,
                onRouteGenerated: _onRouteGenerated,
                onError: (msg) => _showSnackBar(msg),
                onLoadingStart: () => setState(() => _isLoading = true),
                onLoadingEnd: () => setState(() => _isLoading = false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
