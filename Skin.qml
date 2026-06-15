// Appearance resolver. EVERYTHING comes from the config file (Config -> cfg); the
// built-in defaults below are the ONLY fallback - used when a key is absent or the
// config fails to load entirely. No external theme dependency. Pure, computed props.
//
// Color slot priority (low->high):
//   1. built-in default (below)
//   2. external color file (cfg.colors path)
//   3. inline cfg.color{}  (wins)

import QtQuick

QtObject {
    id: pal
    property var cfg              // Config instance

    // ---- Built-in default palette (the single fallback if config is gone) ----
    readonly property color defBackground: "#cc000000"
    readonly property color defText: "#ffffff"
    readonly property color defAccent: "#ffffff"
    readonly property color defBorder: "#ffffff"
    readonly property color defHighlight: "#ffffff"

    function _pick(slot, def) {
        var inl = cfg ? cfg.color : null;       // inline cfg.color{}  (highest)
        var ext = cfg ? cfg.extColor : null;    // external color file
        if (inl && inl[slot]) return inl[slot];
        if (ext && ext[slot]) return ext[slot];
        return def;                             // built-in default
    }

    readonly property color background: _pick("background", defBackground)
    readonly property color text:       _pick("text",       defText)
    readonly property color accent:     _pick("accent",     defAccent)
    readonly property color border:     _pick("border",     defBorder)
    readonly property color highlight:  _pick("highlight",  text)   // hover/focus tint; defaults to text (look unchanged unless set)
    readonly property color separator:  Qt.rgba(text.r, text.g, text.b, 0.35)

    // Rainbow gradient stops - drives rainbow text, visualizer curve, active ws dot,
    // and the selected hub button. Needs >=2 hex stops; otherwise no rainbow.
    readonly property var stops: (cfg && cfg.stops && cfg.stops.length >= 2) ? cfg.stops : []

    // ---- Rolling rainbow band ----
    // The whole UI reads as "windows" into ONE rolling rainbow band: every accent surface samples
    // bandAt(globalX) at its own screen position, so they show different hues at once and the band
    // rolls across them (same period as the clock). `phase` is bound to the bar's animation.
    property real phase: 0
    readonly property real bandPeriod: cfg ? cfg.rainbowPeriod : 420   // px per full rainbow (config: rainbowPeriod)

    function _band(px) {   // -> [r,g,b] 0..255 sampled from the band at global x, or null (no rainbow)
        const s = stops;
        if (!rainbow || !s || s.length < 2) return null;
        const t = (((px / bandPeriod + phase) % 1) + 1) % 1;
        const n = s.length, f = t * n;
        const i = Math.floor(f) % n, j = (i + 1) % n, fr = f - Math.floor(f);
        const ch = (h, k) => parseInt(h.slice(1 + k * 2, 3 + k * 2), 16);
        const a = s[i], b = s[j];
        return [Math.round(ch(a, 0) + (ch(b, 0) - ch(a, 0)) * fr),
                Math.round(ch(a, 1) + (ch(b, 1) - ch(a, 1)) * fr),
                Math.round(ch(a, 2) + (ch(b, 2) - ch(a, 2)) * fr)];
    }
    function bandAt(px) {   // color at global x; solid accent when rainbow is off
        const c = _band(px);
        return c ? Qt.rgba(c[0] / 255, c[1] / 255, c[2] / 255, 1) : accent;
    }
    // "#rrggbb" forms for Canvas (createLinearGradient.addColorStop needs strings, not color objects)
    readonly property string accentHex: { const s = accent.toString(); return s.length === 9 ? "#" + s.slice(3) : s; }
    function bandHex(px) {
        const c = _band(px);
        if (!c) return accentHex;
        const h = v => ("0" + Math.max(0, Math.min(255, v)).toString(16)).slice(-2);
        return "#" + h(c[0]) + h(c[1]) + h(c[2]);
    }

    // ---- Shape / glow / opacity / font (all from config, with defaults) ----
    readonly property real radius:      (cfg && typeof cfg.cornerRadius === "number") ? cfg.cornerRadius : 14
    readonly property bool rainbow:     cfg ? (cfg.rainbow === true) : false
    readonly property real bloom:       (cfg && typeof cfg.bloom === "number") ? Math.max(0, Math.min(1, cfg.bloom)) : 0
    readonly property real uiOpacity:   cfg ? cfg.uiOpacity : 1
    readonly property real uiScale:     cfg ? cfg.uiScale : 1
    readonly property real borderWidth: (cfg && typeof cfg.borderWidth === "number") ? cfg.borderWidth : 0
    readonly property bool hasBox:      cfg ? cfg.hasBox : true

    readonly property string fontFamily: (cfg && cfg.font && cfg.font.family) ? cfg.font.family : "Poppins"
    readonly property int    fontSize:   (cfg && cfg.font && cfg.font.size)   ? cfg.font.size   : 14
    readonly property int    fontWeight: (cfg && cfg.font && cfg.font.weight) ? cfg.font.weight : 300
}
