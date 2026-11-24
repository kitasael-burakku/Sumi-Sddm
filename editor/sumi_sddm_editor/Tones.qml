pragma Singleton

import QtQuick

/**
 * Black Frost: the single source of the editor's look (colours, spacing, geometry, type, motion).
 *
 * Neutral surfaces, frost blue only for interaction and emphasis, square geometry. It follows the desktop's light or
 * dark mode (the application palette that KDE, GNOME or qt6ct set): dark = near-black surfaces with frost accents, as
 * specified; light = near-white surfaces with the same blue, darkened so it keeps its contrast on white. The login
 * screen being edited (the preview) has its own colours and is never restyled to match either.
 */
QtObject {
    readonly property SystemPalette system: SystemPalette {}
    readonly property bool dark: system.window.hslLightness < 0.5

    // ---- core palette ----------------------------------------------------------------------------------------------
    readonly property color ink: "#090B10"
    readonly property color graphite: "#11141B"
    readonly property color slate: "#1A202B"
    readonly property color frost: "#A6C8FA"
    readonly property color glacier: "#7699D0"
    readonly property color snow: "#F0F3FA"
    readonly property color mist: "#B1BACB"
    /** Frost blue for light surfaces: same hue, dark enough for text and boundaries on white. */
    readonly property color deepFrost: "#2A5BA8"

    // ---- surfaces --------------------------------------------------------------------------------------------------
    readonly property color appBackground: dark ? "#0D0F14" : "#F5F7FA"
    readonly property color chromeBackground: dark ? ink : "#ECF0F5"
    readonly property color sidebarBackground: dark ? graphite : "#EFF2F7"
    readonly property color previewBackground: dark ? "#10131A" : "#EDF1F6"
    readonly property color groupSurface: dark ? "#151922" : "#FFFFFF"
    readonly property color controlSurface: dark ? slate : "#F7F9FC"
    readonly property color hoverSurface: dark ? "#222A37" : "#E7EDF5"
    readonly property color pressedSurface: dark ? "#2C3748" : "#D9E2EE"
    readonly property color selectedSurface: dark ? "#23364E" : "#DDE8F7"
    readonly property color overlaySurface: dark ? "#151922" : "#FFFFFF"
    readonly property color disabledSurface: dark ? graphite : "#EEF1F5"
    /** Bands around the greeter render: black in both modes, like the screen it stands for. */
    readonly property color previewLetterbox: "#000000"
    /** Checkerboard behind a colour swatch with alpha (only where the setting accepts #aarrggbb). */
    readonly property color checkerLight: "#FFFFFF"
    readonly property color checkerDark: "#C8CCD4"
    /** Separation between a focus ring or a slider thumb and what it surrounds. */
    readonly property color separation: dark ? ink : "#FFFFFF"

    // ---- content ---------------------------------------------------------------------------------------------------
    readonly property color textPrimary: dark ? snow : "#0E131B"
    readonly property color textSecondary: dark ? mist : "#3B4657"
    readonly property color textMuted: dark ? "#8996AB" : "#566275"
    readonly property color textDisabled: dark ? "#697588" : "#8C96A5"
    readonly property color textOnAccent: dark ? ink : "#FFFFFF"

    // ---- borders ---------------------------------------------------------------------------------------------------
    readonly property color borderSubtle: dark ? "#252C38" : "#E0E5ED"
    readonly property color borderDefault: dark ? "#343F50" : "#CBD3DF"
    readonly property color controlBorder: dark ? "#65748A" : "#7A8597"
    readonly property color borderHover: dark ? "#8996AB" : "#566275"
    readonly property color focusRing: accent

    // ---- accent ----------------------------------------------------------------------------------------------------
    readonly property color accent: dark ? frost : deepFrost
    readonly property color accentHover: dark ? "#BED8FF" : "#234E92"
    readonly property color accentPressed: dark ? "#8BB1EB" : "#1D417A"
    readonly property color modified: accent

    // ---- semantic (always paired with text or an icon) -------------------------------------------------------------
    readonly property color success: dark ? "#94D5B5" : "#1D6B47"
    readonly property color successSurface: dark ? "#142720" : "#E2F2EA"
    readonly property color warning: dark ? "#E8C384" : "#875600"
    readonly property color warningSurface: dark ? "#2A2115" : "#FAF0DC"
    readonly property color error: dark ? "#F1A0A5" : "#B0303A"
    readonly property color errorSurface: dark ? "#301B22" : "#FBE6E8"
    readonly property color info: accent
    readonly property color infoSurface: dark ? "#17263B" : "#E2ECFA"
    readonly property color transparent: "transparent"

    // ---- spacing (logical px; Qt applies the device pixel ratio) ---------------------------------------------------
    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space5: 20
    readonly property int space6: 24
    readonly property int space8: 32
    readonly property int space10: 40
    readonly property int space12: 48

    // ---- geometry --------------------------------------------------------------------------------------------------
    readonly property int cornerRadius: 0
    readonly property int stroke: 1
    readonly property int focusStroke: 2
    /** Gap between a control and its focus ring, so a frost-filled control keeps a dark separation. */
    readonly property int focusGap: 1
    readonly property int iconSize: 16
    readonly property int checkSize: 18
    readonly property int swatchSize: 24
    readonly property int sliderTrack: 4
    readonly property int sliderThumb: 14
    readonly property int sliderHitHeight: 32
    readonly property int indicatorWidth: 2
    readonly property int markerSize: 6

    // ---- typography ------------------------------------------------------------------------------------------------
    /** Inter when present, else Noto Sans, else the desktop's font. Preferences, not dependencies. */
    readonly property var installedFamilies: Qt.fontFamilies()
    function firstFamily(candidates, fallback) {
        for (const family of candidates)
            if (installedFamilies.indexOf(family) >= 0) return family;
        return fallback;
    }
    readonly property font systemFont: Application.font
    readonly property string sans: firstFamily(["Inter", "Noto Sans"], systemFont.family)
    readonly property string mono: firstFamily(["JetBrains Mono", "Iosevka", "Iosevka Term"], "monospace")
    /** Follows a larger desktop font (10 pt ≈ 13.3 px is 1.0) but never shrinks the documented sizes. */
    readonly property real textScale: {
        const px = systemFont.pixelSize > 0 ? systemFont.pixelSize : systemFont.pointSize * 4 / 3;
        return Math.max(1, (px > 0 ? px : 13.333) / 13.333);
    }
    function px(size) { return Math.round(size * textScale); }
    readonly property int appTitleSize: px(15)
    readonly property int pageHeadingSize: px(28)
    readonly property int sectionHeadingSize: px(16)
    readonly property int groupHeadingSize: px(14)
    readonly property int bodySize: px(14)
    readonly property int helperSize: px(13)
    readonly property int metaSize: px(12)
    readonly property int monoSize: px(13)

    // ---- control sizes (grow with the text) ------------------------------------------------------------------------
    readonly property int controlHeight: Math.max(36, Math.round(bodySize * 2.57))
    readonly property int controlHeightLarge: Math.max(44, Math.round(bodySize * 3.14))
    readonly property int rowHeight: Math.max(44, Math.round(bodySize * 3.14))
    readonly property int navHeight: Math.max(36, Math.round(bodySize * 2.57))
    readonly property int titleBarHeight: Math.max(48, controlHeight + space3)
    readonly property int footerHeight: Math.max(44, controlHeight + space2)

    // ---- layout ----------------------------------------------------------------------------------------------------
    readonly property int sidebarWidth: px(224)
    readonly property int contentMinWidth: 440
    readonly property int contentMaxWidth: 760
    readonly property int previewMinWidth: 400
    readonly property int previewMaxWidth: 520
    readonly property int contentPadding: 32
    readonly property int contentPaddingCompact: 16

    // ---- motion ----------------------------------------------------------------------------------------------------
    property bool reduceMotion: false
    readonly property bool systemReducesMotion: {
        const preference = Application.styleHints?.accessibility?.motionPreference;
        return preference !== undefined && preference === Qt.ReducedMotion;
    }
    readonly property bool motion: !reduceMotion && !systemReducesMotion
    readonly property int hoverDuration: motion ? 100 : 0
    readonly property int overlayDuration: motion ? 140 : 0
    readonly property int previewDuration: motion ? 150 : 0
    /** Kept for callers and tests that only ask whether motion is on. */
    readonly property int duration: previewDuration
    readonly property int easing: Easing.OutCubic
}
