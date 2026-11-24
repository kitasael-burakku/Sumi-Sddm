import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Sidebar group label: a small uppercase overline (12 px, muted, modest tracking); its accessible text stays as written.
Label {
    color: Tones.textMuted
    font.pixelSize: Tones.metaSize
    font.weight: Font.DemiBold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.8
    elide: Text.ElideRight
    Layout.fillWidth: true
    Layout.leftMargin: Tones.space3
    Layout.bottomMargin: Tones.space1
    Layout.preferredHeight: Math.max(implicitHeight, Tones.space6)
    verticalAlignment: Text.AlignVCenter
    Accessible.role: Accessible.Heading
}
