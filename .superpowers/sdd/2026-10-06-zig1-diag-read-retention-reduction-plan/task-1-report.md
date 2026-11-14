# Task 1 — Analysis + L6 growth-rule design (READ-ONLY) report

Plan: `docs/superpowers/plans/2026-10-06-zig1-diag-read-retention-reduction-plan.md`
Spec: `docs/superpowers/specs/2026-10-06-zig1-diag-read-retention-reduction-design.md` (binding)
Branch: `zig1_improvements` (NO push). This task made **no `sf/src` edit**, no seed rotation, no
rebuild, no measurement. All findings are from reading the current source tree only.

Established (Task 0, not re-measured): `-s0` pool **19,274 K**; per-arena carve `module` 5,256 K,
`diag_read` 4,545 K, `scratch` 4,570 K, `import_scratch` 1,353 K, `perm` 2,497 K, `type_db`
1,008 K, `source` 0. `diag_read` carve = live 2,913 K (text 2,711 K + `u32` index 202 K + headers
0.7 K) + ~1,632 K segment tail; 43/47 modules faulted once, held to end-of-run; `diag_read` fired
only **7** `arenaGrew` lines (rest satisfied by cross-arena `seg_free_head` reuse).

---

## Verdict (up front)

- **L3 is confirmed and safe** as specified. Exact insertion: `sf/src/main.zig:775`-after, inside the
  `while (mi < mods.len)` body (`main.zig:746-776`), using `ctx.source_man` (`main.zig:103`) and the
  existing `sourceManagerResetFaults` (`source_manager.zig:194-202`). No analysis-time consumer holds a
  faulted file's `content`/`line_offsets` across the reset; print-time already re-faults.
- **L6 primary = R-c** (targeted small-request branch at `allocator.zig:127-131`). Secondary capture
  = **R-b** (lower the 1 MiB cap). Optional third = **R-a** (1.6× global multiplier). Exact-fit is
  rejected per operator ruling (re-tunes on every source change).

---

## Step 1 — L3 confirmation (file:line)

### 1.1 Exact insertion point

`phase_StaticAnalyzers` (`sf/src/main.zig:739`) iterates every module:

```
739: fn phase_StaticAnalyzers(ctx: *CompilerContext) void {
...
744:     var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
745:     var mi: usize = 0;
746:         while (mi < mods.len) : (mi += 1) {
747:             alloc_mod.sandReset(&ctx.alloc.scratch);
...
773:                 .source_file_id = mods[mi].source_file_id,
774:             };
775:             az_mod.runAllAnalyzers(&ac, ast_root);
776:         }      <-- INSERT HERE: ctx.source_man.sourceManagerResetFaults();
777: }
```

- Insertion statement: `ctx.source_man.sourceManagerResetFaults();` immediately after
  `sf/src/main.zig:775`, before the loop close at `:776`.
- Handle: `CompilerContext.source_man: *SourceManager` is defined at `sf/src/main.zig:103` and wired
  at `:321`. Zig method call on the pointer auto-derefs; the method signature
  (`source_manager.zig:194`) takes `self: *SourceManager`, so the call type-checks.
- When it runs: once per analyzed module, after all analyzers for that module have returned and while
  the stack-local `AnalyzerContext ac` (`:751-774`) is already dead (reconstructed next iteration).

### 1.2 What the reset does (mechanism)

`sourceManagerResetFaults` (`sf/src/source_manager.zig:194-202`):

```
194: pub fn sourceManagerResetFaults(self: *SourceManager) void {
195:     if (!self.fault_ready) return;
196:     alloc_mod.sandReset(&self.fault.view);
197:     var files_slice = sourceFileArrayListGetSlice(self.files);
198:     var i: usize = @intCast(usize, 0);
199:     while (i < files_slice.len) : (i += 1) {
200:         if (files_slice[i].transient) files_slice[i].loaded = false;
201:     }
202: }
```

- `sandReset` (`allocator.zig:78-97`) keeps the embedded first segment (4 KiB) and splices the rest
  onto the **global** `seg_free_head` (`:91-92`), making those segments reusable by *any* arena
  (`pool.peak` is monotonic, so this is what lowers future pool growth).
- `loaded=false` on every transient file is the invalidation: `sourceManagerFaultIn`
  (`source_manager.zig:155`, `:161`) re-reads and overwrites `file.content` (`:179`) and
  `file.line_offsets` (`:180`) before either can be read.

### 1.3 Precondition — every compiler-mode file is transient

- The only non-test add site is `sourceManagerAddFileTransient(reg.source_man, path_s, content)` in
  `moduleRegistryParseModule` (`sf/src/import_resolver.zig:16`). `moduleRegistryParseModule` is called
  from the import-resolution loop (`import_resolver.zig:92`) for every module in the import queue.
- The entry module is enqueued too: `phase_ImportResolution` creates it (`main.zig:478`) and
  `importQueueEnqueue(..., mod_id)` (`main.zig:479`); all modules therefore flow through
  `import_resolver.zig:16`.
- The non-transient `sourceManagerAddFile` (`source_manager.zig:96`) has exactly one caller,
  `sf/src/test_runner.zig:95` (test harness), which never runs in `zig1` compiler mode. Grep confirms
  no other production caller.
- Reset skips non-transient entries at `:200`, so even if a test path mixed them in, they would stay
  loaded (no dangling) — conservative.

### 1.4 Safety proof — no analysis-time consumer retains a prior module's slice

All faulted-file reads route through three accessors, each of which calls `sourceManagerFaultIn`
*before* returning and returns only offsets/value copies, never a cached slice:

| Consumer | Fetch | Fault path | Retention? |
|---|---|---|---|
| `diagnosticCollectorScanIdentSpan` (`diagnostics.zig:643-670`) | `sourceManagerGetSourceContent` (`:644`) | `source_manager.zig:219` | local `content`; returns `out_start/out_end` only |
| `diagnosticCollectorFindLastByte` (`:674-684`) | `sourceManagerGetSourceContent` (`:675`) | `:219` | local; returns `u32` |
| `diagnosticCollectorFindFirstByte` (`:688-697`) | `sourceManagerGetSourceContent` (`:689`) | `:219` | local; returns `u32` |
| `sourceManagerGetLocation` (`:233-253`) | inline `faultIn` (`:243`) | `:243` | local `offsets`; returns `Location` |
| `sourceManagerGetSourceContent` (`:213-221`) | inline `faultIn` (`:219`) | `:219` | returns slice owned by the fault arena |
| `sourceManagerGetLineOffsets` (`:223-231`) | inline `faultIn` (`:229`) | `:229` | returns slice owned by the fault arena |

Analysis-time call sites (semantic analyzer, all pass `self.source_file_id`, i.e. the module currently
being analyzed — `semantic_analyzer.zig:34`, set in `main.zig:773`):

- `semantic_analyzer.zig:688` → `diagnosticCollectorScanIdentSpan` (NthIdentSpan helper).
- `semantic_analyzer.zig:4447` (`FindFirstByte`) and `:4449` (`ScanIdentSpan`).
- `semantic_analyzer.zig:5633` (`FindLastByte`), `:5636` and `:5640` (`ScanIdentSpan`).

Every one consumes its `content` inside the same call frame and discards it on return. None stores a
`[]const u8` or `[]u32` into `AnalyzerContext`, the AST store, or the diagnostics list. The
diagnostics records (`diagnosticCollectorAdd`) store `file_id` + span offsets only — never a content
pointer. `AnalyzerContext ac` is stack-local and rebuilt each iteration (`main.zig:751-774`).

Direct `SourceFile.content`/`line_offsets` field reads exist only inside `source_manager.zig`, and all
are immediately preceded by a `faultIn` (`219`→`220`, `229`→`230`, `243`→`245`); after a reset,
`loaded=false` (`:200`) forces the `faultIn`'s re-read/overwrite before any such read.

**Therefore:** after `runAllAnalyzers` for module *mi* returns, no live reference to any faulted file's
`content`/`line_offsets` remains; the reset cannot leave a prior module's slice dangling. The prior
module's offsets recorded in diagnostics are integers, and are re-resolved from a fresh fault at print
time.

### 1.5 Print-time re-fault is already exercised

`diagnosticCollectorPrintAll` (`diagnostics.zig:718`) calls `sourceManagerResetFaults(self.source_manager)`
at `:721` **before** printing, then per diagnostic calls `sourceManagerGetLocation` (`:745`),
`sourceManagerGetSourceContent` (`:778`), and `sourceManagerGetLineOffsets` (`:779`) — each of which
re-faults via `source_manager.zig:219/229/243`. This exact reset→re-fault cycle already runs on every
diagnostic-printing invocation (including the `main.zig:376/384/390/397/405/436` sites). Adding the
same call per-module introduces no novel re-fault path; it only makes the existing end-of-run pattern
recur earlier.

**Step 1 verdict:** L3 is confirmed and safe as specified; precondition (all transient) holds; the
safety argument depends only on the accessor invariant in §1.4 and is gated by the byte-identical
battery in Task 2.

---

## Step 2 — L6 growth-rule design

### 2.1 Growth policy reading (`sf/src/allocator.zig:118-191`)

`growableSandGrow(gs, view, size)` (`:118-157`) decides the next segment:

```
119-126: if (gs.last.next) |next| { … advance to chained segment; no new carve }   // chain reuse
127:     var old_size: usize = gs.last.size;
128:     var new_size: usize = gs.last.size * 2;              // doubling
129:     var max_segment: usize = 1 * 1024 * 1024;            // 1 MiB cap
130:     if (new_size > max_segment) new_size = max_segment;
131:     if (size > new_size) new_size = size;                // exact-fit override
132-145: if (seg_free_head != null) { popFreeBestFit(new_size) → reuse; seg.size=new_size,
         seg.end=actual capacity; return; }                  // cross-arena reuse, no arenaGrew
146-156: carve new_size from backing (module arena) + SandSegment header; arenaGrew(old,new)
```

Notes that matter for L6:

- `new_size` is derived from the **active segment's natural size** `gs.last.size` (`:128`), *not* from
  the current fill. On free-list reuse, `seg.size` is re-baselined to the computed `new_size` while
  `seg.end` keeps the popped segment's real capacity (`:138-140`) — so a reused segment can hold more
  than `new_size`, and the next doubling step uses the re-baselined size, not the capacity.
- `size > new_size` (`:131`) is what turns a `readFile` of a big file into an **exact-fit** segment.
- `max_segment` is the single global knob (`:129`); the multiplier is the other (`:128`).

### 2.2 Fault allocations (`sf/src/source_manager.zig:161-178`)

```
161: pal_mod.readFile(file.filename, &self.fault.view)   // whole file: sandAlloc(sz) — pal.zig:43
163: sandAlloc(&self.fault.view, 16, 4)                  // U32ArrayList header
165: lo_ptr.* = u32ArrayListInit(&self.fault.view)
174: u32ArrayListEnsureCapacity(lo_ptr, cap)             // sandAlloc(4*cap) — growable_array.zig:25
175/177: u32ArrayListAppend …                            // may grow the index further
```

**Tail mechanism (confirms the spec's root cause):** for a file of size `S`, the ladder doubles
(4 K→8 K→…). At the rung where `2×last.size < S ≤` the next value, `:131` sets `new_size = S`
(exact-fit), so the content **exactly fills** the segment. The next request is the 16-byte header;
from `last.size = S` the policy computes `new = 2S`, capped to 1 MiB, and `16 ≪ new`, so it carves a
fresh ~1 MiB segment (`:128-129`, `:146-155`) that the ~`4×line_count` index barely touches. For the
measured `diag_read`, this is the **~1,632 K** tail; 7 `arenaGrew` events account for the 4,545 K
carve (large exact-fit content segments + 1 MiB capped tail segments; the rest is free-list reuse).

### 2.3 Candidate evaluation (R-a … R-e)

All numeric effects below are **predictions to be confirmed by Task 3 measurement**; per the spec's
blast-radius warning, `module`/`scratch`/`emission` are shared by the same `growableSandGrow` and must
be measured, not assumed.

#### R-a — multiplier 2.0 → 1.6 / 1.7 (global)
- **Exact edit site:** `sf/src/allocator.zig:128`, `gs.last.size * 2` → integer 1.6× (`* 8 / 5`) or
  1.7× (`* 17 / 10`). One line.
- **`diag_read`:** after the 600 K exact-fit segment, `new = min(1.6×600 K, 1 MiB) = 960 K` (vs
  1 MiB): tail ≈ 923 K vs ~990 K → saves only ~64–67 K/file (~7%). **Alone insufficient** (matches
  spec §L6).
- **`module`/`scratch`/`emission`:** every doubling step ~20% smaller; per-segment waste 50%→37.5%;
  more segments + `SandSegment` headers + free-list entries. Net pool effect is measurement-dependent.
- **Risk:** low edit risk; moderate measurement risk (global; segment-count growth). Capture-ready as
  an optional comparator.

#### R-b — lower the 1 MiB cap → 512 K / 256 K (global)
- **Exact edit site:** `sf/src/allocator.zig:129`, `1 * 1024 * 1024` → `512 * 1024` (or `256 * 1024`).
  One line.
- **`diag_read`:** after 600 K exact-fit, tail = `min(2×600 K, cap)` = **512 K** (or 256 K) → waste
  ~475 K (~220 K) vs ~990 K; directly halving/quartering the prize.
- **`module`/`scratch`/`emission`:** cap constrains growth; single requests > cap still exact-fit via
  `:131`, so large buffers are fine but force a new segment; medium allocations now carve many small
  segments → more headers/free-list churn. 512 K is the safer arm; 256 K is likely too aggressive.
- **Risk:** moderate (highest blast radius of the pair). Capture-ready as the secondary.

#### R-c — small-request branch (targeted) — **PRIMARY**
- **Exact edit site:** `sf/src/allocator.zig:127-131`. Rule shape (final code is Task 3's; `minimum`
  is tunable, proposed = first-segment size 4096):

  ```
  new_size = last.size * 2; cap to 1 MiB;
  if (size * 4 <= old_size) {          // request is small vs the active segment
      new_size = size + size / 2;      // ~1.6x request
      if (new_size < 4096) new_size = 4096;
  } else if (size > new_size) {
      new_size = size;                 // unchanged exact-fit
  }
  ```

- **`diag_read`:** header `size=16`, `old=600 K`: `16*4=64 ≤ 600 K` → new = `max(24, 4096)=4096`;
  then index `~37 K` vs `old=4096`: normal path → `new = max(8192, 37 K)=37 K`. Per-file extra tail
  ≈ 4 K, replacing ~1 MiB → removes the exact prize identified in §2.2.
- **`module`/`scratch`/`emission`:** fires only when a request ≤ ¼ of the active segment's natural
  size (small append after a large fill); ordinary incremental growth (`size` comparable to `last`)
  is untouched, so the global ladder is preserved except for those small-tail cases. Net effect must
  be measured; the branch itself can add one small segment in the header case.
- **Risk:** low-to-moderate. Under L3 the fault ladder starts from the 4 KiB first segment each
  module, so the branch's `old_size` basis is stable and the change is contained. Residual risk:
  if `module`/`scratch`/`emission` interleave big-then-tiny allocations, extra small segments appear.
- **Capture-ready:** yes — primary.

#### R-d — bounded 1.6× bucket ladder
- **Exact edit site:** `sf/src/allocator.zig:127-131` — replace per-multiplier growth with `new_size`
  rounded up to a fixed ladder of ~1.6×-spaced buckets; caps per-segment waste at 60%.
- **`diag_read`:** like R-a (≈960 K tail); global.
- **`module`/`scratch`/`emission`:** stable per-segment waste bound; bucket table adds complexity.
- **Risk:** global blast radius + implementation complexity; coverage ≈ R-a. Use only if R-c's branch
  proves unclean. Not capture-ready.

#### R-e — move/shrink the line index
- **Exact edit site:** `source_manager.zig`: add a second `GrowableSand` for header+index (init near
  `sourceManagerInit:86-92`; reset in `sourceManagerResetFaults:194-202`), allocate the 16 B header
  and `u32ArrayListInit` from it (`:163-165`), keep the whole-file read on `fault.view` (`:161`). Or
  L1: `:163-178` `u32` → `u16`/delta.
- **`diag_read`:** removes the header/index bytes from the fault arena, but the *next* file's content
  growth still doubles-with-cap, so medium files (`S ≤ 2×last`) retain a tail — it does **not** remove
  the general doubling tail. Structural (new arena + reset wiring + re-fault semantics).
- **L1 alone:** live ≤ ~103 K, ~0 pool-peak benefit; does not remove the growth tail. Deferred
  (Task 4, optional).
- **Risk:** structural/moderate. Not capture-ready for the goal.

### 2.4 Selection

- **Primary (capture-ready): R-c**, with `minimum = 4096` and ratio 1.6; the branch inserts at
  `allocator.zig:127-131` before the unchanged exact-fit override.
- **Secondary (capture-ready): R-b**, cap 512 K first (fall back to 256 K only if 512 K under-delivers
  and the battery holds).
- **Optional third (cheap global comparator): R-a**, 1.6× at `allocator.zig:128`.
- Task 3 therefore has **≥2 capture-ready candidates (R-c, R-b)** plus one free comparator (R-a);
  measure each variant's `-s0` pool + per-arena carve, keep the best, revert the losers so only one
  rule lands (plan Task 3 Step 1).

**Why exact-fit is rejected (operator ruling):** an exact-fit rule would have to derive the index's
final byte size, which is unknown until after the content scan (`source_manager.zig:168-178`) and is
proportional to the source's newline count. Encoding that size is data-dependent and must be
re-tuned whenever any source file changes — fragile and non-stable. R-c keys on a source-independent
ratio (`request` vs the current segment's natural size), so the rule remains valid across source
changes; it bounds the tail structurally rather than predicting an exact number.

**Step 2 verdict:** adopt R-c as the design rule; capture R-c + R-b in Task 3 (R-a optional), chosen
by measured per-arena carve + pool with the byte-identical battery; do not exact-fit.

---

## Concerns

1. **All L6 projections are unmeasured.** The 7-event `diag_read` carve and the cross-arena
   `seg_free_head` reuse mean the net pool delta from R-c/R-b is not analytically obvious (R-c can
   change the ladder base for subsequent content growth; L3 already re-bases each module). Task 3
   must measure `diag_read` **and** `module`/`scratch`/`emission` per candidate, exactly as the spec's
   blast-radius warning requires.
2. **L3's safety is an invariant proof, not a test.** It rests on every accessor re-faulting before
   return (§1.4). The byte-identical battery (corpus/goldens/stdlib/examples/`--markers`) is the
   enforcement; if any future consumer caches a content slice, L3 would silently break — worth a code
   comment at the insertion site in Task 2.
3. **`-o <dir>` must pre-exist** (Task 0 concern #1). Task 3's self-compile measurement must
   `mkdir -p` its output dir first.
4. **No source was edited, no build/measurement run** — Task 1 is strictly read-only per the brief.

## Files read (evidence)

`sf/src/main.zig` (`:103`, `:316-358`, `:456-514`, `:739-778`, `:376-436`),
`sf/src/source_manager.zig` (`:1-262`), `sf/src/import_resolver.zig` (`:1-129`),
`sf/src/allocator.zig` (`:1-359`), `sf/src/growable_array.zig` (`:1-48`),
`sf/src/diagnostics.zig` (`:630-831`), `sf/src/semantic_analyzer.zig` (`:34`, `:680-694`,
`:4438-4452`, `:5625-5643`), `sf/src/pal.zig` (`:25-52`), `sf/src/module_registry.zig` (`:360-409`).
