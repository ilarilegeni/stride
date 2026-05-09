import requests

GEOFABRIK_INDEX_URL = "https://download.geofabrik.de/index-v1.json"

def get_region_pbf_url(lat: float, lon: float) -> str | None:
    """
    Trouve l'URL du fichier PBF le plus précis pour des coordonnées données.
    """
    try:
        response = requests.get(GEOFABRIK_INDEX_URL)
        response.raise_for_status()
        data = response.json()
        
        best_match = None
        min_area = float('inf')
        
        for feature in data.get("features", []):
            props = feature.get("properties", {})
            urls = props.get("urls", {})
            pbf_url = urls.get("pbf")
            
            if not pbf_url:
                continue
                
            # Extraire la bounding box
            # GeoJSON BBox: [minLon, minLat, maxLon, maxLat]
            bbox = feature.get("bbox")
            if not bbox or len(bbox) != 4:
                continue
                
            min_lon, min_lat, max_lon, max_lat = bbox
            
            # Vérifier si (lat, lon) est dans la bounding box
            if min_lat <= lat <= max_lat and min_lon <= lon <= max_lon:
                # Calculer la "surface" de la bbox pour prendre la région la plus spécifique (la plus petite)
                area = (max_lat - min_lat) * (max_lon - min_lon)
                if area < min_area:
                    min_area = area
                    best_match = pbf_url
                    
        return best_match
    except Exception as e:
        print(f"Erreur lors de la recherche Geofabrik: {e}")
        return None
