from fastapi import APIRouter, HTTPException, BackgroundTasks, Security
from fastapi.security.api_key import APIKeyHeader
from app.models.route import RouteRequest
from app.services.valhalla import generate_round_trip
from app.services.geofabrik import get_region_pbf_url
from app.core.config import settings

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

def get_api_key(api_key_header: str = Security(api_key_header)):
    if api_key_header == settings.API_KEY:
        return api_key_header
    raise HTTPException(status_code=403, detail="Clé API invalide ou manquante")

router = APIRouter()


def download_and_rebuild_map(pbf_url: str):
    """Tâche de fond : téléchargement PBF + rebuild Valhalla (stub Phase 3)."""
    print(f"[BACKGROUND] Téléchargement simulé : {pbf_url}")
    print("[BACKGROUND] Terminé. Valhalla nécessitera un redémarrage.")


@router.post("/routes/generate")
def generate_route(request: RouteRequest, background_tasks: BackgroundTasks, api_key: str = Security(get_api_key)):
    """
    Génère un itinéraire circulaire.

    Accepte la distance en pas, km, ou minutes.
    Les waypoints utilisateur sont insérés dans la boucle.
    """
    # --- Calcul de la distance cible ---
    if request.steps:
        step_len = request.step_length_m or settings.STEPS_TO_METERS_RATIO
        target_distance_m = request.steps * step_len
    elif request.distance_km:
        target_distance_m = request.distance_km * 1000
    elif request.time_minutes:
        # Utilise la vitesse fournie par le profil utilisateur, sinon la valeur par défaut
        speed_m_per_min = (
            (request.walking_speed_kmh * 1000 / 60)
            if request.walking_speed_kmh
            else settings.WALKING_SPEED_M_PER_MIN
        )
        target_distance_m = request.time_minutes * speed_m_per_min
    else:
        raise HTTPException(
            status_code=400,
            detail="Fournissez 'steps', 'distance_km' ou 'time_minutes'."
        )

    try:
        route_data = generate_round_trip(
            lat=request.lat,
            lon=request.lon,
            target_distance_m=target_distance_m,
            preferences=request.preferences,
            waypoints=request.waypoints,
        )
        return route_data

    except ValueError as ve:
        if str(ve) == "OUT_OF_BOUNDS":
            pbf_url = get_region_pbf_url(request.lat, request.lon)
            if pbf_url:
                background_tasks.add_task(download_and_rebuild_map, pbf_url)
                return {
                    "status": "downloading",
                    "message": (
                        f"Zone inconnue. Téléchargement en cours "
                        f"({pbf_url.split('/')[-1]}). Revenez dans quelques minutes."
                    ),
                    "geojson": None,
                    "estimated_distance_m": 0,
                }
            raise HTTPException(
                status_code=400,
                detail="Zone inconnue et aucun fichier de carte trouvé."
            )
        raise HTTPException(status_code=500, detail=str(ve))

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
