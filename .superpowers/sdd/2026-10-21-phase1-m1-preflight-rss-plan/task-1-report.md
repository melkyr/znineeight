# Phase 1 M1 Task 1 — Compiler RSS/peak pre-flight measurements

Status: COMPLETE (fix round 1)

Host: Linux, repo root `/workspace/znineeight`, branch `zig1_improvements`,
HEAD `6cc1485fd5f7ab35daa6422d2e23c3b3417081a2` (seed v111, archive
`5dc851a1a96c0776ef36e8e5b29774b7`, fixed point
`21c957730d268f1e7883176fa5413b65`).

## Step 1 — fixed-point seed build

Command (from repo root):

```bash
FIXED_POINT_MD5=21c957730d268f1e7883176fa5413b65 bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m1_build
```

Observed output (gcc warnings omitted; seed-script lines shown):

```text
[seed] hop1 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] hop2 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] two-hop closure OK: hop1 == hop2 == 21c957730d268f1e7883176fa5413b65
[seed] recorded fixed point OK: 21c957730d268f1e7883176fa5413b65
=== [seed] Done: /tmp/m1_build ===
```

Verification:

```bash
$ md5sum /tmp/m1_build/zig1_5_clean
21c957730d268f1e7883176fa5413b65  /tmp/m1_build/zig1_5_clean
```

Result: PASS — fixed-point binary matches `21c957730d268f1e7883176fa5413b65`.

## Step 2 — measurements

All runs used GNU time via `/usr/bin/time -v -o <time-file>` and were started
from the repo root unless noted. Each invocation used a fresh output directory.
The three required fields are `Maximum resident set size (kbytes)`, `Elapsed
(wall clock) time`, and `Exit status`.

### (a) two-hop seed build

Literal whole-build command (same as Step 1, wrapped in `/usr/bin/time -v`):

```bash
FIXED_POINT_MD5=21c957730d268f1e7883176fa5413b65 \
  /usr/bin/time -v -o /tmp/m1_a.time \
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m1_build
```

Observed (GNU time):

```text
Command being timed: "bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m1_build"
User time (seconds): 23.63
System time (seconds): 1.41
Percent of CPU this job got: 99%
Elapsed (wall clock) time (h:mm:ss or m:ss): 0:25.12
Maximum resident set size (kbytes): 164176
Exit status: 0
```

Observed (script result):

```text
[seed] hop1 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] hop2 binary md5: 21c957730d268f1e7883176fa5413b65
[seed] two-hop closure OK: hop1 == hop2 == 21c957730d268f1e7883176fa5413b65
[seed] recorded fixed point OK: 21c957730d268f1e7883176fa5413b65
=== [seed] Done: /tmp/m1_build ===
```

This whole-script process-tree maximum (**164176 KiB**) is not a
compiler-process RSS figure. The script also runs two `gcc -m32` compile/link
passes over the emitted C; a separate gcc-only probe of the same 50 emitted C
files (below) peaks at **172260 KiB**, confirming gcc dominates the build. The
compiler itself peaks at **20792 KiB** without tracking (`--dump-c89`) and
**20804 KiB** with `--markers --track-memory`. The 164176 vs 172260 spread is
run-to-run gcc variation, not a compiler figure.

Fixed-point binary `/tmp/m1_build/zig1_5_clean` self-emission:

```bash
rm -rf /tmp/m1_emit && mkdir -p /tmp/m1_emit
/usr/bin/time -v -o /tmp/m1_emit.time \
  /tmp/m1_build/zig1_5_clean -ffast --dump-c89 \
  --output-dir /tmp/m1_emit sf/src/main.zig > /tmp/m1_emit.out 2>&1
```

Observed:

```text
Command being timed: "/tmp/m1_build/zig1_5_clean -ffast --dump-c89 --output-dir /tmp/m1_emit sf/src/main.zig"
User time (seconds): 5.49
System time (seconds): 0.11
Percent of CPU this job got: 99%
Elapsed (wall clock) time (h:mm:ss or m:ss): 0:05.66
Maximum resident set size (kbytes): 20792
Exit status: 0
```

Emitted C files: 50. `md5sum /tmp/m1_build/zig1_5_clean` =
`21c957730d268f1e7883176fa5413b65`.

Fixed-point closure binary `/tmp/m1_build/hop2/zig1_hop2` self-emission:

```bash
rm -rf /tmp/m1_emit_hop2 && mkdir -p /tmp/m1_emit_hop2
/usr/bin/time -v -o /tmp/m1_a_hop2.time \
  /tmp/m1_build/hop2/zig1_hop2 -ffast --dump-c89 \
  --output-dir /tmp/m1_emit_hop2 sf/src/main.zig > /tmp/m1_a_hop2.out 2>&1
```

Observed:

```text
Command being timed: "/tmp/m1_build/hop2/zig1_hop2 -ffast --dump-c89 --output-dir /tmp/m1_emit_hop2 sf/src/main.zig"
User time (seconds): 5.43
System time (seconds): 0.10
Percent of CPU this job got: 99%
Elapsed (wall clock) time (h:mm:ss or m:ss): 0:05.58
Maximum resident set size (kbytes): 20536
Exit status: 0
```

Emitted C files: 50. `md5sum /tmp/m1_build/hop2/zig1_hop2` =
`21c957730d268f1e7883176fa5413b65` (same fixed point as
`/tmp/m1_build/zig1_5_clean`).

Arena tracking, fixed-point binary (`--markers --track-memory`; this is the
harness that exposes arena, see `sf/src/main.zig:443-449`):

```bash
rm -rf /tmp/m1_self_o && mkdir -p /tmp/m1_self_o
/usr/bin/time -v -o /tmp/m1_a_arena_o.time \
  /tmp/m1_build/zig1_5_clean --markers --track-memory -ffast \
  -o /tmp/m1_self_o sf/src/main.zig > /tmp/m1_a_arena_o.out 2>&1
```

Observed:

```text
track-memory: perm=1023K mod=1023K scr=875K pool=18871K type_db=243K total=2921K
Elapsed (wall clock) time (h:mm:ss or m:ss): 0:06.27
Maximum resident set size (kbytes): 20964
Exit status: 0
```

Same binary, `--dump-c89` mode (the table's no-tracking emit workload):

```bash
rm -rf /tmp/m1_emit_arena && mkdir -p /tmp/m1_emit_arena
/usr/bin/time -v -o /tmp/m1_a_arena_dump.time \
  /tmp/m1_build/zig1_5_clean --markers --track-memory -ffast --dump-c89 \
  --output-dir /tmp/m1_emit_arena sf/src/main.zig > /tmp/m1_a_arena_dump.out 2>&1
```

Observed:

```text
track-memory: perm=1023K mod=1023K scr=875K pool=18871K type_db=243K total=2921K
Elapsed (wall clock) time (h:mm:ss or m:ss): 0:06.51
Maximum resident set size (kbytes): 20804
Exit status: 0
```

`total=2921K` is `perm + mod + scr` only; `pool=18871K` and `type_db=243K`
are separate (source: `sf/src/main.zig:443-449`). Pool is therefore not part
of the reported `total` and must be compared with RSS independently.

### (b) full stdlib gate

Command:

```bash
/usr/bin/time -v -o /tmp/m1_b.time \
  bash scripts/stdlib/verify_stdlib.sh /tmp/m1_build/zig1_5_clean > /tmp/m1_b.log 2>&1
```

Observed:

```text
Command being timed: "bash scripts/stdlib/verify_stdlib.sh /tmp/m1_build/zig1_5_clean"
User time (seconds): 110.92
System time (seconds): 38.24
Percent of CPU this job got: 97%
Elapsed (wall clock) time (h:mm:ss or m:ss): 2:32.45
Maximum resident set size (kbytes): 364936
Exit status: 0
```

Observed result lines:

```text
run_fixtures: 312 PASS / 0 FAIL over 312 dirs
== std-lib crosscheck gate ==
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
STDLIB GATE OK
```

The **364936 KiB** figure is the whole gate's process-tree maximum. The gate
emits fixture C and compiles/builds it with gcc
(`scripts/stdlib/run_fixtures.sh`, `scripts/stdlib/run_crosscheck.sh`), so this
maximum is **not compiler RSS and is non-consumable in the compiler column**.

Compiler-only gate measurement (same gate, wrapper times each compiler call):

```bash
cat > /tmp/m1_zig1_wrap <<'EOF'
#!/bin/sh
exec /usr/bin/time -v -a -o /tmp/m1_gate_compiler.time /tmp/m1_build/zig1_5_clean "$@"
EOF
chmod +x /tmp/m1_zig1_wrap
rm -f /tmp/m1_gate_compiler.time
/usr/bin/time -v -o /tmp/m1_b_wrap.time \
  bash scripts/stdlib/verify_stdlib.sh /tmp/m1_zig1_wrap > /tmp/m1_b_wrap.log 2>&1
```

Observed (whole gate through the wrapper):

```text
Command being timed: "bash scripts/stdlib/verify_stdlib.sh /tmp/m1_zig1_wrap"
Elapsed (wall clock) time (h:mm:ss or m:ss): 2:33.29
Maximum resident set size (kbytes): 366336
Exit status: 0
run_fixtures: 312 PASS / 0 FAIL over 312 dirs
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
STDLIB GATE OK
```

Per-compiler-call extraction from `/tmp/m1_gate_compiler.time`:

```text
$ grep -c 'Command being timed' /tmp/m1_gate_compiler.time
321
$ grep 'Maximum resident' /tmp/m1_gate_compiler.time | awk '{print $6}' | sort -n | awk 'NR==1{min=$1} {a[NR]=$1} END{print "min="min,"median="a[int((NR+1)/2)],"max="a[NR],"n="NR}'
min=4768 median=6148 max=28836 n=321
```

The compiler-only gate maximum is **28836 KiB**; largest single invocation:

```text
Command being timed: "/tmp/m1_build/zig1_5_clean -ffast -o /tmp/stdlib_run_fixtures.LV2woJ repro/mi_matrix/stdlib_pathfind_plus_xmod/main.zig"
Elapsed (wall clock) time (h:mm:ss or m:ss): 0:00.32
Maximum resident set size (kbytes): 28836
Exit status: 0
```

Arena: the gate harness does not pass `--track-memory`, so the gate exposes no
arena line; tracking was not injected into the gate workload.

### (c) one z9play compile (`-fsafe` emit + `build_target.sh linux`)

Emit command (the compile step under test):

```bash
rm -rf /tmp/m1_z9play_out && mkdir -p /tmp/m1_z9play_out
/usr/bin/time -v -o /tmp/m1_c.time \
  /tmp/m1_build/zig1_5_clean -fsafe -o /tmp/m1_z9play_out \
  examples/z98/z9play/main.zig > /tmp/m1_c.log 2>&1
```

Observed:

```text
Command being timed: "/tmp/m1_build/zig1_5_clean -fsafe -o /tmp/m1_z9play_out examples/z98/z9play/main.zig"
User time (seconds): 0.35
System time (seconds): 0.01
Percent of CPU this job got: 100%
Elapsed (wall clock) time (h:mm:ss or m:ss): 0:00.36
Maximum resident set size (kbytes): 8140
Exit status: 0
```

Emitted C files: 37; 0 `error[` lines; 0 `PANIC` lines (count commands below).

Arena tracking, same fixed-point binary:

```bash
rm -rf /tmp/m1_z9play_arena && mkdir -p /tmp/m1_z9play_arena
/usr/bin/time -v -o /tmp/m1_c_arena.time \
  /tmp/m1_build/zig1_5_clean --markers --track-memory -fsafe \
  -o /tmp/m1_z9play_arena examples/z98/z9play/main.zig > /tmp/m1_c_arena.out 2>&1
```

Observed:

```text
track-memory: perm=877K mod=900K scr=255K pool=4609K type_db=124K total=2032K
Elapsed (wall clock) time (h:mm:ss or m:ss): 0:00.42
Maximum resident set size (kbytes): 8384
Exit status: 0
```

Follow-up target build, run in the emitted output directory:

```bash
cd /tmp/m1_z9play_out
/usr/bin/time -v -o /tmp/m1_c_build.time \
  sh build_target.sh linux /tmp/m1_z9play_out/prog
```

Observed:

```text
Command being timed: "sh build_target.sh linux /tmp/m1_z9play_out/prog"
User time (seconds): 1.39
System time (seconds): 0.31
Percent of CPU this job got: 99%
Elapsed (wall clock) time (h:mm:ss or m:ss): 0:01.70
Maximum resident set size (kbytes): 50076
Exit status: 0
Built: /tmp/m1_z9play_out/prog
```

This **50076 KiB** maximum is gcc during `build_target.sh`, not the compiler;
it is recorded separately and is not the `-fsafe` emit figure.

### Count checks

Reproducible emitted-file and error/PANIC counts:

```bash
$ ls /tmp/m1_emit/*.c | wc -l
50
$ grep -c 'error\[' /tmp/m1_emit.out
0
$ grep -c 'PANIC' /tmp/m1_emit.out
0
$ ls /tmp/m1_emit_hop2/*.c | wc -l
50
$ grep -c 'error\[' /tmp/m1_a_hop2.out
0
$ grep -c 'PANIC' /tmp/m1_a_hop2.out
0
$ ls /tmp/m1_z9play_out/*.c | wc -l
37
$ grep -c 'error\[' /tmp/m1_c.log
0
$ grep -c 'PANIC' /tmp/m1_c.log
0
```

(`grep -c` exits 1 when the count is 0; the printed count is `0`.)

### gcc-only probe (proves gcc dominance, I2)

```bash
rm -rf /tmp/m1_gcc_probe && cp -a /tmp/m1_emit /tmp/m1_gcc_probe
/usr/bin/time -v -o /tmp/m1_gcc_compile.time \
  sh -c 'cd /tmp/m1_gcc_probe && gcc -m32 -std=c89 -O0 -Wall \
  -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration \
  -I . -c *.c'
/usr/bin/time -v -o /tmp/m1_gcc_link.time \
  sh -c 'cd /tmp/m1_gcc_probe && gcc -m32 -O0 *.o -o /tmp/m1_gcc_probe/zig1_link'
```

Observed (gcc compile, 50 C files):

```text
Command being timed: "sh -c cd /tmp/m1_gcc_probe && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I . -c *.c"
Elapsed (wall clock) time (h:mm:ss or m:ss): 0:07.23
Maximum resident set size (kbytes): 172260
Exit status: 0
```

Observed (gcc link):

```text
Command being timed: "sh -c cd /tmp/m1_gcc_probe && gcc -m32 -O0 *.o -o /tmp/m1_gcc_probe/zig1_link"
Elapsed (wall clock) time (h:mm:ss or m:ss): 0:00.02
Maximum resident set size (kbytes): 18788
Exit status: 0
```

`md5sum /tmp/m1_gcc_probe/zig1_link` =
`21c957730d268f1e7883176fa5413b65` (the fixed point). Measured gcc-only
compile peak **172260 KiB** is ~8.3× the compiler's 20792 KiB, proving gcc
dominates the whole-build process-tree max; the 164176 vs 172260 difference is
run-to-run gcc variation.

## Table

Main workload table (scope in each row; one run each):

| Workload | Max RSS KiB | Wall s |
|---|---:|---:|
| (a) two-hop seed build — fixed-point binary `zig1_5_clean` self-emission (`--dump-c89`; closure binary = 20536 KiB / 5.58 s) | 20792 | 5.66 |
| (b) full `verify_stdlib.sh` gate — **whole process-tree max (gcc), NOT compiler RSS; non-consumable in compiler column** | 364936 | 152.45 |
| (c) z9play `main.zig` `-fsafe` emit (compiler only) | 8140 | 0.36 |

Supporting measurements (scope explicit):

| Workload | Max RSS KiB | Wall s |
|---|---:|---:|
| (a) whole `build_from_seed.sh` (compiler + both gcc steps; process-tree) | 164176 | 25.12 |
| (a) gcc-only compile of 50 self-emitted C files | 172260 | 7.23 |
| (a) gcc-only link of resulting objects | 18788 | 0.02 |
| (b) gate compiler-only max (321 fixed-point invocations; largest invocation) | 28836 | 0.32 |
| (b) gate process-tree re-check through wrapper | 366336 | 153.29 |
| (c) z9play `build_target.sh linux` (gcc only) | 50076 | 1.70 |

Arena exposures from `--markers --track-memory` (all values KiB; `total` =
`perm + mod + scr` only, per `sf/src/main.zig:443-449`):

| Workload | perm | mod | scr | pool | type_db | total | Max RSS |
|---|---:|---:|---:|---:|---:|---:|---:|
| (a) fixed-point self-build, `-o` mode | 1023 | 1023 | 875 | 18871 | 243 | 2921 | 20964 |
| (a) fixed-point self-build, `--dump-c89` mode | 1023 | 1023 | 875 | 18871 | 243 | 2921 | 20804 |
| (b) full stdlib gate | not exposed (harness passes no `--track-memory`) | — | — | — | — | — | — |
| (c) z9play `-fsafe` emit | 877 | 900 | 255 | 4609 | 124 | 2032 | 8384 |

Arena tracking adds small wall/RSS overhead (e.g. self-build RSS 20804 vs
20792 KiB untracked), so use the untracked numbers in the RSS table and the
tracking numbers for `pool`/component peaks.

## Target verdict

Compiler target: **<16 MB** = `<16384 KiB`.

- **Does not hold for the fixed-point compiler self-build — fails on both RSS
  and pool.**
  - RSS: fixed-point `zig1_5_clean` peaks at **20792 KiB (20.30 MiB)**, 4408
    KiB (4.30 MiB) over target.
  - Pool: **18871 KiB (18.43 MiB)**, 2487 KiB (2.43 MiB) over target. Pool is
    separate from RSS and is not included in `total=2921K`.
  - Closure binary `hop2/zig1_hop2` (same md5) peaks at **20536 KiB (20.05
    MiB)**, 4152 KiB (4.05 MiB) over target.
- **Holds for the z9play `-fsafe` compile:** RSS **8140 KiB (7.95 MiB)** and
  pool **4609 KiB (4.50 MiB)**, both under target.
- **Gate compiler-only max is 28836 KiB (28.16 MiB)**, also over target, but
  the gate row in the main table (364936 KiB) is a gcc-containing process-tree
  maximum and must not be labeled compiler RSS.
- The whole `build_from_seed.sh` (164176 KiB) maximum is likewise a
  gcc-containing process-tree figure, not compiler RSS.

## Concerns

1. **Scope mixing (I1).** Row (b) in the main table is the whole gate's
   process-tree max (gcc compiling a large fixture), **not compiler RSS**.
   Task 2 must not label it as compiler RSS. If Task 2 needs a gate row in the
   compiler column, use the compiler-only max **28836 KiB / 0.32 s** (321
   invocations) instead.
2. **gcc dominance is now measured (I2), not asserted.** A gcc-only compile of
   the same 50 emitted C files peaks at **172260 KiB** (link: 18788 KiB),
   versus the compiler's 20792 KiB.
3. **Arena is measured where exposed (C1).** The fixed-point self-build exposes
   `pool=18871K` and the z9play `-fsafe` emit exposes `pool=4609K`. The stdlib
   gate harness does not pass `--track-memory`; tracking was not injected, so
   no gate arena figure exists.
4. Existing README rows D/E cite an older fixed point (`553a39b4…`, row D
   self-compile 16376 KiB). Current fixed point self-emission is 20792 KiB;
   Task 2 should not carry the old figure forward as current.
5. Measurements are one run per command (brief did not request 3× medians).
   Run-to-run variation is visible in the whole-build 164176 KiB vs gcc-only
   172260 KiB values; both are far above the compiler's 20792 KiB, so the
   gcc/compiler separation does not depend on that variation.
