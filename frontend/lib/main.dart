import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const StrideApp());
}

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

// ---------------------------------------------------------------------------
// Modèle local des préférences (miroir du backend RoutePreferences)
// ---------------------------------------------------------------------------

class RoutePreferences {
  bool preferNature;
  bool preferCulture;
  bool avoidHills;
  bool avoidTraffic;

  RoutePreferences({
    this.preferNature = false,
    this.preferCulture = false,
    this.avoidHills = false,
    this.avoidTraffic = false,
  });

  Map<String, dynamic> toJson() => {
        'prefer_nature': preferNature,
        'prefer_culture': preferCulture,
        'avoid_hills': avoidHills,
        'avoid_traffic': avoidTraffic,
      };
}

// ---------------------------------------------------------------------------
// Page principale
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  double _targetDistance = 5.0; // km
  bool _isLoading = false;
  MapLibreMapController? _mapController;
  Position? _currentPosition;
  bool _locationError = false;

  // Préférences Phase 2
  final RoutePreferences _preferences = RoutePreferences();

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationError = true);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _locationError = true);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationError = true);
      return;
    }

    final position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = position;
    });

    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          14.0,
        ),
      );
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    if (_currentPosition != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          14.0,
        ),
      );
    }
  }

  Future<void> _generateRoute() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez attendre la localisation GPS.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/api/routes/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'lat': _currentPosition!.latitude,
          'lon': _currentPosition!.longitude,
          'distance_km': _targetDistance,
          'preferences': _preferences.toJson(), // Phase 2 : envoi des filtres
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'downloading') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message']),
                backgroundColor: Colors.blueAccent,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }

        final distanceMeters = data['estimated_distance_m'] ?? 0;
        final geojson = data['geojson'];

        _drawRoute(geojson);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Itinéraire généré : ${(distanceMeters / 1000).toStringAsFixed(2)} km',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Erreur API: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('--- ERREUR API ---');
      debugPrint(e.toString());
      debugPrint('------------------');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _drawRoute(Map<String, dynamic> geojson) async {
    if (_mapController == null) return;

    await _mapController!.clearLines();

    final coordinates = geojson['geometry']['coordinates'] as List;
    final List<LatLng> points = coordinates.map((coord) {
      return LatLng(coord[1], coord[0]); // GeoJSON: [lon, lat] → LatLng: (lat, lon)
    }).toList();

    await _mapController!.addLine(
      LineOptions(
        geometry: points,
        lineColor: '#4CAF50',
        lineWidth: 6.0,
        lineOpacity: 0.8,
      ),
    );

    if (points.isNotEmpty) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(points.first),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Widgets
  // ---------------------------------------------------------------------------

  /// Bouton de filtre toggle avec icône et label.
  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: value ? Colors.white : Colors.grey[700]),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: value,
      onSelected: onChanged,
      selectedColor: Theme.of(context).colorScheme.primary,
      labelStyle: TextStyle(
        color: value ? Colors.white : Colors.grey[800],
        fontSize: 12,
      ),
      showCheckmark: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stride - Balades sur-mesure'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          // --- Carte MapLibre en arrière-plan ---
          Positioned.fill(
            child: MapLibreMap(
              onMapCreated: _onMapCreated,
              styleString: 'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json',
              // Monde dézoomé : on attend la localisation GPS avant de zoomer
              initialCameraPosition: const CameraPosition(
                target: LatLng(20.0, 0.0),
                zoom: 2.0,
              ),
              myLocationEnabled: true,
              myLocationTrackingMode: MyLocationTrackingMode.tracking,
              compassEnabled: true,
            ),
          ),

          // --- Panneau de contrôle en bas ---
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Avertissement GPS
                    if (_locationError)
                      const Text(
                        'Erreur GPS. Impossible de vous localiser.',
                        style: TextStyle(color: Colors.red),
                      ),

                    // Curseur distance
                    Text(
                      'Distance souhaitée : ${_targetDistance.toStringAsFixed(1)} km',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Slider(
                      value: _targetDistance,
                      min: 1.0,
                      max: 20.0,
                      divisions: 38,
                      label: '${_targetDistance.toStringAsFixed(1)} km',
                      onChanged: (value) {
                        setState(() {
                          _targetDistance = value;
                        });
                      },
                    ),

                    const SizedBox(height: 4),

                    // --- Filtres Phase 2 ---
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Préférences',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildFilterChip(
                          label: 'Nature',
                          icon: Icons.park,
                          value: _preferences.preferNature,
                          onChanged: (v) => setState(() => _preferences.preferNature = v),
                        ),
                        _buildFilterChip(
                          label: 'Culture',
                          icon: Icons.museum,
                          value: _preferences.preferCulture,
                          onChanged: (v) => setState(() => _preferences.preferCulture = v),
                        ),
                        _buildFilterChip(
                          label: 'Plat',
                          icon: Icons.terrain,
                          value: _preferences.avoidHills,
                          onChanged: (v) => setState(() => _preferences.avoidHills = v),
                        ),
                        _buildFilterChip(
                          label: 'Calme',
                          icon: Icons.volume_off,
                          value: _preferences.avoidTraffic,
                          onChanged: (v) => setState(() => _preferences.avoidTraffic = v),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Bouton de génération
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _generateRoute,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.map),
                        label: Text(
                          _isLoading ? 'Génération...' : 'Générer mon parcours',
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
