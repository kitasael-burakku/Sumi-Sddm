import QtQuick

QtObject {
    readonly property var descriptions: ({
        background: "Choose the wallpaper and tune how it sits behind the sign-in controls.",
        colors: "Set the palette for the sign-in controls, text and feedback.",
        typography: "Choose the login screen font and adjust the interface and text scales.",
        notch: "Adjust the shape and behaviour of the panel at the top of the screen.",
        clock: "Choose how the date and time appear on the login screen.",
        users: "Manage your picture and the layout of the account selector.",
        power: "Choose which power actions appear before signing in.",
        motion: "Adjust transitions and their speed on the login screen.",
        behaviour: "Set how Sumi handles multiple displays and sign-in timeouts."
    })

    readonly property var sections: ({
        background: [
            ["Image source", ["background", "backgroundFill"]],
            ["Image treatment", ["blurRadius", "dimOpacity", "backgroundColor", "blur", "dim"]]
        ],
        colors: [["Interface palette", []]],
        typography: [["Font and scale", []]],
        notch: [
            ["Geometry", ["notchCompactWidth", "notchCompactHeight", "notchExpandedWidth", "notchRadius", "notchShoulder"]],
            ["Expansion", ["notchStartExpanded", "notchIdleCollapse"]]
        ],
        clock: [
            ["Display", ["showClock", "clockFormat", "clockSeconds", "dateFormat", "clockScale", "clockWeight"]],
            ["Placement", ["clockPosition", "clockOffsetX", "clockOffsetY"]]
        ],
        users: [
            ["Profile", ["avatar"]],
            ["Account selector", ["userStrip", "avatarSize", "userNames", "userInactiveOpacity", "userStripMargin", "manualUser"]]
        ],
        power: [["Available actions", []]],
        motion: [["Transitions", []]],
        behaviour: [["Display and sign-in", []]]
    })

    function forPage(group, keys) {
        const groups = sections[group] || [];
        const assigned = groups.reduce((keys, section) => keys.concat(section[1]), []);
        const result = groups.map(section => ({
            title: section[0],
            keys: keys.filter(key => section[1].length ? section[1].includes(key) : !assigned.includes(key))
        }));
        if (!groups.some(section => section[1].length === 0)) {
            result.push({ title: "", keys: keys.filter(key => !assigned.includes(key)) });
        }
        return result.filter(section => section.keys.length > 0);
    }
}
