# Phase 1 M1 Task 1 — Compiler RSS/peak pre-flight measurements

Status: COMPLETE

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

This whole-script process-tree maximum (**164176 KiB**) is gcc-dominated: the
script also runs two `gcc -m32` compile/link passes over the emitted C. It is
therefore not a compiler-process RSS figure. The fixed-point compiler itself
was measured explicitly (below), as required.

Fixed-point compiler self-emission, hop 1:

```bash
rm -rf /tmp/m1_emit && mkdir -p /tmp/m1_emit
/usr/bin/time -v -o /tmp/m1_emit.time \
  /tmp/m1_build/zig1_5_clean -ffast --dump-c89 \
  --output-dir /tmp/m1_emit sf/src/main.zig
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

Fixed-point compiler self-emission, hop 2 (closure binary):

```bash
rm -rf /tmp/m1_emit_hop2 && mkdir -p /tmp/m1_emit_hop2
/usr/bin/time -v -o /tmp/m1_a_hop2.time \
  /tmp/m1_build/hop2/zig1_hop2 -ffast --dump-c89 \
  --output-dir /tmp/m1_emit_hop2 sf/src/main.zig
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
`21c957730d268f1e7883176fa5413b65` (identical fixed point to hop 1).

### (b) full stdlib gate

Command:

```bash
/usr/bin/time -v -o /tmp/m1_b.time \
  bash scripts/stdlib/verify_stdlib.sh /tmp/m1_build/zig1_5_clean
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
maximum is not a compiler-only RSS figure.

### (c) one z9play compile (`-fsafe` emit + `build_target.sh linux`)

Emit command (the compile step under test):

```bash
rm -rf /tmp/m1_z9play_out && mkdir -p /tmp/m1_z9play_out
/usr/bin/time -v -o /tmp/m1_c.time \
  /tmp/m1_build/zig1_5_clean -fsafe -o /tmp/m1_z9play_out \
  examples/z98/z9play/main.zig
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

Emitted C files: 37; 0 `error[` lines; 0 `PANIC` lines.

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

## Table

Compiler/workload maxima measured above (fresh dirs, one run each):

| Workload | Max RSS KiB | Wall s |
|---|---:|---:|
| (a) two-hop seed build — fixed-point compiler self-emission, hop 1 (worst hop; hop 2 = 20536 KiB / 5.58 s) | 20792 | 5.66 |
| (b) full stdlib gate (`verify_stdlib.sh`; process-tree max, includes gcc fixture builds) | 364936 | 152.45 |
| (c) z9play `main.zig` `-fsafe` emit (compiler only) | 8140 | 0.36 |

Supporting maxima outside the compiler column:

| Workload | Max RSS KiB | Wall s |
|---|---:|---:|
| (a) whole `build_from_seed.sh` (compiler + both gcc hops) | 164176 | 25.12 |
| (c) z9play `build_target.sh linux` (gcc only) | 50076 | 1.70 |

Arena: **not exposed** for any of the three required workloads. The measured
commands do not pass `--track-memory` or a marker harness and print no pool
figure, so no arena number is recorded.

## Target verdict

Compiler target: **<16 MB** = `<16384 KiB`.

- **Does not hold for the fixed-point compiler self-build.** Hop 1 peaks at
  **20792 KiB (20.30 MiB)**, 4408 KiB (4.30 MiB) over the 16 MiB target; hop 2
  peaks at **20536 KiB (20.05 MiB)**, 4152 KiB (4.05 MiB) over. This is the
  worst (hop 1) compiler figure and matches the expected "slightly over today"
  seed-build condition.
- **Holds for the z9play `-fsafe` compile:** 8140 KiB (7.95 MiB), under target.
- The whole `build_from_seed.sh` (164176 KiB) and full stdlib gate (364936 KiB)
  maxima are gcc-dominated process-tree peaks, not compiler RSS; they must not
  be published as the compiler's peak.

## Concerns

1. The brief's literal workload (a), `/usr/bin/time -v bash
   scripts/seed/build_from_seed.sh ...`, reports **164176 KiB** because the
   process-tree maximum is gcc, not the compiler. The compiler-only fixed-point
   self-emission is **20792 KiB** (hop 1) / **20536 KiB** (hop 2); that is the
   number relevant to the <16 MB compiler target.
2. The full stdlib gate's **364936 KiB** likewise includes gcc fixture builds,
   so it is not a compiler-only figure.
3. Arena usage is not exposed by the measured commands; no arena value was
   invented.
4. Existing README rows D/E cite an older fixed point (`553a39b4…`, row D self-
   compile 16376 KiB). Current fixed point self-emission is 20792 KiB; Task 2
   should not carry the old figure forward as current.
5. Measurements are one run per command (brief did not request 3× medians),
   so small run-to-run variation is possible; the compiler/gcc separation is
   large enough not to depend on that variation.
