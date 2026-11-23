import QtQuick
import QtQuick.Controls

ScrollView {
    id: root

    readonly property Item focused: root.Window.activeFocusItem
    readonly property Flickable viewport: contentItem as Flickable

    contentWidth: availableWidth
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    onFocusedChanged: {
        const flick = root.viewport;
        if (!root.visible || !root.focused || !flick) return;
        for (let ancestor = root.focused; ancestor; ancestor = ancestor.parent) {
            if (ancestor !== flick.contentItem) continue;
            const y = root.focused.mapToItem(flick.contentItem, 0, 0).y;
            const top = y - Tones.gap;
            const bottom = y + root.focused.height + Tones.gap;
            if (top < flick.contentY)
                flick.contentY = Math.max(flick.originY, top);
            else if (bottom > flick.contentY + flick.height)
                flick.contentY = Math.min(flick.originY + Math.max(0, flick.contentHeight - flick.height),
                                          bottom - flick.height);
            return;
        }
    }
}
