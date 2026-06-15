// One monitor's "board": a grid of `wsCount` numbered workspace cells (columns x rows), plus this
// monitor's special/scratch workspaces shown to the RIGHT of the grid (with a gap), marked by a
// hardcoded RED outline. Numbered cells switch on click; every cell + special tile is a DropArea
// reporting its target to the shared canvas. Numbered-workspace window thumbnails are painted by the
// canvas on top; special-ws windows are shown inside their own tile here. Themed from `pal` (Skin);
// mapping is deterministic (blockBase from the canvas).

import QtQuick
import Quickshell.Hyprland

Item {
    id: sec
    property var pal
    property var canvas                 // WorkspaceCanvas: shared drag state + requestClose()
    property var monitorData            // hyprctl monitor object (name, id, activeWorkspace.id)
    property int blockBase: 0           // first real ws id on this monitor minus 1 (deterministic)
    property int wsCount: 10
    property int columns: 5
    property int rows: 2
    property var specials: []           // this monitor's special ws names (prefix stripped), up to 4
    property real cellW: 100
    property real cellH: 60
    property real cellGap: 10
    property real specialGap: 30        // gap between the numbered grid and the special tiles
    property real headerH: 24           // height of the small title row above the grid (0 = no header)
    property real contentX0: 0          // this section's x within content (for rainbow band positioning)
    property real numberSize: 14

    readonly property string monName: monitorData ? `${monitorData.name}` : ""
    readonly property int monId: monitorData ? monitorData.id : -1
    readonly property int activeWsId: monitorData && monitorData.activeWorkspace ? monitorData.activeWorkspace.id : -1
    readonly property real headerFont: Math.max(11, Math.round(headerH * 0.62))

    readonly property real gridW: columns * cellW + (columns - 1) * cellGap
    readonly property int specialCols: specials.length > 0 ? Math.ceil(specials.length / rows) : 0
    readonly property real specialBlockW: specialCols > 0 ? specialCols * cellW + (specialCols - 1) * cellGap : 0

    // guarded theme colors (pal can be momentarily undefined while the delegate binds)
    readonly property color cBg:        pal ? pal.background : "#000000"
    readonly property color cText:      pal ? pal.text       : "#ffffff"
    readonly property color cAccent:    pal ? pal.accent     : "#ffffff"
    readonly property color cBorder:    pal ? pal.border     : "#ffffff"
    readonly property color cHighlight: pal ? pal.highlight  : "#ffffff"
    readonly property string cFont:     pal ? pal.fontFamily : "Poppins"

    // rolling-band colour for an item, sampled at its global (x+y) -> matches the 45deg box border.
    // Falls back to solid accent when rainbow is off. Re-evaluates on phase change (bandAt reads phase).
    function bandColorAt(item) {
        if (!pal || !pal.rainbow) return cAccent;
        const p = item.mapToItem(null, item.width / 2, item.height / 2);
        return pal.bandAt(p.x + p.y);
    }

    implicitWidth: gridW + (specialCols > 0 ? specialGap + specialBlockW : 0)
    implicitHeight: headerH + rows * cellH + (rows - 1) * cellGap

    // ---- small headers (monitor title over the grid, "Scratchpads" over the special block).
    //      RainbowLabel colours each glyph by its global x -> the rolling band runs THROUGH the text
    //      (a window into the same band as the box border), not a single sample. ----
    RainbowLabel {
        visible: sec.headerH > 0
        x: 2
        y: Math.round((sec.headerH - height) / 2)
        content: sec.monName
        family: sec.cFont
        pixelSize: sec.headerFont
        fontWeight: 600
        rainbow: sec.pal ? sec.pal.rainbow : false
        solid: sec.cAccent
        stops: sec.pal ? sec.pal.stops : []
        phase: sec.pal ? sec.pal.phase : 0
        period: sec.pal ? sec.pal.bandPeriod : 700
    }
    RainbowLabel {
        visible: sec.headerH > 0 && sec.specialCols > 0
        x: sec.gridW + sec.specialGap + 2
        y: Math.round((sec.headerH - height) / 2)
        content: "Scratchpads"
        family: sec.cFont
        pixelSize: sec.headerFont
        fontWeight: 600
        rainbow: sec.pal ? sec.pal.rainbow : false
        solid: sec.cAccent
        stops: sec.pal ? sec.pal.stops : []
        phase: sec.pal ? sec.pal.phase : 0
        period: sec.pal ? sec.pal.bandPeriod : 700
    }

    // ---- numbered workspace grid ----
    Repeater {
        model: sec.wsCount
        delegate: Rectangle {
            id: cell
            required property int index
            readonly property int rowIdx: Math.floor(index / sec.columns)
            readonly property int colIdx: index % sec.columns
            readonly property int wsId: sec.blockBase + index + 1   // real Hyprland id (dispatch/match)
            readonly property int wsLabel: index + 1                // virtual per-monitor number (1..N) shown
            readonly property bool isActive: wsId === sec.activeWsId
            readonly property bool isDropTarget: sec.canvas && sec.canvas.draggingTargetWorkspace === wsId
            readonly property bool hovered: cellMA.containsMouse
            readonly property color bandColor: { if (sec.pal) sec.pal.phase; return sec.bandColorAt(cell); }

            x: colIdx * (sec.cellW + sec.cellGap)
            y: sec.headerH + rowIdx * (sec.cellH + sec.cellGap)
            width: sec.cellW
            height: sec.cellH
            radius: 6
            // fill: drop-target > hover > active > idle
            color: cell.isDropTarget ? Qt.rgba(sec.cHighlight.r, sec.cHighlight.g, sec.cHighlight.b, 0.30)
                 : cell.hovered       ? Qt.rgba(sec.cAccent.r, sec.cAccent.g, sec.cAccent.b, 0.18)
                 : cell.isActive      ? Qt.rgba(sec.cAccent.r, sec.cAccent.g, sec.cAccent.b, 0.12)
                 :                       Qt.rgba(sec.cText.r, sec.cText.g, sec.cText.b, 0.05)
            border.width: (cell.isActive || cell.hovered) ? 2 : 1
            // idle border samples the rolling band; active/hover stay solid accent for clear feedback
            border.color: cell.isActive ? sec.cAccent
                 : cell.hovered ? Qt.rgba(sec.cAccent.r, sec.cAccent.g, sec.cAccent.b, 0.7)
                 : Qt.rgba(cell.bandColor.r, cell.bandColor.g, cell.bandColor.b, 0.45)
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: cell.wsLabel
                // active number is bright accent; the rest ride the rolling rainbow band
                color: cell.isActive ? sec.cAccent
                     : Qt.rgba(cell.bandColor.r, cell.bandColor.g, cell.bandColor.b, 0.75)
                font.family: sec.cFont
                font.pixelSize: sec.numberSize
                font.weight: cell.isActive ? Font.Bold : Font.DemiBold
            }

            MouseArea {
                id: cellMA
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onClicked: {
                    if (sec.canvas && sec.canvas.draggingTargetWorkspace !== -1) return;
                    Hyprland.dispatch(`hl.dsp.focus({monitor = '${sec.monName}'})`);
                    Hyprland.dispatch(`hl.dsp.focus({workspace = '${cell.wsId}'})`);
                    if (sec.canvas) sec.canvas.requestClose();
                }
            }
            DropArea {
                anchors.fill: parent
                onEntered: if (sec.canvas) sec.canvas.setDropTarget(cell.wsId, sec.monName, sec.monId);
                onExited: if (sec.canvas && sec.canvas.draggingTargetWorkspace === cell.wsId) sec.canvas.clearDropTarget(cell.wsId);
            }
        }
    }

    // ---- special / scratch workspaces, to the RIGHT of the grid (hardcoded red outline). These are
    //      drop-target boxes; their window thumbnails are painted by the canvas's shared drag layer
    //      (so special windows can be dragged OUT, exactly like numbered-workspace windows). ----
    Repeater {
        model: sec.specials
        delegate: Rectangle {
            id: stile
            required property int index
            required property string modelData          // special ws name (prefix already stripped)
            readonly property int sCol: Math.floor(index / sec.rows)
            readonly property int sRow: index % sec.rows
            readonly property bool isDrop: sec.canvas && sec.canvas.draggingTargetSpecial === modelData
            property bool hovered: false
            readonly property color bandColor: { if (sec.pal) sec.pal.phase; return sec.bandColorAt(stile); }

            x: sec.gridW + sec.specialGap + sCol * (sec.cellW + sec.cellGap)
            y: sec.headerH + sRow * (sec.cellH + sec.cellGap)
            width: sec.cellW
            height: sec.cellH
            radius: 6
            // same colour rules as the numbered cells (no separate red design)
            color: stile.isDrop  ? Qt.rgba(sec.cHighlight.r, sec.cHighlight.g, sec.cHighlight.b, 0.30)
                 : stile.hovered ? Qt.rgba(sec.cAccent.r, sec.cAccent.g, sec.cAccent.b, 0.18)
                 :                  Qt.rgba(sec.cText.r, sec.cText.g, sec.cText.b, 0.05)
            border.width: (stile.isDrop || stile.hovered) ? 2 : 1
            border.color: (stile.isDrop || stile.hovered) ? sec.cAccent
                                                          : Qt.rgba(stile.bandColor.r, stile.bandColor.g, stile.bandColor.b, 0.45)
            Behavior on color { ColorAnimation { duration: 120 } }

            // hover feedback (mainly for EMPTY special tiles; populated ones get the canvas hover film)
            HoverHandler { onHoveredChanged: stile.hovered = hovered }

            DropArea {
                anchors.fill: parent
                onEntered: if (sec.canvas) sec.canvas.setSpecialDropTarget(stile.modelData, sec.monName, sec.monId);
                onExited: if (sec.canvas && sec.canvas.draggingTargetSpecial === stile.modelData) sec.canvas.clearSpecialDropTarget(stile.modelData);
            }
        }
    }
}
