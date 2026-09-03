# switch-expression payload-capture emission fix — Implementation Plan (I/F)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the zig1 lowering/emission bug where a switch used as an **expression** with a **payload-capture** prong places the capture load in the dispatch fall-through (skipped by the case `goto` → uninitialized read → SIGSEGV), leaving a permanent corpus repro so the bug can never silently return.

**Architecture:** I task (read-only analysis + corpus RED fixture committed) → STOP-present → F task (locus-corrected lowering in `sf/src/lower.zig`) → full battery GATE. Bug context: discovered in the zig1 self-host closure plan Task U-JSON (`const key = switch (keyVal) { .String => |s| s, else => unreachable };` → rc=139 SIGSEGV on all 4 compilers); evidence at `/tmp/ujson/probes/pA.zig` (exhaustive 2-prong, no else) + `pB.zig` (`else => unreachable`), both mis-emit; the statement-switch block form (original json.zig) emits correctly. Reported in `.superpowers/sdd/task-CLOSURE-report.md` `## U-JSON`.

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

### Task F-SWEXPR: fix the lowering so payload-capture loads live in the prong block + full battery

*(Implementation details finalized from I-SWEXPR findings; the fix text below is the expected shape and must be reconciled against the I verdict before coding.)*

**Files:**
- Modify: `sf/src/lower.zig` (the offending site(s): capture `load_field`/`decl_local` placement)
- Test: the I fixture goes GREEN; sibling statement-switch programs byte-identical.

**Interfaces:**
- Consumes: I-SWEXPR's root-cause verdict (which site, which ordering).
- Produces: a corrected lowering where a payload-capture prong's `load_field`+`decl_local` instructions are emitted into the PRONG's own basic block (after `self.current_bb = prong_bb_id`), never into the dispatch fall-through region; the switch-expression result value is written by the prong block and read after the merge.

- [ ] **Step 1: RED first (TDD)**

Run the I fixture on the current reference: confirm RED (SIGSEGV/garbage) as the baseline before touching code. Also run the 4 MD5 gates + golden 9/9 to snapshot the pre-change state.

- [ ] **Step 2: Apply the fix**

Per the I verdict, restructure the offending switch-lowering site in `sf/src/lower.zig` so the prong payload-capture emissions (`load_field` with `TU_FIELD_PAYLOAD`, `decl_local` for the capture name, and the capture's `addLocalDecl`) execute AFTER the emitter has switched `self.current_bb` to the prong's block id — i.e. capture setup belongs to the prong block, mirroring the site/shape that already emits correctly (the block-body statement path). Keep the capture-name disambiguation (`maybeDisambiguateCapture`) and temp bookkeeping (`temp_variant_sub_field`) unchanged. Do not alter enum/error-literal/void-member (payload-less) prong behavior — payload-less captures bind the whole cond value and must stay as-is. No other compiler changes. Compile the changed compiler (`bash sf/scripts/build_release.sh` into a scratch OUT dir OR the documented manual recipe — never `sf/build/out_release/`), emit the I fixture, gcc + run.

- [ ] **Step 3: GREEN gate — the fixture**

I fixture: dump rc=0, gcc clean, run prints the EXPECTED GREEN stdout (len + first char evidence from BOTH the expression-switch and statement-switch siblings), rc=0. This is the regression guard: it must stay green on every future change.

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
