import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../models/preferences.dart';
import '../services/api_service.dart';
import 'waypoint_search.dart';

/// Panneau de contrôle bas de l'écran.
/// Les [waypoints] et leurs callbacks sont gérés par le parent (HomePage)
/// pour que les taps sur la carte puissent aussi en ajouter.
class ControlPanel extends StatefulWidget {
  final Position? currentPosition;
  final bool isLoading;
  final List<WaypointModel> waypoints;
  final ValueChanged<WaypointModel> onWaypointAdded;
  final ValueChanged<String> onWaypointRemoved;
  final ValueChanged<Map<String, dynamic>> onRouteGenerated;
  final ValueChanged<String> onError;
  final VoidCallback onLoadingStart;
  final VoidCallback onLoadingEnd;
  final bool hasRoute;
  final VoidCallback? onShowDirections;
  final VoidCallback? onExportGpx;
  final VoidCallback? onShowSteps;
  final double routeDistanceM;
  final int routeTimeS;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;

  const ControlPanel({
    super.key,
    required this.currentPosition,
    required this.isLoading,
    required this.waypoints,
    required this.onWaypointAdded,
    required this.onWaypointRemoved,
    required this.onRouteGenerated,
    required this.onError,
    required this.onLoadingStart,
    required this.onLoadingEnd,
    this.hasRoute = false,
    this.onShowDirections,
    this.onExportGpx,
    this.onShowSteps,
    this.routeDistanceM = 0,
    this.routeTimeS = 0,
    this.isCollapsed = false,
    this.onToggleCollapse,
  });

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  DistanceUnit _unit = DistanceUnit.kilometers;
  double _value = 5.0;
  final _preferences = RoutePreferences();
  final _profile = UserProfile();

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

  void _changeUnit(DistanceUnit unit) => setState(() {
        _unit = unit;
        _value = switch (unit) {
          DistanceUnit.steps => 6500,
          DistanceUnit.kilometers => 5.0,
          DistanceUnit.time => 45.0,
        };
      });

  Future<void> _showProfileDialog() async {
    // Contrôleurs pré-remplis depuis le profil existant
    final heightCtrl = TextEditingController(text: _profile.heightCm?.toStringAsFixed(0) ?? '');
    final ageCtrl = TextEditingController(text: _profile.ageYears?.toString() ?? '');
    final stepCtrl = TextEditingController(text: _profile.customStepLengthM?.toStringAsFixed(2) ?? '');
    final speedCtrl = TextEditingController(text: _profile.customSpeedKmh?.toStringAsFixed(1) ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) {
          // Mise à jour live des estimations
          void rebuild() => setDs(() {});

          return AlertDialog(
            title: const Row(children: [
              Icon(Icons.person, size: 22),
              SizedBox(width: 8),
              Text('Mon profil de marche'),
            ]),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Informations physiques', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                const SizedBox(height: 8),
                // Taille
                _dialogField(heightCtrl, 'Taille', 'cm', TextInputType.number, digitsOnly: true, onChanged: (v) {
                  _profile.heightCm = double.tryParse(v);
                  rebuild();
                }),
                const SizedBox(height: 8),
                // Âge
                _dialogField(ageCtrl, 'Âge', 'ans', TextInputType.number, digitsOnly: true, onChanged: (v) {
                  _profile.ageYears = int.tryParse(v);
                  rebuild();
                }),
                const SizedBox(height: 12),
                // Résumé estimations
                if (_profile.heightCm != null || _profile.ageYears != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('✦ Estimations calculées', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.green)),
                      const SizedBox(height: 4),
                      if (_profile.heightCm != null)
                        Text('👣  Longueur de pas : ${_profile.stepLengthDisplay}', style: const TextStyle(fontSize: 12)),
                      if (_profile.ageYears != null && _profile.customSpeedKmh == null)
                        Text('⚡  Vitesse de marche : ${_profile.speedDisplay}', style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Ou personnaliser directement', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                const SizedBox(height: 8),
                // Longueur de pas custom
                _dialogField(stepCtrl, 'Longueur d\'un pas', 'm', const TextInputType.numberWithOptions(decimal: true),
                    helperText: 'Laissez vide pour calculer depuis la taille', onChanged: (v) {
                  _profile.customStepLengthM = double.tryParse(v);
                  rebuild();
                }),
                const SizedBox(height: 8),
                // Vitesse custom
                _dialogField(speedCtrl, 'Vitesse de marche', 'km/h', const TextInputType.numberWithOptions(decimal: true),
                    helperText: 'Laissez vide pour calculer depuis l\'âge', onChanged: (v) {
                  _profile.customSpeedKmh = double.tryParse(v);
                  rebuild();
                }),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(
                onPressed: () { setState(() {}); Navigator.pop(ctx); },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogField(
    TextEditingController ctrl,
    String label,
    String suffix,
    TextInputType keyboardType, {
    bool digitsOnly = false,
    String? helperText,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      inputFormatters: digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: helperText,
        border: const OutlineInputBorder(),
        isDense: true,
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
        userProfile: _profile,
        preferences: _preferences,
        waypoints: widget.waypoints,
      );
      widget.onRouteGenerated(data);
    } catch (e) {
      widget.onError(e.toString());
    } finally {
      widget.onLoadingEnd();
    }
  }

  /// Formate une durée en secondes en texte lisible (ex: "45 min" ou "1h 20min").
  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    if (m < 60) return '$m min';
    return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}min';
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
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Bouton pour réafficher les options quand c'est replié ---
            if (widget.isCollapsed)
              Center(
                child: TextButton.icon(
                  onPressed: widget.onToggleCollapse,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Modifier les paramètres du trajet'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  ),
                ),
              ),

            if (!widget.isCollapsed) ...[
              // --- Points de passage ---
            Row(children: [
              Icon(Icons.route, size: 16, color: color),
              const SizedBox(width: 6),
              Text('Points de passage', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('ou appuyez sur la carte 📍', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
            const SizedBox(height: 6),
            WaypointSearch(onWaypointSelected: widget.onWaypointAdded),
            if (widget.waypoints.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6, runSpacing: 4,
                children: widget.waypoints.map((wp) => Chip(
                  label: Text(wp.name, style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => widget.onWaypointRemoved(wp.id),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                )).toList(),
              ),
            ],

            const Divider(height: 20),

            // --- Sélecteur d'unité ---
            Row(children: [
              Icon(Icons.straighten, size: 16, color: color),
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
            if (_unit == DistanceUnit.steps || _unit == DistanceUnit.time)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showProfileDialog,
                  icon: const Icon(Icons.person_outline, size: 14),
                  label: Text(
                    _profile.summary == 'Non configuré'
                        ? 'Configurer mon profil de marche'
                        : 'Profil : ${_profile.summary}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),

            const Divider(height: 16),

            // --- Filtres ---
            Row(children: [
              Icon(Icons.tune, size: 16, color: color),
              const SizedBox(width: 6),
              Text('Ambiance', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _filterChip('Nature', Icons.park, _preferences.preferNature, (v) => setState(() => _preferences.preferNature = v)),
              _filterChip('Culture', Icons.museum, _preferences.preferCulture, (v) => setState(() => _preferences.preferCulture = v)),
              _filterChip('Plat', Icons.terrain, _preferences.avoidHills, (v) => setState(() => _preferences.avoidHills = v)),
              _filterChip('Calme', Icons.volume_off, _preferences.avoidTraffic, (v) => setState(() => _preferences.avoidTraffic = v)),
              _filterChip('Éviter privés', Icons.lock_outline, _preferences.avoidPrivate, (v) => setState(() => _preferences.avoidPrivate = v)),
            ]),

            const SizedBox(height: 12),
            
            // --- Bouton pour masquer les options si on a un trajet ---
            if (widget.hasRoute)
              Center(
                child: IconButton(
                  icon: const Icon(Icons.expand_more, color: Colors.grey),
                  onPressed: widget.onToggleCollapse,
                  tooltip: 'Masquer les paramètres',
                ),
              ),
            ], // Fin du bloc if (!widget.isCollapsed)

            // Résumé de l'itinéraire généré
            if (widget.hasRoute) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.directions_walk, size: 18, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    '${(widget.routeDistanceM / 1000).toStringAsFixed(2)} km',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.timer_outlined, size: 16, color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(widget.routeTimeS),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: widget.onShowSteps,
                    icon: const Icon(Icons.list_alt, size: 14),
                    label: const Text('Étapes', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
            ],

            // Deux boutons toujours visibles côte à côte :
            // [🗺 Générer / Regénérer]  [🧭 Départ]
            // "Départ" est grisé tant qu'aucun parcours n'a été généré.
            Row(children: [
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: widget.isLoading ? null : _generate,
                  icon: widget.isLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(widget.hasRoute ? Icons.refresh : Icons.map, size: 18),
                  label: Text(
                    widget.isLoading ? 'Génération...' : (widget.hasRoute ? 'Regénérer' : 'Générer'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: widget.hasRoute ? widget.onShowDirections : null,
                  icon: const Icon(Icons.navigation, size: 20),
                  label: const Text('Départ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.hasRoute ? Colors.green[700] : Colors.grey[400],
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.hasRoute)
                Tooltip(
                  message: 'Exporter en GPX',
                  child: IconButton.filledTonal(
                    onPressed: widget.onExportGpx,
                    icon: const Icon(Icons.download),
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(14),
                    ),
                  ),
                ),
              if (!widget.hasRoute)
                IconButton.filledTonal(
                  onPressed: null,
                  icon: const Icon(Icons.download),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}
