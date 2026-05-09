# Architecture du Projet Stride

Ce document est destiné aux intelligences artificielles ou développeurs qui seront amenés à travailler sur ce projet. Il décrit la structure, les choix techniques et les conventions à respecter.

## Structure globale

Le projet est divisé en deux grandes parties : `backend` (API + Data) et `frontend` (App Mobile). L'ensemble des services backend est pensé pour être exécuté via Docker.

```
stride/
├── AI_ARCHITECTURE.md      # Ce document
├── README.md               # Documentation pour les humains (Setup, usage)
├── plans.md                # Le plan original du projet (Roadmap, Features)
├── docker-compose.yml      # Orchestration des services (Backend, DB, Valhalla)
│
├── backend/                # API FastAPI (Python)
│   ├── main.py             # Point d'entrée de l'API
│   ├── requirements.txt    # Dépendances Python
│   ├── app/                # Code source de l'API
│   │   ├── api/            # Routes (Endpoints)
│   │   ├── core/           # Configuration, Sécurité
│   │   ├── services/       # Logique métier (Appels Valhalla, conversion)
│   │   ├── models/         # Modèles Pydantic (Entrées/Sorties API)
│   │   └── utils/          # Fonctions utilitaires
│   └── tests/              # Tests unitaires
│
└── frontend/               # Application Mobile (Flutter)
    └── (Structure standard Flutter)
```

## Règles de développement

1. **Fichiers courts** : Aucun fichier ne doit dépasser 300 lignes. Si c'est le cas, il faut refactoriser et diviser les responsabilités.
2. **Maintenabilité** : Code clair, bien nommé et avec des docstrings/commentaires pertinents.
3. **Séparation des préoccupations (Backend)** :
   - Les **routes (`api/`)** ne doivent contenir que la logique HTTP (requête/réponse).
   - La **logique métier (`services/`)** gère les calculs complexes (conversion de pas en mètres, construction des requêtes Valhalla).
4. **Valhalla** : Le moteur de routing tourne en local. L'API FastAPI sert de proxy intelligent pour générer les requêtes de routing (costing dynamique) basées sur les paramètres de l'utilisateur.

## Flux de données principal
1. Le **Frontend** envoie une requête POST `api/routes/generate` avec `{ steps: 5000, lat: 48.8, lon: 2.3 }`.
2. Le **Backend (Service)** :
   - Convertit les pas en distance (~0.75m/pas).
   - Construit la configuration "costing" de Valhalla.
3. Le **Backend** fait un call HTTP interne au container **Valhalla**.
4. Le **Backend** renvoie le GeoJSON au **Frontend**.
5. Le **Frontend** affiche le résultat sur MapLibre.

## Choix techniques
- **Backend** : FastAPI (Python 3.10+)
- **Frontend** : Flutter
- **Routing** : Valhalla (Docker)
- **Base de données** : (Phase ultérieure) PostgreSQL + PostGIS pour gérer les points d'intérêts.
