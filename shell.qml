//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

// HyprSlob Workspace Organizer - standalone full-screen workspace + window exposé (qs -c
// hyprslob-organizer). Separate from the HyprSlob center bar. Shows ONE unified canvas on the
// FOCUSED monitor with every monitor's workspaces + live window thumbnails; click to focus/switch,
// middle-click to close, drag a thumbnail across monitors to move it (see FINDINGS.md for the proven
// move semantics). Appearance (colour/rainbow/font) + layout come from its OWN config at
// ~/.config/hyprslob-organizer/config.jsonc. Activate via IPC (`qs -c hyprslob-organizer ipc call organizer toggle`).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup(); }
    }

    // NB: ids must NOT match the WorkspaceOverlay property names `pal`/`cfg` - inside the Loader's
    // sourceComponent below, `pal: pal` would bind to the component's OWN property (self-ref -> null).
    Config { id: appcfg }
    Skin { id: skin; cfg: appcfg; phase: root.rainbowPhase }

    // Global open state. The exposé is shown only on the focused monitor (each per-screen window
    // gates itself on Hyprland.focusedMonitor), so "follow focus" is automatic.
    property bool open: false
    IpcHandler {
        target: "organizer"
        function toggle(): void { root.open = !root.open }
        function open(): void { root.open = true }
        function close(): void { root.open = false }
    }

    // ---- Flowing rainbow phase. Zero-cost: the timer runs ONLY when rainbow=true and the exposé is
    //      open (no animation work while closed). ----
    property real rainbowPhase: 0
    Timer {
        interval: 60; repeat: true
        running: skin.rainbow && root.open
        onTriggered: root.rainbowPhase = ((root.rainbowPhase + 0.005 * appcfg.rainbowSpeed) % 1 + 1) % 1
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            readonly property string monName: win.modelData ? `${win.modelData.name}` : ""
            readonly property bool isFocused: Hyprland.focusedMonitor && `${Hyprland.focusedMonitor.name}` === win.monName
            readonly property bool shown: root.open && win.isFocused

            WlrLayershell.namespace: "quickshell-hyprslob-organizer"
            WlrLayershell.layer: WlrLayer.Overlay
            // grab keyboard focus only while the exposé is up on THIS (focused) monitor, so Esc works
            WlrLayershell.keyboardFocus: win.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            visible: win.shown
            color: "transparent"

            // full-screen overlay; reserve nothing (it sits on top and blocks input itself)
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore

            Loader {
                anchors.fill: parent
                active: win.shown
                sourceComponent: WorkspaceOverlay {
                    pal: skin
                    cfg: appcfg
                    open: win.shown
                    onRequestClose: root.open = false
                }
            }
        }
    }
}
