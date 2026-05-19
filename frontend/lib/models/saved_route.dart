class SavedRoute {
  final String id;
  final String name;
  final DateTime date;
  final double distanceM;
  final int timeS;
  final List<List<double>> coords; // [[lat, lon], ...]
  final List<dynamic> maneuvers;

  SavedRoute({
    required this.id,
    required this.name,
    required this.date,
    required this.distanceM,
    required this.timeS,
    required this.coords,
    required this.maneuvers,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'date': date.toIso8601String(),
    'distanceM': distanceM,
    'timeS': timeS,
    'coords': coords,
    'maneuvers': maneuvers,
  };

  factory SavedRoute.fromJson(Map<String, dynamic> json) => SavedRoute(
    id: json['id'],
    name: json['name'],
    date: DateTime.parse(json['date']),
    distanceM: json['distanceM'].toDouble(),
    timeS: json['timeS'].toInt(),
    coords: (json['coords'] as List).map((e) => [e[0] as double, e[1] as double]).toList(),
    maneuvers: json['maneuvers'] ?? [],
  );
}
