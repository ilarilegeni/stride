import 'package:flutter/material.dart';
import '../models/saved_route.dart';
import '../services/storage_service.dart';

class SavedRoutesPage extends StatefulWidget {
  const SavedRoutesPage({super.key});

  @override
  State<SavedRoutesPage> createState() => _SavedRoutesPageState();
}

class _SavedRoutesPageState extends State<SavedRoutesPage> {
  List<SavedRoute> _routes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    final routes = await StorageService.getSavedRoutes();
    setState(() {
      _routes = routes;
      _isLoading = false;
    });
  }

  Future<void> _deleteRoute(String id) async {
    await StorageService.deleteRoute(id);
    _loadRoutes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes balades sauvegardées'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _routes.isEmpty
              ? const Center(child: Text("Aucune balade sauvegardée pour l'instant.", style: TextStyle(fontSize: 16)))
              : ListView.builder(
                  itemCount: _routes.length,
                  itemBuilder: (context, index) {
                    final route = _routes[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: 2,
                      child: ListTile(
                        leading: const Icon(Icons.favorite, color: Colors.pink),
                        title: Text(route.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${(route.distanceM / 1000).toStringAsFixed(2)} km • '
                          '${route.timeS ~/ 60} min\n'
                          'Le ${route.date.day.toString().padLeft(2,'0')}/${route.date.month.toString().padLeft(2,'0')}/${route.date.year}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteRoute(route.id),
                        ),
                        onTap: () {
                          // Renvoie la route à la page précédente
                          Navigator.pop(context, route);
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
