# Task 1 — Investigate the string interner (READ-ONLY)

Plan: `docs/superpowers/plans/2026-10-07-zig1-structural-live-set-plan.md`
Spec: `docs/superpowers/specs/2026-10-07-zig1-structural-live-set-design.md`
Branch: `zig1_improvements` (NO push). This task made **no `sf/src` edit**, **no rewiring**, **no
instrumentation**, **no seed build**, and **no self-compile measurement**. All counts below are from
the existing `--markers`/allocation-census record plus source inspection at HEAD `c8b87daa`.

Binding metric: **peak RSS** (`/usr/bin/time -v` Maximum RSS), median ≥3 interleaved `-s0`
self-compile. **Carve ≠ touched RSS**: only written/zeroed pages raise RSS. Every "byte prize" below
is stated **resident at `-s0` (touched pages)**, with the pool-only entries labelled.

---

## Step 1 — Exact layout (`sf/src/string_interner.zig`, read end to end)

The target is **32-bit** (`scripts/seed/build_from_seed.sh:18,91` compile emitted C with `gcc -m32`).
So a Zig slice `[]const u8` is `ptr(4) + len(4) = 8 B`, and `usize` is 4 B. This is why
`InternEntry` is 16 B, not 24 B.

```zig
pub const InternEntry = struct {   // string_interner.zig:7-11
    text: []const u8,   // 8 B: ptr into the perm text copy + len
    hash: u32,          // 4 B: fnv1a(text); used for fast reject + rehash bucket
    next: u32,          // 4 B: chain link = index into entries_items (0 = end)
};                      // total 16 B, align 4 (no padding)
```

`StringInterner` (`:13-22`) = `buckets_items: [*]u32` (4 B/slot, open hashed into buckets `hash % buckets_len`), `buckets_len`/`buckets_capacity`,
`entries_items: [*]InternEntry` (16 B/slot), `entries_len`/`entries_capacity`, `entries_allocator`,
`allocator`. Both arrays come from the same `perm` (permanent, never-reset) arena.

**Init / sizing** (`stringInternerInit`, `:64-103`; called from `main.zig:188-190`):
- `interner_bc = source.len + source.len/4`, floored to 4096 (`main.zig:188-189`). `source.len` is the
  **input file only** (`main.zig:182` reads `cli.input_file`), i.e. `sf/src/main.zig` = **100,639 B**.
- `bc = 100,639 + 25,159 = 125,798` buckets (`:80-90`); bucket array `4 × 125,798 = 503,192 B`; the
  init loop **zeroes every slot** (`:84-87`) → **all 503,192 B touched**.
- `ec = bc/2 = 62,899` entries (`:91-95`); `16 × 62,899 = 1,006,384 B` allocated in one call; only the
  written prefix is ever stored → **carved-but-mostly-NOT-touched**.
- Entry 0 is the sentinel `{ "", 0, 0 }` (`:96-101`), reserved as the "empty bucket" value
  (`buckets[..] == 0`) and returned for `Get(0)`.
- Cumulative `stringInternerInit` = `503,192 + 1,006,384 = 1,509,576 B` (census: 1,474.2K perm +
  entries) — matches exactly.

**Load factor / rehash** (`:134-137`, `stringInternerGrowBuckets`, `:153-170`):
- After each successful insert, `if (entries_len * 2 > buckets_len) growBuckets(buckets_len * 2)`.
- `ensureCapacityBuckets` (`:24-36`) allocates a **new** bucket array, copies the prefix, and leaves the
  old one in `perm` (never freed) → a real grow would *add* touched bytes permanently.
- Rehash walks entries 1..len and relinks each via `entry.hash % new_bucket_count` (`:163-170`).
- Because init pre-sizes `entries_capacity = bc/2` and buckets to `bc`, the 0.5-trigger only fires if
  `entries_len` exceeds `bc/2 = 62,899`. At self-compile `entries_len = 34,021` (sentinel + 34,020) →
  **no bucket growth, no rehash** (pre-size design at `:75-79` deliberately avoids this).
- If `buckets_len == 0` (only `stringInternerInit(arena, 0)`; never in production — `main` floors to
  4096, tests pass 4), insert first calls `growBuckets(8)` (`:110-113`).

**Insert path** (`stringInternerIntern`, `:105-139`): hash = `fnv1a(text)` (`:108`); bucket =
`hash % buckets_len`; walk the chain comparing `entry.hash == hash and mem_eql(entry.text, text)`
(`:117-122`, marker `INT:dup`); on miss copy `text` into `perm` (`stringInternerCopyToArena`,
`:145-151`, alignment 1, no per-alloc header) and `appendEntry` with `next = buckets[bucket]`
(`:124-132`, marker `INT:new` via `measureMarkerWriteInt`), then store the new index into the bucket.
Counters are `INT:new`/`INT:dup`/`INT:tl`/`INT:t0` (marker-only; no wiring added).

**Get path** (`stringInternerGet`, `:141-143`): returns `entries_items[id].text` — a slice pointing
into the **`perm` text blob**, which is never freed, so the slice is stable for the whole run.

**Consumers** (source scan): `stringInternerIntern` in lexer (`lexer.zig:312,448,459,480`), parser
(`parser.zig:118,128,152,157,460`), analyzer (`analyzer.zig:185-509`), comptime
(`comptime_eval.zig:131-147`), type_resolver (`type_resolver.zig:1074-2278`), module_registry
(`module_registry.zig:174-196`). `stringInternerGet` is called ~100+ times, dominated by the C emitter
(`c89_emit.zig`) during emission; several callers return/retain the slice (mangled names, `c_name_id`,
`path_id`). Two consumers also read the array fields directly rather than through `Get`:
`diagnostics.zig:738,773,822,841` read `interner.entries_items[mid].text` (by-value slice copy, written
immediately), and `const_alias_prepass.zig:81` reads `interner.entries_len`. No consumer stores a
pointer **into `entries_items` or `buckets_items`** — they only hold `text` slices into the stable text
blob (and the id `u32`).

---

## Step 2 — True self-compile counts (existing measurements only)

| quantity | value | source |
|---|---:|---|
| `source.len` (main.zig) | **100,639 B** | `wc -c sf/src/main.zig`; `main.zig:188` |
| buckets `bc` | **125,798** | `100,639 + 25,159` (`main.zig:188-189`) |
| bucket array | **503,192 B** | `4 × 125,798` (`string_interner.zig:82`), **all zeroed/touched** |
| entries cap `ec` | **62,899** | `bc/2` (`:91-95`) |
| entries carve | **1,006,384 B** | `16 × 62,899` (`:93`) |
| entries written | **34,020 new + 1 sentinel = 34,021** | `INT:new34020`; census `CopyToArena` 34,020 calls (`allocation-census.md:86`) |
| entries resident (touched) | **544,336 B** | `16 × 34,021` |
| entries tail (carved, NOT touched) | **462,048 B** | `16 × (62,899 − 34,021)` |
| text copies | **428,506 B / 34,020 allocs** | census `stringInternerCopyToArena` (`allocation-census.md:86`) |
| `stringInternerInit` cumulative | **1,509,576 B** | census (`allocation-census.md:77`) |
| **interner resident total** | **≈1,476,034 B (1.41 MiB)** | `503,192 + 544,336 + 428,506` |

Load-factor sanity: 34,020 distinct strings at 0.5 → 68,040 buckets; current 125,798 →
**57,758 excess ≈ 231,032 B touched** (`task-1-report.md` 2026-10-06 §Interner). Page granularity:
buckets 503,192 B ≈ 123 pages; entries-resident ≈ 133 pages; text ≈ 105 pages.

---

## Step 3 — Four-lens analysis and ranked candidates

Each candidate: mechanism · `file:line` · **resident byte prize** · risk · gate. The common gate for
any Fix is the Global-Constraints battery (corpus 923/58/116, goldens gol/lisp/json/mud,
`verify_stdlib` 266/0, examples 24/24, dump-MD5 8/8, semantic markers byte-identical in-session) **plus
RSS median ≥3** and the new fixed point recorded.

### R1 — Narrow bucket slot `u32` → `u16`  ★ top candidate
- **Mechanism.** Bucket slots hold an **entry index** with `0` as the empty sentinel. `entries_len`
  maxes at 34,021 at self-compile, and even at full design occupancy `ec = bc/2 = 62,899 < 65,536`.
  Widen on load (`:115`), narrow on store (`:132`). Bucket *count*, `hash % buckets_len` distribution,
  insert order and ids are all unchanged → **byte-identical output**. Use `u16` when
  `bc ≤ 131,070` (⇒ `ec ≤ 65,535`), else the existing `u32` path (wide fallback); if `entries_len`
  would cross 65,535 in `u16` mode, migrate buckets to `u32` once in `stringInternerGrowBuckets`.
- **Sites.** `string_interner.zig:14` (field type), `:24-36` (`ensureCapacityBuckets`),
  `:52-56`/`:82-90` (append/init fill), `:115`/`:130-132` (lookup/store), `:153-170` (grow/migrate).
- **Resident prize.** `(4−2) × 125,798 = 251,596 B` (byte) → **≈245–250 KB** (page-rounded:
  123→62 pages). All bucket bytes are zeroed today, so every saved slot is a resident slot.
- **Risk.** **Low–Med.** Correctness is trivial; the only complexity is the `u16`/`u32` fallback and
  the rare overflow migration. Fully expressible in the seed model.
- **Gate.** Common + markers byte-identical (ids/order untouched) + `--track-memory perm` drop.

### R2 — Drop (or narrow) the stored `hash`  ★ second candidate
- **Mechanism.** `InternEntry` is `{text 8 + hash 4 + next 4} = 16 B`. Equality already
  memcmp-fallbacks (`:118`: `entry.hash == hash and mem_eql(...)`), so `hash` is a **pure fast-reject
  column** — derivable from `text`. Remove it → `{text 8 + next 4} = 12 B` (align 4). Rehash at
  `:166` recomputes `fnv1a(entry.text)` instead of reading `entry.hash` (no rehash occurs at
  self-compile). *Alternative:* keep a 16-bit reject as `{text 8 + hash u16 + next u16} = 12 B`, but
  then bucket selection, insertion and rehash must consistently use `hash & 0xffff`, and narrowing
  `next` to `u16` re-imposes a 65,535-entry ceiling (same fallback/migration concern as R1); same
  saving, keeps a cheap reject. The primary remove-`hash` path keeps `next: u32` and is unaffected by
  that ceiling.
- **Sites.** `string_interner.zig:7-11`, `:43`/`:93` (`@sizeOf` uses), `:96-101` (sentinel),
  `:117-122` (lookup), `:127-131` (append), `:153-170` (grow recompute).
- **Resident prize.** `4 × 34,021 = 136,084 B` (byte) → **≈135 KB** (page-rounded 133→100 pages),
  only on the written prefix; the untouched tail shrinks by the same 4 B/slot at no RSS cost.
- **Risk.** **Low.** Output/equality semantics unchanged; only extra `mem_eql` on collisions
  (load factor ≤0.5 ⇒ short chains). Seed supports it.
- **Gate.** Common + markers byte-identical.

### R3 — Tighten the bucket over-provision (count, not width)
- **Mechanism.** `interner_bc = source.len + source.len/4` (`main.zig:188`) buys a 0.5-load target for
  a *worst case* that does not occur: self-compile interns 34,020, needing only 68,040 buckets. A
  tighter hint (e.g. `bc = source.len` = 100,639 ⇒ `ec = 50,319`, a 48% margin) reduces zeroed/touched
  buckets. This is a **different mechanism** from the closed write-through S-INTERNER lever.
- **Sites.** `sf/src/main.zig:188-190` only.
- **Resident prize.** `bc=source.len`: `(125,798−100,639) × 4 = 100,636 B` → **≈100 KB**. Aggressive
  `bc=68,040`: 231,032 B but **zero margin**.
- **Risk.** **Med, data-dependent.** Under-provision triggers `stringInternerGrowBuckets`, which
  allocates a new bucket array and leaks the old one in `perm` (never freed) → *adds* touched bytes and
  can be net-worse. Only safe with a measured margin ≥ ~1.4× actual intern count. Combines with R1 for
  ~0.30–0.35 MiB total.
- **Gate.** Common + re-measure intern count across the corpus (not just self-compile) before choosing.

### R4 — Exact-fit the entries array — **POOL-ONLY, NOT resident**
- **Mechanism.** Entries pre-size to `bc/2` (1,006,384 B) but only 34,021 are written. `sandAlloc` is a
  bump that never zeroes (`allocator.zig:43-76`), so the 462,048 B tail is **carved-but-NOT-touched**.
  Shrinking it (impossible to "exact-fit" at init without a count) lowers `pool` carve only.
- **Sites.** `string_interner.zig:91-95`; `main.zig:188`.
- **Resident prize.** **0 B.** Pool carve up to 462,048 B.
- **Risk.** **Med** if actually under-sized: growing entries abandons the old array in `perm` and
  `touches` the new one → **worse RSS**. Do **not** fund this for the RSS target. (Same page-density
  argument defeats "don't zero buckets": with 34,020 hash-scattered occupied slots over 123 pages,
  every page still receives a write, so a sparse/occupancy-bitset scheme saves ~0 RSS. Rejected.)

### R5 — Open-addressing rewrite (drop `next`) — deferred, larger ceiling
- **Mechanism.** Replace per-bucket chaining with linear probing; buckets store an entry index; remove
  `next` from `InternEntry` (`{text 8, hash 4}=12`, or with R2 `{text 8}=8`). Ids and insertion order
  are preserved, so output stays byte-identical. The `0` sentinel doubles as "empty slot"; there are
  no deletions.
- **Sites.** `string_interner.zig:105-170` (lookup/insert/grow) — a subsystem rewrite.
- **Resident prize.** `4 × 34,021 = 136,084 B` (drop `next`), up to ~272 KB if `hash` is also dropped;
  buckets can stay wide. Total with R1+R2 ceiling ≈0.5 MiB.
- **Risk.** **Med–High.** Probing/rehash correctness, sentinel semantics, and seed-model support. Rank
  behind R1/R2 (same or less prize for much more disturbance).

### R6 — Inline text / offset encoding — REJECTED (no win + aliasing trap)
- On 32-bit an offset is 4 B vs a 4 B pointer, so storing `offset+len` into one text blob is **byte-
  neutral** (8 B → 8 B). Inlining text *into* `entries_items` would make `stringInternerGet` return an
  **interior pointer into a growable array**; `ensureCapacityEntries` (`:38-50`) reallocates-and-copies,
  invalidating every previously returned slice that callers retained (emitter name slices, mangled
  names, `path_id`s). That is the known growable-array aliasing trap → reject. (R1/R2 change only
  widths/columns, never the `text` pointer, so the retained-slice contract is untouched.)

### Lens verdicts
1. **Integer reuse / interning.** `hash` is the derivable parallel column → R2. `next` is topology,
   not derivable → R5. Exact-string dedup already happens; substring/suffix sharing would touch the
   emitter's stable slices and is unproven → not pursued.
2. **One-use / retention.** The interner is live for the whole run; emission dominates `Get`s and the
   RSS peak is at/near emission, so freeing or streaming later cannot lower the peak. No actionable
   retention lever (see S-INTERNER below).
3. **Representation.** R1 (width), R3 (sparse density), R5 (SoA→open addressing), R6 (offset/inline —
   rejected), R4 (exact-fit — **pool-only**).
4. **Pointer vs inline, mutation safety.** No win on 32-bit (pointer = offset = 4 B); inlining into the
   entries array is rejected on the reallocation/retained-slice hazard. Text keeps pointing into the
   never-freed `perm` blob, which is why the current returned slices are safe and why R1/R2 are safe.

### Honest total and target reality
R1 (~0.24 MiB) + R2 (~0.13 MiB) ≈ **0.37 MiB resident**; adding R3 ≈ **0.47 MiB**. The binding
baseline is peak RSS **17,424 K** and the interim target is **16,384 K** — a gap of **1,040 K ≈
1.0 MiB** to find. **The interner alone cannot
reach the stop-gate**; the plan must proceed to the type registry / comptime packages unless another
structure yields the remainder. The byte prize is real but modest relative to the goal.

### Closed levers — stated explicitly (must not be re-opened)
- **S-INTERNER, as previously scoped, is CLOSED UNFEASIBLE.** That lever was **write-through /
  streaming the interner text** out of `perm`: 95.9% of interner `Get`s happen **during emission**,
  the actual text was only **288 KiB** (a 14× correction of the prior ~4 MB assumption), the text was
  **being written during emission** (not quiescent), **slices into interner text are retained**, and
  the prize was **~0.29 MiB at the highest risk** (`task-3-report.md` 2026-10-06 §B, AMENDMENT 17).
  Nothing found here re-opens it; R1/R2/R3 are *different* mechanisms (bucket width, hash column,
  bucket count) that never touch text residency.
- Also not re-opened: 16-B `AstNode` (I-COMPACT), sparse→dense for `coercion`/`enum_value_table`/
  `comptime_values`, F-1/I-F1, M5.

---

## Step 4 — Scope / commit

No `sf/src` edit, no rewiring, no instrumentation, no seed build, no measurement. Only this report
(and the pre-existing ledger `progress.md` change) are committed with `git add -f`
(`docs: structural live-set plan — Task 1 interner analysis`). Branch `zig1_improvements`, **no push**.
Pre-existing untracked root strays (`anytype_pos.z98`, `fi.err`, `for_closed.z98`, `for_open.z98`,
`name_u65.z98`, `num_member.z98`, `q.err`, `sh.err`, `sz_u0.z98`) were left untouched.

## Concerns

1. **Interner alone is short of the gate.** Best realizable R1+R2+R3 ≈0.47 MiB; the gap is 1,040 K ≈1.0 MiB.
   Do not expect the Task 2 stop-gate to trigger on the interner package.
2. **R1 fallback/migration is the only non-trivial part.** Without it, inputs interning >65,535 strings
   would corrupt the bucket chain. The fix task must implement and reason about the wide path.
3. **R3 is data-dependent.** The corpus (not just main.zig) must be probed for max intern count before
   tightening the hint, or growth (which leaks into `perm`) can raise RSS.
4. **Counts are HEAD-dependent.** 34,020/125,798/62,899 are for the current `sf/src`; any source change
   shifts them by tens/hundreds. The fix task must re-derive from the new `INT:new` marker and
   re-measure RSS median ≥3.
5. **Page granularity** means a few KB of byte savings can round to 0 or to one 4 KB page; prizes are
   stated byte-level and page-rounded.
