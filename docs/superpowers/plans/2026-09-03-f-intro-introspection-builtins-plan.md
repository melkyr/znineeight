# F-INTRO Implementation Plan — `@offsetOf` / `@bitSizeOf` / `@bitOffsetOf` comptime introspection builtins

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make zig1 recognize and comptime-fold `@offsetOf(T, "field")`, `@bitSizeOf(T)`, and `@bitOffsetOf(T, "field")` so the three committed R1 RED fixtures (`builtin_offsetof_xmod`, `builtin_bitsizeof_xmod`, `builtin_bitoffsetof_xmod`) go GREEN with byte-exact stdout.

**Architecture:** pure front-end additions — no LIR, no Type-layer, no emitter, no parser change. Each builtin is added as (1) an interned name id + (2) a comptime-eval fold branch that returns a `ComptimeVal` constant (mirroring the existing `@sizeOf`/`@alignOf` branches), (3) a semantic-analysis branch returning `TYPE_INT_LIT`, and (4) an extension of lower.zig's `iceUnresolvedComptime` guard so an un-foldable instance fails loudly instead of silently mis-emitting through the generic builtin tail.

**Tech Stack:** Z98 dialect in `sf/src/*.zig` (self-hosted compiler source); verified against the zig0-built reference compiler; battery via the established corpus/gate scripts.

## Global Constraints

- This plan is **F-INTRO** = item 1 of the operator-approved follow-on execution order in `docs/superpowers/plans/2026-09-03-language-wins-r-i-plan.md` (AMENDMENT, G1 rulings). Only the three builtins above; **no other F work, no other compiler changes.**
- Z98 dialect discipline: `@intCast` on every narrowing/widening; no `anytype`/`@Type`; `switch` must have `else`; no method syntax; no pointer captures. Follow the surrounding file style exactly.
- Source edits via `fastedit` ONLY per `docs/sf/AGENTS.md` X.7 (re-read the region immediately before each edit; absolute line numbers; edit bottom-to-top; an INSERT = replace the anchor line keeping the original at the end of `new_code` since `end_line = start_line - 1` errors). No python/sed/bulk transforms. No `git checkout` to erase.
- Files that MAY change in this plan (compiler source): `sf/src/comptime_eval.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`. No other `sf/src` file. Never touch `sf/build/out_release/`.
- Reference rebuild: `timeout 900 bash sf/scripts/build_release.sh` → output `/tmp/fx_subfolder/zig1` (this plan's edits move its md5 from `1a5056b2…` — expected, NOT a re-baseline event by itself; see Task 2).
- The 4-MD5 gate programs (gol/lisp/json/mud) use none of the new builtins ⇒ their dump md5 MUST stay byte-identical: gol `302df36b…`, lisp `3591bad9…`, json `76056b97…`, mud `53405b3b…`. Any move is a bug → STOP-present.
- GREEN contract (byte-exact stdout, run-gate `RUNRC=0`): `builtin_offsetof_xmod` → `0 4 8`; `builtin_bitsizeof_xmod` → `1 8 32`; `builtin_bitoffsetof_xmod` → `0 32 64`.
- Only `struct_type` field lookup is implemented (fixtures are plain structs). A non-struct type arg or missing field → fold returns null → lower's extended `iceUnresolvedComptime` fires (loud ICE), never silent mis-emission. Clean diagnostics for unsupported usage are F-CLEANDIAG scope (later plan), NOT this plan.
- Self-compile round-trip fixed point WILL move (compiler source grows) ⇒ NEW fixed-point md5 recorded, re-baseline is operator-ruled in Task 2's STOP-present, never silent.
- Full battery on any F commit: golden 9/9, matrix 21/21, corpus sweep (424 dirs `-s0`), self-compile round-trip. Expected corpus delta: the 3 R1 builtin dirs flip GCCFAIL→OK/run-GREEN; all other 421 dirs unchanged (0 asymmetric vs the pre-edit reference).
- Authoritative per-fixture classifier = Step-4 recipe in `.superpowers/sdd/task-LANGWINS-report.md` (`classify1.sh` compile-gate + `fixture_run.sh` run-gate; fresh output dir `rm -rf`+`mkdir -p` REQUIRED, else dump ICEs rc=3 spill-open). Pre-existing dirty/untracked repo files are NEVER staged or committed.
- Commit messages follow repo style (lowercase `feat:`/`fix:`/`docs:`/`test:` prefix + concise body).
- Operator standing rules: only plan-authorized actions; STOP-and-present on any issue or any plan-vs-evidence divergence; store memories as we go (mnemoria agent `fintro-session`); NO context compression during this build session.

---

## Background (verified anchors — read before editing)

Current green path for `@sizeOf`/`@alignOf` (the template to mirror):

1. Lexer: every `@name` = ONE generic token `builtin_identifier` (token.zig:11; lexer.zig:159-168/:487). Name = interner string id in the token payload.
2. Parser: `parserParseBuiltinCall` (parser.zig:691-739) is fully generic — type-leading args (`* [ ? ! fn struct enum union error anytype`) parse via `parserParseType`, everything else (incl. an ident like `Mixed` and a `"c"` string literal) parses as an expression into the same `child_buf` → `AstKind.builtin_call` node with `child_0` = builtin name id, extra-children slice `ec` = the arg node indices (`astStoreNodeExtraChildren`). Unknown names parse fine by construction.
3. Comptime fold: `phase_ComptimeEvaluation` (main.zig:475-503, runs AFTER type resolution at main.zig:277/287) sweeps every `builtin_call` node; `comptimeEvalEvaluate` (comptime_eval.zig:166-168) → `comptimeEvalBuiltin` (:113-164); a non-null result's `.bits` is stored in the ctx `comptime_values` map keyed by node_idx (main.zig:485-488).
4. Semantic resolution: builtin dispatch by name id at `semantic_analyzer.zig:1499-1599`; `@sizeOf`/`@alignOf` (:1501-1506) resolve the type arg then return `TYPE_INT_LIT` (so the node is not typed as a struct value). Name ids: struct fields semantic_analyzer.zig:62-63, interned :107-110, assigned :192-193.
5. Lowering: builtin_call (:3238+); FIRST checks the fold map (:3250 `u32ToU64MapGet`), on hit emits `int_const` (:3271-3274, result `TYPE_USIZE` default); `@sizeOf`/`@alignOf` NOT in the map hit the ICE guard `iceUnresolvedComptime` (lower.zig:3277-3280, msg :923; def :920). Name ids: struct fields lower.zig:378-379, interned :448-451, assigned :523-524.
6. String-literal payload (for the `"field"` arg): `astStoreAddStringLiteral` (ast.zig:876-880) stores the interned string id in `store.string_values[]`; the node payload = the index into `string_values` (read via `ast_mod.astStoreNodePayload(store, node_idx)`, ast.zig:822). Precedent read in lower.zig:1671.
7. Field lookup: struct byte offsets live in `FieldEntry{name_id,type_id,offset}` (type_registry.zig:86), populated by `typeResolverResolveLayout` struct branch (type_resolver.zig:139-156, `fe.offset` :147). Slice accessors `typeRegistryGetStructFields` (type_registry.zig:806) / `typeRegistryGetUnionFields` (:814). Match the string arg's interned id against `FieldEntry.name_id`.
8. Type bit size: NO per-type bit-size exists. `Type.size` = C-emission BYTES (type_registry.zig:65); bool registered size 4 (:608) but `@bitSizeOf(bool)` must fold to **1** ⇒ special-case `bool_type`; every other state-2 type → `size*8`. (comptime_eval.zig:140 already uses `ty.size * @intCast(u32, 8)`.)
9. `TypeKind` enum names (type_registry.zig:41-58): `bool_type`, `u8_type`, … `struct_type`, `union_type`. `ty.state == 2` = layout-resolved (primitives register state 2 at :272-285; structs state→2 at type_resolver.zig:312).

---

### Task 1: Implement the three comptime introspection builtins

**Files:**
- Modify: `sf/src/comptime_eval.zig` (ComptimeEval struct :25-28, `comptimeEvalInit` :31-45, `comptimeEvalBuiltin` :113-164)
- Modify: `sf/src/semantic_analyzer.zig` (struct :62-63, init :107-110 + :192-193, dispatch :1501-1506)
- Modify: `sf/src/lower.zig` (struct :378-379, init :448-451 + :523-524, ICE guard :3277-3280)

**Interfaces:**
- Consumes: existing `@sizeOf`/`@alignOf` fold path, `typeRegistryGetStructFields`, `astStoreNodePayload`/`string_values`, `FieldEntry.offset`, the R1 fixtures under `repro/mi_matrix/{builtin_offsetof,builtin_bitsizeof,builtin_bitoffsetof}_xmod/main.zig`.
- Produces: `@offsetOf`/`@bitSizeOf`/`@bitOffsetOf` recognized + folded to constants; R1 fixtures GREEN; 4-MD5 gates byte-identical.

- [ ] **Step 1: Verify RED on the pre-edit reference**

Run against the current reference (repo-root CWD):
```bash
bash /tmp/sd_work/classify1.sh /tmp/fx_subfolder/zig1 /tmp/fintro_red builtin_offsetof_xmod repro/mi_matrix/builtin_offsetof_xmod/main.zig
bash /tmp/sd_work/classify1.sh /tmp/fx_subfolder/zig1 /tmp/fintro_red builtin_bitsizeof_xmod repro/mi_matrix/builtin_bitsizeof_xmod/main.zig
bash /tmp/sd_work/classify1.sh /tmp/fx_subfolder/zig1 /tmp/fintro_red builtin_bitoffsetof_xmod repro/mi_matrix/builtin_bitoffsetof_xmod/main.zig
```
Expected: each prints `... GCCFAIL` (R1-documented silent dump → invalid C). If any prints OK/GREEN/FAIL-wrong, STOP-present (fixture drift).

- [ ] **Step 2: Edit `sf/src/comptime_eval.zig`**

(2a) Add three name-id fields to the `ComptimeEval` struct after `.align_of_id: u32,` (:26):
```
    offset_of_id: u32,
    bit_size_of_id: u32,
    bit_offset_of_id: u32,
```

(2b) Intern the three names in `comptimeEvalInit` after the `@alignOf` intern (:37), and add the fields to the returned struct literal after `.align_of_id = align_id,` (:42). Insert:
```
    var s_off: []const u8 = "@offsetOf";
    var s_bitsz: []const u8 = "@bitSizeOf";
    var s_bitoff: []const u8 = "@bitOffsetOf";
    var off_id = interner_mod.stringInternerIntern(interner, s_off);
    var bitsz_id = interner_mod.stringInternerIntern(interner, s_bitsz);
    var bitoff_id = interner_mod.stringInternerIntern(interner, s_bitoff);
```
and in the literal:
```
        .offset_of_id = off_id, .bit_size_of_id = bitsz_id, .bit_offset_of_id = bitoff_id,
```

(2c) Add three fold branches in `comptimeEvalBuiltin` immediately after the `@alignOf` branch's closing `return null;` (:132) and BEFORE the `if (node.child_0 == self.int_cast_id) {` (:133):
```
    if (node.child_0 == self.offset_of_id or node.child_0 == self.bit_offset_of_id) {
        var ec2: []const u32 = ast_mod.astStoreNodeExtraChildren(self.store, node_idx);
        if (ec2.len >= @intCast(usize, 2)) {
            var tid = comptimeEvalResolveTypeArg(self, ec2[@intCast(usize, 0)]);
            if (tid) |t| {
                var ty = self.registry.types_items[@intCast(usize, t)];
                if (ty.state == @intCast(u8, 2) and ty.kind == type_mod.TypeKind.struct_type) {
                    var fields: []type_mod.FieldEntry = undefined;
                    type_mod.typeRegistryGetStructFields(self.registry, t, &fields);
                    var fname_node = ast_mod.astStoreNodeAt(self.store, ec2[@intCast(usize, 1)]);
                    if (fname_node.kind == AstKind.string_literal) {
                        var sv_idx = ast_mod.astStoreNodePayload(self.store, ec2[@intCast(usize, 1)]);
                        var want_id = self.store.string_values.items[@intCast(usize, sv_idx)];
                        var fi: usize = 0;
                        while (fi < fields.len) : (fi += 1) {
                            if (fields[fi].name_id == want_id) {
                                var bo: u64 = @intCast(u64, fields[fi].offset);
                                if (node.child_0 == self.bit_offset_of_id) {
                                    bo = bo * @intCast(u64, 8);
                                }
                                return ComptimeVal{ .bits = bo, .width_bits = @intCast(u32, 0), .sig = false };
                            }
                        }
                    }
                }
            }
        }
        return null;
    }
    if (node.child_0 == self.bit_size_of_id) {
        var ec3: []const u32 = ast_mod.astStoreNodeExtraChildren(self.store, node_idx);
        if (ec3.len >= @intCast(usize, 1)) {
            var tid2 = comptimeEvalResolveTypeArg(self, ec3[@intCast(usize, 0)]);
            if (tid2) |t2| {
                var ty2 = self.registry.types_items[@intCast(usize, t2)];
                if (ty2.state == @intCast(u8, 2)) {
                    var bsz: u64 = @intCast(u64, ty2.size) * @intCast(u64, 8);
                    if (ty2.kind == type_mod.TypeKind.bool_type) {
                        bsz = @intCast(u64, 1);
                    }
                    return ComptimeVal{ .bits = bsz, .width_bits = @intCast(u32, 0), .sig = false };
                }
            }
        }
        return null;
    }
```
Note: `ec` is already declared by the existing `@alignOf` branch scope; use distinct names (`ec2`, `ec3`) to avoid a redeclaration clash inside `comptimeEvalBuiltin`. If `AstKind` / `type_mod` / `ast_mod` are already imported (they are — see :3/:8/:9), no import edits are needed.

- [ ] **Step 3: Edit `sf/src/semantic_analyzer.zig`**

(3a) Add three name-id fields after `.align_of_name_id: u32,` (:63):
```
    offset_of_name_id: u32,
    bit_size_of_name_id: u32,
    bit_offset_of_name_id: u32,
```

(3b) Intern after the `@alignOf` intern (`ao_id`, :109-110) and assign after `.align_of_name_id = ao_id,` (:193):
```
    var oo_s: []const u8 = "@offsetOf";
    var oo_id = interner_mod.stringInternerIntern(interner, oo_s);
    var bso_s: []const u8 = "@bitSizeOf";
    var bso_id = interner_mod.stringInternerIntern(interner, bso_s);
    var boo_s: []const u8 = "@bitOffsetOf";
    var boo_id = interner_mod.stringInternerIntern(interner, boo_s);
```
```
        .offset_of_name_id = oo_id,
        .bit_size_of_name_id = bso_id,
        .bit_offset_of_name_id = boo_id,
```

(3c) Extend the size/align dispatch branch condition (:1501) to also match the three new ids:
```zig
        if (node.child_0 == self.size_of_name_id or node.child_0 == self.align_of_name_id or node.child_0 == self.offset_of_name_id or node.child_0 == self.bit_size_of_name_id or node.child_0 == self.bit_offset_of_name_id) {
```
Body unchanged (resolve type arg ec[0] when `ec.len >= 1`, result `TYPE_INT_LIT`). The `"field"` string arg needs no semantic resolution.

- [ ] **Step 4: Edit `sf/src/lower.zig`**

(4a) Add three name-id fields after `.align_of_name_id: u32,` (:379):
```
    offset_of_name_id: u32,
    bit_size_of_name_id: u32,
    bit_offset_of_name_id: u32,
```

(4b) Intern after the `@alignOf` intern (`alignof_id`, :450-451) and assign after `.align_of_name_id = alignof_id,` (:524):
```
    var offsetof_s: []const u8 = "@offsetOf";
    var offsetof_id = si_mod.stringInternerIntern(ctx.registry.interner, offsetof_s);
    var bitsizeof_s: []const u8 = "@bitSizeOf";
    var bitsizeof_id = si_mod.stringInternerIntern(ctx.registry.interner, bitsizeof_s);
    var bitoffsetof_s: []const u8 = "@bitOffsetOf";
    var bitoffsetof_id = si_mod.stringInternerIntern(ctx.registry.interner, bitoffsetof_s);
```
```
         .offset_of_name_id = offsetof_id,
         .bit_size_of_name_id = bitsizeof_id,
         .bit_offset_of_name_id = bitoffsetof_id,
```

(4c) Extend the ICE-guard condition (:3277):
```zig
            if (node.child_0 == self.size_of_name_id or node.child_0 == self.align_of_name_id or node.child_0 == self.offset_of_name_id or node.child_0 == self.bit_size_of_name_id or node.child_0 == self.bit_offset_of_name_id) {
```
Body unchanged (fire `iceUnresolvedComptime` for an un-folded instance so it never reaches the generic tail at :3482-3554). Optionally generalize the guard's message text at lower.zig:923 from `@sizeOf/@alignOf` to `@sizeOf/@alignOf/@offsetOf/@bitSizeOf/@bitOffsetOf` (ICE-path string only; does not affect any gate emission).

- [ ] **Step 5: Rebuild the reference compiler**

```bash
timeout 900 bash sf/scripts/build_release.sh
```
Expected: prints the release-Done line, produces `/tmp/fx_subfolder/zig1` with a NEW md5 (≠ `1a5056b2…`). Record the md5. (This is the normal F-plan reference rebuild; not a gate re-baseline.)

- [ ] **Step 6: Verify the three fixtures flip RED→GREEN**

```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/builtin_offsetof_xmod/main.zig /tmp/fintro_g_oo
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/builtin_bitsizeof_xmod/main.zig /tmp/fintro_g_bs
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/builtin_bitoffsetof_xmod/main.zig /tmp/fintro_g_bo
```
Expected (each): `RUNRC=0`; stdout byte-exact `0 4 8` / `1 8 32` / `0 32 64`; gcc clean (empty `gcc.err`). Confirm the emitted `main_*.c` contains the constants (e.g. `zT_.. = 0;` … `= 4;` … `= 8;` and the bitOffset variant `= 0/32/64`, bitSize `= 1/8/32`) — proof the builtins fold at comptime rather than emitting helper calls. If any fixture is not GREEN with the exact contract, STOP-present.

- [ ] **Step 7: 4-MD5 gates byte-identical (repo-root CWD)**

```bash
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum; done
```
Expected: gol `302df36b…` / lisp `3591bad9…` / json `76056b97…` / mud `53405b3b…` — all FOUR byte-identical to the pre-change baselines. ANY move = a bug → STOP-present (do not re-baseline).

- [ ] **Step 8: Self-compile round-trip (fixed point check)**

```bash
bash scripts/self_compile/build_next_gen.sh /tmp/fx_subfolder/zig1 /tmp/fintro_self
```
Expected: dump rc=0, 42 `.c`, 0 `error[`, 0 PANIC, hop binaries md5-identical to each other AND to the new reference (fixed point closed). Record the NEW fixed-point md5. If the fixed point does NOT close (hop1 ≠ reference, or hop2 ≠ hop1), STOP-present.

- [ ] **Step 9: Commit + report**

```bash
git add sf/src/comptime_eval.zig sf/src/semantic_analyzer.zig sf/src/lower.zig
git commit -m "feat: comptime introspection builtins @offsetOf/@bitSizeOf/@bitOffsetOf (F-INTRO)"
```
Stage ONLY the three source files. Pre-existing dirty/untracked files stay unstaged. Append the full report to `.superpowers/sdd/task-F-INTRO-report.md` (`## F-INTRO-1`): RED proof, exact edits (per-file hunk list), fixture GREEN evidence (stdout bytes + emitted-constant snippet), 4-MD5 table, new reference md5, fixed-point md5, commit sha, git-status-at-end. Ledger line in `.superpowers/sdd/progress.md`.

Report back: `DONE` + commit sha + one-line battery summary + any concern.

---

### Task 2: Full battery + corpus reconciliation + STOP-present re-baseline proposal

**Files:**
- Create report: `.superpowers/sdd/task-F-INTRO-report.md` (`## F-INTRO-2` appended; gitignored scratch)

**Interfaces:**
- Consumes: the Task-1 compiler `/tmp/fx_subfolder/zig1` (new md5), the three GREEN fixtures, `.superpowers/sdd/task-LANGWINS-report.md` G1 corpus numbers.
- Produces: full-battery evidence, corpus reconciliation table, STOP-present with a re-baseline proposal for the NEW self-compile fixed-point md5 (operator-ruled). NO commits in this task (no source change since Task 1; no docs change without operator approval).

- [ ] **Step 1: Golden 9/9**

Run the 9 golden fixtures (emission_assoc_chain_xmod, fn_ptr_struct_field, emission_lower_crash_xmod, tco_return_try, tco_defer, tco_factorial, quicksort, func_ptr_return, hello) emit→gcc→link→run with the new compiler; stdout byte-identical to the pre-change reference golden. Record each rc + stdout state.

- [ ] **Step 2: Matrix 21/21**

Run the 21 `examples/z98` programs emit→gcc→link→run with the new compiler; all dump rc=0/gcc rc=0/link rc=0; mud_server + rogue_mud timeout-gated rc=124 with correct output = PASS; runtime stdout byte-equal vs the pre-change reference.

- [ ] **Step 3: Corpus sweep (424 dirs, `-s0`) + asymmetric reconciliation**

Generate the 424-dir program list (351 mi_matrix + 53 top-level repro + 20 examples/z98 — R-phase enumeration in task-LANGWINS-report.md G1). Sweep BOTH the pre-edit reference (save first, e.g. reuse a freshly made `/tmp/fintro_sweep_ref/results.txt`) AND the new compiler with the same list + `sweep.sh` classifier. Expected: exactly the 3 builtin dirs change (GCCFAIL → OK; compile gate OK, and at run-gate they print the GREEN contracts) → pre-edit `OK=397/FAIL=15/GCCFAIL=5/GREEN=6/ICE=1/CRASH=0` becomes `OK=400/FAIL=15/GCCFAIL=2/GREEN=6/ICE=1/CRASH=0`; per-dir asymmetric vs pre-edit = exactly those 3 dirs and nothing else; **0 NEW** FAIL/ICE/CRASH/gcc-error anywhere. Any other delta → STOP-present.

- [ ] **Step 4: Self-compile confirmation + fixed-point record**

Re-run the Task-1 round-trip result summary; record the NEW fixed-point md5 and confirm hop1==hop2==reference. State plainly that this fixed point MOVED from the previous plan value because compiler source grew (expected per regression discipline).

- [ ] **Step 5: STOP-present re-baseline proposal**

Append `## F-INTRO-2` to `.superpowers/sdd/task-F-INTRO-report.md` with the full evidence (golden/matrix/corpus tables + per-dir asymmetric diff list + new reference md5 + new fixed-point md5). STOP-present to the operator:
- proposal: re-baseline the self-compile fixed-point md5 `(previous) → (new)` (operator-ruled; 4-MD5 gates unchanged at gol/lisp/json/mud so NO gate re-baseline);
- note: the 3 R1 fixtures are GREEN and their EXPECTED_FAIL.md rows (v63) need a RESOLVED docs update in a follow-up docs commit AFTER operator approval (not this task);
- any concern discovered during the battery.

Report back: `DONE` (evidence) + one-line battery summary + concerns. NO commit.

---

### Task 3: Docs GATE — EXPECTED_FAIL.md resolution + QUICK_REF baseline (operator-approved)

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`
- Modify: `docs/sf/QUICK_REF.md`

**Interfaces:**
- Consumes: operator approval of the Task-2 re-baseline proposal; the Task-2 evidence.
- Produces: committed docs reconciliation. THIS TASK RUNS ONLY AFTER THE OPERATOR APPROVES.

- [ ] **Step 1: EXPECTED_FAIL.md — mark the three R1 rows RESOLVED**

Header version bump (v63 → v64, following file convention). For each of the three Langwins sections carrying `builtin_offsetof_xmod` / `builtin_bitsizeof_xmod` / `builtin_bitoffsetof_xmod`: mark the row/bullet RESOLVED with the F-INTRO fixing commit sha + the GREEN contract (`0 4 8` / `1 8 32` / `0 32 64`, run-gate verified). Preserve the historical RED root-cause text beneath (prior convention). Do not touch other sections.

- [ ] **Step 2: QUICK_REF.md — new newest-first baseline bullet**

Insert a dense dated bullet ABOVE the current newest (`Post-SWEXPR + store-drop baseline`) recording: F-INTRO commit sha, three introspection builtins folded at comptime (struct-only `@offsetOf`/`@bitOffsetOf`, bool→1 `@bitSizeOf`), R1 fixtures GREEN (`0 4 8`/`1 8 32`/`0 32 64`), 4-MD5 gates byte-identical (unchanged hashes), golden 9/9, matrix 21/21, corpus OK=400/FAIL=15/GCCFAIL=2/GREEN=6/ICE=1/CRASH=0 (3-dir delta only, 0 asymmetric elsewhere), NEW reference md5 + NEW self-compile fixed-point md5 (operator-ruled re-baseline).

- [ ] **Step 3: Commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs: GATE — introspection builtins GREEN + fixed-point re-baseline (F-INTRO)"
```
Only the two doc files staged. Pre-existing dirty/untracked stay unstaged. Report back: `DONE` + commit sha.

---

## Plan Self-Review (performed at authoring time)

1. **Spec coverage:** A8 `@offsetOf`/`@bitSizeOf`/`@bitOffsetOf` (design spec semantics §1, I1 verdicts IMPLEMENT-NOW) → Task 1 implements exactly these three; Task 2 = regression discipline (design §"Regression discipline"); Task 3 = EXPECTED_FAIL/QUICK_REF reconciliation. Fixture GREEN contracts match the committed R1 headers exactly (`0 4 8`, `1 8 32`, `0 32 64`). No packed handling (out of scope — I8 note: non-packed exact today).
2. **Placeholder scan:** no TBD/TODO; every step carries exact file paths, edit content, and commands; the four lower/sema/comptime insertion blocks are complete code.
3. **Type/name consistency:** the three new name-id field names are consistent across all three files (`offset_of_id`/`bit_size_of_id`/`bit_offset_of_id` in comptime_eval; `offset_of_name_id`/`bit_size_of_name_id`/`bit_offset_of_name_id` in semantic_analyzer and lower), matching each file's existing naming convention (`align_of_id` vs `align_of_name_id`). Intern string literals match the fixture call sites (`@offsetOf`, `@bitSizeOf`, `@bitOffsetOf`). Fixture field names `"c"`/`"b"`/`"d"` match `FieldEntry.name_id` after interning.

## Execution Handoff

Plan complete. **Subagent-Driven (recommended per operator):** fresh implementer subagent per task + task reviewer (spec compliance + quality) after each; Task 2 and Task 3 proceed only after the prior review approves and, for Task 3, after the operator approves the Task-2 re-baseline proposal.
