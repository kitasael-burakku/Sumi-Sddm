pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window

/*
 * La pantalla de inicio de sesión completa, sin dependencias de SDDM: todo llega por propiedades.
 * `Main.qml` la conecta al contexto real del greeter; las pruebas, a objetos simulados con la
 * misma forma (tests/harness).
 *
 *   users        modelo con roles name, realName, icon, needsPassword (+ lastUser, lastIndex)
 *   sessions     modelo con roles name, file (+ lastIndex)
 *   backend      login(user, password, sessionIndex), powerOff(), reboot(), suspend(),
 *                canPowerOff/canReboot/canSuspend, señales loginSucceeded/loginFailed/
 *                informationMessage(message)
 *   keyboardState capsLock
 *   cfg          mapa de configuración (claves de theme.conf)
 *
 * Seguridad: la contraseña sólo vive en el TextInput y en la llamada a `backend.login`. No se
 * registra, no se copia a otras propiedades, y se borra (con su historial de deshacer) al
 * fallar, al acertar, al cambiar de usuario, con Esc y al recogerse por inactividad.
 */
FocusScope {
    id: root

    property var users: null
    property var sessions: null
    property var backend: null
    property var keyboardState: null
    property var cfg: null
    property bool primary: true

    // ── Estado (público: lo leen las pruebas) ───────────────────────────────────────────
    property int userIndex: -1
    property bool manualEntry: false
    property int sessionIndex: 0
    /** compact | expanded | sessions | confirm */
    property string notchMode: "compact"
    /** idle | authenticating | failed | succeeded */
    property string authState: "idle"
    property string message: ""
    /** "" | error | info */
    property string messageKind: ""
    /** "" | poweroff | reboot | suspend */
    property string pendingPower: ""
    /** true cuando init() eligió usuario y sesión iniciales. */
    property bool ready: false

    readonly property alias style: st
    readonly property alias background: bg
    readonly property bool loginUi: primary || st.multiMonitor === "all"

    Style {
        id: st
        source: root.cfg
        screenWidth: root.width > 0 ? root.width : 1920
        screenHeight: root.height > 0 ? root.height : 1080
        softwareRenderer: root.GraphicsInfo.api === GraphicsInfo.Software
        bundledFont: interFont.status === FontLoader.Ready ? interFont.name : ""
    }

    FontLoader {
        id: interFont
        source: Qt.resolvedUrl("../assets/fonts/InterVariable.ttf")
    }

    // ── Espejo de los modelos (acceso por índice desde JS) ──────────────────────────────
    component UserEntry: QtObject {
        required property var model
        readonly property string name: model.name ?? ""
        readonly property string realName: model.realName ?? ""
        readonly property string icon: model.icon ?? ""
        readonly property bool needsPassword: model.needsPassword ?? true
    }
    component SessionEntry: QtObject {
        required property var model
        readonly property string name: model.name ?? ""
        readonly property string file: model.file ?? ""
    }
    Instantiator {
        id: userList
        model: root.users
        delegate: UserEntry {}
        function entry(i: int): UserEntry {
            return objectAt(i) as UserEntry;
        }
    }
    Instantiator {
        id: sessionList
        model: root.sessions
        delegate: SessionEntry {}
        function entry(i: int): SessionEntry {
            return objectAt(i) as SessionEntry;
        }
    }

    readonly property int userCount: userList.count
    readonly property int sessionCount: sessionList.count
    readonly property UserEntry currentUser: !manualEntry && userIndex >= 0 && userIndex < userCount ? userList.entry(userIndex) : null
    readonly property string currentLogin: manualEntry ? usernameField.text.trim() : (currentUser ? currentUser.name : "")
    readonly property string displayName: manualEntry ? "" : currentUser ? (currentUser.realName !== "" ? currentUser.realName : currentUser.name) : ""
    readonly property bool needsPassword: manualEntry || !currentUser || currentUser.needsPassword
    /** Sin usuarios listados la entrada manual es obligatoria, diga lo que diga `manualUser`. */
    readonly property bool manualAllowed: userCount === 0 || st.manualUser === "always"
    readonly property string sessionName: {
        const s = sessionIndex >= 0 && sessionIndex < sessionCount ? sessionList.entry(sessionIndex) : null;
        return s ? s.name : "";
    }
    readonly property bool busy: authState === "authenticating" || authState === "succeeded"
    readonly property bool capsLock: !!(keyboardState && keyboardState.capsLock)

    function canDo(kind) {
        if (!backend)
            return false;
        if (kind === "poweroff")
            return st.showShutdown && !!backend.canPowerOff;
        if (kind === "reboot")
            return st.showRestart && !!backend.canReboot;
        if (kind === "suspend")
            return st.showSuspend && !!backend.canSuspend;
        return false;
    }

    // ── Inicialización ──────────────────────────────────────────────────────────────────
    function pickInitialUser() {
        if (userCount === 0) {
            userIndex = -1;
            manualEntry = true;
            return;
        }
        let idx = -1;
        const last = users && users.lastUser !== undefined ? String(users.lastUser) : "";
        for (let i = 0; last !== "" && i < userCount; i++) {
            const u = userList.entry(i);
            if (u && u.name === last)
                idx = i;
        }
        if (idx < 0 && users && users.lastIndex !== undefined && users.lastIndex >= 0 && users.lastIndex < userCount)
            idx = users.lastIndex;
        userIndex = idx < 0 ? 0 : idx;
        manualEntry = false;
    }
    function pickInitialSession() {
        const li = sessions && sessions.lastIndex !== undefined ? Number(sessions.lastIndex) : 0;
        sessionIndex = li >= 0 && li < sessionCount ? li : 0;
    }
    function init() {
        pickInitialUser();
        pickInitialSession();
        if (st.notchStartExpanded && loginUi)
            expand();
        else
            root.forceActiveFocus();
        // Sólo recuentos: nada de nombres ni datos sensibles en el registro.
        console.info("sumi-sddm: ready users=" + userCount + " sessions=" + sessionCount + " primary=" + primary + " clock=" + (st.clock24h ? "24h" : "12h"));
        ready = true;
    }
    Component.onCompleted: Qt.callLater(init)

    Connections {
        target: userList
        function onCountChanged() {
            if (root.userCount === 0 || (!root.manualEntry && (root.userIndex < 0 || root.userIndex >= root.userCount)))
                root.pickInitialUser();
        }
    }
    Connections {
        target: sessionList
        function onCountChanged() {
            if (root.sessionIndex < 0 || root.sessionIndex >= root.sessionCount)
                root.pickInitialSession();
        }
    }

    // ── Acciones ────────────────────────────────────────────────────────────────────────
    function showMessage(text, kind) {
        message = text;
        messageKind = kind;
    }
    function clearMessage() {
        message = "";
        messageKind = "";
    }
    function wipe() {
        passwordField.wipe();
    }
    function primaryField() {
        if (manualEntry && usernameField.text.trim().length === 0)
            return usernameField.input;
        return needsPassword ? passwordField.input : loginButton;
    }
    function focusField() {
        if (notchMode !== "expanded")
            return;
        primaryField().forceActiveFocus();
    }
    function expand() {
        if (!loginUi)
            return;
        if (notchMode !== "expanded") {
            pendingPower = "";
            notchMode = "expanded";
        }
        focusField();
    }
    function collapse() {
        if (busy || !loginUi)
            return;
        wipe();
        clearMessage();
        if (authState === "failed")
            authState = "idle";
        pendingPower = "";
        notchMode = "compact";
        root.forceActiveFocus();
    }
    function selectUser(index, keepFocus) {
        if (busy)
            return;
        if (index === -1) {
            if (!manualAllowed && userCount > 0 && st.manualUser === "never")
                return;
            manualEntry = true;
            userIndex = -1;
            usernameField.wipe();
        } else {
            if (index < 0 || index >= userCount)
                return;
            manualEntry = false;
            userIndex = index;
        }
        wipe();
        clearMessage();
        authState = "idle";
        if (notchMode !== "expanded") {
            pendingPower = "";
            notchMode = "expanded";
        }
        if (!keepFocus)
            focusField();
    }
    function submit() {
        if (busy)
            return;
        if (!backend) {
            showMessage("The login service is unavailable", "error");
            return;
        }
        const login = currentLogin;
        if (login.length === 0) {
            showMessage("Enter your user name", "error");
            usernameField.input.forceActiveFocus();
            return;
        }
        if (sessionCount === 0) {
            showMessage("No desktop sessions are installed", "error");
            return;
        }
        if (needsPassword && passwordField.text.length === 0) {
            showMessage("Enter your password", "info");
            shake.restart();
            passwordField.input.forceActiveFocus();
            return;
        }
        clearMessage();
        authState = "authenticating";
        authTimer.restart();
        try {
            backend.login(login, needsPassword ? passwordField.text : "", sessionIndex);
        } catch (e) {
            authTimer.stop();
            authState = "idle";
            showMessage("The login service is unavailable", "error");
        }
    }
    function openSessions() {
        if (busy || !loginUi)
            return;
        notchMode = "sessions";
        sessionView.currentIndex = Math.max(0, Math.min(sessionIndex, sessionCount - 1));
        sessionView.forceActiveFocus();
    }
    function chooseSession(index) {
        if (index >= 0 && index < sessionCount)
            sessionIndex = index;
        notchMode = "expanded";
        focusField();
    }
    function requestPower(kind) {
        if (busy || !loginUi || !canDo(kind))
            return;
        pendingPower = kind;
        notchMode = "confirm";
        confirmTimer.restart();
        cancelButton.forceActiveFocus();
    }
    function confirmPower() {
        const kind = pendingPower;
        confirmTimer.stop();
        pendingPower = "";
        notchMode = "expanded";
        if (!canDo(kind))
            return;
        if (kind === "poweroff")
            backend.powerOff();
        else if (kind === "reboot")
            backend.reboot();
        else if (kind === "suspend")
            backend.suspend();
        focusField();
    }
    function cancelPower() {
        confirmTimer.stop();
        pendingPower = "";
        notchMode = "expanded";
        focusField();
    }
    function sanitize(text) {
        return String(text).replace(/[\u0000-\u001f\u007f]+/g, " ").trim().slice(0, 240);
    }
    function isPrintable(event) {
        if (event.text.length === 0)
            return false;
        const c = event.text.charCodeAt(0);
        return c >= 32 && c !== 127 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
    }
    /** Reinicia la cuenta de inactividad (actividad del usuario). */
    function poke() {
        if (idleTimer.running)
            idleTimer.restart();
    }

    Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onLoginFailed() {
            authTimer.stop();
            root.authState = "failed";
            root.wipe();
            root.showMessage(root.manualEntry ? "Incorrect user name or password" : "Incorrect password", "error");
            shake.restart();
            if (root.notchMode !== "expanded")
                root.notchMode = "expanded";
            root.focusField();
        }
        function onLoginSucceeded() {
            root.authState = "succeeded";
            root.wipe();
            root.clearMessage();
            authTimer.restart();
        }
        function onInformationMessage(message) {
            root.showMessage(root.sanitize(message), "info");
        }
    }

    Timer {
        id: authTimer
        interval: st.authTimeout * 1000
        onTriggered: {
            if (root.authState === "authenticating") {
                root.authState = "idle";
                root.showMessage("No response from the login service. Try again.", "error");
                root.focusField();
            } else if (root.authState === "succeeded") {
                // SDDM debería haber cerrado el greeter; si sigue aquí, devolver el control.
                root.authState = "idle";
                root.focusField();
            }
        }
    }
    Timer {
        id: idleTimer
        interval: st.notchIdleCollapse * 1000
        running: st.notchIdleCollapse > 0 && root.loginUi && root.notchMode !== "compact" && !root.busy
        onTriggered: root.collapse()
    }
    Timer {
        id: confirmTimer
        interval: 30000
        onTriggered: if (root.notchMode === "confirm") root.cancelPower()
    }

    onNotchModeChanged: poke()
    Connections {
        target: root.Window.window
        ignoreUnknownSignals: true
        function onActiveFocusItemChanged() {
            root.poke();
        }
    }

    // Teclas que nadie más consumió. Compacta: escribir o Intro la expanden.
    Keys.onPressed: event => {
        if (!root.loginUi || root.notchMode !== "compact")
            return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
            root.expand();
            event.accepted = true;
        } else if (root.isPrintable(event)) {
            root.expand();
            const f = root.primaryField();
            if (f.insert)
                f.insert(f.cursorPosition, event.text);
            event.accepted = true;
        }
    }

    // ── Fondo ───────────────────────────────────────────────────────────────────────────
    Background {
        id: bg
        anchors.fill: parent
        style: st
    }

    TapHandler {
        onTapped: {
            if (root.notchMode === "compact")
                root.expand();
            else if (root.notchMode === "expanded")
                root.focusField();
        }
    }
    HoverHandler {
        onPointChanged: root.poke()
    }

    // ── Reloj ───────────────────────────────────────────────────────────────────────────
    Clock {
        id: clock
        style: st
        readonly property real margin: st.px(56)
        readonly property bool atLeft: st.clockPosition.endsWith("left")
        readonly property bool atRight: st.clockPosition.endsWith("right")
        width: Math.min(root.width - 2 * margin, st.px(900) * st.clockScale)
        align: atLeft ? Text.AlignLeft : atRight ? Text.AlignRight : Text.AlignHCenter
        x: atLeft ? margin : atRight ? root.width - width - margin : (root.width - width) / 2
        y: st.clockPosition === "center"
           ? Math.max(root.height * 0.2, (notch.visible ? notch.height : 0) + st.px(40))
           : st.clockPosition.startsWith("top") ? margin : root.height - implicitHeight - margin
        Behavior on y {
            NumberAnimation {
                duration: st.dur(460)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: st.curve
            }
        }
    }

    // ── Usuarios ────────────────────────────────────────────────────────────────────────
    UserStrip {
        id: strip
        objectName: "userStrip"
        style: st
        visible: root.loginUi && st.userStrip !== "never"
                 && (root.userCount > 1 || (root.userCount === 1 && (st.userStrip === "always" || showOther)))
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: st.px(64)
        width: root.width - st.px(64)
        model: root.users
        count: root.userCount
        currentIndex: root.userIndex
        manualEntry: root.manualEntry
        showOther: root.userCount > 0 && root.manualAllowed
        locked: root.busy
        onSelected: (index, fromKeyboard) => root.selectUser(index, fromKeyboard)
        onActivated: root.expand()
        onTyped: text => {
            root.expand();
            const f = root.primaryField();
            if (f.insert)
                f.insert(f.cursorPosition, text);
        }
    }

    // ── Notch ───────────────────────────────────────────────────────────────────────────
    Notch {
        id: notch
        objectName: "notch"
        style: st
        visible: root.loginUi
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0

        readonly property real pad: st.px(20)
        readonly property real contentWidth: st.px(st.notchExpandedWidth) - 2 * pad
        readonly property Item activePage: root.notchMode === "sessions" ? sessionsPage
                                         : root.notchMode === "confirm" ? confirmPage
                                         : root.notchMode === "expanded" ? loginPage : null

        bodyWidth: root.notchMode === "compact" ? st.px(st.notchCompactWidth) : st.px(st.notchExpandedWidth)
        bodyHeight: activePage ? activePage.implicitHeight + st.px(16) + st.px(20) : st.px(st.notchCompactHeight)

        MouseArea {
            anchors.fill: parent
            enabled: root.notchMode === "compact"
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expand()
        }

        component Page: FocusScope {
            property bool active: false
            x: (notch.body.width - width) / 2
            y: st.px(16)
            width: notch.contentWidth
            opacity: active ? 1 : 0
            visible: active || opacity > 0
            enabled: active
            Behavior on opacity {
                NumberAnimation {
                    duration: st.dur(220)
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Compacta: candado y nombre.
        Item {
            objectName: "compactPage"
            anchors.fill: parent
            opacity: root.notchMode === "compact" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation {
                    duration: st.dur(180)
                }
            }
            Row {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -st.px(1)
                spacing: st.px(7)
                Icon {
                    name: "lock"
                    size: st.px(13)
                    stroke: 2
                    color: st.textDim
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.manualEntry ? "Log in" : root.displayName
                    width: Math.min(implicitWidth, notch.bodyWidth - st.px(56))
                    elide: Text.ElideRight
                    color: st.textDim
                    font.family: st.fontFamily
                    font.pixelSize: st.px(12.5)
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Expandida: autenticación.
        Page {
            id: loginPage
            objectName: "loginPage"
            active: root.notchMode === "expanded"
            implicitHeight: loginColumn.implicitHeight

            Column {
                id: loginColumn
                width: parent.width
                spacing: st.px(12)

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.manualEntry ? "Log in" : root.displayName
                    elide: Text.ElideRight
                    color: st.text
                    font.family: st.fontFamily
                    font.pixelSize: st.px(15)
                    font.weight: Font.DemiBold
                }

                InputField {
                    id: usernameField
                    objectName: "usernameField"
                    style: st
                    width: parent.width
                    visible: root.manualEntry
                    icon: "user"
                    placeholder: "User name"
                    readOnly: root.busy
                    onAccepted: passwordField.input.forceActiveFocus()
                    onEscaped: {
                        if (text.length > 0)
                            wipe();
                        else
                            root.collapse();
                    }
                    input.onTextChanged: {
                        root.poke();
                        if (root.messageKind !== "" && !root.busy)
                            root.clearMessage();
                    }
                }

                InputField {
                    id: passwordField
                    objectName: "passwordField"
                    style: st
                    width: parent.width
                    visible: root.needsPassword
                    secret: true
                    icon: "lock"
                    placeholder: "Password"
                    readOnly: root.busy
                    onAccepted: root.submit()
                    onEscaped: {
                        if (text.length > 0)
                            root.wipe();
                        else
                            root.collapse();
                    }
                    input.onTextChanged: {
                        root.poke();
                        if (text.length > 0 && !root.busy) {
                            if (root.authState === "failed")
                                root.authState = "idle";
                            if (root.messageKind !== "")
                                root.clearMessage();
                        }
                    }
                    transform: Translate {
                        id: shakeOffset
                    }

                    Icon {
                        objectName: "capsIndicator"
                        visible: root.capsLock
                        name: "caps"
                        size: st.px(16)
                        color: st.textDim
                        anchors.verticalCenter: parent.verticalCenter
                        Accessible.role: Accessible.StaticText
                        Accessible.name: "Caps Lock is on"
                    }
                    IconButton {
                        id: submitButton
                        objectName: "submitButton"
                        style: st
                        size: st.px(30)
                        icon: root.authState === "succeeded" ? "check" : "arrow-right"
                        label: "Log in"
                        busy: root.authState === "authenticating"
                        fill: passwordField.text.length > 0 ? Qt.rgba(st.accent.r, st.accent.g, st.accent.b, 0.22) : st.fieldHover
                        tint: passwordField.text.length > 0 ? st.accent : st.textDim
                        activeFocusOnTab: false
                        onClicked: root.submit()
                    }
                }

                PillButton {
                    id: loginButton
                    objectName: "loginButton"
                    style: st
                    visible: !root.needsPassword
                    anchors.horizontalCenter: parent.horizontalCenter
                    kind: "primary"
                    text: root.authState === "authenticating" ? "Logging in…" : "Log In"
                    minWidth: st.px(140)
                    onClicked: root.submit()
                    Keys.onEscapePressed: root.collapse()
                }

                Row {
                    id: messageRow
                    objectName: "messageRow"
                    visible: root.message !== ""
                    width: parent.width
                    spacing: st.px(8)
                    Icon {
                        visible: root.messageKind === "error"
                        name: "alert"
                        size: st.px(15)
                        color: st.error
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        width: parent.width - (root.messageKind === "error" ? st.px(23) : 0)
                        horizontalAlignment: root.messageKind === "error" ? Text.AlignLeft : Text.AlignHCenter
                        text: root.message
                        color: root.messageKind === "error" ? st.error : st.textDim
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.family: st.fontFamily
                        font.pixelSize: st.px(13)
                        Accessible.role: Accessible.AlertMessage
                        Accessible.name: root.message
                    }
                }

                Item {
                    width: parent.width
                    height: st.px(32)

                    PillButton {
                        id: sessionButton
                        objectName: "sessionButton"
                        style: st
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "monitor"
                        chevron: true
                        text: root.sessionCount > 0 ? root.sessionName : "No sessions"
                        maxWidth: parent.width - powerRow.width - st.px(16)
                        minWidth: st.px(80)
                        enabled: root.sessionCount > 0 && !root.busy
                        onClicked: root.openSessions()
                        Accessible.name: "Session: " + text
                    }

                    Row {
                        id: powerRow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: st.px(8)

                        IconButton {
                            objectName: "suspendButton"
                            style: st
                            size: st.px(32)
                            visible: root.canDo("suspend")
                            enabled: !root.busy
                            icon: "moon"
                            label: "Sleep"
                            onClicked: root.requestPower("suspend")
                        }
                        IconButton {
                            objectName: "rebootButton"
                            style: st
                            size: st.px(32)
                            visible: root.canDo("reboot")
                            enabled: !root.busy
                            icon: "restart"
                            label: "Restart"
                            onClicked: root.requestPower("reboot")
                        }
                        IconButton {
                            objectName: "poweroffButton"
                            style: st
                            size: st.px(32)
                            visible: root.canDo("poweroff")
                            enabled: !root.busy
                            icon: "power"
                            label: "Shut Down"
                            onClicked: root.requestPower("poweroff")
                        }
                    }
                }
            }
        }

        // Selector de sesión.
        Page {
            id: sessionsPage
            objectName: "sessionsPage"
            active: root.notchMode === "sessions"
            implicitHeight: sessionsColumn.implicitHeight
            Keys.onEscapePressed: root.chooseSession(root.sessionIndex)

            Column {
                id: sessionsColumn
                width: parent.width
                spacing: st.px(10)

                Item {
                    width: parent.width
                    height: st.px(28)
                    IconButton {
                        style: st
                        size: st.px(28)
                        icon: "back"
                        label: "Back"
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        activeFocusOnTab: false
                        onClicked: root.chooseSession(root.sessionIndex)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "Session"
                        color: st.text
                        font.family: st.fontFamily
                        font.pixelSize: st.px(15)
                        font.weight: Font.DemiBold
                    }
                }

                ListView {
                    id: sessionView
                    objectName: "sessionView"
                    width: parent.width
                    readonly property real rowHeight: st.px(38)
                    height: Math.min(count, 5) * rowHeight
                    clip: true
                    model: root.sessions
                    keyNavigationEnabled: true
                    keyNavigationWraps: false
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: st.dur(120)
                    Keys.onReturnPressed: root.chooseSession(currentIndex)
                    Keys.onEnterPressed: root.chooseSession(currentIndex)
                    Keys.onSpacePressed: root.chooseSession(currentIndex)
                    Accessible.role: Accessible.List
                    Accessible.name: "Sessions"

                    highlight: Rectangle {
                        radius: st.px(10)
                        color: sessionView.activeFocus ? st.fieldHover : st.field
                    }

                    delegate: Item {
                        id: srow
                        required property int index
                        required property var model
                        width: sessionView.width
                        height: sessionView.rowHeight
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: st.px(14)
                            anchors.right: check.left
                            anchors.rightMargin: st.px(8)
                            anchors.verticalCenter: parent.verticalCenter
                            text: srow.model.name ?? ""
                            elide: Text.ElideRight
                            color: st.text
                            font.family: st.fontFamily
                            font.pixelSize: st.px(14)
                            font.weight: srow.index === root.sessionIndex ? Font.DemiBold : Font.Normal
                        }
                        Icon {
                            id: check
                            anchors.right: parent.right
                            anchors.rightMargin: st.px(12)
                            anchors.verticalCenter: parent.verticalCenter
                            visible: srow.index === root.sessionIndex
                            name: "check"
                            size: st.px(16)
                            color: st.accent
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.chooseSession(srow.index)
                        }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: srow.model.name ?? ""
                        Accessible.selected: srow.index === root.sessionIndex
                    }
                }
            }
        }

        // Confirmación de energía.
        Page {
            id: confirmPage
            objectName: "confirmPage"
            active: root.notchMode === "confirm"
            implicitHeight: confirmColumn.implicitHeight
            Keys.onEscapePressed: root.cancelPower()

            readonly property var copy: ({
                    "poweroff": ["power", "Shut down now?", "The computer will turn off.", "Shut Down"],
                    "reboot": ["restart", "Restart now?", "The computer will restart.", "Restart"],
                    "suspend": ["moon", "Sleep now?", "The computer will go to sleep.", "Sleep"]
                })
            readonly property var c: copy[root.pendingPower] || copy["poweroff"]

            Column {
                id: confirmColumn
                width: parent.width
                spacing: st.px(12)

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: st.px(8)
                    Icon {
                        name: confirmPage.c[0]
                        size: st.px(18)
                        color: st.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: confirmPage.c[1]
                        color: st.text
                        font.family: st.fontFamily
                        font.pixelSize: st.px(15)
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: confirmPage.c[2]
                    color: st.textDim
                    font.family: st.fontFamily
                    font.pixelSize: st.px(13)
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: st.px(10)
                    PillButton {
                        id: cancelButton
                        objectName: "cancelButton"
                        style: st
                        text: "Cancel"
                        minWidth: st.px(120)
                        onClicked: root.cancelPower()
                        KeyNavigation.right: confirmButton
                        KeyNavigation.tab: confirmButton
                    }
                    PillButton {
                        id: confirmButton
                        objectName: "confirmButton"
                        style: st
                        kind: "danger"
                        text: confirmPage.c[3]
                        minWidth: st.px(120)
                        onClicked: root.confirmPower()
                        KeyNavigation.left: cancelButton
                        KeyNavigation.tab: cancelButton
                    }
                }
            }
        }
    }

    SequentialAnimation {
        id: shake
        running: false
        alwaysRunToEnd: false
        NumberAnimation { target: shakeOffset; property: "x"; to: st.animate ? -st.px(10) : 0; duration: st.dur(50) }
        NumberAnimation { target: shakeOffset; property: "x"; to: st.animate ? st.px(9) : 0; duration: st.dur(70) }
        NumberAnimation { target: shakeOffset; property: "x"; to: st.animate ? -st.px(6) : 0; duration: st.dur(70) }
        NumberAnimation { target: shakeOffset; property: "x"; to: st.animate ? st.px(3) : 0; duration: st.dur(60) }
        NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: st.dur(50) }
    }
}
