from fastapi import APIRouter, HTTPException, BackgroundTasks
from app.models.route import RouteRequest, RouteResponse
from app.services.valhalla import generate_round_trip
from app.services.geofabrik import get_region_pbf_url
from app.core.config import settings

router = APIRouter()


def download_and_rebuild_map(pbf_url: str):
    """
    Tâche de fond : télécharge un fichier PBF Geofabrik et demande à Valhalla
    de reconstruire ses tuiles (implémentation réelle : Phase 3 / infra NAS).
    """
    print(f"[BACKGROUND] Début du téléchargement simulé pour : {pbf_url}")
    # TODO: Télécharger le PBF dans /custom_files (volume Docker partagé)
    # et déclencher un restart du conteneur Valhalla.
    print(f"[BACKGROUND] Terminé. Valhalla nécessitera un redémarrage.")


@router.post("/routes/generate")
def generate_route(request: RouteRequest, background_tasks: BackgroundTasks):
    """
    Endpoint principal de génération d'itinéraire.

    Accepte une distance (km) ou un nombre de pas, ainsi que des préférences
    de personnalisation (Phase 2 : nature, culture, anti-dénivelé, anti-affluence).
    """
    if not request.steps and not request.distance_km:
        raise HTTPException(
            status_code=400,
            detail="Vous devez fournir 'steps' ou 'distance_km'"
        )

    if request.steps:
        target_distance_m = request.steps * settings.STEPS_TO_METERS_RATIO
    else:
        target_distance_m = request.distance_km * 1000

    try:
        route_data = generate_round_trip(
            lat=request.lat,
            lon=request.lon,
            target_distance_m=target_distance_m,
            preferences=request.preferences,  # Passage des préférences Phase 2
        )
        return route_data

    except ValueError as ve:
        if str(ve) == "OUT_OF_BOUNDS":
            # La zone n'est pas dans les tuiles Valhalla actuelles.
            # On cherche le bon fichier PBF sur Geofabrik et on lance le téléchargement.
            pbf_url = get_region_pbf_url(request.lat, request.lon)
            if pbf_url:
                background_tasks.add_task(download_and_rebuild_map, pbf_url)
                return {
                    "status": "downloading",
                    "message": (
                        f"Nouvelle zone détectée. Téléchargement en arrière-plan démarré "
                        f"({pbf_url.split('/')[-1]}). Revenez dans quelques minutes."
                    ),
                    "geojson": None,
                    "estimated_distance_m": 0
                }
            raise HTTPException(
                status_code=400,
                detail="Zone inconnue et impossible de trouver un fichier de carte correspondant."
            )
        raise HTTPException(status_code=500, detail=str(ve))

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
