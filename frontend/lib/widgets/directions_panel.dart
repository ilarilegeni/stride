import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/preferences.dart';

/// Icône selon le type de manœuvre Valhalla.
IconData _maneuverIcon(int type) => switch (type) {
      1 || 2 || 3 => Icons.play_arrow,           // Départ
      4 || 5 || 6 => Icons.flag,                  // Arrivée
      8 => Icons.straight,                         // Tout droit
      9 => Icons.turn_slight_right,
      10 => Icons.turn_right,
      11 => Icons.turn_sharp_right,                // Virage serré droite
      12 || 13 => Icons.u_turn_right,              // Demi-tour
      14 => Icons.turn_sharp_left,
      15 => Icons.turn_left,
      16 => Icons.turn_slight_left,
      _ => Icons.navigation,
    };

/// Formate une durée en secondes en texte lisible.
String _formatTime(int seconds) {
  final m = seconds ~/ 60;
  if (m < 60) return '$m min';
  return '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
}

/// Panneau de directions pas-à-pas affiché en bottom sheet.
/// Reçoit les [maneuvers] du backend Valhalla, la distance et le temps estimés.
class DirectionsPanel extends StatelessWidget {
  final List<dynamic> maneuvers;
  final double distanceM;
  final int timeS;
  final double? startLat;
  final double? startLon;
  final List<WaypointModel> waypoints;

  const DirectionsPanel({
    super.key,
    required this.maneuvers,
    required this.distanceM,
    required this.timeS,
    this.startLat,
    this.startLon,
    required this.waypoints,
  });

  Future<void> _exportToMaps(BuildContext context) async {
    if (startLat == null || startLon == null) return;
    final lat = startLat!;
    final lon = startLon!;

    // Waypoints utilisateur comme étapes intermédiaires
    final wps = waypoints.map((w) => '${w.lat},${w.lon}').join('|');

    // Google Maps (fonctionne sur Android, iOS si installé, et navigateur web)
    final googleUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=$lat,$lon'
      '&destination=$lat,$lon'
      '${wps.isNotEmpty ? "&waypoints=$wps" : ""}'
      '&travelmode=walking',
    );

    if (await canLaunchUrl(googleUri)) {
      await launchUrl(googleUri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir l\'application de cartes.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final km = (distanceM / 1000).toStringAsFixed(2);

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.15,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12)],
        ),
        child: Column(
          children: [
            // Poignée
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Colors.grey[300], borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(height: 12),

            // En-tête : stats + bouton export
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(Icons.directions_walk, color: color, size: 28),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$km km · ${_formatTime(timeS)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text('${maneuvers.length} étapes', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ]),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _exportToMaps(context),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Maps'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ]),
            ),
            const Divider(height: 20),

            // Liste des étapes
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: maneuvers.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                itemBuilder: (_, i) {
                  final m = maneuvers[i] as Map<String, dynamic>;
                  final type = m['type'] as int? ?? 0;
                  final instruction = m['instruction'] as String? ?? '';
                  final lengthM = m['length_m'] as int? ?? 0;
                  final timeStep = m['time_s'] as int? ?? 0;
                  final isFirst = i == 0;
                  final isLast = type == 4 || type == 5 || type == 6;

                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: isFirst || isLast ? color : Colors.grey[200],
                      child: Icon(
                        _maneuverIcon(type),
                        size: 18,
                        color: isFirst || isLast ? Colors.white : Colors.grey[700],
                      ),
                    ),
                    title: Text(instruction, style: const TextStyle(fontSize: 13)),
                    trailing: lengthM > 0
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                lengthM >= 1000
                                    ? '${(lengthM / 1000).toStringAsFixed(1)} km'
                                    : '$lengthM m',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              Text(_formatTime(timeStep),
                                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                            ],
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
