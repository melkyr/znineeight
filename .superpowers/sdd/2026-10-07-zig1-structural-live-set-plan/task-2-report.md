# Task 2 — Fix the string interner (R1 + R2) → STOP-GATE

Plan: `docs/superpowers/plans/2026-10-07-zig1-structural-live-set-plan.md`
Spec: `docs/superpowers/specs/2026-10-07-zig1-structural-live-set-design.md`
Branch: `zig1_improvements` (NO push). Source edit: `sf/src/string_interner.zig` only.

Implemented the controller-selected **R1 (★)** and **R2 (★)** from
`task-1-report.md`. **R3 / R4 / R5 / R6 were NOT implemented**, no call site was
touched, no rewiring/instrumentation was added, and **S-INTERNER was not
re-opened**. The `stringInternerGet` contract (a `[]const u8` slice into the
never-freed `perm` text blob) is preserved — the `text` column and its pointer
are untouched; only bucket slot width and the entry `hash` column changed.

---

## Step 1 — Mechanism + file:line

### R1 — narrow bucket slots `u32` → `u16` (wide fallback + one-time migration)

Bucket slots hold an entry index with `0` = empty sentinel. At self-compile
`bc = 125,798 ≤ 131,070` (⇒ entry capacity `ec = bc/2 = 62,899 ≤ 65,535`), so the
slots are `u16`; a larger `bc` (or an `entries_len` that would cross 65,535)
uses the pre-existing `u32` path.

- `sf/src/string_interner.zig:12-23` — `StringInterner` now carries
  `buckets_narrow_items: [*]u16`, `buckets_wide_items: [*]u32`,
  `buckets_is_wide: bool` (bucket *count*, `hash % buckets_len` distribution,
  insert order and ids are unchanged).
- `:25-26` — `NARROW_BUCKET_MAX_BC = 131070`, `MAX_U16_ENTRY_INDEX = 65535`.
- `:28-36` — `internerBucketsAllocNarrow` (2 B/slot, align 2) /
  `internerBucketsAllocWide` (4 B/slot, align 4).
- `:38-57` — `internerBucketGet/Set/Zero` width-dispatched accessors.
- `:79-114` — init selects narrow unless `bc > NARROW_BUCKET_MAX_BC`, then zeroes
  `bc` slots in the selected width.
- `:128-164` — intern: `bucket` is a `usize`; chain walk uses `internerBucketGet`;
  before appending, `if (!buckets_is_wide and new_idx > MAX_U16_ENTRY_INDEX)`
  calls `stringInternerMakeBucketsWide` (one-time migration); store via
  `internerBucketSet`.
- `:178-196` — `stringInternerMakeBucketsWide`: allocate a `u32` array of the same
  count, zero it, rehash entries `1..entries_len` (recomputing `fnv1a(entry.text)`
  after R2), set the head links.
- `:198-226` — `stringInternerGrowBuckets`: rehashes in the current width; slot
  stores use the same width-dispatched accessors.

### R2 — drop the stored `hash` column from `InternEntry`

`{text 8 + hash 4 + next 4} = 16 B` → `{text 8 + next 4} = 12 B` (align 4);
`next` stays `u32`. Equality already memcmp-fallbacks, and rehash (which does not
occur at self-compile) recomputes `fnv1a(entry.text)`.

- `sf/src/string_interner.zig:7-10` — `InternEntry` loses `hash`.
- `:64` — entries carve uses `@sizeOf(InternEntry)` (12) instead of hardcoded 16.
- `:120-123` — sentinel `{ "", 0 }`.
- `:141` — lookup is `if (mem_mod.mem_eql(entry.text, text))` (fast-reject gone).
- `:153-156` — append no longer stores `hash`.
- `:190` / `:221` — rehash/migration recompute `fnv1a(entry.text)`.

Removed the now-obsolete `ensureCapacityBuckets` + dormant `appendBucket`
helpers (both operated on the old `[*]u32` bucket representation); no new
dormant helper was introduced.

---

## Step 2 — Build, equivalence battery, markers

### Seed build (no `FIXED_POINT_MD5` pin)

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/struct_seed
```

- archive md5 `3cacdd44df75c0ce96abfd51af93f928` (v92, unchanged).
- `[seed] two-hop closure OK: hop1 == hop2` — **NEW fixed point / binary md5 =
  `9cdcc97bb8dc0a0b94e29b9e981e5376`** (moved from the Task-0 `2293f756…`;
  recorded, not silent). Measurement binary: `/tmp/struct_seed/zig1_5_clean`.

### Self-compile (`-s0 --markers --track-memory`, repo root, RELATIVE path)

```
mkdir -p /tmp/struct_s0/out
/usr/bin/time -v -o /tmp/struct_s0/time.txt \
  /tmp/struct_seed/zig1_5_clean -s0 --markers --track-memory \
  -o /tmp/struct_s0/out sf/src/main.zig
```

- rc 0, **0 `error[` / 0 `PANIC`**, **48 `.c` / 48 `.h`**.
- `track-memory: perm=759K mod=1020K scr=965K pool=14433K type_db=346K total=2744K`
  (baseline `perm=982K … pool=14924K total=2967K` ⇒ **pool −491 K**, perm/total
  −223 K).
- `INT:new` count = **34,039** (was 34,020; the source grew by ~19 names). Still
  `≪` the 65,535 ceiling ⇒ narrow path, no migration, no bucket growth/rehash at
  self-compile.

### Dump-MD5 8/8 (stdout stream) — delta 0

| program | `-fsafe` | pin | `-ffast` | pin |
|---|---|---|---|---|
| game_of_life | `6df1e4d2e9afa0f4163a7053f67384be` | ✅ | `98e934f3e15be355d47e26ded595dc8a` | ✅ |
| lisp_interpreter_curr | `e27b7c35678974deb130cfc77cb08686` | ✅ | `2514f8b5ddceacba67203af37a7346c3` | ✅ |
| json_parser | `d51f17aebdabcd009e453adb2e286d4e` | ✅ | `e1cc386e9d09e322a068731cb2061621` | ✅ |
| mud_server | `f3be9bb9ebc0c1c9799da2181e2fa7e8` | ✅ | `66d547d4a076fc2ce44d6d3aa3092c1d` | ✅ |

**dump-MD5 delta = 0 → byte-identical output** (as predicted: only widths/columns
changed, never ids/insertion order).

### corpus — `scripts/corpus/classify`

`1097` dirs = **923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH** — exact match.

### stdlib — `scripts/stdlib/verify_stdlib.sh`

`run_fixtures: 266 PASS / 0 FAIL over 266 dirs` → `STDLIB GATE OK`.

### examples matrix — 24/24

`MATRIX total=24 ok=24 dumpfail=0 gccfail=0 linkfail=0`
(20 `main.zig` dirs + 4 single-file entries `func_ptr_return`, `mandelbrot`,
`quicksort`, `sort_strings`; dump + gcc + link).

### Runtime goldens

| golden | observed | pinned |
|---|---|---|
| gol stdout | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | ✅ |
| lisp `(+ 1 2)` | `b3d9f8974da24ddbf9d389f3d7d97322` | ✅ |
| json stdout | `8bda3d5a1ec07d14a301bc343df32bf8` | ✅ |
| mud server / client | `66c8f0abb926cca7baf9a0d1692ab318` / `93147d0f0bbd983a9d844fea8b7a6fa7` | ✅ |

### Semantic markers — byte-identical IN-SESSION

Same input (`sf/src/main.zig`, the new source) compiled by the **baseline**
binary (`/tmp/liveset_seed/zig1_5_clean`, md5 `2293f756…`) and the **new** binary
(`9cdcc97b…`), both `-s0 --markers --track-memory`; filter
`arena .*: grew` and `track-memory:` (legitimately shift) on both:

```
filtered lines: base 48713 / new 48713
diff /tmp/struct_base/markers.filt /tmp/struct_s0/markers.filt → rc 0, 0 diff lines
```

`INT:*` markers, phase/token/AST markers are all byte-identical. No remaining
diff. (AST-index markers were compared in-session against the baseline binary on
the identical input, not against a stale cross-source capture.)

---

## Step 3 — Peak RSS (median of ≥3, interleaved)

`/usr/bin/time -v` Maximum RSS, `-s0` self-compile, alternating baseline/new,
fresh `-o` dir each run:

| run | baseline (`2293f756…`) | new (`9cdcc97b…`) |
|---|---:|---:|
| 1 | 17,364 K | 16,996 K |
| 2 | 17,552 K | 17,272 K |
| 3 | 17,428 K | 17,096 K |
| **median** | **17,428 K** | **17,096 K** |

- **new median = 17,096 K**, **delta = −332 K** vs the interleaved baseline
  (and −328 K vs the frozen Task-0 baseline 17,424 K).
- Consistent with the byte prize (~0.37 MiB R1+R2) after page rounding; the
  pool drop is larger (−491 K) but only touched pages raise RSS.

---

## STOP-GATE verdict

**Peak RSS ≤ 16,384 K? NO — 17,096 K > 16,384 K.** The stop-gate is **NOT**
triggered. Per the plan, the interner package is complete and the plan
**proceeds to Task 3 (type registry)** — do not stop at Task 7 yet.

(Expected: Task 1 already flagged the interner alone cannot reach the 16 MB
target; the gap remains ≈712 K.)

---

## Scope / commit

- Only `sf/src/string_interner.zig` + this report (+ the pre-existing
  `progress.md` ledger line) are committed: `refactor(interner): structural
  reduction`. Branch `zig1_improvements`, **no push**.
- Pre-existing untracked root strays (`anytype_pos.z98`, `fi.err`,
  `for_closed.z98`, `for_open.z98`, `name_u65.z98`, `num_member.z98`, `q.err`,
  `sh.err`, `sz_u0.z98`) left untouched.
- No call sites changed; `stringInternerGet` still returns `entries_items[id].text`
  into the never-freed `perm` text blob (no interior pointer into
  `buckets_items`/`entries_items`).

## Concerns

1. **Gate not met** — expected; the interner package is a partial reduction.
   Task 3 must not assume the 16 MB target is near at hand.
2. **RSS host noise** is ±~0.3 MB (baseline samples span 188 K), but the
   new-vs-baseline separation (≈330 K) is consistent across all three
   interleaved pairs.
3. **Wide fallback/migration is unexercised at self-compile** (narrow path,
   `entries_len = 34,040 < 65,535`). It is exercised only by inputs interning
   >65,535 distinct strings; the corpus (923 OK / 58 GREEN) and stdlib exercised
   larger multi-module inputs but not that ceiling. The migration guard is
   index-safe by construction (`new_idx > 65535` before any `u16` store), but no
   battery fixture drives it.
4. The `hash` fast-reject removal adds `mem_eql` comparisons on hash collisions;
   at load factor ≤0.5 chains are short and all gates pass byte-identically.
