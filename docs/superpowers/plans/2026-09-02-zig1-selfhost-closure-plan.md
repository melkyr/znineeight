# zig1 Self-Host Chain Determinism Closure + Advanced Examples — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the self-host chain converges to a byte-identical fixed point (zig1_5_clean == zig1_5_self == zig1_5_self_self, all passing the full gate battery), measure compiler performance (including the `-s` RAM-vs-disk spill tradeoff), then write advanced `_upgraded` examples using idiomatic z98 syntax to demonstrate zig1's descendants supersede zig0.

**Architecture:** Phase T (5 small T tasks: re-self-compile hops + md5 fixed point, self-emission determinism, full gate battery, perf measurement, z98 determinism) → Phase U (4 final U tasks: U-INV construct inventory, three `_upgraded` example dirs, closure doc + docs GATE).

**Tech Stack:** Zig (sf/src), C89 (emitted), gcc -m32, bash, `/usr/bin/time -v`.

## Global Constraints

- **Determinism bar:** `zig1_5_clean`/`zig1_5_self`/`zig1_5_self_self` MUST be byte-identical (md5). The zig0→zig1_5 md5 is a first-attempt check — if it does NOT hold, correctness = emission identity + runtime identity + gates (never binary equality). Record both.
- **Gate baselines (MUST NOT move):** gol `302df36b` / lisp `3591bad9` / json `76056b97` / mud `4591fef0` (4 MD5, repo-root CWD `timeout 120 <C> --dump-c89 <entry> | md5sum`); golden 9/9 (`repro/mi_matrix/{emission_assoc_chain_xmod,fn_ptr_struct_field,emission_lower_crash_xmod}` + `examples/z98/{tco_return_try,tco_defer,tco_factorial,quicksort,func_ptr_return,hello}`); matrix 21/21; corpus 0-asymmetric; self-compile 42 `.c`/0 err/0 PANIC; reference 0-warning (1 pre-authorized fwrite `-Wbuiltin-declaration-mismatch` carve-out).
- **Compilers under test:** reference `/tmp/fx_subfolder/zig1` (zig0-built, md5 `0c09fe1a`), `/tmp/zig1_5/zig1_5_clean` (md5 `0c09fe1a`), and the plan's produced `/tmp/zig1_5_self/...` + `/tmp/zig1_5_self_self/...`.
- **Build recipes:** reference rebuild `timeout 900 bash sf/scripts/build_release.sh` (WIPES `/tmp/fx_subfolder` → reinstall `cp sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig} /tmp/fx_subfolder/lib/`). Self-compile `timeout 900 bash scripts/self_compile/build_zig1_5.sh` (gate `=== [zig1_5] Done ===`). `--output-dir` MUST pre-exist.
- **Z98 dialect** for any `.zig` change (no anytype/@Type; `@intCast`; `switch` needs `else`; no method syntax; no pointer captures). U examples may use richer-but-still-z98 idioms from U-INV.
- `edit`/`fastedit` only; re-read before edit; bottom-to-top; never touch `sf/build/out_release/`.
- Ledger `.superpowers/sdd/progress.md` (one line/task). Memory `mnemoria --path .opencode/memory add --agent selfhostclosure-session --type <t> --summary "<s>" "<body>"`.
- Report `.superpowers/sdd/task-CLOSURE-report.md` (gitignored; `task-1-report.md` TRACKED — never reuse).
- Pre-existing dirty never staged: `docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `mnemoria/*`, untracked `build/`.
- Design doc: `docs/superpowers/specs/2026-09-02-zig1-selfhost-closure-design.md`.

---

### Task T-RE-SELF: two more self-host hops + md5 fixed point

**Files:**
- Create: `scripts/self_compile/build_next_gen.sh` (parametrized next-generation builder)
- Test: the produced binaries' md5 + a smoke `hello` compile.

**Interfaces:**
- Consumes: `scripts/self_compile/build_zig1_5.sh` (the canonical recipe); `/tmp/zig1_5/zig1_5_clean`.
- Produces: `/tmp/zig1_5_self/zig1_5_self_clean` + `/tmp/zig1_5_self_self/zig1_5_self_self_clean` + the md5 equality record.

- [ ] **Step 1: Write the parametrized builder**

`scripts/self_compile/build_next_gen.sh` — same recipe as `build_zig1_5.sh` but takes two args: the compiler binary and the output dir:

```bash
#!/usr/bin/env bash
set -euo pipefail
# usage: build_next_gen.sh <compiler> <out_dir>
COMPILER="$1"; OUT="$2"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/lib"
cp "$ROOT"/sf/src/std.zig "$ROOT"/sf/src/std_io.zig "$ROOT"/sf/src/std_arena.zig "$ROOT"/sf/src/std_net.zig "$OUT/lib/"
cd "$ROOT"
timeout 120 "$COMPILER" --dump-c89 --output-dir "$OUT/gen" sf/src/main.zig
cd "$OUT/gen"
gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration \
    -I "$ROOT/sf/src/include" -c *.c
gcc -m32 -O0 *.o "$ROOT/sf/src/include/zig_runtime.c" "$ROOT/sf/src/include/zig_pal.c" "$ROOT/sf/src/c_exit.c" \
    -o "$OUT/zig1_5_clean"
echo "=== [next-gen] Done: $OUT ==="
```

- [ ] **Step 2: Produce the two hops**

Run: `timeout 900 bash scripts/self_compile/build_next_gen.sh /tmp/zig1_5/zig1_5_clean /tmp/zig1_5_self`
Expected: `=== [next-gen] Done: /tmp/zig1_5_self ===`.
Run: `timeout 900 bash scripts/self_compile/build_next_gen.sh /tmp/zig1_5_self/zig1_5_clean /tmp/zig1_5_self_self`
Expected: `=== [next-gen] Done: /tmp/zig1_5_self_self ===`.

- [ ] **Step 3: Record the md5 fixed point**

```bash
md5sum /tmp/fx_subfolder/zig1 /tmp/zig1_5/zig1_5_clean /tmp/zig1_5_self/zig1_5_clean /tmp/zig1_5_self_self/zig1_5_clean
```
Record all four. The three self-host binaries (`/tmp/zig1_5/zig1_5_clean`, `/tmp/zig1_5_self/zig1_5_clean`, `/tmp/zig1_5_self_self/zig1_5_clean`) MUST be byte-identical (== `0c09fe1a`). Note whether zig0-built `zig1` matches (first-attempt check).

- [ ] **Step 4: Smoke-test each new hop**

For each of the two new binaries: `mkdir -p /tmp/smoke && timeout 120 <bin> --dump-c89 --output-dir /tmp/smoke examples/z98/hello/main.zig`, then gcc-compile + run → `Hello, world!` rc=0.

- [ ] **Step 5: Report + commit the script**

Append `## T-RE-SELF` to `.superpowers/sdd/task-CLOSURE-report.md` (md5 table + smoke results). Commit the new script:
```bash
git add scripts/self_compile/build_next_gen.sh
git commit -m "test: parametrized self-host chain builder (next-generation hops)"
```

---

### Task T-EMIT-DET: self-emission byte-identity

**Files:** none modified (measurement only; report-only).

**Interfaces:**
- Consumes: T-RE-SELF's four binaries.
- Produces: the emission-determinism record (each compiler's `--dump-c89 sf/src/main.zig` output, md5-compared).

- [ ] **Step 1: Emit sf/src with each self-host compiler**

For each of `/tmp/zig1_5/zig1_5_clean`, `/tmp/zig1_5_self/zig1_5_clean`, `/tmp/zig1_5_self_self/zig1_5_clean`:
```bash
mkdir -p /tmp/emitdet_<tag>
timeout 120 <bin> --dump-c89 --output-dir /tmp/emitdet_<tag> sf/src/main.zig
```

- [ ] **Step 2: Compare emissions byte-for-byte**

```bash
diff -r /tmp/emitdet_z15 /tmp/emitdet_self && diff -r /tmp/emitdet_z15 /tmp/emitdet_selfself
```
Record: are all 42 `.c` + headers byte-identical across the three self-host compilers? (Expected: YES — the md5 fixed point from T-RE-SELF implies it.) Also emit with zig0-built `zig1` and note the diff (first-attempt).

- [ ] **Step 3: Report**

Append `## T-EMIT-DET` to `.superpowers/sdd/task-CLOSURE-report.md` (per-compiler emission md5 list + the diff result). No commit (read-only).

---

### Task T-GATE: full battery on the new hops

**Files:** none modified (verification only).

**Interfaces:**
- Consumes: T-RE-SELF's `zig1_5_self` + `zig1_5_self_self`.
- Produces: the full gate battery result for each new hop.

- [ ] **Step 1: 4 MD5 gates**

For each new hop binary `<bin>`, repo-root CWD: `timeout 120 <bin> --dump-c89 examples/z98/game_of_life/main.zig | md5sum` (and `lisp_interpreter_curr`, `json_parser`, `mud_server`). Expected: gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `4591fef0` — byte-identical for both hops.

- [ ] **Step 2: Golden 9/9 + matrix 21/21 + corpus**

Run the golden-9 fixture set (dump/gcc/link/run, stdout matches the reference golden) and matrix 21/21 with each new hop. Run the mi_matrix corpus sweep (0-asymmetric vs the reference zig1). Record results.

- [ ] **Step 3: Self-compile round-trip**

Run `timeout 900 bash scripts/self_compile/build_next_gen.sh <hop> /tmp/zig1_5_gate` and confirm 42 `.c` / 0 `error[` / 0 PANIC, plus the produced binary md5 == the hop's md5 (closing the loop).

- [ ] **Step 4: Report + ledger**

Append `## T-GATE` to `.superpowers/sdd/task-CLOSURE-report.md` (full result table). No source commit; controller appends the ledger line.

---

### Task T-PERF: wall + RSS + pool across compilers × `-s` levels

**Files:** none modified (measurement only).

**Interfaces:**
- Consumes: the four binaries; the `-s`/`-mm` CLI (F-S/F-MM).
- Produces: the perf report (wall/RSS/pool per compiler × `-s` level × workload).

- [ ] **Step 1: Define the workloads**

Self-compile: `sf/src/main.zig`. z98 ladder: `hello`, `game_of_life`, `lisp_interpreter_curr`, `json_parser`, `rogue_mud` (5 examples).

- [ ] **Step 2: Measure**

For each compiler (zig1, zig1_5_clean, zig1_5_self, zig1_5_self_self) × each `-s` level (0..5) × each workload:
- wall + RSS: `/usr/bin/time -v <bin> -s<N> --dump-c89 --output-dir /tmp/perf_out <entry> 2>&1 | grep -E 'Maximum resident|Elapsed|wall clock'`
- pool: `timeout 120 <bin> -s<N> --dump-c89 --markers --track-memory --output-dir /tmp/perf_out <entry> 2>&1 | grep track-memory`
- `-s2..-s5` on self-compile exceed `-mm64` → append `-mm128` and note the ICE-without-`-mm128` case.

- [ ] **Step 3: Tabulate the RAM-vs-disk tradeoff**

Produce tables: per workload, wall / RSS / pool= as a function of `-s` level and compiler. State the tradeoff plainly (higher `-s` → higher RSS/pool, lower disk I/O) and whether it matches the operator's expectation (RAM mode holds source + spill → higher RSS by design).

- [ ] **Step 4: Report**

Append `## T-PERF` to `.superpowers/sdd/task-CLOSURE-report.md` (full tables). No commit.

---

### Task T-Z98-DET: all 21 z98 examples determinism

**Files:** none modified (verification only).

**Interfaces:**
- Consumes: the chain binaries.
- Produces: per-example emission + runtime equivalence record.

- [ ] **Step 1: Emit + run all 21 examples on zig1 and zig1_5_clean**

For each of the 21 `examples/z98/*/` dirs (entry = `main.zig` unless the dir's own `.zig` is the entry): `--dump-c89` with both compilers, diff the emissions, gcc-compile + run, compare stdout/rc. Record per-example: emission-identical? runtime-identical?

- [ ] **Step 2: Spot-check the two new hops**

For the two new hops, re-run the 3 emblematic examples (lisp/json/mud) and diff against zig1_5_clean's emission + runtime.

- [ ] **Step 3: Report**

Append `## T-Z98-DET` to `.superpowers/sdd/task-CLOSURE-report.md` (21-row table). No commit.

---

### Task U-INV: idiomatic-z98 construct inventory (read-only)

**Files:**
- (Read) `sf/src/semantic_analyzer.zig`, `sf/src/parser.zig` (the accepted-dialect source of truth), the mi_matrix fixture set, `examples/z98/*` (current quirk-avoiding idioms), the design doc's modern-construct note.

**Interfaces:**
- Consumes: the z98 dialect as zig1 accepts it (semantic analyzer + parser).
- Produces: the refactor list — idiomatic z98 constructs zig1 supports that the current examples avoid for zig0 compatibility — consumed by U-LISP/U-JSON/U-MUD.

- [ ] **Step 1: Catalog what zig1 accepts that zig0 rejects**

Read `sf/src/semantic_analyzer.zig` + `sf/src/parser.zig` and cross-reference the bootstrap-restore findings (zig0's type_checker.cpp gaps: computed-start slice of `[*]u8` field, certain var-decl inference shapes). Produce the list of constructs zig1 handles but zig0's front-end does NOT (e.g. computed-start multi-pointer slices, richer var-decl inference, `enum(u8)`-style tagged enums, value-pool getters, spill/`-s`/`-mm` as library surface, dense resolved-type tables).

- [ ] **Step 2: Map current quirk-avoiding idioms in the examples**

Grep `examples/z98/{lisp_interpreter_curr,json_parser,rogue_mud}` for the zig0-avoidance patterns (the forms that would break zig0 but are idiomatic z98). List, per example, the specific rewrite that becomes possible.

- [ ] **Step 3: STOP-present the refactor list**

Present the list to the operator (idiomatic construct → current quirk → rewrite). Append `## U-INV` to `.superpowers/sdd/task-CLOSURE-report.md`. No commit, no source edits.

---

### Task U-LISP / U-JSON / U-MUD: `_upgraded` examples

**Files:**
- Create: `examples/z98/lisp_interpreter_upgraded/`, `examples/z98/json_parser_upgraded/`, `examples/z98/rogue_mud_upgraded/` (sibling dirs; copy the current example as base, then apply U-INV refactors).

**Interfaces:**
- Consumes: U-INV's refactor list (the exact idiomatic constructs to use).
- Produces: three new dirs whose `main.zig` (and modules) compile + run identically on zig1, zig1_5_clean, zig1_5_self, zig1_5_self_self.

- [ ] **Step 1: Copy base + apply refactors**

`cp -r examples/z98/lisp_interpreter_curr examples/z98/lisp_interpreter_upgraded` (and json_parser → json_parser_upgraded, rogue_mud → rogue_mud_upgraded). Rewrite the source to use the U-INV idiomatic constructs (no quirk-avoiding forms). Keep behavior identical (same stdout/rc).

- [ ] **Step 2: Verify behavior is preserved**

For each upgraded example: `--dump-c89` with the reference zig1, gcc-compile + run → stdout/rc MUST match the original example's (behavior-preserving refactor).

- [ ] **Step 3: Verify on the self-host chain**

Emit + run each upgraded example with `zig1_5_clean`, `zig1_5_self`, `zig1_5_self_self` — all four compilers produce identical emission + identical runtime.

- [ ] **Step 4: Commit (per example)**

```bash
git add examples/z98/lisp_interpreter_upgraded
git commit -m "feat: lisp_interpreter_upgraded — idiomatic z98 (zig1-supersedes-zig0 demo)"
```
(separate commit per example: `json_parser_upgraded`, `rogue_mud_upgraded`.)

---

### Task U-CLOSE: closure doc + docs GATE

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (or the closure summary location), `docs/sf/QUICK_REF.md`
- Create: none (report is gitignored).

**Interfaces:**
- Consumes: T-RE-SELF..T-Z98-DET determinism + perf evidence, U-LISP/U-JSON/U-MUD.
- Produces: the committed closure record + migration-readiness note.

- [ ] **Step 1: Write the closure summary**

Document: the md5 fixed point (`zig1_5_clean == zig1_5_self == zig1_5_self_self == 0c09fe1a`; zig0-built zig1 first-attempt result), the full-battery results, the perf tradeoff table, and the three `_upgraded` examples.

- [ ] **Step 2: Update docs**

Add the closure section to `docs/sf/QUICK_REF.md` (newest-first) + reconcile the expected-fail/gate record. Note the migration-readiness statement (the bootstrap cycle is closable via the future cInclude-zig1-only migration).

- [ ] **Step 3: Commit**

```bash
git add docs/sf/QUICK_REF.md repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "docs: self-host closure — deterministic fixed point + advanced examples"
```

- [ ] **Step 4: Ledger + STOP**

Controller appends the final ledger line + stores memory; STOP-present the closure to the operator.
