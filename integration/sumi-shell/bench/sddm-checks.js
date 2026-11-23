// Pasos del banco de Settings → Login screen (Sumi SDDM). Cada paso devuelve false para «aún no» (se reintenta) y lo demás
// avanza. Sólo se tocan el HOME y el XDG privados del banco.
//
// 2026-11-23: desde la ventana propia de Sumi Shell (ADR-41) la página es un resumen: estado, «Open Login screen» y
// Apply / Use / Restore. Las claves, la vista previa, Reset y el avatar están en la ventana (su banco es
// tools/login-ui/window-bench.py del repo de Sumi Shell); aquí se prueban la página y, por el servicio que comparten
// (SddmTheme), los caminos que llegan a la CLI real: escritura agrupada, conflicto, rechazo, wallpaper, reset, avatar.

function cases(w, sddm, settings, ui) {
    const p = w.page, test = (c, label) => w.assertThat(c, label);
    const steps = [];
    const step = (label, fn, timeout) => steps.push({ label: label, fn: fn, timeout: timeout });
    const idle = () => !sddm.busy && sddm.ready && sddm.systemBusy === "";
    const rowIds = () => p.searchIndex.filter(e => e.kind === "row" && e.path.indexOf("shell/sddm/") === 0).map(e => e.id);
    const cli = (label, argv, check) => {
        step(label + " (orden)", () => { w.run(["sumi-sddm"].concat(argv).concat(["--json"])); });
        step(label, () => { if (w.external === null) return false; check(w.external.doc || {}, w.external); });
    };

    step("abrir la página", () => {
        test(p.openPath("shell/sddm"), "abrir shell/sddm");
        test(p.shownKey === "shell/sddm", "página Login screen a la vista");
        test(sddm.watching, "la página reclama el servicio");
        test(rowIds().join(",") === "sddmStatus,sddmApplied,sddmOpen,sddmApply,sddmActivate,sddmDeactivate",
             "filas: " + rowIds().join(","));
        test(p.sectionTabs.length <= 1, "sin pestañas");
    });

    if (w.scenario === "missing" || w.scenario === "incompatible") {
        const want = w.scenario;
        step("estado " + want, () => {
            if (sddm.status === "checking" || sddm.status === "") return false;
            test(sddm.status === want, "estado " + want + " (es " + sddm.status + ")");
            test(p.infoValue({ id: "sddmStatus" }) === (want === "missing" ? "Not installed" : "Incompatible version"),
                 "la fila de estado lo dice");
            const cap = p.captionOf({ id: "sddmStatus" });
            test(want === "missing" ? cap.indexOf("sumi-sddm package") >= 0 : cap.indexOf("version 2") >= 0,
                 "el pie explica qué hacer: " + cap);
            test(p.rowReason({ id: "sddmApply", kind: "action" }).length > 0, "las acciones quedan desactivadas");
            test(p.rowReason({ id: "sddmOpen", kind: "action" }) === "", "Open sigue disponible (la ventana lo explica)");
            test(sddm.rows("notch").length === 0, "sin esquema, sin filas de claves");
        });
        step("captura", () => { w.shot(want + ".png"); });
        step("cerrar la página", () => {
            test(p.openPath("shell/general"), "volver a General");
            test(!sddm.watching, "al salir se suelta el servicio");
        });
        return steps;
    }

    step("cargar", () => {
        if (!sddm.ready) return false;
        test(sddm.order.length === 41 && sddm.groups.length === 9, "esquema: 41 claves en 9 grupos");
        test(sddm.customCount === 0 && sddm.stamp.length === 32, "configuración vacía con huella");
        test(p.infoValue({ id: "sddmStatus" }).indexOf("Version ") === 0, "estado con versión");
        test(!sddm.previewing && sddm.previewUrl === "", "Settings no genera vista previa");
    });
    step("estado del sistema (falso)", () => {
        if (sddm.system === null || sddm.avatar === null) return false;
        test(sddm.system.installed === true && sddm.system.active === false, "instalado y no activo");
        test(p.infoValue({ id: "sddmApplied" }) === "Installed, not in use", "fila: " + p.infoValue({ id: "sddmApplied" }));
        test(sddm.system.inSync === true, "sin configuración, nada que aplicar");
        test(p.rowReason({ id: "sddmApply", kind: "action" }) === "The login screen already has your settings", "Apply desactivado");
        test(p.rowReason({ id: "sddmActivate", kind: "action" }) === "", "Use disponible");
        test(p.rowReason({ id: "sddmDeactivate", kind: "action" }) === "Sumi isn't your login screen", "Restore desactivado");
        test(p.captionOf({ id: "sddmOpen" }).indexOf("in their own window") > 0, "pie de Open");
    });
    step("captura", () => { w.shot(w.scenario + "-page.png"); });
    if (w.scenario !== "real") {
        step("cerrar", () => { test(p.openPath("shell/general") && !sddm.watching, "soltar al salir"); });
        return steps;
    }

    // ── escrituras por el servicio: agrupadas y persistidas ──
    let writesBefore = 0;
    step("doce cambios seguidos", () => {
        writesBefore = sddm.writeCount;
        for (let i = 1; i <= 12; i++) sddm.set("notchRadius", 20 + i * 2);
        sddm.set("clockSeconds", true);
        test(sddm.valueOf("notchRadius") === 44 && sddm.isSet("clockSeconds"), "la vista cambia al momento");
    });
    step("una escritura", () => {
        if (!idle() || sddm.writeCount === writesBefore) return false;
        test(sddm.writeCount - writesBefore === 1, "trece cambios, una escritura (" + (sddm.writeCount - writesBefore) + ")");
    });
    cli("en disco", ["config", "get", "notchRadius"], d => test(d.value === 44, "notchRadius=44 en disco"));

    // ── un cambio desde la terminal entre medias: no se pisa ──
    cli("cambio externo", ["config", "set", "accentColor=#ff8800"], d => test(d.ok === true, "otra parte cambia el acento"));
    step("escritura con la huella vieja", () => { sddm.set("notchRadius", 30); });
    step("conflicto detectado", () => {
        if (!idle()) return false;
        test(sddm.notice.indexOf("Changed outside") === 0, "aviso de conflicto: " + sddm.notice);
        test(sddm.valueOf("accentColor") === "#ff8800", "se recarga lo de fuera");
        test(sddm.valueOf("notchRadius") !== 30, "el cambio con huella vieja no se escribe");
    });

    // ── un valor que la CLI rechaza: en inglés, junto a su clave y en el estado de la página ──
    step("valor inválido", () => { sddm.set("fontFamily", "Bad;Name"); });
    step("rechazo", () => {
        if (!idle()) return false;
        test(sddm.error.length > 0, "error visible: " + sddm.error);
        test(sddm.fieldErrors["fontFamily"] !== undefined, "fieldErrors.fontFamily");
        test(sddm.valueOf("fontFamily") === "", "la vista vuelve a lo guardado");
        test(p.captionOf({ id: "sddmStatus" }) === sddm.error, "el estado de la página enseña el error");
    });

    // ── wallpaper ──
    step("poner wallpaper", () => { sddm.setWallpaper(w.home + "/pic.png"); });
    step("wallpaper preparado", () => {
        if (!idle()) return false;
        test(sddm.valueOf("background") === "backgrounds/user.png", "background=backgrounds/user.png");
        test(sddm.error === "", "sin error");
    });

    // ── restablecer todo (dos pulsaciones) y deshacer ──
    let before = 0;
    step("reset armado", () => {
        before = sddm.customCount;
        test(before >= 3, "hay cambios (" + before + ")");
        sddm.resetAll();
        test(sddm.resetArmed && sddm.customCount === before, "la primera pulsación sólo arma");
    });
    step("reset", () => { sddm.resetAll(); });
    step("reset hecho", () => { if (!idle()) return false; test(sddm.customCount === 0, "todo al defecto"); });
    step("restore", () => { sddm.restorePrevious(); });
    step("restore hecho", () => { if (!idle()) return false; test(sddm.customCount === before, "vuelve lo de antes"); });

    // ── el sistema (falso) desde la página: aplicar, usar y restaurar, sin pkexec real ──
    step("hay algo que aplicar", () => {
        if (!idle() || sddm.system === null) return false;
        test(sddm.system.inSync === false, "tras los cambios, lo aplicado ya no coincide");
        test(p.captionOf({ id: "sddmApplied" }).indexOf("aren't on the login screen yet") >= 0, "el pie lo dice");
        test(p.rowReason({ id: "sddmApply", kind: "action" }) === "", "Apply disponible");
        p.runAction("sddmApply");
        test(sddm.systemBusy === "apply", "Apply en marcha (esperaría la contraseña)");
        test(p.rowReason({ id: "sddmActivate", kind: "action" }) === "Waiting for your password…", "lo demás espera");
    });
    step("aplicado", () => {
        if (sddm.systemBusy !== "" || !idle()) return false;
        test(sddm.notice === "Applied to the login screen", "aviso: " + sddm.notice + " / " + sddm.error);
    });
    step("estado tras aplicar", () => {
        if (!idle() || !sddm.system || sddm.system.inSync !== true) return false;
        test(p.captionOf({ id: "sddmApplied" }) === "Has your current settings · Use it to make it your login screen", "pie tras aplicar");
    });
    step("Use armado", () => {
        p.runAction("sddmActivate");
        test(sddm.activateArmed && sddm.systemBusy === "", "la primera pulsación sólo arma");
        test(p.captionOf({ id: "sddmActivate" }).indexOf("Press again") === 0, "lo pide");
    });
    step("Use", () => { p.runAction("sddmActivate"); test(sddm.systemBusy === "activate", "activando"); });
    step("en uso", () => {
        if (sddm.systemBusy !== "" || !idle() || !sddm.system || !sddm.system.active) return false;
        test(p.infoValue({ id: "sddmApplied" }) === "In use", "fila: en uso");
        test(sddm.notice.indexOf("Sumi will be your login screen") === 0, "aviso de activación");
        test(p.rowReason({ id: "sddmActivate", kind: "action" }) === "Already your login screen", "Use ya no se ofrece");
    });
    step("captura en uso", () => { w.shot("real-page-in-use.png"); });
    step("Restore", () => { p.runAction("sddmDeactivate"); p.runAction("sddmDeactivate"); test(sddm.systemBusy === "deactivate", "restaurando"); });
    step("restaurado", () => {
        if (sddm.systemBusy !== "" || !idle() || !sddm.system || sddm.system.active) return false;
        test(sddm.notice.indexOf("Back to orbital") === 0, "aviso: " + sddm.notice);
        test(p.infoValue({ id: "sddmApplied" }) === "Installed, not in use", "otra vez sin usar");
    });

    // ── avatar (AccountsService falso) ──
    step("poner avatar", () => {
        test(sddm.captionFor("avatar").indexOf("your initials are shown") > 0, "pie sin avatar");
        sddm.setAvatar(w.home + "/pic.png");
    });
    step("avatar puesto", () => {
        if (!idle() || !sddm.avatar || !sddm.avatar.exists) return false;
        test(sddm.isSet("avatar") && sddm.notice === "Avatar saved", "aviso: " + sddm.notice + " / " + sddm.error);
    });
    step("quitar avatar", () => { sddm.unset("avatar"); });
    step("avatar quitado", () => { if (!idle() || !sddm.avatar || sddm.avatar.exists) return false; });

    // ── Open: la ventana, con origen en esta fila ──
    step("Open", () => {
        if (!p.screenName) p.screenName = "BENCH-1";      // review.qml no le da pantalla a Settings; la ventana la pide
        p.runAction("sddmOpen");
        test(!!ui && ui.open && !!ui.origin && ui.origin.path === "shell/sddm/sddmOpen", "Open abre la ventana con origen");
        test(ui.close(false), "cerrarla");
    });

    step("cerrar la página", () => {
        test(p.openPath("shell/general"), "volver a General");
        test(!sddm.watching, "al salir se suelta el servicio");
    });
    return steps;
}
