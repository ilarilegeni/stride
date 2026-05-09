# Plan de Développement : Application de Balades Optimisées (Project "Stride")

Ce document définit l'architecture technique, les fonctionnalités et la stratégie d'implémentation pour l'application de génération d'itinéraires de balades personnalisées.

## 1. Vision du Projet
Créer une application mobile permettant de générer des boucles de marche sur-mesure basées sur des objectifs physiques (pas, distance) et des préférences environnementales (parcs, monuments, calme), de manière gratuite et performante.

---

## 2. Architecture Technique

L'architecture est pensée pour être auto-hébergée (NAS) tout en restant extensible.

### A. Stack Technologique
* **Frontend :** Flutter (Multiplateforme iOS/Android, excellent support des cartes).
* **Backend API :** FastAPI (Python) - Rapide, moderne, facile à interfacer avec des outils de données.
* **Moteur de Routage :** **Valhalla** (Open Source) tournant dans un conteneur Docker.
    * *Pourquoi Valhalla ?* Il supporte nativement les "circuits" (boucles), le "costing" dynamique (pénaliser les côtes ou les rues passantes) et tourne bien sur du hardware modeste.
* **Base de Données :** PostgreSQL + PostGIS (pour stocker les POI locaux et les favoris utilisateurs).
* **Données Cartographiques :** OpenStreetMap (Extraits au format `.pbf` via Geofabrik).
* **Reverse Geocoding :** Nominatim (version légère ou via API publique gratuite pour les recherches d'adresses).

### B. Schéma de Flux
1.  **Client (App)** envoie les critères (Distance, Préférences).
2.  **API (FastAPI)** convertit les "pas" en "mètres", récupère l'heure actuelle.
3.  **API** interroge **Valhalla** avec une configuration de "costing" spécifique (ex: poids élevé sur les rues principales le matin).
4.  **Valhalla** calcule le chemin sur le graphe OSM et renvoie le GeoJSON.
5.  **API** enrichit le GeoJSON avec des POI récupérés via une requête spatiale PostGIS (si nécessaire).
6.  **Client** affiche la carte et guide l'utilisateur.

---

## 3. Plan des Features (Roadmap)

### Phase 1 : MVP (Minimum Viable Product)
* **Saisie simplifiée :** Un seul curseur/champ pour la distance (en km) ou le nombre de pas.
* **Génération de boucle :** Calcul d'un itinéraire circulaire partant de la position GPS actuelle.
* **Fond de carte :** Intégration de MapLibre (version open source de Mapbox) avec OSM.
* **Algorithme de base :** Préférence pour les zones piétonnes.

### Phase 2 : Personnalisation & Filtres
* **Module "Nature" :** Augmenter le poids des tags OSM `leisure=park`, `landuse=grass`, `leisure=garden`.
* **Module "Culture" :** Forcer le passage par des nodes `historic=monument` ou `tourism=viewpoint`.
* **Module "Anti-Dénivelé" :** Utilisation des données SRTM (Digital Elevation Model) intégrées à Valhalla pour éviter les pentes > 5%.
* **Heuristiques d'Affluence :** Système de pénalisation des rues `highway=primary/secondary` selon des plages horaires codées en dur (ex: 08h-10h).

### Phase 3 : UX Avancée & Fiabilité
* **Indicateur d'incertitude :** Icône spécifique sur les POI dont les horaires d'ouverture sont inconnus dans OSM.
* **Mode Offline :** Possibilité de télécharger une zone de 10km autour de chez soi.
* **Gestion des impasses :** Message d'alerte si les critères sont trop restrictifs ("Aucun parc trouvé sur 2km, itinéraire alternatif proposé").

---

## 4. Logique Algorithmique & Challenges

### Le calcul de la boucle (The "Round-Trip")
Valhalla utilise une technique d'expansion de graphe. On ne lui donne pas un point B, on lui donne une direction de départ et une longueur. 
* **Implémentation :** L'API enverra une requête `route` avec le type `expansion`. On peut aussi simuler cela en plaçant 2 ou 3 points de passage "fantômes" de manière aléatoire sur un rayon de $Distance/2\pi$.

### Conversion Pas -> Distance
* **Formule :** $Distance (m) = Nombre de pas \times 0.75$.
* *Challenge :* Proposer à l'utilisateur de calibrer sa taille dans les réglages pour plus de précision.

### Système de Pondération (Costing)
C'est ici que se joue la "solidité" du projet. Chaque critère utilisateur modifie le coût de l'arête (segment de route) :
* `street_penalty` : Appliqué si `highway=tertiary` et `hour` $\in$ [08:00, 09:30].
* `park_bonus` : Réduction du coût si le segment longe un polygone `leisure=park`.

---

## 5. Maintenabilité & Scalabilité

### Maintenance des données
* **Update mensuel :** Un script cron sur le NAS pour télécharger le nouveau fichier `.pbf` de la région et reconstruire les tuiles Valhalla (opération de 10-15 min pour une région).
* **Logs d'échec :** Tracker les recherches qui ne retournent aucun itinéraire pour ajuster les seuils de pénalité.

### Auto-hébergement sur NAS
* **Docker-compose :** Tout le système doit tenir dans un fichier `docker-compose.yml` unique (FastAPI + Valhalla + PostGIS).
* **Sécurité :** Utilisation d'un Reverse Proxy (Nginx/Traefik) avec HTTPS pour exposer l'API à l'application mobile.

---
*Document généré pour le projet de balades optimisées - Version 1.0*