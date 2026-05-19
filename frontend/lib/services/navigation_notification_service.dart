import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

/// Service de notifications de navigation persistantes (écran verrouillé).
/// Affiche une notification foreground avec ETA, km restants, et prochain virage.
class NavigationNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _navNotificationId = 42;
  static const String _channelId = 'stride_navigation';
  static const String _channelName = 'Navigation Stride';

  static bool _initialized = false;

  /// Initialise le plugin de notifications (à appeler au démarrage de l'app).
  static Future<void> initialize() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  /// Demande la permission de notification (Android 13+).
  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    return true; // iOS gère ça autrement
  }

  /// Affiche / met à jour la notification de navigation.
  ///
  /// [nextManeuver] : instruction du prochain virage (ex: "Tournez à droite")
  /// [distanceToNextM] : mètres avant le prochain virage
  /// [remainingKm] : kilomètres restants sur le parcours
  /// [etaMinutes] : minutes estimées restantes
  /// [remainingSteps] : nombre de pas restants estimé
  static Future<void> showNavigationNotification({
    required String nextManeuver,
    required int distanceToNextM,
    required double remainingKm,
    required int etaMinutes,
    required int remainingSteps,
  }) async {
    if (!_initialized) await initialize();

    final distText = distanceToNextM >= 1000
        ? '${(distanceToNextM / 1000).toStringAsFixed(1)} km'
        : '$distanceToNextM m';

    final etaText = etaMinutes < 60
        ? 'ETA : $etaMinutes min'
        : 'ETA : ${etaMinutes ~/ 60}h${(etaMinutes % 60).toString().padLeft(2, '0')}';

    final stepsText = remainingSteps > 0 ? ' · ~$remainingSteps pas' : '';
    final kmText = remainingKm.toStringAsFixed(2);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Guidage navigation Stride',
      importance: Importance.low,      // Low = pas de son, pas de pop-up
      priority: Priority.low,
      ongoing: true,                   // Non-dismissible tant que navigation active
      autoCancel: false,
      showWhen: false,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(
        '$etaText$stepsText\n$kmText km restants · Dans $distText : $nextManeuver',
        contentTitle: '🧭 Navigation Stride',
        summaryText: 'En cours',
      ),
    );

    await _plugin.show(
      _navNotificationId,
      '🧭 Dans $distText — $nextManeuver',
      '$etaText · $kmText km restants$stepsText',
      NotificationDetails(android: androidDetails),
    );
  }

  /// Annule la notification de navigation.
  static Future<void> cancelNavigationNotification() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_navNotificationId);
    } catch (e) {
      debugPrint('[NavigationNotification] Erreur annulation: $e');
    }
  }
}
