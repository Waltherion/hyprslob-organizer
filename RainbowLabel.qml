import QtQuick

// Text where EACH character is colored based on its GLOBAL x-position in the bar (via mapToItem)
// + an animated phase. Multiple RainbowLabels with the same `phase`/`period`/`stops` form one
// continuous rainbow band running across all modules (the text = the "window" into the band).
// rainbow=false -> single-color `solid` (used by non-neon themes).
Row {
    id: rl

    property string content: ""
    property string family: "sans"
    property int pixelSize: 16
    property int fontWeight: 400
    property bool upper: false
    property real letterSpacing: 0
    property var features: ({})

    property bool rainbow: true
    property color solid: Qt.rgba(1, 1, 1, 1)
    property var stops: []           // rainbow colors (#rrggbb)
    property real phase: 0           // animated 0..1
    property real period: 800        // px per full rainbow

    function colAt(px) {
        const s = rl.stops;
        if (!s || s.length < 2) return rl.solid;
        let t = (((px / rl.period + rl.phase) % 1) + 1) % 1;
        const n = s.length, f = t * n;
        const i = Math.floor(f) % n, j = (i + 1) % n, fr = f - Math.floor(f);
        const ch = (h, k) => parseInt(h.slice(1 + k * 2, 3 + k * 2), 16);
        const a = s[i], b = s[j];
        return Qt.rgba((ch(a, 0) + (ch(b, 0) - ch(a, 0)) * fr) / 255,
                       (ch(a, 1) + (ch(b, 1) - ch(a, 1)) * fr) / 255,
                       (ch(a, 2) + (ch(b, 2) - ch(a, 2)) * fr) / 255, 1);
    }

    // code-point iteration (Array.from) so nerd-font icons (including outside BMP) aren't split
    readonly property var chars: rl.content ? Array.from(rl.content) : []

    Repeater {
        model: rl.chars.length
        delegate: Text {
            required property int index
            text: rl.chars[index]
            font.family: rl.family
            font.pixelSize: rl.pixelSize
            font.weight: rl.fontWeight
            font.capitalization: rl.upper ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: rl.letterSpacing
            font.features: rl.features
            // global character center in window coordinates; recomputes every phase tick (also during morph)
            color: rl.rainbow ? rl.colAt(mapToItem(null, x + width / 2, 0).x) : rl.solid
        }
    }
}
