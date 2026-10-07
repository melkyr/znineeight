# Task 5 — Investigate the comptime fold table (READ-ONLY)

Plan: `docs/superpowers/plans/2026-10-07-zig1-structural-live-set-plan.md`
Spec: `docs/superpowers/specs/2026-10-07-zig1-structural-live-set-design.md`
Branch: `zig1_improvements` (NO push). This task made **no `sf/src` edit**, **no rewiring**, **no
new instrumentation**, **no seed build**, **no self-compile measurement**, and **no subagents**. All
counts below come from reading source at HEAD `da376da0` plus the **existing** frozen captures:

- `sf/src/comptime_eval.zig` (1,902 lines) — read end to end, plus `ComptimeVal`/`ComptimeInt`/
  `ComptimeFoldTable` and every consumer in `sf/src`.
- `sf/src/util/hash.zig` (`U32ToU32Map`), `sf/src/allocator.zig` (`Sand`/`GrowableSand`).
- `.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/allocation-census.md` — the gdb-probe
  cumulative `sandAlloc` traffic (the `comptimeFoldTableGrow` row: **module 1535.2K / 11 calls /
  1,572,096 B**), and the baseline per-arena carve.
- `.superpowers/sdd/2026-10-07-zig1-structural-live-set-plan/task-0-report.md` (per-arena carve) and
  `task-4-report.md` (post-Task-4 RSS 16,880 K; remaining gap ≈496 K).
- `/tmp/task1_markers.txt` — the pre-Task-2 `-s0 --markers --track-memory` capture (the `arena
  module: grew` segment ladder).
- `sf/src/tests/test_lower_bin.zig`, `sf/src/tests/test_semantic_bin.zig` (fold-table construction /
  `ComptimeVal` value copies).

Binding metric: **peak RSS** (`/usr/bin/time -v` Maximum RSS), median ≥3 interleaved `-s0`
self-compile. **Carve ≠ touched RSS** (only written/zeroed pages raise RSS). Every "resident prize"
below is stated as **resident at `-s0` (touched pages)**; carved-but-unwritten tails are labelled.

**Headline (the two answers the brief demands):**

1. **Value range.** Every folded value *stored* at self-compile fits in **≤64 bits (≤2 limbs)**; the
   256-bit `mag[8]u32` is dead weight for **all** stored entries. Static producer analysis (§1.4)
   shows the only ways to get a >64-bit stored value are `~` (a 256-bit complement), `<<` beyond
   bit 64, or an overflowing `*`/`+` — and **none occurs** in the 45-module self-compile closure. The
   full-width path must be *retained* for corpus/stdlib correctness, so the fix is a **narrow common
   case + a rare wide side pool**, not a hard 64-bit truncation.
2. **High-water verdict.** The fold table is **NOT a pure high-water non-lever**: it lives in the
   `module` arena, which is reset *after* lowering (`main.zig:407`), and the post-reset
   emission/`lir_read` phases **carve ~0 new pool bytes** (they reuse `seg_free_head`; the Task-0
   per-arena carve list has **no `emission`/`lir_read` row**). So the global pool high-water is set
   **pre-reset**, while the fold table is live — shrinking it can lower peak RSS. The win is
   **sub-linear**, however, because the `module` segment ladder is shared with the AST node buffers
   and `GrowableSand` doubles whole segments (Task-4 precedent: R1 projected 380–400 K, delivered
   ≈150–220 K). See §1.5.

---

## Step 1 — Exact layout, element sizes, counts, caps

### 1.1 `ComptimeInt` — 36 B; `ComptimeVal` — 48 B (`comptime_eval.zig:19-44`)

```zig
pub const ComptimeInt = struct {          // 36 B, align 4
    mag: [8]u32,   // 32 B  little-endian 256-bit magnitude, offset 0
    len: u8,       //  1 B  # of significant limbs (0 = zero), offset 32
    neg: bool,     //  1 B  sign (false when len==0), offset 33 (+2 pad) => 36
};

pub const ComptimeVal = struct {          // 48 B, align 8
    v: ComptimeInt,      // 36 B   offset 0
    kind: u8,            //  1 B   offset 36 (KIND_INT=0 / KIND_BOOL=1 / KIND_FLOAT=2)
    float_bits: u64,     //  8 B   offset 40 (8-align forces 3 pad bytes at 37..39)
};                        // 48 B
```

`kind` replaces the old width sentinel role; `float_bits` carries the f64 bit pattern for
`KIND_FLOAT` and is zero for INT/BOOL. `len`/`neg` are the *only* per-value metadata; signedness is
**not** stored (sign is `neg`).

On the **32-bit** seed target this is ABI-stable: `ComptimeInt` has no pointer/slice field, so
`@sizeOf` is 36/48 independent of `usize`.

### 1.2 `ComptimeFoldTable` (`comptime_eval.zig:46-99`)

```zig
pub const ComptimeFoldTable = struct {
    slots: hash_mod.U32ToU32Map,   // node_idx -> dense slot
    vals: [*]ComptimeVal,          // dense value array (48 B each)
    len: usize,
    capacity: usize,
    alloc: *alloc_mod.Sand,
};
```

- **`slots`** is `U32ToU32Map` (`util/hash.zig:23-30`): `keys:[*]u32` (4) + `values:[*]u32` (4) +
  `occupied:[*]u8` (1) = **9 B/slot**; open-addressed linear probe, load factor 3/4
  (`u32ToU32MapPut`, `util/hash.zig:107-120`).
- **`vals`** is a dense `ComptimeVal` array; growth is `comptimeFoldTableGrow` (`:70-81`):
  16→32→…→16384 (doubling, cap 16 B min), `sandAlloc` a **new** array, copy the live prefix, and
  **abandon the old array in the `module` arena**.
- `Put` (`:83-92`) is insert-or-**overwrite** (`self.vals[slot] = v` on hit); `Get` (`:94-99`) returns
  `?ComptimeVal` **by value**, guarding `slot < len`.
- Init (`:60-68`) uses the **zero-cap** `u32ToU32MapInit` and `capacity = 0`; everything grows
  geometrically from `main.zig:310` (`comptimeFoldTableInit(&compiler_alloc.module)`).

### 1.3 Self-compile counts and caps (existing captures only)

| quantity | value | source |
|---|---:|---|
| `comptimeFoldTableGrow` calls | **11** | census row (`comptime_eval.zig:75`) |
| `vals` cumulative carve | **1,572,096 B = 1,535.25 KiB** | `16·(2^11−1)·48`; census |
| `vals` final `capacity` | **16,384** | 11th grow |
| `vals` final live byte (carved) | **786,432 B = 768 KiB** | `16,384 × 48` |
| `slots` final live byte | **147,456 B = 144 KiB** | `16,384 × 9` (cap inferred) |
| **live total at cap** | **933,888 B = 912 KiB** | brief's ≈912 KiB; confirmed |
| `slots` cumulative carve (keys+values+occupied) | ≈**294,840 B** | `(4+4)·32760 + 1·32760`, geometric-to-16,384 |
| **live+abandoned carve** | ≈**1,866,936 B ≈ 1,823 KiB** | vals + slots |
| fold entry count `len` | **∈ [8,193, 12,288]** | 11 `vals` grows ⇒ `len > 8,192`; `slots` cap 16,384 ⇒ `count·4 < 16,384·3` |
| `@sizeOf` in closure | 172 | dominant fold producer (all u32-bounded) |
| `@alignOf / @offsetOf / @bitSizeOf / @bitOffsetOf` | 12 / 11 / 10 / 11 | u32/u64-bounded |

`len` is bounded, not measured directly: `vals` grew at `len == 8,192` (cap 8,192→16,384, the 11th
call) and never made a 12th call (cap stayed 16,384 ⇒ `len < 16,384`); the inferred `slots` cap of
16,384 requires `count ≤ 12,288` (at 12,289 the map grows to 32,768). So **≈8.2 K–12.3 K folded
values** at self-compile.

### 1.4 Value-range evidence — how many stored values need the 256-bit `mag[8]u32`?

The fold table is populated at exactly three sites in `phase_ComptimeEvaluation` (`main.zig:618-675`):

| arm | gate | `comptime_eval.zig` producer | result width |
|---|---|---|---|
| `builtin_call` (`main.zig:629-638`) | every builtin_call node folds | `comptimeEvalBuiltin` `:1304-1481` | see below |
| `var_decl` (`main.zig:639-651`) | `flags&1==0` (**`const`**; `parser.zig:1546-1547` bit0 = is_mutable) **and** init kind ∈ `{33..42,62,64}` = arithmetic `+ - * / % & \| ^ << >>`, `negate`, `bit_not` | `comptimeEvalEvaluateDepth` | arithmetic exact |
| `if_expr` no-else (`main.zig:652-672`) | capture-free, payload 0 | boolean fold | `KIND_BOOL` (0/1) |

Producer widths:

- **`int_literal` / `char_literal`** (`:1782-1785`) → `ciFromU64(astStoreIntValue(...))`. The AST
  stores literals as **u64** (`ast.zig:313,471`: `int_values` `elem_bytes = 8`). ⇒ **always ≤64 bits,
  `len ≤ 2`**.
- **`@sizeOf`** (`:1306-1315`) → `ciFromU64(ty.size)` where `Type.size: u32` (post-Task-4 `Type` is
  `size u32` at offset 0, `type_registry.zig:70-85`). **`@alignOf`** (`:1317-1325`) → `alignment: u8`.
  **`@offsetOf`/`@bitOffsetOf`** (`:1327-1370`) → u32 offset (×8 for bits). **`@bitSizeOf`**
  (`:1372-1400`) → `size×8` or `width_bits` (≤64). ⇒ **≤64 bits, mostly ≤32 bits.**
- **`@intCast` / `@as`** (`:1402-1465`) → returns the inner value unchanged (or masks to the target
  byte width `< 64` bits, `:1445-1458`). ⇒ **bounded by the inner expression.**
- **`@isWindows`** (`:1466-1469`) → bool. **`@intToFloat`/`@floatCast`** (`:1470-1479`) → `KIND_FLOAT`
  with `v = ciZeroInt()` (`len = 0`) and `float_bits: u64`.
- **`const` arithmetic** (`:1829-1834` → `comptimeEvalBinOp`): exact `ciAdd`/`ciSub`/`ciMul`/`ciDivMod`/
  `ciBitAnd/Or/Xor`/`ciShl`/`ciShr`; operand magnitudes are themselves ≤64-bit by the rules above.
  - `negate`/`~` (`:1789-1826`): `ciNeg` keeps ≤3 limbs; **`ciBitNot` always emits a full 8-limb
    (256-bit) complement** (`ciMagNot` `:311-317`, then `ciNormalize`).
  - `mul` of two u64 values and `shl` can exceed 64 bits in principle.

**Closure scan for the only >64-bit producers (`~`, `<<`, huge products):**

- `grep -rnE "=\s*~|const [A-Za-z_]+[^=]*=[^=]*~" sf/src/*.zig` → the **only** `const`-adjacent `~`
  is `c89_emit.zig:6875` `var clear_val: u32 = ~(win_mask << inbyte_lo) …`, which is a **`var`**
  (bit0 set) and therefore **skipped** by the `flags&1==0` gate. No module-scope or const
  `const … = ~ …` exists in the closure ⇒ **0 stored 256-bit complements.**
- Module-scope `const` shifts: none (all `<<` are inside functions / runtime `var`s).
- Module-scope products are small: `DEV_MAX_MEM = 16*1024*1024` (2²⁴), `RELEASE_MAX_MEM` (2²⁴),
  `PER_FUNC_BUDGET = 512*1024` (2¹⁹), `DEFAULT_MAX_MEM_KB = 64*1024` (2¹⁶) — **no product approaches
  2⁶⁴**; the observed pattern is size/offset composition (`@sizeOf(usize)*2` …).

**Conclusion.** At self-compile, **every stored `ComptimeVal` fits ≤64 bits (INT `len ≤ 2`), is a
bool, or is a float** ⇒ **0 values require the full `mag[8]u32`**. The 32-byte magnitude is pure
over-provision for the observed population. Because the compiler must stay exact on other inputs
(`~small`, `1 << 100`-class, the documented bounded divergences), the stored representation must
keep a **rare wide side path** — exactly the brief's leading lead.

*Caveat:* the exact value histogram cannot be measured here (no instrumentation permitted; no existing
marker records `ComptimeInt.len`). The evidence is a **static producer + literal-typing** argument,
which is complete for the `~`/shift/overflow classes that are the only routes to `len > 2`.

### 1.5 Arena wiring and the high-water crux (`allocator.zig:17-157`, `main.zig:310,407`)

- `comptime_folds` is allocated from **`compiler_alloc.module`** (`main.zig:310`), which is
  `mod_gs.view` — a `GrowableSand` over the monotonic `pool` (`allocator.zig:270-286`).
- `GrowableSand` growth (`growableSandGrow` `:118-157`) creates a **new segment** (`max(2·last, req)`,
  capped 1 MiB) from `pool`; the old segment stays in the chain. `sandAlloc` never zeroes, so only
  written pages of a segment are resident.
- **`sandReset(&ctx.alloc.module)` at `main.zig:407`** (the brief's F-FREE; moved from 401 by Task 4)
  runs **after `phase_LIRLowering`** and **before `phase_C89Emission`**. It splices the module chain
  (all but the first segment) into `seg_free_head` (`allocator.zig:78-97`).
- `pool.peak` is monotonic (the pool itself is never reset). A segment reused from `seg_free_head`
  emits **no** `arenaGrew` and carves no new pool bytes.
- **Task-0 per-arena carve** (`task-0-report.md`): `module 5,382,144 · diag_read 4,655,313 · perm
  2,558,152 · import_scratch 1,385,155 · type_db 1,032,192 · scratch 223,519 · source 0`. There is
  **no `emission` and no `lir_read` row** ⇒ in the self-compile the emission and LIR-stream phases
  carve **≈0 new pool bytes** — they run entirely out of `seg_free_head`/`scratch`.

**Verdict.** Since (a) `module` is the largest single carved arena (5.25 MiB), (b) it is only reset
*after* lowering, and (c) the post-reset emission phases add no new carve, the global `pool`/RSS
high-water is reached **while the module arena — and therefore the fold table — is live**. Bytes not
allocated into the fold table therefore do **not** raise the high-water, i.e. **shrinking the table
can lower peak RSS** (not a high-water non-lever). This is the opposite of the Task-3 "free caches
before emission" rejection: that argued *freeing later* cannot help a monotonic high-water; here the
lever is *never allocating* bytes that the high-water includes.

**Why the win is sub-linear (do not over-promise).** The `module` segment ladder is driven jointly by
the fold `vals` array and the AST node buffers (`AstNode` = 24 B; `astSlotEnsureNodeCap` cumulative
862.5 K module, `ast.zig:739`). The observed ladder steps `196,608 → 393,216 → 786,432 → 1,048,576`
match both `vals` caps (4,096/8,192/16,384 ×48 = 196,608/393,216/786,432) and AST node caps
(8,192/16,384/32,768 ×24). `GrowableSand` doubles whole segments and the freed segments are reused by
later phases, so part of any per-array saving is masked by the segment ladder — the exact
under-delivery Task 4 measured for the type registry (projected 380–400 K, delivered ≈150–220 K).

### 1.6 Consumers and by-value copy sites (the change surface)

**`ComptimeVal` is copied by value at every boundary:**

- **`comptimeFoldTablePut(self, node_idx, v: ComptimeVal)`** — the `v` argument is copied. Production
  call sites (3): `main.zig:637` (builtin arm), `main.zig:648` (var_decl arm), `main.zig:669`
  (if_expr bool arm).
- **`comptimeFoldTableGet(self, node_idx) ?ComptimeVal`** — returns by value. Production call sites
  (6, all in `lower.zig`): `:1623` (`foldPrintArgIntExact`), `:3430` (`foldNodeIntExact`), `:3505`
  (`comptimeFoldBool`), `:3520` (`lowerFoldedIntConst`), `:5764` (builtin fold materialisation —
  reads `.kind`, `.float_bits`, `.v`), `:8213` (inferred-local decl type choice — reads `.v`).
- **Helpers returning `?ComptimeVal`**: `lower.zig:1621` `foldPrintArgIntExact`,
  `lower.zig:3428` `foldNodeIntExact` (both also call `ce_mod.ciIntVal`, `:3438,3445`).
- **`comptime_eval.zig` internals**: `ciIntVal` `:276` (returns by value; called throughout),
  `ciBoolVal` `:280`, `comptimeEvalEvaluate`/`…Depth` `:1775/1779` (return `?ComptimeVal`),
  `comptimeEvalBuiltin` `:1304`, the float construction `:1477`, and `comptimeValStoreU64(cv:
  ComptimeVal)` `:1293` (by value).
- **Tests**: `test_lower_bin.zig:115` init; `test_semantic_bin.zig:52` `cvTestU64(v:
  ce_mod.ComptimeVal)`.

Consumers are **read-only** after `phase_ComptimeEvaluation`: they read `.kind`, `.v` (`ciIsZero`,
`comptimeIntFitsType`, `comptimeIntUntypedType`, `comptimeIntMaterialize`), and `.float_bits`. No
consumer retains a pointer into `vals`, and no consumer mutates a fetched value in place (all
`fv`/`cv`/`iv` are locals). The table is append-or-overwrite during the comptime phase and never
mutated during lowering. **This is the crucial mutation-safety fact** for any pointer/index design.

---

## Step 2 — Four lenses → ranked candidates

Common gate for every Fix: the Global-Constraints battery (corpus 923/58/116; goldens gol/lisp/json/
mud; `verify_stdlib` 266/0; examples 24/24; dump-MD5 8/8; semantic markers byte-identical IN-SESSION)
**plus RSS median ≥3**, the new fixed point recorded, and `--track-memory mod`/`pool` recorded.
Because the fold table is internal and never serialized, correct representation/narrowing changes are
output-byte-identical (only ids never change). The **aliasing analysis** is binding: the returned
`ComptimeVal` is always a value; a side pool must be addressed by **`u32` index** (never a pointer),
so growth cannot dangle a retained wide value (§1.6).

### R1 ★ — Narrow the common-case element 48 B → 16 B with a rare big-integer side pool

- **Mechanism.** Replace the inline `ComptimeInt` (36 B) in the dense `vals` array with a tagged
  16-B record:
  ```zig
  // vals element, 16 B (align 8)
  const FoldVal = struct {
      small: u64,     // int: low 64 magnitude bits (len<=2); float: f64 bits; bool: 0/1
      kind: u8,       // KIND_INT / KIND_BOOL / KIND_FLOAT
      neg: u8,        // int sign when small (needed: u64 two's complement is ambiguous for -1 vs u64max)
      wide: u8,       // 0 = small inline; 1 = small holds a u32 index into wide_ints
      _pad: u8,
  };                    // 16 B
  ```
  A rare side pool `wide_ints: [*]ComptimeInt` (36 B each) holds any value with `len > 2` (or a
  `KIND_FLOAT` that a future change wants out-of-line). `Get` reconstructs a `ComptimeVal` on demand:
  small ⇒ `ciFromU64`/sign; wide ⇒ copy `wide_ints[index]`.
- **Value-range evidence.** §1.4: **0 stored values need `len > 2` at self-compile**, so in practice
  the side pool is empty for the self-compile and the element is a flat 16 B; the pool exists only to
  keep `~`/`<<`/overflow-inputs exact (corpus/stdlib safety).
- **Sites.** `comptime_eval.zig:21-25` (keep `ComptimeInt` for the evaluator's stack scratch),
  `:40-44` (`ComptimeVal` becomes a transient reconstruction type or gains `toFold`/`fromFold`),
  `:52-58` (`vals: [*]FoldVal` + `wide_ints`/`wide_len`/`wide_cap`), `:70-81` (grow `vals` and the
  side pool), `:83-92` (`Put` encodes), `:94-99` (`Get` decodes). Call sites are unchanged in shape
  (Put/Get signatures keep `ComptimeVal` by value), so §1.6's 3+6+helper sites need **no edits**
  beyond recompilation — but each must be re-verified against the encoder/decoder.
- **Resident prize.** Element 48→16: **live (32 B × 16,384) = 524,288 B = 0.50 MiB**; cumulative
  carve **(32 × 32,752) = 1,048,064 B ≈ 1.0 MiB**. The 16-B ceiling at cap 16,384 is 262,144 B
  (0.25 MiB). RSS effect is discounted by the segment-ladder masking above (expect roughly half, i.e.
  **≈0.2–0.5 MiB**, cf. Task-4's measured under-delivery). No change to `slots`.
- **Risk.** **Med.** New encode/decode must preserve exact semantics for negative small ints
  (`neg` bit), zero-length (`-0` normalized to 0), `KIND_FLOAT` (`float_bits`), and bools; the wide
  path must be exercised by a targeted fixture (a `const`/module-scope `~` or `1 << 70`) **before**
  trusting the battery. Index-based side pool ⇒ no dangling. Fully expressible in the seed model.
- **Gate.** Common + a new wide-value fixture + markers byte-identical + `--track-memory mod`/`pool` +
  RSS median ≥3.

### R2 ★ — Pre-size (`right-size`) `vals` + `slots` to eliminate abandoned geometric generations

- **Mechanism.** `comptimeFoldTableInit` starts at cap 0 and doubles; the abandoned generations
  (`16+32+…+8,192` elements = 393,168 B of `vals`, plus ~147 K of `slots`) stay resident in the
  `module` arena until the reset. Seed both at (or near) their eventual capacity, using the
  **existing** `hash_mod.u32ToU32MapInitCap(alloc, hint)` (`util/hash.zig:39`, already used in
  emission and by Task-4 R1) and a new `comptimeFoldTableInitSized(alloc, hint)`.
- **Sites.** `comptime_eval.zig:60-68` (init), `:70-81` (keep doubling as the soft fallback),
  `main.zig:310` (thread a hint). Hint mirrors the landed interner/type-registry pre-size:
  `max(4096, source.len/8)` ⇒ self-compile ≈12,580 ⇒ `vals`/`slots` cap 16,384.
- **Resident prize.** No change to live bytes; **removes ≈933 KB of cumulative carve** (vals 785,664 B
  + slots ≈147,384 B). RSS effect again sub-linear (segment-ladder masking); **≈0.1–0.3 MiB**.
  `*InitCap` zeroes only `slots.occupied` (cap bytes, ≤ the abandoned occupied it replaces); `vals`
  is bump-allocated and **not zeroed**, so an unused tail is carved-but-not-resident.
- **Risk.** **Low–Med.** Soft floor only: an undershoot resumes doubling (correct, residual waste
  bounded); no output change. Data-dependent hint must be probed on corpus/stdlib like the other
  pre-sizes.
- **Gate.** Common + `--track-memory mod`/`pool` + RSS median ≥3.

### R3 — Drop `float_bits` out of the element (48 B → 40 B)

- **Mechanism.** Only `KIND_FLOAT` uses `float_bits`; floats are rare (only `@intToFloat`/`@floatCast`
  folds). Move the f64 into the same rare side pool as R1 (or a parallel float pool), leaving
  `ComptimeVal` = `ComptimeInt (36) + kind (1)` ⇒ padded to **40 B**.
- **Sites.** `comptime_eval.zig:40-44`, `:1477`, `:83-99`, and the read at `lower.zig:5814/5826`.
- **Resident prize.** **live (8 × 16,384) = 131,072 B = 0.125 MiB**; cumulative 262,016 B. Small.
- **Risk.** **Low.** It is a strict subset of R1's change; if R1 lands, R3 is subsumed. Only useful as
  a fallback if the full 16-B design is judged too risky.
- **Gate.** Common + float fixtures (`@intToFloat`/`@floatCast`) byte-identical.

### R4 — Narrow the `slots` map value column `u32` → `u16` (and/or merge the occupied array)

- **Mechanism.** `slots.values` holds a dense slot index `< 12,288 < 65,536`; a `U32ToU16Map`
  (keys 4 + values 2 + occupied 1 = 7 B/slot) saves 2 B/slot. This is a **column narrowing**, not the
  deferred interleaved-single-array hash-map restructure.
- **Sites.** `util/hash.zig` (new narrow map or generics), `comptime_eval.zig:53,62,84-90,95`.
- **Resident prize.** **live (2 × 16,384) = 32,768 B**; cumulative ≈65 K. Very small.
- **Risk.** **Low.** Slot ceiling 65,535 requires a fallback (entries could exceed it on huge input);
  keep the `u32` path.
- **Gate.** Common + markers byte-identical.

### R5 — Value interning / dedup (lens 1)

- **Mechanism.** Many folded nodes share a value (`@sizeOf(usize)`, small masks, bools). A
  value→index intern map with a dense unique-value pool would let `vals` shrink below `len`. But the
  keys become 16-B `FoldVal`s (hashing/flattening), and the intern map costs keys+occupied similar to
  the savings — and after R1 the values are already tiny. The dominant repeated value is bool
  (`len=0/1`) and small ints, which R1 already packs to 16 B.
- **Resident prize.** **Uncertain** (depends on the unknown unique-value count; estimated ≤
  `len/4` distinct, but not measured) — likely a few hundred KB at best, largely overlapping R1.
- **Risk.** **Med–High** (new value-keyed map; must hash the whole 16-B record exactly). Not funded
  ahead of R1/R2. Listed for completeness only.

### R6 — Store the dense slot directly in `AstNode` payload (lens 4) — REJECTED

- Removing `slots` (~147 K live) would need a per-node slot column. AST nodes are ~hundreds of
  thousands; `payload` is already used for value-pool indices (and I-COMPACT froze `AstNode` at 24 B).
  A node-indexed array is the explicitly closed **sparse→dense** direction and would be larger.
  **Rejected.**

### Rejected / not actionable (with reasons)

- **Sparse→dense `comptime_values` (closed lever).** Explicitly NOT re-opened. The fold table's
  `vals` is *already dense* with a **sparse index** (`slots`); R1/R2 keep that shape and only narrow
  the element. Nothing here densifies `comptime_values`.
- **16-B `AstNode` (I-COMPACT); F-1/I-F1; M5; prior S-INTERNER; deferred hash-map layout.** Untouched
  by any candidate. R4 narrows one map column and does not restructure map storage.
- **Free/reset the table before emission for RSS (lens 2).** Already done (`main.zig:407`); freeing
  *later* cannot lower a monotonic high-water (Task-1/Task-3 conclusion). The *lever* is not
  allocating the bytes at all (§1.5), which R1/R2 do.
- **Pointer-vs-inline with pointers into `vals`.** Rejected: `Get` returns by value and no consumer
  retains an interior pointer (`§1.6`); a pointer-based side pool would dangle when the side pool
  grows. Use **indices**.

### Four-lens verdicts

1. **Integer reuse / interning + redundant columns.** The only real redundancy is the over-wide
   inline magnitude (`mag[8]u32` for `len ≤ 2`) → **R1**; a derivable/sparse `float_bits` → **R3**;
   `slots` value over-width → **R4**. Value interning (**R5**) is weak once R1 packs the common case.
2. **One-use / retention.** The table is written during comptime eval, read-only during lowering,
   and reset at `main.zig:407`. Freeing later is a no-op for RSS; the actionable form is **not
   allocating** the abandoned generations (**R2**) and the dead magnitude bytes (**R1**). Verdict:
   the table is **on the pre-reset high-water** (§1.5), so it is a genuine (if sub-linear) lever.
3. **Representation.** Narrow the common case to ≤64 bits inline + rare wide side pool (**R1**);
   right-size the geometric arrays (**R2**); narrow the map value column (**R4**); drop the sparse
   float column (**R3**). Sparse→dense is closed and unnecessary (already dense values).
4. **Pointer vs inline, mutation safety.** The stored values are plain values and consumers never
   retain interior pointers; an **index-addressed** side pool is safe under growth; pointer-based
   side storage is rejected. R1/R3 are the only "indirection" and both use indices.

### Ranking and honest total

| rank | candidate | resident prize (live / cumulative carve) | confidence | risk |
|---:|---|---:|---|---|
| 1 | **R1** narrow element 48→16 + wide side pool | **0.50 MiB / ~1.0 MiB** (RSS ≈0.2–0.5 MiB) | Med | Med |
| 2 | **R2** pre-size `vals`+`slots` | 0 / **~0.93 MiB** (RSS ≈0.1–0.3 MiB) | Med | Low–Med |
| 3 | **R4** `slots` value `u32`→`u16` | 32 KiB / ~65 KiB | High | Low |
| 4 | **R3** drop `float_bits` (48→40) | 0.125 MiB / ~0.26 MiB (subsumed by R1) | High | Low |
| 5 | **R5** value interning | uncertain, overlaps R1 | Low | Med–High |
| — | R6 node-indexed slot column | — | — | **rejected** |

R1+R2 are **complementary** (pre-size the *narrowed* table): together they would place
`16,384 × 16 = 262,144 B` once instead of the current 1,866,936 B, a ~1.6 MiB carve reduction with a
0.5 MiB live reduction. The remaining gap after Task 4 is **≈496 K**, so R1 alone (if it delivers
even a third of its 0.5 MiB live prize) **plausibly reaches the 16,384 K stop-gate**. Task 6 must
measure honestly (median ≥3) and not claim the projection.

### Closed levers — explicitly NOT re-opened

- **Sparse→dense for `coercion` / `enum_value_table` / `comptime_values`** — **CLOSED** (sparse-wins;
  dense adds ~4.7 MB). No candidate densifies any of them; the fold table already has dense values.
- **16-B `AstNode` (I-COMPACT)** — **CLOSED** (byte-neutral/net-worse); the 16 B here is the fold
  *value*, not an AST node.
- **F-1/I-F1 free-list, M5, prior S-INTERNER scope, deferred hash-map layout** — untouched. R4 is a
  single-column narrowing, not the deferred interleaved-map restructure.

---

## Step 3 — Scope / commit

No `sf/src` edit, no rewiring, no instrumentation, no seed build, no measurement, no subagents. Only
this report (and the pre-existing `progress.md` ledger change) are committed with `git add -f`
(`docs: structural live-set plan — Task 5 comptime analysis`). Branch `zig1_improvements`, **no
push**. Pre-existing untracked root strays (`anytype_pos.z98`, `fi.err`, `for_closed.z98`,
`for_open.z98`, `name_u65.z98`, `num_member.z98`, `q.err`, `sh.err`, `sz_u0.z98`) left untouched.

## Concerns

1. **High-water benefit is real but sub-linear.** The fold table is live at the pre-reset peak
   (§1.5), so shrinking it lowers the high-water — but `GrowableSand` doubles whole segments and the
   `module` ladder is shared with the AST node buffers, so expect materially less than the byte
   prize (Task-4 precedent: 380–400 K projected → ≈150–220 K measured). Task 6 must not assume 1:1.
2. **`len` is bounded, not measured.** `[8,193, 12,288]` follows from the 11 `vals` grows and the
   inferred `slots` cap; it is not a direct marker. The Fix must re-derive or simply pre-size to
   16,384.
3. **Value-range evidence is static.** No existing marker records `ComptimeInt.len`; the "0 values
   need >64 bits at self-compile" claim rests on the exhaustive producer scan for `~`/shift/
   overflowing product. The wide side path (R1) must be exercised by a dedicated fixture
   (`const … = ~small` or `1 << 70` at module scope) so corpus/stdlib exactness is proven, not
   assumed.
4. **Copy-site blast radius.** Put (3) and Get (6) keep their signatures under R1, but the encoder/
   decoder in `comptime_eval.zig` and the `.float_bits` reads (`lower.zig:5814/5826`) must all agree;
   `ciIntVal`/`comptimeValStoreU64` and the two test binaries are the other `ComptimeVal` value
   boundaries (§1.6).
5. **R2's hint is data-dependent.** As with the interner/registry pre-sizes, probe the corpus/stdlib
   before fixing the hint; an undershoot only loses the saving, never correctness.
6. **Stop-gate may or may not fire.** Best realizable R1+R2 ≈0.3–0.8 MiB vs the ≈496 K gap. If R1
   lands near its live ceiling (0.5 MiB) the gate is likely met; if it under-delivers like Task-4 R1
   (<0.3 MiB), the plan proceeds to Task 7 without the target being met.
