# Task 1 — Allocation-savings census (READ-ONLY) report

Plan: `docs/superpowers/plans/2026-10-06-zig1-live-set-reduction-plan.md` (Task 1)
Spec: `docs/superpowers/specs/2026-10-06-zig1-live-set-reduction-design.md` (§Workstream 1, §Evidence)
Census: `allocation-census.md` (all 280 entry points + shortlist). **Fix round 1 applied** (see §Fix round 1).
Task 0 baseline: `task-0-report.md` (frozen HEAD `1bb72f62`).

Branch `zig1_improvements` (NO push). This task made **no `sf/src` edit**, **no seed rotation**, **no
dump-MD5 re-baseline**. All measurements used the frozen seed
`/tmp/liveset_seed/zig1_5_clean` (md5 `2293f756a8250351740cf6acde194d17`) and ran with CWD
`/workspace/znineeight`, RELATIVE source arg `sf/src/main.zig`. Throwaway probes live only in `/tmp`;
no root `.zig1_*.tmp` was created.

Binding metric = peak **RSS** (`/usr/bin/time -v`), with `pool`/carve as context. Baseline (Task 0):
pool 14,924K, RSS median 17,424K, carve module 5,382,144 / diag_read 4,655,313 / perm 2,558,152 /
import_scratch 1,385,155 / type_db 1,032,192 / scratch 223,519 B (Σ 15,236,475).

---

## Step 1 — Inventory of allocation entry points

### Closure definition

The `-s0` self-compile emits 48 `.c` (+ 48 `.h` + `build_target.sh`). Mapping emit-basename → source
(confirmed by symbol/import trace) gives the **45-module closure**:

```
allocator analyzer ast async_analysis async_frame_layout async_state_machine c89_emit cinclude
coercion comptime_eval const_alias_prepass diagnostics emit_support extern_c util/format
front_resolution growable_array util/hash import_resolver util/itoa lexer tests/lexer_tests lir
lir_opt_pass lir_stream lower main util/mem module_registry name_mangler pal panic parser util/path
resolved_type_table semantic_analyzer source_manager spill_store state_map string_interner
symbol_registrator symbol_table token type_registry type_resolver
```

(Not in closure: `main_dump`, `main_exp`, `strip_main`, `ast_dump_main`, `dump_*`, `test_main`,
`std_*.zig`, and the other `*/tests/*` — so `md5`-pin tools and the std lib are out of scope. Note
`lexer.zig:16` imports `tests/lexer_tests.zig`, so that test module *is* compiled into the binary;
its `runLexerUnitTests` is **not executed** on a normal compile — no "All lexer tests passed." on
stderr.)

### Enumerated classes and the site count

| entry-point class | count | grep/definition evidence |
|---|---:|---|
| `sandAlloc(` occurrences in closure | **215** | `grep -rn "sandAlloc" <closure>` (232 in all `sf/src`); 1 is the definition → **214 call occurrences** |
| distinct `sandAlloc` call lines | **211** | 212 grep lines, 1 is the `pub fn sandAlloc` definition, 3 lines hold two calls → 211 lines / 214 calls |
| `*ArrayList` struct types | **23** | 8 in `growable_array.zig`, 8 in `lir.zig`, 4 in `lower.zig`, 2 `module_registry`, 1 `source_manager` |
| `*ArrayList` ensure/grow allocator functions | **33** | `…EnsureCapacity`/`…Grow`/`arrayGrow`/`arrayListEnsureCapacityBytes` (incl. `ast.zig`'s 4 private `…AppendInner`) |
| `growableSandInit` **call** sites | **10** | `allocator.zig:272-276`, `import_resolver.zig:57/61/65`, `main.zig:200`, `source_manager.zig:158` (line 99 is the def) |
| `SpillStore`-bearing structs / `spillOpen` **call** sites | 5 / **7** | fields `ast.zig:325/372`, `lir_stream.zig:21`, `module_registry.zig:242`, `resolved_type_table.zig:23`; opens `ast.zig:546,706`, `lir_stream.zig:44,58`, `module_registry.zig:471,495`, `resolved_type_table.zig:78` |
| inline `[N]` buffer fields (non-zero) | **16** | 5 × `spill_path:[512]u8` field *declarations* (8 live buffers, see §2c), `buf:[4096]u8`, `la:[3]Token`, `mag:[8]u32`, `slots`, `slot_block`×2, `slot_dirty`, `note_ids`, `include_dirs`, `defer_label_stack`, `defer_label_isloop` |

**Verified total = 280 entry points** (214 `sandAlloc` call occurrences + 33 ArrayList allocator fns +
10 arena-ctor calls + 7 spillOpen calls + 16 inline `[N]` fields). The spec's "~249
`sandAlloc`/ArrayList sites" is in the right family: 215 + the ~52 ArrayList *ensure/grow call sites*
≈ 267. **Fix round 1 (findings 1, 8, 10):** earlier draft said 9 spill opens / 11 arena ctors / 14
inline fields (=282) — corrected to 7 / 10 / 16 (=280). **`spill_path` (finding 6):** `AstStore`
embeds `AstValuePool` **four times** (`ast.zig:337-360`), so `ast.zig:326` is instantiated 4×; plus
`AstStore.spill_path` (`ast.zig:373`) = **5 buffers in AST alone**; + `lir_stream.zig:22` (named
`path`) + `module_registry.zig:240` (`hash_spill_path`) + `resolved_type_table.zig:24` = **8 live
`[512]u8` buffers, 4,096 B total**, on `main`'s stack, touched once — no meaningful RSS.

### Measurement method (throwaway gdb probe)

`grep` gives the sites but not counts. I used a `/tmp` gdb-Python probe on the frozen binary
(`/tmp/alloc_probe.py`): break at `zF_1395EB68_sandAlloc`, read the hidden-sret args
(`[ebp+0xc]`=sand, `[ebp+0x10]`=size; `[ebp+4]`=return address; arena name at `sand+16/20`),
aggregate `(caller, arena, size) → (calls, bytes)`, dump at exit. **682,537 `sandAlloc` calls /
272,667,671 B cumulative** over one `-s0` self-compile. No `sf/src` file touched; probe artifacts in
`/tmp/` only.

**Validation (proves the probe is exact).** Probe cumulative per arena vs frozen prior measurements:

| arena | probe cumulative | reference |
|---|---:|---|
| `module` | 5,418.7K | == prior module max-live 5,419K |
| `diag_read` | 2,913.4K | == prior diag_read live 2,913.4K (Task 1 of non-AST plan) |
| `unknown` (the `pool`) | 14,924.5K | == `track-memory pool=14924K` |
| `perm` / `type_db` / `emission` | 2,132.7K / 907.0K / 1,011.7K | context |

For the never-reset arenas `module`/`perm`/`type_db`, cumulative churn == carved footprint; it equals
*nearly* all touched bytes, with one important **exception** (finding 5): arrays that are allocated in
full but only partially written have a **carved-but-not-touched tail** that raises pool but not RSS —
the string-interner entries array is the concrete case (pre-sized 62,861 × 16 B but only 34,020
written → ~461K carved-not-touched). For reset arenas (`scratch`, `lir_read`, `source`,
`import_scratch`, `diag_read`) cumulative is churn only.

---

## Step 2 — Per-site rows

The full 81-row per-entry-point table and the **211-row** direct-`sandAlloc` table are in
`allocation-census.md` (Tables 1–2). Table 2 records, per site, all five spec-mandated columns —
`file:line`/fn, owning arena(s), calls+bytes, **object+count**, **per-object overhead**,
**alloc+copy redundancy**, **over-sizing**, **live-vs-dead** — with `n/a` stated explicitly where a
column does not apply (fix round 1, finding 4). Headline per-class findings:

### 2a. Direct `sandAlloc` sites (211 lines) — dominant owners

| site(s) | arena | calls | bytes | class |
|---|---|---:|---:|---|
| `source_manager.zig:161` (`pal.readFile`) → text; `:163` header; `:174` index ensure | diag_read | 43 | 2,711.1K text + 201.6K index | retained live; **L3 present** |
| `lir_stream.zig:217,226,242,254,263,272,282-284` (`lirStreamReadFunction`) | lir_read | 363,692 | 154,990K | exact-fit, `sandReset` per fn → carve 0 |
| `c89_emit.zig:3195-3204,3241-3252,3285-3288` (`emitHoistedDecls`) | scratch (+24 emission) | 24,243 | 11,094K | per-function, scratch reset |
| `lower.zig:533-541,1937-1945` (local-decl arrays) | scratch | 14,868 | 3,098K | per-function, scratch reset |
| `lir_opt_pass.zig:2128-2148` (`allocU32Raw`/`allocU64Raw`/`allocU8Raw`/`allocU32With`) | scratch | ~92,000 | ~11,500K | per-function nest/DCE arrays |
| `ast.zig:551,592` (`valuePoolEnsureHead/Cache`) | module | 8 | 147.5K | AST value pool blocks |
| `module_registry.zig:384` (`pal.readFile` content hash) | import_scratch | 45 | 2,686K | transient exact-fit |

### 2b. `*ArrayList` ensure/grow allocators (33)

All use the same pattern: `new_cap = max(2*capacity, need)` (min 8), `sandAlloc`, copy old prefix,
**abandon** the old buffer. **Fix round 1 (finding 2):** the `sandTryReallocInPlace`-first attempt is
already used at **21 call sites** across the closure (not "four functions"):

```
source_manager.zig:40                symbol_registrator.zig:43
symbol_table.zig:49, 100             type_resolver.zig:200
ast.zig:154, 186, 216, 246           coercion.zig:57
diagnostics.zig:404, 581             growable_array.zig:72
lir.zig:575                          lower.zig:125
module_registry.zig:64, 106, 254, 561 parser.zig:579
spill_store.zig:120
```

(The reviewer recorded "17 sites"; the grep-verified count is 21 — the reviewer's own enumeration
sums to 21.) The shortlist rows 1–4,6 are the remaining doubling growers that still lack it. Selected
measured cost (scratch = transient):

| allocator fn | arena | calls | bytes |
|---|---|---:|---:|
| `lirInstArrayListEnsureCapacity` (`lir.zig:263`) | scratch | 49,775 | 38,537K |
| `tempDeclArrayListEnsureCapacity` (`lir.zig:389`) | scratch | 6,299 | 3,839K |
| `basicBlockArrayListInit` (`lir.zig:300`) | scratch | 3,144 | 1,964K |
| `lirSideEntryArrayListInit` (`lir.zig:214`) | scratch | 1,973 | 1,188K |
| `u32ArrayListEnsureCapacity` (`growable_array.zig:20`) | module/diag_read/emission | 78 | 473K |
| `astNodeArrayListEnsureCapacity` (`growable_array.zig:121`) | module/perm/emission/scratch/type_db | 217 | 261K |

### 2c. Per-object overhead (arena alignment pad + headers)

`sandAlloc` aligns `pos` up to the requested alignment before adding size (`allocator.zig:47-48`).
Observed requests are 4- or 8-aligned; the pad is ≤3 B (≤7 B for the 8-aligned `ComptimeVal` grow at
`comptime_eval.zig:75`) per allocation. The prior plan measured only **63 B** of total pad over all 43
`diag_read` file triples — alignment overhead is negligible. List *headers* are boxed at 16 B each
(`U32ArrayList` header = 16 B) and there are only tens of them.

### 2d. Alloc+copy redundancy (the dominant class)

Per-function churn for the never-reset arenas shows geometric doubling: a length-N list allocates
≈2N across its grow chain, so ≈N is **abandoned-but-carved**. Because the old buffer is read during
the copy it is **touched** (resident), and because `module`/`perm`/`type_db` are never reset during
analysis it stays resident through the pool peak. The largest such sites (measured cumulative):

| grow fn | arena | cumulative | abandoned (upper ≈ ½) |
|---|---|---:|---:|
| `u32ToU32MapGrow` (`util/hash.zig:66`) | module 1,763.7K + emission 367.5K + scratch 154.9K + perm 3.4K + type_db 0.5K | 2,289K | ~1,145K |
| `comptimeFoldTableGrow` (`comptime_eval.zig:70`) | module 1,535.3K | 1,535K | ~768K |
| `astSlotEnsureNodeCap` + `astSlotEnsurePayloadCap` (`ast.zig:739/755`) | module 862.5K + 143.8K | 1,006K | ~503K |
| `u64ToU32MapGrow` (`util/hash.zig:174`) | type_db 440.0K + module 207.8K + emission 207.9K | 856K | ~428K |
| `typeRegistryEnsureCapacity` + `arrayGrow` (`type_registry.zig:179/160`) | type_db 255.0K + 211.6K | 467K | ~233K |
| `coercionTableEnsureCapacity` (`coercion.zig:51`) | module 191.9K | 192K | ≤96K (in-place already) |
| `u32ArrayListEnsureCapacity` (`growable_array.zig:20`) | module 259.9K + diag_read 42.9K | 303K | ~150K |

### 2e. Over-sizing (capacity ≫ high-water)

- **String interner buckets** (`main.zig:188-190`; source-verified: 188 computes `interner_bc`, 189
  floors it, 190 calls `stringInternerInit`): `interner_bc = source.len + source.len/4` sized
  from **main.zig only** (`source.len` = **100,639 B** = `wc -c sf/src/main.zig`; finding 9) →
  100,639 + 25,159 = 125,798 buckets × 4 B = **503,192 B** (the probe's `stringInternerInit` first
  array), all **zeroed** (`string_interner.zig:84-87`) — every bucket page *touched*. Actual distinct
  strings = `INT:new34020` = 34,020; a load factor 0.5 needs ~68,040 buckets → **~57,758 excess
  buckets = ~231K touched**. (Cumulative `stringInternerInit` measured 1,474.2K including entries.)
- **Interner entries** (`string_interner.zig:93`): pre-sized to `bc/2 = 62,899` × 16 B = 1,006,384 B,
  but only `entries_len = 34,020` are written (544,320 B) → **~451K of the array is
  carved-but-not-touched** (pool-only, no RSS). This is the L3 lesson applied: carve ≠ touched.
- **`emitHoistedDecls`** (`c89_emit.zig:3189`): `max_temp` floors at **256** per function, so the 10
  DCE arrays (`3195-3204`) allocate (4+4+1+4+1+1+1+1+1+1)=**19 B** × 256 = **4,864 B (~4.75K) per
  function** even for tiny functions (finding 7; earlier draft miscomputed 23 B / ~5.9K) — 24,243
  calls / 11,094K across ~1.6k functions. Transient (scratch reset).
- **`local_name_ids`/`local_types`** (`c89_emit.zig:3241-3242`): floor 128 entries, doubles.

### 2f. Live-vs-dead (retained-after-last-read — the `diag_read` tail class)

Already addressed by the **L3 fix present in `sf/src`** (`sourceManagerResetFaults`,
`source_manager.zig:194-202`, called per module). Post-L3 `scratch` carve collapsed to 223,519 B
(reusing `diag_read`'s freed segments via `seg_free_head`). The residual `diag_read` live set is
**2,913.4K** (text 2,711.1K + line index 201.6K); the per-line `u32` index could shrink ≤101K live
(`u32→u16`/delta) but the prior L1 analysis bounds its **pool** prize at ≈0.

---

## Step 3 — Expected touched-RSS drop for the highest-value rows

The rewrite of the L3 lesson (`carve ≠ touched RSS`; only touched pages raise RSS) governs each
estimate. For **never-reset** arenas the abandoned grow buffers are touched during the copy and stay
resident, so their removal lowers RSS directly. For **reset** arenas the churn is already reclaimed
by `seg_free_head` reuse and is **not** an RSS lever — this is why `lir_read` (154,990K churn, 0
carve) and `scratch` (78,424K churn, 223K carve) are excluded despite huge churn numbers.

Highest-value rows, expected touched-RSS:

1. **Hash-map grow abandon** (`util/hash.zig:66,174`) — **one reconciled derivation (finding 3)**:
   `u32ToU32MapGrow` module 1,806,048 + emission 376,272 + perm 3,456 + type_db 504 + scratch
   158,616 = 2,344,896 B; `u64ToU32MapGrow` type_db 450,528 + emission 212,888 + module 212,784 =
   876,200 B; **full cumulative = 3,221,096 B (3,145.6K)**, 849 calls. Resident (drop the reset
   `scratch` term) = 3,221,096 − 158,616 = 3,062,480 B (2,990.7K); abandoned-only upper
   = resident/2 (geometric: allocated ≈ 2× final) = **1,531,240 B (1,495.4K)**; realistic
   **~0.5–0.9M**. Risk Med (overlaps prior **F-HASHMAP**). The earlier draft quoted 2,729.5K/~1,365K
   (census) and ~1,285K (report) — those mixed maps and dropped per-arena terms; the arithmetic above
   is the single source used in both files.
2. **`comptimeFoldTableGrow`** (`comptime_eval.zig:70`): 1,535.3K in module; `ComptimeVal` = 48 B;
   11 doublings from cap 16 → final 16,384 slots, cumulative 32,752 → **~768K abandoned, all
   touched**; realistic **~0.4–0.7M**. Risk Low–Med (allocation strategy only).
3. **AST head-slot growth** (`ast.zig:739,755`): 1,006.3K in module; `AstNode` = 24 B
   (`AST_BLOCK_NODE_BYTES 98304 = 4096*24`); ~503K abandoned; realistic **~0.25–0.4M**. Risk Med
   (AST spill window).
4. **Type-registry grow** (`type_registry.zig:160,179`): 466.6K in type_db; ~233K abandoned;
   realistic **~0.1–0.2M**.
5. **Interner bucket over-provision** (`main.zig:188-190`): ~231K **touched** (zeroed buckets);
   realistic **~0.2M**. Risk Low; overlaps exhausted **S-INTERNER**.
6. **Module `u32ArrayList` grow** (`growable_array.zig:20`): 259.9K module; ~130K abandoned;
   realistic **~0.1M**. Risk Low, generic helper.

The common mechanism (rows 1–4, 6) is: add the already-proven `sandTryReallocInPlace` first attempt
(`allocator.zig:219`) to the doubling grow functions that lack it. It wins when the buffer is the
arena tail; exact-fit sizing is the alternative. Neither changes emitted text.

**Deferred / disconfirmed (not levers, with the number):**

- `lir_read` churn 154,990K → **carve 0 at `-s0`**, `sandReset` per function
  (`lir_stream.zig:185`) + exact-fit arrays: no touched peak.
- `scratch` churn 78,424K → **carve 223,519 B post-L3**; segments reused via `seg_free_head`.
- `diag_read` text 2,711.1K + index 201.6K → **L3 already in `sf/src`**; index `u32→u16` ≤101K
  live, ~0 pool (prior L1).
- `import_scratch` 2,686K / `source` 2,790K churn → exact-fit, reset per import/module; prior L5
  disconfirmed (`module` reuses 1,276,415 B) → ≈0 pool.
- Inline `spill_path` buffers ×8 (4,096 B total), `buf:[4096]u8`, boxed headers (≤16 B each): no
  meaningful RSS.

---

## Step 4 — Shortlist + outputs

Written to `allocation-census.md` (Tables 1–2 + the "Shortlist" section). The shortlist rows carry
mechanism/sites, arena, measured cumulative bytes, abandoned-only upper bound, realistic touched-RSS,
risk, and the proving gate (corpus + goldens + stdlib + examples + 8/8 dump-MD5 + `median≥3`
pool/RSS). Top-3 by expected touched-RSS:

1. **Hash-map `…MapGrow` in-place/exact-fit** (`util/hash.zig:66,174`) — ~0.5–0.8M; risk Med.
2. **`comptimeFoldTableGrow` in-place/exact-fit** (`comptime_eval.zig:70`) — ~0.4–0.7M; risk Low–Med.
3. **AST head-slot growth in-place/exact-fit** (`ast.zig:739,755`) — ~0.25–0.4M; risk Med.

---

## Concerns

1. **Counts are per enclosing function, not per `sandAlloc` line.** The frozen binary carries no
   DWARF line info, so individual sites inside a multi-`sandAlloc` function (e.g. `emitHoistedDecls`,
   23 sites) share the aggregate; `addr2line` resolves symbols only. `allocation-census.md` Table 2
   flags shared rows. A per-line split would need a rebuilt `-g` instrumented compiler (out of scope
   for a spike).
2. **Cumulative churn ≠ footprint for reset arenas.** All churn tables overstate footprint for
   `scratch`/`lir_read`/`source`/`import_scratch`/`diag_read`; only `module`/`perm`/`type_db`
   cumulative equals carve. The shortlist is restricted to resident arenas accordingly.
3. **Abandoned ≈ cumulative/2 is a first-order upper bound.** It assumes pure geometric doubling and
   that every old buffer is truly dead; some grows are pre-sized via `…InitCap` and some maps use
   `sandTryReallocInPlace` already, so real reclaim is lower. Any fix task must measure the actual
   pool/RSS delta.
4. **Overlap with declared non-goals.** `u32ToU32MapGrow` overlaps prior **F-HASHMAP**; interner
   sizing overlaps **S-INTERNER**; segment-tail waste (module 1,084K / scratch 1,007K pre-L3) is the
   exhausted **M5** lever. The census reports them (Task 1 is exhaustive); Task 3 must decide whether
   they are already exhausted or have a new allocation-level angle.
5. **Data-dependent.** Which modules/args allocate most shifts with small `sf/src` changes; the probe
   numbers are for HEAD `1bb72f62`.
6. **`tests/lexer_tests.zig` is compiled into the production binary** (`lexer.zig:16`) and contributes
   code size (not runtime memory — its `runLexerUnitTests` is never called on a normal compile). Flagged
   as a dead-weight observation, not a memory-census row.
7. **No `sf/src` edit, no seed rotation, no committed probe.** Probe scripts remain in `/tmp`
   (`alloc_probe.py`, `run_alloc_probe.gdb`, `alloc_counts.txt`, `alloc_detail.tsv`). Only the two
   report files are staged with `git add -f`.

## Commands used (evidence)

```
# closure: emit and map
rm -rf /tmp/task1_out && mkdir -p /tmp/task1_out
timeout 120 /tmp/liveset_seed/zig1_5_clean -s0 --markers --track-memory -o /tmp/task1_out sf/src/main.zig

# enumerate
grep -rn "sandAlloc" <closure>
grep -rnE "const [A-Za-z0-9_]+ArrayList = struct" <closure>
grep -rn "growableSandInit\|spillOpen" <closure>

# measure (throwaway; 682,537 calls, 272,667,671 B)
timeout 300 gdb -batch -x /tmp/run_alloc_probe.gdb /tmp/liveset_seed/zig1_5_clean
```

---

## Fix round 1

Independent review returned **Spec ❌ / Needs fixes**. All 10 findings addressed below; `sf/src`
remains unmodified (READ-ONLY). Evidence commands are grep/`wc` against the frozen worktree.

**1 — SpillStore opens miscounted 9 vs actual 7 (Important).** Resolved. `grep -rn "spillOpen("`
(excluding the definition and comments) returns exactly **7** call sites: `ast.zig:546,706`;
`lir_stream.zig:44,58`; `module_registry.zig:471,495`; `resolved_type_table.zig:78`. Corrected in
`task-1-report.md` (site-count table + §2b) and `allocation-census.md` (§SpillStore opens). Total
entry points recomputed **282 → 280**.

**2 — "Four functions already call `sandTryReallocInPlace`" false (Important).** Resolved. Corrected
to the grep-verified count **21 call sites** and the full list is now quoted in
`task-1-report.md §2b` and `allocation-census.md §Shortlist`. (The reviewer's written "17" is a
miscount of their own enumerated list, which sums to 21.) Shortlist rows 1–4,6 remain the growers
that *lack* the attempt.

**3 — Top-lever byte estimate unreconciled (Important).** Resolved. One derivation is now used in both
files, with arithmetic shown inline (`task-1-report.md §3` row 1 and `allocation-census.md §Shortlist`
row 1): full cumulative **3,221,096 B (3,145.6K)** = `u32ToU32MapGrow` 2,344,896 + `u64ToU32MapGrow`
876,200; resident = 3,221,096 − 158,616 (scratch) = **3,062,480 B (2,990.7K)**; abandoned-only upper =
resident/2 = **1,531,240 B (1,495.4K)**; realistic **~0.5–0.9M**. The stale 2,729.5K/~1,365K/~1,285K
figures were removed.

**4 — Per-site required columns not populated (Important, binding spec violation).** Resolved.
`allocation-census.md` **Table 2** now has 211 rows, each carrying all five spec-mandated columns —
`object + count`, `per-object overhead`, `alloc+copy redundancy`, `over-sizing`, `live-vs-dead` —
alongside site/fn/arena/calls/bytes, with `n/a` written explicitly where a column does not apply
(e.g. single allocations show `n/a (single allocation)` and `n/a (fixed/exact request)`). Columns are
generated mechanically from the allocation expression, the alignment argument, the sibling ensure
class, and the owning arena. `task-1-report.md §Step 2` now points at the populated table.

**5 — Overbroad "never-reset cumulative == carved == nearly touched".** Resolved. Qualified in
`task-1-report.md` (validation table note) to add the **carved-but-not-touched tail** exception, with
the string-interner entries array as the concrete case (~451K carved, only 34,020/62,899 entries
written). The census already carried this; the report now agrees.

**6 — `spill_path` count / byte total.** Resolved. `AstStore` embeds `AstValuePool` **four times**
(`extra_children`, `identifiers`, `int_values`, `extra_ranges`; `ast.zig:337-360`), so the
`spill_path:[512]u8` at `ast.zig:326` is instantiated 4×; plus `AstStore.spill_path` (`ast.zig:373`)
= 5 in AST; + `lir_stream.zig:22` (`path`) + `module_registry.zig:240` (`hash_spill_path`) +
`resolved_type_table.zig:24` = **8 live buffers, 4,096 B**. Corrected in both files. Conclusion
(negligible RSS) unchanged.

**7 — `emitHoistedDecls` arithmetic.** Resolved. The ten `3195-3204` arrays are
4+4+1+4+1+1+1+1+1+1 = **19 B**, so 19 × 256 = **4,864 B (~4.75K)/function**, not 23 B/~5.9K. Fixed in
`task-1-report.md §2e`.

**8 — `growableSandInit` count.** Resolved. **10 call sites** + 1 definition (the 5 tier ctors
`allocator.zig:272-276`, `import_resolver.zig:57/61/65`, `main.zig:200`, `source_manager.zig:158`);
line 99 is `pub fn growableSandInit`. Corrected; total entry points 280.

**9 — Cite drift (interner lines, source length).** Resolved. `source.len` corrected **100,578 →
100,639 B** (`wc -c sf/src/main.zig`), and derived `interner_bc` 125,798, buckets 503,192 B, entries
62,899 × 16 = 1,006,384 B, excess ~231K. On the line range: source shows `main.zig:188` (compute),
`:189` (floor), `:190` (call); the report consequently keeps **188-190** and records that the
reviewer's "189-191" is off-by-one (verified against the source listing, which is authoritative).

**10 — Inline `[N]` count not reproducible.** Resolved. `grep -rnE "^\s+[A-Za-z_][A-Za-z0-9_]*: *\[[1-9][0-9]*\]"`
over the closure returns exactly **16** non-zero inline-array field declarations; the census table
now lists each row and the count is 16 (was 14). Total entry points 280.

Constraint checks re-run: `git show --name-only HEAD` contains no `sf/src` path (READ-ONLY held);
only `task-1-report.md` + `allocation-census.md` are staged with `git add -f`; no root `.zig1_*.tmp`
exists.
