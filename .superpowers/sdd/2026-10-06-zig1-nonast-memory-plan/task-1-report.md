# Task 1 — Decompose `diag_read` (READ-ONLY) report

Branch: `zig1_improvements` (NO push). Spike: no `sf/src` edits, no seed rotation, no dump-MD5
re-baseline. All probes were throwaway LD_PRELOAD shims + gdb scripts under `/tmp` (nothing in the
repo, nothing to revert). CWD for the self-compile: `/workspace/znineeight`, source arg RELATIVE
`sf/src/main.zig`.

Reference compiler (not rebuilt): `/tmp/nonast_seed/zig1_5_clean`, md5
`d40e875a7ba3aa55d441af56006f6023`.

## Step 1 — Exact retention model of `fault`

`diag_read` is the single `GrowableSand` named `"diag_read"` belonging to the process-wide
`SourceManager` (`sf/src/main.zig:191`; `sf/src/source_manager.zig:75-94`). It is the compiler's
*source fault-in* arena. `grep -rn diag_read sf/src` returns exactly one site:
`sf/src/source_manager.zig:157`.

**Object.** `SourceManager.fault: *alloc_mod.GrowableSand` (`source_manager.zig:78`). A
`GrowableSand` (`allocator.zig:17-22`) is an embedded first-segment header + `last` + `backing` +
a stable `Sand view`. It is backed directly by the global monotonic `pool` (`allocator.zig:249,262`),
never by another tier arena.

**Init.** Lazy, on the first fault (`source_manager.zig:156-160`):
`growableSandInit(self.fault, poolPtr(), 4096, "diag_read")`. This immediately carves the **first
4096-byte segment** from the pool (this initial segment does NOT emit an `arena grew` line —
`growableSandInit` calls `sandAlloc` directly). `fault_ready` is then set.

**Per fault (`sourceManagerFaultIn`, `source_manager.zig:148-192`).** Callers are only the
diagnostic span scanners (`diagnostics.zig:644,675,689` → `GetSourceContent`) reached from
`semantic_analyzer.zig:688,4447,5633` (ident-span / first-byte / last-byte lookups for `for` captures
and `switch` prongs). Once `file.loaded` is set (`line 155`) a file is never faulted again until a
reset. What is retained per faulted file:

| retained item | code | bytes |
|---|---|---|
| file text | `pal.readFile(file.filename, &self.fault.view)` (`source_manager.zig:161`) → `sandAlloc(view, ftell_size, 1)` + `fread` (`pal.zig:25-52`) | exactly the on-disk file size |
| per-file `U32ArrayList` header | `sandAlloc(&self.fault.view, 16, 4)` (`source_manager.zig:163`) | 16 |
| per-line offset array | `u32ArrayListEnsureCapacity(lo_ptr, line_count+1)` (`source_manager.zig:174`; `growable_array.zig:20-32`); then `Append(0)` + one `Append(i+1)` per `'\n'` (no realloc because capacity is pre-sized) | `4 * max(line_count+1, 8)` |
| allocator alignment | `sandAlloc` rounds `pos` up to the request alignment before adding size | ≤ 3 B before each 4-aligned alloc |

`line_count` is counted over `scan_len = min(file.len, content.len)` (`source_manager.zig:166-172`),
and `file.len` was set to the same `content.len` at `ModuleParseModule`/`AddFileTransient` time, so
`scan_len == content.len`. Net index size = `4*(newlines+1)` (min 8 words).

Failure branch (readFile returns null, `source_manager.zig:182-191`) retains only a 16-byte header +
`Append(0)` (8-word array) = 48 B; it was not taken in this run.

**Lifetime.** `fault` is never reset during a successful compile. `sourceManagerResetFaults`
(`source_manager.zig:194-202`) calls `sandReset` on the view (returning every segment after the first
to the shared cross-arena `seg_free_head` list, `allocator.zig:78-97`) and clears `loaded` on transient
files — but its only caller is `diagnosticCollectorPrintAll` (`diagnostics.zig:721`), which on this
clean run is reached once at the very end (`main.zig:436`, after lowering and C emission). Therefore
**all faulted bytes and all carved segment capacity are held from mid-analysis through emission**, i.e.
across the pool peak. After that single reset the process exits, so the freed segments are not reused.
(On a `HasErrors` run `PrintAll` can run earlier at `main.zig:376/384/390/397`, but not here.)

**Key observation.** The 100 warnings this compile collects are all printed with `file_id == 0`
(e.g. `warning[3037]: potential null pointer dereference`, no `file:line:col` prefix), so the final
`PrintAll` takes the `d.file_id == 0` fast path (`diagnostics.zig:727-744`) and never calls
`GetLocation`/`GetSourceContent`. Hence there is **exactly one fault round** (the analysis-time span
scanners) and **zero re-reads**: the retained source bytes are not even consulted again after the
scans that faulted them.

## Step 2 — Static byte/line sums and reconciliation vs 4,545K

Method: instrumented the unmodified compiler with a throwaway 32-bit `LD_PRELOAD` shim that logs every
`fopen(...,"rb")` with its return-address chain; mapped the addresses with `nm`/`addr2line`. Exactly
**43** `pal.readFile` calls come from `sourceManagerFaultIn` (addr1 offset `0x26a86d`), each a distinct
`sf/src/*.zig` file, in this order: main, allocator, string_interner, source_manager, diagnostics,
token, lexer, pal, parser, ast, util/itoa, util/path, module_registry, import_resolver, analyzer,
symbol_table, type_registry, c89_emit, lower, lir, lir_stream, resolved_type_table, util/hash,
growable_array, coercion, semantic_analyzer, type_resolver, comptime_eval, symbol_registrator,
const_alias_prepass, front_resolution, async_analysis, async_frame_layout, async_state_machine,
cinclude, spill_store, panic, util/format, util/mem, lir_opt_pass, state_map, tests/lexer_tests,
std_fmt.

- The self-compile reads **47** unique source modules; **43** are faulted. Not faulted:
  `emit_support.zig`, `extern_c.zig`, `name_mangler.zig`, `util/util.zig` (they never pass through the
  analyzer span-scanner paths). No std-lib file is faulted — all imports resolve inside `sf/src`.
- Static sums over the 43 faulted files: **text = 2,776,127 B**, **lines = 51,578**,
  **index = 206,484 B** (= `4*(51,578+43)`), **headers = 688 B** (43×16). Sum = 2,983,299 B.
- Adding allocator alignment padding (63 B over the 43 file triples) gives the exact live payload
  **2,983,362 B = 2,913.4 K**.

Cross-check (independent, gdb): breaking on `growableSandGrow` and reading the `diag_read` view's
`pos` at each growth reproduces the per-segment usage exactly, summing to 2,983,362 B:

| segment | capacity (B) | used (B) | unused tail (B) |
|---|---:|---:|---:|
| initial | 4,096 | 0 | 4,096 |
| 1 | 100,578 | 100,578 | 0 |
| 2 | 201,156 | 153,732 | 47,424 |
| 3 | 402,312 | 342,464 | 59,848 |
| 4 | 804,624 | 570,376 | 234,248 |
| 5 | 1,048,576 | 723,832 | 324,744 |
| 6 | 1,048,576 | 1,040,700 | 7,876 |
| 7 | 1,048,576 | 51,680 | 996,896 |
| **Σ** | **4,658,494** | **2,983,362** | **1,675,132** |

The `diag_read` carve Task 0 measured (Σ of `new` over the 7 `arena diag_read: grew` lines) is
**4,654,398 B = 4,545.3 K** (4,658,494 B including the un-logged initial 4096 segment).

**Reconciliation (the gap is real and is the headline):**
4,545.3 K carve = **2,913.4 K live payload + 1,631.9 K unused segment tail** (logged carve;
**1,635.9 K** including the 4,096 B un-logged first segment).
The carve overstates retained *bytes* by **~1,636 K (36%)**. This is not a measurement artifact: it is
the `growableSandGrow` sizing policy (`allocator.zig:118-157`) interacting with whole-file requests.
Each fault asks for a whole file (up to 597 K) plus its index; when that does not fit in the current
segment the arena takes `max(2*last_size, request)` (capped at 1 MiB) from the pool. Large requests
therefore abandon large tails (segment 5 wastes 325 K, segment 7 wastes 997 K), and the capacity is
never returned until the end-of-run reset. **The pool cost of `diag_read` is genuinely 4,545 K even
though only 2,913 K is live data.**

Payload split (`live = 2,913.4 K`): text **2,711.1 K (93.0%)**, line-offset index **201.6 K (6.9%)**,
per-file headers **0.7 K**. Top contributors:

| file | text B | lines | index B | live B |
|---|---:|---:|---:|---:|
| `sf/src/lower.zig` | 596,656 | 9,321 | 37,288 | 633,960 |
| `sf/src/c89_emit.zig` | 531,960 | 9,599 | 38,400 | 570,376 |
| `sf/src/semantic_analyzer.zig` | 425,201 | 6,739 | 26,960 | 452,177 |
| `sf/src/type_resolver.zig` | 134,978 | 2,466 | 9,868 | 144,862 |
| `sf/src/lir_opt_pass.zig` | 100,786 | 2,150 | 8,604 | 109,406 |
| `sf/src/main.zig` | 100,578 | 1,917 | 7,672 | 108,266 |
| `sf/src/parser.zig` | 98,582 | 2,159 | 8,640 | 107,238 |
| `sf/src/comptime_eval.zig` | 87,985 | 1,902 | 7,612 | 95,613 |
| `sf/src/type_registry.zig` | 75,344 | 1,410 | 5,644 | 81,004 |
| `sf/src/async_state_machine.zig` | 73,962 | 1,275 | 5,104 | 79,082 |
| …36 more files | 550,095 | 18,148 | 48,820 | … |

(Full 43-row table is reproducible from the log; the three giant files dominate, and the two largest —
`lower.zig`/`c89_emit.zig` — are exactly the requests that force segments 4→5→6.)

## Step 3 — Growth chronology and reset/reuse

Chronological position of the 7 `arena diag_read: grew` lines (stderr line numbers, clean `-s0` run
with `--markers`; all 42 arena grows total):

```
    1  scratch        4096 -> 100578        (startup)
    2-4 perm           4096 -> 502888 -> 1005776 -> 1048576
   46  module        4096 -> 8192            (import-resolution begin)
   53-8091 import_scratch 256 -> 12050/45121/98582/531960/596656/100786   (module parse phase)
13366-16869 module/scratch/type_db grows     (symbol-registration / type-resolution)
17519-17520 module   786432 -> 1048576 -> 1048576
17521  diag_read     4096 -> 100578          <-- first diag_read growth
17522  diag_read     100578 -> 201156
17623  diag_read     201156 -> 402312
17643  module        1048576 -> 1048576
17647  type_db       262144 -> 524288
17691  diag_read     402312 -> 804624
17753  diag_read     804624 -> 1048576
17778  diag_read     1048576 -> 1048576
17793  module        1048576 -> 1048576
17824  diag_read     1048576 -> 1048576      <-- last diag_read growth (peak set)
17837+ scratch       65536 .. 131072/262144  (emission phase; diag_read never grows again)
```

So `diag_read` is the **last** of the five arenas to grow and does so in one burst during semantic
analysis (stderr 17521–17824), *after* `perm`, `scratch`, `type_db` and `module` have already taken
their early/mid segments, interleaved with the final `module`/`type_db` segment growths. Its peak
(4,658,494 B capacity / 2,983,362 B live) is fixed at stderr line 17824 and is held unchanged through
the later emission-phase `scratch`/`module` growth (stderr 18246–18512), i.e. through the pool peak.

Reset/reuse (code, not just log): the arena is reset exactly once, at the end-of-run
`diagnosticCollectorPrintAll` → `sourceManagerResetFaults` (`main.zig:436` → `diagnostics.zig:721` →
`source_manager.zig:194`). `sandReset` returns segments 2…N to the global `seg_free_head`
(`allocator.zig:78-97`), so in a longer-lived process they would be reusable by any arena via
`popFreeBestFit` (`allocator.zig:159-191`); in this run the process exits immediately afterwards, so
there is **no reuse**. During the compile `diag_read` is not reset or reused.

## Concerns

1. **The 4,545 K figure is capacity, not live data.** Only **2,913 K** is live (`text 2,711 K +
   index 202 K`); **1,636 K (36%)** is unused segment tail caused by the `max(2*last, request)`
   growth policy with whole-file requests. Any optimisation that targets "4,545 K of retained source"
   should distinguish the two: (a) shrink/eliminate the 2,913 K payload, and/or (b) shrink the 1,636 K
   over-allocation (e.g. a right-sized segment for a known request, or faulting only the byte ranges
   the scanners actually need instead of a whole file).
2. **The retained source is never needed after the scans that fault it** (the emitted diagnostics all
   have `file_id == 0`), yet the arena is not reset until after C emission. A reset at the end of
   semantic analysis would return the segments to the free list before the emission phase, where
   `scratch`/`module` are still growing — but this is a live-code change and outside this spike.
3. **43 of 47 parsed modules are faulted; the faulting is a side effect of the analyzer span
   scanners**, not of diagnostics that are ultimately reported. The 4 non-faulted modules
   (`emit_support`, `extern_c`, `name_mangler`, `util/util`) simply never hit those paths.
4. **Measurement caveat / method.** Static reconciliation relies on the fault order and file sizes;
   the compiler may in principle fault a file twice if `sourceManagerResetFaults` were to run before
   analysis completes. It does not here (single reset at exit; 43 fault read-opens = 43 unique files).
   The LD_PRELOAD and gdb probes are throwaway `/tmp` artifacts; no `sf/src` file was modified.
5. The source tree read is the **current** worktree (`sf/src` at the measurement commit); because the
   analysis-time fault set is data-dependent, small future source changes can shift which modules are
   scanned and thus the carve by tens of KB.

## Commands used (evidence)

```
timeout 120 /tmp/nonast_seed/zig1_5_clean -s0 --markers --track-memory -o /tmp/nonast_t1_out6 sf/src/main.zig 2>/tmp/t1_stderr_clean.txt
# LD_PRELOAD read-open logger (return-address attribution): /tmp/t1_caller.c -> /tmp/t1_caller.so
# LD_PRELOAD offset logger + stderr interleave: /tmp/t1_off.c -> /tmp/t1_off.so
# gdb segment-usage probe: break zF_130612FB_growableSandGrow; read view->pos/end per grow
```

## Step 4 — Commit

Report committed with `git add -f` and message
`docs: non-AST memory plan — Task 1 diag_read decomposition` (only this report; `.superpowers/sdd/...`
is gitignored). No source files staged.
