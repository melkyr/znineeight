# undersanded M10.1 — settlement + field feedback UX — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** every screen answers “what just happened?” and “what do I do next?”; no field transition is silent; Release/Sell is an informed choice; no irreversible action is one mis-pressed key away.

**Architecture:** one transient one-action status line (`NavState.field_msg`) fed by explicit field events (`GameState.last_event`) and rendered by the shared `navResultLine` path (stdout + window row 29). Subdue gets an explicit intro screen (`NAV_SUBDUE_INTRO`); settlement uses `1`/`2`. Help pages, copy, and terminal/art widgets are corrected; behavior/RNG/save semantics are unchanged.

**Tech Stack:** Z98 → C89 `-fsafe`; existing nav/render/fight/expedition; native tier.

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §7.1 (binding copy/status contract), §9.3, §9.7, §18, §27, §28, §36, §38 P30.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must run in CI without Wine.

**No behavior change:** no RNG draw, phase count, save field/version, or fight resolution changes. This milestone changes presentation/feedback only. `canSave` semantics stay as M7. Subdue still awards loot immediately; Release/Sell still keep parts.

**Status-line contract (binding):** the exact strings in spec §7.1; terminal prints after the frame, window renders cell row 29; one action lifetime, cleared at the start of the next key (including no-ops). Status line is UI-only (`NavState`), never persisted.

**Settlement contract (binding):** `NAV_SUBDUE_INTRO` → `[C]ontinue` → `NAV_SETTLE`; settlement keys `1`/`2` only. No `R`/`S` on settle. Header `UNDERSANDED  SETTLE`; the creature name and both effects must be visible. Art intro is a modal over the last fight frame; cell intro is a full screen.

**Help contract:** pages 1–9; page map exactly as spec §7.1; `[?] Help` on every screen footer; `[J]ournal` on dock/field screens when a save is active. `?` consumes the key and never mutates game state.

**Console boot:** `undtool.exe --play` skipping boot is accepted (test-only; `under.exe` is the real game). Record, do not fix.

**Files/editing:** use edit/fastedit only; no sed/awk/python. Explicit array types, no `?[N]T` returns, no fixed-array returns, avoid nested-array indexed writes. No side fixes.

## Review Focus

- Settlement is still an irreversible choice: R/S must not work, and the copy must name the creature and both effects (spec §7.1).
- The status line must not overwrite a live art log or the fight log; it is for screens after a fight, not mid-fight.
- GameState event fields are transient and must be zeroed/reset; never persisted; no save-version change.
- `NavState` must be explicitly initialized everywhere; missing `field_msg_len` would print garbage.
- Help page map and `manual.9` must not break the loader's `[text]` vocabulary or content tests.
- Golden churn must be intentional: normal dock/map/node/fight goldens may change for copy/red-zone/status; terminal/M8/M9 goldens must be re-pinned only where the new copy appears. Art fight golden re-pins at most once (subdue intro modal is a new state, not the normal fight).

---

### Task 0: Preflight

**Files:** `examples/z98/undersanded/NOTES.md`

- [ ] Record baseline `TIER_M10 PASS 71/0`, `TIER_EDIT PASS 38/0`, compiler id, and the exact copy table/status-line/page-map from spec §7.1. Record P30, the console-boot ruling, the settle keys `1`/`2`, `C` continue, and the list of goldens expected to change.
- [ ] Add a `## M10.1 preflight` section; do not change code. Commit `example(undersanded): M10.1 preflight`.

### Task 1: Field status infrastructure

**Files:**
- Modify: `examples/z98/undersanded/def.zig`, `game.zig`, `nav.zig`
- Test: `examples/z98/undersanded/tests/ux_test.zig`

**Interfaces:**
- `def.EV_NONE=0`, `EV_DEPART=1`, `EV_REST_NODE=2`, `EV_ROUGH=3`, `EV_REST_DOCK=4`, `EV_SURFACE=5`, `EV_SUBDUE=6`, `EV_KILL=7`, `EV_OVERKILL=8`, `EV_CREATURE_FLED=9`, `EV_PLAYER_FLED=10`, `EV_ASCENT=11`, `EV_HUNT_MAX=12`, `EV_HUNT_EMPTY=13`, `EV_RELEASED=14`, `EV_SOLD=15`.
- `GameState` gains `last_event: i32`, `last_event_def: i32`, `last_event_value: i32` (transient; zeroed by `game.newGame`/`startFight`).
- `NavState` gains `field_msg: [96]u8`, `field_msg_len: usize`; `pub fn initState() NavState` explicitly zeroes every field. `navRun`, `loop_gfx`, and all test constructors use it.
- `pub fn navClearFieldMsg(st: *NavState) void`, `pub fn navSetFieldMsg(st: *NavState, text: []const u8) void`, `pub fn navSetFieldMsgInt(st: *NavState, prefix: []const u8, value: i32, suffix: []const u8) void`.
- `navResultLine` returns `st.field_msg` first, then the existing dock result/preview.

- [ ] Tests `ux_test.zig`: `field_msg_cleared_on_next_key`, `init_state_zeroes_every_field`, `nav_result_line_prefers_field_msg`, `field_msg_does_not_change_phase_or_rng`. Run natively; PASS. Commit `example(undersanded): field status infrastructure`.

### Task 2: Subdue intro + settlement choice

**Files:**
- Modify: `def.zig`, `expedition.zig`, `nav.zig`, `render_term.zig`, `render_art.zig`, `loop_gfx.zig`, `undtool.zig`
- Test: `tests/ux_test.zig`, `tests/screens_test.zig`, `tests/nav_test.zig`
- Goldens: `tests/fixtures/dump_grid_subdue.golden`, `dump_grid_settle.golden` (new)

**Interfaces:**
- `def.NAV_SUBDUE_INTRO = 24`.
- `expedition.postFight` on `OUT_SUBDUE` sets `g.screen = NAV_SUBDUE_INTRO` after loot/log/hull. `nav.deriveScreen` preserves it while pending; otherwise `NAV_SETTLE`.
- `nav` pending block: intro accepts only `C`/`c` and moves to `NAV_SETTLE`; `1`→Release, `2`→Sell on settle; every other key is a no-op. `R`/`S` are never settlement keys.
- `render_term.renderNode`: intro header/copy from spec §7.1; settle header `UNDERSANDED  SETTLE`, creature name, secured parts, release/sell lines with `creatures.defAt(...).sale`; no Rest hint.
- `render_art`: `NAV_SUBDUE_INTRO` is an art mode; draw the existing fight frame and a centered modal `SUBDUED <name>` / `[C]ontinue`; no RNG/phase.
- `undtool --dump-grid --screen subdue|settle` renders the two new states with a synthetic pending subdue.

- [ ] Tests: `subdue_intro_before_settle`, `settle_ignores_r_and_s`, `settle_1_releases_2_sells`, `settle_copy_names_creature_and_effects`, `subdue_intro_no_rng_no_phase`; update old settle R/S tests. Goldens byte-compare. Commit `example(undersanded): subdue intro + settlement UX`.

### Task 3: Field event status

**Files:** `expedition.zig`, `nav.zig`, `render_term.zig`, `tests/ux_test.zig`

- [ ] `expedition` sets `last_event`/`last_event_def`/`last_event_value` for depart, node/dock rest, rough sleep, surface, subdue/kill/overkill, creature flee, player flee, Hull-0 ascent, hunt max/empty, released/sold.
- [ ] `nav` consumes the event after `navStep` into `st.field_msg` using the §7.1 copy; clears the event; clears the message at the next key. No-op refusals set their specific copy.
- [ ] Tests: one case per event, exact copy; `no_event_no_status`; `status_clears_next_key`; `event_does_not_change_phase_or_rng`; kill/overkill/flee/ascent copy survives the screen change. Commit `example(undersanded): field event status lines`.

### Task 4: Silent mechanics visibility

**Files:** `fight.zig`, `fight_rules.zig`, `expedition.zig`, `world.zig`, `render_term.zig`, `render_art.zig`, `tests/ux_test.zig`

- [ ] Add fight-start logs `MSG_WARY` (`This one remembers: +15 Resolve.`) and `MSG_GRUDGE` (`It remembers the last run: +30 Resolve` / armor). Add message rows + tests.
- [ ] Display rough-sleep condition: `COND <name>` in terminal fight stats and art stats; name Drowsy/Shaky/Exposed in node/dock status. Effective modifiers are stated in help (Task 6).
- [ ] Node shows `Rare chance: N%` and lockout state; show `Pool: N` or equivalent availability; map shows actual travel cost including Heavy and a `Heavy +1` note when active.
- [ ] Sale price on settle (Task 2) and `+N coins` result; phase/cycle line on dock/node/map (`Cycle N - Day/Night`); phase spends are reflected in status copy.
- [ ] Tests: wariness/grudge logs, condition visibility, rare/lockout line, Heavy cost display, phase/cycle line, sale/coins. Commit `example(undersanded): visible mechanics feedback`.

### Task 5: Fight feedback polish

**Files:** `fight.zig`, `fight_rules.zig`, `tools.zig`, `render_term.zig`, `render_art.zig`, `render_text.zig`, `tests/ux_test.zig`, `tests/fight_test.zig`, `tests/tools_test.zig`

- [ ] Tool break: add `MSG_TOOL_BROKEN`; log at the moment `onHullHit` breaks; EQUIP refusal returns a reason (`No tool selected.` / `Tool is broken.` / `No charge left.` / `Tool is rigged - always on.`) and logs `MSG_EQUIP_REFUSED`.
- [ ] Blind/ink/phasing/counter tools: log arming and forced actions with names; `MSG_BLIND` copy is corrected to the miss (or split armed/miss); Ink names the forced action; phasing HUD shows `SOLID`/`PHASE`; Lure/Sonar/Hook/Shield suppressions log once.
- [ ] Last Surge modal states the numbers (+25% Resolve, +25% Attack, +2 Speed cap +6); modal keeps HP/RES/HULL visible; `[F] Fight on / decline` and `[Esc] Decline` clearly both decline.
- [ ] Terminal fight: red-zone `|` marker, `COND` line, `[E] Use tool` label; art notices no longer overwrite the newest log line.
- [ ] Tests + goldens: `dump_grid_fight.golden` updated intentionally; art golden re-pinned at most once (new intro state only; normal fight unchanged unless copy requires). Commit `example(undersanded): fight feedback polish`.

### Task 6: Help, journal, tooltips, discoverability

**Files:** `journal.zig`, `render_term.zig`, `render_art.zig`, `data.z98`, `data_schema.zig`, `tests/ux_test.zig`, `tests/content_test.zig`, `tests/help_test.zig`

- [ ] Add `manual.9` (Journal & Speed) and update `manual.3` (Release/Sell), `manual.5` (rough sleep/phases), `manual.6` (each tool), `manual.7` (boss gate), `manual.1` (dock action index). Extend `[text]` vocabulary to `manual.1..9`; keep `MAX_TEXT_KEYS`/bytes.
- [ ] Fix page map exactly as §7.1 (CRAFT/TOOLS→6, JOURNAL→9, NODE→5). Add `[?] Help` to every footer and `[J]ournal` on dock/field. Add `SPD ??` explanation.
- [ ] Add one-line effect text for tools, boat axes, and cosmetics (locked cosmetics name their unlock condition). Add `?` to boot/menu/lore/save-error.
- [ ] Tests: page map, manual.9 present, help render goldens, `?` consumes no action/RNG, tool/upgrade/cosmetic copy, Journal hint. Commit `example(undersanded): help + discoverability`.

### Task 7: Boot/save safety

**Files:** `render_term.zig`, `nav.zig`, `save_ux.zig`, `tests/ux_test.zig`

- [ ] Wrap first-run lore at 80 columns (preserve `\n\n` paragraphs); re-pin `dump_grid_lore.golden`.
- [ ] Save-error `[F]resh` asks `Erase this save? [Y] [N]`; only `Y` erases, `N` returns. Add `boot_pending=2` handling; tests.
- [ ] Record console boot as test-only in NOTES/README; no console boot implementation.
- [ ] Tests: lore no clipping, Fresh cancel/erase, save error copy. Commit `example(undersanded): boot + save UX safety`.

### Task 8: Residual copy polish

**Files:** `dock.zig`, `nav.zig`, `render_term.zig`, `save_ux.zig`, `loop_gfx.zig`, tests

- [ ] Dock results name the amount (`Refined X; E+1`, `Upgraded <axis> to Tn`); 0-yield deep refine explains the expertise gain; rare-arm cancel says `Rare batch cancelled.`; buy locked shows the condition; quit Cancel prints `Stayed.`; Saved reports slot; stale `Secured:` clears after a non-settlement action; art notice gets its own row/does not cover the log.
- [ ] Tests for each copy/state. Commit `example(undersanded): UX copy polish`.

### Task 9: UX tier

**Files:** `tests/tier_m101_ux.sh`, `tests/ux_test.zig`, `README.md`, goldens

- [ ] Tier nests `tier_m10_assets.sh`; runs UX tests, page-map/help goldens, settle/intro/status goldens, real `under.exe` path checks; non-vacuous (mutate a golden copy → fail); no Python. Update README key/status help.
- [ ] Run from repo root and `/tmp` with fresh OUT; `TIER_M10.1 PASS`, nested `TIER_M10 PASS`. Commit `example(undersanded): M10.1 UX tier`.

### Task 10: M11 amendment review

**Files:** `examples/z98/undersanded/NOTES.md`

- [ ] Record M11 amendments: new `NAV_SUBDUE_INTRO`/status plumbing, `assets.zig` accessors for boss variants/overlays, boat hull bbox `x=30,y=42,w=153,h=67` + paint shade mapping, `journalOnBossKill` wiring, and the M11 file-list additions. No M11 code. Commit `example(undersanded): M11 amendment review`.

**Gate:** every field transition has a visible status; settlement names creature + effects and uses 1/2; no silent state change; `TIER_M10` green; M10.1 tier green; terminal/art parity. Full art polish, Esc menu, boss journal wiring, `legend.1/2`, `zone.4..8`, `error.*` remain deferred.
