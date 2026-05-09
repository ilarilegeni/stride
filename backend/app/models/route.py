from pydantic import BaseModel, Field
from typing import Optional

class RoutePreferences(BaseModel):
    """
    Filtres de personnalisation pour la Phase 2.
    Chaque module peut être activé indépendamment.
    """
    # Module Nature : favorise les parcs, jardins, espaces verts
    prefer_nature: bool = Field(default=False, description="Favoriser les parcs et zones vertes (leisure=park, landuse=grass)")

    # Module Culture : passe par des monuments et points de vue
    prefer_culture: bool = Field(default=False, description="Passer près de monuments et points d'intérêt culturels")

    # Module Anti-Dénivelé : évite les pentes fortes
    avoid_hills: bool = Field(default=False, description="Éviter les montées et descentes importantes (pentes > 5%)")

    # Module Anti-Affluence : évite les rues passantes aux heures de pointe
    avoid_traffic: bool = Field(default=False, description="Éviter les rues principales aux heures de pointe")


class RouteRequest(BaseModel):
    lat: float = Field(..., description="Latitude de départ")
    lon: float = Field(..., description="Longitude de départ")
    steps: Optional[int] = Field(default=None, description="Nombre de pas souhaités")
    distance_km: Optional[float] = Field(default=None, description="Distance souhaitée en kilomètres")
    preferences: RoutePreferences = Field(
        default_factory=RoutePreferences,
        description="Préférences de personnalisation de l'itinéraire"
    )


class RouteResponse(BaseModel):
    geojson: dict = Field(..., description="Le tracé de la route au format GeoJSON")
    estimated_distance_m: float = Field(..., description="Distance estimée en mètres")
