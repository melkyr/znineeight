# undersanded M6 — data tables + loader — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `data.z98` (§25.10) and its loader: every game table parsed from one human-readable file into the §25.1/§25.2 structs, with **spec-complete T1 content** (18 creature rows incl. names, masks and §14.4 drops), strict validation, loader goldens, malformed-input rejection, and the game running from the file.

**Architecture:** `def.zig` owns the schema (`CreatureDef` + `Tables` + the row structs moved there from `tables_t1`, which re-exports them). `data.zig` scans/parses into a static `Tables`; `validate.zig` enforces invariants. Consumers reach content through the existing accessors (`defAt`, `rows`) plus accessor twins for the const arrays, backed by a `def.content_override: ?*Tables` installed by the loader — the compiled-in `creatures_t1`/`tables_t1` stay as the fallback/golden (verified legal in Z98: `?*T` global + `if (o) |p|`).

**Tech Stack:** Z98 → C89 `-fsafe -W`; `std_file`/`std_arena`/`std_str`/`std_parse` (M1); fixed arrays, no generics (R14).

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §25.1 (capacities incl. `MAX_NAME_LEN`/`MAX_TEXT_KEYS`/`MAX_TEXT_BYTES`), §25.2, §25.10 (file format, binding), §14.2/§14.4 (T1 rows), §12–§13 (zones/encounters), §32 (location), §33 (fatal copy), §35 (arena/tables budget), §38 P23.

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m05-dock-economy-plan.md`. NEXT: `2026-11-12-undersanded-m07-save-system-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must run in CI without Wine.

As prior. Loader must fit `MAX_CREATURES=56`, `MAX_ZONES=12`, `MAX_RULES=96`, `MAX_DROP_LINES=4`, `MAX_ENCOUNTER=24` (**per zone per phase**), `MAX_PARTS=14`, `MAX_MATERIALS=10`, `MAX_TOOLS=8`, `MAX_COSMETICS=12`, `MAX_NAME_LEN=24`, `MAX_TEXT_KEYS=256`, `MAX_TEXT_BYTES=48*1024` exactly (spec §25.1 — never resize). Fatal parse errors use spec §33 copy. Every field explicitly initialized (R8); `switch` needs `else` (R3). No Python. Z98 drops writes through nested struct arrays (D18) — use whole-struct initializers or pointer workarounds.

**M6 kickoff rulings (spec §38 P23):** accessor-with-override; `CreatureDef.name`; §25.10 grammar as written; **spec-complete** §14.4 drops for all 18 rows (drop-dependent goldens are re-pinned HERE); static `Tables` + 256 KB arena for the file buffer/strings; `undtool` tools tolerate a missing file (fallback), the game does not.

## File Structure

- `examples/z98/undersanded/def.zig` — §25.1 constants, `CreatureDef.name/name_len`, `Tables`, row structs (`CostSlot/ToolRow/UpgradeRow/CosmeticRow/EncounterRow/TextEntry`), `content_override`.
- `examples/z98/undersanded/data.z98` — spec-complete T1 content (§14.2 stats/names/masks, §14.4 drops, rules, tools, upgrades, cosmetics, Z1–Z3 encounters, empty Z4–Z8, `manual.1` text).
- `examples/z98/undersanded/data.zig` — scanner, section dispatch, field parsers, `g_tables` + install.
- `examples/z98/undersanded/validate.zig` — post-load invariants.
- `examples/z98/undersanded/creatures_t1.zig`, `tables_t1.zig` — fallback content + accessor twins (`rules()`, `tools()`, `upgrades()`, `cosmetics()`, `zoneCost()`, `zoneIsBoss()`); re-export moved row structs.
- `examples/z98/undersanded/tests/data_test.zig`, `validate_test.zig`, `tests/tier_m6_data.sh`, `tests/fixtures/data_good.z98`, `defs_golden.txt`, `data_bad_*.z98`.
- Touched for binding: `app.zig` (arena 256 KB + load + fatal path), `build.sh` (copy `data.z98`), `undtool.zig`/`undtool_native.zig`/`README.md` (`--dump-defs`), `render_term.zig` (name from def), `tests/fight_test.zig` (drop its duplicate name switch).

## Review Focus

- Silent truncation when a table exceeds capacity (hard error, not a clamp) → over-capacity fixture rejects with a line number; 56 ok / 57 rejects.
- Loaded tables drifting from the compiled-in fallback (names, masks, drops) → field-by-field transcription test over all 18 rows + all four tables.
- Boss sentinel inverted (`subdue_chance=-1` iff `F_BOSS`) → both rejection fixtures (boss row is a fixture now; the real row is M8/M11).
- Encounter weights that do not sum to 100 per zone/phase, or reference a `def_index` ≥ loaded count → referential fixture with line number.
- Rule packing (`owner=`) producing gaps/overlaps, or ops out of range → partition fixture; `rule_start/rule_count` must be loader-computed and equal the fallback's.
- Rows half-applied on a bad number (must be all-or-nothing) → fixture with one bad field leaves `Tables` unchanged.
- Golden honesty: `defs_golden.txt` is a **field-by-field** dump (never raw struct bytes; padding/0xAA).

---

### Task 0: Preflight

- [ ] Append `### M6 preflight` to `NOTES.md`: point at spec §25.10 + P23; record the Z98 override probe result (`?*Tables` global, `&g_tables`, `if (o) |p|`, fallback→override verified on seed v151); record the M5 baseline (`TIER_M5 PASS 57/0`, nested M4 47/0); list the goldens expected to move (only `tests/fixtures/loop_golden.txt`, plus any driver that hardcodes a blank drop table); note the two recorded follow-ups — (a) `MAX_DROP_LINES=4` cannot hold the Derelict's 5-line kill table (§39 TBD, resolve M8/M11), (b) for the M7 Task 7 review, M8's Task 1/2 wording needs reconciling because M6 now ships the rows/names/masks/drops. Commit `example(undersanded): M6 preflight`.

### Task 1: Schema + complete T1 fallback rows

**Interfaces (the contract for M7/M13):** in `def.zig`: the §25.1 constants; `CreatureDef` gains `name: [MAX_NAME_LEN]u8, name_len: i32` (after `id`); `pub const CostSlot/ToolRow/UpgradeRow/CosmeticRow/EncounterRow/TextEntry`; `pub const Tables = struct { defs: [MAX_CREATURES]CreatureDef, def_count: i32, rules: [MAX_RULES]Rule, rule_count: i32, tools: [MAX_TOOLS]ToolRow, tool_count: i32, upgrades: [15]UpgradeRow, upgrade_count: i32, cosmetics: [MAX_COSMETICS]CosmeticRow, cosmetic_count: i32, encounters: [MAX_ZONES * 2 * MAX_ENCOUNTER]EncounterRow, enc_count: [MAX_ZONES * 2]i32, zone_cost: [MAX_ZONES]i32, zone_boss: [MAX_ZONES]i32, text_key: [MAX_TEXT_KEYS][]const u8, text_val: [MAX_TEXT_KEYS][]const u8, text_count: i32, content_version: i32 }`; `pub var content_override: ?*Tables = null`. `Rule` moves to `def.zig` (`behavior` re-exports `pub const Rule = def.Rule`, its op constants stay in `behavior.zig`).
- [ ] Move the row structs to `def.zig`; re-export from `tables_t1`/`behavior` so no call site changes. Fill names, real `zone_mask`/`phase_mask` (bit z = zone index, bit0 Day/bit1 Night; §14.2 columns), and the **§14.4 drops for all 18 rows** (the five blank tables become spec-complete). Replace `render.creatureName(id)` with `creatureName(d: *const def.CreatureDef) []const u8` returning `name[0..name_len]`; update its callers and delete `fight_test`'s duplicate switch. Re-pin `loop_golden.txt` (drops moved) and any hardcoded drop expectation to spec values.
- [ ] Unit tests: name non-empty/unique ≤24; masks match §14.2 for all 18; drops match §14.4 per creature (explicit expected rows, not an oracle copy); `Tables` size budget sanity if cheap. Run `tier_m5_dock.sh` → PASS (nested M4 green). Commit `example(undersanded): content schema + complete T1 rows`.

### Task 2: Scanner + scalar parsers (`data.zig`)

**Interfaces:** `pub fn parseI32(s: []const u8) ?i32` (thin wrapper over `std_parse.parseInt`; no twin in `std_str`); `pub const RowField = struct { key: []const u8, val: []const u8 };` `pub const ROW_MAX = 40;` `pub fn parseRowKV(line: []const u8, out: *[ROW_MAX]RowField, n: *usize) bool`; `pub fn sectionId(name: []const u8) i32`.
- [ ] Load the whole file with `std_file.readAll(&arena, path)`; split on `\n` (`\r` stripped); enforce §25.10 (header first, known sections, comments/blank, 4096-byte line cap, unknown/duplicate keys, all-or-nothing rows). Parse into a temp row then commit.
- [ ] Unit tests: parseI32 edges (±, overflow, empty, garbage); header not `format=2` rejected; unknown section/key; duplicate key; 4097-byte line; a bad field in row N leaves `Tables` unchanged; `\r\n` accepted. PASS. Commit `example(undersanded): data scanner + row parser`.

### Task 3: Sections + `--dump-defs` + `data.z98`

**Interfaces:** `pub fn loadFile(path: []const u8, tables: *Tables) LoadErr` (`error{ Missing, DamagedLine, Overflow, BadSentinel, BadRef, TooMany, Io }`, every `std_file` call `catch`-mapped; mapping table recorded in NOTES); `pub fn install(t: *Tables) void` / `pub fn uninstall() void`; `pub fn dumpDefs(t: *const Tables, out: *Buf) void` (field-by-field).
- [ ] Implement `[creatures] [rules] [tools] [upgrades] [cosmetics] [encounter] [zones] [text]` per §25.10 into `Tables`; pack `[rules]` by `owner` first-appearance order and compute `rule_start/rule_count`; store encounters at `zone*2*MAX_ENCOUNTER + phase*MAX_ENCOUNTER`.
- [ ] Write `data.z98` from the Task 1 content (18 rows, 4 rules with `owner=`, 7/15/12 rows, Z1–Z3 encounters, empty Z4–Z8 stubs, real `manual.1` page-1 prose). `undtool --dump-defs <file>` (new flag; add to `undtool_native.zig` header + README; missing arg/bad file → exit 2) prints the field-by-field dump. Commit `tests/fixtures/defs_golden.txt` (force-add; `*.txt` is ignored).
- [ ] Tests: `loadFile(data.z98)` → field-by-field equality against the compiled-in fallback for **every** field of all 18 rows + rules/tools/upgrades/cosmetics/encounters/zones; dump == golden byte-exact; loading a temp file with one changed HP makes `defAt` see the change only after `install`; two dumps byte-identical. PASS. Commit `example(undersanded): data sections + dump-defs golden`.

### Task 4: Validation (`validate.zig`)

**Interfaces:** `pub fn validateAll(t: *const Tables) LoadErr` (same error set; no second error type).
- [ ] Checks: `def_count ≤ 56`; unique `id`; `name` non-empty/short/unique; `subdue_chance == -1` iff `F_BOSS`, else 0..100; `role/family` in range; `zone_mask` bits ⊆ known zones, `phase_mask != 0`; `sale > 0`; `respawn_sub ≤ respawn_kill ≤ respawn_over`; drop `count 0..99` and part `0..13` (0 = empty slot, blanks allowed); `rule_start/rule_count` a complete contiguous partition of `rule_count` rows with ops in range; tool ids 1..7 unique, kind 0/1, cost kinds 0 or 1..9, no duplicate/negative cost kinds; full 5×3 upgrade grid with kinds 0 / 1..7 / 8..9 (reject ≥10 and negatives); 12 cosmetics, `unlock` 1..4, `price > 0`; encounter `def_index < def_count`, `zone < 12`, `phase` 0/1, `weight > 0`, per-zone/phase sum exactly 100 or empty; zone cost ≥ 0, boss 0/1; `content_version == 2`; text caps + known key vocabulary.
- [ ] One `data_bad_*.z98` fixture per rejection rule, each asserting the exact error + line number; plus `validateAll(fallback-built Tables) == 0 errors` and the same for `data_good.z98`. PASS. Commit `example(undersanded): loader validation + rejection fixtures`.

### Task 5: Bind the game to the file

- [ ] `app.zig`: `ARENA_SIZE` 64 KB → **256 KB** (§35); resolve the exe dir (M1 `paths`), read/load/validate `data.z98` from it, `install()`, then run; missing → "Content file missing. Reinstall from CD.", damaged → §33 damaged copy (line N); no silent fallback in the game. Keep the M1 `sample.txt`/`probe_out` diagnostics untouched.
- [ ] Accessor twins: `creatures.rules()` / `tables.tools()` / `tables.upgrades()` / `tables.cosmetics()` / `tables.zoneCost(i)` / `tables.zoneIsBoss(i)`; replace the const-array call sites in `world/encounter/expedition/tools/dock/economy/render_term/sim/undtool` (≈20 refs); `creatures.defAt/defCount` and `tables.rows` consult `def.content_override`. `undtool` tool paths load `data.z98` beside the exe when present, else keep the fallback (never fail); `--dump-defs` always takes an explicit path.
- [ ] `build.sh` copies `data.z98` beside `under.exe`/`undtool.exe` (like `sample.txt`); `tests/tier_m1_std.sh` copies `tests/fixtures/../data.z98` (or the repo `data.z98`) beside the CUI exe it builds, since the console entry now loads content.
- [ ] Tests: a temp `data.z98` with a changed `hp`/sale/weight is observed through `defAt`/`rows` after `install`; `uninstall` restores the fallback; game startup on a missing file prints the missing copy and exits non-zero (headless check via the console entry); arena accounting stays within §35. PASS. Commit `example(undersanded): game loads data.z98`.

### Task 6: `tier_m6_data.sh`

- [ ] FAST/native tier: Tasks 1–4 drivers + `--dump-defs` golden + `data_good`/all `data_bad_*` fixtures + fallback≡loaded transcription + 56-creature boundary (56 ok / 57 rejects) + empty Z4–Z8 load + loaded-path override test; **nests `tier_m5_dock.sh`** (which nests M4→M3) and fails on any non-zero. No Python. Non-vacuous (mutate a fixture in a `/tmp` copy and watch it fail). Run PASS. Commit `example(undersanded): M6 data tier`.

**Gate:** loader goldens pass; loaded T1 == compiled-in fallback field-for-field; every malformed class rejected with its line number; 56/57 proven; the game boots and reads content from `data.z98`.

### Task 7: Next-milestone amendment review (M7)

- [ ] Read `2026-11-12-undersanded-m07-save-system-plan.md`; judge parser reuse (the save grammar vs §25.10), `data_version` ↔ `content_version`, the `[text]` page-1 handoff, and the persisted-field list against the P23 shapes. Record the M8-plan reconciliation note (M6 now authors rows/names/masks/drops). Amendment or "no amendment needed" in NOTES.md; doc-only. Commit `example(undersanded): M7 amendment review`.
