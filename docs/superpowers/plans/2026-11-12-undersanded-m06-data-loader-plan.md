# undersanded M6 — data tables + loader — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The `data.z98` text format and loader: all game tables (creatures, rules, drops, tools, upgrades, cosmetics, encounters, text) parsed from one human-readable file into the §25.1/§25.2 structs, with full-size capacities, strict validation, loader goldens, and malformed-input rejection.

**Architecture:** `data.zig` parses with `std_str` (`parseInt`, `splitOnce`, `trim`, `split`) into the fixed arrays; `validate.zig` enforces the invariants (boss sentinel, ranges, capacities, referential integrity). `data.z98` lives in the exe directory (spec §32); M8 authoring replaces the hardcoded `tables_t1.zig` source with file content — schema is identical, so only the source binding changes.

**Tech Stack:** Z98 → C89 `-fsafe`; std_str/std_file (M1); no generics (R14) — fixed arrays + runtime parse.

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §25.1–25.2 (capacities + `CreatureDef`), §25.6 (`Rule` rows), §12–13 (zone/encounter schema), §30 (8.3 filename rule for text keys), §32 (data.z98 location + parse-error copy), §33 (fatal messages), §36 (M6 row).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m05-dock-economy-plan.md`. NEXT: `2026-11-12-undersanded-m07-save-system-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. Loader must fit `MAX_CREATURES=56`, `MAX_ZONES=12`, `MAX_RULES=96`, `MAX_DROP_LINES=4`, `MAX_ENCOUNTER=24`, `MAX_PARTS=14`, `MAX_MATERIALS=10`, `MAX_TOOLS=8`, `MAX_COSMETICS=12` exactly (spec §25.1 — never resize). Fatal parse errors print spec §33 copy ("Content file is damaged at line N. Reinstall from CD."). Every field explicitly initialized (R8); `switch` needs `else` (R3).

## File Structure

- `examples/z98/undersanded/data.zig` — line scanner, section dispatch, field parsers.
- `examples/z98/undersanded/validate.zig` — post-load invariant checks.
- `examples/z98/undersanded/data.z98` — the content file (T1 rows from spec §14; Z4–Z8 stub sections; tools/upgrades/cosmetics §10–§11; text: journal/manual/legends placeholders until M8).
- `examples/z98/undersanded/tests/data_test.zig`, `tests/tier_m6_data.sh`, `tests/fixtures/data_good.z98`, `tests/fixtures/data_bad_*.z98` (one per rejection rule).

## Review Focus

- Silent truncation when a table exceeds capacity (must be a hard error, not a clamp) → over-capacity fixture rejects with line number.
- Boss sentinel inverted (boss must have `subdue_chance=-1`, non-boss must not) → both rejection fixtures (spec §34 row).
- Encounter weights that don't renormalize or reference unknown creature ids → referential-integrity fixture.
- Rule rows referencing out-of-range ops/ids → op-range fixture; `rule_start/rule_count` slice bounds fixture.
- Integer parse overflow / garbage fields half-applied → parser is all-or-nothing per row: fixture with one bad number must leave defs unchanged.

---

### Task 0: Preflight

- [ ] Freeze the file format in NOTES.md before coding: line grammar `key=value` and `[section]` headers; **row grammar = comma-separated `key=value` fields per row** (order-free; field names exactly the §25.2 names; unknown/missing key → DamagedLine — kills the M6-vs-M8 positional-order class of bug entirely). Comments `#`; blank lines ok. Header `format=2` (published as `content_version`; save `data_version` must equal it — bumped only by spec amendment). Line buffer capacity **4096 bytes**. ASCII only (era codepage rule).

### Task 1: Scanner + scalar parsers (`data.zig`)

**Interfaces (consumed by M7 save too — reuse, do not fork):** `pub fn parseI32(s: []const u8) ?i32`; `pub fn parseRowKV(line: []const u8, out: *RowBuf, max: usize) ?usize` (key=value pairs); parser records **per-row line numbers** (side table) so validate errors can cite lines; `pub fn loadFile(path: []const u8, world: *World, defs: *[56]CreatureDef, n: *i32, tables: *Tables) LoadErr` (named error set, R15: `error{ Missing, DamagedLine, Overflow, BadSentinel, BadRef, TooMany, Io }`); every `std_file` call is `catch`-mapped into these (R15 try-superset — document the mapping in NOTES.md). **`Tables` contract (one line):** `Tables = { defs, rules, tools, upgrades, cosmetics, encounters, zones, text }`.
- [ ] Unit tests: parseI32 edges (from M2 + overflow); row arity mismatch → DamagedLine with line number; partial-row application impossible (parse into temp, commit on success). Implement. PASS. Commit `example(undersanded): data scanner + scalar parsers`.

### Task 2: Table sections

**Interfaces:** sections `[creatures]` (one KV row per creature incl. 3 drop lines + `respawn[3]` + `rule_start/rule_count`), `[rules]` (KV rows §25.6), `[tools]`, `[upgrades]`, `[cosmetics]`, `[encounter]` (zone/phase/creature/weight KV rows), `[zones]` (id, travel cost, boss flag), `[text]` (**multi-line**: entry starts `key=` then continuation lines indented one space until next key; MAX_TEXT_KEYS=256, total text bytes ≤ 48 KB inside the 256 KB arena; prose with `=`/`,` safe, `#` only at line start is a comment).
- [ ] Golden: `data_good.z98` (subset + Z1–Z3 encounter rows + stubs) loads; `--dump-defs` emits a **field-by-field text dump** (never struct bytes — padding/0xAA poison) compared to `tests/fixtures/defs_golden.txt`. **ID contract (frozen):** creature `name` strings are append-only forever — rows are never reordered or removed (saves index by load-order def index; M13 appends at the end). Implement sections. PASS. Commit `example(undersanded): data table sections + golden`.

### Task 3: Validation (`validate.zig`)

**Interfaces:** `pub fn validateAll(defs, n, rules, nr, world_tables) ValidateErr` — checks: `subdue_chance == -1` iff `flags & F_BOSS`; else 0..100 · zone_mask ⊂ known zones · phase_mask ≠ 0 · `rule_start+rule_count` ≤ rules loaded and ops in range · drop lines: `0 < count ≤ 99`, part ids < MAX_PARTS · encounter rows reference loaded creature ids and zone ids · weights > 0 · weight-sum check per zone/phase (M4 rule) · max-text-keys/bytes check.
- [ ] One `data_bad_*.z98` fixture per rule asserting the exact error + line number. Implement. PASS. Commit `example(undersanded): loader validation + rejection fixtures`.

### Task 4: Bind game to file source

- [ ] Swap `tables_t1.zig` consumers to load `data.z98` at startup (keep `tables_t1.zig` only as the golden source fixture). Startup path: resolve data dir (M1) → read `data.z98` from exe dir → load → validate → run. Missing file → spec §33 fatal copy path. Commit `example(undersanded): game loads data.z98`.

### Task 5: `tier_m6_data.sh`

- [ ] Tier: Tasks 1–3 unit tests + all fixtures + `--dump-defs` golden + empty-stub Z4–Z8 loads + 56-creature capacity boundary (56 ok / 57 rejects). Non-vacuous. Run PASS. Commit `example(undersanded): M6 data tier`.

**Gate:** loader goldens pass; every malformed class rejected with line numbers; capacities proven at full size.

### Task 6: Next-milestone amendment review (M7)

- [ ] Read `2026-11-12-undersanded-m07-save-system-plan.md`; judge parser reuse (M7 serializes with the same grammar) and the `[text]`/save-section overlap. Amendment or "no amendment needed" in NOTES.md.
