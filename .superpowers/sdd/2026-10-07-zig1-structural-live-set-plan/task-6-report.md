# Task 6 — Fix the comptime fold table (R1 + R2) → STOP-GATE

Plan: `docs/superpowers/plans/2026-10-07-zig1-structural-live-set-plan.md`
Spec: `docs/superpowers/specs/2026-10-07-zig1-structural-live-set-design.md`
Brief: `.superpowers/sdd/2026-10-07-zig1-structural-live-set-plan/task-6-brief.md`
Branch: `zig1_improvements` (NO push). Inputs: `task-5-report.md` §R1/§R2/§1.4/§1.6.

Implemented the controller-selected **R1 (★ narrow element 48 B → 16 B + rare wide side pool)** and
**R2 (★ pre-size `vals` + `slots`)** exactly as Task 5 defines them. **R3–R6 were NOT implemented**
and no closed lever was re-opened (`comptime_values` stays sparse; no 16-B `AstNode`/I-COMPACT; no
F-1/I-F1; no M5; no prior S-INTERNER; no deferred hash-map layout). No subagents were dispatched.
Edits used `edit`/`fastedit` only; the `Put`/`Get` by-value signatures are unchanged, so the 3+6
production call sites and helpers needed **only recompilation** — each was re-verified against the
encoder/decoder below.

Source edit: `sf/src/comptime_eval.zig` (primary), `sf/src/main.zig` (hint threading).
Report: this file. No test binary was touched (they call `comptimeFoldTableInit`, preserved).

---

## Step 1 — Mechanism + file:line

### R1 — dense element `ComptimeVal` 48 B → `FoldVal` 16 B + index-addressed wide side pool

- `sf/src/comptime_eval.zig:56` — new `FoldVal` (16 B, align 8):
  `{ small: u64, kind: u8, neg: u8, wide: u8, _pad: u8 }`.
- `sf/src/comptime_eval.zig:70` — `ComptimeFoldTable` now carries
  `vals: [*]FoldVal`, `wide_ints: [*]ComptimeInt`, `wide_len`, `wide_cap` (plus the unchanged
  `slots`, `len`, `capacity`, `alloc`). `ComptimeInt` (36 B) and `ComptimeVal` are **retained
  verbatim** for the evaluator's scratch and the by-value boundary.
- `sf/src/comptime_eval.zig:144` `foldValEncode`:
  - `KIND_FLOAT` ⇒ `small = float_bits`, `wide = 0`, `v` reconstructs to `ciZeroInt` (all producers
    set `v = ciZeroInt()` for floats, `:1477`);
  - `KIND_INT`/`KIND_BOOL` with `v.len <= 2` ⇒ inline `small = mag[0] | (mag[1] << 32)` and
    `neg = (v.neg and small != 0)`;
  - `v.len > 2` (rare) ⇒ append `v` to `wide_ints`, `small = u32 index`, `wide = 1`.
- `sf/src/comptime_eval.zig:174` `foldValDecode` reconstructs **by value**:
  float ⇒ `ComptimeVal{ .v = ciZeroInt(), .kind, .float_bits = small }`; wide ⇒ copy
  `wide_ints[small]`; small ⇒ `ciFromU64(small)` then `ci.neg = true` iff the stored `neg` bit is
  set (never for zero, so `-0` normalises to `0`).
- `sf/src/comptime_eval.zig:186` `comptimeFoldTablePut` encodes then stores; overwrite-on-hit
  preserved. `sf/src/comptime_eval.zig:198` `comptimeFoldTableGet` decodes the dense record.
- **Indices, never pointers.** `comptimeFoldTableGrow` (`:117`) copies `FoldVal` records (wide
  indices stay valid) and `comptimeFoldTableGrowWide` (`:130`) copies `ComptimeInt` entries — Get
  always re-reads the *current* `wide_ints` base, so growth cannot dangle a retained wide value.

**Exact-semantics coverage (required):**
- negative small ints — sign is a separate `neg` bit, so `-1` never collides with `u64max`
  (u64 two's-complement would be ambiguous);
- zero / `-0` — `len == 0` round-trips to `ciZeroInt` (all limbs zero, `neg = false`);
- `KIND_FLOAT` — `float_bits` in `small`, round-trips bit-exactly;
- bools — stored `small ∈ {0,1}`, round-trip to `ciBoolVal(false/true)` equality.
Round-trip fixtures `rt.zig` (`0-1`, `u64max`, `0-0`, `-2^63`) and `rt2.zig` (bool + `1<<62`)
emit **byte-identical** `.c` old-vs-new (see Step 1b).

### R2 — source-derived soft pre-size of `vals` + `slots` (keep doubling)

- `sf/src/main.zig:199-200` — `fold_hint = max(16, source.len/9)`. Self-compile source is
  101,537 B ⇒ hint **11,281**. (Distinct divisor from `type_hint`/32 and `name_hint`/10; probed so
  the self-compile lands both arrays at cap 16,384.)
- `sf/src/main.zig:315` — `ce_mod.comptimeFoldTableInitSized(&compiler_alloc.module, fold_hint)`.
- `sf/src/comptime_eval.zig:96` — `comptimeFoldTableInitSized(alloc, hint)`: `vals` is carved once
  at `foldCapFromHint(hint)` = next power of two ≥ hint = **16,384** (`:81`); `slots` is seeded with
  the **existing** `hash_mod.u32ToU32MapInitCap(alloc, hint)` (`util/hash.zig:39`), whose
  `mapCapacityFromHint(11,281)` = `next_pow2(ceil(45,126/3))` = **16,384**.
- `sf/src/comptime_eval.zig:87` — legacy `comptimeFoldTableInit(alloc)` = `InitSized(alloc, 0)`,
  reproducing the old zero-cap growth exactly (test binaries unchanged).
- **Soft floor, never a hard cap:** `comptimeFoldTableGrow` (`:117`) and the map's own
  `u32ToU32MapGrow` resume normal doubling if an input exceeds the seed. `vals` is bump-allocated
  and never zeroed, so an unused tail is carved but not resident; only the map `occupied` array is
  zeroed (16,384 B, replacing the abandoned occupied arrays).

---

## Step 2 — Build, equivalence battery, wide path

### Seed build (no `FIXED_POINT_MD5` pin)

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/struct_seed6
```

- archive md5 `3cacdd44df75c0ce96abfd51af93f928` (v92, unchanged).
- `[seed] two-hop closure OK: hop1 == hop2 == 44b8e7fff5a115743ab5c62adb849555`
  — **NEW fixed point / binary md5 = `44b8e7fff5a115743ab5c62adb849555`**
  (moved from Task 4 `078ed10fc3477c0cfd07140b2dfb4ece`; recorded, not silent).
  Measurement binary: `/tmp/struct_seed6/zig1_5_clean`.

### Self-compile (`-s0 --markers --track-memory`, repo root, RELATIVE path)

```
mkdir -p /tmp/s6/out
/usr/bin/time -v -o /tmp/s6/time.txt /tmp/struct_seed6/zig1_5_clean \
  -s0 --markers --track-memory -o /tmp/s6/out sf/src/main.zig
```

- rc 0, **0 `error[` / 0 `PANIC`**, **48 `.c` / 48 `.h`**.
- `track-memory: perm=761K mod=1023K scr=1020K pool=11965K type_db=249K total=2804K`
  (Task-4 baseline `perm=761K mod=1020K scr=1020K pool=14074K total=2801K` ⇒ **pool −2,109 K**,
  mod +3 K). The pool drop is the removed abandoned fold generations + narrowed element; the
  `module` arena peak itself is flat because `GrowableSand` doubles whole segments (§1.5).

### Step 1b — WIDE-PATH VERIFICATION (mandatory)

The self-compile/battery never stores a >64-bit value (§1.4), so the wide side pool was exercised
by throwaway fixtures in `/tmp/widefix` (NOT committed), across both the fold-table **encode** (the
`var_decl` fold gate stores `shl`/`mul` inits whose `ciShl`/`ciMul` result has `len > 2`) and the
fold-table **decode** (lowering's declaration fit-check `foldNodeIntExact` → `Get` → `foldValDecode`
reconstructs the wide value and rejects it with `error[3000]`):

| fixture | shape | reaches | old `078ed10f` | new `44b8e7ff` | match |
|---|---|---|---|---|---|
| `d.zig` | `const X = 1 << 70;` | wide Put+Get | rc 2, `error[3000]` | rc 2, same stderr | ✅ |
| `e.zig` | `const X: u64 = 1 << 70;` | wide Put+Get | rc 2, `error[3000]` | rc 2, same | ✅ |
| `f.zig` | `1<<70` + `(X>>64)==64` | wide Put+Get | rc 2, `error[3000]` | rc 2, same | ✅ |
| `g.zig` | function-local `1<<70` | wide Put+Get | rc 2, `error[3000]` | rc 2, same | ✅ |
| `c.zig` / `h.zig` | `u64max*3`; **20** wide consts `1<<70..1<<89` | wide Put+Get + **`wide_ints` grow 16→32** | rc 2, `error[3000]` | rc 2, same | ✅ |
| `rt.zig` | `0-1`, `u64max`, `0-0`, `-2^63` | small neg/zero round-trip | rc 0, emitted `.c` | rc 0, **byte-identical** `.c` | ✅ |
| `rt2.zig` | bool + `1<<62` | bool/small round-trip | rc 0, emitted `.c` | rc 0, **byte-identical** `.c` | ✅ |

- `h.zig` (20 distinct wide integers) forces at least one `comptimeFoldTableGrowWide` (cap 0 → 16
  → 32); identical behaviour proves index stability across the side-pool growth.
- Only the `.zig1_lir.tmp` spill temp differs between old/new dumps; every emitted `.c` is
  byte-identical. **Verdict: the wide path is genuinely reached and byte-equivalent to the pre-fix
  inline 256-bit representation.**

### Dump-MD5 8/8 (stdout stream) — delta 0

| program | `-fsafe` | pin | `-ffast` | pin |
|---|---|---|---|---|
| game_of_life | `6df1e4d2e9afa0f4163a7053f67384be` | ✅ | `98e934f3e15be355d47e26ded595dc8a` | ✅ |
| lisp_interpreter_curr | `e27b7c35678974deb130cfc77cb08686` | ✅ | `2514f8b5ddceacba67203af37a7346c3` | ✅ |
| json_parser | `d51f17aebdabcd009e453adb2e286d4e` | ✅ | `e1cc386e9d09e322a068731cb2061621` | ✅ |
| mud_server | `f3be9bb9ebc0c1c9799da2181e2fa7e8` | ✅ | `66d547d4a076fc2ce44d6d3aa3092c1d` | ✅ |

**dump-MD5 delta = 0 → byte-identical output** (only the internal representation changed, never ids
or insertion order).

### corpus — `scripts/corpus/classify`

`1097` dirs = **923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH** — exact match (2m49s).

### stdlib — `scripts/stdlib/verify_stdlib.sh`

`run_fixtures: 266 PASS / 0 FAIL over 266 dirs` → `STDLIB GATE OK` (1m52s).

### examples matrix — 24/24

`MATRIX total=24 ok=24 dumpfail=0 gccfail=0 linkfail=0` (20 `main.zig` dirs + 4 single-file
entries; dump + gcc + link).

### Runtime goldens

| golden | observed | pinned |
|---|---|---|
| gol stdout | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | ✅ |
| lisp `(+ 1 2)` | `b3d9f8974da24ddbf9d389f3d7d97322` | ✅ |
| json stdout | `8bda3d5a1ec07d14a301bc343df32bf8` | ✅ |
| mud server / client | `66c8f0abb926cca7baf9a0d1692ab318` / `93147d0f0bbd983a9d844fea8b7a6fa7` | ✅ |

### Semantic markers — byte-identical IN-SESSION

Same input (`sf/src/main.zig`, the new source) compiled by the **Task-4** binary
(`/tmp/struct_seed4/zig1_5_clean`, md5 `078ed10f…`) and the **new** binary (`44b8e7ff…`), both
`-s0 --markers --track-memory`; telemetry filtered (`arena .*: grew` and `track-memory:`):

```
filtered lines: base 48851 / new 48851
diff base.filt new.filt -> rc 0, 0 diff lines
```

**Residual = only the filtered telemetry**, as expected: the raw `arena module: grew` ladder went
`7 → 8` lines (`4096→8192` then a smoother doubling `8192→65536→…→1048576`, vs the old
`196608→393216→786432→1048576`), and `track-memory:` shifted (`pool 14074K → 11965K`). No AST /
token / phase / fold-value marker differs.

---

## Step 3 — Peak RSS (median of ≥3, interleaved)

`/usr/bin/time -v` Maximum RSS, `-s0` self-compile, alternating Task-4 baseline / new, fresh `-o`
dir each run. 8 interleaved pairs:

| run | baseline `078ed10f` | new `44b8e7ff` | delta K |
|---|---:|---:|---:|
| 1 | 16,936 | 16,080 | −856 |
| 2 | 16,980 | 15,964 | −1,016 |
| 3 | 16,532 | 16,180 | −352 |
| 4 | 16,788 | 16,432 | −356 |
| 5 | 16,984 | 16,252 | −732 |
| 6 | 17,076 | 16,180 | −896 |
| 7 | 16,872 | 16,080 | −792 |
| 8 | 16,740 | 16,168 | −572 |
| **median** | **16,904** | **16,174** | **−730** |
| mean | 16,864 | 16,167 | −697 |

- **new RSS median = 16,174 K** (n=8); **delta ≈ −730 K** vs the interleaved Task-4 binary;
  per-pair median delta ≈ **−762 K**. vs the Task-4 pinned median (16,880 K) the delta is **−706 K**.
- All 8 new samples ≤16,432 K; 7/8 ≤16,384 K (one sample 16,432 K); the **median** — the binding
  metric — is below the target.
- The pool carve fell **−2,109 K** (14,074→11,965 K) while the module arena peak stayed flat
  (`mod=1020K→1023K`): removing the abandoned fold generations drops whole module segments from
  the monotonic pool (the same sub-linear `GrowableSand` masking Task-4 documented, but here the
  cumulative carves were large enough that whole segments vanish).

---

## STOP-GATE verdict

**Peak RSS ≤ 16,384 K? YES — 16,174 K ≤ 16,384 K** (margin ≈210 K, n=8 interleaved median). The
stop-gate **FIRES** for the first time in the plan. Per the plan, the comptime package is complete
and the structural live-set target is met; Task 7 closeout (battery re-verify + seed v93 rotation)
is the remaining step.

---

## Scope / commit

- Source edits: `sf/src/comptime_eval.zig`, `sf/src/main.zig`; report + ledger. Commit
  `refactor(comptime): structural reduction`; branch `zig1_improvements`, **no push**.
- Pre-existing untracked root strays (`anytype_pos.z98`, `fi.err`, `for_closed.z98`,
  `for_open.z98`, `name_u65.z98`, `num_member.z98`, `q.err`, `sh.err`, `sz_u0.z98`) left untouched.
- `/tmp` fixtures not committed.

## Concerns

1. **Thin stop-gate margin.** Median 16,174 K is ~210 K under the 16,384 K target; host noise is
   ±~150 K and one of eight new samples reached 16,432 K. The verdict is the n=8 median (as bound
   by the metric), but a re-run under different load could straddle the line. Task 7 should
   re-measure at HEAD.
2. **Pool drop (−2,109 K) exceeds the ~1.8 MB cumulative fold carve.** Consistent with the
   monotonic pool dropping whole abandoned module segments (`GrowableSand` doubles segments, and
   the old 1.57 MB `vals` carve spanned them), but this was **not independently isolated** — no new
   instrumentation was added. The output-equivalence battery, not a carve model, is the correctness
   evidence.
3. **Wide side pool is exercised only by erring fixtures.** Any genuine >64-bit comptime value is
   rejected at materialisation (`error[3000]`), so the pool's encode/decode is proven by
   identical-error fixtures (incl. a 20-value pool-growth case); a future change that lets a wide
   value materialise would already be covered by this representation.
4. **`fold_hint` upper watch.** For the self-compile both arrays land at cap 16,384 while
   `source.len/9 ∈ [8193, 12287]`, i.e. `source.len ≤ 110,583` (currently 101,537, ~9% headroom).
   Above that the slot map would seed at 32,768 (still correct, only less optimal); this is a soft
   floor, so no correctness risk.
5. **Test binaries not built/run** (unchanged from Task 4): they compile against the preserved
   `comptimeFoldTableInit`; the binding battery is corpus/stdlib/examples/goldens/markers. The
   Task-4 deferred action to run `sf/scripts/build_test.sh` at Task 7 still applies.
