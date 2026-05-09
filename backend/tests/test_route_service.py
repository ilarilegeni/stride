"""
Tests unitaires pour la logique de conversion et de génération de route.
Ces tests vérifient la logique métier sans appeler Valhalla (mocked).
"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from unittest.mock import patch, MagicMock
from app.core.config import settings


def test_steps_to_meters_ratio():
    """La constante de conversion pas->mètres doit être 0.75."""
    assert settings.STEPS_TO_METERS_RATIO == 0.75


def test_steps_conversion():
    """5000 pas doivent correspondre à 3750 mètres."""
    steps = 5000
    expected_meters = 3750.0
    result = steps * settings.STEPS_TO_METERS_RATIO
    assert result == expected_meters


def test_valhalla_url_default():
    """L'URL Valhalla par défaut doit pointer sur localhost:8002."""
    # En dehors de Docker, la valeur par défaut s'applique
    assert "8002" in settings.VALHALLA_URL or "valhalla" in settings.VALHALLA_URL


def test_generate_round_trip_calls_valhalla():
    """
    Vérifie que generate_round_trip construit bien 4 locations (boucle)
    et appelle Valhalla avec le bon endpoint.
    """
    mock_response = MagicMock()
    mock_response.ok = True
    mock_response.json.return_value = {
        "trip": {
            "legs": [
                {"shape": "_ibE_seK_c@_c@"},
                {"shape": "_c@_c@_ibE_seK"}
            ],
            "summary": {"length": 5.0}
        }
    }

    with patch("app.services.valhalla.requests.post", return_value=mock_response) as mock_post:
        from app.services.valhalla import generate_round_trip
        result = generate_round_trip(lat=48.8566, lon=2.3522, target_distance_m=5000)

        # Valhalla a bien été appelé
        mock_post.assert_called_once()
        call_args = mock_post.call_args

        import json
        payload = json.loads(call_args[1].get("data", call_args[0][1] if len(call_args[0]) > 1 else "{}"))

        # On doit avoir 4 locations (départ + 2 waypoints + retour au départ)
        assert len(payload["locations"]) == 4
        assert payload["costing"] == "pedestrian"

        # Le résultat doit contenir un geojson
        assert "geojson" in result
        assert result["geojson"]["type"] == "Feature"
        assert result["geojson"]["geometry"]["type"] == "LineString"
        assert "estimated_distance_m" in result


def test_generate_round_trip_out_of_bounds():
    """
    Si Valhalla retourne un code 400 avec error_code 171,
    generate_round_trip doit lever ValueError('OUT_OF_BOUNDS').
    """
    mock_response = MagicMock()
    mock_response.ok = False
    mock_response.status_code = 400
    mock_response.headers = {"Content-Type": "application/json"}
    mock_response.json.return_value = {"error_code": 171, "error": "No suitable edges near location"}

    with patch("app.services.valhalla.requests.post", return_value=mock_response):
        from app.services.valhalla import generate_round_trip
        try:
            generate_round_trip(lat=0.0, lon=0.0, target_distance_m=5000)
            assert False, "Devrait lever une ValueError"
        except ValueError as e:
            assert str(e) == "OUT_OF_BOUNDS"
