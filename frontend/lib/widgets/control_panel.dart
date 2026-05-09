import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../models/preferences.dart';
import '../services/api_service.dart';
import 'waypoint_search.dart';

/// Panneau de contrôle bas de l'écran.
/// Gère : unité de mesure, points de passage, filtres, et déclenchement de la génération.
class ControlPanel extends StatefulWidget {
  final Position? currentPosition;
  final bool isLoading;
  final ValueChanged<Map<String, dynamic>> onRouteGenerated;
  final ValueChanged<WaypointModel> onWaypointMarkerAdded;
  final ValueChanged<String> onWaypointMarkerRemoved;
  final ValueChanged<String> onError;
  final VoidCallback onLoadingStart;
  final VoidCallback onLoadingEnd;

  const ControlPanel({
    super.key,
    required this.currentPosition,
    required this.isLoading,
    required this.onRouteGenerated,
    required this.onWaypointMarkerAdded,
    required this.onWaypointMarkerRemoved,
    required this.onError,
    required this.onLoadingStart,
    required this.onLoadingEnd,
  });

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  DistanceUnit _unit = DistanceUnit.kilometers;
  double _value = 5.0; // km par défaut
  final _preferences = RoutePreferences();
  final _userProfile = UserProfile();
  final List<WaypointModel> _waypoints = [];

  // Plages selon l'unité
  double get _min => switch (_unit) {
        DistanceUnit.steps => 1000,
        DistanceUnit.kilometers => 1.0,
        DistanceUnit.time => 5.0,
      };
  double get _max => switch (_unit) {
        DistanceUnit.steps => 30000,
        DistanceUnit.kilometers => 20.0,
        DistanceUnit.time => 120.0,
      };
  int get _divisions => switch (_unit) {
        DistanceUnit.steps => 29,
        DistanceUnit.kilometers => 38,
        DistanceUnit.time => 23,
      };
  String get _label => switch (_unit) {
        DistanceUnit.steps => '${_value.round()} pas',
        DistanceUnit.kilometers => '${_value.toStringAsFixed(1)} km',
        DistanceUnit.time => '${_value.round()} min',
      };

  void _changeUnit(DistanceUnit unit) {
    setState(() {
      _unit = unit;
      _value = switch (unit) {
        DistanceUnit.steps => 6500,
        DistanceUnit.kilometers => 5.0,
        DistanceUnit.time => 45.0,
      };
    });
  }

  void _addWaypoint(WaypointModel wp) {
    setState(() => _waypoints.add(wp));
    widget.onWaypointMarkerAdded(wp);
  }

  void _removeWaypoint(WaypointModel wp) {
    setState(() => _waypoints.removeWhere((w) => w.id == wp.id));
    widget.onWaypointMarkerRemoved(wp.id);
  }

  Future<void> _showCalibrationDialog() async {
    final heightController = TextEditingController(
      text: _userProfile.heightCm?.toStringAsFixed(0) ?? '',
    );
    final stepController = TextEditingController(
      text: _userProfile.customStepLengthM?.toStringAsFixed(2) ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Calibrer mes pas'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: heightController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Ma taille (cm)',
                  suffixText: 'cm',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final h = double.tryParse(v);
                  setDialogState(() => _userProfile.heightCm = h);
                },
              ),
              const SizedBox(height: 8),
              if (_userProfile.heightCm != null)
                Text('→ Longueur estimée : ${_userProfile.stepLengthDisplay}',
                    style: const TextStyle(color: Colors.green, fontSize: 13)),
              const Divider(height: 24),
              TextField(
                controller: stepController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Personnaliser (m/pas)',
                  suffixText: 'm',
                  border: OutlineInputBorder(),
                  helperText: 'Laissez vide pour calculer depuis la taille',
                ),
                onChanged: (v) => _userProfile.customStepLengthM = double.tryParse(v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () { setState(() {}); Navigator.pop(ctx); },
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    if (widget.currentPosition == null) {
      widget.onError('Veuillez attendre la localisation GPS.');
      return;
    }
    widget.onLoadingStart();
    try {
      final data = await ApiService.generateRoute(
        lat: widget.currentPosition!.latitude,
        lon: widget.currentPosition!.longitude,
        unit: _unit,
        value: _value,
        userProfile: _userProfile,
        preferences: _preferences,
        waypoints: _waypoints,
      );
      widget.onRouteGenerated(data);
    } catch (e) {
      widget.onError(e.toString());
    } finally {
      widget.onLoadingEnd();
    }
  }

  Widget _filterChip(String label, IconData icon, bool value, ValueChanged<bool> onChange) {
    final color = Theme.of(context).colorScheme.primary;
    return FilterChip(
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: value ? Colors.white : Colors.grey[700]),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]),
      selected: value,
      onSelected: onChange,
      selectedColor: color,
      labelStyle: TextStyle(color: value ? Colors.white : Colors.grey[800]),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Points de passage ---
            Row(children: [
              Icon(Icons.route, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text('Points de passage', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            WaypointSearch(onWaypointSelected: _addWaypoint),
            if (_waypoints.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _waypoints.map((wp) => Chip(
                  label: Text(wp.name, style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => _removeWaypoint(wp),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                )).toList(),
              ),
            ],

            const Divider(height: 20),

            // --- Sélecteur d'unité ---
            Row(children: [
              Icon(Icons.straighten, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text('Distance cible', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            SegmentedButton<DistanceUnit>(
              segments: const [
                ButtonSegment(value: DistanceUnit.steps, label: Text('Pas'), icon: Icon(Icons.directions_walk, size: 16)),
                ButtonSegment(value: DistanceUnit.kilometers, label: Text('km'), icon: Icon(Icons.place, size: 16)),
                ButtonSegment(value: DistanceUnit.time, label: Text('Temps'), icon: Icon(Icons.timer, size: 16)),
              ],
              selected: {_unit},
              onSelectionChanged: (s) => _changeUnit(s.first),
              style: ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Slider(
                value: _value.clamp(_min, _max),
                min: _min, max: _max, divisions: _divisions,
                label: _label,
                onChanged: (v) => setState(() => _value = v),
              )),
              Text(_label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            if (_unit == DistanceUnit.steps)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showCalibrationDialog,
                  icon: const Icon(Icons.tune, size: 14),
                  label: Text('Calibrer (${_userProfile.stepLengthDisplay})', style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
              ),

            const Divider(height: 16),

            // --- Filtres ---
            Row(children: [
              Icon(Icons.tune, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text('Ambiance', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _filterChip('Nature', Icons.park, _preferences.preferNature, (v) => setState(() => _preferences.preferNature = v)),
              _filterChip('Culture', Icons.museum, _preferences.preferCulture, (v) => setState(() => _preferences.preferCulture = v)),
              _filterChip('Plat', Icons.terrain, _preferences.avoidHills, (v) => setState(() => _preferences.avoidHills = v)),
              _filterChip('Calme', Icons.volume_off, _preferences.avoidTraffic, (v) => setState(() => _preferences.avoidTraffic = v)),
            ]),

            const SizedBox(height: 12),

            // --- Bouton générer ---
            FilledButton.icon(
              onPressed: widget.isLoading ? null : _generate,
              icon: widget.isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.map),
              label: Text(widget.isLoading ? 'Génération...' : 'Générer mon parcours', style: const TextStyle(fontSize: 15)),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
