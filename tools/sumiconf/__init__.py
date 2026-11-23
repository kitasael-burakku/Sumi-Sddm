"""Configuración de Sumi SDDM: esquema, INI compatible con QSettings, imágenes y rutas del usuario."""
import sys

sys.dont_write_bytecode = True

from .schema import ConfigError, Schema, lenient, strict, to_ini  # noqa: E402

__all__ = ["ConfigError", "Schema", "lenient", "strict", "to_ini"]
