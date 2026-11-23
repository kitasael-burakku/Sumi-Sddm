"""Backend del editor: la traducción a Python de `integration/sumi-shell/services/SddmTheme.qml` (Settings).

Todo lo hace la orden `sumi-sddm` del PATH (contrato JSON api 1, docs/CLI-JSON.md) con verbos fijos y `argv`: nunca
un shell, nunca escribe archivos ni valida por su cuenta. Las reglas son las de Settings, para que las dos
superficies no se contradigan:

- un proceso a la vez, en cola; `show`, `preview`, `system` y `avatar` no se repiten en la cola;
- `set(k, v)` cambia la vista al momento y se escribe agrupado (300 ms quieto) con `--expect <stamp>`; ante un
  `conflict` se descarta lo pendiente, se recarga y se avisa;
- vista previa 600 ms después del último cambio guardado, una a la vez;
- `system apply|activate|deactivate` (pkexec) corren en su propio proceso: esperar a polkit no bloquea la cola;
- las acciones con riesgo (Reset all, Use, Restore, Try) piden dos pulsaciones.

Además de Settings: cada orden de la cola tiene un tiempo límite (una CLI colgada no bloquea el editor para
siempre; las de sistema no, porque esperan a una persona) y `recheck()`, para cuando la ventana recupera el foco:
relee y avisa si alguien cambió algo desde la terminal o desde Settings.

Sólo usa QtCore: se prueba sin ventana (tests/py/test_editor_backend.py, con una CLI falsa).
"""
from __future__ import annotations

import json
import math
import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from PySide6.QtCore import Property, QObject, QProcess, QTimer, QUrl, Signal, Slot

API = 1
PROGRAM = "sumi-sddm"
DEDUP = frozenset({"show", "preview", "system", "avatar", "log"})
#: Guía de recuperación: la del paquete y, en el repositorio, la de docs/.
RECOVERY_DOCS = ["/usr/share/doc/sumi-sddm/RECUPERACION.md",
                 str(Path(__file__).resolve().parents[2] / "docs" / "RECUPERACION.md")]
RECOVERY_COMMAND = "sudo /usr/lib/sumi-sddm/sumi-sddm-helper deactivate"
STAMP_LEN = 32
SCENARIOS = [{"label": "Compact", "value": "compact"}, {"label": "Password", "value": "expanded"},
             {"label": "Sessions", "value": "sessions"}, {"label": "Error", "value": "failed"}]


@dataclass
class Job:
    kind: str
    args: list[str]
    done: Callable[[dict | None, int], None]
    expect: bool = False
    timeout_ms: int = 0


def raw_value(entry: dict, value: Any) -> str:
    """Un valor del tipo del esquema → el texto que espera `config set` (igual que `_raw` de Settings)."""
    t = entry.get("type")
    if t == "bool":
        return "true" if value else "false"
    if t == "integer":
        return str(math.floor(float(value) + 0.5))          # Math.round de JS, no el redondeo bancario
    if t == "number":
        r = math.floor(float(value) * 1000 + 0.5) / 1000
        return str(int(r)) if r == int(r) else repr(r)
    return str(value)


def local_path(path: Any) -> str:
    """Ruta de un FileDialog (QUrl o `file:///…`) o escrita a mano (`~/…`) → ruta local."""
    if isinstance(path, QUrl):
        path = path.toLocalFile() if path.isLocalFile() else path.toString()
    p = str(path or "").strip()
    if p.startswith("file:"):
        p = QUrl(p).toLocalFile()
    return os.path.expanduser(p) if p.startswith("~/") else p


def enum_label(v: Any) -> str:
    """"top-left" → «Top left», "24h" → «24 h»."""
    s = str(v)
    if s[:-1].isdigit() and s.endswith("h"):
        return s[:-1] + " h"
    t = s.replace("-", " ")
    return t[:1].upper() + t[1:]


def _ro(typ, name: str, notify):
    return Property(typ, lambda self: getattr(self, "_" + name), notify=notify)


class Backend(QObject):
    # ---- estado (QML lee estas propiedades) --------------------------------------------------------------------------
    statusChanged = Signal()
    statusDetailChanged = Signal()
    versionChanged = Signal()
    groupsChanged = Signal()
    keysChanged = Signal()
    orderChanged = Signal()
    valuesChanged = Signal()
    stampChanged = Signal()
    warningsChanged = Signal()
    fontsChanged = Signal()
    errorChanged = Signal()
    noticeChanged = Signal()
    systemChanged = Signal()
    systemBusyChanged = Signal()
    avatarChanged = Signal()
    systemLogChanged = Signal()
    busyChanged = Signal()
    writeCountChanged = Signal()
    previewUrlChanged = Signal()
    previewStampChanged = Signal()
    previewFailedChanged = Signal()
    previewStaleChanged = Signal()
    scenarioChanged = Signal()
    previewSizeChanged = Signal()
    previewEnabledChanged = Signal()
    resetArmedChanged = Signal()
    activateArmedChanged = Signal()
    deactivateArmedChanged = Signal()
    tryArmedChanged = Signal()

    #: "" sin comprobar · checking · ready · missing (no hay `sumi-sddm`) · incompatible (otro api) · broken
    status = _ro(str, "status", statusChanged)
    statusDetail = _ro(str, "statusDetail", statusDetailChanged)
    version = _ro(str, "version", versionChanged)
    groups = _ro("QVariantList", "groups", groupsChanged)           # [{id, label}]
    keys = _ro("QVariantMap", "keys", keysChanged)                  # clave → entrada del esquema
    order = _ro("QVariantList", "order", orderChanged)              # claves en el orden del esquema
    values = _ro("QVariantMap", "values", valuesChanged)            # clave → {value, default, set}
    stamp = _ro(str, "stamp", stampChanged)
    warnings = _ro("QVariantList", "warnings", warningsChanged)     # [{key, message}]
    fonts = _ro("QVariantList", "fonts", fontsChanged)              # [{family, system}]
    error = _ro(str, "error", errorChanged)                         # el último error para la persona
    notice = _ro(str, "notice", noticeChanged)                      # aviso informativo
    system = _ro("QVariant", "system", systemChanged)               # `system status` o None
    systemBusy = _ro(str, "systemBusy", systemBusyChanged)          # "" · apply · activate · deactivate
    avatar = _ro("QVariant", "avatar", avatarChanged)               # `avatar info` o None
    systemLog = _ro("QVariant", "systemLog", systemLogChanged)      # `system log` (último arranque) o None
    busy = _ro(bool, "busy", busyChanged)
    writeCount = _ro(int, "writeCount", writeCountChanged)          # escrituras aceptadas (diagnóstico, pruebas)
    previewUrl = _ro(str, "previewUrl", previewUrlChanged)
    previewStamp = _ro(str, "previewStamp", previewStampChanged)
    previewFailed = _ro(bool, "previewFailed", previewFailedChanged)
    previewStale = _ro(bool, "previewStale", previewStaleChanged)
    resetArmed = _ro(bool, "resetArmed", resetArmedChanged)
    activateArmed = _ro(bool, "activateArmed", activateArmedChanged)
    deactivateArmed = _ro(bool, "deactivateArmed", deactivateArmedChanged)
    tryArmed = _ro(bool, "tryArmed", tryArmedChanged)

    def __init__(self, parent: QObject | None = None, *, program: str | None = None, write_delay_ms: int = 300,
                 preview_delay_ms: int = 600, job_timeout_ms: int = 60_000, preview_timeout_ms: int = 120_000,
                 disarm_ms: int = 4000, apply_retry_ms: int = 250):
        super().__init__(parent)
        self._program = program                  # None = buscar `sumi-sddm` en el PATH al cargar
        self._exe = ""
        self._job_timeout_ms = job_timeout_ms
        self._preview_timeout_ms = preview_timeout_ms

        self._status = self._statusDetail = self._version = self._stamp = ""
        self._error = self._notice = self._systemBusy = ""
        self._groups: list = []
        self._keys: dict = {}
        self._order: list = []
        self._values: dict = {}
        self._warnings: list = []
        self._fonts: list = []
        self._system: dict | None = None
        self._avatar: dict | None = None
        self._systemLog: dict | None = None
        self._busy = False
        self._writeCount = 0
        self._previewUrl = self._previewStamp = ""
        self._previewFailed = False
        self._previewStale = True
        self._previewScenario = ""
        self._previewSerial = 0
        self._scenario = "expanded"
        self._previewSize = "1280x720"
        self._previewEnabled = True
        self._resetArmed = self._activateArmed = self._deactivateArmed = self._tryArmed = False

        self._queue: list[Job] = []
        self._running: Job | None = None
        self._pending: dict[str, dict] = {}      # clave → {value, raw}; raw "" = quitar
        self._last_stderr = ""

        self._write_timer = self._timer(write_delay_ms, self._flush)
        self._preview_timer = self._timer(preview_delay_ms, self._preview)
        self._apply_retry = self._timer(apply_retry_ms, self.systemApply)
        self._disarm = self._timer(disarm_ms, self._disarm_all)

    def _timer(self, ms: int, slot) -> QTimer:
        t = QTimer(self)
        t.setSingleShot(True)
        t.setInterval(ms)
        t.timeout.connect(slot)
        return t

    def _put(self, name: str, value) -> None:
        if getattr(self, "_" + name) != value:
            setattr(self, "_" + name, value)
            getattr(self, name + "Changed").emit()

    # ---- propiedades escribibles y derivadas ------------------------------------------------------------------------
    @Property(bool, notify=statusChanged)
    def ready(self) -> bool:
        return self._status == "ready"

    @Property(int, notify=valuesChanged)
    def customCount(self) -> int:
        return sum(1 for k in self._order if self._values.get(k, {}).get("set"))

    @Property("QVariantList", constant=True)
    def scenarios(self) -> list:
        return SCENARIOS

    @Property(str, constant=True)
    def recoveryDoc(self) -> str:
        """URL de la guía de recuperación instalada («» si no está)."""
        return next((QUrl.fromLocalFile(p).toString() for p in RECOVERY_DOCS if os.path.isfile(p)), "")

    @Property(str, constant=True)
    def recoveryCommand(self) -> str:
        return RECOVERY_COMMAND

    def _get_scenario(self) -> str:
        return self._scenario

    def _set_scenario(self, v: str) -> None:
        if v != self._scenario:
            self._put("scenario", str(v))
            self._refresh_stale()
            self.schedulePreview()

    scenario = Property(str, _get_scenario, _set_scenario, notify=scenarioChanged)

    def _get_preview_size(self) -> str:
        return self._previewSize

    def _set_preview_size(self, v: str) -> None:
        if v != self._previewSize:
            self._put("previewSize", str(v))
            self.schedulePreview()

    previewSize = Property(str, _get_preview_size, _set_preview_size, notify=previewSizeChanged)

    def _get_preview_enabled(self) -> bool:
        return self._previewEnabled

    def _set_preview_enabled(self, v: bool) -> None:
        self._put("previewEnabled", bool(v))
        if self._previewEnabled:
            self.schedulePreview()
        else:
            self._preview_timer.stop()

    previewEnabled = Property(bool, _get_preview_enabled, _set_preview_enabled, notify=previewEnabledChanged)

    def _refresh_busy(self) -> None:
        self._put("busy", self._running is not None or bool(self._queue) or self._write_timer.isActive())

    def _refresh_stale(self) -> None:
        self._put("previewStale", self._previewStamp != self._stamp or self._previewScenario != self._scenario)

    def _set_stamp(self, s: str) -> None:
        self._put("stamp", s)
        self._refresh_stale()

    # ---- procesos ------------------------------------------------------------------------------------------------
    def _run(self, args: list[str], timeout_ms: int, on_done: Callable[[dict | None, int], None]) -> QProcess:
        """Lanza `sumi-sddm ARGS` (programa + argv, sin shell) y llama a on_done(doc, code) una sola vez."""
        proc = QProcess(self)
        proc.setProgram(self._exe)
        proc.setArguments(args)
        proc.setProcessChannelMode(QProcess.ProcessChannelMode.SeparateChannels)
        state = {"done": False, "timed_out": False}
        watchdog = None

        def finish(code: int) -> None:
            if state["done"]:
                return
            state["done"] = True
            if watchdog is not None:
                watchdog.stop()
            out = bytes(proc.readAllStandardOutput()).decode("utf-8", "replace")
            self._last_stderr = bytes(proc.readAllStandardError()).decode("utf-8", "replace").strip()
            proc.deleteLater()
            if state["timed_out"]:
                doc: dict | None = {"ok": False, "code": "timeout", "error": "sumi-sddm did not answer in time"}
            else:
                try:
                    doc = json.loads(out.strip())
                except ValueError:
                    doc = None
                if not isinstance(doc, dict):
                    doc = None
            on_done(doc, code)

        def on_error(err) -> None:
            # Un programa que no arranca no emite `finished`; un cuelgue sí (después de kill).
            if err == QProcess.ProcessError.FailedToStart:
                finish(127)

        def on_timeout() -> None:
            state["timed_out"] = True
            proc.kill()

        proc.finished.connect(lambda code, _status: finish(code))
        proc.errorOccurred.connect(on_error)
        if timeout_ms > 0:
            watchdog = QTimer(proc)
            watchdog.setSingleShot(True)
            watchdog.timeout.connect(on_timeout)
            watchdog.start(timeout_ms)
        proc.start()
        proc.closeWriteChannel()
        return proc

    def _enqueue(self, job: Job) -> None:
        if job.kind in DEDUP and any(j.kind == job.kind for j in self._queue):
            return
        self._queue.append(job)
        self._pump()

    def _pump(self) -> None:
        if self._running is not None or not self._queue:
            self._refresh_busy()
            return
        job = self._queue.pop(0)
        self._running = job
        self._refresh_busy()
        # La huella se toma al LANZAR, no al encolar: una escritura propia anterior ya la habrá actualizado.
        expect = ["--expect", self._stamp] if job.expect and len(self._stamp) == STAMP_LEN else []
        self._run(job.args + expect + ["--json"], job.timeout_ms or self._job_timeout_ms,
                  lambda doc, code: self._job_done(job, doc, code))

    def _job_done(self, job: Job, doc: dict | None, code: int) -> None:
        self._running = None
        try:
            job.done(doc, code)
        except Exception:            # un fallo en un manejador no debe parar la cola
            self._put("error", "Unexpected reply from sumi-sddm")
        self._pump()

    @staticmethod
    def _err(doc: dict | None, fallback: str) -> str:
        return str(doc["error"]) if doc and doc.get("error") else fallback

    @staticmethod
    def _ok(doc: dict | None) -> bool:
        return bool(doc) and doc.get("ok") is True

    # ---- carga -----------------------------------------------------------------------------------------------------
    @Slot()
    def load(self) -> None:
        """versión → esquema → valores (y después fuentes, sistema, avatar y vista previa)."""
        self._exe = self._program or shutil.which(PROGRAM) or ""
        if not self._exe:
            self._put("statusDetail", "")
            self._put("status", "missing")
            return
        self._put("status", "checking")
        self._enqueue(Job("version", ["version"], self._version_done))

    def _broken(self, detail: str) -> None:
        self._put("statusDetail", detail)
        self._put("status", "broken")

    def _version_done(self, doc: dict | None, code: int) -> None:
        if code == 127 and doc is None:
            self._put("statusDetail", "")
            self._put("status", "missing")
            return
        if not self._ok(doc):
            first = self._last_stderr.splitlines()[0] if self._last_stderr else ""
            self._broken(self._err(doc, first or "sumi-sddm did not answer as expected"))
            return
        if doc.get("api") != API:
            self._put("statusDetail", f"sumi-sddm speaks version {doc.get('api')} of its interface; "
                                      f"this editor expects {API}")
            self._put("status", "incompatible")
            return
        self._put("version", str(doc.get("version") or ""))
        self._enqueue(Job("schema", ["config", "schema"], self._schema_done))

    def _schema_done(self, doc: dict | None, _code: int) -> None:
        if not self._ok(doc) or not isinstance(doc.get("keys"), list):
            self._broken(self._err(doc, "Could not read the settings list"))
            return
        keys = {str(e["key"]): e for e in doc["keys"]}
        self._put("keys", keys)
        self._put("order", list(keys))
        self._put("groups", [{"id": str(g["id"]), "label": str(g.get("label") or g["id"])}
                             for g in doc.get("groups") or []])
        self._reload(announce=False)
        if not self._fonts:
            self._enqueue(Job("fonts", ["config", "fonts"], self._fonts_done))

    def _fonts_done(self, doc: dict | None, _code: int) -> None:
        if self._ok(doc):
            self._put("fonts", list(doc.get("families") or []))

    @Slot()
    def reload(self) -> None:
        """Relee los valores. Lo que aún espera a escribirse se conserva encima (la vista no salta atrás)."""
        self._reload(announce=False)

    @Slot()
    def recheck(self) -> None:
        """Al volver el foco: relee y, si la huella cambió por algo ajeno, avisa."""
        if self.ready:
            self._reload(announce=True)

    def _reload(self, announce: bool) -> None:
        self._enqueue(Job("show", ["config", "show"], lambda doc, code: self._show_done(doc, announce)))

    def _show_done(self, doc: dict | None, announce: bool) -> None:
        if not self._ok(doc):
            self._broken(self._err(doc, "Could not read the settings"))
            return
        vals = {k: dict(v) for k, v in (doc.get("values") or {}).items()}
        for key, p in self._pending.items():
            if key in vals:
                vals[key].update(value=p["value"], set=p["raw"] != "")
        new_stamp = str(doc.get("stamp") or "")
        if announce and self._stamp and new_stamp != self._stamp and not self._pending:
            self._put("notice", "Changed outside the editor · reloaded")
        self._put("values", vals)
        self._set_stamp(new_stamp)
        self._put("warnings", list(doc.get("warnings") or []))
        self._put("status", "ready")
        self.schedulePreview()
        self.refreshSystem()
        if self._avatar is None:
            self.refreshAvatar()

    @Slot()
    def refreshSystem(self) -> None:
        def done(doc, _code):
            if self._ok(doc):
                self._put("system", doc)
            else:
                self._put("system", {"installed": False, "missing": bool(doc and doc.get("code") == "missing"),
                                     "error": self._err(doc, "")})
        self._enqueue(Job("system", ["system", "status"], done))

    @Slot()
    def refreshLog(self) -> None:
        """`system log`: qué pasó en la pantalla de inicio de este arranque (sin root, del journal)."""
        if not self.ready:
            return

        def done(doc, _code):
            # Sale con 1 si un greeter de Sumi tuvo problemas, pero el documento sigue siendo válido. «missing» = el
            # journal no tiene ningún greeter en este arranque: no es un error, es que aún no se ha visto ninguno.
            if self._ok(doc):
                self._put("systemLog", doc)
            elif doc and doc.get("code") == "missing":
                self._put("systemLog", {"greeters": []})
            else:
                self._put("systemLog", {"error": self._err(doc, "The log could not be read")})
        self._enqueue(Job("log", ["system", "log"], done))

    @Slot(str)
    def inform(self, text: str) -> None:
        """Un aviso de la ventana en el mismo sitio que los del backend."""
        self._put("error", "")
        self._put("notice", text)

    @Slot()
    def refreshAvatar(self) -> None:
        def done(doc, _code):
            self._put("avatar", doc if self._ok(doc) else {"exists": False, "error": self._err(doc, "")})
        self._enqueue(Job("avatar", ["avatar", "info"], done))

    # ---- avatar ------------------------------------------------------------------------------------------------------
    @Slot("QVariant")
    def setAvatar(self, path) -> None:
        p = local_path(path)
        if not self.ready or not p:
            return
        self._clear_messages()

        def done(doc, _code):
            if self._ok(doc):
                # Siempre «cambió»: AccountsService guarda la foto nueva con el mismo nombre, así que la respuesta
                # puede ser idéntica a la anterior y, sin el aviso, la ventana seguiría enseñando la vieja.
                self._avatar = doc
                self.avatarChanged.emit()
                self._put("notice", "Avatar saved")
                self.schedulePreview()
            else:
                self._put("error", self._err(doc, "The avatar could not be saved"))
                self.refreshAvatar()
        self._enqueue(Job("avatarSet", ["avatar", "set", p], done))

    @Slot()
    def clearAvatar(self) -> None:
        if not self.ready:
            return

        def done(doc, _code):
            if not self._ok(doc):
                self._put("error", self._err(doc, "The avatar could not be removed"))
            self.refreshAvatar()
            self.schedulePreview()
        self._enqueue(Job("avatarSet", ["avatar", "clear"], done))

    # ---- escribir --------------------------------------------------------------------------------------------------
    @Slot(str, result="QVariant")
    def valueOf(self, key: str):
        if key == "avatar":
            return str(self._avatar["iconFile"]) if self._avatar and self._avatar.get("exists") else ""
        v = self._values.get(key)
        return v.get("value") if v else None

    @Slot(str, result=bool)
    def isSet(self, key: str) -> bool:
        if key == "avatar":
            return bool(self._avatar and self._avatar.get("exists"))
        return bool(self._values.get(key, {}).get("set"))

    @Slot(str, "QVariant")
    def set(self, key: str, value) -> None:
        """Cambio de una clave, en el tipo del esquema; None = volver al valor por defecto."""
        e = self._keys.get(key)
        if not e or not self.ready:
            return
        unset = value is None
        shown = e.get("default") if unset else value
        self._pending = {**self._pending, key: {"value": shown, "raw": "" if unset else raw_value(e, value)}}
        vals = dict(self._values)
        vals[key] = {**vals.get(key, {}), "value": shown, "set": not unset}
        self._put("values", vals)
        self._clear_messages()
        self._write_timer.start()
        self._refresh_busy()

    @Slot(str)
    def unset(self, key: str) -> None:
        if key == "avatar":
            self.clearAvatar()
        else:
            self.set(key, None)

    @Slot()
    def flushNow(self) -> None:
        """Escribe ya lo pendiente (al cerrar la ventana: no se pierde lo de los últimos 300 ms)."""
        if self._pending:
            self._write_timer.stop()
            self._flush()

    @Slot()
    def shutdown(self) -> None:
        """Al salir: nada más en marcha. Para los temporizadores, vacía la cola y termina los procesos de la cola.

        Una operación de sistema en curso (pkexec) no se mata aquí: la ventana no deja cerrar mientras dure.
        """
        for t in (self._write_timer, self._preview_timer, self._apply_retry, self._disarm):
            t.stop()
        self._queue.clear()
        for proc in self.findChildren(QProcess):
            if proc.property("sumiSystem"):
                continue
            if proc.state() != QProcess.ProcessState.NotRunning:
                proc.kill()
                proc.waitForFinished(2000)
        self._refresh_busy()

    @Slot()
    def dismiss(self) -> None:
        """Cierra el aviso o el error que se está enseñando."""
        self._clear_messages()

    def _flush(self) -> None:
        if not self._pending:
            self._refresh_busy()
            return
        if self._running is not None and self._running.kind == "set":
            self._write_timer.start()
            return
        sent, self._pending = self._pending, {}
        self._write(["config", "set", *(f"{k}={p['raw']}" for k, p in sent.items())])

    def _write(self, args: list[str]) -> None:
        self._enqueue(Job("set", args, self._written, expect=True))

    def _written(self, doc: dict | None, _code: int) -> None:
        if self._ok(doc):
            self._put("writeCount", self._writeCount + 1)
            self._set_stamp(str(doc.get("stamp") or self._stamp))
            self.reload()                 # y, tras ella, `system status`: lo aplicado deja de coincidir
            return
        # Lo enviado no se guardó: lo pendiente posterior tampoco vale si la base cambió.
        if doc and doc.get("code") == "conflict":
            self._pending = {}
            self._write_timer.stop()
            self._put("notice", "Changed outside the editor · reloaded")
        else:
            self._put("error", self._err(doc, "sumi-sddm could not save the change"))
        self.reload()

    @Slot("QVariant")
    def setWallpaper(self, path) -> None:
        p = local_path(path)
        if not self.ready or not p:
            return
        self._clear_messages()
        self._write(["wallpaper", "set", p])

    @Slot()
    def clearWallpaper(self) -> None:
        if self.ready:
            self._write(["wallpaper", "clear"])

    @Slot()
    def resetAll(self) -> None:
        """Reset all: dos pulsaciones; deja una copia (.prev) que recupera restorePrevious()."""
        if not self.ready or self.customCount == 0:
            return
        if not self._arm("resetArmed"):
            return
        self._pending = {}
        self._write_timer.stop()
        self._write(["config", "reset"])

    @Slot()
    def restorePrevious(self) -> None:
        if self.ready:
            self._write(["config", "restore"])

    # ---- dos pulsaciones -----------------------------------------------------------------------------------------
    def _arm(self, name: str) -> bool:
        """Primera pulsación: arma y devuelve False. Segunda (antes de que caduque): desarma y devuelve True."""
        if not getattr(self, "_" + name):
            self._put(name, True)
            self._disarm.start()
            return False
        self._put(name, False)
        return True

    def _disarm_all(self) -> None:
        for name in ("resetArmed", "activateArmed", "deactivateArmed", "tryArmed"):
            self._put(name, False)

    def _clear_messages(self) -> None:
        self._put("error", "")
        self._put("notice", "")

    @Slot()
    def openTestWindow(self) -> None:
        """El greeter real en una ventana (`try --yes`): toma el teclado, así que dos pulsaciones."""
        if not self.ready or not self._arm("tryArmed"):
            return
        QProcess.startDetached(self._exe, ["try", "--yes"])

    # ---- sistema (pkexec, su propio proceso) ----------------------------------------------------------------------
    def _installed(self) -> bool:
        return bool(self._system) and self._system.get("installed") is True

    @Slot()
    def systemApply(self) -> None:
        if not self.ready or self._systemBusy or not self._installed():
            return
        # lo pendiente de escribir va antes: se aplica lo que se ve
        if self._pending or self._write_timer.isActive() or self._running is not None or self._queue:
            self._apply_retry.start()
            return
        self._system_run("apply")

    @Slot()
    def activateSystem(self) -> None:
        if not self.ready or self._systemBusy or not self._installed() or self._system.get("active"):
            return
        if self._arm("activateArmed"):
            self._system_run("activate")

    @Slot()
    def deactivateSystem(self) -> None:
        if not self.ready or self._systemBusy or not self._system or self._system.get("active") is not True:
            return
        if self._arm("deactivateArmed"):
            self._system_run("deactivate")

    def _system_run(self, verb: str) -> None:
        self._clear_messages()
        self._put("systemBusy", verb)
        proc = self._run(["system", verb, "--json"], 0, lambda doc, code: self._system_done(verb, doc))
        proc.setProperty("sumiSystem", True)

    def _system_done(self, verb: str, doc: dict | None) -> None:
        self._put("systemBusy", "")
        if self._ok(doc):
            if verb == "apply":
                msg = "Applied to the login screen" if doc.get("changed") else \
                    "The login screen already had these settings"
            elif verb == "activate":
                msg = "Sumi will be your login screen the next time it appears"
            else:
                msg = f"Back to {doc.get('activeTheme') or 'the previous theme'} the next time the login screen appears"
            self._put("notice", msg)
        elif doc and doc.get("code") == "denied":
            self._put("notice", "Authentication cancelled · nothing changed")
        elif doc and doc.get("code") == "probe":
            first = (doc.get("problems") or [""])[0]
            self._put("error", "The theme failed its test with these settings · nothing changed"
                      + (f" · {first}" if first else ""))
        else:
            self._put("error", self._err(doc, "sumi-sddm could not change the login screen"))
        self.refreshSystem()

    # ---- vista previa ----------------------------------------------------------------------------------------------
    @Slot()
    def schedulePreview(self) -> None:
        if self._previewEnabled and self.ready:
            self._preview_timer.start()

    def _preview(self) -> None:
        if not self._previewEnabled or not self.ready:
            return
        if self._pending or self._write_timer.isActive():
            self._preview_timer.start()
            return
        sc, size = self._scenario, self._previewSize

        def done(doc, _code):
            if self._ok(doc) and doc.get("png"):
                self._previewSerial += 1
                # otra URL en cada vista previa: la Image no reutiliza la anterior de su caché
                self._put("previewUrl", QUrl.fromLocalFile(str(doc["png"])).toString() + f"?v={self._previewSerial}")
                self._put("previewStamp", str(doc.get("stamp") or ""))
                self._previewScenario = sc
                self._put("previewFailed", False)
            else:
                self._put("previewFailed", True)
                self._put("error", self._err(doc, "The preview could not be made"))
            self._refresh_stale()
        self._enqueue(Job("preview", ["preview", "--scenario", sc, "--size", size], done,
                          timeout_ms=self._preview_timeout_ms))

    # ---- ayudas para el formulario ----------------------------------------------------------------------------------
    @Slot(str, result=str)
    def captionFor(self, key: str) -> str:
        if key == "avatar":
            a = self._avatar
            if not a:
                return ""
            if a.get("error"):
                return str(a["error"])
            if not a.get("exists"):
                return "Choose a picture · without one, your initials are shown"
            return "Shown on the login screen · cropped to a circle" if a.get("sddmUses") else \
                "Saved, but the login screen can't read it"
        w = next((w for w in self._warnings if w.get("key") == key), None)
        if w:
            return str(w.get("message", ""))
        return str(self._keys.get(key, {}).get("help") or "")

    @Slot("QVariant", result=str)
    def enumLabel(self, v) -> str:
        return enum_label(v)

    @Slot(str, int)
    def step(self, key: str, direction: int) -> None:
        """Un paso de teclado sobre la clave (←/→ = -1/+1, Enter = 0), como en Settings."""
        e = self._keys.get(key)
        if not e or not self.ready:
            return
        v = self.valueOf(key)
        t = e.get("type")
        if t == "bool":
            self.set(key, (not v) if direction == 0 else direction > 0)
        elif t == "enum":
            vals = list(e.get("values") or [])
            if not vals:
                return
            i = vals.index(v) if v in vals else 0
            self.set(key, vals[(i + (direction or 1)) % len(vals)])
        elif t in ("number", "integer") and direction:
            lo = 0 if e.get("allowZero") else e["min"]
            n = float(v) + direction * float(e.get("step") or 1)
            if e.get("allowZero") and 0 < n < e["min"]:
                n = e["min"] if direction > 0 else 0
            n = max(lo, min(e["max"], math.floor(n * 1000 + 0.5) / 1000))
            self.set(key, int(n) if t == "integer" else n)
