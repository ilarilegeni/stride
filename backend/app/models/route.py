from pydantic import BaseModel, Field
from typing import Optional, List


class Waypoint(BaseModel):
    lat: float = Field(..., description="Latitude du point de passage")
    lon: float = Field(..., description="Longitude du point de passage")
    name: Optional[str] = Field(default=None, description="Nom affiché du lieu")


class RoutePreferences(BaseModel):
    """Filtres de personnalisation de l'itinéraire (Phase 2)."""
    prefer_nature: bool = Field(default=False, description="Favoriser les parcs et zones vertes")
    prefer_culture: bool = Field(default=False, description="Passer près de monuments et POI culturels")
    avoid_hills: bool = Field(default=False, description="Éviter les pentes fortes (> 5%)")
    avoid_traffic: bool = Field(default=False, description="Éviter les rues passantes aux heures de pointe")


class RouteRequest(BaseModel):
    lat: float = Field(..., description="Latitude de départ")
    lon: float = Field(..., description="Longitude de départ")

    # --- Modes de saisie de la distance cible (un seul requis) ---
    steps: Optional[int] = Field(default=None, description="Nombre de pas souhaités")
    distance_km: Optional[float] = Field(default=None, description="Distance souhaitée en km")
    time_minutes: Optional[float] = Field(default=None, description="Durée de marche souhaitée en minutes")

    # Longueur d'un pas en mètres (calculée depuis la taille ou saisie manuellement)
    step_length_m: Optional[float] = Field(default=None, description="Longueur d'un pas en mètres")

    # Points de passage explicites
    waypoints: List[Waypoint] = Field(default_factory=list, description="Lieux à inclure dans l'itinéraire")

    preferences: RoutePreferences = Field(
        default_factory=RoutePreferences,
        description="Préférences de personnalisation"
    )


class RouteResponse(BaseModel):
    geojson: dict = Field(..., description="Tracé de la route au format GeoJSON Feature")
    estimated_distance_m: float = Field(..., description="Distance estimée en mètres")
