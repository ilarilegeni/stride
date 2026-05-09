/// Modèles de données partagés entre les widgets du frontend Stride.

enum DistanceUnit { steps, kilometers, time }

/// Vitesse estimée selon l'âge (source : études de biomécanique pédestre).
double _speedFromAge(int age) {
  if (age < 20) return 5.5;
  if (age < 40) return 5.2;
  if (age < 60) return 4.8;
  if (age < 70) return 4.2;
  return 3.5;
}

/// Profil de marche de l'utilisateur — sert à calibrer pas et vitesse.
class UserProfile {
  double? heightCm;
  int? ageYears;

  /// Longueur d'un pas saisie manuellement (m). Prioritaire sur la taille.
  double? customStepLengthM;

  /// Vitesse de marche saisie manuellement (km/h). Prioritaire sur l'âge.
  double? customSpeedKmh;

  UserProfile({
    this.heightCm,
    this.ageYears,
    this.customStepLengthM,
    this.customSpeedKmh,
  });

  /// Longueur d'un pas effective : manuelle > taille > défaut 0.75 m.
  double get stepLengthM {
    if (customStepLengthM != null) return customStepLengthM!;
    if (heightCm != null) return (heightCm! * 0.415) / 100.0;
    return 0.75;
  }

  /// Vitesse de marche effective : manuelle > âge > défaut 5.0 km/h.
  double get walkingSpeedKmh {
    if (customSpeedKmh != null) return customSpeedKmh!;
    if (ageYears != null) return _speedFromAge(ageYears!);
    return 5.0;
  }

  /// Vitesse en m/min.
  double get walkingSpeedMPerMin => walkingSpeedKmh * 1000 / 60;

  String get stepLengthDisplay => '${stepLengthM.toStringAsFixed(2)} m/pas';
  String get speedDisplay => '${walkingSpeedKmh.toStringAsFixed(1)} km/h';

  /// Résumé textuel du profil pour affichage dans l'UI.
  String get summary {
    final parts = <String>[];
    if (heightCm != null) parts.add('${heightCm!.toStringAsFixed(0)} cm');
    if (ageYears != null) parts.add('${ageYears!} ans');
    return parts.isEmpty ? 'Non configuré' : parts.join(' · ');
  }
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
  bool avoidPrivate;

  RoutePreferences({
    this.preferNature = false,
    this.preferCulture = false,
    this.avoidHills = false,
    this.avoidTraffic = false,
    this.avoidPrivate = false,
  });

  Map<String, dynamic> toJson() => {
        'prefer_nature': preferNature,
        'prefer_culture': preferCulture,
        'avoid_hills': avoidHills,
        'avoid_traffic': avoidTraffic,
        'avoid_private': avoidPrivate,
      };
}
