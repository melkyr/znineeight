# switch-expression payload-capture emission fix — Implementation Plan (I/F)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the zig1 front-end defect found while validating idiomatic switch payload captures: a switch used as an **expression** with a **payload-capture** prong places the capture load in the dispatch fall-through (skipped by the case `goto` → uninitialized read → SIGSEGV/garbage). A permanent corpus RED fixture guards the fix so the bug can never silently return. (A second suspected quirk — stale slice-field reads in a callee — was investigated as I2-SLICESTALE and CLOSED as a false positive by operator ruling 2026-09-03.)

**Architecture:** I-SWEXPR (root-cause defect + corpus RED fixture, commit `05d104fa`, review Approved) → STOP-present → I2-SLICESTALE (investigate the suspected stale-read quirk; CLOSED as phantom by operator ruling — no fixture committed) → F-SWEXPR (fix the switch-expression capture-placement defect in `sf/src/lower.zig` only) → full battery GATE. Bug context: discovered in the zig1 self-host closure plan Task U-JSON (`const key = switch (keyVal) { .String => |s| s, else => unreachable };` → rc=139 SIGSEGV on all 4 compilers); evidence at `/tmp/ujson/probes/pA.zig` (exhaustive 2-prong, no else) + `pB.zig` (`else => unreachable`), both mis-emit; the statement-switch block form (original json.zig) emits correctly. Reported in `.superpowers/sdd/task-CLOSURE-report.md` `## U-JSON`.

**Tech Stack:** Z98 (sf/src), C89 emission, gcc -m32, bash. Compilers: reference `/tmp/fx_subfolder/zig1` (zig0-built, md5 `29327e2c`), chain `/tmp/zig1_5/{zig1_5_clean,zig1_5_self,zig1_5_self_self}` (all md5 `e2028dcf`). Current HEAD `8650b959`.

## Global Constraints

- **Determinism baselines (MUST NOT move unless a gate hash genuinely changes — then STOP + operator re-baseline ruling):** 4 MD5 gol `302df36b` / lisp `3591bad9` / json `76056b97` / mud `4591fef0` (repo-root CWD `timeout 120 <C> --dump-c89 <entry> | md5sum`); golden 9/9; matrix 21/21; corpus 0-asymmetric; self-compile 42 `.c`/0 err/0 PANIC.
- The **I task must not modify compiler source** (sf/src) — analysis + a NEW corpus fixture only. Compiler binaries stay `e2028dcf` until the F task.
- The **F task changes sf/src** → the compiler binary md5 will change (fixed point `e2028dcf` no longer holds for the rebuilt compiler). F must re-establish the chain: rebuild reference (`timeout 900 bash sf/scripts/build_release.sh` → wipe/reinstall std into `/tmp/fx_subfolder/lib`), rebuild zig1_5 (`timeout 900 bash scripts/self_compile/build_zig1_5.sh`), re-run the full battery, and record the NEW compiler md5s (a new fixed point). Emission of the 4 gate examples must stay byte-identical (expected: fix is only exercised by switch-expression+payload-capture programs); if any 4-MD5 hash moves, STOP for operator ruling (no silent re-baseline).
- **Z98 dialect** (no anytype/@Type; `@intCast`; no method syntax; no pointer captures). `edit`/`fastedit` only; re-read before edit; bottom-to-top; never touch `sf/build/out_release/`.
- Ledger `.superpowers/sdd/progress.md` (one line/task). Report `.superpowers/sdd/task-SWEXPR-report.md` (gitignored). Memory `mnemoria --path .opencode/memory add --agent swexpr-session --type <t> --summary "<s>" "<body>"`.
- Pre-existing dirty never staged: `docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `mnemoria/*`, untracked `build/`, untracked `examples/z98/json_parser_upgraded/` (blocked U-JSON dir — left in place; F task may use it as an end-to-end validation target but commits nothing there unless operator approves).

---

### Task I-SWEXPR: root-cause the lowering + commit the corpus RED fixture

**Files:**
- Create (corpus RED fixture, committed): `repro/mi_matrix/switch_expr_payload_capture_xmod/main.zig`
- Modify (docs note, committed): `repro/mi_matrix/EXPECTED_FAIL.md`
- Read: `sf/src/lower.zig`, `sf/src/lir.zig`, `sf/src/c89_emit.zig`, `sf/src/semantic_analyzer.zig`, sibling fixtures `repro/mi_matrix/tagged_union_cmp_xmod/main.zig` + `repro/mi_matrix/emission_assoc_chain_xmod/main.zig` (print idiom).

**Interfaces:**
- Consumes: the `/tmp/ujson/probes/` repros; json.zig original (statement switch) vs upgraded (expression switch) emitted-C diff already recorded in the CLOSURE report.
- Produces: (1) root-cause verdict with file:line evidence naming the exact instruction-placement defect; (2) a committed runtime-gated corpus fixture that is RED today (SIGSEGV/garbage on all 4 compilers) and will be GREEN only when the lowering is correct — the permanent regression guard.

- [ ] **Step 1: Root-cause the lowering defect**

Two `switch_br` lowering sites exist: `sf/src/lower.zig:4055-~4250` and `:4937-~5100`. Determine which site lowers switch-as-**expression** (value-producing) vs switch-as-**statement**, and which the fixture's shape uses. Working hypothesis to confirm/refute with evidence: at the expression-site the payload-capture `load_field`/`decl_local` instructions (lower.zig:4169/4171/4175) are emitted while `self.current_bb` is still the dispatch block, because `self.current_bb = prong_bb_id` happens AFTER the capture emission (line ~4179-4180); the case `goto` then lands past the capture loads → uninitialized capture. Verify against BOTH sites, explain why the statement-switch/block-body form emits the capture inside the case block (does it go through a different site or an ordering difference?), and produce the minimal emitted-C/LIR contrast (expression vs statement shape from the SAME site if both go through it).

Evidence to record in the report: for each site — the surrounding function name + line range, where `current_bb` is set relative to capture `emitInst`s, where the prong body is lowered, and how the exit/merge temp is handled. Confirm with `--dump-lir` (if available on the compilers) or emitted-C inspection of pA/pB.

- [ ] **Step 2: Author the corpus RED fixture**

`repro/mi_matrix/switch_expr_payload_capture_xmod/main.zig`: a self-contained, runnable, deterministic program that (a) builds a payload-carrying `union(enum)` value, (b) extracts the payload via a switch-EXPRESSION with payload capture (`const x = switch (v) { .String => |s| s, else => unreachable };`), (c) prints integer evidence of the captured payload (e.g. `@intCast`-friendly: len and first char via the print idiom used by sibling mi_matrix fixtures — follow `emission_assoc_chain_xmod`/`tagged_union_cmp_xmod` exactly for the print/extern idiom so the fixture runs under the corpus machinery), and (d) prints a statement-switch sibling result for the same payload so a correct compiler prints identical evidence from both paths. Design so RED = SIGSEGV/garbage (payload never written), GREEN = fixed deterministic stdout. Use std-free or std-bare imports per sibling-fixture convention (verify how `tagged_union_cmp_xmod` imports/prints; mirror it). Document the exact expected GREEN stdout in the fixture header comment and in EXPECTED_FAIL.md.
Keep behavior deterministic (no timers/RNG). The fixture's run must be gcc-linkable with the standard recipe (`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include` + link `zig_runtime.c` `zig_pal.c`).

- [ ] **Step 3: Prove RED on all 4 compilers**

For each of `/tmp/fx_subfolder/zig1`, `/tmp/zig1_5/zig1_5_clean`, `/tmp/zig1_5_self/zig1_5_clean`, `/tmp/zig1_5_self_self/zig1_5_clean`: `--dump-c89` the fixture into a fresh pre-created dir (expect rc=0, 0 `error[`, 0 PANIC — the bug is runtime-only), gcc-compile + link + run (expect rc=139 SIGSEGV or garbage stdout on ALL FOUR). Record the emitted-C defect region (the misplaced capture assignment before the case label) for one compiler in the report. This RED proof is the fixture's reason to exist.

- [ ] **Step 4: Record in EXPECTED_FAIL.md + commit**

Append to `repro/mi_matrix/EXPECTED_FAIL.md` a short note: the fixture, its expected GREEN stdout, its current RED status (runtime CRASH — compile-gate OK, so it is a RUNTIME-gated guard; the standard corpus compile sweep classifies it OK → the guard fires in run/golden-style batteries and the F-task gate), and the rule that it must print the expected stdout after any future change. Commit ONLY the fixture + EXPECTED_FAIL note:
```bash
git add repro/mi_matrix/switch_expr_payload_capture_xmod repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "test: RED fixture — switch-expression payload-capture mis-lowering (SIGSEGV)"
```
No compiler source touched; binaries remain `e2028dcf`.

- [ ] **Step 5: Report + STOP**

Append `## I-SWEXPR` to `.superpowers/sdd/task-SWEXPR-report.md` (root-cause verdict with file:line + emitted-C contrast, fixture design, RED proof table across the 4 compilers, commit sha). Report back under 15 lines. The controller STOP-presents the findings; the F task does NOT start without the controller (or operator) ruling.

---

### Task I2-SLICESTALE: reproduce + root-cause the stale slice-field-read quirk + commit the RED fixture

*(Operator directive 2026-09-02: I-SWEXPR surfaced a SECOND suspected front-end quirk; an additional investigation task MUST run before F-SWEXPR, and the F phase must solve both IF real. CLOSED by operator ruling 2026-09-03: the stale slice-field read is NOT reproducible (false positive — tF/tE probes' `helloA`/`helloB` share `payload[0]=='h'`/`len==6`); no fixture committed (would be GREEN); F-SWEXPR fixes ONLY the switch-expression capture-placement defect.)*

**Files:**
- Create (corpus RED fixture, committed): `repro/mi_matrix/slice_field_callee_stale_xmod/main.zig`
- Modify (docs note, committed): `repro/mi_matrix/EXPECTED_FAIL.md`
- Read: `sf/src/lower.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/c89_emit.zig`, and the I-SWEXPR probe family (tF/tE/tC/tF2/green2/control — re-derive under /tmp if the originals are not recoverable).

**Interfaces:**
- Consumes: I-SWEXPR's report (`.superpowers/sdd/task-SWEXPR-report.md` line ~116-121) describing the quirk: a slice-typed callee parameter whose FIELDS are read (`payload[0]`, `payload.len`) returns STALE values on a 2nd call when the slice came from a payload capture (probes showed `kv.tag=1` yet a `helloA` payload read inside the callee before return). Whole-slice `write()` pass-through is immune (tC/tF2/green2 correct).
- Produces: (1) a minimal deterministic reproduction, (2) a root-cause verdict with file:line evidence, (3) a committed runtime-gated corpus RED fixture that turns GREEN only when the defect is fixed.

- [ ] **Step 1: Minimal reproduction**

Build the smallest program (under /tmp/slicestale/) showing the quirk: a payload-carrying `union(enum)` whose payload is a slice; extract the slice via a payload-capture switch (statement-switch form, the one currently "correct"); pass the captured slice to a helper callee that READS slice fields (`payload[0]`, `payload.len`) rather than whole-slicing; call the path twice with DIFFERENT payload values so the 2nd call must observe the 2nd value. Also probe: (a) same shape but the capture never leaves the caller (field reads in the caller), (b) whole-write pass-through control, (c) values read immediately vs after another capture/decl is created (temp-reuse suspicion). Establish determinism (3 runs identical). Confirm the stale read reproduces on all 4 compilers (`/tmp/fx_subfolder/zig1`, `/tmp/zig1_5/zig1_5_clean`, `/tmp/zig1_5_self/zig1_5_clean`, `/tmp/zig1_5_self_self/zig1_5_clean`).

- [ ] **Step 2: Root-cause**

Determine the mechanism with evidence: is the stale read caused by (a) the payload-capture `decl_local` binding to a temp whose C storage is reused/clobbered by a later capture or call argument (name-dedup / temp-renumbering in c89_emit, `fl_temps`/F-EMITMAP `ea6882ac` behavior), (b) argument materialization reading the slice pointer/len from a stale local, or (c) something in the callee's parameter binding? Contrast the emitted C for the stale path vs the immune whole-write path (file:line in `sf/src/c89_emit.zig` and/or `sf/src/lower.zig`). Also determine whether the switch-expr placement defect (I-SWEXPR) and this quirk share a root or are independent. Record the verdict precisely — the F phase fixes both.

- [ ] **Step 3: Author the corpus RED fixture**

`repro/mi_matrix/slice_field_callee_stale_xmod/main.zig`: self-contained, runnable, deterministic; prints integer evidence (slice len + first char) for two consecutive calls with different payload values; RED today (2nd call prints the stale 1st value / garbage), GREEN = correct values both calls. Document expected GREEN stdout in the header + EXPECTED_FAIL.md. Mirror the print idiom of the I-SWEXPR fixture (whole-slice `write` for OUTPUT is fine — the STALE path under test is the callee FIELD read, keep that distinction explicit in comments). The fixture must exercise ONLY shapes that are correct-by-design post-fix; note any shape that must remain avoided.

- [ ] **Step 4: RED proof + EXPECTED_FAIL + commit**

Prove RED on all 4 compilers (dump rc=0/0 error[, gcc -c + link clean, run rc=0 with stale/garbage stdout ≠ expected). Append the EXPECTED_FAIL.md note (fixture, expected GREEN stdout, RED status, runtime-gated guard semantics). Commit ONLY the fixture + EXPECTED_FAIL.md:
```bash
git add repro/mi_matrix/slice_field_callee_stale_xmod repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "test: RED fixture — stale slice-field reads in callee on 2nd call"
```
No compiler source touched; binaries remain `e2028dcf`.

- [ ] **Step 5: Report + STOP**

Append `## I2-SLICESTALE` to `.superpowers/sdd/task-SWEXPR-report.md` (reproduction shapes, root-cause verdict with file:line + emitted-C contrast, fixture design, RED proof table, commit sha, and the statement of whether the two defects share a root). Report back under 15 lines. The controller STOP-presents; F-SWEXPR does NOT start without the controller (or operator) ruling.

---

### Task F-SWEXPR: fix the switch-expression payload-capture placement defect + full battery

*(Implementation details finalized from the I-SWEXPR verdict; I2-SLICESTALE was closed as a phantom by operator ruling 2026-09-03 and contributes no fix.)*

**STATUS (AMENDMENT 2, operator ruling 2026-09-03):** the switch-expr capture-placement fix is COMMITTED (`6d71b917`). The full battery AND the mud re-baseline (`4591fef0 → 517635c9`) are DEFERRED: the operator determined mud_server is currently a broken "sample" (its world never initializes — see Task I3-STORE-DROP below), so re-baselining it now is meaningless. Sequence now: I3-STORE-DROP (RED repro + root-cause, DONE `42d41e79`) → E-STORE-DROP (POC/experiment: candidate fixes evaluated CORPUS-ONLY, no permanent change) → operator picks 1-2 candidates → F-STORE-DROP (real fix, full battery, mud correctness vs oracle, with the SWEXPR fix retained) → combined full battery → THEN decide the final mud re-baseline once mud runtime correctness is verified against the zig0 oracle. Do NOT run F-SWEXPR's Step 4 battery standalone.

**Files:**
- Modify: `sf/src/lower.zig` (the expression-switch site `lowerExprImpl`: capture `load_field`/`decl_local` placement)
- Test: the `switch_expr_payload_capture_xmod` I fixture goes GREEN; sibling statement-switch programs byte-identical.

**Interfaces:**
- Consumes: I-SWEXPR's root-cause verdict (expression-site capture placement; lower.zig:4150-4178 emitted before `self.current_bb = prong_bb_id` at :4180).
- Produces: a corrected lowering where a payload-capture prong's `load_field`+`decl_local` instructions are emitted into the PRONG's own basic block (after `self.current_bb = prong_bb_id`), never into the dispatch fall-through region; the switch-expression result value is written by the prong block and read after the merge.

- [ ] **Step 1: RED first (TDD)**

Run the `switch_expr_payload_capture_xmod` fixture on the current reference: confirm RED (garbage-empty stdout ≠ expected GREEN) as the baseline before touching code. Also run the 4 MD5 gates + golden 9/9 to snapshot the pre-change state.

- [ ] **Step 2: Apply the fix**

Per the I-SWEXPR verdict, restructure the offending expression-switch site in `sf/src/lower.zig` so each prong's payload-capture emissions (`load_field` with `TU_FIELD_PAYLOAD`, `decl_local` for the capture name, and the capture's `addLocalDecl`) execute AFTER the emitter has switched `self.current_bb` to the prong's block id — i.e. capture setup belongs to the prong block, mirroring the statement site's ordering (lower.zig:5026 before :5028-5052). Keep the capture-name disambiguation (`maybeDisambiguateCapture`) and temp bookkeeping (`temp_variant_sub_field`) unchanged. Do not alter enum/error-literal/void-member (payload-less) prong behavior — payload-less captures bind the whole cond value and must stay as-is. No other compiler changes. Compile the changed compiler via the documented recipe (never `sf/build/out_release/`), emit the fixture, gcc + run.

- [ ] **Step 3: GREEN gate — the fixture**

`switch_expr_payload_capture_xmod`: dump rc=0, gcc clean, run prints the EXPECTED GREEN stdout, rc=0. It stays green on every future change.

- [ ] **Step 4: Full battery**

1. 4 MD5 gates byte-identical (gol/lisp/json/mud). If ANY moves, STOP for operator ruling (no silent re-baseline). 2. Golden 9/9 (incl. original lisp/json/mud statement-switch programs). 3. Matrix 21/21. 4. Corpus sweep 0-asymmetric vs the reference (the new fixture GREEN in run-style sweeps). 5. Self-compile round-trip: 42 `.c`/0 err/0 PANIC; new compiler self-compiles to a byte-identical binary (record the NEW fixed-point md5). 6. Reference rebuild 0-warning (1 pre-authorized fwrite carve-out).
- End-to-end validation (optional, not committed unless operator approves): run the existing untracked `examples/z98/json_parser_upgraded/` on the fixed compiler — it must now run rc=0 with the original `json_parser` stdout (the exact program that exposed the bug). Record the result.

- [ ] **Step 4: Full battery**

1. 4 MD5 gates byte-identical (gol/lisp/json/mud). If ANY moves, STOP for operator ruling (no silent re-baseline). 2. Golden 9/9 (incl. original lisp/json/mud statement-switch programs). 3. Matrix 21/21. 4. Corpus sweep 0-asymmetric vs the reference (and the new fixture OK in run-style sweeps — GREEN, no longer CRASH). 5. Self-compile round-trip: 42 `.c`/0 err/0 PANIC; new compiler self-compiles to a byte-identical binary (record the NEW fixed-point md5). 6. Reference rebuild 0-warning (1 pre-authorized fwrite carve-out).
- End-to-end validation (optional, not committed unless operator approves): run the existing untracked `examples/z98/json_parser_upgraded/` — the U-JSON rewrite — on the fixed compiler: it must now run rc=0 with the original `json_parser` stdout (the exact program that exposed the bug). Record the result.

- [ ] **Step 5: Commit + report**

Commit the compiler fix:
```bash
git add sf/src/lower.zig
git commit -m "fix: lower switch-expression payload captures into the prong block (SIGSEGV)"
```
Append `## F-SWEXPR` to `.superpowers/sdd/task-SWEXPR-report.md` (RED→GREEN evidence, full-battery table, new compiler md5s). Report back under 15 lines. Controller appends ledger + stores memory.

---

### Task (optional, operator-approved): commit json_parser_upgraded

Only if the operator approves after F-SWEXPR GREEN: `git add examples/z98/json_parser_upgraded` + `git commit -m "feat: json_parser_upgraded — idiomatic z98 (zig1-supersedes-zig0 demo)"`, completing the deferred U-JSON.

---

## AMENDMENT 2 (operator ruling 2026-09-03): store-drop I/F first; mud re-baseline deferred

**Context:** During the F-SWEXPR runtime check the operator asked to compare mud_server against the zig0-bootstrap oracle. The oracle moves north correctly; every zig1-emitted mud_server binary (old AND new, ref AND chain) returns "You cannot go that way." Root cause (runtime-instrumented): emitted `initRooms()` builds the two Room structs in locals (`zT_0.north = 1;` …) then `return;` — the stores `zG_2C95C42B_rooms[0] = zT_0;` / `[1] = zT_10;` are **missing from the emitted C**. The rooms global is all-zero at runtime. **zig1 DROPS struct-value assignments into a global array element.** Source: `examples/z98/mud_server/main.zig:33-47`. zig0 emits the stores correctly.

**Ruling:** Do NOT re-baseline mud now (`4591fef0 → 517635c9` is deferred; the sample is broken by the store-drop bug). Keep the SWEXPR placement fix (`6d71b917`). Run the store-drop I/F FIRST, then the combined full battery, then decide the final mud re-baseline with runtime verified against the oracle.

### Task I3-STORE-DROP: reproduce + root-cause the dropped global array-element struct store + commit the RED fixture

**Files:**
- Create (corpus RED fixture, committed): `repro/mi_matrix/global_struct_array_store_xmod/main.zig`
- Modify (docs note, committed): `repro/mi_matrix/EXPECTED_FAIL.md`
- Read: `sf/src/lower.zig`, `sf/src/c89_emit.zig`, `sf/src/semantic_analyzer.zig`, `examples/z98/mud_server/main.zig:22-47` (the source shape), the `/tmp/mudcheck_*` emitted-C evidence (initRooms missing stores).

**Interfaces:**
- Consumes: the runtime-instrumented evidence (`DBG dir=0 tag=1 room=0 north=0`; initRooms emitted C builds locals then returns with no global store).
- Produces: (1) minimal reproduction, (2) root-cause verdict (file:line) of where the global-array-element struct store is dropped in lowering/emission, (3) a committed runtime-gated corpus RED fixture (prints the room world; RED today = zeros/garbage, GREEN = the source-set values).

- [ ] **Step 1: Minimal reproduction**
Smallest program: a file-scope `var world: [N]Room = undefined;` + `fn init() void { world[0] = Room{ .north = @intCast(u8,1), ... }; }` + `main` calls init then prints `world[0].north`. Confirm on all 4 compilers that the print shows the stored value (RED today: 0 / uninitialized) and that the emitted C of init() lacks the global store. Also probe the shape matrix: scalar store to `world[0].field = v` (works?), whole-struct literal store to `world[0] = Room{...}` (dropped?), copy from a local `var r: Room = ...; world[0] = r;` (dropped?), local array `var a: [2]Room` (works?). This bounds the defect.
- [ ] **Step 2: Root-cause**
Find in `sf/src/lower.zig`/`sf/src/c89_emit.zig` how a `store` whose target is a subscripted global array element with a struct-valued source is lowered/emitted, and why the aggregate is built in a temp but the store is never emitted (or dropped by DCE/`store` handling — check whether related prior fixes F-ACOPY `0af060d8`, `emission_misc_xmod`, `field_store_drop`, `array_value_copy` fixtures are the same class). Cite file:line; state whether the defect is in lowering (no store inst emitted), emission (store inst skipped), or the analyzer. Record the verdict precisely for F-STORE-DROP.
- [ ] **Step 3: Author the corpus RED fixture**
`repro/mi_matrix/global_struct_array_store_xmod/main.zig`: self-contained, runnable, deterministic; file-scope `var rooms: [2]Room = undefined;`, `fn initRooms()` mirroring mud's shape, `main` calls it and prints integer evidence of `rooms[0].north`/`rooms[1].desc.len` etc. GREEN = source-set values; RED today = zeros. Document expected GREEN stdout in the header + EXPECTED_FAIL.md. Mirror sibling print idioms.
- [ ] **Step 4: RED proof + EXPECTED_FAIL + commit**
Prove RED on all 4 compilers (dump rc=0/0 error[, gcc clean, run prints zeros ≠ expected). Append the EXPECTED_FAIL.md note (runtime-gated guard semantics). Commit ONLY the fixture + EXPECTED_FAIL.md:
```bash
git add repro/mi_matrix/global_struct_array_store_xmod repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "test: RED fixture — global array-element struct store dropped (rooms init)"
```
- [ ] **Step 5: Report + STOP**
Append `## I3-STORE-DROP` to `.superpowers/sdd/task-SWEXPR-report.md` (shapes tested, root-cause verdict file:line, fixture design, RED proof table, commit sha). Controller STOP-presents; F-STORE-DROP does not start without a ruling.

### Task E-STORE-DROP (POC / experiment): candidate fixes, corpus-only evaluation, no permanent change

*(Operator directive 2026-09-03: BEFORE the real F-STORE-DROP, run a BOUNDED experiment to find 1-2 candidate fixes for the RED `global_struct_array_store_xmod`. Boundary: NO permanent compiler change — scratch builds only, working tree left clean; for EACH candidate run the CORPUS ONLY (no other gates) plus the RED fixture (mud "north" probe optional), to see which candidate turns the RED GREEN without opening regressions. The real F-STORE-DROP (full battery, mud correctness vs oracle, mud re-baseline decision) runs afterward on the chosen candidate. Do NOT start the experiment with a predetermined single answer — enumerate candidates and let the corpus adjudicate.)*

**Files:**
- None committed. Scratch under `/tmp/storedrop_cand/` (copy `sf/src` per candidate; edit the COPY's `c89_emit.zig`; build a scratch zig1 from the copy; restore/delete after).
- Test (read): `repro/mi_matrix/global_struct_array_store_xmod` (RED today: `0 0 0 0`; GREEN = `1 5 5 10`); the corpus (404 dirs at `-s0`, classifier per docs/sf/QUICK_REF.md lines ~61-89).

**Interfaces:**
- Consumes: I3-STORE-DROP's root-cause (mark/release two-pass liveness; `.assign_index` base array-guard c89_emit.zig:7080; unconditional base release :7237; `load_global` no_decl :7137 + `temp_global_map` :5172-5181; the `dceTempIsArray` guard born in commit `c45f7333`, no documented rationale). Baseline compiler = current HEAD (incl. SWEXPR `6d71b917`).
- Produces: a candidate table (1-2 recommended) — per candidate: exact diff, RED-fixture verdict, corpus sweep summary (asymmetric count; NEW FAIL/ICE/CRASH/gcc-error vs baseline), optional mud-north probe, and a recommendation for F-STORE-DROP.

- [ ] **Step 1: Baseline**
Build the baseline zig1 from current HEAD into a scratch dir; confirm the RED fixture prints `0 0 0 0` (RED); run the corpus sweep to capture baseline counts (the comparison reference). (Corpus = the established 404-dir `-s0` sweep reusing the documented classifier; record OK/FAIL/ICE/CRASH + asymmetric=0 vs the reference `/tmp/fx_subfolder/zig1`.)
- [ ] **Step 2: Enumerate + implement candidates (scratch copies)**
Starting set (extend if analysis reveals more): 
  - C1: mark the `.assign_index` base read unconditionally (remove the `!dceTempIsArray` guard, c89_emit.zig:7080).
  - C2: C1 AND exempt the `.assign_index` base from the release pass (:7237) so the mark is not undone.
  - C3: keep the base alive + no-decl only when it is a by-name `load_global` alias (protect/no-release for the global-alias case; targeted, globals only).
  - C4: any other locus the executor's analysis surfaces.
  For each candidate: copy `sf/src` to `/tmp/storedrop_cand/cN/`, apply the exact edit to the copy's `c89_emit.zig` (edit tool; re-read before edit), build a scratch zig1 from the copy (zig0 → gcc, never `sf/build/out_release/`), verify the candidate compiler runs.
- [ ] **Step 3: Evaluate each candidate — corpus ONLY**
For each candidate compiler: (a) emit + gcc + run the RED fixture → GREEN (`1 5 5 10`, rc=0)? (b) run the corpus sweep (404 dirs `-s0`) → compare vs baseline: asymmetric count must stay 0 and no NEW FAIL/ICE/CRASH/gcc-error; any new corpus failure = reject the candidate (matryoshka signal). Optional: mud_server "north" probe (timeout-guarded) if a candidate reaches GREEN.
- [ ] **Step 4: Report + restore + STOP**
Rank candidates; pick the 1-2 that fix RED with a clean corpus. Append `## E-STORE-DROP` to the report file (candidate table: diff, fixture verdict, corpus counts, probe, recommendation). Restore the working tree to clean (no compiler change left). NO commit of any candidate. STOP-present the candidates to the operator — F-STORE-DROP runs only after the operator chooses a candidate.

### Task F-STORE-DROP: fix the dropped global array-element struct store + mud correctness + combined battery

*(Fix shape finalized from I3-STORE-DROP findings + the candidate selected in E-STORE-DROP.)*

**Files:**
- Modify: `sf/src/lower.zig` and/or `sf/src/c89_emit.zig` (emit the missing store)
- Test: the `global_struct_array_store_xmod` fixture GREEN; mud_server movement now matches the zig0 oracle.

**Interfaces:**
- Consumes: I3's root-cause verdict; the committed RED fixture; the mud_server source shape.
- Produces: correct emission such that `world[i] = <struct value>` stores to the global; mud_server's `initRooms` populates the world; mud .Go movement behaves like the zig0 oracle.

- [ ] **Step 1: RED first** — run the I3 fixture on the current compiler (with the SWEXPR fix `6d71b917` retained): RED (zeros). Snapshot gates.
- [ ] **Step 2: Apply the fix** — per the I3-STORE-DROP verdict and the E-STORE-DROP-selected candidate, ensure a struct-valued store to a subscripted global array element emits the store (whole-struct assignment or equivalent correct field stores). No unrelated changes.
- [ ] **Step 3: GREEN gate** — I3 fixture prints expected values rc=0. Also rebuild mud_server and drive it (timeout-guarded socket probe): "north" from start must reply `A sunny clearing...` (oracle-verified), movement works.
- [ ] **Step 4: Combined full battery + final mud re-baseline decision**
Run the full battery with BOTH fixes (SWEXPR + store-drop): 4 MD5 gates (gol/lisp/json MUST stay byte-identical; **mud WILL move** — this is now the FINAL mud hash, proposed for re-baseline only with runtime verified vs the oracle per AMENDMENT 2, STOP for operator ruling), golden 9/9, matrix 21/21, corpus 0-asymmetric, self-compile round-trip (record NEW fixed-point md5), reference 0-warning, json_parser_upgraded end-to-end (run-only). Present the mud re-baseline proposal + full results to the operator.
- [ ] **Step 5: Commit + report** — commit the fix, append `## F-STORE-DROP` to the report, controller ledger + memory.
