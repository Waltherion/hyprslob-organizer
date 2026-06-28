pragma ComponentBehavior: Bound

// The unified exposé: one board per connected monitor, stacked in WORKSPACE-NUMBER order (block 0 on
// top: DP-1 ws 1-10, then DP-3 ws 11-20 below), all at a UNIFORM cell size (locked to the smallest
// monitor's logical geometry so resolution/scale never changes tile size). A single window-tile layer
// sits on top of every section, which makes dragging a tile across section (= monitor) boundaries work
// for free. Themed from `pal` (Skin), no matugen.
//
// Mapping & moves are deterministic per FINDINGS.md:
//  - blockBase(M) = prioIndex(M) * wsCount  (prioIndex from config monitorOrder, else derived).
//  - to move window X to monitor M's virtual ws V: monitor-move FIRST, then workspace-move to the
//    real id (so an empty cross-monitor target never ghosts onto the focused monitor).
//
// NOTE: the global scale factor is `zoom`, NOT `scale` (a builtin Item transform that would shrink
// the whole canvas).

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: canvas
    property var pal
    property var cfg
    signal requestClose()

    // ---- config knobs (guarded; cfg.overview always present via Config defaults) ----
    readonly property var ov: (cfg && cfg.overview) ? cfg.overview : ({})
    readonly property int wsCount: (ov.workspaceCount > 0) ? ov.workspaceCount : 10
    readonly property int columns: (ov.columns > 0) ? ov.columns : 5
    readonly property int rows: Math.max(1, Math.ceil(wsCount / columns))
    readonly property var monitorOrder: Array.isArray(ov.monitorOrder) ? ov.monitorOrder : []
    readonly property real sectionSpacing: (typeof ov.spacing === "number" && ov.spacing >= 0) ? ov.spacing : 24
    readonly property real cellGap: (typeof ov.cellGap === "number" && ov.cellGap >= 0) ? ov.cellGap : 10
    readonly property real maxZoom: (ov.scale > 0) ? ov.scale : 0.18
    readonly property bool livePreviews: ov.livePreviews !== false
    // "vertical" = monitors stacked top->bottom (number order); "horizontal" = side by side
    readonly property bool vertical: `${ov.direction || "vertical"}` !== "horizontal"

    // guarded theme colors
    readonly property color cBg:     pal ? pal.background : "#000000"
    readonly property color cBorder: pal ? pal.border     : "#ffffff"
    readonly property color cAccent: pal ? pal.accent     : "#ffffff"

    WorkspaceData { id: hd }

    // ---- deterministic monitor<->block mapping (FINDINGS.md) ----
    function prioIndex(m) {
        if (!m) return 0;
        if (canvas.monitorOrder.length) {
            const i = canvas.monitorOrder.indexOf(`${m.name}`);
            if (i >= 0) return i;
        }
        const a = (m.activeWorkspace) ? m.activeWorkspace.id : 1;
        return Math.floor((Math.max(1, a) - 1) / canvas.wsCount);
    }
    function blockBaseForMon(m) { return canvas.prioIndex(m) * canvas.wsCount; }

    // monitors sorted by block (number order): block 0 first (top), block 1 next, ...
    readonly property var mons: {
        const m = (hd.monitors || []).slice();
        m.sort((a, b) => canvas.prioIndex(a) - canvas.prioIndex(b));
        return m;
    }
    readonly property int n: mons.length

    function monIndexForId(id) { return mons.findIndex(m => m.id === id); }
    function monForWs(realId) {
        const base = Math.floor((realId - 1) / canvas.wsCount) * canvas.wsCount;
        return mons.find(m => canvas.blockBaseForMon(m) === base) || null;
    }

    // ---- per-monitor logical (scale=1) sizes, transform-aware ----
    function logW(m) { return ((m.transform % 2 === 1) ? m.height : m.width) / (m.scale || 1); }
    function logH(m) { return ((m.transform % 2 === 1) ? m.width : m.height) / (m.scale || 1); }
    function rawCellW(m) { return Math.max(1, logW(m) - ((m.reserved && m.reserved[0]) || 0) - ((m.reserved && m.reserved[2]) || 0)); }
    function rawCellH(m) { return Math.max(1, logH(m) - ((m.reserved && m.reserved[1]) || 0) - ((m.reserved && m.reserved[3]) || 0)); }

    // ---- UNIFORM cell size: locked to the smallest monitor's logical geometry ----
    readonly property var refMon: {
        if (n === 0) return null;
        let r = mons[0];
        for (let i = 1; i < n; i++) if (rawCellW(mons[i]) < rawCellW(r)) r = mons[i];
        return r;
    }
    readonly property real refW: refMon ? rawCellW(refMon) : 1
    readonly property real refH: refMon ? rawCellH(refMon) : 1

    // ---- special/scratch workspaces (monitor-bound). Shown to the RIGHT of the grid. ----
    readonly property bool showSpecial: ov.showSpecial !== false
    function specialsForMon(monName) {
        const out = [];
        const push = (nm) => { const s = nm.slice(8); if (s.length && out.indexOf(s) < 0) out.push(s); };
        // configured workspace rules first - these persist even when the special ws is empty, so its
        // drop-target tile stays visible after you drag the last window out.
        const rules = hd.workspaceRules || [];
        for (let i = 0; i < rules.length; i++) {
            const ws = `${rules[i] && rules[i].workspaceString ? rules[i].workspaceString : ""}`;
            if (!ws.startsWith("special:")) continue;
            if (`${rules[i].monitor || ""}` !== `${monName}`) continue;
            push(ws);
        }
        // any live special ws on this monitor not covered by a rule (ad-hoc)
        const wss = hd.allWorkspaces || [];
        for (let i = 0; i < wss.length; i++) {
            const nm = `${wss[i] && wss[i].name ? wss[i].name : ""}`;
            if (!nm.startsWith("special:")) continue;
            if (`${wss[i].monitor || ""}` !== `${monName}`) continue;
            push(nm);
        }
        return out.slice(0, 4);
    }
    function specialsAt(i) { return (showSpecial && mons[i]) ? specialsForMon(`${mons[i].name}`) : []; }
    function specialColsAt(i) { const k = specialsAt(i).length; return k > 0 ? Math.ceil(k / rows) : 0; }
    readonly property int maxSpecialCols: { let m = 0; for (let i = 0; i < n; i++) m = Math.max(m, specialColsAt(i)); return m; }
    // gap between grid and special block = the same as the gap between monitor sections
    readonly property real specialGap: sectionSpacing

    // small header row above each section (monitor title + special title). Fixed readable px height.
    readonly property bool showHeaders: ov.headers !== false
    readonly property real headerH: showHeaders ? Math.round((pal ? pal.fontSize : 14) * 1.7) : 0

    // one global zoom that fits the uniform board into the focused screen. The grid height never
    // changes (specials sit to the RIGHT, <= `rows` tall); only the effective WIDTH grows.
    readonly property real zoom: {
        if (n === 0) return maxZoom;
        const extraCols = maxSpecialCols;
        const cw = refW * (columns + extraCols);   // ref-unit width of grid + special columns
        const ch = refH * rows;
        const specGapW = extraCols > 0 ? specialGap : 0;   // fixed px gap before the special block
        let fitW, fitH;
        if (vertical) {
            const gapsW = (columns - 1) * cellGap + (extraCols > 0 ? (extraCols - 1) * cellGap : 0) + specGapW;
            const gapsH = n * (rows - 1) * cellGap + (n - 1) * sectionSpacing + n * headerH;
            fitW = (width * 0.94 - gapsW) / Math.max(1, cw);
            fitH = (height * 0.90 - gapsH) / Math.max(1, n * ch);
        } else {
            const gapsW = n * ((columns - 1) * cellGap + (extraCols > 0 ? (extraCols - 1) * cellGap : 0) + specGapW) + (n - 1) * sectionSpacing;
            const gapsH = (rows - 1) * cellGap + headerH;
            fitW = (width * 0.92 - gapsW) / Math.max(1, n * cw);
            fitH = (height * 0.85 - gapsH) / Math.max(1, ch);
        }
        return Math.max(0.02, Math.min(fitW, fitH, maxZoom));
    }

    function cellW(i) { return refW * zoom; }   // uniform across all monitors
    function cellH(i) { return refH * zoom; }
    function monScaleX(i) { return cellW(i) / rawCellW(mons[i]); }
    function monScaleY(i) { return cellH(i) / rawCellH(mons[i]); }
    function gridW(i) { return cellW(i) * columns + (columns - 1) * cellGap; }
    function specialBlockW(i) { const c = specialColsAt(i); return c > 0 ? c * cellW(i) + (c - 1) * cellGap : 0; }
    function sectionW(i) { return gridW(i) + (specialColsAt(i) > 0 ? specialGap + specialBlockW(i) : 0); }
    function sectionH(i) { return headerH + cellH(i) * rows + (rows - 1) * cellGap; }
    readonly property real totalW: {
        if (!vertical) { let w = 0; for (let i = 0; i < n; i++) w += sectionW(i); return w + Math.max(0, n - 1) * sectionSpacing; }
        let w = 0; for (let i = 0; i < n; i++) w = Math.max(w, sectionW(i)); return w;
    }
    readonly property real totalH: {
        if (vertical) { let h = 0; for (let i = 0; i < n; i++) h += sectionH(i); return h + Math.max(0, n - 1) * sectionSpacing; }
        let h = 0; for (let i = 0; i < n; i++) h = Math.max(h, sectionH(i)); return h;
    }
    function originX(i) {
        if (vertical) return (totalW - sectionW(i)) / 2;
        let x = 0; for (let j = 0; j < i; j++) x += sectionW(j) + sectionSpacing; return x;
    }
    function originY(i) {
        if (!vertical) return (totalH - sectionH(i)) / 2;
        let y = 0; for (let j = 0; j < i; j++) y += sectionH(j) + sectionSpacing; return y;
    }

    // ---- shared drag state (set by section DropAreas) ----
    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1   // real id of the hovered cell, or -1
    property string draggingTargetMonName: ""
    property int draggingTargetMonId: -1
    function setDropTarget(realId, monName, monId) {
        draggingTargetWorkspace = realId; draggingTargetMonName = monName; draggingTargetMonId = monId;
    }
    function clearDropTarget(realId) {
        if (draggingTargetWorkspace === realId) { draggingTargetWorkspace = -1; draggingTargetMonName = ""; draggingTargetMonId = -1; }
    }
    property string draggingTargetSpecial: ""   // special ws name (no prefix) hovered, or ""
    property string draggingTargetSpecialMon: ""  // the special's monitor-bound name (from ws rules)
    property int draggingTargetSpecialMonId: -1
    function setSpecialDropTarget(name, monName, monId) {
        draggingTargetSpecial = name; draggingTargetSpecialMon = monName; draggingTargetSpecialMonId = monId;
        draggingTargetWorkspace = -1;
    }
    function clearSpecialDropTarget(name) {
        if (draggingTargetSpecial === name) { draggingTargetSpecial = ""; draggingTargetSpecialMon = ""; draggingTargetSpecialMonId = -1; }
    }
    // Special workspaces are monitor-bound via ws-rules, BUT an EMPTY one still binds to the FOCUSED
    // monitor at birth (the exposé's, since it holds exclusive focus). Same focus dance as moveWindow:
    // focus the special's monitor so it's born there, move silently, restore focus to the exposé.
    function moveWindowToSpecial(addr, name, monName, monId, curMonId) {
        if (!addr || !name) return;
        const overlayMon = Hyprland.focusedMonitor ? `${Hyprland.focusedMonitor.name}` : "";
        const dance = monName && monName.length && overlayMon.length && overlayMon !== `${monName}`;
        if (dance) Hyprland.dispatch(`hl.dsp.focus({monitor = '${monName}'})`);
        Hyprland.dispatch(`hl.dsp.window.move({workspace = 'special:${name}', follow = false, window = 'address:${addr}'})`);
        if (dance) Hyprland.dispatch(`hl.dsp.focus({monitor = '${overlayMon}'})`);
    }

    // Move window X onto monitor M's virtual ws (real id). KEY FACT (confirmed empirically): a NEW
    // (empty) workspace is bound to whatever monitor is FOCUSED at the instant it's born — and the
    // exposé holds exclusive focus on the monitor it's shown on. A window-move alone does NOT change
    // that focus, so it can't re-home the ws (an earlier attempt failed for exactly this reason).
    // Fix = focus dance: briefly focus the TARGET monitor so the ws is born/bound there, move the
    // window silently into it, then restore focus to the exposé's own monitor so the overlay stays
    // put. Only needed when dropping onto a DIFFERENT monitor than the one showing the exposé;
    // same-monitor drops already have focus on the right screen.
    function moveWindow(addr, realId, monName, monId, curMonId) {
        if (!addr) return;
        const overlayMon = Hyprland.focusedMonitor ? `${Hyprland.focusedMonitor.name}` : "";
        const dance = monName && monName.length && overlayMon.length && overlayMon !== `${monName}`;
        if (dance) Hyprland.dispatch(`hl.dsp.focus({monitor = '${monName}'})`);
        Hyprland.dispatch(`hl.dsp.window.move({workspace = '${realId}', follow = false, window = 'address:${addr}'})`);
        if (dance) Hyprland.dispatch(`hl.dsp.focus({monitor = '${overlayMon}'})`);
    }
    function focusWindow(addr) {
        if (!addr) return;
        Hyprland.dispatch(`hl.dsp.focus({window = 'address:${addr}'})`);
    }
    function closeWindow(addr) {
        if (!addr) return;
        Hyprland.dispatch(`hl.dsp.window.close('address:${addr}')`);
    }

    // ---- themed UI box behind the board (sibling of content, follows its geometry) ----
    readonly property real framePad: 22
    readonly property real borderW: (pal && pal.borderWidth > 0) ? pal.borderWidth : 0
    Rectangle {
        id: frame
        x: content.x - canvas.framePad
        y: content.y - canvas.framePad
        width: content.width + canvas.framePad * 2
        height: content.height + canvas.framePad * 2
        radius: pal ? pal.radius : 14
        color: canvas.cBg
        // solid border only when rainbow is OFF; otherwise the rolling-band Canvas below draws it
        border.width: (pal && pal.rainbow) ? 0 : canvas.borderW
        border.color: canvas.cBorder
    }
    // Rolling 45-degree rainbow band stroked along the box outline (like the center bar's band).
    Canvas {
        id: rainbowBorder
        visible: pal && pal.rainbow && pal.stops && pal.stops.length >= 2 && canvas.borderW > 0
        x: frame.x; y: frame.y; width: frame.width; height: frame.height
        antialiasing: true
        renderStrategy: Canvas.Cooperative
        property real phase: pal ? pal.phase : 0
        property real bw: Math.max(2, canvas.borderW)
        property real rad: pal ? pal.radius : 14
        onPhaseChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height, half = bw / 2;
            if (w < 4 || h < 4 || !pal) return;
            // TRUE 45deg band: the gradient axis is the (1,1) direction (NOT the box diagonal, which is
            // shallow for a wide box). Colour at a pixel depends on (x+y); sampled from the rolling band
            // so the whole thing scrolls as `phase` advances. span = max (x+y) across the box.
            // Sample in CONTENT-LOCAL space so the frame stays in sync with the cell borders + numbers
            // (which use contentX0/Y0), independent of scene scaling/centring. The frame's top-left sits
            // at content-local (-framePad, -framePad), so its band origin is -2*framePad.
            const gOff = -2 * canvas.framePad;
            const span = w + h;
            const g = ctx.createLinearGradient(0, 0, span / 2, span / 2);   // axis at exactly 45deg
            const M = 80;
            for (let k = 0; k <= M; k++) { const t = k / M; g.addColorStop(t, pal.bandHex(gOff + span * t)); }
            ctx.strokeStyle = g;
            ctx.lineWidth = bw;
            ctx.lineJoin = "round";
            const r = Math.max(0, Math.min(rad, Math.min(w, h) / 2 - half));
            ctx.beginPath();
            ctx.moveTo(half + r, half);
            ctx.lineTo(w - half - r, half);
            ctx.arcTo(w - half, half, w - half, half + r, r);
            ctx.lineTo(w - half, h - half - r);
            ctx.arcTo(w - half, h - half, w - half - r, h - half, r);
            ctx.lineTo(half + r, h - half);
            ctx.arcTo(half, h - half, half, h - half - r, r);
            ctx.lineTo(half, half + r);
            ctx.arcTo(half, half, half + r, half, r);
            ctx.closePath();
            ctx.stroke();
        }
    }

    // centered content (sections board + tiles layer) - centered directly in the canvas
    Item {
        id: content
        width: canvas.totalW
        height: canvas.totalH
        anchors.centerIn: parent

        // ---- boards (one per monitor) ----
        Repeater {
            model: canvas.n
            delegate: MonitorSection {
                required property int index
                pal: canvas.pal
                canvas: canvas
                monitorData: canvas.mons[index]
                blockBase: canvas.blockBaseForMon(canvas.mons[index])
                specials: canvas.specialsAt(index)
                wsCount: canvas.wsCount
                columns: canvas.columns
                rows: canvas.rows
                cellW: canvas.cellW(index)
                cellH: canvas.cellH(index)
                cellGap: canvas.cellGap
                specialGap: canvas.specialGap
                headerH: canvas.headerH
                contentX0: canvas.originX(index)
                contentY0: canvas.originY(index)
                numberSize: Math.max(10, Math.round(canvas.cellH(index) * 0.26))
                x: canvas.originX(index)
                y: canvas.originY(index)
            }
        }

        // ---- window tiles (shared layer over all boards; cross-monitor drag) ----
        Repeater {
            model: ScriptModel {
                values: {
                    const by = hd.windowByAddress;
                    return ToplevelManager.toplevels.values.filter(tl => {
                        const a = `0x${tl.HyprlandToplevel.address}`;
                        const w = by[a];
                        if (!w) return false;
                        const mi = canvas.monIndexForId(w.monitor);
                        if (mi < 0) return false;
                        const wsName = `${w.workspace && w.workspace.name ? w.workspace.name : ""}`;
                        if (wsName.startsWith("special:"))
                            // include special windows only if their special ws is shown on this monitor
                            return canvas.specialsAt(mi).indexOf(wsName.slice(8)) >= 0;
                        const base = canvas.blockBaseForMon(canvas.mons[mi]);
                        const wsId = w.workspace ? w.workspace.id : -1;
                        return wsId >= base + 1 && wsId <= base + canvas.wsCount;
                    });
                }
            }
            delegate: Item {
                id: tileWrap
                required property var modelData
                readonly property string addr: `0x${modelData.HyprlandToplevel.address}`
                readonly property var wdata: hd.windowByAddress[addr]
                readonly property int mi: canvas.monIndexForId(wdata ? wdata.monitor : -1)
                readonly property var mon: mi >= 0 ? canvas.mons[mi] : null

                readonly property string wsName: wdata && wdata.workspace ? `${wdata.workspace.name || ""}` : ""
                readonly property bool isSpecial: wsName.startsWith("special:")
                readonly property string specialName: isSpecial ? wsName.slice(8) : ""
                readonly property int sk: (isSpecial && mi >= 0) ? canvas.specialsAt(mi).indexOf(specialName) : -1
                readonly property int sCol: sk >= 0 ? Math.floor(sk / canvas.rows) : 0
                readonly property int sRow: sk >= 0 ? sk % canvas.rows : 0

                readonly property int base: mon ? canvas.blockBaseForMon(mon) : 0
                readonly property int wsIdx: ((wdata && wdata.workspace ? wdata.workspace.id : 1) - base - 1)
                readonly property int colIdx: ((wsIdx % canvas.columns) + canvas.columns) % canvas.columns
                readonly property int rowIdx: Math.max(0, Math.floor(wsIdx / canvas.columns))

                // Cell content sits inside an even inset so the cell/special border shows all around.
                // NUMBERED windows keep their REAL side-by-side layout (mapped into the inset content
                // area); SPECIAL windows fill the inset tile.
                readonly property real inset: 6
                readonly property real cellX: mi < 0 ? 0
                    : isSpecial ? canvas.originX(mi) + canvas.gridW(mi) + canvas.specialGap + sCol * (canvas.cellW(mi) + canvas.cellGap)
                                : canvas.originX(mi) + colIdx * (canvas.cellW(mi) + canvas.cellGap)
                readonly property real cellY: mi < 0 ? 0
                    : isSpecial ? canvas.originY(mi) + canvas.headerH + sRow * (canvas.cellH(mi) + canvas.cellGap)
                                : canvas.originY(mi) + canvas.headerH + rowIdx * (canvas.cellH(mi) + canvas.cellGap)
                // scale mapping this monitor's logical px into the cell's inset content area
                readonly property real isx: (mi >= 0 && mon) ? (canvas.cellW(mi) - inset * 2) / canvas.rawCellW(mon) : canvas.zoom
                readonly property real isy: (mi >= 0 && mon) ? (canvas.cellH(mi) - inset * 2) / canvas.rawCellH(mon) : canvas.zoom
                readonly property real lx: mon ? Math.max((((wdata && wdata.at ? wdata.at[0] : 0) - mon.x - ((mon.reserved && mon.reserved[0]) || 0)) * isx), 0) : 0
                readonly property real ly: mon ? Math.max((((wdata && wdata.at ? wdata.at[1] : 0) - mon.y - ((mon.reserved && mon.reserved[1]) || 0)) * isy), 0) : 0
                readonly property real baseX: isSpecial ? cellX + inset : cellX + inset + lx
                readonly property real baseY: isSpecial ? cellY + inset : cellY + inset + ly

                property bool dragging: false
                visible: !!wdata && mi >= 0 && (!isSpecial || sk >= 0)
                width: isSpecial ? Math.max(8, canvas.cellW(mi) - inset * 2) : Math.max(8, (wdata && wdata.size ? wdata.size[0] : 100) * isx)
                height: isSpecial ? Math.max(8, canvas.cellH(mi) - inset * 2) : Math.max(8, (wdata && wdata.size ? wdata.size[1] : 100) * isy)
                x: baseX
                y: baseY
                z: dragging ? 99999 : 1

                Behavior on x { enabled: !tileWrap.dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !tileWrap.dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                Drag.active: tileWrap.dragging
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2

                WindowTile {
                    anchors.fill: parent
                    toplevel: tileWrap.modelData
                    windowData: tileWrap.wdata
                    live: canvas.livePreviews
                    capture: true
                    bg: Qt.rgba(canvas.cBorder.r, canvas.cBorder.g, canvas.cBorder.b, 0.10)
                    tileBorder: Qt.rgba(canvas.cBorder.r, canvas.cBorder.g, canvas.cBorder.b, 0.50)
                    hoverBorder: canvas.cAccent
                    hovered: dragMA.containsMouse
                    pressed: tileWrap.dragging
                    radiusPx: pal ? pal.cellRadius : 6
                }

                // hover "film" over the WHOLE cell, painted ON TOP of the window thumbnail (same look as
                // hovering an empty cell). Cell-sized regardless of the window's size/position.
                Rectangle {
                    visible: dragMA.containsMouse && !tileWrap.dragging
                    x: tileWrap.cellX - tileWrap.baseX
                    y: tileWrap.cellY - tileWrap.baseY
                    width: tileWrap.mi >= 0 ? canvas.cellW(tileWrap.mi) : 0
                    height: tileWrap.mi >= 0 ? canvas.cellH(tileWrap.mi) : 0
                    radius: pal ? pal.cellRadius : 6
                    color: Qt.rgba(canvas.cAccent.r, canvas.cAccent.g, canvas.cAccent.b, 0.20)
                    border.width: 2
                    border.color: canvas.cAccent
                }

                MouseArea {
                    id: dragMA
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    drag.target: tileWrap
                    onPressed: (mouse) => {
                        if (mouse.button !== Qt.LeftButton) return;
                        canvas.draggingFromWorkspace = (tileWrap.wdata && tileWrap.wdata.workspace) ? tileWrap.wdata.workspace.id : -1;
                        tileWrap.dragging = true;
                        tileWrap.Drag.hotSpot.x = mouse.x;
                        tileWrap.Drag.hotSpot.y = mouse.y;
                    }
                    onReleased: {
                        const fromWs = (tileWrap.wdata && tileWrap.wdata.workspace) ? tileWrap.wdata.workspace.id : -1;
                        const target = canvas.draggingTargetWorkspace;
                        const tMonName = canvas.draggingTargetMonName;
                        const tMonId = canvas.draggingTargetMonId;
                        const special = canvas.draggingTargetSpecial;
                        const sMonName = canvas.draggingTargetSpecialMon;
                        const sMonId = canvas.draggingTargetSpecialMonId;
                        const curMonId = tileWrap.wdata ? tileWrap.wdata.monitor : -1;
                        const addr = tileWrap.wdata ? tileWrap.wdata.address : "";
                        tileWrap.dragging = false;
                        canvas.draggingFromWorkspace = -1;
                        canvas.draggingTargetWorkspace = -1;
                        canvas.draggingTargetMonName = "";
                        canvas.draggingTargetMonId = -1;
                        canvas.draggingTargetSpecial = "";
                        canvas.draggingTargetSpecialMon = "";
                        canvas.draggingTargetSpecialMonId = -1;
                        if (special && special.length)
                            canvas.moveWindowToSpecial(addr, special, sMonName, sMonId, curMonId);
                        else if (target !== -1 && target !== fromWs)
                            canvas.moveWindow(addr, target, tMonName, tMonId, curMonId);
                        tileWrap.x = Qt.binding(() => tileWrap.baseX);
                        tileWrap.y = Qt.binding(() => tileWrap.baseY);
                    }
                    onClicked: (mouse) => {
                        if (!tileWrap.wdata) return;
                        if (mouse.button === Qt.LeftButton) {
                            canvas.focusWindow(tileWrap.wdata.address);
                            canvas.requestClose();
                        } else if (mouse.button === Qt.MiddleButton) {
                            canvas.closeWindow(tileWrap.wdata.address);
                        }
                    }
                }
            }
        }
    }
}
