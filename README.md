# Stride - Application de Balades Optimisées

Stride est une application mobile permettant de générer des boucles de marche sur-mesure basées sur des objectifs physiques (pas, distance) et des préférences environnementales.

## Technologies
- **Frontend** : Flutter
- **Backend** : FastAPI (Python)
- **Moteur de routage** : Valhalla
- **Infrastructure** : Docker Compose (pensé pour NAS)

## Architecture
Veuillez vous référer au fichier `AI_ARCHITECTURE.md` pour une vue détaillée de l'organisation du projet.

## Prérequis
- Docker & Docker Compose
- Python 3.10+
- Flutter SDK

## Installation & Démarrage

### 1. Démarrer l'infrastructure avec Docker (Méthode Recommandée)
Cette commande va lancer le moteur Valhalla ET l'API FastAPI en même temps. 
*(L'API s'exécutera dans un conteneur Linux avec Python 3.11, ce qui évite les erreurs d'installation sur Windows).*
```bash
docker compose up --build -d
```
L'API sera accessible sur `http://localhost:8000`.

### 2. (Alternative) Démarrer l'API FastAPI manuellement
*Attention : Ne faites ceci que si vous voulez développer hors de Docker. Vous devez posséder Python 3.10, 3.11 ou 3.12. Sur des versions plus récentes (comme Python 3.14), l'installation de `pydantic` échouera.*
```bash
cd backend
python -m venv venv
source venv/bin/activate  # ou `venv\Scripts\activate` sur Windows
pip install -r requirements.txt
uvicorn main:app --reload
```

### 3. Démarrer l'application mobile
```bash
cd frontend
flutter pub get
flutter run
```
*(Note: l'application nécessite le lancement préalable du backend).*
