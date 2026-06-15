// Full-screen exposé contents: the real desktop stays VISIBLE behind (dimmed, and blurred via the
// hyprland layer_rule), with the centered board card on top. The board's own cells are solid, so
// windows render cleanly; the gaps just show the dimmed desktop (the full-screen layer captures all
// input, so nothing behind is clickable). Esc or a click on empty space closes. Loaded by shell.qml's
// per-screen window, only on the focused monitor.

import QtQuick

Item {
    id: overlay
    property var pal
    property var cfg
    property bool open: false
    signal requestClose()

    readonly property real dim: (cfg && cfg.overview && typeof cfg.overview.backdropOpacity === "number")
                                ? Math.max(0, Math.min(1, cfg.overview.backdropOpacity)) : 0.4

    anchors.fill: parent
    focus: true
    // the layer-shell window grabs keyboard focus (Exclusive) while open, but the item still needs
    // active focus for Keys to fire - grab it once the overlay is created (Loader activates on show).
    Component.onCompleted: overlay.forceActiveFocus()
    Keys.onEscapePressed: overlay.requestClose()
    Keys.onPressed: (e) => { if (e.key === Qt.Key_Escape) { overlay.requestClose(); e.accepted = true; } }

    // Dim layer only (the window itself is transparent, so the desktop shows through and the
    // layer_rule blurs it). backdropOpacity = dim amount: 0 = desktop fully visible, 1 = black.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: overlay.dim
        MouseArea { anchors.fill: parent; onClicked: overlay.requestClose() }
    }

    WorkspaceCanvas {
        anchors.fill: parent
        anchors.margins: 40
        pal: overlay.pal
        cfg: overlay.cfg
        onRequestClose: overlay.requestClose()
    }
}
