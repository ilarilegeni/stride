import requests
import json
import math
import random
from datetime import datetime
from typing import List, Optional

from app.core.config import settings
from app.models.route import RoutePreferences, Waypoint

# Correspondance type de manœuvre Valhalla → libellé court pour le frontend
_MANEUVER_LABELS = {
    1: "Départ", 2: "Départ (droite)", 3: "Départ (gauche)",
    4: "Arrivée", 5: "Arrivée (droite)", 6: "Arrivée (gauche)",
    7: "Continuer", 8: "Continuer tout droit",
    9: "Légèrement à droite", 10: "Tourner à droite", 11: "Virage serré à droite",
    12: "Demi-tour droite", 13: "Demi-tour gauche",
    14: "Virage serré à gauche", 15: "Tourner à gauche", 16: "Légèrement à gauche",
}


def _build_costing_options(preferences: RoutePreferences) -> dict:
    """
    Construit les options de costing Valhalla selon les préférences utilisateur.
    Voir : https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/#pedestrian-costing-options
    """
    options: dict = {
        "use_ferry": 0.0,
        "use_living_streets": 0.5,
        "use_tracks": 0.5,
    }
    if preferences.avoid_hills:
        options["use_hills"] = 0.1

    if preferences.prefer_nature:
        options["use_living_streets"] = 1.0
        options["use_tracks"] = 0.9

    if preferences.avoid_traffic:
        hour = datetime.now().hour
        if (8 <= hour <= 10) or (17 <= hour <= 19):
            options["street_penalty"] = 120

    if preferences.avoid_private:
        # Décourage fortement les pistes non balisées, voies de service et accès privés
        # use_tracks=0 : évite les chemins de terre / sentiers non officiels
        # service_penalty élevé : pénalise les voies de service (driveways, impasses privées)
        # service_road_factor faible : fait préférer les routes publiques aux routes de service
        # max_hiking_difficulty=0 : ne prend que les chemins faciles / balisés
        options["use_tracks"] = 0.0
        options["service_penalty"] = 300
        options["service_road_factor"] = 0.1
        options["max_hiking_difficulty"] = 0

    return options


def _random_loop_waypoints(lat: float, lon: float, radius_m: float) -> list[dict]:
    """
    Génère 2 waypoints géométriques à angle aléatoire → chaque route est unique.
    Les deux waypoints sont séparés de ~120° pour une boucle équilibrée.
    """
    lat_scale = 1.0 / 111320.0
    lon_scale = 1.0 / (111320.0 * math.cos(math.radians(lat)))
    base_angle = random.uniform(0, 2 * math.pi)
    return [
        {
            "lat": lat + radius_m * math.sin(base_angle) * lat_scale,
            "lon": lon + radius_m * math.cos(base_angle) * lon_scale,
        },
        {
            "lat": lat + radius_m * math.sin(base_angle + 2 * math.pi / 3) * lat_scale,
            "lon": lon + radius_m * math.cos(base_angle + 2 * math.pi / 3) * lon_scale,
        },
    ]


def _parse_maneuvers(legs: list) -> list[dict]:
    """Extrait les manœuvres de toutes les jambes du trajet Valhalla."""
    maneuvers = []
    for leg in legs:
        for m in leg.get("maneuvers", []):
            mtype = m.get("type", 0)
            streets = m.get("street_names", [])
            maneuvers.append({
                "type": mtype,
                "label": _MANEUVER_LABELS.get(mtype, "Continuer"),
                "instruction": m.get("instruction", ""),
                "street": streets[0] if streets else "",
                "length_m": round(m.get("length", 0) * 1000),
                "time_s": m.get("time", 0),
            })
    return maneuvers


def generate_round_trip(
    lat: float,
    lon: float,
    target_distance_m: float,
    preferences: Optional[RoutePreferences] = None,
    waypoints: Optional[List[Waypoint]] = None,
) -> dict:
    """
    Génère un itinéraire circulaire via Valhalla.
    Retourne le GeoJSON, la distance estimée et les manœuvres pas-à-pas.
    """
    if preferences is None:
        preferences = RoutePreferences()
    if waypoints is None:
        waypoints = []

    valhalla_url = f"{settings.VALHALLA_URL}/route"
    radius_m = target_distance_m / (2 * math.pi)
    geo_waypoints = _random_loop_waypoints(lat, lon, radius_m)

    locations = (
        [{"lat": lat, "lon": lon}]
        + [{"lat": wp.lat, "lon": wp.lon} for wp in waypoints]
        + geo_waypoints
        + [{"lat": lat, "lon": lon}]
    )

    payload = {
        "locations": locations,
        "costing": "pedestrian",
        "costing_options": {"pedestrian": _build_costing_options(preferences)},
        # "maneuvers" : on récupère les instructions pas-à-pas
        "directions_type": "maneuvers",
        "directions_options": {"language": "fr-FR"},
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
                raise ValueError("OUT_OF_BOUNDS")
            raise Exception(f"Valhalla Error ({response.status_code}): {response.text}")

        data = response.json()
        from app.utils.polyline import decode_polyline6

        trip = data.get("trip", {})
        legs = trip.get("legs", [])

        all_coordinates = []
        for leg in legs:
            shape = leg.get("shape", "")
            if shape:
                coords = decode_polyline6(shape)
                all_coordinates.extend([[c[1], c[0]] for c in coords])

        return {
            "geojson": {
                "type": "Feature",
                "geometry": {"type": "LineString", "coordinates": all_coordinates},
            },
            "estimated_distance_m": trip.get("summary", {}).get("length", 0) * 1000,
            "estimated_time_s": trip.get("summary", {}).get("time", 0),
            "maneuvers": _parse_maneuvers(legs),
        }

    except requests.exceptions.RequestException as e:
        raise Exception(f"Erreur de communication avec Valhalla : {e}")
