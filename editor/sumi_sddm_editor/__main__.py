"""Arranque del editor: `python3 -m sumi_sddm_editor` (o el lanzador `editor/sumi-sddm-editor`)."""
from __future__ import annotations

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main(argv: list[str] | None = None) -> int:
    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtQuickControls2 import QQuickStyle

    from .backend import Backend

    argv = sys.argv if argv is None else argv
    # Fusion sigue la paleta del sistema en cualquier escritorio; quien quiera otro estilo usa la variable de Qt.
    if not os.environ.get("QT_QUICK_CONTROLS_STYLE"):
        QQuickStyle.setStyle("Fusion")
    app = QGuiApplication(argv)
    app.setApplicationName("sumi-sddm-editor")
    app.setApplicationDisplayName("Login Screen (Sumi)")
    app.setDesktopFileName("sumi-sddm-editor")

    backend = Backend()
    engine = QQmlApplicationEngine()
    engine.setInitialProperties({"backend": backend})
    engine.load(QUrl.fromLocalFile(str(HERE / "Main.qml")))
    if not engine.rootObjects():
        return 1
    app.aboutToQuit.connect(backend.shutdown)
    backend.load()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
