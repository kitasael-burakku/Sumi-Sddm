"""Rutas de usuario (sin privilegios). Respetan XDG_CONFIG_HOME / XDG_CACHE_HOME."""
from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
THEME = ROOT / "theme" / "sumi"
HARNESS = ROOT / "tools" / "harness"

WALLPAPER_STEM = "user"
WALLPAPER_DIR = "backgrounds"


def _xdg(var: str, fallback: str) -> Path:
    v = os.environ.get(var)
    return Path(v) if v and os.path.isabs(v) else Path.home() / fallback


def config_dir() -> Path:
    return _xdg("XDG_CONFIG_HOME", ".config") / "sumi-sddm"


def user_conf() -> Path:
    return config_dir() / "theme.conf.user"


def staged_backgrounds() -> Path:
    return config_dir() / WALLPAPER_DIR


def cache_dir() -> Path:
    return _xdg("XDG_CACHE_HOME", ".cache") / "sumi-sddm"
