from fastapi import APIRouter, HTTPException, BackgroundTasks
from app.models.route import RouteRequest, RouteResponse
from app.services.valhalla import generate_round_trip
from app.services.geofabrik import get_region_pbf_url
from app.core.config import settings

router = APIRouter()

def download_and_rebuild_map(pbf_url: str):
    # TODO: Télécharger le PBF dans le dossier partagé et déclencher un script de rebuild.
    # Dans une infrastructure NAS/Docker, on stockerait le fichier dans /custom_files
    # et on demanderait au démon Docker de redémarrer le conteneur Valhalla.
    print(f"[BACKGROUND] Début du téléchargement simulé pour : {pbf_url}")
    # ... logiques de téléchargement ...
    print(f"[BACKGROUND] Terminé. Valhalla nécessitera un redémarrage.")

@router.post("/routes/generate")
def generate_route(request: RouteRequest, background_tasks: BackgroundTasks):
    if not request.steps and not request.distance_km:
        raise HTTPException(status_code=400, detail="Vous devez fournir 'steps' ou 'distance_km'")

    if request.steps:
        target_distance_m = request.steps * settings.STEPS_TO_METERS_RATIO
    else:
        target_distance_m = request.distance_km * 1000

    try:
        route_data = generate_round_trip(
            lat=request.lat,
            lon=request.lon,
            target_distance_m=target_distance_m
        )
        return route_data
    except ValueError as ve:
        if str(ve) == "OUT_OF_BOUNDS":
            # La zone n'est pas connue de Valhalla. On cherche l'URL.
            pbf_url = get_region_pbf_url(request.lat, request.lon)
            if pbf_url:
                background_tasks.add_task(download_and_rebuild_map, pbf_url)
                return {
                    "status": "downloading",
                    "message": f"Nouvelle zone détectée. Téléchargement en arrière-plan démarré ({pbf_url.split('/')[-1]}). Revenez dans quelques minutes.",
                    "geojson": None,
                    "estimated_distance_m": 0
                }
            raise HTTPException(status_code=400, detail="Zone inconnue et impossible de trouver un fichier de carte correspondant.")
        raise HTTPException(status_code=500, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
