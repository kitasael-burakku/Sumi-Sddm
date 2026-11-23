// Pasos del banco de Settings → Login screen. Cada paso devuelve false para «aún no» (se reintenta) y lo demás avanza.
// Sólo se tocan el HOME y el XDG privados del banco.

function cases(w, sddm, settings) {
    const p = w.page, test = (c, label) => w.assertThat(c, label);
    const steps = [];
    const step = (label, fn, timeout) => steps.push({ label: label, fn: fn, timeout: timeout });
    const idle = () => !sddm.busy && sddm.ready;
    const tabs = () => p.sectionTabs.map(t => t.key).join("|");
    const shots = name => {
        for (const t of ["Overview", "Look", "Notch and clock", "Users and power", "Behaviour"]) {
            step("pestaña " + t, () => { test(p.selectTab(t), "pestaña " + t); });
            step("captura " + t, () => {
                if (t === "Overview" && (sddm.previewStale || sddm.previewUrl === "")) return false;
                w.shot(name + "-" + t.replace(/ /g, "-").toLowerCase() + ".png");
            }, 30000);
        }
    };
    const cli = (label, argv, check) => {
        step(label + " (orden)", () => { w.run(["sumi-sddm"].concat(argv).concat(["--json"])); });
        step(label, () => { if (w.external === null) return false; check(w.external.doc || {}, w.external); });
    };

    step("abrir la página", () => {
        test(p.openPath("shell/sddm"), "abrir shell/sddm");
        test(p.shownKey === "shell/sddm", "página Login screen a la vista");
        test(sddm.watching, "la página reclama el servicio");
    });

    if (w.scenario === "missing" || w.scenario === "incompatible") {
        const want = w.scenario;
        step("estado " + want, () => {
            if (sddm.status === "checking" || sddm.status === "") return false;
            test(sddm.status === want, "estado " + want + " (es " + sddm.status + ")");
            test(p.infoValue({ id: "sddmStatus" }) === (want === "missing" ? "Not installed" : "Incompatible version"),
                 "la fila de estado lo dice");
            const cap = p.captionOf({ id: "sddmStatus" });
            test(want === "missing" ? cap.indexOf("install --user") >= 0 : cap.indexOf("version 2") >= 0,
                 "el pie explica qué hacer: " + cap);
            test(p.rowReason({ id: "sddmReset", kind: "action" }).length > 0, "las acciones quedan desactivadas");
            test(sddm.rows("notch").length === 0, "sin esquema, sin filas de claves");
        });
        step("captura", () => { w.shot(want + ".png"); });
        for (const t of ["Look", "Behaviour"]) {
            step("pestaña " + t, () => { test(p.selectTab(t), "pestaña " + t); });
            step("captura " + t, () => { w.shot(want + "-" + t.toLowerCase() + ".png"); });
        }
        step("cerrar la página", () => {
            test(p.openPath("shell/general"), "volver a General");
            test(!sddm.watching, "al salir se suelta el servicio");
        });
        return steps;
    }

    step("cargar", () => {
        if (!sddm.ready) return false;
        test(sddm.order.length === 41 && sddm.groups.length === 9, "esquema: 41 claves en 9 grupos");
        test(tabs() === "Overview|Look|Notch and clock|Users and power|Behaviour", "pestañas: " + tabs());
        test(sddm.customCount === 0 && sddm.stamp.length === 32, "configuración vacía con huella");
        test(p.infoValue({ id: "sddmStatus" }).indexOf("Version ") === 0, "estado con versión");
    });
    step("estado del sistema (falso)", () => {
        if (sddm.system === null || sddm.avatar === null) return false;
        test(sddm.system.installed === true && sddm.system.active === false, "instalado y no activo");
        test(p.infoValue({ id: "sddmApplied" }) === "Installed, not in use", "fila: " + p.infoValue({ id: "sddmApplied" }));
        test(sddm.system.inSync === true, "sin configuración, nada que aplicar");
        test(p.rowReason({ id: "sddmApply", kind: "action" }) === "The login screen already has your settings", "Apply desactivado");
        test(p.rowReason({ id: "sddmActivate", kind: "action" }) === "", "Use disponible");
        test(p.rowReason({ id: "sddmDeactivate", kind: "action" }) === "Sumi isn't your login screen", "Restore desactivado");
        test(sddm.avatar.exists === false, "sin avatar");
    });
    shots(w.scenario);
    if (w.scenario !== "real") {
        step("cerrar", () => { test(p.openPath("shell/general") && !sddm.watching, "soltar al salir"); });
        return steps;
    }

    // ── un interruptor de verdad, con el puntero ──
    step("pestaña Notch and clock", () => { test(p.selectTab("Notch and clock"), "pestaña"); });
    step("clic en Seconds", () => {
        const f = w.field("clockSeconds");
        test(f && f.type === "bool", "fila clockSeconds con interruptor");
        w.click(f.children[0].item);
        test(sddm.valueOf("clockSeconds") === true && sddm.isSet("clockSeconds"), "el clic cambia la vista al momento");
    });
    step("guardado", () => idle() && sddm.writeCount >= 1 ? true : false);
    cli("persistido", ["config", "get", "clockSeconds"], d => test(d.value === true && d.set === true, "clockSeconds=true en disco"));

    // ── un deslizador arrastrado: la fila no se rehace y se escribe agrupado ──
    let rowBefore = null, writesBefore = 0;
    step("arrastrar Corner radius", () => {
        const f = w.field("notchRadius");
        test(!!f, "fila notchRadius");
        rowBefore = p.rowItems["sddm:notchRadius"];
        writesBefore = sddm.writeCount;
        const slider = f.children[0].item.children[0];
        const y = slider.height / 2;
        w.pointer.mousePress(slider, 4, y, Qt.LeftButton, Qt.NoModifier, 0);
        for (let i = 1; i <= 12; i++) w.pointer.mouseMove(slider, 4 + i * (slider.width - 8) / 12, y, 0, Qt.LeftButton, Qt.NoModifier);
        w.pointer.mouseRelease(slider, slider.width - 4, y, Qt.LeftButton, Qt.NoModifier, 0);
        test(sddm.valueOf("notchRadius") >= 44, "el arrastre lleva el radio arriba (" + sddm.valueOf("notchRadius") + ")");
    });
    step("arrastre guardado", () => {
        if (!idle() || sddm.writeCount === writesBefore) return false;
        test(p.rowItems["sddm:notchRadius"] === rowBefore, "la fila sobrevive al arrastre (no se recrea)");
        test(sddm.writeCount - writesBefore === 1, "doce movimientos, una escritura (" + (sddm.writeCount - writesBefore) + ")");
    });
    cli("radio en disco", ["config", "get", "notchRadius"], d => test(d.value === sddm.valueOf("notchRadius"), "notchRadius en disco = vista"));

    // ── teclado: la fila de Format con → ──
    step("teclado en Format", () => {
        test(p.openPath("shell/sddm/sddm:clockFormat"), "ruta a la fila de Format");
        p.setZone("content");
        test(p.currentRowId() === "sddm:clockFormat", "foco en Format (" + p.currentRowId() + ")");
        w.key(Qt.Key_Right);
        test(sddm.valueOf("clockFormat") === "12h", "→ cambia a 12 h");
    });
    step("teclado guardado", () => idle());
    cli("formato en disco", ["config", "get", "clockFormat"], d => test(d.value === "12h", "clockFormat=12h en disco"));

    // ── restablecer una clave con el botón de la fila ──
    step("restablecer Seconds", () => {
        const row = p.rowItems["sddm:clockSeconds"];
        test(row && row.custom === true, "la fila se marca como personalizada");
        row.resetRequested();
        test(!sddm.isSet("clockSeconds"), "restablecer la vuelve al defecto");
    });
    step("restablecido guardado", () => idle());

    // ── un cambio desde la terminal entre medias: no se pisa ──
    cli("cambio externo", ["config", "set", "accentColor=#ff8800"], d => test(d.ok === true, "otra parte cambia el acento"));
    step("escritura con la huella vieja", () => { sddm.set("notchRadius", 30); });
    step("conflicto detectado", () => {
        if (!idle()) return false;
        test(sddm.notice.indexOf("Changed outside") === 0, "aviso de conflicto: " + sddm.notice);
        test(sddm.valueOf("accentColor") === "#ff8800", "se recarga lo de fuera");
        test(sddm.valueOf("notchRadius") !== 30, "el cambio con huella vieja no se escribe");
    });
    cli("acento conservado", ["config", "get", "accentColor"], d => test(d.value === "#ff8800", "el cambio externo sigue en disco"));

    // ── un valor que la CLI rechaza ──
    step("valor inválido", () => { sddm.set("fontFamily", "Bad;Name"); });
    step("rechazo", () => {
        if (!idle()) return false;
        test(sddm.error.length > 0, "error visible: " + sddm.error);
        test(sddm.valueOf("fontFamily") === "", "la vista vuelve a lo guardado");
        test(p.captionOf({ id: "sddmStatus" }) === sddm.error, "el estado enseña el error");
    });

    // ── wallpaper ──
    step("poner wallpaper", () => { sddm.setWallpaper(w.home + "/pic.png"); });
    step("wallpaper preparado", () => {
        if (!idle()) return false;
        test(sddm.valueOf("background") === "backgrounds/user.png", "background=backgrounds/user.png");
        test(sddm.error === "", "sin error");
    });
    step("vista previa con wallpaper", () => {
        if (sddm.previewStale) return false;
        test(p.selectTab("Look"), "pestaña Look");
    }, 30000);
    step("captura con wallpaper", () => { w.shot("real-look-wallpaper.png"); });
    step("pestaña Overview", () => { test(p.selectTab("Overview"), "Overview"); });
    step("captura Overview con cambios", () => { if (sddm.previewStale) return false; w.shot("real-overview-changed.png"); }, 30000);

    // ── restablecer todo (dos pulsaciones) y deshacer ──
    let before = 0;
    step("reset armado", () => {
        before = sddm.customCount;
        test(before >= 3, "hay cambios (" + before + ")");
        p.runAction("sddmReset");
        test(sddm.resetArmed && sddm.customCount === before, "la primera pulsación sólo arma");
        test(p.captionOf({ id: "sddmReset" }).indexOf("Press again") === 0, "el pie lo pide");
    });
    step("reset", () => { p.runAction("sddmReset"); });
    step("reset hecho", () => { if (!idle()) return false; test(sddm.customCount === 0, "todo al defecto"); });
    step("restore", () => { p.runAction("sddmRestore"); });
    step("restore hecho", () => { if (!idle()) return false; test(sddm.customCount === before, "vuelve lo de antes"); });

    // ── el sistema (falso): aplicar, usar y restaurar, sin pkexec real ──
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
    step("captura Overview en uso", () => { test(p.selectTab("Overview"), "Overview"); });
    step("captura en uso", () => { if (sddm.previewStale) return false; w.shot("real-overview-in-use.png"); }, 30000);
    step("Restore", () => { p.runAction("sddmDeactivate"); p.runAction("sddmDeactivate"); test(sddm.systemBusy === "deactivate", "restaurando"); });
    step("restaurado", () => {
        if (sddm.systemBusy !== "" || !idle() || !sddm.system || sddm.system.active) return false;
        test(sddm.notice.indexOf("Back to orbital") === 0, "aviso: " + sddm.notice);
        test(p.infoValue({ id: "sddmApplied" }) === "Installed, not in use", "otra vez sin usar");
    });

    // ── avatar (AccountsService falso) ──
    step("pestaña Users and power", () => { test(p.selectTab("Users and power"), "pestaña"); });
    step("fila del avatar", () => {
        const row = p.rowItems["sddm:avatar"];
        test(!!row && row.custom === false, "fila Avatar sin personalizar");
        test(p.captionOf({ id: "sddm:avatar", key: "avatar" }).indexOf("your initials are shown") > 0, "pie sin avatar");
        sddm.setAvatar(w.home + "/pic.png");
    });
    step("avatar puesto", () => {
        if (!idle() || !sddm.avatar || !sddm.avatar.exists) return false;
        test(p.rowItems["sddm:avatar"].custom === true, "la fila se marca");
        test(sddm.notice === "Avatar saved", "aviso: " + sddm.notice + " / " + sddm.error);
    });
    step("captura con avatar", () => { w.shot("real-users-avatar.png"); });
    step("quitar avatar", () => { p.rowItems["sddm:avatar"].resetRequested(); });
    step("avatar quitado", () => {
        if (!idle() || !sddm.avatar || sddm.avatar.exists) return false;
        test(p.rowItems["sddm:avatar"].custom === false, "fila sin marca");
    });

    // ── la ventana de prueba: sólo se arma (abrirla tomaría el teclado) ──
    step("test window armado", () => {
        p.runAction("sddmTry");
        test(sddm.tryArmed, "Open pide confirmación");
        test(p.captionOf({ id: "sddmTry" }).indexOf("takes the keyboard") > 0, "avisa del teclado");
    });

    step("cerrar la página", () => {
        test(p.openPath("shell/general"), "volver a General");
        test(!sddm.watching && !sddm.tryArmed, "al salir se suelta el servicio y se desarma");
    });
    return steps;
}
