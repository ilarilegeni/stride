from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.routes import router

app = FastAPI(
    title="Stride API",
    description="API for the Stride app to generate optimized walking routes.",
    version="1.0.0"
)

# Configuration CORS pour autoriser l'application Flutter (Web/Desktop) à faire des requêtes
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # En développement, on autorise toutes les origines
    allow_credentials=True,
    allow_methods=["*"], # Autorise POST, GET, OPTIONS, etc.
    allow_headers=["*"],
)

app.include_router(router, prefix="/api")

@app.get("/")
def read_root():
    return {"message": "Welcome to Stride API"}
