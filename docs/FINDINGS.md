# Fase 1 — FINDINGS: workspace↔monitor-model + move/focus-primitiver

Bevist empirisk 2026-06-15 på den live 2-monitor-opsætning (DP-1 + DP-3, split-monitor-workspaces,
Lua-config, Hyprland). Verificeret udelukkende via `hyprctl clients/monitors/workspaces -j`
(HDR bryder `grim`). **GATE: PASSED.**

## 1. Deterministisk mapping (bekræftet mod live state)

| Monitor | id | prio-index | real ws-ids | vist som |
|---|---|---|---|---|
| DP-1 (x=2048, højre) | 0 | 0 | **1–10** | virtuel 1–10 |
| DP-3 (x=0, venstre)  | 1 | 1 | **11–20** | virtuel 1–10 |

Formel: `base_M = prio_index(M) * workspace_count` (workspace_count = 10).
`realId = base_M + V` for virtuel V ∈ 1..10. **Stabil — udled ALDRIG fra aktiv ws.**
Tomme nummererede workspaces eksisterer ikke (non-persistent); kun aktive/befolkede findes.

## 2. Ghost-årsagen (afklaret — vigtig forfining af briefet)

`hl.dsp.window.move({workspace='ID'})` til en **tom** target-ws opretter den nye workspace på
**vinduets NUVÆRENDE monitor** (ikke nødvendigvis den fokuserede, som briefet gættede).

- Vindue på DP-1 → move til tom 13 ⇒ ws 13 oprettes på **DP-1** (ghost). ✗
- Vindue på DP-3 → move til tom 13 ⇒ ws 13 oprettes på **DP-3** (korrekt). ✓

⇒ Fix: flyt vinduet til den rigtige monitor FØRST, så er den tomme target-ws bundet rigtigt.

## 3. ✅ VINDENDE PRIMITIV — flyt vindue X til monitor M's virtuelle ws V

To dispatches, **monitor først, så workspace** (back-to-back, INGEN delay nødvendig):

```js
// QML (Quickshell): Hyprland.dispatch(...) — strengen evalueres som Lua
Hyprland.dispatch(`hl.dsp.window.move({monitor='${M}', window='address:${addr}'})`)
Hyprland.dispatch(`hl.dsp.window.move({workspace='${realId}', window='address:${addr}'})`)
// M = monitornavn ('DP-1'/'DP-3'); realId = base_M + V
```

- **Stress-testet 10× cross-monitor til tomme celler, begge retninger: 0 ghosts.** Splittet
  kollapsede aldrig til "begge 1-10".
- Back-to-back uden sleep bekræftet (ingen QML-Timer mellem de to kald nødvendig).
- Optimering (valgfri): spring `{monitor=M}` over når `window.monitor === M.id` allerede — men
  "altid begge" er robust og idempotent (anden dispatch korrigerer).
- TODO Fase 5: bekræft at `{monitor=M}` ikke stjæler fokus væk fra exposéet (tilføj evt.
  `follow=false` til workspace-dispatchen — shelved-koden brugte det).

## 3b. ⚠️ FORFINING (med exposéet ÅBENT) — FOKUS, ikke vinduets monitor, binder en tom ws

Fase 1 testede UDEN overlay. Med exposéet oppe holder det EXCLUSIVE keyboard-fokus på sin egen
monitor, og der er INTET fokuseret vindue. Så reglen skifter: en **tom** target-ws bindes til den
**FOKUSEREDE monitor** (exposéets), ikke vinduets. Et rent vindue-flyt (`window.move({monitor=M})`)
ankrer derfor IKKE — ws'en ghoster stadig til exposéets skærm når man omarrangerer på en ANDEN skærm
end den man ser exposéet på (fx vindue på DP-1, exposé på DP-3, drop på ny celle på DP-1 ⇒ ws på DP-3).

✅ Fix = **fokus-dans**: fokusér target-monitoren → silent ws-move → fokusér tilbage til exposéets
monitor (så overlayet bliver stående). Kun nødvendigt når target-monitor ≠ exposéets monitor:

```js
const overlayMon = Hyprland.focusedMonitor.name;
if (target !== overlayMon) Hyprland.dispatch(`hl.dsp.focus({monitor='${target}'})`);
Hyprland.dispatch(`hl.dsp.window.move({workspace='${realId}', follow=false, window='address:${addr}'})`);
if (target !== overlayMon) Hyprland.dispatch(`hl.dsp.focus({monitor='${overlayMon}'})`);
```

## 4. ✅ Skift monitor M til virtuel ws V (klik på workspace-celle)

Samme mønster — **monitor først, så workspace** (ellers ghoster tom celle):

```js
Hyprland.dispatch(`hl.dsp.focus({monitor='${M}'})`)
Hyprland.dispatch(`hl.dsp.focus({workspace='${realId}'})`)
```

Bekræftet: `focus({monitor='DP-3'})` + `focus({workspace='18'})` fra DP-1 ⇒ ws 18 på DP-3,
ingen ghost. (Plain `focus({workspace='18'})` alene ⇒ ghost på fokuseret monitor.)

## 5. ✅ Special/scratch-ws (den nemme case — monitor-bundne)

```js
Hyprland.dispatch(`hl.dsp.window.move({workspace='special:${name}', window='address:${addr}'})`)
```

Pålidelig; special-ws er monitor-bundne via ws-rules. Verificeret: vindue på DP-3 → move til
`special:scratchbottomright` (DP-1-bundet) landede korrekt på DP-1.
Live special-ws: DP-1 = `scratchright`, `scratchbottomright`; DP-3 = `scratchleft`, `scratchbottomleft`.

## 6. ✅ Fokus + luk vindue

```js
Hyprland.dispatch(`hl.dsp.focus({window='address:${addr}'})`)   // fokusér (klik)
Hyprland.dispatch(`hl.dsp.window.close('address:${addr}')`)     // luk (middle-klik)
```

## 7. Konsekvenser for UI-koden

- `MonitorSection`/`Canvas`: udled blokken fra `prio_index * 10`, IKKE fra aktiv ws.
  Prio-rækkefølgen er `monitor_priority = { "DP-1", "DP-3" }`; map monitornavn → index.
  (Robust fallback hvis priority ikke kan læses: sortér monitorer efter deres laveste
  ejede real-ws-id og brug rækkefølgen som index.)
- Alle window-moves og ws-switches: **target monitoren først, så workspace** — det er det
  ene princip der eliminerer ghosts.
