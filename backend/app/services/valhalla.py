import requests
import json
import math
import random
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
        options["use_hills"] = 0.1
    if preferences.prefer_nature:
        options["use_living_streets"] = 1.0
        options["use_tracks"] = 0.9
    if preferences.avoid_traffic:
        hour = datetime.now().hour
        if (8 <= hour <= 10) or (17 <= hour <= 19):
            options["street_penalty"] = 120
    return options


def _random_loop_waypoints(
    lat: float, lon: float, radius_m: float
) -> list[dict]:
    """
    Génère 2 waypoints intermédiaires à une position aléatoire autour du départ.

    Chaque appel produit un angle de départ différent → itinéraire unique.
    Les deux waypoints sont séparés de ~120° pour former une boucle équitable.
    """
    lat_scale = 1.0 / 111320.0
    lon_scale = 1.0 / (111320.0 * math.cos(math.radians(lat)))

    # Angle de départ aléatoire : garantit que chaque génération emprunte
    # une direction différente et donc une route différente.
    base_angle = random.uniform(0, 2 * math.pi)
    wp1_angle = base_angle
    wp2_angle = base_angle + (2 * math.pi / 3)  # 120° plus loin

    return [
        {
            "lat": lat + radius_m * math.sin(wp1_angle) * lat_scale,
            "lon": lon + radius_m * math.cos(wp1_angle) * lon_scale,
        },
        {
            "lat": lat + radius_m * math.sin(wp2_angle) * lat_scale,
            "lon": lon + radius_m * math.cos(wp2_angle) * lon_scale,
        },
    ]


def generate_round_trip(
    lat: float,
    lon: float,
    target_distance_m: float,
    preferences: Optional[RoutePreferences] = None,
    waypoints: Optional[List[Waypoint]] = None,
) -> dict:
    """
    Génère un itinéraire circulaire via Valhalla.

    - Les waypoints utilisateur sont insérés après le départ.
    - Deux waypoints géométriques aléatoires complètent la boucle.
    - Chaque appel produit une route différente (angle aléatoire).
    """
    if preferences is None:
        preferences = RoutePreferences()
    if waypoints is None:
        waypoints = []

    valhalla_url = f"{settings.VALHALLA_URL}/route"

    radius_m = target_distance_m / (2 * math.pi)

    # Waypoints géométriques avec angle aléatoire → route toujours différente
    geo_waypoints = _random_loop_waypoints(lat, lon, radius_m)

    # Ordre : départ → waypoints utilisateur → waypoints géo → retour départ
    user_locations = [{"lat": wp.lat, "lon": wp.lon} for wp in waypoints]
    locations = (
        [{"lat": lat, "lon": lon}]
        + user_locations
        + geo_waypoints
        + [{"lat": lat, "lon": lon}]
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
