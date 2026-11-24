import QtQuick
import QtQuick.Controls

// Vertical scrolling only, with a square scroll bar; keeps the focused control in view while tabbing.
ScrollView {
    id: root

    readonly property Item focused: root.Window.activeFocusItem
    readonly property Flickable viewport: contentItem as Flickable

    contentWidth: availableWidth
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical: SquareScrollBar {
        parent: root
        x: root.mirrored ? 0 : root.width - width
        y: root.topPadding
        height: root.availableHeight
        active: root.ScrollBar.horizontal.active
    }

    onFocusedChanged: {
        const flick = root.viewport;
        if (!root.visible || !root.focused || !flick) return;
        for (let ancestor = root.focused; ancestor; ancestor = ancestor.parent) {
            if (ancestor !== flick.contentItem) continue;
            const y = root.focused.mapToItem(flick.contentItem, 0, 0).y;
            const top = y - Tones.space6;
            const bottom = y + root.focused.height + Tones.space6;
            if (top < flick.contentY)
                flick.contentY = Math.max(flick.originY, top);
            else if (bottom > flick.contentY + flick.height)
                flick.contentY = Math.min(flick.originY + Math.max(0, flick.contentHeight - flick.height),
                                          bottom - flick.height);
            return;
        }
    }
}
