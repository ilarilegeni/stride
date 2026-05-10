import 'dart:async';
import 'package:flutter/material.dart';
import '../models/preferences.dart';
import '../services/geocoding_service.dart';

/// Champ de recherche de lieu (Nominatim) avec autocomplétion.
/// Appelle [onWaypointSelected] quand l'utilisateur choisit un résultat.
class WaypointSearch extends StatefulWidget {
  final ValueChanged<WaypointModel> onWaypointSelected;
  final String hintText;

  const WaypointSearch({
    super.key,
    required this.onWaypointSelected,
    this.hintText = 'Ajouter un lieu à passer...',
  });

  @override
  State<WaypointSearch> createState() => _WaypointSearchState();
}

class _WaypointSearchState extends State<WaypointSearch> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<GeocodeResult> _results = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.length < 3) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => _isSearching = true);
      final results = await GeocodingService.search(value);
      if (mounted) setState(() { _results = results; _isSearching = false; });
    });
  }

  void _selectResult(GeocodeResult result) {
    widget.onWaypointSelected(WaypointModel(
      lat: result.lat,
      lon: result.lon,
      name: result.shortName,
    ));
    _controller.clear();
    setState(() => _results = []);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: Icon(Icons.search, color: color),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : _controller.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _controller.clear(); setState(() => _results = []); })
                    : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Column(
              children: _results.map((r) => ListTile(
                dense: true,
                leading: Icon(Icons.place, color: color, size: 18),
                title: Text(r.shortName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(r.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                onTap: () => _selectResult(r),
              )).toList(),
            ),
          ),
      ],
    );
  }
}
