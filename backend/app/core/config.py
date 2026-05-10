import os

class Settings:
    VALHALLA_URL: str = os.getenv("VALHALLA_URL", "http://localhost:8002")
    API_KEY: str = os.getenv("API_KEY", "stride_default_dev_key")
    STEPS_TO_METERS_RATIO: float = 0.75
    # Vitesse de marche par défaut : 5 km/h = 83.33 m/min
    WALKING_SPEED_M_PER_MIN: float = 83.33

settings = Settings()
