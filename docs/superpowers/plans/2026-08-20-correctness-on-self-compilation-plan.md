# Self-Compilation Correctness (Determinism + Memory) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove zig1 self-compiles deterministically into `zig1_5`, that both emit matching C and runtime-identical programs for all 21 examples, and measure compiler memory (in-use arena + RSS) against the 16 MB target — read-only, STOP on any finding.

**Architecture:** Sequential verification pipeline — T1 baseline recon (self-compile smoke) → T2 produce `zig1_5` (asan + clean) → T3 determinism (byte → normalized) → T4 runtime match → T5 memory (4 runs vs 16 MB) → T6 report + commit. No `sf/src` edits anywhere; scripts + report only.

**Tech Stack:** bash + gcc -m32 + `/usr/bin/time -v`; Z98 dialect; zig0 bootstrap / zig1 self-hosted.

## Global Constraints

- **Read-only:** zero `sf/src` edits. Scripts under `scripts/`; findings report under `docs/`. STOP on any non-determinism or memory overshoot — do NOT auto-fix.
- **Determinism compares zig1 vs zig1_5 ONLY** — never zig0 (legacy single-file format, byte-level incompatible with the 40-file multi-module format).
- **Tiered determinism:** byte (`md5sum`/`diff -r`) → normalized (temp names `zT_N`, hashes `z[FT]_<8hex>_`, block labels `z_bb_N`, comments, `#include` lines) → runtime (stdout + exit code).
- **Memory:** `--track-memory` output only prints with `--markers`. In-use = `perm+mod+scr` (+`type_db`); `pool` = reserved/carved. Target = 16 MB (`RELEASE_MAX_MEM`); `--max-mem` is currently unwired (record, don't fix). RSS via `/usr/bin/time -v`.
- **zig1_5 built both ways:** `-fsanitize=address` (matches zig1) and clean.
- **Examples:** all 21 `examples/z98/*` for C-diff + memory; runtime comparison only for the 19 non-interactive (skip `mud_server`/`rogue_mud` runtime).
- **std install per binary:** `mkdir -p <exe_dir>/lib && cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig <exe_dir>/lib/`.
- Never touch/ls `sf/build/out_release/` (WEDGED); all runs `timeout 120`.
- lisp MD5 from repo root; json_parser from its own dir; interactive examples timeout-gated rc=124 with correct output = PASS.
- Branch `zig1_start` (HEAD `6dd11b24`, widthbits fix — self-compile prerequisite).
- Commit messages verbatim per task.

---

### Task T1: baseline recon + self-compile smoke

**Files:**
- Create: `scripts/self_compile/README.md` (pipeline index — one line per task + artifact paths)

**Consumes:** spec §Background. **Produces:** confirmed self-compile baseline + zig1 identity.

- [ ] **Step 1: Confirm zig1 self-compiles**

Run from repo root: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/sc sf/src/main.zig ; echo "rc=$?"`
Expected: `rc=0`, 40 `.c` files in `/tmp/sc`, zero `error[` non-9999 on stderr, zero PANIC.

- [ ] **Step 2: Record identity**

Run: `md5sum /tmp/fx_subfolder/zig1` and `git rev-parse HEAD` — record both in the README.
If `/tmp/fx_subfolder/zig1` is missing or stale (self-compile fails): rebuild via `bash sf/scripts/build_release.sh` (gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`), then reinstall std (`mkdir -p /tmp/fx_subfolder/lib && cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`), and re-run Step 1.

- [ ] **Step 3: Commit**

Commit: `docs: self-compilation correctness plan T1 baseline recon`

### Task T2: produce zig1_5 (self-compile)

**Files:**
- Create: `scripts/self_compile/build_zig1_5.sh`

**Consumes:** T1 (working zig1). **Produces:** `/tmp/zig1_5/zig1_5_asan` + `/tmp/zig1_5/zig1_5_clean`.

- [ ] **Step 1: Write build_zig1_5.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT=/tmp/zig1_5
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/lib"
cp "$ROOT"/sf/src/std.zig "$ROOT"/sf/src/std_io.zig "$ROOT"/sf/src/std_arena.zig "$ROOT"/sf/src/std_net.zig "$OUT/lib/"
cd "$ROOT"
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir "$OUT/gen" sf/src/main.zig
# canonical multi-module recipe (QUICK_REF §Multi-Module Build): compile inside DIR, link zig_runtime.c + zig_pal.c
cd "$OUT/gen"
gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration \
    -I "$ROOT/sf/src/include" -c *.c
gcc -m32 -O0 -fsanitize=address *.o "$ROOT/sf/src/include/zig_runtime.c" "$ROOT/sf/src/include/zig_pal.c" \
    -o "$OUT/zig1_5_asan"
gcc -m32 -O0 *.o "$ROOT/sf/src/include/zig_runtime.c" "$ROOT/sf/src/include/zig_pal.c" \
    -o "$OUT/zig1_5_clean"
echo "=== [zig1_5] Done: $OUT ==="
```

- [ ] **Step 2: Run it**

Run: `bash scripts/self_compile/build_zig1_5.sh`
Expected: rc=0, `zig1_5_asan` + `zig1_5_clean` produced. If gcc fails on a generated `.c`, that is a self-compile C-emission defect — STOP and report (do not patch).

- [ ] **Step 3: Smoke both binaries**

Run: `timeout 120 /tmp/zig1_5/zig1_5_clean --dump-c89 --output-dir /tmp/sc5 examples/z98/hello/main.zig ; echo "rc=$?"` and the same with `zig1_5_asan`.
Expected: rc=0, `.c` emitted. Both must run.

- [ ] **Step 4: Commit**

Commit: `verify: self-compile zig1 → zig1_5 (asan + clean)`

### Task T3: determinism — C output (byte → normalized)

**Files:**
- Create: `scripts/self_compile/determinism_c.sh`

**Consumes:** T2 (`zig1_5_clean`). **Produces:** per-target byte-tier verdict + normalized diff.

- [ ] **Step 1: Write determinism_c.sh**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
Z1=/tmp/fx_subfolder/zig1
Z15=/tmp/zig1_5/zig1_5_clean
TMP=/tmp/det_c
OUT="$ROOT/scripts/self_compile/det_c_report.txt"
: > "$OUT"
targets=( sf/src/main.zig examples/z98/days_in_month/main.zig examples/z98/fibonacci/main.zig examples/z98/func_ptr_return/main.zig examples/z98/game_of_life/main.zig examples/z98/heapsort/main.zig examples/z98/hello/main.zig examples/z98/json_parser/main.zig examples/z98/json_parser_workaround/main.zig examples/z98/lisp_interpreter/main.zig examples/z98/lisp_interpreter_adv/main.zig examples/z98/lisp_interpreter_curr/main.zig examples/z98/lzw/main.zig examples/z98/mandelbrot/main.zig examples/z98/mud_server/main.zig examples/z98/prime/main.zig examples/z98/quicksort/main.zig examples/z98/rogue_mud/main.zig examples/z98/sort_strings/main.zig examples/z98/tco_defer/main.zig examples/z98/tco_factorial/main.zig examples/z98/tco_return_try/main.zig )
for t in "${targets[@]}"; do
  a="$TMP/a"; b="$TMP/b"
  rm -rf "$a" "$b"; mkdir -p "$a" "$b"
  timeout 120 "$Z1"  --dump-c89 --output-dir "$a" "$ROOT/$t" >/dev/null 2>&1
  timeout 120 "$Z15" --dump-c89 --output-dir "$b" "$ROOT/$t" >/dev/null 2>&1
  a_md5=$(cd "$a" && md5sum *.c | md5sum); b_md5=$(cd "$b" && md5sum *.c | md5sum)
  if [ "$a_md5" = "$b_md5" ]; then echo "BYTE-IDENTICAL  $t" >> "$OUT";
  else
    # normalized diff: strip comments, #include, temp names, hashes, block labels
    norm() { sed 's|/\*.*\*/||g' "$1" | grep -v '^#include' | sed 's/zT_[0-9]*/__tmp/g; s/z[FT]_[a-f0-9]\{8\}_/z_<hash>_/g; s/z_bb_[0-9]*/__bb/g'; }
    na=$(for f in "$a"/*.c; do norm "$f"; done | md5sum); nb=$(for f in "$b"/*.c; do norm "$f"; done | md5sum)
    if [ "$na" = "$nb" ]; then echo "NORM-IDENTICAL   $t" >> "$OUT"; else echo "DIFFERENT        $t" >> "$OUT"; fi
  fi
done
cat "$OUT"
```

- [ ] **Step 2: Run it**

Run: `bash scripts/self_compile/determinism_c.sh`
Expected: `det_c_report.txt` with one line per target. If `sf/src/main.zig` is NOT `BYTE-IDENTICAL`, that is a **major finding** — STOP and report (do not investigate/fix here).

- [ ] **Step 3: Record verdict + commit**

Append the tier distribution summary to the report header. Commit: `verify: determinism C-output comparison zig1 vs zig1_5`

### Task T4: runtime behavior match (19 non-interactive)

**Files:**
- Create: `scripts/self_compile/runtime_match.sh`

**Consumes:** T2 (`zig1_5_clean`). **Produces:** per-example runtime verdict.

- [ ] **Step 1: Write runtime_match.sh**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
Z1=/tmp/fx_subfolder/zig1
Z15=/tmp/zig1_5/zig1_5_clean
TMP=/tmp/rt_match
OUT="$ROOT/scripts/self_compile/runtime_report.txt"
: > "$OUT"
# 19 non-interactive (skip mud_server, rogue_mud)
examples=( days_in_month fibonacci func_ptr_return game_of_life heapsort hello json_parser json_parser_workaround lisp_interpreter lisp_interpreter_adv lisp_interpreter_curr lzw mandelbrot prime quicksort sort_strings tco_defer tco_factorial tco_return_try )
for ex in "${examples[@]}"; do
  w="$TMP/$ex"; rm -rf "$w"; mkdir -p "$w/1" "$w/15"
  d="$ROOT/examples/z98/$ex"
  timeout 120 "$Z1"  --dump-c89 --output-dir "$w/1"  "$d/main.zig" >/dev/null 2>&1
  timeout 120 "$Z15" --dump-c89 --output-dir "$w/15" "$d/main.zig" >/dev/null 2>&1
  # canonical multi-module recipe (QUICK_REF §Multi-Module Build)
  for side in 1 15; do
    ( cd "$w/$side" \
      && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I "$ROOT/sf/src/include" -c *.c \
      && gcc -m32 *.o "$ROOT/sf/src/include/zig_runtime.c" "$ROOT/sf/src/include/zig_pal.c" -o app \
      && ( cd "$d" && timeout 60 "$w/$side/app" > "$w/$side/out.txt" 2>&1 ) \
      ; echo "rc=$?" > "$w/$side/rc.txt" )
  done
  if [ -f "$w/1/rc.txt" ] && [ -f "$w/15/rc.txt" ] && diff -q "$w/1/rc.txt" "$w/15/rc.txt" >/dev/null && diff -q "$w/1/out.txt" "$w/15/out.txt" >/dev/null; then
    echo "MATCH  $ex" >> "$OUT"; else echo "MISMATCH  $ex" >> "$OUT"; fi
done
cat "$OUT"
```

Note: the binary runs from the example's own dir (`cd "$d"`) so file-relative examples (json_parser reads `test.json`) resolve identically for both sides.

- [ ] **Step 2: Run it**

Run: `bash scripts/self_compile/runtime_match.sh`
Expected: all 19 `MATCH`. Any `MISMATCH` is a finding — STOP and report (do not fix).

- [ ] **Step 3: Commit**

Commit: `verify: runtime behavior match zig1 vs zig1_5 (19 examples)`

### Task T5: memory measurement (4 runs vs 16 MB)

**Files:**
- Create: `scripts/self_compile/memory_measure.sh`

**Consumes:** T1 (zig0), T2 (zig1_5 both builds). **Produces:** memory table.

- [ ] **Step 1: Write memory_measure.sh**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
Z0="$ROOT/sf/build/zig0"
Z1=/tmp/fx_subfolder/zig1
Z15_ASAN=/tmp/zig1_5/zig1_5_asan
Z15_CLEAN=/tmp/zig1_5/zig1_5_clean
TMP=/tmp/mem_measure
OUT="$ROOT/scripts/self_compile/memory_report.txt"
: > "$OUT"
cd "$ROOT"
mem_rss() { /usr/bin/time -v "$@" 2>&1 >/dev/null | grep -o 'Maximum resident set size.*: [0-9]*'; }
echo "== zig0 -> zig1 (RSS only) ==" >> "$OUT"
mem_rss "$Z0" --header-priority-include -o "$TMP/z0.c" sf/src/main.zig >> "$OUT"
echo "== zig1 -> zig1_5 (internal + RSS) ==" >> "$OUT"
timeout 120 "$Z1" --markers --track-memory --dump-c89 --output-dir "$TMP/z1" sf/src/main.zig 2>&1 | grep -a 'track-memory:' >> "$OUT"
mem_rss "$Z1" --dump-c89 --output-dir "$TMP/z1rss" sf/src/main.zig >> "$OUT"
echo "== zig1 -> examples (internal + RSS) ==" >> "$OUT"
for ex in days_in_month fibonacci game_of_life heapsort hello lisp_interpreter_curr lzw mandelbrot mud_server prime quicksort rogue_mud sort_strings tco_factorial; do
  timeout 120 "$Z1" --markers --track-memory --dump-c89 --output-dir "$TMP/e1" "$ROOT/examples/z98/$ex/main.zig" 2>&1 | grep -a 'track-memory:' | sed "s/^/$ex: /" >> "$OUT"
done
echo "== zig1_5 -> examples (internal + RSS, asan + clean) ==" >> "$OUT"
for ex in days_in_month fibonacci game_of_life heapsort hello lisp_interpreter_curr lzw mandelbrot mud_server prime quicksort rogue_mud sort_strings tco_factorial; do
  timeout 120 "$Z15_ASAN"  --markers --track-memory --dump-c89 --output-dir "$TMP/e2" "$ROOT/examples/z98/$ex/main.zig" 2>&1 | grep -a 'track-memory:' | sed "s/^/$ex(asan): /" >> "$OUT"
  timeout 120 "$Z15_CLEAN" --markers --track-memory --dump-c89 --output-dir "$TMP/e3" "$ROOT/examples/z98/$ex/main.zig" 2>&1 | grep -a 'track-memory:' | sed "s/^/$ex(clean): /" >> "$OUT"
done
cat "$OUT"
```

- [ ] **Step 2: Run it**

Run: `bash scripts/self_compile/memory_measure.sh`
Expected: per-run `track-memory:` line (in-use `perm`/`mod`/`scr`/`type_db` + reserved `pool`) and RSS. Compute in-use total and 16 MB margin for run 2 (zig1 → zig1_5, the key measurement). If in-use > 16 MB, STOP and report.

- [ ] **Step 3: Commit**

Commit: `verify: compiler memory measurement (4 runs) vs 16 MB target`

### Task T6: findings report + reconciliation

**Files:**
- Create: `docs/self-compilation-correctness-report.md`

**Consumes:** T1-T5 reports. **Produces:** consolidated findings + operator decision point.

- [ ] **Step 1: Write the report**

Sections: (1) self-compile verdict (zig1_5 built + runs); (2) determinism table (byte/normalized per target, with `sf/src/main.zig` headline); (3) runtime table (19 examples); (4) memory table (4 runs, in-use vs 16 MB margin, `pool` reserved, `--max-mem` unwired note); (5) findings list (any STOP-level items surfaced).

- [ ] **Step 2: Present findings to operator**

If any STOP-level finding exists (non-determinism, runtime mismatch, or >16 MB), STOP here and present — do not fix. If all clean, state "self-compile deterministic + within 16 MB budget" with the measured numbers.

- [ ] **Step 3: Commit**

Commit: `docs: self-compilation correctness report`
