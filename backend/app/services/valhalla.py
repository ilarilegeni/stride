import requests
import json
import math
from datetime import datetime

from app.core.config import settings
from app.models.route import RoutePreferences


def _build_costing_options(preferences: RoutePreferences) -> dict:
    """
    Construit les options de 'costing' Valhalla en fonction des préférences utilisateur.
    Le costing 'pedestrian' de Valhalla accepte plusieurs paramètres de pénalisation.
    Voir : https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/#pedestrian-costing-options
    """
    options = {
        # Base : on préfère toujours les trottoirs et sentiers piétons
        "use_ferry": 0.0,
        "use_living_streets": 0.5,
        "use_tracks": 0.5,
    }

    # --- Module Anti-Dénivelé ---
    # use_hills : 0 = évite totalement les pentes, 0.5 = neutre, 1 = cherche les pentes
    if preferences.avoid_hills:
        options["use_hills"] = 0.1  # Forte pénalisation des pentes

    # --- Module Nature ---
    # Valhalla n'a pas de "park_bonus" natif, mais on peut augmenter l'usage des
    # "living streets" et pistes cyclables/piétonnes qui longent souvent les parcs.
    # Le vrai filtrage par tags OSM nécessiterait un custom costing (Phase 3).
    if preferences.prefer_nature:
        options["use_living_streets"] = 1.0  # Forte préférence pour les voies calmes
        options["use_tracks"] = 0.9          # Préférence pour les sentiers

    # --- Module Anti-Affluence (heuristique horaire) ---
    # Pénalise les rues principales si on est en heure de pointe (8h-10h, 17h-19h)
    if preferences.avoid_traffic:
        current_hour = datetime.now().hour
        is_rush_hour = (8 <= current_hour <= 10) or (17 <= current_hour <= 19)
        if is_rush_hour:
            # street_penalty : coût additionnel en secondes pour traverser une rue principale
            options["street_penalty"] = 120  # 2 minutes de pénalité par rue principale

    return options


def generate_round_trip(
    lat: float,
    lon: float,
    target_distance_m: float,
    preferences: RoutePreferences | None = None
) -> dict:
    """
    Appelle l'API Valhalla locale pour générer un itinéraire circulaire.
    Accepte maintenant des préférences pour le costing dynamique (Phase 2).

    La boucle est simulée avec 4 points de passage géométriquement répartis
    (départ → Nord-Est → Sud-Est → retour départ).
    """
    if preferences is None:
        preferences = RoutePreferences()

    valhalla_url = f"{settings.VALHALLA_URL}/route"

    # Rayon estimé du cercle : circonférence = target_distance_m
    radius_m = target_distance_m / (2 * math.pi)

    # 1 degré de latitude ~= 111,320 mètres (approximation sphérique)
    lat_offset = radius_m / 111320.0
    lon_offset = radius_m / (111320.0 * math.cos(math.radians(lat)))

    locations = [
        {"lat": lat,              "lon": lon},              # Départ
        {"lat": lat + lat_offset, "lon": lon + lon_offset}, # Nord-Est
        {"lat": lat - lat_offset, "lon": lon + lon_offset}, # Sud-Est
        {"lat": lat,              "lon": lon},              # Retour
    ]

    costing_options = _build_costing_options(preferences)

    payload = {
        "locations": locations,
        "costing": "pedestrian",
        "costing_options": {
            "pedestrian": costing_options
        },
        "directions_type": "none"
    }

    try:
        response = requests.post(valhalla_url, data=json.dumps(payload))

        if not response.ok:
            error_data = (
                response.json()
                if "application/json" in response.headers.get("Content-Type", "")
                else {}
            )
            if response.status_code == 400 and error_data.get("error_code") == 171:
                # Valhalla error 171 : "No suitable edges near location" = zone hors carte
                raise ValueError("OUT_OF_BOUNDS")
            raise Exception(f"Valhalla Error ({response.status_code}): {response.text}")

        response.raise_for_status()
        data = response.json()

        from app.utils.polyline import decode_polyline6

        trip = data.get("trip", {})
        legs = trip.get("legs", [])

        all_coordinates = []
        for leg in legs:
            shape = leg.get("shape", "")
            if shape:
                coords = decode_polyline6(shape)
                # Convertir [lat, lon] → [lon, lat] pour respecter le standard GeoJSON
                all_coordinates.extend([[c[1], c[0]] for c in coords])

        return {
            "geojson": {
                "type": "Feature",
                "geometry": {
                    "type": "LineString",
                    "coordinates": all_coordinates
                }
            },
            "estimated_distance_m": trip.get("summary", {}).get("length", 0) * 1000
        }

    except requests.exceptions.RequestException as e:
        raise Exception(f"Erreur lors de la communication avec Valhalla : {e}")
