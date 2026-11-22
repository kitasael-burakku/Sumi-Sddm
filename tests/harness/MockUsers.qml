import QtQuick

/*
 * Doble de `userModel`: mismos roles (name, realName, homeDir, icon, needsPassword) y propiedades
 * lastUser/lastIndex. `fill(n)` crea n usuarios de ejemplo.
 */
ListModel {
    id: m
    property string lastUser: ""
    property int lastIndex: 0
    readonly property var samples: [
        ["alice", "Alice Moreau", true],
        ["bruno", "Bruno Okafor", true],
        ["chen", "Chen Wei", true],
        ["dana", "", true],
        ["emeka", "Emeka Nwosu", false],
        ["fatima", "Fátima Zahra Benali", true],
        ["goro", "Goro Tanaka", true],
        ["hana", "Hana Kim", true],
        ["ivan", "Ivan Petrov", true],
        ["julia", "Julia Rossi", true]
    ]
    function fill(n, icon) {
        clear();
        for (let i = 0; i < n; i++) {
            const s = samples[i % samples.length];
            append({ name: s[0] + (i >= samples.length ? String(i) : ""), realName: s[1], homeDir: "/home/" + s[0],
                     icon: icon !== undefined ? icon : "/usr/share/sddm/faces/.face.icon", needsPassword: s[2] });
        }
    }
}
