# Task 0 — Preflight baseline (READ-ONLY) report

Branch: `zig1_improvements` (NO push). Spike: no `sf/src` edits, no seed rotation, no dump-MD5 re-baseline.
CWD for all self-compiles: `/workspace/znineeight`, source arg RELATIVE `sf/src/main.zig`.

## Step 1 — Seed build

Command (verbatim per Global Constraints):

```
FIXED_POINT_MD5=0b8c3e4ac0b1fc49c0bdf8caf9d39945 bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/nonast_seed
```

- Seed archive: `release/seed/zig1-seed.tgz`, md5 `39669954c928df59263e5d03cbaacd1d` (matches spec v91).
- Build result: **rc=1** at the final `FIXED_POINT_MD5` gate; the artifact was nevertheless produced and is self-consistent.
  - hop1 binary md5: `d40e875a7ba3aa55d441af56006f6023`  → `/tmp/nonast_seed/zig1_5_clean`
  - hop2 binary md5: `d40e875a7ba3aa55d441af56006f6023`
  - `[seed] two-hop closure OK: hop1 == hop2 == d40e875a7ba3aa55d441af56006f6023`
  - `error: fixed-point mismatch: got 'd40e875a7ba3aa55d441af56006f6023', want '0b8c3e4ac0b1fc49c0bdf8caf9d39945'`
- **Binary used for measurement:** `/tmp/nonast_seed/zig1_5_clean`
  - md5 `d40e875a7ba3aa55d441af56006f6023`; ELF 32-bit LSB pie executable (i386).
- Interpretation: the seed model's *self*-fixed-point holds (hop1 == hop2), so the measured compiler is a
  stable fixed point of the current `sf/src`. The recorded *archived* fixed point `0b8c…` does **not** hold
  because current `sf/src` has moved (logic-dedup commits b6307e88/b6c3be27/93cb5e6f/6f4d8b9f on this
  branch), so its emitted C/binary md5 differs. See Concerns.

## Step 2 — `-s0` self-compile

Command:

```
timeout 120 /usr/bin/time -v /tmp/nonast_seed/zig1_5_clean -s0 --markers --track-memory -o /tmp/nonast_out0 sf/src/main.zig
```

- rc = 0
- `--track-memory` line (stderr, verbatim):
  `track-memory: perm=982K mod=1020K scr=1020K pool=19274K type_db=346K total=3022K`
- `/usr/bin/time -v`: **Maximum resident set size = 20152 kbytes**; wall/Elapsed = **0:04.31**; Exit status 0.
- Dump output (`/tmp/nonast_out0`): **48 `.c`**, **48 `.h`** (plus `build_target.sh`; 97 entries total).
- Markers are on **stderr**; stdout is empty.

## Step 3 — Per-arena carve at `-s0`

Carve = Σ of the `new` value over every `arena <name>: grew <old> -> <new>` line (`sf/src/allocator.zig:155`,
`arenaGrew` fires only on a genuine new carve from the backing pool; `sf/src/allocator.zig:193` formats it).

| arena | Σ new (bytes) | Σ new (K) | grew lines |
|---|---:|---:|---:|
| module | 5,382,144 | 5,256 | 7 |
| scratch | 4,679,906 | 4,570 | 13 |
| diag_read | 4,654,398 | 4,545 | 7 |
| perm | 2,557,240 | 2,497 | 3 |
| import_scratch | 1,385,155 | 1,353 | 6 |
| type_db | 1,032,192 | 1,008 | 6 |
| **Σ** | **19,691,035** | **19,229** | 42 |
| pool (`track-memory`) | 19,736,576 | 19,274 | — |
| untracked remainder (pool − Σ) | 45,541 | 44.5 | — |

Σ ≈ pool: residual **45,541 B (≈44.5 K, 0.23%)** = initial embedded segments (not reported by `arenaGrew`;
`growableSandInit` allocates the first segment without calling it) + `SandSegment` headers + 4-byte alignment.
`diag_read` = **4,545 K** and `import_scratch` = **1,353 K** match the plan's expected figures.

## Step 4 — `-s1` and `-s2`

`-s<N>` deactivates the first N disk spills to RAM, spill order `AST,LIR,HASH,RES,SIDE,EXTRA`
(`sf/src/main.zig:1814-1817`). So `-s1` = AST in RAM, `-s2` = AST+LIR in RAM.

### `-s1` (rc = 0)

Command: `timeout 120 /usr/bin/time -v /tmp/nonast_seed/zig1_5_clean -s1 --markers --track-memory -o /tmp/nonast_out1 sf/src/main.zig`

- `track-memory: perm=982K mod=8192K scr=1020K pool=38252K type_db=563K total=10194K`
- `/usr/bin/time -v`: Max RSS **36684 kbytes**; Elapsed **0:04.61**; rc 0.
- Dump output: 48 `.c`, 48 `.h`.

### `-s2` (rc = 3, expected)

Command: `timeout 120 /usr/bin/time -v /tmp/nonast_seed/zig1_5_clean -s2 --markers --track-memory -o /tmp/nonast_out2 sf/src/main.zig`

- rc = **3**; `/usr/bin/time -v`: Max RSS **67676 kbytes**; Elapsed **0:01.78**.
- Failure line: `memory limit exceeded: pool limit=65536K pool=75693K` then
  `ICE: out of memory at allocator.zig:28` (the 64 MB pool budget is exceeded before completion).
- No final `track-memory` line (aborted); no dump output (0 `.c`, 0 `.h`).

### Per-arena carve tables (`Σ new`), all levels

| arena | -s0 (B) | -s0 (K) | -s1 (B) | -s1 (K) | -s2 (B) | -s2 (K) |
|---|---:|---:|---:|---:|---:|---:|
| emission | 0 | 0 | 0 | 0 | 37,683,200 | 36,800 |
| module | 5,382,144 | 5,256 | 25,174,016 | 24,584 | 25,174,016 | 24,584 |
| scratch | 4,679,906 | 4,570 | 4,679,906 | 4,570 | 5,335,266 | 5,210 |
| diag_read | 4,654,398 | 4,545 | 3,878,844 | 3,787 | 3,878,844 | 3,787 |
| perm | 2,557,240 | 2,497 | 2,557,240 | 2,497 | 2,557,240 | 2,497 |
| import_scratch | 1,385,155 | 1,353 | 1,284,369 | 1,254 | 1,284,369 | 1,254 |
| source | 0 | 0 | 1,156,835 | 1,129 | 1,156,835 | 1,129 |
| type_db | 1,032,192 | 1,008 | 393,216 | 384 | 393,216 | 384 |
| **Σ** | **19,691,035** | **19,229** | **39,124,426** | **38,207** | **77,462,986** | **75,647** |
| pool | 19,736,576 | 19,274 | 39,170,048 | 38,252 | 77,509,632* | 75,693* |
| residual | 45,541 | 44.5 | 45,622 | 44.6 | 46,646 | 45.6 |

\* `-s2` aborted mid-run; "pool" is the value at abort (`pool limit=65536K pool=75693K`), not a final total.

### Arena deltas showing AST/LIR leaving disk

| arena | Δ s0→s1 (B) | Δ s1→s2 (B) | meaning |
|---|---:|---:|---|
| module | **+19,791,872** | 0 | AST (spill #1) pulled off disk into the `module` arena at `-s1` |
| source | **+1,156,835** (new) | 0 | `source` arena appears once AST is RAM-resident |
| emission | 0 | **+37,683,200** (new) | LIR (spill #2) pulled off disk into the `emission` arena at `-s2` |
| scratch | 0 | +655,360 | extra scratch pressure at `-s2` |
| diag_read | −775,554 | 0 | shrinks at `-s1` |
| import_scratch | −100,786 | 0 | shrinks at `-s1` |
| type_db | −638,976 | 0 | shrinks at `-s1` |
| **Σ** | **+19,433,391** | **+38,338,560** | |

So `-s0` keeps AST/LIR on disk (small `module`, no `source`/`emission`); `-s1` materialises AST in
`module` (+18.9 MiB); `-s2` additionally materialises LIR in `emission` (+36.8 MiB), which is what pushes
`pool` past the 64 MB budget.

## Step 5 — AST/LIR/string scale markers

| marker | -s0 | -s1 | -s2 |
|---|---:|---:|---:|
| `IRN:n` (import_resolver shared_store.nodes) | 294,063 then 294,693 | 294,063 then 294,693 | 294,063 then 294,693 |
| `IRE:x` (extra_children) | 117,479 then 117,727 | 117,479 then 117,727 | 117,479 then 117,727 |
| `INT:new` count (interned strings) | **34,020** (final `INT:new34020`) | **34,020** | 13,600 (aborted) |
| `L nodes=` | **not emitted** | not emitted | not emitted |

- `IRN`/`IRE` are emitted by `sf/src/import_resolver.zig:148-149` (two passes each; final values
  294,693 nodes / 117,727 extra-children).
- `INT:new` is emitted by `sf/src/string_interner.zig:125`; markers are numbered `INT:new1 … INT:new34020`,
  so the count is 34,020 on a full run.
- **`L nodes=` is unavailable:** it is emitted via `pal.markerWrite` (`sf/src/main.zig:785-797`,
  `ctx.store.nodes.len` + `extra_children.len`) but `pal.markerWrite` is gated by
  `pub const g_markers_debug: u32 = 0` (`sf/src/pal.zig:210-216`), a compile-time constant. It is compiled
  out of this binary and cannot be observed with `--markers`. `IRN:n`/`IRE:x` are the only live
  AST/LIR scale markers.

## Step 6 — Commit

Report committed with `git add -f` and message `docs: non-AST memory plan — Task 0 baseline` (only this
report file; the `.superpowers/sdd/...` path is gitignored).

## Concerns

1. **Recorded archived fixed point does not reproduce (rc=1 at the gate).** hop1==hop2 confirms a valid
   self-fixed-point, but both equal `d40e875a7ba3aa55d441af56006f6023`, not the archived
   `0b8c3e4ac0b1fc49c0bdf8caf9d39945`. Cause: current `sf/src` differs from the seed's era (logic-dedup
   commits on this branch), so the emitted C/binary md5 changes. All memory numbers nevertheless match the
   plan's expected `diag_read` 4,545 K and `import_scratch` 1,353 K, so the refactors appear
   memory-neutral; but strictly the measurement binary is **not** the archived fixed point. No
   re-baseline was performed (per spike rules).
2. **`L nodes=` marker is compiled out** (`g_markers_debug = 0`); Step 5's request for it cannot be
   satisfied from the shipped binary. `IRN:n`/`IRE:x` stand in.
3. **`source` arena absent at `-s0`** (0 B) but the plan's Task 2 expects a `source` carve (583 K); it only
   appears at `-s1` here (1,129 K). Flagging so Task 2 does not hunt a nonexistent `-s0` row.
4. `-s2` aborts before producing a final `track-memory` line or any dump output; "pool" for `-s2` is the
   abort-time value, so its Σ-vs-pool residual is approximate.
5. Untracked root-level files (`*.z98`, `*.err`) pre-existed in the worktree and were deliberately **not**
   committed; only this report is staged.
