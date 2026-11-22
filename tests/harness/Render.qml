import QtQuick
import QtQuick.Window
import "../../theme/sumi/components"

/*
 * Captura un escenario del Greeter a PNG con datos simulados (sin SDDM, sin ventana visible si se
 * lanza con QT_QPA_PLATFORM=offscreen). Uso:
 *
 *   qml6 tests/harness/Render.qml -- --scenario=failed --size=1920x1080 --out=/ruta.png \
 *        [--users=3] [--config='{"clockFormat":"12h"}']
 *
 * Las animaciones van apagadas salvo que la configuración diga lo contrario: capturas estables.
 */
Window {
    id: win

    readonly property var opts: parse(Qt.application.arguments)

    function parse(argv) {
        const o = { scenario: "compact", width: 1920, height: 1080, out: "", users: 3, config: {} };
        for (let i = 0; i < argv.length; i++) {
            const m = /^--([a-z]+)=(.*)$/.exec(argv[i]);
            if (!m)
                continue;
            if (m[1] === "size") {
                const wh = m[2].split("x");
                o.width = Number(wh[0]);
                o.height = Number(wh[1]);
            } else if (m[1] === "users") {
                o.users = Number(m[2]);
            } else if (m[1] === "config") {
                o.config = JSON.parse(m[2]);
            } else {
                o[m[1]] = m[2];
            }
        }
        if (o.scenario === "manual")
            o.users = 0;
        if (o.scenario === "single" || o.scenario === "nopass-single")
            o.users = 1;
        if (o.scenario === "many")
            o.users = 10;
        if (o.scenario === "nopass")
            o.users = 5;
        return o;
    }

    width: opts.width
    height: opts.height
    visible: true
    color: "black"

    MockBackend {
        id: mockBackend
    }
    MockKeyboard {
        id: kb
    }
    MockUsers {
        id: mockUsers
        lastUser: "alice"
        Component.onCompleted: fill(win.opts.users)
    }
    MockSessions {
        id: mockSessions
        lastIndex: 0
        Component.onCompleted: fill(win.opts.scenario === "nosessions" ? [] : ["Hyprland", "Hyprland (uwsm-managed)", "Plasma (Wayland)"])
    }

    Greeter {
        id: g
        anchors.fill: parent
        focus: true
        users: mockUsers
        sessions: mockSessions
        backend: mockBackend
        keyboardState: kb
        primary: win.opts.scenario !== "secondary"
        cfg: Object.assign({ "animations": "false" },
                           win.opts.scenario === "secondary" ? { "multiMonitor": "primary" } : {},
                           win.opts.config)
    }

    function find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) {
            const r = find(kids[i], name);
            if (r)
                return r;
        }
        return null;
    }
    function typePassword(text) {
        find(g, "passwordField").input.text = text;
    }

    function apply(s) {
        switch (s) {
        case "compact":
        case "single":
        case "many":
        case "secondary":
            break;
        case "expanded":
        case "manual":
        case "nosessions":
            g.expand();
            break;
        case "typing":
            g.expand();
            typePassword("hunter22");
            break;
        case "caps":
            kb.capsLock = true;
            g.expand();
            typePassword("hun");
            break;
        case "authenticating":
            g.expand();
            typePassword("hunter22");
            g.submit();
            break;
        case "failed":
            g.expand();
            typePassword("hunter22");
            g.submit();
            mockBackend.loginFailed();
            break;
        case "info":
            g.expand();
            mockBackend.informationMessage("Your password will expire in 3 days.");
            break;
        case "sessions":
            g.expand();
            g.openSessions();
            break;
        case "confirm":
            g.expand();
            g.requestPower("poweroff");
            break;
        case "other":
            g.selectUser(-1, false);
            break;
        case "nopass":
            g.selectUser(4, false);
            break;
        default:
            console.warn("render: unknown scenario " + s);
            Qt.exit(2);
        }
    }

    Timer {
        interval: 400
        running: true
        onTriggered: {
            win.apply(win.opts.scenario);
            grabTimer.start();
        }
    }
    Timer {
        id: grabTimer
        interval: 700
        onTriggered: {
            if (win.opts.out === "") {
                console.warn("render: missing --out");
                Qt.exit(2);
                return;
            }
            win.contentItem.grabToImage(result => {
                const ok = result.saveToFile(win.opts.out);
                console.info("render: " + (ok ? "saved " : "FAILED ") + win.opts.out);
                Qt.exit(ok ? 0 : 1);
            });
        }
    }
}
