import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/saved_route.dart';

class StorageService {
  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/saved_routes.json');
  }

  static Future<List<SavedRoute>> getSavedRoutes() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List data = jsonDecode(content);
      return data.map((e) => SavedRoute.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveRoute(SavedRoute route) async {
    final routes = await getSavedRoutes();
    routes.add(route);
    final file = await _getFile();
    await file.writeAsString(jsonEncode(routes.map((e) => e.toJson()).toList()));
  }

  static Future<void> deleteRoute(String id) async {
    final routes = await getSavedRoutes();
    routes.removeWhere((r) => r.id == id);
    final file = await _getFile();
    await file.writeAsString(jsonEncode(routes.map((e) => e.toJson()).toList()));
  }
}
