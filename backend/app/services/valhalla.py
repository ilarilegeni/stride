import requests
import json
from app.core.config import settings

import math

def generate_round_trip(lat: float, lon: float, target_distance_m: float) -> dict:
    """
    Appelle l'API Valhalla locale pour générer un itinéraire circulaire.
    Comme Valhalla ne supporte pas nativement le round_trip, on simule une boucle
    avec des points de passages calculés géométriquement.
    """
    valhalla_url = f"{settings.VALHALLA_URL}/route"
    
    # Rayon estimé du cercle pour correspondre à la circonférence = target_distance_m
    radius_m = target_distance_m / (2 * math.pi)
    
    # Approximation grossière : 1 degré de latitude ~= 111,320 mètres
    # 1 degré de longitude ~= 111,320 * cos(lat) mètres
    lat_offset = radius_m / 111320.0
    lon_offset = radius_m / (111320.0 * math.cos(math.radians(lat)))
    
    # On crée 3 points pour forcer Valhalla à faire une boucle
    # Point 1 : Départ
    # Point 2 : Nord-Est
    # Point 3 : Sud-Est
    # Point 4 : Retour au départ
    locations = [
        {"lat": lat, "lon": lon},
        {"lat": lat + lat_offset, "lon": lon + lon_offset},
        {"lat": lat - lat_offset, "lon": lon + lon_offset},
        {"lat": lat, "lon": lon}
    ]
    
    payload = {
        "locations": locations,
        "costing": "pedestrian",
        "directions_type": "none"
    }
    
    try:
        response = requests.post(valhalla_url, data=json.dumps(payload))
        if not response.ok:
            error_data = response.json() if "application/json" in response.headers.get("Content-Type", "") else {}
            if response.status_code == 400 and error_data.get("error_code") == 171:
                # Error 171: No suitable edges near location
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
                # Convertir [lat, lon] en [lon, lat] pour le standard GeoJSON
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
