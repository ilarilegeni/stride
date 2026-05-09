import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'models/preferences.dart';
import 'widgets/control_panel.dart';

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

  // Cercles des waypoints sur la carte (id waypoint → Circle)
  final Map<String, Circle> _waypointCircles = {};

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
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
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

  Future<void> _addWaypointMarker(WaypointModel wp) async {
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

  Future<void> _removeWaypointMarker(String wpId) async {
    final circle = _waypointCircles.remove(wpId);
    if (circle != null) await _mapController?.removeCircle(circle);
  }

  void _onRouteGenerated(Map<String, dynamic> data) {
    if (data['status'] == 'downloading') {
      _showSnackBar(data['message'] as String, color: Colors.blueAccent, duration: 5);
      return;
    }
    final geojson = data['geojson'];
    if (geojson != null) _drawRoute(geojson as Map<String, dynamic>);
    final km = ((data['estimated_distance_m'] ?? 0) / 1000).toStringAsFixed(2);
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
          // Carte plein écran
          Positioned.fill(
            child: MapLibreMap(
              onMapCreated: _onMapCreated,
              styleString: 'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json',
              // Monde dézoomé : zoom automatique dès que le GPS répond
              initialCameraPosition: const CameraPosition(target: LatLng(20.0, 0.0), zoom: 2.0),
              myLocationEnabled: true,
              myLocationTrackingMode: MyLocationTrackingMode.tracking,
              compassEnabled: true,
            ),
          ),

          // Bannière erreur GPS
          if (_locationError)
            Positioned(
              top: 12, left: 16, right: 16,
              child: Material(
                borderRadius: BorderRadius.circular(12),
                color: Colors.red.shade100,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.location_off, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(child: Text('GPS non disponible. La génération se fera depuis le centre de la carte.')),
                  ]),
                ),
              ),
            ),

          // Panneau de contrôle en bas
          Positioned(
            bottom: 20, left: 16, right: 16,
            child: SingleChildScrollView(
              child: ControlPanel(
                currentPosition: _currentPosition,
                isLoading: _isLoading,
                onRouteGenerated: _onRouteGenerated,
                onWaypointMarkerAdded: _addWaypointMarker,
                onWaypointMarkerRemoved: _removeWaypointMarker,
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
