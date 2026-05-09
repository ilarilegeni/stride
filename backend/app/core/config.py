import os

class Settings:
    VALHALLA_URL: str = os.getenv("VALHALLA_URL", "http://localhost:8002")
    STEPS_TO_METERS_RATIO: float = 0.75

settings = Settings()
