import QtQuick

/* Doble de `sessionModel`: roles name, file, type, exec, comment y propiedad lastIndex. */
ListModel {
    property int lastIndex: 0
    function fill(names) {
        clear();
        for (let i = 0; i < names.length; i++)
            append({ name: names[i], file: names[i].toLowerCase().replace(/[^a-z0-9]+/g, "-") + ".desktop",
                     type: "wayland", exec: "", comment: "" });
    }
}
