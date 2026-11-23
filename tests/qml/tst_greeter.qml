pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import "../../theme/sumi/components"
import "../../tools/harness"

/*
 * Comportamiento del Greeter con dobles de SDDM: teclado, foco, autenticación, errores, energía,
 * sesiones, usuarios y configuración inválida. Ejecutar con:
 *   QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    id: tc
    name: "Greeter"
    when: windowShown
    visible: true  // TestCase es invisible por defecto: sus hijos heredarían visible=false
    width: 1280
    height: 800

    Component {
        id: backendC
        MockBackend {}
    }
    Component {
        id: usersC
        MockUsers {}
    }
    Component {
        id: sessionsC
        MockSessions {}
    }
    Component {
        id: keyboardC
        MockKeyboard {}
    }
    Component {
        id: greeterC
        Greeter {
            width: tc.width
            height: tc.height
        }
    }

    property var be
    property var us
    property var ss
    property var kb
    property var g

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
    function pw() {
        return find(g, "passwordField");
    }
    function un() {
        return find(g, "usernameField");
    }

    /** Monta un Greeter nuevo. `cfg` se mezcla sobre {animations:false}. */
    function make(opts) {
        opts = opts || {};
        be = createTemporaryObject(backendC, tc);
        us = createTemporaryObject(usersC, tc, { lastUser: opts.lastUser !== undefined ? opts.lastUser : "bruno" });
        us.fill(opts.users !== undefined ? opts.users : 3, opts.icon);
        ss = createTemporaryObject(sessionsC, tc, { lastIndex: opts.lastSession !== undefined ? opts.lastSession : 1 });
        ss.fill(opts.sessions !== undefined ? opts.sessions : ["Hyprland", "Hyprland (uwsm-managed)", "Plasma"]);
        kb = createTemporaryObject(keyboardC, tc);
        for (const k in (opts.backend || {}))
            be[k] = opts.backend[k];
        g = createTemporaryObject(greeterC, tc, {
            users: us, sessions: ss, backend: be, keyboardState: kb,
            primary: opts.primary !== undefined ? opts.primary : true,
            cfg: Object.assign({ "animations": "false" }, opts.cfg || {})
        });
        verify(g !== null);
        // init() se ejecuta con Qt.callLater
        tryCompare(g, "ready", true);
        compare(g.userIndex, opts.expectUser !== undefined ? opts.expectUser : (opts.users === 0 ? -1 : 1));
        g.forceActiveFocus();
        return g;
    }
    /**
     * Clic tras resolver la disposición: con el bucle de render de OpenGL el Row puede no haberse
     * colocado aún (polish pendiente) y el mosaico seguiría en x=0, encima de otro. Una persona no
     * puede hacer clic antes del primer fotograma, así que esperar es lo realista.
     */
    function clickItem(item) {
        verify(item !== null);
        for (let p = item.parent; p; p = p.parent)
            tryVerify(() => !isPolishScheduled(p), 2000);
        mouseClick(item);
    }
    function typeText(t) {
        for (let i = 0; i < t.length; i++)
            keyClick(t.charAt(i));
    }

    // ── Estado inicial ──────────────────────────────────────────────────────────────────
    function test_initial_state() {
        make();
        compare(g.notchMode, "compact");
        compare(g.authState, "idle");
        compare(g.currentLogin, "bruno", "lastUser preselected");
        compare(g.sessionIndex, 1, "sessionModel.lastIndex preselected");
        compare(g.manualEntry, false);
        verify(!find(g, "suspendButton").visible, "suspend hidden by default");
        verify(find(g, "poweroffButton").visible === false, "power buttons live in the (hidden) expanded page");
    }

    function test_last_user_unknown_falls_back_to_index() {
        make({ lastUser: "nobody", expectUser: 0 });
        compare(g.userIndex, 0);
    }

    function test_start_expanded_option() {
        make({ cfg: { "notchStartExpanded": "true" } });
        tryCompare(g, "notchMode", "expanded");
        tryVerify(() => pw().input.activeFocus);
    }

    // ── Teclado y foco ──────────────────────────────────────────────────────────────────
    function test_typing_in_compact_expands_and_keeps_character() {
        make();
        keyClick("s");
        compare(g.notchMode, "expanded");
        compare(pw().text.length, 1, "first keystroke not lost");
        tryVerify(() => pw().input.activeFocus, 1000, "password field focused");
        typeText("ecret");
        compare(pw().text.length, 6);
    }

    function test_enter_in_compact_expands_without_login() {
        make();
        keyClick(Qt.Key_Return);
        compare(g.notchMode, "expanded");
        compare(be.loginCount, 0);
    }

    function test_escape_clears_then_collapses() {
        make();
        typeText("abc");
        keyClick(Qt.Key_Escape);
        compare(pw().text, "");
        compare(g.notchMode, "expanded");
        verify(!pw().input.canUndo, "undo history wiped");
        keyClick(Qt.Key_Escape);
        compare(g.notchMode, "compact");
    }

    function test_tab_reaches_session_and_power_controls() {
        make();
        g.expand();
        tryVerify(() => pw().input.activeFocus);
        keyClick(Qt.Key_Tab);
        verify(find(g, "sessionButton").activeFocus, "Tab → session");
        keyClick(Qt.Key_Tab);
        verify(find(g, "rebootButton").activeFocus, "Tab → restart");
        keyClick(Qt.Key_Tab);
        verify(find(g, "poweroffButton").activeFocus, "Tab → shut down");
        keyClick(Qt.Key_Tab);
        verify(find(g, "userStrip").activeFocus, "Tab → user strip");
    }

    // ── Autenticación ───────────────────────────────────────────────────────────────────
    function test_enter_submits_once_with_selected_session() {
        make();
        typeText("hunter22");
        keyClick(Qt.Key_Return);
        compare(be.loginCount, 1);
        compare(be.lastUser, "bruno");
        compare(be.lastPasswordLength, 8);
        compare(be.lastSession, 1);
        compare(g.authState, "authenticating");
        verify(pw().readOnly, "field read-only while authenticating");
        keyClick(Qt.Key_Return);
        g.submit();
        compare(be.loginCount, 1, "no double submit");
        verify(!find(g, "poweroffButton").enabled, "power disabled while authenticating");
    }

    function test_empty_password_is_not_submitted() {
        make();
        g.expand();
        keyClick(Qt.Key_Return);
        compare(be.loginCount, 0);
        compare(g.messageKind, "info");
        verify(g.message.length > 0);
    }

    function test_failed_login_wipes_password_and_shows_error() {
        make();
        typeText("wrong");
        keyClick(Qt.Key_Return);
        be.loginFailed();
        compare(g.authState, "failed");
        compare(pw().text, "");
        verify(!pw().input.canUndo, "previous password not recoverable with undo");
        compare(g.messageKind, "error");
        verify(find(g, "messageRow").visible);
        tryVerify(() => pw().input.activeFocus, 1000, "focus back on password");
        verify(!pw().readOnly);
        keyClick("x");
        compare(g.message, "", "typing clears the error");
        compare(g.authState, "idle");
        keyClick(Qt.Key_Return);
        compare(be.loginCount, 2, "can retry");
    }

    function test_succeeded_login_wipes_password() {
        make();
        typeText("right");
        keyClick(Qt.Key_Return);
        be.loginSucceeded();
        compare(g.authState, "succeeded");
        compare(pw().text, "");
        g.submit();
        compare(be.loginCount, 1);
    }

    function test_information_message_is_sanitized() {
        make();
        g.expand();
        be.informationMessage("Password expires\nsoon\u0007");
        compare(g.messageKind, "info");
        compare(g.message, "Password expires soon");
    }

    function test_auth_timeout_reenables_form() {
        make({ cfg: { "authTimeout": "5" } });
        typeText("pw");
        keyClick(Qt.Key_Return);
        compare(g.authState, "authenticating");
        tryCompare(g, "authState", "idle", 7000);
        compare(g.messageKind, "error");
        verify(!pw().readOnly);
    }

    function test_backend_missing_is_reported() {
        make();
        g.backend = null;
        typeText("pw");
        keyClick(Qt.Key_Return);
        compare(g.authState, "idle");
        compare(g.messageKind, "error");
    }

    function test_no_sessions_blocks_login() {
        make({ sessions: [] });
        compare(g.sessionCount, 0);
        typeText("pw");
        keyClick(Qt.Key_Return);
        compare(be.loginCount, 0);
        compare(g.messageKind, "error");
        verify(!find(g, "sessionButton").enabled);
    }

    // ── Usuarios ────────────────────────────────────────────────────────────────────────
    function test_switching_user_wipes_password() {
        make();
        typeText("secret");
        g.selectUser(2, false);
        compare(g.currentLogin, "chen");
        compare(pw().text, "");
        verify(!pw().input.canUndo);
        tryVerify(() => pw().input.activeFocus);
    }

    function test_user_strip_keyboard() {
        make();
        const strip = find(g, "userStrip");
        strip.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(g.userIndex, 2);
        verify(strip.activeFocus, "focus stays on the strip while browsing");
        keyClick(Qt.Key_Right);
        compare(g.userIndex, 0, "wraps (no 'Other' tile by default)");
        keyClick(Qt.Key_Left);
        compare(g.userIndex, 2);
        keyClick("p");
        tryVerify(() => pw().input.activeFocus);
        compare(pw().text.length, 1, "typing on the strip goes to the password");
    }

    function test_click_user_tile() {
        make();
        const tile = find(g, "userTile0");
        verify(tile !== null);
        clickItem(tile);
        compare(g.userIndex, 0);
        compare(g.notchMode, "expanded");
    }

    function test_user_without_password() {
        // MockUsers: el índice 4 («emeka») no necesita contraseña.
        make({ users: 5 });
        g.selectUser(4, false);
        compare(g.needsPassword, false);
        verify(!pw().visible);
        verify(find(g, "loginButton").visible);
        tryVerify(() => find(g, "loginButton").activeFocus);
        keyClick(Qt.Key_Return);
        compare(be.loginCount, 1);
        compare(be.lastPasswordLength, 0);
    }

    function test_manual_entry_when_no_users() {
        make({ users: 0 });
        compare(g.manualEntry, true);
        verify(!find(g, "userStrip").visible);
        keyClick("r");
        compare(g.notchMode, "expanded");
        compare(un().text, "r", "first character goes to the user name");
        tryVerify(() => un().input.activeFocus);
        typeText("oot");
        keyClick(Qt.Key_Return);
        tryVerify(() => pw().input.activeFocus, 1000, "Enter on user name → password");
        keyClick(Qt.Key_Return);
        compare(be.loginCount, 0, "empty password refused");
        typeText("pw");
        keyClick(Qt.Key_Return);
        compare(be.loginCount, 1);
        compare(be.lastUser, "root");
        be.loginFailed();
        compare(un().text, "root", "user name kept after failure");
        compare(pw().text, "");
    }

    function test_manual_entry_requires_user_name() {
        make({ users: 0 });
        g.expand();
        g.submit();
        compare(be.loginCount, 0);
        compare(g.messageKind, "error");
    }

    function test_manual_never_cannot_lock_out() {
        make({ users: 0, cfg: { "manualUser": "never" } });
        compare(g.manualEntry, true, "no users → manual entry even with manualUser=never");
    }

    function test_other_tile_when_manual_always() {
        make({ cfg: { "manualUser": "always" } });
        const other = find(g, "userTileOther");
        verify(other.visible);
        clickItem(other);
        compare(g.manualEntry, true);
        compare(g.currentLogin, "");
    }

    function test_avatar_fallbacks() {
        ignoreWarning(new RegExp("Cannot open: file:///nonexistent/avatar.png"));
        make({ icon: "/nonexistent/avatar.png" });
        const tile = find(g, "userTile0");
        verify(tile !== null);
        // la imagen falla → iniciales; ningún error lanzado
        wait(100);
        make({ icon: "" });
        verify(find(g, "userTile0") !== null);
    }

    function test_strip_hidden_single_user_auto() {
        make({ users: 1, lastUser: "alice", expectUser: 0, cfg: { "userStrip": "auto" } });
        verify(!find(g, "userStrip").visible);
        make({ users: 1, lastUser: "alice", expectUser: 0 });
        verify(find(g, "userStrip").visible, "default 'always' shows a single user");
    }

    // ── Sesiones ────────────────────────────────────────────────────────────────────────
    function test_session_picker_keyboard() {
        make();
        g.expand();
        g.openSessions();
        compare(g.notchMode, "sessions");
        tryVerify(() => find(g, "sessionView").activeFocus);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        compare(g.sessionIndex, 2);
        compare(g.notchMode, "expanded");
        tryVerify(() => pw().input.activeFocus);
        g.openSessions();
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Escape);
        compare(g.sessionIndex, 2, "Esc keeps the previous session");
        compare(g.notchMode, "expanded");
    }

    // ── Energía ─────────────────────────────────────────────────────────────────────────
    function test_power_requires_confirmation_and_cancel_is_default() {
        make();
        g.expand();
        g.requestPower("poweroff");
        compare(g.notchMode, "confirm");
        compare(be.powerCalls.length, 0, "nothing happens before confirming");
        tryVerify(() => find(g, "cancelButton").activeFocus, 1000, "Cancel has the focus");
        keyClick(Qt.Key_Return);
        compare(g.notchMode, "expanded");
        compare(be.powerCalls.length, 0, "Enter on the default button cancels");
    }

    function test_power_confirmed_with_keyboard() {
        make();
        g.expand();
        g.requestPower("reboot");
        tryVerify(() => find(g, "cancelButton").activeFocus);
        keyClick(Qt.Key_Right);
        verify(find(g, "confirmButton").activeFocus);
        keyClick(Qt.Key_Return);
        compare(be.powerCalls, ["reboot"]);
    }

    function test_power_escape_cancels() {
        make();
        g.expand();
        g.requestPower("poweroff");
        keyClick(Qt.Key_Escape);
        compare(g.notchMode, "expanded");
        compare(be.powerCalls.length, 0);
    }

    function test_power_button_click_opens_confirmation() {
        make();
        g.expand();
        clickItem(find(g, "poweroffButton"));
        compare(g.notchMode, "confirm");
        compare(g.pendingPower, "poweroff");
        clickItem(find(g, "confirmButton"));
        compare(be.powerCalls, ["powerOff"]);
    }

    function test_unavailable_power_actions_hidden() {
        make({ backend: { canPowerOff: false, canReboot: false } });
        g.expand();
        verify(!find(g, "poweroffButton").visible);
        verify(!find(g, "rebootButton").visible);
        g.requestPower("poweroff");
        compare(g.notchMode, "expanded", "requestPower ignored when unavailable");
    }

    function test_suspend_opt_in() {
        make({ cfg: { "showSuspend": "true" } });
        g.expand();
        verify(find(g, "suspendButton").visible);
        make({ cfg: { "showSuspend": "true" }, backend: { canSuspend: false } });
        g.expand();
        verify(!find(g, "suspendButton").visible, "hidden if SDDM says it cannot suspend");
    }

    // ── Indicadores, inactividad y pantallas ────────────────────────────────────────────
    function test_caps_lock_indicator() {
        make();
        g.expand();
        verify(!find(g, "capsIndicator").visible);
        kb.capsLock = true;
        verify(find(g, "capsIndicator").visible);
    }

    function test_idle_collapse_wipes_password() {
        make({ cfg: { "notchIdleCollapse": "5" } });
        typeText("half");
        tryCompare(g, "notchMode", "compact", 7000);
        compare(pw().text, "");
    }

    function test_secondary_screen_primary_mode() {
        make({ primary: false, cfg: { "multiMonitor": "primary" } });
        verify(!find(g, "notch").visible);
        verify(!find(g, "userStrip").visible);
        keyClick("a");
        compare(g.notchMode, "compact");
        make({ primary: false });
        verify(find(g, "notch").visible, "default 'all' shows login on every screen");
    }

    // ── Configuración ───────────────────────────────────────────────────────────────────
    function test_invalid_config_falls_back() {
        make({ cfg: {
                "notchExpandedWidth": "abc", "notchRadius": "-40", "accentColor": "#zzz", "blurRadius": "1e9",
                "clockFormat": "25h", "userStrip": "sideways", "animations": "maybe", "uiScale": "0",
                "background": "../../etc/shadow", "showSuspend": "yes"
            } });
        const st = g.style;
        compare(st.notchExpandedWidth, 440);
        compare(st.notchRadius, 4, "clamped to minimum");
        compare(st.accent.toString(), "#a9bdff");
        compare(st.blurRadius, 100);
        compare(st.clock24h, true);
        compare(st.userStrip, "always");
        compare(st.animate, true, "unparseable bool → default");
        compare(st.uiScale, 0.5);
        compare(st.background.toString(), "", "path with .. rejected");
        compare(st.showSuspend, true);
    }

    function test_config_list_values_are_joined() {
        // QSettings convierte «dddd, d MMMM» sin comillas en una lista
        make({ cfg: { "dateFormat": ["dddd", "d MMMM"] } });
        compare(g.style.dateFormat, "dddd, d MMMM");
    }

    function test_remote_background_rejected() {
        make({ cfg: { "background": "https://example.com/a.jpg" } });
        compare(g.style.background.toString(), "");
        ignoreWarning(new RegExp("Cannot open: file:///nonexistent/wall.jpg"));
        ignoreWarning(new RegExp("background image could not be loaded"));
        make({ cfg: { "background": "/nonexistent/wall.jpg" } });
        tryVerify(() => g.background.wallpaperFailed, 2000);
        verify(!g.background.wallpaperReady);
    }

    function test_animations_off_gives_zero_durations() {
        make();
        compare(g.style.dur(400), 0);
        make({ cfg: { "animations": "true", "animationSpeed": "2" } });
        compare(g.style.dur(400), 200);
    }

    function test_user_strip_appearance_keys() {
        make({ cfg: { "userNames": "false", "userInactiveOpacity": "0.3", "userStripMargin": "120" } });
        const strip = find(g, "userStrip");
        compare(strip.anchors.bottomMargin, g.style.px(120));
        const tile = find(g, "userTile0");
        tryCompare(tile, "opacity", 0.3);
        compare(find(g, "userTile1").opacity, 1, "selected tile stays opaque");
    }

    function test_clock_offset_and_font_scale() {
        make();
        const clock = find(g, "clock");
        const x0 = clock.x;
        const y0 = clock.y;
        const field = pw().input;
        const fs0 = field.font.pixelSize;
        make({ cfg: { "clockOffsetX": "-100", "clockOffsetY": "40", "fontScale": "1.5" } });
        const clock2 = find(g, "clock");
        compare(clock2.x, x0 - g.style.px(100));
        compare(clock2.y, y0 + g.style.px(40));
        fuzzyCompare(pw().input.font.pixelSize, fs0 * 1.5, 1);
    }

    function test_scale_follows_resolution() {
        make();
        g.width = 3840;
        g.height = 2160;
        compare(g.style.unit, 2);
        g.width = 1366;
        g.height = 768;
        verify(Math.abs(g.style.unit - 0.7111) < 0.001);
        g.width = 1080;
        g.height = 1920;
        compare(g.style.unit, 1, "portrait keeps the landscape scale");
    }
}
