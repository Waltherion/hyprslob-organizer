pragma ComponentBehavior: Bound

// Window/monitor/workspace data not exposed by Quickshell.Hyprland, fetched via hyprctl.
// Trimmed copy of the standalone overview config's services/HyprlandData.qml, stripped of its
// Config dependency. A plain Item (not a singleton): OverviewCanvas owns ONE instance, alive only
// while the overview overlay is open via Loader.active -> zero hyprctl polling when closed.

import QtQuick
import Quickshell.Io
import Quickshell.Hyprland

Item {
    id: root
    property var windowList: []
    property var windowByAddress: ({})
    property var addresses: []
    property var monitors: []
    property var allWorkspaces: []
    property var workspaceRules: []  // configured ws rules (incl. special:NAME -> monitor); always present even when empty
    property int debounceMs: 16     // coalesce event bursts (the source read this from Config.hacks)

    property bool pendingWindows: false
    property bool pendingMonitors: false
    property bool pendingWorkspaces: false

    function updateAll() { schedule(true, true, true); flush(); }
    function schedule(w, m, ws) {
        pendingWindows = pendingWindows || w;
        pendingMonitors = pendingMonitors || m;
        pendingWorkspaces = pendingWorkspaces || ws;
        if (debounceMs <= 0) flush();
        else debounceTimer.restart();
    }
    function flush() {
        if (pendingWindows) { pendingWindows = false; getClients.running = true; }
        if (pendingMonitors) { pendingMonitors = false; getMonitors.running = true; }
        if (pendingWorkspaces) { pendingWorkspaces = false; getWorkspaces.running = true; }
    }

    Component.onCompleted: { root.updateAll(); getWorkspaceRules.running = true; }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = `${event && event.name ? event.name : ""}`;
            if (["openlayer", "closelayer", "screencast"].includes(n)) return;
            if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "movewindowv2" || n === "windowtitle") { root.schedule(true, false, true); return; }
            if (n.startsWith("monitor") || n === "configreloaded") { if (n === "configreloaded") getWorkspaceRules.running = true; root.schedule(true, true, true); return; }
            if (n === "workspace" || n === "workspacev2" || n === "focusedmon" || n === "focusedmonv2" || n === "activewindow" || n === "activewindowv2") { root.schedule(true, false, true); return; }
            root.schedule(true, true, true);
        }
    }
    Timer { id: debounceTimer; interval: root.debounceMs; repeat: false; onTriggered: root.flush() }

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector { id: clientsCol; onStreamFinished: {
            const list = JSON.parse(clientsCol.text);
            root.windowList = list;
            const by = {};
            for (let i = 0; i < list.length; i++) by[list[i].address] = list[i];
            root.windowByAddress = by;
            root.addresses = list.map(w => w.address);
        } }
    }
    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector { id: monCol; onStreamFinished: root.monitors = JSON.parse(monCol.text) }
    }
    Process {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector { id: wsCol; onStreamFinished: root.allWorkspaces = JSON.parse(wsCol.text) }
    }
    // Configured workspace rules (special:NAME -> monitor). Fetched once + on config reload; these
    // persist even when a special ws is empty, so its drop-target tile stays visible.
    Process {
        id: getWorkspaceRules
        command: ["hyprctl", "workspacerules", "-j"]
        stdout: StdioCollector { id: ruleCol; onStreamFinished: {
            try { root.workspaceRules = JSON.parse(ruleCol.text) || []; } catch (e) { root.workspaceRules = []; }
        } }
    }
}
