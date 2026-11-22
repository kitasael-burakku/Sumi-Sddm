import QtQuick

/*
 * Doble de `sddm` (GreeterProxy) para pruebas. Mismos nombres que la API real de SDDM 0.21.
 * No guarda la contraseña: sólo su longitud, para comprobar qué llegó a `login`.
 */
QtObject {
    property string hostName: "sumi-test"
    property bool canPowerOff: true
    property bool canReboot: true
    property bool canSuspend: true
    property bool canHibernate: false
    property bool canHybridSleep: false

    signal loginSucceeded
    signal loginFailed
    signal informationMessage(string message)

    property int loginCount: 0
    property string lastUser: ""
    property int lastPasswordLength: -1
    property int lastSession: -1
    property var powerCalls: []

    function login(user, password, sessionIndex) {
        loginCount += 1;
        lastUser = user;
        lastPasswordLength = password.length;
        lastSession = sessionIndex;
    }
    function powerOff() { powerCalls = powerCalls.concat(["powerOff"]); }
    function reboot() { powerCalls = powerCalls.concat(["reboot"]); }
    function suspend() { powerCalls = powerCalls.concat(["suspend"]); }
    function hibernate() { powerCalls = powerCalls.concat(["hibernate"]); }
    function hybridSleep() { powerCalls = powerCalls.concat(["hybridSleep"]); }
}
