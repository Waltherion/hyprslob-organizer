// One window's visual in the overview: live ScreencopyView thumbnail (rounded), with an app-icon
// fallback when previews are off. Distilled from the standalone overview's OverviewWindow.qml
// (kept: ScreencopyView + aspect fit + icon fallback; dropped: glass effects, Appearance, event
// recapture). Purely visual + themed via injected props; positioning + drag live in OverviewCanvas.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

Item {
    id: tile
    property var toplevel               // Wayland toplevel (ScreencopyView capture source)
    property var windowData             // hyprctl client object (size/class)
    property bool live: true            // live previews on?
    property bool capture: true         // actively capture this tile?
    property color bg: "#222222"
    property color tileBorder: "#444444"
    property color hoverBorder: "#888888"
    property bool hovered: false
    property bool pressed: false
    property real radiusPx: 6

    readonly property bool showPreview: tile.live && tile.capture && !!tile.toplevel
    readonly property string iconName: {
        const entry = DesktopEntries.heuristicLookup(`${tile.windowData?.class ?? ""}`);
        const raw = `${entry?.icon ?? ""}`.trim().replace(/^image:\/\/icon\//, "").split("?")[0].trim();
        return raw.length > 0 ? raw : "application-x-executable";
    }

    Rectangle {
        anchors.fill: parent
        radius: tile.radiusPx
        color: tile.bg
        border.width: tile.pressed ? 2 : 1
        border.color: (tile.hovered || tile.pressed) ? tile.hoverBorder : tile.tileBorder

        Image {   // app-icon fallback (shown when no live preview)
            anchors.centerIn: parent
            visible: !tile.showPreview
            source: Quickshell.iconPath(tile.iconName, "image-missing")
            readonly property real s: Math.max(16, Math.min(parent.width, parent.height) * 0.4)
            width: s; height: s
            sourceSize.width: Math.max(1, Math.round(s)); sourceSize.height: Math.max(1, Math.round(s))
        }
    }

    ScreencopyView {
        id: preview
        visible: tile.showPreview
        readonly property real srcAspect: {
            const w = tile.windowData?.size?.[0] ?? 0, h = tile.windowData?.size?.[1] ?? 0;
            return (w > 0 && h > 0) ? (w / h) : 1;
        }
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height * srcAspect)
        height: Math.min(parent.height, parent.width / srcAspect)
        captureSource: tile.showPreview ? tile.toplevel : null
        live: tile.live
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: previewMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }
    Item {   // rounded mask matching the thumbnail rect
        id: previewMask
        anchors.centerIn: parent
        width: preview.width; height: preview.height
        visible: false
        layer.enabled: true
        layer.smooth: true
        Rectangle { anchors.centerIn: parent; width: preview.width; height: preview.height; radius: tile.radiusPx }
    }
}
