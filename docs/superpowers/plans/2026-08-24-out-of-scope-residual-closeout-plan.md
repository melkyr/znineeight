# Out-of-Scope Residual Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out every residual item recorded as out-of-scope in the R2/R1 self-compile closeout (HEAD `aca45a01`): the `plat_stubs_missing_xmod` crash, the `c_exit` self-compile link gap, the two labeled-statement RED fixtures (po1/pco1), the optional-fn-ptr wrap gap, and the FAIL=7 corpus set — using real-Zig semantics as the oracle for all syntax/format decisions.

**Architecture:** Five phases, each an independent R/I/F (Reproduce / Investigate / Fix) cycle per the established repo methodology. Phase 1 fixes a frontend SEGV (`front_resolution.zig`). Phase 2 is a build-script link fix. Phases 3-4 fix `lower.zig` emission gaps. Phase 5 closes the seven pre-existing FAIL corpus fixtures, two of which collapse into one root (brace-less `if/else` source migration) and three of which are reclassified to green-guards because real Zig rejects the construct (oracle-governed). Ends with a GATE-FINAL sweep + docs reconciliation.

**Tech Stack:** Z98 (Zig subset) in `sf/src/`, compiled by `zig0` to C89; compiler-under-test `/tmp/fx_subfolder/zig1`; `gcc -m32 -std=c89` for emitted-C verification; `mnemoria --path .opencode/memory` for memory; SDD skill scripts under `/home/node/.cache/opencode/packages/superpowers@git+https:/github.com/obra/superpowers.git/node_modules/superpowers/skills/subagent-driven-development/scripts/`.

## Real-Zig Oracle Decisions (authoritative — decided before execution)

These two decisions were flagged open during brainstorming and are now settled by consulting the Zig Language Reference (ziglang.org/documentation/master):

1. **`{x}` format specifier.** Real Zig's `std.fmt` `{x}` formats integers as **lowercase hexadecimal with no `0x` prefix** (the prefix must come from the literal string). Demonstrated in the langref: `print("0x{x}\n", .{invalid_utf8[1]})` prints `0xfe`. **Therefore Z98 `std.io.print("{x}\n", .{v})` with `v: u8 = 65` must print `41`** — NOT `65` (current silent decimal degrade) and NOT a compile error. Phase 5.2 implements this.

2. **Brace-less `if (cond) stmt; else stmt;`.** Real Zig's grammar **rejects** this form. The `IfStatement` production is `IfPrefix BlockExpr (KEYWORD_else …)` or `IfPrefix !BlockExprPrefix AssignExpr (SEMICOLON / KEYWORD_else …)`; the ordered choice tries `SEMICOLON` first, so the `;` terminates the if-statement and the following `else` is a dangling token → parse error. `if (cond) stmt else stmt;` (no semicolon before `else`) and `if (cond) { stmt; } else stmt;` are valid. **Therefore zig1's `error[2000]` rejection of `if (cond) x = x + 1; else x = x - 1;` is CORRECT.** The fix is NOT parser leniency — it is migrating the 3 `sf/src` sites that use the invalid shape to the braced form (Phase 5.1). The fixtures `strictzig_brace_if_xmod` and `parsergap_selfblok_xmod` are then reclassified as **green-guards** (correct rejection), and the self-compile frontend blocker clears.

Corollary oracle rulings applied inside Phase 5 tasks (decided here, not deferred):
- **Scalar-base slice** (`var n: u32 = 7; var s = n[1..];`): real Zig rejects slicing a scalar (expected array/slice, found u32). The current `error[3043]` ICE must become a **clean frontend diagnostic**; the fixture becomes a green-guard.
- **Missing call-arg comma** (`f(1 2)`): real Zig rejects (expected comma). zig1 must emit a clean error; the fixture becomes a green-guard.
- **Self-referential struct via optional** (`next: ?X`): real Zig accepts (optional is pointer-like, breaks the cycle). Z98's optional-is-a-struct-by-value layout makes this infinite-size; this is a genuine layout bug to fix (or explicitly document as a deferred design item if the I-task proves it requires a layout change).

## Global Constraints

Every task implicitly includes this section:

- **Compiler-under-test:** `/tmp/fx_subfolder/zig1` (rebuild via `bash sf/scripts/build_release.sh`; gate = `=== [release] Done: /tmp/fx_subfolder/zig1 ===`). `sf/build/out_release/` is WEDGED — never touch/list/build into it.
- **Emission recipe:** `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/<x> <fixture>/main.zig`, then `cd /tmp/<x> && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c`. Runtime link adds `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c` (+ `sf/src/c_exit.c` for self-compile).
- **Z98 dialect (§1.3):** no `anytype`/`@Type`; concrete maps; `@intCast` for all i32↔usize/u64 casts; `switch` requires `else`; no method syntax; no pointer captures (`if (opt) |*p|` forbidden).
- **Editing discipline (§X.3/X.7):** `edit`/`fastedit` only. Re-read the region immediately before each `fastedit`; edit bottom-to-top; never `end_line = start_line - 1`; insert by replacing an anchor line.
- **Gates (per fix task):** target fixture GREEN (`gcc -c` rc=0); the 4 authoritative MD5s byte-identical (gol `4afb203f…`, lisp `5f886646…` repo-root CWD, json `d31e43b1…`, mud `a1d0dd55…`); matrix 21/21 (dump/gcc/link rc=0); corpus re-count; self-compile re-count; RUNTIME execution of affected programs (§2.5 runtime gates mandatory — compile-only gates forbidden).
- **Byte-identity rule:** any emitted-C change on a currently-GREEN program is a re-baseline-default case only if runtime-identical; changing a GREEN program without runtime identity requires operator ruling.
- **Review hardening (§2.5):** deviations = BLOCKED; reviewer independence (no "do not flag" instructions); evidence required for all verification claims.
- **Tech-doc maintenance (§1.1.1):** any change to lexer/parser/type-system/semantic/static-analyzers/LIR-lowering/C89-emission must update the corresponding doc in `sf/docs/tech_docs/` with `[updated: date]`.
- **Self-compile link caveat (pre-existing, out-of-scope here except Phase 2):** `build_zig1_5.sh` never linked `sf/src/c_exit.c`; Phase 2 fixes this.
- **Reports:** every I-task writes a report to `.superpowers/sdd/<task>-<phase>-report.md`; every R-task writes fixture NOTES.md + commits; implementer/reviewer per SDD skill.
- **Commit style:** one commit per task, message `fix: …` / `repro: …` / `docs: …` matching the repo's established history.

---

## Phase 1 — plat_stubs crash (`front_resolution.resolveStmtTypes` SEGV)

**Root (preliminary, I-task confirms):** `resolveStmtTypes` (`sf/src/front_resolution.zig:131-161`) recurses into `node.child_0` and `node.child_1` for EVERY node kind (`:158-160`), but some node kinds store NON-node data in those fields (e.g. a builtin-call node like `@isWindows()` stores its interned **name string-id** in `child_0`, per `sf/src/lower.zig:3169`). The recursion then reads `ct.store.nodes.items[@intCast(usize, node_idx)]` (`:133`) with a garbage index → OOB READ → ASan SEGV. Crash is **path-dependent**: it fires when the fixture is compiled from inside its own directory (`cd repro/mi_matrix/plat_stubs_missing_xmod && zig1 --dump-c89 main.zig` → ASan SEGV, rc=1) but NOT when compiled from repo root with a relative path. Reproduced deterministically at HEAD `aca45a01`. Pre-existing (introduced Aug 18-19, suspected u32-widening `378c71fa`/`50ebbf82` window; NOT caused by the R2/R1 plan). Fixture `repro/mi_matrix/plat_stubs_missing_xmod` (`main.zig` imports `console.zig`; `console.zig` = `if (@isWindows()) { @putChar('X'); }`) is the repro; it currently crashes and is mis-recorded as CRASH in the corpus.

### Task 1.1: I-PLATSTUBS (read-only investigation)

**Files:**
- Read: `sf/src/front_resolution.zig:131-161`, `sf/src/lower.zig:3150-3260` (builtin name-id handling), `sf/src/ast.zig` (AstKind child semantics), `repro/mi_matrix/plat_stubs_missing_xmod/*.zig`
- Report: `.superpowers/sdd/task-IPLATSTUBS-report.md` (gitignored)

**Interfaces:**
- Consumes: HEAD `aca45a01`, fixture above.
- Produces: pinned node kind + child-field semantics; explanation of path-dependence; recommended F design (with byte-identity verdict).

- [ ] **Step 1:** Reproduce the crash exactly: `cd repro/mi_matrix/plat_stubs_missing_xmod && mkdir -p /tmp/plat_i && rm -f /tmp/plat_i/* && timeout 60 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/plat_i main.zig`. Expected: `AddressSanitizer:DEADLYSIGNAL … zF_cbee323d_76fb677f_resolveStmtTypes`, rc=1. Also run the non-crashing variant from repo root and capture both stack traces / emission for comparison.
- [ ] **Step 2:** Instrument or reason statically to identify WHICH node kind's `child_0`/`child_1` holds a non-node value. Confirm the builtin-call hypothesis: for `@isWindows()`/`@putChar('X')` call nodes, `child_0` is the interned name id (check how `lower.zig` dispatches builtins via `node.child_0 == self.is_windows_name_id`). Trace the recursion path from `main → doConsole → block → if_stmt → call`.
- [ ] **Step 3:** Explain the path-dependence. Candidate: the set of interned strings (and thus which string ids the builtin-call nodes reference) or module node-index layout differs between the two invocation forms, so the OOB index is only out-of-bounds in the crashing form. Verify against the AST dump if possible (`--dump-ast` on both forms).
- [ ] **Step 4:** Determine the correct fix. Candidates: (a) bounds-check `node_idx` against `nodes.items.len` before deref; (b) only recurse into `child_0`/`child_1` for node kinds whose children are node indices (kind-gated recursion); (c) skip builtin-call callee children. Assess each for (i) closing the crash, (ii) preserving resolution behavior on GREEN programs, (iii) byte-identity on the 4 gates + matrix. State whether the fix changes emitted C on any currently-GREEN program. If candidates differ in byte-identity impact, STOP and escalate per plan Step-3 convention.
- [ ] **Step 5:** Write the report with the pinned mechanism, the chosen fix (exact edit), and the byte-identity verdict. Report back status + report path.

### Task 1.2: F-PLATSTUBS (fix)

**Files:**
- Modify: `sf/src/front_resolution.zig:131-161` (exact edit per I-PLATSTUBS Step 4)
- Test: `repro/mi_matrix/plat_stubs_missing_xmod/main.zig`

**Interfaces:**
- Consumes: I-PLATSTUBS pinned fix (exact locus + guard shape).
- Produces: crash-free `resolveStmtTypes`; fixture compiles GREEN.

- [ ] **Step 1:** Re-read the target region in `sf/src/front_resolution.zig`, then apply the fix with `edit`/`fastedit` per the I-PLATSTUBS design (single locus, Z98-dialect-conformant).
- [ ] **Step 2:** Rebuild: `bash sf/scripts/build_release.sh`. Expected: `=== [release] Done: /tmp/fx_subfolder/zig1 ===`.
- [ ] **Step 3:** Gate — run BOTH invocation forms on the fixture: from inside the dir AND from repo root with the relative path. Expected: dump rc=0, `.c`/`.h` emitted, NO ASan SEGV in both forms.
- [ ] **Step 4:** Gate — compile emitted C GREEN: `cd /tmp/plat_i && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c` rc=0. Link + run with the runtime recipe; record stdout.
- [ ] **Step 5:** Gate — byte-identity: run the 4 MD5 gates (gol/lisp/json/mud via the QUICK_REF recipe); all byte-identical. Matrix 21/21. Self-compile re-count (dump + `gcc -c` on `sf/src/main.zig`): record error count (must not regress from 0).
- [ ] **Step 6:** Commit: `git add sf/src/front_resolution.zig && git commit -m "fix: resolveStmtTypes recurses into non-node child fields (plat_stubs SEGV)"`.

---

## Phase 2 — c_exit self-compile link gap

**Root (fully established, no I-task needed):** `pal.zig:10` declares `extern "c" fn c_exit(code: i32) void;`, called at `pal.zig:98`. The zig0 bootstrap build links fine because zig0 generates a `zig_runtime.c` containing `void c_exit(int code) { exit(code); }` (observed at `/tmp/fx_subfolder/zig_runtime.c:365`). The self-compile (`scripts/self_compile/build_zig1_5.sh`) emits modules that call `c_exit(...)` (observed `/tmp/zig1_5/gen/pal_388A8A1B.c:602 c_exit(zT_1);`) but links only `zig_runtime.c` + `zig_pal.c`, neither of which defines `c_exit`. `sf/src/c_exit.c` (content: `#include <stdlib.h>` + `void c_exit(int code) { exit(code); }`) exists but is never linked. **User ruling: fix by linking `c_exit.c`** (not migrating to the `@exit` builtin).

### Task 2.1: F-CEXIT (build-script fix)

**Files:**
- Modify: `scripts/self_compile/build_zig1_5.sh` lines 13 and 15
- Test: run the script end-to-end

**Interfaces:**
- Consumes: nothing (standalone).
- Produces: working self-compile LINK (both `zig1_5_asan` and `zig1_5_clean`).

- [ ] **Step 1:** Read `scripts/self_compile/build_zig1_5.sh`. Add `"$ROOT/sf/src/c_exit.c"` to BOTH gcc link lines (line 13 ASan, line 15 clean), after `"$ROOT/sf/src/include/zig_pal.c"`.
- [ ] **Step 2:** Run: `bash scripts/self_compile/build_zig1_5.sh`. Expected: `=== [zig1_5] Done: /tmp/zig1_5 ===` with BOTH `zig1_5_asan` and `zig1_5_clean` produced and NO `undefined reference` errors.
- [ ] **Step 3:** If the link reports MORE undefined symbols than `c_exit`, record each (do not guess; STOP if any is not resolvable by an existing definition). Expected: only `c_exit` was missing.
- [ ] **Step 4:** Smoke-test the self-compiled compiler: `/tmp/zig1_5/zig1_5_clean --dump-c89` on a trivial program (e.g. `repro/mi_matrix/emission_assign_xmod/main.zig` into `/tmp/cex_smoke`); rc=0. Optionally run `zig1_5_asan` on the same.
- [ ] **Step 5:** Byte-identity: this change is build-script-only, so all 4 MD5s are trivially unchanged. Note this in the report; no emission re-run required.
- [ ] **Step 6:** Commit: `git add scripts/self_compile/build_zig1_5.sh && git commit -m "fix: self-compile link c_exit.c (undefined reference to c_exit)"`.

### Task 2.2: I/F-GLOBVAR (global-var emitted as stack local — self-compiled binary stack-overflow)  [AMENDMENT 2]

**Root (verified by the F-CEXIT smoke test, 2026-08-24):** after the c_exit link fix, the self-compiled
binary (`/tmp/zig1_5/zig1_5_clean` / `_asan`) core-dumps at startup: `AddressSanitizer: stack-overflow in
zF_90E832C7_initCompilerAlloc`. Cause: the module-level global `var memory_pool_buf: [POOL_SIZE]u8 = undefined`
(`sf/src/allocator.zig:184-186`, `POOL_SIZE = 268435456`) is emitted by zig1 as a **function-local temp**
(`zT_5B44B793_Arr_unsigned_char_2 zT_1;` = 256 MiB on the stack, `allocator_E75B7A0B.c:863`) instead of a
static global. zig0 (reference) emits it correctly: `static unsigned char zV_..._memory_pool_buf[268435456];`
(`/tmp/fx_subfolder/allocator.c:17`). This is a global-var emission bug (module-level `var` lowered to a stack
temp), pre-existing, NOT caused by this plan. **Operator ruling (AMENDMENT 2): add this fix task to the plan.**

**Files:**
- Read (I sub-step): `sf/src/lower.zig` (module-var → decl_local / addLocalDecl path; how module-level `var`
  gets a temp), `sf/src/c89_emit.zig` (global/static emission; `zV_`/`zG_` prefix handling), reference
  emission `/tmp/fx_subfolder/allocator.c:16-17`, self-compile emission
  `/tmp/zig1_5/gen/allocator_E75B7A0B.c:860-870`
- Modify (F): the exact locus the I sub-step pins (likely `sf/src/lower.zig` or `sf/src/c89_emit.zig`)
- Report (I sub-step): `.superpowers/sdd/task-GLOBVAR-report.md` (gitignored)
- Test: `bash scripts/self_compile/build_zig1_5.sh` then run `/tmp/zig1_5/zig1_5_clean` on a trivial input

**Interfaces:**
- Consumes: the F-CEXIT link fix (aa552f5d); the verified stack-overflow root above.
- Produces: module-level `var` arrays emitted as static globals; self-compiled binary RUNS.

- [ ] **Step 1:** (Investigate, read-only) Pin exactly where a module-level `var` (e.g. `memory_pool_buf`)
  gets lowered to a stack temp. Trace `sf/src/allocator.zig:185` through lowering + emission; compare with
  how zig0 emits the same global (static global `zV_...`). Determine whether ALL module-level `var`s are
  wrongly stack-local or only array-typed ones; identify the correct emission path (static/global storage,
  `zV_`/`zG_` naming). Verify against the 4 gates + matrix whether any currently-GREEN program has a
  module-level `var` whose emission would change (byte-identity risk). Write the I report.
- [ ] **Step 2:** Apply the fix per the I sub-step (single locus, Z98-conformant).
- [ ] **Step 3:** Rebuild via `bash sf/scripts/build_release.sh` → `=== [release] Done ===`.
- [ ] **Step 4:** Gate — self-compiled binary RUNS: `bash scripts/self_compile/build_zig1_5.sh`, then
  `/tmp/zig1_5/zig1_5_clean --help` rc=0 (no stack-overflow), then
  `/tmp/zig1_5/zig1_5_clean --dump-c89 --output-dir /tmp/gv_smoke repro/mi_matrix/emission_assign_xmod/main.zig`
  rc=0 with `.c` emitted. Verify `memory_pool_buf` is now a static global in the self-compile emission
  (grep `static.*memory_pool_buf` in `/tmp/zig1_5/gen/*.c` or equivalent).
- [ ] **Step 5:** Gate — byte-identity: 4 MD5s (gol `4afb203f…`, lisp `5f886646…` repo-root CWD, json
  `d31e43b1…`, mud `a1d0dd55…`) byte-identical; matrix 21/21. If ANY gate MD5 changes, that is a
  byte-identity break on a currently-GREEN program — **DO NOT re-baseline silently; report BLOCKED for an
  operator runtime-identity ruling.**
- [ ] **Step 6:** Gate — self-compile re-count (dump + `gcc -c` on `sf/src/main.zig`) stays 0 errors; corpus
  re-count unchanged (no fixture classification change expected — this fixes a latent emission path).
- [ ] **Step 7:** Commit: `git add <modified file(s)> && git commit -m "fix: module-level var arrays emitted as static globals (self-compile stack-overflow)"`.

### Task 2.3: I/F-NULLWRAP (?*void extern-call result optional-wrap missing NULL-check)  [AMENDMENT 3]

**Root (verified by the F-GLOBVAR gate, 2026-08-24):** after the GLOBVAR fix, the self-compiled binary still
core-dumps rc=139 at startup (`fclose(NULL)` in `pal.fileExists`, `sf/src/pal.zig:49-59`, during import
resolution). Cause: when zig1 wraps an extern-C-call result of type `?*void` (e.g. `fopen`) into an optional,
it emits `has_value = 1` **unconditionally** BEFORE the call, then checks it (`pal_388A8A1B.c:168-171`:
`zT_29.has_value = 1; zT_29.value = fopen(...); zT_30 = zT_29.has_value; if (zT_30) ...`). When `fopen`
returns NULL the orelse (`return false`) never fires → `fclose(NULL)`. zig0 reference emits the NULL-check
(`has_value = (result != NULL)`) correctly. This is an optional-wrap-of-extern-call-result missing-NULL-check
emission bug, pre-existing, separate locus from GLOBVAR. **Operator ruling (AMENDMENT 3): add this fix task.**

**Files:**
- Read (I sub-step): `sf/src/lower.zig` (optional-wrap of call results; where `?*void` / `?T` call results get
  their `.has_value` materialized), `sf/src/c89_emit.zig` (optional emission; `builtin_opt_*`/coerce paths),
  reference emission `/tmp/fx_subfolder/pal.c` (zig0's correct `has_value = fopen(...) != NULL` shape),
  self-compile emission `/tmp/zig1_5/gen/pal_388A8A1B.c:160-180`
- Modify (F): the exact locus the I sub-step pins (likely `sf/src/lower.zig` or `sf/src/c89_emit.zig`)
- Report (I sub-step): `.superpowers/sdd/task-NULLWRAP-report.md` (gitignored)
- Test: `bash scripts/self_compile/build_zig1_5.sh` then run `/tmp/zig1_5/zig1_5_clean` on a real input

**Interfaces:**
- Consumes: the GLOBVAR fix (35ebe8e3); the verified NULL-wrap mechanism above.
- Produces: extern-call `?*void` results emitted with a real NULL check (`has_value = result != NULL`);
  self-compiled binary RUNS end-to-end.

- [ ] **Step 1:** (Investigate, read-only) Pin where an extern-call result of optional type gets its
  `has_value` materialized, and why it is hard-coded to `1` instead of a NULL/zero check. Compare with the
  zig0 reference emission (`/tmp/fx_subfolder/pal.c`). Determine whether the bug is specific to `?*void`
  (extern fn returning `?*void`) or general to all optional-wrapped call results; identify the correct
  fix locus. Byte-identity risk: verify no currently-GREEN program (4 gates + matrix) wraps an extern-call
  result in an optional with a NULL check that would change; if any GREEN program's emitted C would change,
  STOP and report BLOCKED for an operator byte-identity ruling. Write the I report.
- [ ] **Step 2:** Apply the fix per the I sub-step (single locus, Z98-conformant).
- [ ] **Step 3:** Rebuild via `bash sf/scripts/build_release.sh` → `=== [release] Done ===`.
- [ ] **Step 4:** Gate A — self-compiled binary RUNS end-to-end: `bash scripts/self_compile/build_zig1_5.sh`
  (generous timeout), then `mkdir -p /tmp/nw_smoke && rm -f /tmp/nw_smoke/* && /tmp/zig1_5/zig1_5_clean
  --dump-c89 --output-dir /tmp/nw_smoke repro/mi_matrix/emission_assign_xmod/main.zig` rc=0 AND a second,
  more demanding run proving startup survives import resolution (e.g. dump `sf/src/main.zig` — or at minimum
  a multi-module fixture that triggers `fileExists`), rc=0, no crash. Verify the emitted `pal_*.c` now has a
  NULL check (`has_value = ... != NULL` or `if (fopen(...) == NULL) ...`) instead of unconditional `1`.
- [ ] **Step 5:** Gate B — byte-identity: 4 MD5s (gol `4afb203f…`, lisp `5f886646…` repo-root CWD, json
  `d31e43b1…`, mud `a1d0dd55…`) byte-identical; matrix 21/21. If ANY gate MD5 changes, report BLOCKED for an
  operator runtime-identity ruling — do not re-baseline silently.
- [ ] **Step 6:** Gate C — self-compile re-count (dump + `gcc -c` on `sf/src/main.zig`) stays 0 errors; corpus
  re-count unchanged.
- [ ] **Step 7:** Commit (only if gates clean): `git add <modified file(s)> && git commit -m "fix: optional wrap of extern-call result emits NULL check (self-compile fclose(NULL))"`.

---

## Phase 3 — labeled-statement orelse/catch RHS (po1/pco1)

**Root (preliminary, I-task confirms):** `emission_orelse_labeled_xmod` (po1: `zT_6 = prefix;` Slice→int) and `emission_catch_labeled_xmod` (pco1: `zT_4 = prefix;`) both RED with the first-parameter-leak class. The R2/R1 F-ORELSEBLK fix (commit `7a7f5928`, Fix A at `sf/src/lower.zig:3588-3597`) wrapped the orelse else-branch join materialize+assign in `if (self.block_terminated == 0)` and closed the PLAIN-block-RHS shape, but did NOT close the **labeled-statement** RHS shape (`var x = mod_a.maybe(seed) orelse blk: { return null; };`). A labeled block terminates the function via `return null`, so the join temp should never be assigned; instead `prefix` (first param, a Slice) leaks into the join temp. Both fixtures exist with full 3-module graphs + NOTES.md.

### Task 3.1: I-LABELED (read-only investigation)

**Files:**
- Read: `sf/src/lower.zig` `orelse_expr` (~:3557-3600), `catch_expr` (~:3490-3550), labeled-block lowering, `block_terminated` flag handling; `repro/mi_matrix/emission_orelse_labeled_xmod/*` and `emission_catch_labeled_xmod/*`
- Report: `.superpowers/sdd/task-ILABELED-report.md` (gitignored)

**Interfaces:**
- Consumes: both RED fixtures; knowledge that Fix A (block_terminated guard) closed the plain-block shape.
- Produces: pinned mechanism (why the labeled-block terminator does not suppress the join-assign / why `prefix` leaks); recommended F design + byte-identity verdict.

- [ ] **Step 1:** Verify both fixtures RED at HEAD: dump rc=0, then `gcc -c` rc=1 with the documented error text (`zT_6 = prefix;` / `zT_4 = prefix;`, incompatible Slice→int).
- [ ] **Step 2:** Compare the AST/lowering of the labeled-statement RHS (`blk: { return null; }`) vs the plain-block RHS (`{ return null; }`) that Fix A closed. Determine whether a labeled block's `return` sets `block_terminated` (check the labeled-statement lowering path vs plain block; check where `return` inside a labeled block routes).
- [ ] **Step 3:** Trace why the join temp gets assigned `prefix`. Candidate: the orelse/catch else-branch materializes a "null value" temp that is actually the first param temp (temp 0 == first param per the `field_store_drop` family of bugs — `lower.zig:4011` first param gets `p_temp = nextTemp(self, TYPE_UNDEFINED)` which can be 0), OR the labeled-block RHS falls through to the join-assign because `block_terminated` is not set on this path. Verify which.
- [ ] **Step 4:** Design the fix (mirror Fix A's guard for the labeled-block path, or extend the guard condition, or set `block_terminated` in the labeled-block terminator path). Assess byte-identity on the 4 gates + matrix + `emission_orelse_xmod`/`emission_catch_*` GREEN controls. If candidates differ in byte-identity impact on a GREEN program, STOP and escalate.
- [ ] **Step 5:** Write the report (mechanism, chosen fix, byte-identity verdict). Report back status + report path.

### Task 3.2: F-LABELED (fix)

**Files:**
- Modify: `sf/src/lower.zig` (exact locus per I-LABELED Step 4)
- Test: `repro/mi_matrix/emission_orelse_labeled_xmod`, `repro/mi_matrix/emission_catch_labeled_xmod`, `repro/mi_matrix/emission_orelse_xmod`, `repro/mi_matrix/emission_orelse_block_xmod`

**Interfaces:**
- Consumes: I-LABELED pinned fix.
- Produces: both labeled fixtures GREEN; no regression on orelse/catch controls.

- [ ] **Step 1:** Re-read the target region in `sf/src/lower.zig`; apply the fix per I-LABELED (single locus, Z98-conformant).
- [ ] **Step 2:** Rebuild via `bash sf/scripts/build_release.sh` → `=== [release] Done ===`.
- [ ] **Step 3:** Gate — `emission_orelse_labeled_xmod` + `emission_catch_labeled_xmod`: dump rc=0, `gcc -c` rc=0, emitted C has NO `zT_n = prefix;` line, link+run rc=0. Expected runtime: `useRet` returns the joined optional correctly (fixture NOTES defines expected output).
- [ ] **Step 4:** Gate — regression controls: `emission_orelse_xmod`, `emission_orelse_block_xmod` GREEN (gcc -c rc=0); matrix 21/21.
- [ ] **Step 5:** Gate — byte-identity: 4 MD5s byte-identical; corpus re-count: FAIL must drop by 2 (9→7); self-compile re-count stays 0.
- [ ] **Step 6:** Commit: `git add sf/src/lower.zig && git commit -m "fix: orelse/catch labeled-block RHS no longer leaks first param (zT undeclared)"`.

---

## Phase 4 — optional-fn-ptr wrap gap

**Root (preliminary, I-task confirms):** `var f: ?fn () void = foo;` (probe pv3) and struct field `cb: ?fn () void` store (probe pvo1) emit a DIRECT assign of the fn-ptr value into the optional struct WITHOUT the `.has_value`/`.value` wrap: `error: incompatible types when assigning to type 'zT_…_Opt_45' from type 'zT_…_FP_void' {aka 'void (*)(void)'}` at `f = zT_1;`. This is a distinct emission gap (optional-wrap missing for fn-pointer payloads), not one of the 23 solved fixture families. Recorded in A-ANALYZE §6.1; future fixture name suggested as `emission_opt_fptr_wrap_xmod`.

### Task 4.1: R-OPTFPTR (fixture)

**Files:**
- Create: `repro/mi_matrix/emission_opt_fptr_wrap_xmod/{main.zig,mod_a.zig,mod_b.zig,NOTES.md}`

**Interfaces:**
- Consumes: probe shapes pv3 (`var f: ?fn () void = foo;`) and pvo1 (struct field `cb: ?fn () void` store).
- Produces: RED fixture reproducing the `Opt_N ← FP_void` class, NOTES.md complete.

- [ ] **Step 1:** Author a 3-module fixture (`main.zig` imports `mod_a`/`mod_b`; at least one module has a `fn foo() void` and one assigns it to an optional fn-ptr var `var f: ?fn()void = foo;` and/or stores it into a struct field `cb: ?fn()void`; Z98 dialect, no anytype). Include `std.io.printInt` or an equivalent sink so the graph lowers. Mirror the pv3/pvo1 probe shapes verbatim where possible.
- [ ] **Step 2:** Verify RED: dump rc=0; `gcc -c` rc=1 with `incompatible types when assigning to type 'zT_…_Opt_<n>' from type 'zT_…_FP_void'`. Record exact error text + emitted-C lines in NOTES.md. Add a GREEN control shape in NOTES.md (e.g. the same assign with a non-fn-ptr payload like `var f: ?i32 = 5;` compiles GREEN) to pin the class to the fn-ptr payload.
- [ ] **Step 3:** Write NOTES.md per the fixture convention (purpose / verbatim source / RED evidence / root-cause pin to `lower.zig` optional-wrap assign path / expected post-fix).
- [ ] **Step 4:** Commit: `git add repro/mi_matrix/emission_opt_fptr_wrap_xmod && git commit -m "repro: optional fn-pointer wrap emission fixture (Opt_N vs FP_void)"`.

### Task 4.2: I-OPTFPTR (read-only investigation)

**Files:**
- Read: `sf/src/lower.zig` optional-wrap / assign paths (plain_assign, optional coercion/coerceOptional, `has_value`/`value` materialization), `sf/src/c89_emit.zig` optional emission; the new fixture
- Report: `.superpowers/sdd/task-IOPTFPTR-report.md` (gitignored)

**Interfaces:**
- Consumes: R-OPTFPTR fixture.
- Produces: pinned mechanism (why fn-ptr payload skips the optional wrap); recommended F design + byte-identity verdict.

- [ ] **Step 1:** Confirm the fixture RED at HEAD (dump rc=0, gcc -c rc=1, exact `Opt_N ← FP_void` text).
- [ ] **Step 2:** Locate where an optional-typed var init / field store materializes `.has_value` and `.value`. Determine why a fn-ptr payload takes the DIRECT-assign path instead. Candidates: the coercion/optional-wrap branch matches on payload type and lacks a fn-pointer arm; or the payload temp type for `fn()void` resolves differently. Trace `var f: ?fn()void = foo;` end-to-end.
- [ ] **Step 3:** Confirm the GREEN control (non-fn-ptr payload) takes the wrapped path, isolating the fn-ptr-specific gap.
- [ ] **Step 4:** Design the fix (extend the optional-wrap to fn-pointer payloads; exact locus). Byte-identity: verify no GREEN gate/corpus program wraps a fn-pointer in an optional (A-ANALYZE already found none) — if so, no re-baseline. If the fix would alter a GREEN program, STOP and escalate.
- [ ] **Step 5:** Write the report (mechanism, fix, byte-identity verdict). Report back status + report path.

### Task 4.3: F-OPTFPTR (fix)

**Files:**
- Modify: `sf/src/lower.zig` (or `sf/src/c89_emit.zig` per I-OPTFPTR) — exact locus
- Test: `repro/mi_matrix/emission_opt_fptr_wrap_xmod`

**Interfaces:**
- Consumes: I-OPTFPTR pinned fix.
- Produces: fixture GREEN (optional fn-ptr wrap emitted correctly); binary runs.

- [ ] **Step 1:** Re-read the target region; apply the fix per I-OPTFPTR (single locus, Z98-conformant).
- [ ] **Step 2:** Rebuild via `bash sf/scripts/build_release.sh` → `=== [release] Done ===`.
- [ ] **Step 3:** Gate — fixture: dump rc=0, `gcc -c` rc=0, emitted C shows the optional wrap (`.has_value` set + `.value`/payload assign, or equivalent), link + run rc=0 with expected stdout.
- [ ] **Step 4:** Gate — regression: `emission_void_call_xmod` (void fn-ptr family, GREEN control) still GREEN; matrix 21/21.
- [ ] **Step 5:** Gate — byte-identity: 4 MD5s byte-identical; corpus re-count (new fixture must be GREEN, so OK count rises by 1).
- [ ] **Step 6:** Commit: `git add sf/src/lower.zig sf/src/c89_emit.zig && git commit -m "fix: optional wrap for fn-pointer payloads (Opt_N vs FP_void)"` (adjust paths to actual edit).

---

## Phase 5 — FAIL=7 corpus closeout

Seven pre-existing FAIL fixtures. Two collapse into one root (brace-less `if/else` migration). Three are reclassified to green-guards because real Zig rejects the construct. Two are genuine compiler-correctness fixes. One (self-referential optional struct) may be a layout-level item. Order below is dependency-sorted (migration first, since it unblocks self-compile frontend).

### Task 5.1: F-BRACEMIG (strictzig_brace_if + parsergap_selfblok — one root)

**Files:**
- Modify: `sf/src/type_resolver.zig:980-981`, `sf/src/type_resolver.zig:987-990`, `sf/src/diagnostics.zig:295-296` (the 3 brace-less `if (…) stmt; else stmt;` sites)
- Test: `repro/mi_matrix/strictzig_brace_if_xmod`, `repro/mi_matrix/parsergap_selfblok_xmod`, self-compile frontend

**Interfaces:**
- Consumes: oracle ruling #2 (real Zig rejects brace-less `if;else`; braced form valid); the two fixtures.
- Produces: 3 sites in braced form; self-compile frontend blocker clears; both fixtures reclassified as green-guards; byte-identity preserved.

- [ ] **Step 1:** Confirm both fixtures RED at HEAD: `strictzig_brace_if_xmod` → `error[2000]` rejection (expected, correct per oracle); `parsergap_selfblok_xmod` → `error[2000]` at the fixture's brace-less if/else.
- [ ] **Step 2:** Re-read the 3 target sites. Convert each `if (cond) stmt; else stmt;` to `if (cond) { stmt; } else stmt;` (braces around the then-body — the form the rest of `sf/src` already uses, per the selfblok NOTES control). Z98-dialect-conformant; do NOT change any logic.
- [ ] **Step 3:** Rebuild via `bash sf/scripts/build_release.sh` → `=== [release] Done ===`.
- [ ] **Step 4:** Verify byte-identity of the migration: the migration must emit byte-identical C (per strictzig_brace_if NOTES). Rebuild the 4 MD5 gates; all byte-identical. Also confirm `--dump-c89` of the migrated sources (self-compile frontend) no longer shows `error[2000]` at `type_resolver.zig:981`/`diagnostics.zig:295`.
- [ ] **Step 5:** Reclassify (docs): `strictzig_brace_if_xmod` → green-guard (correct rejection); `parsergap_selfblok_xmod` → green-guard (correct rejection). Update NOTES.md headers if they assert otherwise.
- [ ] **Step 6:** Gate — corpus re-count: FAIL drops by 2 (the two fixtures move to green-guards). Self-compile frontend re-count: the brace-less cascade clears (record error-count change).
- [ ] **Step 7:** Commit: `git add sf/src/type_resolver.zig sf/src/diagnostics.zig repro/mi_matrix/strictzig_brace_if_xmod repro/mi_matrix/parsergap_selfblok_xmod && git commit -m "fix: migrate brace-less if/else sites to braced form (strict-zig, self-compile blocker)"`.

### Task 5.2: F-SPECIFIER (parsergap_specifier — `{x}` hex)

**Files:**
- Modify: `sf/src/lower.zig:549-556` (print specifier capture — B-F1) and the print/format emission path (`std_io.zig`/`c89_emit.zig` where the specifier is dispatched)
- Test: `repro/mi_matrix/parsergap_specifier_xmod/main.zig`

**Interfaces:**
- Consumes: oracle ruling #1 (`{x}` = lowercase hex, no prefix → `41` for 65).
- Produces: `{x}` prints lowercase hex; fixture GREEN printing `41`.

- [ ] **Step 1:** Confirm the fixture RED-at-runtime at HEAD: compiles, but `std.io.print("{x}\n", .{v})` with `v: u8 = 65` prints `65` (silent decimal degrade).
- [ ] **Step 2:** Read `sf/src/lower.zig:549-556` (specifier capture) and the print dispatch. Determine where `{x}` currently falls through to decimal. Add an `x` specifier arm that formats the integer as lowercase hex (no `0x` prefix). Z98-dialect-conformant; reuse any existing hex-format helper (e.g. `writeHex` in `c89_emit.zig`) rather than adding `@Type`/anytype.
- [ ] **Step 3:** Rebuild via `bash sf/scripts/build_release.sh` → `=== [release] Done ===`.
- [ ] **Step 4:** Gate — fixture: dump rc=0, `gcc -c` rc=0, link + run rc=0, **stdout `41`** (the oracle-expected output). Also verify `{d}` still prints decimal and `{}`/`{c}` unaffected (no regression on existing print usage in gates/matrix).
- [ ] **Step 5:** Gate — byte-identity: 4 MD5s byte-identical (no GREEN gate/corpus program uses `{x}`); matrix 21/21. Corpus re-count: `parsergap_specifier_xmod` moves FAIL→GREEN.
- [ ] **Step 6:** Commit: `git add sf/src/lower.zig sf/src/std_io.zig && git commit -m "fix: {x} print specifier formats lowercase hex (was silent decimal degrade)"` (adjust paths).

### Task 5.3: F-STRICTCOMMA (parsergap_strict_comma)

**Files:**
- Modify: `sf/src/parser.zig:401-407` (call-arg comma handling)
- Test: `repro/mi_matrix/parsergap_strict_comma_xmod/main.zig`

**Interfaces:**
- Consumes: oracle ruling (real Zig rejects `f(1 2)` — expected comma).
- Produces: missing comma between call args is a clean error; fixture becomes a green-guard (correct rejection).

- [ ] **Step 1:** Confirm the fixture behavior at HEAD: `f(1 2)` is SILENTLY accepted and compiles to the same program as `f(1, 2)` (dump rc=0, GREEN — the bug).
- [ ] **Step 2:** Read `sf/src/parser.zig:401-407`. Change the comma handling so a missing comma between call arguments is a clean `error[2000]`-style diagnostic (require the comma; do NOT silently skip). Verify the valid `f(1, 2)` form still parses.
- [ ] **Step 3:** Rebuild via `bash sf/scripts/build_release.sh` → `=== [release] Done ===`.
- [ ] **Step 4:** Gate — fixture: dump rc≠0 with a clean diagnostic on `f(1 2)` (no ICE, no crash). Reclassify `parsergap_strict_comma_xmod` as a green-guard in NOTES/docs.
- [ ] **Step 5:** Gate — byte-identity: 4 MD5s byte-identical (no GREEN program has a missing comma); matrix 21/21; corpus re-count FAIL drops by 1.
- [ ] **Step 6:** Commit: `git add sf/src/parser.zig && git commit -m "fix: require comma between call arguments (missing-comma now errors)"`.

### Task 5.4: I/F-SLICESCALAR (parsergap_slice_expr — scalar-base ICE)

**Files:**
- Modify: `sf/src/lower.zig:722-739` (ICE path), `:3849-3921` (slice_expr lowering) — or the frontend sema/type-checker per investigation
- Report (I sub-step): `.superpowers/sdd/task-SLICESCALAR-report.md` (gitignored)
- Test: `repro/mi_matrix/parsergap_slice_expr_xmod/main.zig`

**Interfaces:**
- Consumes: oracle ruling (real Zig rejects scalar-base slice); the RED fixture (current `error[3043]` ICE).
- Produces: scalar-base (or otherwise unsupported) `[a..]` slicing is a clean frontend diagnostic, not an ICE; fixture becomes a green-guard.

- [ ] **Step 1:** Confirm the fixture ICE at HEAD: dump rc=3, stderr `error[3043]: internal: unsupported slice_expr form/base (node 9)`, 0 `.c`.
- [ ] **Step 2:** (Investigate, read-only) Determine where a scalar-base slice should be rejected. Real-Zig semantics: `var n: u32 = 7; var s = n[1..];` is a type error. Verify the fixture program is genuinely invalid (scalar base) vs a supported-shape gap. Identify the correct rejection point (frontend type-check vs the lowering ICE). Decide: clean diagnostic at the frontend for non-array/non-slice/non-pointer base. Write the investigation report.
- [ ] **Step 3:** Apply the fix: replace the `iceSliceUnsupported` fall-through for invalid base types with a clean diagnostic (mirror existing error[3xxx] frontend errors; no crash/exit-3). Keep the supported bases (slice_type / array_type) working unchanged.
- [ ] **Step 4:** Rebuild via `bash sf/scripts/build_release.sh` → `=== [release] Done ===`.
- [ ] **Step 5:** Gate — fixture: dump rc≠0 with a CLEAN diagnostic (no `error[3043]`, no ICE); supported control shapes still GREEN (array `buf[1..]`, slice-of-slice `rem[cut..]`, two-bound `buf[0..2]` per NOTES — dump rc=0, gcc rc=0). Reclassify `parsergap_slice_expr_xmod` as a green-guard.
- [ ] **Step 6:** Gate — byte-identity: 4 MD5s byte-identical (no GREEN program hits the ICE path); matrix 21/21; corpus re-count FAIL drops by 1.
- [ ] **Step 7:** Commit: `git add sf/src/lower.zig && git commit -m "fix: scalar-base slice_expr is a clean diagnostic, not an ICE (3043)"`.

### Task 5.5: I/F-FIELDSTORE (field_store_drop — temp-0 sentinel collision)

**Files:**
- Modify: `sf/src/lower.zig` — `findLocalTemp` sentinel (`:926`), `nextTemp` start (`:322`), first-param `p_temp` (`:4011`), `plain_assign` skip-store (`:1376`), ident_expr load_local (`:1677-1678`)
- Report (I sub-step): `.superpowers/sdd/task-FIELDSTORE-report.md` (gitignored)
- Test: `repro/mi_matrix/field_store_drop`

**Interfaces:**
- Consumes: fixture NOTES (root cause pinned: `findLocalTemp` returns `0` as "not found" sentinel but `nextTemp` starts at `0`, so the first param's temp is `0` → `plain_assign` treats `src == 0` as skip-store).
- Produces: sentinel collision eliminated; `field_store_drop` GREEN; no silent store drop.

- [ ] **Step 1:** Confirm the fixture RED at HEAD (record exact error class; NOTES: undeclared `zT_11/zT_16/…` + the extra-load_local copy symptom).
- [ ] **Step 2:** (Investigate, read-only) Map every `0`-sentinel collision in `lower.zig` (the NOTES names `findLocalTemp`→0, `nextTemp`→0-first, `plain_assign`→src==0 skip). Decide the least-invasive fix: prefer a sentinel change (e.g. `findLocalTemp` returns a distinct `TEMP_NONE` value, or `nextTemp` starts at 1) IF byte-identity on all 4 gates + matrix is preserved; if any GREEN program's emitted C would change (temp numbering shifts), STOP and escalate per the byte-identity rule. Write the investigation report with the exact fix + byte-identity evidence.
- [ ] **Step 3:** Apply the fix per the I sub-step (single, focused change).
- [ ] **Step 4:** Rebuild via `bash sf/scripts/build_release.sh` → `=== [release] Done ===`.
- [ ] **Step 5:** Gate — fixture: dump rc=0, `gcc -c` rc=0, link + run rc=0 with expected stdout; emitted C shows all three stores (`t.a`, `t.b`, `t.c`) without the extra load_local copy (or with it, if the chosen fix keeps numbering). Record exact emitted-C delta.
- [ ] **Step 6:** Gate — byte-identity: 4 MD5s byte-identical (CRITICAL for this fix — any temp renumbering must be verified against all 4 gates). Matrix 21/21. Corpus re-count: `field_store_drop` moves FAIL→GREEN.
- [ ] **Step 7:** Commit: `git add sf/src/lower.zig && git commit -m "fix: findLocalTemp 0-sentinel collides with first-param temp 0 (field_store_drop)"`.

### Task 5.6: I/F-SELFCYCLE (self_embed_optional_cycle)

**Files:**
- Read: `sf/src/type_resolver.zig`, `sf/src/c89_emit.zig` (struct layout + optional emission), `repro/mi_matrix/self_embed_optional_cycle/*`
- Report (I sub-step): `.superpowers/sdd/task-SELFCYCLE-report.md` (gitignored)
- Test: `repro/mi_matrix/self_embed_optional_cycle`

**Interfaces:**
- Consumes: oracle ruling (real Zig accepts `next: ?X` — optional breaks the cycle); the RED fixture (`error[24]`, infinite-size C type).
- Produces: either a fix making self-referential-optional structs compile GREEN, OR an explicit documented deferral with operator sign-off.

- [ ] **Step 1:** Confirm the fixture RED at HEAD (record exact diagnostic; NOTES: expected `error[24]` / topo-2-cycle or gcc incomplete-type `struct X { struct X next; int has_value; }`).
- [ ] **Step 2:** (Investigate, read-only) Trace how an optional field's payload type is laid out for a self-referential struct. Determine whether Z98's optional (struct with has_value + payload by value) can ever be finite for `next: ?X`, or whether it requires a pointer/indirect representation that is a larger layout change. Assess blast radius (how many programs/gates touch optional struct layout).
- [ ] **Step 3:** DECISION GATE: present the I-task findings to the operator with two options — (a) fix the optional layout for self-referential payloads (may change emitted C for optional-struct programs → byte-identity risk, needs operator ruling), or (b) document `self_embed_optional_cycle` as an accepted deferral (real-Zig-supported construct that Z98's by-value-optional design intentionally defers). STOP for the ruling before any `sf/src` edit.
- [ ] **Step 4:** Per the ruling: if (a), implement the fix and run the full gate battery (fixture GREEN, 4 MD5s byte-identical OR operator-approved re-baseline, matrix, corpus re-count FAIL drops by 1). If (b), update NOTES.md/docs to record the deferral and reclassify the fixture per the operator's decision, commit docs only.
- [ ] **Step 5:** Commit accordingly (fix commit or docs commit).

---

## GATE-FINAL — full sweep + docs reconciliation

**Files:**
- Modify: `docs/sf/EXPECTED_FAIL.md` (v46→v47 closeout), `docs/sf/QUICK_REF.md` (post-residual baseline), `docs/superpowers/plans/2026-08-24-out-of-scope-residual-closeout-plan.md` (closeout annotation)

**Interfaces:**
- Consumes: all completed phases above.
- Produces: reconciled corpus state, EXPECTED_FAIL v47 closeout, QUICK_REF baseline, milestone statement.

- [ ] **Step 1:** Final sweep: 4 MD5s byte-identical; matrix 21/21; full corpus re-count (list every fixture that changed classification); self-compile re-count (dump + `gcc -c`); test_analyzer_bin result.
- [ ] **Step 2:** Self-compile LINK: run `bash scripts/self_compile/build_zig1_5.sh` — BOTH `zig1_5_asan` + `zig1_5_clean` link rc=0. Optionally run the self-compiled compiler on a trivial input (smoke). This is the **self-compile LINK-green milestone** (was blocked on `c_exit`).
- [ ] **Step 3:** Reconcile docs: EXPECTED_FAIL v46→v47 closeout (per-phase fix list with SHAs, oracle rulings, green-guard reclassifications, deferral record if any, milestone statement); QUICK_REF post-residual baseline paragraph (corpus counts, self-compile link-green, `c_exit` fix, plat_stubs green, new fixture count). Verify internal consistency (same corpus numbers, same SHAs in both docs).
- [ ] **Step 4:** Ledger + memory: append the closeout entry to `.superpowers/sdd/progress.md`; store per-phase memories via `mnemoria --path .opencode/memory`.
- [ ] **Step 5:** Commit: `git add docs/sf/EXPECTED_FAIL.md docs/sf/QUICK_REF.md && git commit -m "docs: out-of-scope residual closeout GATE + reconciliation"`.

---

## Expected Final State

- **Corpus:** `plat_stubs_missing_xmod` GREEN (CRASH→GREEN); `emission_orelse_labeled_xmod` + `emission_catch_labeled_xmod` GREEN; `emission_opt_fptr_wrap_xmod` GREEN (new); `parsergap_specifier_xmod` GREEN; `field_store_drop` GREEN; `strictzig_brace_if_xmod`/`parsergap_selfblok_xmod`/`parsergap_strict_comma_xmod`/`parsergap_slice_expr_xmod` → green-guards; `self_embed_optional_cycle` per operator ruling. FAIL count drops from 9 to 0 (or to whatever the self-cycle ruling yields); CRASH count 1→0.
- **Self-compile:** frontend frontend-blocker (brace-less if) cleared; gcc -c stays 0-error; **LINK green** and **self-compiled binary RUNS** (`zig1_5_clean` + `zig1_5_asan` build, smoke rc=0) — new milestones (link via Task 2.1, run via Task 2.2 global-var fix).
- **Oracle compliance:** `{x}` prints lowercase hex (`41` for 65); brace-less `if;else` stays a correct rejection; scalar-base slice and missing-comma are clean errors.
- **Byte-identity:** all 4 MD5s unchanged unless a task explicitly receives operator approval for a runtime-identical re-baseline (only the temp-sentinel task is at risk; it must prove byte-identity before commit).

---

## AMENDMENT 1 — plat_stubs fix = Option B (kind-gated recursion)  [2026-08-24, operator ruling]

Task 1.1 (I-PLATSTUBS) pinned the mechanism: `AstKind.builtin_call` stores its interned
name string-id in `child_0` (`parser.zig:645`; `lower.zig:3169/3225` dispatch on
`child_0 == name_id`), and `resolveStmtTypes` (`front_resolution.zig:159→133`)
unconditionally recurses into `child_0`/`child_1` as node indices. The crash is
path-dependent because module-path interning shifts the builtin string-ids by 1
(27/28 vs 28/29), selecting different stale slots in the nodes array's spare capacity
(≥ `len` but within capacity) → garbage-cascade → wild-index SEGV.

I-PLATSTUBS escalated a plan Step-3 fork (candidates differ in byte-identity impact on
the GREEN gol gate). **Operator RULED Option B — kind-gated recursion** (the
semantically-correct root fix), NOT the bounds-guard Option A.

Consequences for F-PLATSTUBS (Task 1.2):
- Implement kind-gated recursion: in `resolveStmtTypes`, only recurse into `child_0`/
  `child_1` for node kinds whose children ARE node indices; do NOT recurse into
  `builtin_call.child_0` (a string id). Equivalently, skip the builtin-call callee
  children (candidate (c) ≡ (b) here per the audit).
- Because Option B changes traversal on all 4 gates (all have reachable builtin_calls
  in fn bodies), F-PLATSTUBS **MUST gate-verify** the 4 MD5s (gol `4afb203f…`, lisp
  `5f886646…` repo-root CWD, json `d31e43b1…`, mud `a1d0dd55…`) and the 21-fixture
  matrix. If ANY gate MD5 changes, that is a byte-identity break on a currently-GREEN
  program and REQUIRES a fresh operator runtime-identity re-baseline ruling BEFORE the
  fix may be committed — do not re-baseline silently.
- Fixture outcome: `plat_stubs_missing_xmod` compiles GREEN (no SEGV, both invocation
  forms), CRASH→GREEN in the corpus.

---

## AMENDMENT 2 — new Task 2.2 F-GLOBVAR (global-var emitted as stack local)  [2026-08-24, operator ruling]

The F-CEXIT smoke test revealed a pre-existing emission bug blocking the self-compiled
binary from running: module-level `var memory_pool_buf: [268435456]u8`
(`sf/src/allocator.zig:184-186`) is emitted by zig1 as a **function-local temp**
(256 MiB stack array in `initCompilerAlloc`) instead of a static global; zig0 emits it
as `static unsigned char zV_..._memory_pool_buf[268435456];` and runs fine. This is a
global-var emission bug, NOT caused by this plan, NOT in the original scope.

**Operator RULED: add a fix task now** — Task 2.2 (I/F-GLOBVAR, inserted after Task 2.1
in Phase 2, executed before Phase 3). It fixes the global-var-as-stack-local emission
so the self-compiled binary RUNS. Same gate discipline as every fix task: 4 MD5s
byte-identical (else STOP for a runtime-identity ruling), matrix 21/21, self-compile
re-count 0, self-compiled binary smoke rc=0. Milestone now reads: self-compile **LINK
green AND self-compiled binary RUNS**.

---

## AMENDMENT 3 — new Task 2.3 I/F-NULLWRAP (?*void extern-call optional-wrap missing NULL-check)  [2026-08-24, operator ruling]

After Task 2.2 (GLOBVAR) fixed the 256 MiB stack-local emission, the self-compiled
binary still crashed rc=139 at startup: `fclose(NULL)` in `pal.fileExists`
(`sf/src/pal.zig:49-59`) during import resolution. Root: zig1 emits `has_value = 1`
**unconditionally** when wrapping an extern-C-call result of type `?*void` (fopen)
into an optional (`pal_388A8A1B.c:168-171`), so the `orelse return false` never fires
on a NULL result → `fclose(NULL)`. zig0 reference emits `has_value = result != NULL`
correctly. Pre-existing, separate locus from GLOBVAR.

**Operator RULED: add a fix task now** — Task 2.3 (I/F-NULLWRAP, inserted after
Task 2.2 in Phase 2, executed before Phase 3). Same gate discipline as every fix task:
4 MD5s byte-identical (else STOP for a runtime-identity ruling), matrix 21/21,
self-compile re-count 0, and the self-compiled binary must RUN end-to-end (real-input
dump, not `--help`, which the reference compiler also rejects).

The Phase 2 milestone is thereby: self-compile **LINK green AND self-compiled binary
RUNS** (via Tasks 2.1 + 2.2 + 2.3).

---

## AMENDMENT 4 — NULLWRAP applied + json re-baseline + self-emission gap residual  [2026-08-24, operator rulings]

Task 2.3 (F-NULLWRAP) was BLOCKED on a byte-identity break: the fix (emit `has_value =
result != 0` for optional-wrapped extern-call results instead of unconditional `1`) is
correct and general (`.call_direct` need_wrap, `c89_emit.zig:5503-5549`), but json_parser
wraps `fopen(...) ?*File` with `orelse return error.OpenFailed` and had the SAME latent
bug, so its emitted C changes.

**Ruling 1 (json re-baseline):** operator APPROVED the fix + json gate re-baseline. The
change is runtime-identical on every program's normal path (fopen succeeds → has_value=1
either way) and repairs the NULL path (orelse fires; latent NULL-crash fixed). gol/lisp/mud
byte-identical. **json re-baselined: `d31e43b19f752e40b9fd4b8885b13600` →
`089e4f046464ce3882aa2b2c4e585013`** (recorded in QUICK_REF.md, commit a6fe169b + docs).
`089e4f046464ce3882aa2b2c4e585013` is the authoritative json hash for all remaining gates.

**Ruling 2 (self-emission gap deferred):** a THIRD pre-existing blocker surfaced during
Gate A — the self-compiled binary now RUNS (crash fixed) but misparses basic operators
(`1 + 1`, `y = 5`, `x.len`, `y == 0`) → 27,664 `error[2000]` parse errors self-dumping
`sf/src/main.zig`. Proven independent of NULLWRAP (parser.c/lexer.c/token.c/ast.c
byte-identical pre/post). This is a **self-emission fidelity gap** (zig1 mis-emits its own
parser/lexer), potentially deep, NOT a single-locus fix. Operator ruled: **defer** — record
as a new major out-of-scope residual requiring its own dedicated R/I/F plan.

Phase 2 milestone (amended): self-compile **LINK green, self-compiled binary RUNS
(crash-free)**; the deeper self-emission fidelity gap is a recorded deferred residual and
does NOT block Phases 3-5, which do not depend on the self-compiled binary running.

---

## AMENDMENT 5 — field_store_drop fixture corrected + reclassified OK  [2026-08-24, operator ruling]

During Task 5.5 (I/F-FIELDSTORE) dispatch the operator asked to correct the fixture's
bare `@import("pal")` to the canonical `@import("pal.zig")` form. Investigation found the
fixture had TWO stale dependencies masking its documented temp-0 sentinel target:
1. `main.zig:1` bare `@import("pal")` → `error[3048]` at import resolution (a user program
   cannot import the compiler-internal `pal` module by bare name). Corrected to
   `@import("pal.zig")` + a bundled self-contained `pal.zig` stub providing `stderr_write`
   (via the `@stderrWrite` builtin) — the canonical fixture pattern (cf. `emission_pal_xmod`).
2. `__bootstrap_print_int(...)` — a bare extern removed from the runtime (F4). Corrected to
   `std.io.printInt(...)` (the canonical fixture sink).

**Result (operator ruling):** `field_store_drop` is now GREEN (dump/gcc/link/run rc=0;
stdout `2030`, stderr `OK`). The emitted `store()` shows direct `t.s = s; t.b = b; t.c = c;`
— the temp-0 sentinel extra-copy symptom is GONE. **The temp-sentinel bug is superseded by
later compiler fixes; Task 5.5's code fix is MOOT — no `sf/src` change needed.**
Reclassified **FAIL → OK** (fixture NOTES.md + QUICK_REF current-state note; commit
`3ef2e8c8`). Corpus: 323 dirs = OK 313 / FAIL 1 / ICE 0 / CRASH 0 / GREEN 9.

**Remaining FAIL=1** = `self_embed_optional_cycle` (error[24], the genuine deferred design
gap — Z98's optional-by-value cannot break a self-referential struct cycle; real Zig accepts
it because its optional is pointer-like). Handled by Task 5.6's decision-gate: operator may
rule to (a) attempt an optional-layout fix (large blast radius, byte-identity risk) or
(b) record it as an accepted deferral (the plan's default) and proceed to GATE-FINAL.
