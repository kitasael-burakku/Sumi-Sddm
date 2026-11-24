pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win

    required property var backend
    property bool reduceMotion: false
    property string selectedGroup: ""
    property string page: "settings"
    property bool showPreview: true
    property bool previewExpanded: false
    property bool closeWhenIdle: false

    readonly property QtObject tones: Tones
    // Columnas según lo que cada una necesita (no según un monitor): barra lateral + contenido mínimo con sus
    // márgenes; la vista previa se acopla como tercera columna sólo si el contenido sigue cabiendo a su lado.
    readonly property bool showSidebar: width >= Tones.sidebarWidth + Tones.contentMinWidth + Tones.contentPadding * 2
    readonly property int previewWidth: Math.round(Math.max(Tones.previewMinWidth, Math.min(Tones.previewMaxWidth, width * 0.34)))
    readonly property bool dockPreview: showSidebar
        && width - Tones.sidebarWidth - previewWidth >= Tones.contentMinWidth + Tones.contentPadding * 2
    readonly property bool previewVisible: showPreview && (dockPreview || previewExpanded)
    readonly property var sys: backend.system
    readonly property bool needsApply: !!(sys && sys.installed === true && sys.inSync === false)
    readonly property string group: selectedGroup || (backend.groups[0] || {}).id || ""
    readonly property var groups: backend.groups
    readonly property string groupLabel: (groups.find(entry => entry.id === group) || {}).label || ""
    readonly property string query: search.text.trim().toLowerCase()
    readonly property bool searching: query.length > 0
    readonly property var settingsSections: {
        const keys = win.backend.keys;
        const order = win.backend.order;
        if (!win.searching) {
            const pageKeys = order.filter(key => keys[key].group === win.group);
            if (win.group === "users") pageKeys.unshift("avatar");
            return catalog.forPage(win.group, pageKeys);
        }
        const terms = win.query.split(/\s+/);
        return win.groups.map(section => {
            const matches = order.filter(key => keys[key].group === section.id && terms.every(term =>
                (key + " " + keys[key].label).toLowerCase().includes(term)));
            if (section.id === "users" && terms.every(term => "users avatar picture photo".includes(term)))
                matches.unshift("avatar");
            return { title: section.label, keys: matches };
        }).filter(section => section.keys.length > 0);
    }
    readonly property int resultCount: settingsSections.reduce((count, entry) => count + entry.keys.length, 0)
    readonly property var navSections: [
        { title: "Appearance", groups: groups.filter(entry =>
            ["background", "colors", "typography", "notch", "clock", "motion"].includes(entry.id)) },
        { title: "Sign-in", groups: groups.filter(entry =>
            !["background", "colors", "typography", "notch", "clock", "motion"].includes(entry.id)) }
    ]
    readonly property var compactChoices: navSections.reduce((choices, section) => choices.concat(section.groups), [])
        .concat([{ id: "system", label: "Login screen" }])
    readonly property var customByGroup: {
        const vals = win.backend.values;
        const entries = win.backend.keys;
        const counts = {};
        for (const key of win.backend.order) {
            if ((vals[key] || {}).set) {
                const id = entries[key].group;
                counts[id] = (counts[id] || 0) + 1;
            }
        }
        // La misma definición que el pie («N customised») y que «Reset all»: claves de la configuración. El avatar
        // vive en AccountsService (Reset all no lo toca); su fila lleva su propia marca.
        return counts;
    }

    width: Math.min(1440, Screen.desktopAvailableWidth)
    height: Math.min(860, Screen.desktopAvailableHeight)
    minimumWidth: 360
    minimumHeight: 420
    visible: true
    title: "Sumi Settings"
    color: Tones.appBackground
    font.family: Tones.sans
    font.pixelSize: Tones.bodySize
    // Lo que Fusion pinta por su cuenta (información emergente, diálogos de QML, indicadores) toma Black Frost de
    // aquí, en la variante clara u oscura que corresponda al escritorio.
    palette.window: Tones.appBackground
    palette.windowText: Tones.textPrimary
    palette.base: Tones.controlSurface
    palette.text: Tones.textPrimary
    palette.alternateBase: Tones.groupSurface
    palette.button: Tones.controlSurface
    palette.buttonText: Tones.textPrimary
    palette.brightText: Tones.textOnAccent
    palette.placeholderText: Tones.textMuted
    palette.highlight: Tones.accent
    palette.highlightedText: Tones.textOnAccent
    palette.light: Tones.pressedSurface
    palette.midlight: Tones.hoverSurface
    palette.mid: Tones.borderDefault
    palette.dark: Tones.textMuted          // p. ej. el indicador de actividad de Fusion
    palette.shadow: Tones.ink
    palette.toolTipBase: Tones.overlaySurface
    palette.toolTipText: Tones.textPrimary
    palette.link: Tones.accent
    palette.linkVisited: Tones.glacier

    SettingsCatalog { id: catalog }

    function openPage(id) {
        search.clear();
        win.previewExpanded = false;
        win.page = id === "system" ? "system" : "settings";
        if (win.page === "settings") win.selectedGroup = id;
    }
    function togglePreview() {
        if (win.previewVisible) {
            win.previewExpanded = false;
            win.showPreview = false;
        } else {
            win.showPreview = true;
            win.previewExpanded = !win.dockPreview;
        }
    }
    function focusNavigation(item, offset) {
        const links = [];
        for (let i = 0; i < navSectionsRepeater.count; ++i) {
            const list = navSectionsRepeater.itemAt(i).links;
            for (let j = 0; j < list.count; ++j) links.push(list.itemAt(j));
        }
        links.push(sysItem);
        const next = links[links.indexOf(item) + offset];
        if (next) next.forceActiveFocus(Qt.TabFocusReason);
    }
    function resetScroll() {
        if (settingsScroll.viewport) settingsScroll.viewport.contentY = settingsScroll.viewport.originY;
    }
    function closeIfIdle() {
        if (win.closeWhenIdle && !win.backend.busy && win.backend.systemBusy.length === 0) win.close();
    }

    onGroupChanged: resetScroll()
    onQueryChanged: resetScroll()
    onActiveChanged: if (active) backend.recheck()
    onReduceMotionChanged: Tones.reduceMotion = reduceMotion
    Component.onCompleted: {
        Tones.reduceMotion = win.reduceMotion;
        const w = Math.round(Screen.width * Screen.devicePixelRatio);
        const h = Math.round(Screen.height * Screen.devicePixelRatio);
        if (w >= 100 && h >= 100) {
            preview.screenSize = w + "x" + h;
            win.backend.previewSize = preview.screenSize;
        }
    }
    Binding { target: win.backend; property: "previewEnabled"; value: win.previewVisible }
    onClosing: close => {
        if (win.backend.systemBusy.length > 0) {
            close.accepted = false;
            win.closeWhenIdle = true;
            win.backend.inform("The window will close when the login screen change finishes");
        } else if (win.backend.busy) {
            close.accepted = false;
            win.closeWhenIdle = true;
            win.backend.flushNow();
        }
    }
    Connections {
        target: win.backend
        function onBusyChanged() { win.closeIfIdle(); }
        function onSystemBusyChanged() { win.closeIfIdle(); }
    }

    Shortcut {
        sequences: [StandardKey.Find]
        enabled: win.backend.ready
        onActivated: { win.previewExpanded = false; search.forceActiveFocus(); search.selectAll(); }
    }
    Shortcut { sequences: [StandardKey.Quit, StandardKey.Close]; onActivated: win.close() }

    header: Pane {
        implicitHeight: Tones.titleBarHeight
        topPadding: 0
        bottomPadding: 0
        leftPadding: Tones.space4
        rightPadding: Tones.space3
        background: Rectangle {
            color: Tones.chromeBackground
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Tones.stroke
                color: Tones.borderSubtle
            }
        }
        contentItem: RowLayout {
            spacing: Tones.space3
            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: Tones.cornerRadius
                color: Tones.transparent
                border.width: Tones.stroke
                border.color: Tones.borderDefault
                SettingsIcon { name: "notch"; color: Tones.accent; anchors.centerIn: parent }
            }
            Label {
                text: "Sumi Settings"
                font.pixelSize: Tones.appTitleSize
                font.weight: Font.DemiBold
                color: Tones.textPrimary
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
            ActionButton {
                objectName: "quickApply"
                visible: win.backend.ready && win.needsApply && win.page !== "system"
                enabled: win.backend.systemBusy.length === 0
                text: win.backend.systemBusy === "apply" ? "Applying…" : win.showSidebar ? "Apply to login screen" : "Apply"
                highlighted: true
                Accessible.name: "Apply your settings to the login screen"
                onClicked: win.backend.systemApply()
            }
            ActionButton {
                objectName: "togglePreview"
                visible: win.backend.ready
                text: win.showSidebar ? (win.previewVisible ? "Hide preview" : "Show preview")
                    : (win.previewVisible ? "Back" : "Preview")
                glyph: win.previewVisible ? "close" : "system"
                flat: true
                Accessible.name: win.previewVisible ? "Hide preview" : "Show preview"
                ToolTip.visible: hovered || visualFocus
                ToolTip.text: Accessible.name
                onClicked: {
                    win.togglePreview();
                    if (win.previewVisible && win.previewExpanded) preview.focusPanel();
                }
            }
        }
    }

    ColumnLayout {
        objectName: "statusPage"
        visible: !win.backend.ready
        anchors.centerIn: parent
        width: Math.min(parent.width - Tones.space6 * 2, 520)
        spacing: Tones.space3

        BusyIndicator {
            running: win.backend.status === "" || win.backend.status === "checking"
            visible: running
            Layout.alignment: Qt.AlignHCenter
        }
        Label {
            objectName: "statusTitle"
            text: win.backend.status === "missing" ? "The sumi-sddm command was not found"
                : win.backend.status === "incompatible" ? "This sumi-sddm is a different version"
                : win.backend.status === "broken" ? "sumi-sddm did not answer as expected"
                : "Loading…"
            font.pixelSize: Tones.sectionHeadingSize
            font.weight: Font.DemiBold
            color: win.backend.status === "missing" || win.backend.status === "incompatible"
                || win.backend.status === "broken" ? Tones.error : Tones.textPrimary
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }
        Label {
            objectName: "statusDetail"
            text: win.backend.status === "missing"
                ? "Install the sumi-sddm package, which provides the command, and try again."
                : win.backend.statusDetail
            visible: text.length > 0 && win.backend.status !== "checking"
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: Tones.textSecondary
            Layout.fillWidth: true
        }
        ActionButton {
            objectName: "retry"
            visible: ["missing", "incompatible", "broken"].includes(win.backend.status)
            text: "Try again"
            Layout.alignment: Qt.AlignHCenter
            onClicked: win.backend.load()
        }
    }

    InputField {
        id: search
        parent: win.showSidebar ? sidebarSearch : narrowSearch
        anchors.fill: parent
        objectName: "search"
        placeholderText: "Search settings"
        Accessible.name: placeholderText
        leftPadding: Tones.space3 + lens.implicitWidth + Tones.space2
        rightPadding: clearSearch.visible ? clearSearch.width + Tones.space1 : Tones.space3
        Keys.onEscapePressed: clear()
        onTextChanged: if (text.length > 0) { win.previewExpanded = false; win.page = "settings"; }
        SettingsIcon {
            id: lens
            name: "search"
            color: Tones.textMuted
            anchors.left: parent.left
            anchors.leftMargin: Tones.space3
            anchors.verticalCenter: parent.verticalCenter
        }
        ActionButton {
            id: clearSearch
            visible: search.text.length > 0
            width: height
            height: search.height - 2 * Tones.stroke
            anchors.right: parent.right
            anchors.rightMargin: Tones.stroke
            anchors.verticalCenter: parent.verticalCenter
            glyph: "close"
            flat: true
            Accessible.name: "Clear search"
            onClicked: { search.clear(); search.forceActiveFocus(); }
        }
    }

    RowLayout {
        objectName: "form"
        visible: win.backend.ready
        anchors.fill: parent
        spacing: 0

        Pane {
            visible: win.showSidebar
            Layout.fillHeight: true
            Layout.preferredWidth: Tones.sidebarWidth
            Layout.minimumWidth: Tones.sidebarWidth
            Layout.maximumWidth: Tones.sidebarWidth
            padding: Tones.space3
            topPadding: Tones.space4
            rightPadding: Tones.space3 + Tones.stroke
            background: Rectangle {
                color: Tones.sidebarBackground
                Rectangle {
                    anchors.right: parent.right
                    width: Tones.stroke
                    height: parent.height
                    color: Tones.borderSubtle
                }
            }
            contentItem: ColumnLayout {
                spacing: Tones.space4
                Item {
                    id: sidebarSearch
                    Layout.fillWidth: true
                    Layout.preferredHeight: search.implicitHeight
                }
                SettingsScroll {
                    id: sidebarView
                    objectName: "groups"
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Pane {
                        id: sidebarLinks
                        width: sidebarView.availableWidth
                        padding: 0
                        background: null
                        contentItem: ColumnLayout {
                            spacing: 0
                            Repeater {
                                id: navSectionsRepeater
                                model: win.navSections
                                delegate: ColumnLayout {
                                    id: navSection
                                    required property var modelData
                                    required property int index
                                    readonly property alias links: navLinks
                                    visible: modelData.groups.length > 0
                                    Layout.fillWidth: true
                                    Layout.topMargin: index > 0 ? Tones.space4 : 0
                                    spacing: 0
                                    NavOverline { text: navSection.modelData.title }
                                    Repeater {
                                        id: navLinks
                                        model: navSection.modelData.groups
                                        delegate: NavigationItem {
                                            id: link
                                            required property var modelData
                                            Layout.fillWidth: true
                                            objectName: "group-" + modelData.id
                                            glyph: modelData.id
                                            text: modelData.label
                                            customised: win.customByGroup[modelData.id] || 0
                                            highlighted: !win.searching && win.page === "settings"
                                                && modelData.id === win.group
                                            onClicked: win.openPage(modelData.id)
                                            Keys.onUpPressed: win.focusNavigation(link, -1)
                                            Keys.onDownPressed: win.focusNavigation(link, 1)
                                            Keys.onReturnPressed: clicked()
                                        }
                                    }
                                }
                            }
                            NavOverline { text: "System"; Layout.topMargin: Tones.space4 }
                            NavigationItem {
                                id: sysItem
                                objectName: "page-system"
                                Layout.fillWidth: true
                                text: "Login screen"
                                glyph: "system"
                                highlighted: win.page === "system"
                                pending: win.needsApply
                                onClicked: win.openPage("system")
                                Keys.onUpPressed: win.focusNavigation(sysItem, -1)
                                Keys.onReturnPressed: clicked()
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            visible: !win.previewExpanded
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            spacing: 0

            RowLayout {
                visible: !win.showSidebar
                spacing: Tones.space2
                Layout.fillWidth: true
                Layout.margins: Tones.contentPaddingCompact
                Layout.bottomMargin: 0
                ChoiceBox {
                    objectName: "sectionPicker"
                    Layout.preferredWidth: Math.min(168, Math.max(120, implicitWidth))
                    model: win.compactChoices
                    textRole: "label"
                    valueRole: "id"
                    currentIndex: win.compactChoices.findIndex(entry =>
                        entry.id === (win.page === "system" ? "system" : win.group))
                    Accessible.name: "Settings section"
                    onActivated: win.openPage(currentValue)
                }
                Item {
                    id: narrowSearch
                    Layout.fillWidth: true
                    Layout.preferredHeight: search.implicitHeight
                }
            }

            Loader {
                objectName: "systemPage"
                active: win.page === "system"
                visible: active
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: SystemPanel { backend: win.backend }
            }

            SettingsScroll {
                id: settingsScroll
                objectName: "scroll"
                visible: win.page === "settings"
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    width: settingsScroll.availableWidth
                    implicitHeight: settingsContent.implicitHeight + gutter * 2
                    readonly property int gutter: width >= Tones.contentMinWidth + Tones.contentPadding * 2
                        ? Tones.contentPadding : Tones.contentPaddingCompact

                    ColumnLayout {
                        id: settingsContent
                        objectName: "settingsContent"
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.gutter
                        width: Math.min(Tones.contentMaxWidth, parent.width - parent.gutter * 2)
                        spacing: Tones.space8

                        NumberAnimation on opacity {
                            id: pageTransition
                            running: false
                            from: 0.76
                            to: 1
                            easing.type: Tones.easing
                            duration: Tones.navDuration
                        }
                        Connections {
                            target: win
                            function onGroupChanged() { if (!win.searching && Tones.motion) pageTransition.restart(); }
                        }
                        SectionHeader {
                            Layout.fillWidth: true
                            title: win.searching ? (win.resultCount === 1 ? "1 result" : win.resultCount + " results")
                                : win.groupLabel
                            description: win.searching ? "Settings matching “" + search.text.trim() + "”, by page"
                                : (catalog.descriptions[win.group] || "")
                        }
                        Repeater {
                            id: groupsRepeater
                            objectName: "fields"
                            model: win.settingsSections
                            delegate: SettingsGroup {
                                id: card
                                required property var modelData
                                Layout.fillWidth: true
                                title: modelData.title
                                Repeater {
                                    model: card.modelData.keys
                                    delegate: Loader {
                                        id: field
                                        required property string modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        readonly property bool hasNext: index + 1 < card.modelData.keys.length
                                        sourceComponent: modelData === "avatar" ? avatarComponent : fieldComponent
                                        Component {
                                            id: avatarComponent
                                            AvatarRow { backend: win.backend; divider: field.hasNext }
                                        }
                                        Component {
                                            id: fieldComponent
                                            Field { backend: win.backend; key: field.modelData; divider: field.hasNext }
                                        }
                                    }
                                }
                            }
                        }
                        Label {
                            objectName: "noResults"
                            visible: win.searching && win.resultCount === 0
                            text: "Nothing matches “" + search.text.trim() + "”. Try a shorter word, or clear the search "
                                + "to browse the pages."
                            color: Tones.textSecondary
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        Preview {
            id: preview
            objectName: "preview"
            backend: win.backend
            visible: win.previewVisible
            canExpand: win.dockPreview
            expanded: win.previewExpanded
            onToggleExpanded: win.previewExpanded = !win.previewExpanded
            Layout.fillHeight: true
            Layout.fillWidth: win.previewExpanded
            Layout.preferredWidth: win.previewWidth
            Layout.minimumWidth: win.previewExpanded ? 0 : Tones.previewMinWidth

            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tones.previewDuration; easing.type: Tones.easing } }
        }
    }

    footer: Pane {
        visible: win.backend.ready
        topPadding: visible ? Tones.space1 + Tones.stroke : 0
        bottomPadding: visible ? Tones.space1 : 0
        leftPadding: Tones.space4
        rightPadding: Tones.space3
        background: Rectangle {
            implicitHeight: Tones.footerHeight
            color: Tones.chromeBackground
            Rectangle { width: parent.width; height: Tones.stroke; color: Tones.borderSubtle }
        }

        contentItem: ColumnLayout {
            spacing: 0
            RowLayout {
                visible: message.text !== ""
                spacing: Tones.space2
                Layout.topMargin: Tones.space1
                SettingsIcon {
                    name: message.isError ? "alert" : "check"
                    color: message.isError ? Tones.error : Tones.textSecondary
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: Math.max(0, (messageMetrics.height - height) / 2)
                }
                FontMetrics { id: messageMetrics; font: message.font }
                Label {
                    id: message
                    objectName: "message"
                    readonly property bool isError: win.backend.error.length > 0
                    text: isError ? win.backend.error : win.backend.notice
                    color: isError ? Tones.error : Tones.textPrimary
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Accessible.role: Accessible.AlertMessage
                    ToolTip.visible: messageHover.hovered && truncated
                    ToolTip.text: text
                    HoverHandler { id: messageHover }
                }
                ActionButton {
                    objectName: "dismiss"
                    glyph: "close"
                    flat: true
                    Accessible.name: "Dismiss message"
                    onClicked: win.backend.dismiss()
                }
            }
            // Una fila; si no caben el estado y las dos acciones, dos (las acciones debajo, a la derecha).
            GridLayout {
                id: footerRow
                visible: win.backend.ready
                readonly property bool wraps: width < countLabel.implicitWidth + restoreButton.implicitWidth
                    + resetButton.implicitWidth + Tones.space8 * 2
                columns: wraps ? 1 : 2
                rowSpacing: 0
                columnSpacing: Tones.space3
                Layout.minimumHeight: Tones.footerHeight - Tones.space2 - Tones.stroke
                RowLayout {
                    spacing: Tones.space2
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.minimumHeight: Tones.controlHeight
                    BusyIndicator {
                        running: win.backend.busy
                        visible: running
                        implicitWidth: Tones.iconSize + Tones.space1
                        implicitHeight: implicitWidth
                        Accessible.name: "Saving"
                    }
                    Label {
                        id: countLabel
                        objectName: "customCount"
                        text: win.backend.customCount ? win.backend.customCount + " customised" : "All defaults"
                        color: Tones.textSecondary
                        font.pixelSize: Tones.helperSize
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                    }
                }
                RowLayout {
                    spacing: Tones.space2
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    ActionButton {
                        id: restoreButton
                        objectName: "restore"
                        text: "Restore previous"
                        flat: true
                        Accessible.name: "Restore the settings saved before the last reset"
                        ToolTip.visible: hovered || visualFocus
                        ToolTip.text: Accessible.name
                        ToolTip.delay: 400
                        onClicked: win.backend.restorePrevious()
                    }
                    ActionButton {
                        id: resetButton
                        objectName: "resetAll"
                        text: win.backend.resetArmed ? "Press again to reset" : "Reset all"
                        enabled: win.backend.customCount > 0
                        highlighted: win.backend.resetArmed
                        destructive: true
                        flat: true
                        Accessible.name: win.backend.resetArmed ? "Press again to reset every setting" : "Reset all settings"
                        onClicked: win.backend.resetAll()
                    }
                }
            }
        }
    }
}
