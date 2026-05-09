"""
Tests unitaires pour le système de costing dynamique (Phase 2).
Vérifie que les préférences utilisateur se traduisent bien en options Valhalla.
"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.models.route import RoutePreferences
from app.services.valhalla import _build_costing_options


def test_default_preferences_no_special_options():
    """Des préférences par défaut (tout désactivé) ne doivent pas forcer use_hills."""
    prefs = RoutePreferences()
    options = _build_costing_options(prefs)
    # use_hills ne doit pas être fixé à une valeur basse par défaut
    assert options.get("use_hills", 0.5) >= 0.5


def test_avoid_hills_lowers_use_hills():
    """Activer avoid_hills doit baisser le paramètre use_hills sous 0.3."""
    prefs = RoutePreferences(avoid_hills=True)
    options = _build_costing_options(prefs)
    assert "use_hills" in options
    assert options["use_hills"] < 0.3


def test_prefer_nature_increases_living_streets():
    """Activer prefer_nature doit monter use_living_streets à 1.0."""
    prefs = RoutePreferences(prefer_nature=True)
    options = _build_costing_options(prefs)
    assert options.get("use_living_streets") == 1.0
    assert options.get("use_tracks", 0) >= 0.8


def test_all_preferences_combined():
    """Combiner tous les filtres ne doit pas lever d'exception."""
    prefs = RoutePreferences(
        prefer_nature=True,
        prefer_culture=True,
        avoid_hills=True,
        avoid_traffic=True,
    )
    try:
        options = _build_costing_options(prefs)
        assert isinstance(options, dict)
    except Exception as e:
        assert False, f"Exception inattendue : {e}"


def test_costing_options_always_returns_dict():
    """_build_costing_options doit toujours retourner un dictionnaire."""
    for flags in [(False, False, False, False), (True, True, True, True)]:
        prefs = RoutePreferences(
            prefer_nature=flags[0],
            prefer_culture=flags[1],
            avoid_hills=flags[2],
            avoid_traffic=flags[3],
        )
        result = _build_costing_options(prefs)
        assert isinstance(result, dict)
