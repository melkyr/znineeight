# Packed Struct Core (P1–P3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `packed struct` for field types `bool`/`uN`/`iN` — parse, backend-neutral bit-layout, LIR `load_bitfield`/`store_bitfield`, and a C89 single-member-struct carrier shift/mask emitter — turning the committed L0/L1/L2 packed RED fixtures GREEN with their locked byte-exact contracts.

**Architecture:** `packed struct` = existing `struct_type` + flags bit4 (`is_packed`) + a bit-layout side table; the C89 emitter owns byte packing (never C bitfields). Three stacked change layers (parse/type/sema → LIR/DCE → emitter), each byte-neutral for non-packed programs until the emitter layer turns the fixtures GREEN. Executes AFTER INTWIDTH (uN registry, `intWidthBits`/`intIsSigned`).

Design spec: `docs/superpowers/specs/2026-09-06-packed-struct-core-design.md` (operator-approved).

## Global Constraints

- **Depends on INTWIDTH executed first** (its `Type.width_bits`/`is_signed` + `intWidthBits(ty) u8`/`intIsSigned(ty) bool` helpers + uN/iN registration). PACK-CORE never re-implements uN registration.
- No `sf/src` edit may change emission of any non-packed program: the 4-MD5 gate (gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `846106ac`), golden 9/9, matrix 21/21, and the self-compile fixed point's byte-identity must hold on every F task until the emitter layer lands. The self-compile fixed point will move once the emitter layer is committed → operator-ruled re-baseline at Task 6 (never silent).
- `examples/z98` originals, gate programs, goldens, `sf/build/`, `out_release/` untouched. Stage ONLY intended files. Pre-existing dirty/untracked set (2026-08-26 plan doc, `mnemoria/*`, `.zig1_*.tmp`, `build/`, `examples/z98/json_parser_upgraded/`) never staged.
- Reference compiler: `/tmp/fx_subfolder/zig1` per the SEEDMIG seed model (committed seed `release/seed/zig1-seed.tgz` = zig0-built reference binary md5 `3707d33b…` + self-emission C; fixed point `24da89b9…`; provenance `release/seed/CHANGELOG.md`). Forward rebuild path: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh-out>` — NEVER point `<fresh-out>` at `/tmp/fx_subfolder` (the script `rm -rf`s it); std lib (4 std `.zig`) is copied to `<fresh-out>/lib` by the script. `bash sf/scripts/build_release.sh` (zig0) remains usable ONLY while zig0 still compiles the current `sf/src` subset; the moment a task's `sf/src` needs syntax zig0 cannot parse, rebuild the reference from the seed (STOP-present on first such use). Bootstrap-staging constraint (binding): this plan's `sf/src` feature code must be written in constructs the current seed (`24da89b9`-era) already understands; `sf/src` may adopt packed syntax only after the Task-6 fixed-point re-baseline + Task-7 seed rotation. Fixture run/classify recipe: authoritative copy in `.superpowers/sdd/task-LANGWINS-report.md` Step-4 (fresh-dir `rm -rf`+`mkdir -p` REQUIRED). Feed `bash /tmp/sd_work/fixture_run.sh` equivalents per that recipe.
- Fastedit per docs/sf/AGENTS.md X.7 (re-read region before every edit; absolute lines; edit bottom-to-top). No python/sed/bulk transforms; no `git checkout` to erase.
- Report: `.superpowers/sdd/task-PACKCORE-report.md` (gitignored). Ledger: `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory`, agent `packcore-session`.
- Per-task evidence contract: status, commits, per-gate md5/evidence, fixture run-gate output, concerns. STOP-present on any divergence/ambiguity/plan-vs-evidence mismatch.
- Subagent-driven execution with the SDD skill (fresh implementer per task, independent reviewer, fix loops, ledger lines).
- **Seed rotation is part of the Task-7 docs-GATE commit** (SEEDMIG model): Task 7 additionally runs `bash scripts/seed/archive_seed.sh <Task-6 fixed-point binary> <fresh gen dir> release/seed/zig1-seed.tgz --update-changelog`, staging `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` alongside EXPECTED_FAIL.md + QUICK_REF.md (the seed rotates ONLY at this operator-approved closeout — never mid-plan).

---

### Task 1: Record-only census + edit-map + RED baseline (no commit)

**Files:**
- Record only: `.superpowers/sdd/task-PACKCORE-report.md` header + Task 1 section.

**Interfaces:**
- Produces: (a) verified baseline (HEAD, reference md5, 4-MD5 gates, fixed point, EXPECTED_FAIL version at execution); (b) the authoritative packed-adjacent edit-map at the CURRENT post-INTWIDTH HEAD (Task 2-5 implementers consume this; exact function names + anchors, since pre-INTWIDTH line numbers are stale); (c) RED reproduction of L0/L1/L2.

- [ ] **Step 1: Baseline.** `git rev-parse --short HEAD`; `md5sum /tmp/fx_subfolder/zig1`; re-run the 4-MD5 gate (repo-root CWD `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/{game_of_life,lisp_interpreter_curr,json_parser,mud_server}/main.zig | md5sum`); confirm the INTWIDTH-era fixed point (hop1==hop2 dump round-trip); record the current EXPECTED_FAIL header version.

- [ ] **Step 2: RED reproduction.** For each `repro/mi_matrix/packed_{l0_flags,l1_mix,l2_straddle}_xmod/main.zig` run the authoritative classify/run recipe → confirm RED class + 0 `.c` (parse error[2000]) on the current compiler, deterministic. Record.

- [ ] **Step 3: Parser census.** Map the expression-primary path (`parserParsePrimary`, struct-decl parse `parserParseStructType`), the container-decl/statement paths (grammar-completeness only), AST node flags byte + free bits (bit4 `0x10` availability), token keyword table + `kw_*` add pattern, `dump_ast` flag printing if struct flags are printed. Record exact current line anchors.

- [ ] **Step 4: Type/resolution census.** Map: `struct_type` registration/resolution path in type_registry.zig + type_resolver.zig (where the packed flag must land on `Type`), `Type` fields + flags byte + free bits, `FieldEntry` + the struct-fields helpers (`typeRegistryGetStructFields` etc.), where type-layout/field offsets are computed today (non-packed), and where a per-type side table could hang (type registry side arena/caches). Map the introspect fold sites for `@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf`/`@bitOffsetOf` and confirm which already read per-field offsets (F-INTRO) so packed bit-offsets can be added there. Record.

- [ ] **Step 5: LIR + DCE census.** Map `LirInst` variant set + where variants are added, the `lir_stream` raw-byte serialization sites, and enumerate EVERY inst-switch site that must gain `load_bitfield`/`store_bitfield` arms (emitter inst walk; `dceMarkAllReads`, `dceReleaseOperands`, `dceResultPos`, `dceTempIsArray`, `dceBaseEscapes`, `dceMarkLoadGlobalAliases`, any spill/other walks) — the authoritative "arm list" Tasks 4/5 must not miss. Record the store-drop rule sites (f014259b/C4) that need the "is-array **or** is-packed" generalization.

- [ ] **Step 6: Emitter census.** Map: where a struct type's C type name + definition are emitted (packed must instead emit the single-member struct carrier `typedef struct { unsigned char _[N]; } zT_NAME;` per spec AMENDMENT 1), local var decl for a struct-typed temp/value, whole-value assignment/param/return lowering to C (native struct-by-value; note C89 arrays cannot be by-value — the carrier MUST be a struct for L6), `&packed-value` / `[*]u8` casting path, existing struct-typedef precedent, and the small-endian byte gather/shift sites. Record.

- [ ] **Step 7: Report + ledger.** Write the edit-map + baseline into the report; ledger line. No commit, no source edits.

---

### Task 2: Parser `kw_packed` + AST flag + B6 sema gate (byte-neutral)

**Files:**
- Modify (per Task-1 census, exact anchors from the Task-1 edit-map): lexer keyword table + `kw_packed`, parser expression-primary path threading `is_packed` into `parserParseStructType`, AST struct-decl node flags (bit4), semantic analyzer B6 field-type gate for packed structs + `&packed.field` rejection.
- Record: report + ledger.

**Interfaces:**
- Consumes: Task-1 parser census.
- Produces: `packed struct` parses and type-checks as a `struct_type` flagged packed; L0/L1/L2 now pass the FRONTEND (no more `expected ';'` parse error) but still mis-lower/emit (RED persists at run-gate until Task 5).

- [ ] **Step 1: `kw_packed`.** Add `kw_packed` to the keyword table (pattern of existing `kw_struct`); verify the fixtures' `const X = packed struct {…}` now tokenizes with a `packed` keyword at the expected column.

- [ ] **Step 2: Expression-primary threading.** In `parserParsePrimary`, add a `kw_packed` case that parses a following struct type with `is_packed=true`, threading the bit into `parserParseStructType` and onto the struct-decl AST node flags (bit4 `0x10`). Grammar-completeness: also accept the statement/pub-decl container forms if the codebase's struct-decl path is shared — follow the Task-1 map; the fixture path (var-decl init) is the gate.

- [ ] **Step 3: Sema B6 gate.** In semantic analysis of a packed struct's fields, enforce the allowed set (`bool`, `uN`/`iN` via `intIsSigned`/`intWidthBits`; reject float/pointer/array/slice/optional/error-union/non-packed-struct/packed-union/enum(uN)) with a clean `error[3000]`; reject `&packed.field` (address-of a packed field) with a clean diagnostic. No ICE.

- [ ] **Step 4: Byte-neutrality gate.** Rebuild the reference compiler (record md5). Re-run 4-MD5 (must be byte-identical), golden 9/9, and self-compile hop1==hop2 (fixed point must NOT move yet — parser/sema additions are reachable only via `packed`). Verify the fixtures now classify as a frontend-accepted-but-not-GREEN state (record the actual class; do NOT force).

- [ ] **Step 5: Commit.**

```bash
git add sf/src/<per-census>            # ONLY the front-end files actually changed
git commit -m "feat: packed struct — kw_packed parse + is_packed flag + B6 field gate (PACK-CORE)"
```

- [ ] **Step 6: Report.** Diff summary, byte-neutrality evidence, fixture front-end state, concerns. Ledger line.

---

### Task 3: Type layer — packed bit-layout side table + introspection (byte-neutral)

**Files:**
- Modify (per Task-1 census): type_registry.zig / type_resolver.zig (packed flag on `struct_type` `Type` + bit-layout side table resolution), comptime_eval.zig and/or the F-INTRO introspect folds (`@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf`/`@bitOffsetOf` on packed).
- Record: report + ledger.

**Interfaces:**
- Consumes: Task-1 type census + INTWIDTH width helpers.
- Produces: resolved per-field bit layout (`bit_offset`, `bit_width`; LSB-first, `bool`=1, widths via `intWidthBits`) for packed structs, and correct introspect folds. Still byte-neutral (nothing consumes packed emission yet).

- [ ] **Step 1: Packed flag on Type.** When a `struct_type` resolves from an AST node carrying the packed bit, set the packed flag on the resolved `Type` (flags bit, per Task-1 census of free bits). Verify via a scratch probe (report only) that `@bitSizeOf`/`@sizeOf` on a packed type reach the fold with the flag visible.

- [ ] **Step 2: Bit-layout side table.** After all field types of a packed struct are resolved (state-2), compute the side-table entry: running LSB-first bit offset, per field `bit_offset`+`bit_width` (`bool`→1; ints → `intWidthBits`), total bits. Store keyed by type id (registry side table/arena). Non-packed structs unchanged. Cross-check against the L1 byte math (`x@0 u1, y@1 u3, z@4 u4` → 8 bits) and L2 (`a@0 u5, b@5 u8` → 13 bits → 2 bytes).

- [ ] **Step 3: Introspection.** `@sizeOf(packed)` = `ceil(total_bits/8)`; `@alignOf(packed)` = 1; `@bitSizeOf(packed)` = total bits; `@offsetOf`/`@bitOffsetOf` read the side table (byte/bit). These must fold at comptime like today's introspect. Record contracts on scratch probes (`@sizeOf` on the three fixture types → 1/1/2).

- [ ] **Step 4: Byte-neutrality gate.** Rebuild; 4-MD5 byte-identical; golden 9/9; self-compile fixed point unchanged. Fixtures: frontend-accepted state unchanged (still not GREEN).

- [ ] **Step 5: Commit.**

```bash
git add sf/src/<per-census>
git commit -m "feat: packed struct — bit-layout side table + introspect (PACK-CORE)"
```

- [ ] **Step 6: Report.** Side-table design, probe evidence, byte-neutrality, concerns. Ledger line.

---

### Task 4: LIR `load_bitfield`/`store_bitfield` + DCE/switch arms (byte-neutral)

**Files:**
- Modify (per Task-1 census): lir.zig (new variants), lir_stream raw-byte serialization (layout-only), c89_emit inst-switch + all 4+ DCE liveness fns and any pre-pass arms (present, minimal), lower.zig (emit the new ops for packed field accesses).
- Record: report + ledger.

**Interfaces:**
- Consumes: Task-1 LIR/DCE census; Task-3 side table.
- Produces: packed field reads/writes lower to `load_bitfield`/`store_bitfield` with every inst-switch site armed (no missed arm → no silent drop / 0xFFFFFFFF result), whole packed-value stores kept live by the store-drop rule generalization. Emission bodies land in Task 5; until then the ops are never produced for non-packed code → byte-neutral.

- [ ] **Step 1: LIR variants.** Add `load_bitfield { base, src?, bit_offset, bit_width }` and `store_bitfield { base, bit_offset, bit_width, value }` following the existing LirInst convention (fields + serialization). Add the raw-byte layout entries to `lir_stream`.

- [ ] **Step 2: Arm the switch sites.** For EVERY inst-switch site from the Task-1 arm list, add `load_bitfield`/`store_bitfield` arms. In the DCE liveness fns the arms must mark the base/value read appropriately so a bitfield read is never DCE-dropped; in the emitter inst walk add the arms (bodies can be `else`-style no-ops until Task 5, but they must EXIST so nothing falls into a catch-all). Also generalize the store-drop rule: a base whose type is a packed `struct_type` is treated like the array case (whole-value store kept live).

- [ ] **Step 3: Lowering.** In `lower.zig`, packed field access (load/store of a member of a `var`/lvalue whose type is packed `struct_type`) emits `load_bitfield`/`store_bitfield` with the side-table `bit_offset`/`bit_width`. Whole-value packed ops (assignment, by-value, memcpy needs) keep the existing paths. `&packed.field` is already rejected in sema (Task 2).

- [ ] **Step 4: Byte-neutrality gate.** Rebuild; 4-MD5 byte-identical; golden 9/9; self-compile fixed point unchanged; corpus zero-asymmetric on the common set. Fixtures: record the current class (frontend-accepted; expected still not GREEN until Task 5).

- [ ] **Step 5: Commit.**

```bash
git add sf/src/<per-census>
git commit -m "feat: packed struct — LIR load_bitfield/store_bitfield + DCE arms (PACK-CORE)"
```

- [ ] **Step 6: Report.** Arm-list completeness proof (grep: every switch on LirInst handles the 2 new variants), DCE evidence, concerns. Ledger line.

---

### Task 5: C89 emitter — carrier + bitfield accessors + memcpy → L0/L1/L2 GREEN

**Files:**
- Modify (per Task-1 census): c89_emit.zig (packed type emission as the single-member struct carrier per spec AMENDMENT 1, `load_bitfield`/`store_bitfield` bodies, whole-value native struct ops, `*Packed` carrier pointer, local packed var carrier).
- Record: report + ledger.

**Interfaces:**
- Consumes: Task-3 side table + Task-4 armed ops.
- Produces: L0/L1/L2 GREEN with byte-exact contracts; fixed point moves (emitter-layer commit) → Task 6 re-baseline.

- [ ] **Step 1: Type emission.** A packed `struct_type` emits as the single-member struct carrier `typedef struct { unsigned char _[N]; } zT_NAME;` (N = `@sizeOf`) wherever a struct type name/definition would be emitted (spec AMENDMENT 1) — never C bitfields, never multi-field natural layout. Verify the three fixture types produce 1/1/2-byte carriers in the emitted C.

- [ ] **Step 2: Local + whole-value.** A packed-typed local/value is a carrier-struct local; whole-value `=`/by-value param/return/array-element store are native C struct-by-value ops (no memcpy wrapper needed — C89 supports struct-by-value, arrays do not). `*Packed` is emitted as a pointer to the carrier struct, so the fixtures' `@ptrCast([*]const u8, &f)` byte-dump works (first-member address == carrier start).

- [ ] **Step 3: `store_bitfield` body.** Emit the read-modify-write: locate byte(s) `bo/8..(bo+w-1)/8`; clear the bit window `[bo%8, bo%8+w)`; OR the value masked to `w` bits (unsigned; for signed field values store the two's-complement bit pattern of the sign-extended value) shifted into the window. Match L1 (single byte) and L2 (byte-spanning) shapes.

- [ ] **Step 4: `load_bitfield` body.** Emit little-endian gather across the spanned byte(s) (shift/OR per byte honoring the byte stride when the field crosses a byte boundary), mask to `w` bits; for signed fields sign-extend from bit `w-1` (`intIsSigned`). Verify L2 `b` spans bytes 0-1.

- [ ] **Step 5: GREEN gate.** Build, then run the three fixtures via the authoritative run recipe: byte-exact `1 5 1` / `1 155 1 5 9` / `2 255 31 31 255`, RUNRC=0, deterministic 3× (fresh dirs). Emitted-C spot-check: L0 byte `5` from bit stores; L1 byte `155`; L2 bytes `255 31`.

- [ ] **Step 6: Regression.** 4-MD5 byte-identical (packed emission is reachable only via `packed`); golden 9/9; matrix 21/21; corpus 428-style sweep zero-asymmetric on the common set except the 3 packed dirs (RED→GREEN); EXPECTED_FAIL version-bump + GREEN rows are the Task-7 docs GATE (post-approval).

- [ ] **Step 7: Commit.**

```bash
git add sf/src/<per-census>
git commit -m "feat: packed struct — C89 single-member-struct carrier + bitfield accessors (PACK-CORE)"
```

- [ ] **Step 8: Report.** GREEN evidence (3 fixtures ×3, md5s, emitted-C shapes), byte-neutrality on the common set, fixed-point-moved disclosure, concerns. Ledger line.

---

### Task 6: Full battery + fixed-point re-baseline STOP-present

**Files:**
- Record only.

- [ ] **Step 1: Battery.** golden 9/9 rc0 byte-identical; matrix 21/21; full corpus sweep (common set zero-asymmetric except the 3 packed dirs); 4-MD5 byte-identical (gol/lisp/json/mud unchanged); live mud/rogue net unaffected (no net change).

- [ ] **Step 2: Self-compile round-trip.** hop1==hop2; record the NEW fixed point md5 (seed v0-era `24da89b9…`, moved by the emitter-layer commit) + 42-ish `.c`, 0 `error[`, 0 PANIC.

- [ ] **Step 3: STOP-present.** Re-baseline proposal (self-compile fixed point re-baseline; NO 4-MD5 gate re-baseline since gates are byte-identical); L0/L1/L2 GREEN rows need the EXPECTED_FAIL/QUICK_REF docs update in Task 7 AFTER operator approval; seed rotation to the new fixed point also happens in Task 7 (never here). No commit, no docs touched.

---

### Task 7: Docs GATE (after operator approval)

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (header bump from the then-current version + RESOLVED rows for `packed_l0_flags_xmod`/`packed_l1_mix_xmod`/`packed_l2_straddle_xmod` with the fixing commits + GREEN contracts; RED history preserved verbatim), `docs/sf/QUICK_REF.md` (newest-first baseline bullet).
- Record: report + ledger.

- [ ] **Step 1: EXPECTED_FAIL.** Header version bump; three RESOLVED markers (per-file fix commits from Tasks 2-5) with contracts `1 5 1`/`1 155 1 5 9`/`2 255 31 31 255`; historical RED text verbatim below; no other section touched.

- [ ] **Step 2: QUICK_REF.** Newest-first bullet above the current-newest, dense dated style: PACK-CORE landed (parse/type/LIR/emitter), L0/L1/L2 GREEN + contracts, 4-MD5 unchanged, fixed point re-baselined to the Task-6 value, corpus/golden/matrix state, EXPECTED_FAIL version.

- [ ] **Step 3: Commit.**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
# Seed rotation (SEEDMIG model): rotate the committed seed to the Task-6 fixed-point binary
bash scripts/seed/archive_seed.sh <Task-6-fixed-point-binary> <Task-6-fresh-gen-dir> release/seed/zig1-seed.tgz --update-changelog
git add release/seed/zig1-seed.tgz release/seed/CHANGELOG.md
git commit -m "docs: GATE — packed struct core L0-L2 GREEN + fixed-point re-baseline + seed rotation (PACK-CORE)"
```

- [ ] **Step 4: Report + STOP-present plan close** (PACK-AGG/PACK-B3 remain; operator-authority to continue).

---

## Plan Self-Review

1. **Spec coverage:** parse (T2), type/layout side table + introspect (T3), LIR + DCE arms (T4), emitter carrier/accessors/memcpy (T5) → L0/L1/L2 GREEN; byte-neutral gates on every F task (T2-T4), fixed-point re-baseline STOP (T6), docs GATE (T7); success criteria 1-4 → T5/T6; out-of-scope (union/nested/array/global/enum uN/token.zig FIXME) untouched.
2. **Placeholder scan:** no TBD; census-dependent line anchors are resolved by the record-only Task-1 edit-map (execution follows it, matching the established INTWIDTH pattern); contracts are the committed fixture values.
3. **Type/name consistency:** flags bit4 `0x10` `is_packed`; LIR ops `load_bitfield`/`store_bitfield`; fixture paths + contracts byte-exact; report file `task-PACKCORE-report.md`; memory agent `packcore-session`.
