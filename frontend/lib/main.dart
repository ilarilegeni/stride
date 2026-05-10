import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
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

  // Hauteur estimée du panneau de contrôle en bas (en pixels logiques).
  // Utilisée comme inset bottom pour que MapLibre centre correctement.
  static const double _panelBottomInset = 360.0;

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
    if (coords.isEmpty) return;
    await _mapController!.addLine(LineOptions(
      geometry: coords,
      lineColor: '#4CAF50',
      lineWidth: 6.0,
      lineOpacity: 0.85,
    ));

    double minLat = coords[0].latitude;
    double maxLat = coords[0].latitude;
    double minLon = coords[0].longitude;
    double maxLon = coords[0].longitude;
    for (var c in coords) {
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLon) minLon = c.longitude;
      if (c.longitude > maxLon) maxLon = c.longitude;
    }

    // BUG FIX #1 — bottom padding = hauteur panneau pour que le tracé soit
    // visible au-dessus du ControlPanel (et non caché derrière lui).
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLon), northeast: LatLng(maxLat, maxLon)),
        left: 40, top: 80, right: 40, bottom: _panelBottomInset.toInt(),
      ),
    );
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
      _drawRoute(geojson as Map<String, dynamic>);
      setState(() {
        _routeCoords = coords;
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
              // BUG FIX #1 — Indique à MapLibre que le bas de la carte est
              // recouvert par le panneau. Le point GPS et le centre de la
              // caméra seront dans la zone visible, pas sous le panneau.
              contentInsets: const EdgeInsets.only(bottom: _panelBottomInset),
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
