# sf/src_sh/ Self-Containment Implementation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `sf/src_sh/` so `zig1_5` depends only on `zig1` — externs migrate to `@cInclude`, `__bootstrap_*` eliminated, zig0 left out of service. Logic unchanged; only dependencies change.

**Architecture:** Create a 40-module self-hosted tree (`sf/src_sh/`) as a copy of `sf/src/` with deps-only modifications: `pal.zig` gains `@cInclude` lines, `extern_c.zig` drops `__bootstrap_print*`, a new `sh_runtime.h` holds the renamed 9 cast helpers, and the build script links self-emitted `.o` + renamed runtime + `zig_pal.c` + `c_exit.c`. No zig0, no `__bootstrap_*`.

**Tech Stack:** Zig (sf/src), C89 (emitted code), gcc -m32, bash.

## Global Constraints

- Compiler under test `/tmp/fx_subfolder/zig1`; rebuild = `bash sf/scripts/build_release.sh` (gate `=== [release] Done ===`). Rebuild WIPES `/tmp/fx_subfolder/lib` — reinstall canonical std after each rebuild: `cp sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig} /tmp/fx_subfolder/lib/`.
- Byte-identity gates (QUICK_REF.md): gol `4afb203fdde7a880ec6e7aed32543691`, lisp `5f886646b164a70c52bf042eb54bda78` (repo-root CWD), json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. The sh-tree is a NEW directory; canonical `sf/src/` emissions must remain byte-identical.
- Compile recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 X.zig`; multi-module `gcc -m32 -std=c89 -c` INSIDE output dir with absolute `-I /workspace/znineeight/sf/src/include`; link `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c`.
- Z98 dialect: no anytype/@Type; `@intCast` for int casts; `switch` requires `else`; no method syntax; no pointer captures.
- Editing discipline: `edit`/`fastedit` only; re-read region before each edit; edit bottom-to-top; never `end_line=start_line-1`; insert via replacing an anchor line.
- Markers extract with `grep -a`, never `strings`.
- Ledger: append one line per completed task to `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory` entry per completed task (agent `r2r1-session`; types discovery/decision/intent/problem/pattern).
- Reports written to `.superpowers/sdd/task-<N>-report.md` (gitignored); return only status + one-line gate summary.
- `@cInclude` semantics: emits `#include "X"` (quoted) or `#include <X>` (if starts with `<`) in the module header, per-module (c89_emit.zig:2204-2219). It does NOT supply Zig-side signatures. Extern fns are never forward-declared by the emitter (c89_emit.zig:2226, :2373 skip `is_extern==1`).
- The fidelity-gap fix (enum-switch drop) is Plan 1 — this plan may depend on it being merged, but does not itself fix it.

---

### Task 1: F-CINCLUDE — migrate externs to `@cInclude` in `sf/src_sh/pal.zig` + `extern_c.zig`

**Files:**
- Create: `sf/src_sh/` tree skeleton (copy of `sf/src/` 40 build modules)
- Create: `sf/src_sh/include/sh_runtime.h`
- Modify: `sf/src_sh/pal.zig`, `sf/src_sh/extern_c.zig`
- Commit: `feat: sf/src_sh externs migrated to @cInclude`

**Interfaces:**
- Consumes: Task 7 design (`/workspace/znineeight/.superpowers/sdd/task-7-report.md`), verified extern surface.
- Produces: self-hosted tree with `@cInclude` migration + renamed runtime headers.

- [ ] **Step 1: Copy the 40-module tree**

Copy `sf/src/*.zig` (the 40 build modules per `/tmp/zig1_5/gen/*.c` basenames) into `sf/src_sh/`. Do NOT copy non-build files (e.g. `util/diagnostic_sort.zig`, `main_exp.zig`, `test_a.zig`, `extern_c_z98.zig` — the dead exemplar). Create `sf/src_sh/include/`.

- [ ] **Step 2: Write `sf/src_sh/include/sh_runtime.h`**

The 9 cast helpers renamed `z_<a>_from_<b>` with EXACT bounds-checked bodies (panic on overflow), matching the three-source-verified implementation (`if (x > LIMIT) std_panic(...)`), plus `std_panic` prototype. Copy the bounds-check logic verbatim from `sf/src/include/zig_runtime.c:182-185` (the hand-written static helpers).

- [ ] **Step 3: Modify `sf/src_sh/pal.zig`**

Add at top:
```zig
const _ = @cInclude("<stdio.h>");
const _ = @cInclude("<unistd.h>");
const _ = @cInclude("sh_runtime.h");
```
Keep the existing `extern "c" fn` declarations (fopen/fread/fclose/fseek/ftell/c_exit/pal_file_open/pal_file_write/pal_file_close/pal_get_default_lib_path) — `@cInclude` supplies C prototypes, Zig signatures are retained (Decision 1). The `<unistd.h>` include lives HERE because `write` is called only in pal.zig (Decision 2).

- [ ] **Step 4: Modify `sf/src_sh/extern_c.zig`**

Drop `__bootstrap_print`/`__bootstrap_print_int` extern declarations. Keep `write`. (The 40-module build never calls the dropped helpers.)

- [ ] **Step 5: Verify + commit**

Verify: `grep -a -c "write(" /tmp/.../pal_*.c` (include reaches the call site); `grep -a "__bootstrap_" sf/src_sh/` is empty (or only documented); the 4 MD5 gates still byte-identical (canonical sf/src untouched). Commit `feat: sf/src_sh externs migrated to @cInclude`. Report + ledger + memory.

---

### Task 2: F-RUNTIME — renamed minimal runtime

**Files:**
- Create: `sf/src_sh/include/zig_runtime.c` (renamed helpers)
- Modify: `sf/src_sh/include/zig_runtime.h` (rename references)
- Commit: `feat: sf/src_sh minimal non-bootstrap runtime (z_*_from_*, no __bootstrap_*)`

**Interfaces:**
- Consumes: Task 1 sh-tree.
- Produces: linkable runtime with zero `__bootstrap_*`.

- [ ] **Step 1: Rename helpers**

Copy `sf/src/include/zig_runtime.c` to `sf/src_sh/include/zig_runtime.c`; rename the 9 `__bootstrap_<a>_from_<b>` → `z_<a>_from_<b>` and `__bootstrap_panic` → `std_panic` (or keep std_panic if already present). Keep all bounds-check bodies byte-identical.

- [ ] **Step 2: Rename in header**

`sf/src_sh/include/zig_runtime.h`: update the 9 helper prototypes + `std_panic` decl to the renamed symbols.

- [ ] **Step 3: Verify zero `__bootstrap_*`**

`grep -a -c "__bootstrap_" sf/src_sh/include/zig_runtime.c sf/src_sh/include/zig_runtime.h` == 0. Compile `gcc -m32 -std=c89 -c sf/src_sh/include/zig_runtime.c` rc=0. Commit `feat: sf/src_sh minimal non-bootstrap runtime (z_*_from_*, no __bootstrap_*)`. Report + ledger + memory.

---

### Task 3: F-BUILD — `build_zig1_5.sh` targets `sf/src_sh/`

**Files:**
- Modify: `scripts/self_compile/build_zig1_5.sh`
- Commit: `build: zig1_5 from sf/src_sh (self-contained, no zig0)`

**Interfaces:**
- Consumes: Tasks 1-2 sh-tree.
- Produces: `zig1_5` built from `sf/src_sh/` linking only self-emitted `.o` + renamed runtime + `zig_pal.c` + `c_exit.c`.

- [ ] **Step 1: Point the compile at `sf/src_sh/main.zig`**

Change the dump source from `sf/src/main.zig` to `sf/src_sh/main.zig` (and the include path to `-I sf/src_sh/include`).

- [ ] **Step 2: Update link line**

Link: self-emitted `*.o` + `sf/src_sh/include/zig_runtime.c` + `sf/src/include/zig_pal.c` + `sf/src/c_exit.c`. No zig0 step, no `__bootstrap_*` object.

- [ ] **Step 3: Build + verify**

`bash scripts/self_compile/build_zig1_5.sh` → both `zig1_5_asan` + `zig1_5_clean` link rc=0. `nm /tmp/zig1_5/zig1_5_clean | grep -c "__bootstrap_"` == 0. Run `zig1_5_clean --dump-c89` on a real fixture (e.g. `examples/z98/fibonacci/main.zig`) — runs (may show the documented fidelity-gap parse behavior, which is Plan 1's scope). Commit `build: zig1_5 from sf/src_sh (self-contained, no zig0)`. Report + ledger + memory.

---

### Task 4: GATE-FINAL — sweep + reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Commit: `docs: sf/src_sh self-containment GATE + reconciliation`

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: reconciled docs + verified gate.

- [ ] **Step 1: Full sweep**

4 MD5 gates byte-identical (canonical sf/src untouched); matrix 21/21; corpus re-count.

- [ ] **Step 2: Self-containment verification**

`nm` on `zig1_5_clean`: zero `__bootstrap_*`, zero zig0-produced symbols; links only self-emitted `.o` + the 3 runtime files.

- [ ] **Step 3: Docs reconciliation**

EXPECTED_FAIL.md bump + closeout (sh-tree, extern migration, milestone); QUICK_REF.md baseline paragraph.

- [ ] **Step 4: Commit + ledger + memory**

Commit `docs: sf/src_sh self-containment GATE + reconciliation`. Ledger + memory entries.

---

## Self-Review (controller, before execution)

- **Spec coverage:** Task 1 (@cInclude migration) + Task 2 (renamed runtime) + Task 3 (build) + Task 4 (gate) cover the design's 6 decisions.
- **Placeholder scan:** all steps carry exact commands/expected output; no TBD.
- **Type consistency:** `z_*_from_*` rename consistent across runtime.c/h; `sf/src_sh/include/` path stable; `build_zig1_5.sh` single source of truth.
- **Fork policy:** if any canonical `sf/src/` module must change (not just sh-tree copies), STOP + escalate — the constraint is deps-only, canonical source unchanged.
