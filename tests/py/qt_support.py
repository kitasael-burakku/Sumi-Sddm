"""Una sola QGuiApplication offscreen para todas las pruebas con Qt (backend y ventana del editor).

Qt sólo admite una aplicación por proceso y `unittest discover` carga todas las pruebas en el mismo: si la primera
creara una QCoreApplication, las de QtQuick ya no podrían crear la suya.
"""
from __future__ import annotations

import os
import time

try:
    from PySide6.QtCore import QCoreApplication, QEvent, QEventLoop
    from PySide6.QtGui import QGuiApplication
except ImportError:          # pragma: no cover - depende del sistema
    QGuiApplication = None


def app():
    # Siempre offscreen y sin el tema de Qt de quien ejecuta las pruebas: con `setdefault`, una sesión con
    # QT_QPA_PLATFORM=wayland abría las ventanas de prueba en su escritorio, y qt6ct imponía su paleta.
    if QGuiApplication.instance() is None:
        os.environ["QT_QPA_PLATFORM"] = "offscreen"
        os.environ["QT_QUICK_BACKEND"] = "software"
        os.environ.pop("QT_QPA_PLATFORMTHEME", None)
        os.environ.pop("QT_STYLE_OVERRIDE", None)
    return QGuiApplication.instance() or QGuiApplication([])


def spin(seconds: float) -> None:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        app().processEvents(QEventLoop.ProcessEventsFlag.AllEvents, 20)
        time.sleep(0.002)


def wait(cond, timeout: float = 10) -> bool:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if cond():
            return True
        app().processEvents(QEventLoop.ProcessEventsFlag.AllEvents, 20)
        time.sleep(0.002)
    return cond()


def flush_deletes() -> None:
    """Procesa ya los deleteLater pendientes (processEvents no los procesa fuera de un bucle exec)."""
    for _ in range(3):
        QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
        app().processEvents(QEventLoop.ProcessEventsFlag.AllEvents, 20)
