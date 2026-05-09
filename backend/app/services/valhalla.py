import requests
import json
import math
from datetime import datetime
from typing import List, Optional

from app.core.config import settings
from app.models.route import RoutePreferences, Waypoint


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
        options["use_hills"] = 0.1  # 0 = évite, 1 = cherche les pentes

    if preferences.prefer_nature:
        options["use_living_streets"] = 1.0
        options["use_tracks"] = 0.9

    if preferences.avoid_traffic:
        hour = datetime.now().hour
        if (8 <= hour <= 10) or (17 <= hour <= 19):
            options["street_penalty"] = 120  # secondes de pénalité par rue principale

    return options


def generate_round_trip(
    lat: float,
    lon: float,
    target_distance_m: float,
    preferences: Optional[RoutePreferences] = None,
    waypoints: Optional[List[Waypoint]] = None,
) -> dict:
    """
    Génère un itinéraire circulaire via Valhalla.

    Les waypoints utilisateur sont insérés entre le départ et les waypoints géométriques,
    afin d'être traversés tout en maintenant la structure de boucle.
    """
    if preferences is None:
        preferences = RoutePreferences()
    if waypoints is None:
        waypoints = []

    valhalla_url = f"{settings.VALHALLA_URL}/route"

    # Waypoints géométriques pour forcer la boucle
    radius_m = target_distance_m / (2 * math.pi)
    lat_offset = radius_m / 111320.0
    lon_offset = radius_m / (111320.0 * math.cos(math.radians(lat)))

    # Construction de la liste de locations :
    # [départ] + [waypoints utilisateur] + [NE géométrique] + [SE géométrique] + [retour départ]
    user_locations = [{"lat": wp.lat, "lon": wp.lon} for wp in waypoints]

    locations = (
        [{"lat": lat, "lon": lon}]
        + user_locations
        + [
            {"lat": lat + lat_offset, "lon": lon + lon_offset},
            {"lat": lat - lat_offset, "lon": lon + lon_offset},
            {"lat": lat, "lon": lon},
        ]
    )

    payload = {
        "locations": locations,
        "costing": "pedestrian",
        "costing_options": {
            "pedestrian": _build_costing_options(preferences)
        },
        "directions_type": "none",
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
        }

    except requests.exceptions.RequestException as e:
        raise Exception(f"Erreur de communication avec Valhalla : {e}")
