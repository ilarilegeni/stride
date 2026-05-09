from pydantic import BaseModel, Field

class RouteRequest(BaseModel):
    lat: float = Field(..., description="Latitude de départ")
    lon: float = Field(..., description="Longitude de départ")
    steps: int | None = Field(default=None, description="Nombre de pas souhaités")
    distance_km: float | None = Field(default=None, description="Distance souhaitée en kilomètres")

class RouteResponse(BaseModel):
    geojson: dict = Field(..., description="Le tracé de la route au format GeoJSON")
    estimated_distance_m: float = Field(..., description="Distance estimée en mètres")
