/// Modèles de données partagés entre les widgets du frontend Stride.

// Unité de mesure choisie par l'utilisateur pour la distance cible.
enum DistanceUnit { steps, kilometers, time }

/// Profil de marche de l'utilisateur, utilisé pour calibrer les pas.
class UserProfile {
  /// Taille en cm. Si fournie, calcule automatiquement la longueur d'un pas.
  double? heightCm;

  /// Longueur d'un pas en mètres, saisie manuellement (prioritaire sur la taille).
  double? customStepLengthM;

  /// Vitesse de marche en km/h pour le mode "temps" (défaut : 5 km/h).
  double walkingSpeedKmh;

  UserProfile({
    this.heightCm,
    this.customStepLengthM,
    this.walkingSpeedKmh = 5.0,
  });

  /// Longueur d'un pas effective : personnalisée > calculée depuis taille > défaut 0.75m.
  double get stepLengthM {
    if (customStepLengthM != null) return customStepLengthM!;
    if (heightCm != null) return (heightCm! * 0.415) / 100.0;
    return 0.75;
  }

  String get stepLengthDisplay => '${stepLengthM.toStringAsFixed(2)} m/pas';
}

/// Point de passage explicite demandé par l'utilisateur.
class WaypointModel {
  final String id;
  final double lat;
  final double lon;
  final String name;

  WaypointModel({
    required this.lat,
    required this.lon,
    required this.name,
  }) : id = DateTime.now().microsecondsSinceEpoch.toString();
}

/// Préférences de filtrage de l'itinéraire (modules Phase 2).
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
