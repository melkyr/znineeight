# 00 — Shared Infrastructure [updated: 2026-09-20 — refresh against the pool-backed growable-tier allocator, SourceManager fault-in, and config.zig/panic.zig coverage; line references and dated evidence removed]

> Covers: `allocator.zig`, `string_interner.zig`, `source_manager.zig`, `diagnostics.zig`, `pal.zig`, `growable_array.zig`, `panic.zig`, `config.zig`, `util/`
> Cross-ref: [INDEX.md](INDEX.md) §G (arena tier table)

## Summary

| Key | Value |
|-----|-------|
| Input | (none — shared infrastructure, called by all phases) |
| Output | N/A |
| Key structs | `Sand`, `GrowableSand`, `SandSegment`, `CompilerAlloc`, `StringInterner`, `DiagnosticCollector`, `SourceManager`, `U32ArrayList`, `U32ToU32Map`, `TrackingAllocator` (kept unwired) |
| Key functions | `sandAlloc`, `growableSandInit`, `stringInternerIntern`, `diagnosticCollectorAdd`, `sourceManagerGetLocation`, `markerWrite`, `panicHandler` |
| Markers | `INT:tl`, `INT:t0`, `INT:dup`, `INT:new` (from `stringInternerIntern`); `arena <name>: grew <old> -> <new>` (from `arenaGrew`) |

---

## 1. `allocator.zig` — Bump Arena Allocator

### Structs

**`Sand`** — Linear bump allocator state. Fields: `start` (base ptr), `pos` (current offset), `end` (byte length of the current backing region), `peak` (high-water mark), `name` (label for diagnostics/`arenaGrew`), `growable` (`?*GrowableSand`; non-null for a tier view so `sandAlloc` can grow). No free-list, no per-allocation metadata. [inference]

**`SandSegment`** — One growable-arena segment: `start` (base ptr), `size` (natural ladder size), `end` (segment byte capacity), `next` (segment chain link). [inference]

**`GrowableSand`** — Growable tier header: embedded `first: SandSegment`, `last: *SandSegment`, `backing: *Sand` (the pool that supplies new segments), and `view: Sand` (the stable `*Sand` held by consumers). [inference]

**`CompilerAlloc`** — 5-tier arena container. Holds five `Sand` instances: `permanent`, `module`, `scratch`, `lir_read`, `emission` + `max_mem` (u32 pool budget in KB). [inference]

**`TrackingAllocator`** — Wraps a `*Sand` (`arena`) with `total_allocated`, `peak_allocated`, `allocation_count` counters. **Kept but not wired into `CompilerAlloc`.** [inference]

**`TrackingAllocatorReport`** — Snapshot struct: `peak`, `total`, `count`. [inference]

### Static Buffer

A single 256 MiB static pool `memory_pool_buf[POOL_SIZE]` (`POOL_SIZE = 268435456`) backs all tier arenas. A module-level `Sand` `pool` is a monotonic bump allocator over it (never reset); the five tier arenas are `GrowableSand` views seeded from the pool, plus a cross-arena free list `seg_free_head`. This replaces the old three fixed-size static buffers. [inference]

### Constants

**`DEV_MAX_MEM`** = 16 MB, **`RELEASE_MAX_MEM`** = 16 MB — the `initCompilerAlloc` default `max_mem` (overridden by `main` from the parsed `--max-mem`/`-mm` value). **`DEFAULT_MAX_MEM_KB`** = 64 MB — the `--max-mem`/`-mm` CLI default pool budget. **`POOL_SIZE`** = 256 MiB. `checkCombinedPeak` compares `pool.peak` against `max_mem` KB (or the full pool when `max_mem == 0`). [inference]

### Function Walkthrough

| Function | Vis. | Purpose | Called By | Calls | Key Decisions | Markers |
|----------|------|---------|-----------|-------|---------------|---------|
| `sandInit` | pub | Initialize a `Sand` from a byte slice. Sets `start=buf.ptr`, `pos=0`, `end=buf.len`, `peak=0`, `name="unknown"`, `growable=null`. Adjusts peak if initial pos > 0. | `initCompilerAlloc`, test harness | (none) | Caller provides backing buffer; no malloc. | None [inference] |
| `sandAlloc` | pub | Allocate `size` bytes with `alignment` from arena. Aligns `pos` up to the boundary; if `new_pos <= end`, returns `start+aligned` and updates `pos`/`peak`. On overflow with a growable view, calls `growableSandGrow` and retries in the new segment; otherwise prints `used/new/total` and calls `panicHandler`. | any code that needs arena memory | `pal.stderr_write`, `printUsize`, `growableSandGrow`, `panic_mod.panicHandler` | Alignment via `(pos + mask) & ~mask`. Growable tiers retry; a pool-exhausted carve is fatal. | None [inference] |
| `sandReset` | pub | Reset `pos` to 0 without modifying `peak`. For a growable tier, recycles all segments after the first onto `seg_free_head` and restores the first segment as the active one. | phase transitions | (none) | Cheap; no free to the OS. | None [inference] |
| `growableSandInit` | pub | Seed a `GrowableSand`: allocate a `first_size` first segment from `backing`, set `first`/`last`, and build `view` with `growable` pointing back at the caller's `GrowableSand`. | `initCompilerAlloc`, `sourceManagerFaultIn`, `import_resolver.zig`, `main.zig` (`type_db_arena`) | `sandAlloc` | `view.growable` set after assignment (points at final location). | None [inference] |
| `growableSandGrow` | private | Advance a full tier to a larger segment: reuse the next chained segment after a reset, else best-fit pop from `seg_free_head`, else carve a new segment (doubling, capped at 1 MiB; exact-fit if the request is larger) plus a `SandSegment` node from `backing`, then call `arenaGrew`. | `sandAlloc` | `popFreeBestFit`, `sandAlloc`, `arenaGrew` | Capped doubling; free-list reuse; genuine new carves emit `arenaGrew`. | `arena <name>: grew <old> -> <new>` [inference] |
| `popFreeBestFit` | private | Pop the smallest free segment whose capacity ≥ the request from `seg_free_head`. | `growableSandGrow` | (none) | Cross-arena segment reuse after reset. | None [inference] |
| `arenaGrew` | pub | Emit the `arena <name>: grew <old> -> <new>` measurement marker when markers are enabled. | `growableSandGrow` | `pal.isMarkersEnabled`, `pal.measureMarkerWrite`, `writeUsizeExact` | Only fires on a genuine new carve. | `arena <name>: grew …` [inference] |
| `sandResetPeak` | pub | Set `peak = pos`. Effectively freezes the current high-water mark. | `phase_StaticAnalyzers` and per-function analyzer resets | (none) | Peak tracking separate from pos for diagnosis. | None [inference] |
| `sandTryReallocInPlace` | pub | Try to grow an allocation at the arena tail: returns `old_ptr` if `new_size <= old_size`; else if the allocation ends exactly at `sand.start + sand.pos` and the extension fits, bumps `pos`/`peak` and returns `old_ptr`; otherwise `null`. | growable collections (byte/source/diag/related-span/symbol/type/AST/LIR) | (none) | Tail-only; no copy fallback. | None [inference] |
| `sandReallocInPlace` | pub | Public alias for `sandTryReallocInPlace`. | callers wanting the documented name | `sandTryReallocInPlace` | Thin wrapper. | None [inference] |
| `poolPtr` | pub | Return `*Sand` for the backing pool (for `growableSandInit` callers). | `sourceManagerFaultIn`, `import_resolver.zig`, `main.zig` | (none) | Exposes the shared pool. | None [inference] |
| `poolPeak` | pub | Return `pool.peak` (the combined live high-water mark). | `--track-memory` reporting in `runCompiler` | (none) | Pool-level peak, not per-tier. | None [inference] |
| `initCompilerAlloc` | pub | Initialize the pool and the five tier arenas (`"perm"`, `"module"`, `"scratch"`, `"lir_read"`, `"emission"`), each seeded with a 4 KB first segment; set `max_mem = DEV_MAX_MEM`. | `main.zig` at startup | `sandInit`, `growableSandInit` | Tier names used in `arenaGrew`/OOM messages. One-time init. | None [inference] |
| `checkCombinedPeak` | pub | Compare `pool.peak / 1024` against the configured budget (`max_mem` KB; full `POOL_SIZE` when `max_mem == 0`). On excess, prints the limit and pool peak, then calls `panicHandler`. | `runCompiler` after phases | `printUsize`, `pal.stderr_write`, `panic_mod.panicHandler` | Pool-wide hard limit; `-mm0` relaxes to the whole pool. | None [inference] |
| `printUsize` | private | Format a `usize` as decimal into a 16-byte buffer, right-aligned to 15 chars, write to stderr. Used for OOM/memory-limit messages. | `sandAlloc`, `checkCombinedPeak` | `itoa_mod.itoa`, `pal.stderr_write` | Fixed-width right-aligned for readability. | None [inference] |
| `trackingAllocatorInit` | pub | Init `TrackingAllocator` with a Sand arena, zero counters. | (unwired) | (none) | Wraps existing Sand; no separate memory. | None [inference] |
| `trackingAlloc` | pub | Allocate via `sandAlloc`, then increment `allocation_count`, add `size` to `total_allocated`, update `peak_allocated`. | (unwired) | `sandAlloc` | Thin wrapper — same allocation path, just counting. | None [inference] |
| `trackingReset` | pub | Reset Sand AND zero `total_allocated`. Keeps `allocation_count` and `peak_allocated` as-is (historical). | (unwired) | `sandReset` | Partial reset — peak persists for reporting. | None [inference] |
| `trackingPeak` | pub | Return `peak_allocated` as u32. | (unwired) | (none) | Simple accessor. | None [inference] |
| `trackingAllocatorReport` | pub | Return `TrackingAllocatorReport` snapshot of peak, total, count. | (unwired) | (none) | Value copy, not pointer. | None [inference] |

### Data Flow — Allocator

```
initCompilerAlloc()
  │
  ├─ pool = sandInit(memory_pool_buf[0..POOL_SIZE])   ← monotonic, never reset
  ├─ permanent: growableSandInit(&pool, 4096, "perm")      ← never reset
  ├─ module:    growableSandInit(&pool, 4096, "module")    ← reset at lowering→emission
  ├─ scratch:   growableSandInit(&pool, 4096, "scratch")   ← reset per phase
  ├─ lir_read:  growableSandInit(&pool, 4096, "lir_read")  ← never reset
  └─ emission:  growableSandInit(&pool, 4096, "emission")  ← never reset

sandAlloc(sand, size, alignment):
  1. mask = alignment - 1
  2. aligned = (sand.pos + mask) & ~mask
  3. if (aligned + size <= sand.end):
       result = sand.start + aligned; sand.pos = aligned + size; update peak; return
  4. if sand.growable: growableSandGrow(...) and retry
  5. else OOM panic
```

Arena layout is strictly linear within a segment — no free, no coalesce. Reset (or advancing to the next segment) is the only reclaim mechanism; after reset, segments are recycled through the free list rather than returned to the OS.

---

## 2. `string_interner.zig` — FNV-1a String Interner

### Structs

**`InternEntry`** — Hash table entry. `text` (slice into arena), `hash` (FNV-1a), `next` (open-chaining link to next entry in same bucket). [inference]

**`StringInterner`** — Interner state. Separate arrays for buckets (`buckets_items: [*]u32`, bucket index → entry ID, plus `buckets_len`/`buckets_capacity`) and entries (`entries_items: [*]InternEntry`, plus `entries_len`/`entries_capacity`). Entry 0 is the sentinel (empty string, hash 0, next 0). Two `*Sand` allocator references: `entries_allocator` and `allocator` (both point to the same arena — permanent). [inference]

### Function Walkthrough

| Function | Vis. | Purpose | Called By | Calls | Key Decisions | Markers |
|----------|------|---------|-----------|-------|---------------|---------|
| `ensureCapacityBuckets` | private | Grow bucket array to at least `new_capacity`. Doubles on growth, min 8. Allocates via `sandAlloc`, copies old entries. | `stringInternerGrowBuckets` | `alloc_mod.sandAlloc` | Growth factor 2x, min 8. Raw memory, no initialization of new slots (caller handles). | None [inference] |
| `ensureCapacityEntries` | private | Same pattern but for `InternEntry` arrays. Element size = 16 bytes (text ptr + hash u32 + next u32 + padding). | `appendEntry` | `alloc_mod.sandAlloc` | Same 2x growth, min 8. | None [inference] |
| `appendBucket` | private | Ensure capacity for +1, then append `value`. | (now unused — `stringInternerInit` pre-sizes buckets) | `ensureCapacityBuckets` | Wraps ensure+store+increment pattern. | None [inference] |
| `appendEntry` | private | Ensure capacity for +1, then append `InternEntry`. | `stringInternerIntern` | `ensureCapacityEntries` | Wraps ensure+store+increment pattern. | None [inference] |
| `stringInternerInit` | pub | Create interner with `bucket_count` initial buckets. Pre-sizes buckets (4 B each, zeroed) and entries (16 B each) in single allocations instead of the growth chain; entry capacity is `max(bucket_count/2, 8)` to land near the load-factor 0.5 bound without growth. Entry 0 is the sentinel (empty string, hash 0, next 0). | `main.zig` setup, test harness | `alloc_mod.sandAlloc` | Entry 0 reserved as null/sentinel. All buckets initially empty. | None [inference] |
| `stringInternerIntern` | pub | Intern a string. Hash via `fnv1a`, find bucket, walk chain for match. If found, return existing ID. Otherwise: copy to arena, append entry (head-insert into bucket chain), grow buckets if load factor > 0.5. Emits markers for trace. | All phases needing string dedup. Called by `diagnosticCollectorAdd`, `diagnosticBuilderMakeMsg`, lexer/parser. | `hash_mod.fnv1a`, `mem_mod.mem_eql`, `stringInternerCopyToArena`, `appendEntry`, `stringInternerGrowBuckets`, `pal.markerWriteInt`, `pal.measureMarkerWriteInt` | FNV-1a hash. Open chaining. Bucket doubling at 50% load. String copied to arena (no original ref kept). Grows to 8 buckets if started empty. | `INT:tl` (text len), `INT:t0` (first char), `INT:dup` (existing ID) via `markerWriteInt`; `INT:new` (new ID) via `measureMarkerWriteInt` [inference] |
| `stringInternerGet` | pub | Lookup interned string by ID. Indexes into entries array, returns `entry.text`. ID 0 returns the empty-string sentinel. | `diagnosticBuilderMakeMsg`, `type_resolver.zig`, `analyzer.zig`, `symbol_registrator.zig`, import resolver | (none) | O(1) lookup. | None [inference] |
| `stringInternerCopyToArena` | private | Copy string bytes into arena (byte-level alignment=1). Returns raw ptr. | `stringInternerIntern` | `alloc_mod.sandAlloc` | Byte copy, no null terminator. | None [inference] |
| `stringInternerGrowBuckets` | private | Set `buckets_len=0`, ensure capacity for `new_bucket_count`, zero all buckets, then walk entries 1..N, computing new bucket index = hash % new_count, setting entry.next to current bucket head and bucket head to entry ID. | `stringInternerIntern` (when load > 0.5) | `ensureCapacityBuckets` | Full rehash of all entries. Old bucket array leaked (arena allocated, never freed). | None [inference] |

### Data Flow — Interning

```
stringInternerIntern("foo"):
  1. hash = fnv1a("foo")           -- 32-bit FNV-1a
  2. if buckets_len == 0 → grow to 8 buckets
  3. bucket = hash % buckets_len    -- index into bucket array
  4. Walk chain: entries[buckets[bucket]].next...
  5. If match (hash + mem_eql) → return existing ID
  6. If no match:
     a. Copy "foo" to arena via sandAlloc
     b. appendEntry with .text=copied, .hash=hash, .next=current bucket head
     c. buckets[bucket] = new entry ID
     d. If (entry_count * 2 > bucket_count) → grow buckets (double + rehash)
  7. Return new entry ID
```

---

## 3. `diagnostics.zig` — Error/Diagnostic Reporting

### Types

**`DiagnosticLevel`** — `enum(u8)`: `err_lvl=0`, `warning=1`, `info=2`, `note=3`. [inference]

**`ErrorCode`** — `enum(u16)` with 70 error/warning/info members. Most auto-increment from 0; the newer members pin explicit numeric discriminants (e.g. `ERR_3008_...=3008` … `ERR_3050_ARRAY_SIZE_NOT_CONSTANT=3050`). Members are named `ERR_`/`WARN_`/`INFO_` with a phase-ish numeric label, but the label is a naming convention, not the discriminant (e.g. `ERR_2000_UNEXPECTED_TOKEN` auto-increments to 8). [inference]

**Numeric constants** — 10 members re-exported as standalone `u16` constants: `ERR_1000..ERR_1005` (0..5), `WARN_1010` (6), `WARN_1011` (7), `ERR_3045_UNKNOWN_CALLING_CONVENTION` (3045), `ERR_3017_SUSPENDING_FUNCTION_POINTER` (3017). These expose the raw numeric code passed as `code`. [inference]

**`Diagnostic`** — Single diagnostic. Fields: `level` (u8), `code` (u16), `file_id` (u32), `span_start/span_end` (u32 byte offsets), `message_id` (u32 — interned string), `note_count` (u8, max 3), `note_ids` ([3]u32), `related_span_idx` (u16 — into `Collector.related_span_items`). [inference]

**`RelatedSpan`** — Secondary source location for a diagnostic. Fields: `span_file_id`, `span_start`, `span_end`, `message_id`. [inference]

**`MAX_DIAGNOSTICS`** — 256 (`usize`). Hard cap; overflow triggers ERR_9999. [inference]

**`DiagnosticArrayList`** — Dynamic array of `Diagnostic` on a Sand arena. Fields: `items`, `len`, `capacity`, `allocator`. [inference]

**`DiagnosticCollector`** — Central diagnostic hub. Holds `*DiagnosticArrayList`, `related_span_items` (raw dynamic array of `RelatedSpan`), `*Sand` allocator, `*SourceManager`, `*StringInterner`, `error_count`/`warning_count` (`usize`), `max_diagnostics`, and the per-node dedupe set `diag_seen_items`/`diag_seen_len`/`diag_seen_cap`. [inference]

### Function Walkthrough

| Function | Vis. | Purpose | Called By | Calls | Key Decisions | Markers |
|----------|------|---------|-----------|-------|---------------|---------|
| `getLevelName` | prv | Map level u8 → string: 0="error", 1="warning", 2="info", 3="note", else="unknown". | `diagnosticCollectorPrintAll` | (none) | Switch over u8. | None [inference] |
| `formatU32` | prv | Write decimal representation of u32 into buf (right-aligned). Returns character count. | `diagnosticCollectorPrintAll` | (none) | Manual ascii conversion, right-aligned. | None [inference] |
| `writeStr` | prv | Shorthand for `pal.stderr_write(s)`. | `diagnosticCollectorPrintAll` | `pal.stderr_write` | Pure delegation. | None [inference] |
| `compareDiag` | prv | Compare two `Diagnostic` by file_id, then span_start, then level. Returns i32 difference. | `sortDiagnostics` | (none) | Insertion sort comparator. | None [inference] |
| `sortDiagnostics` | prv | Insertion sort diagnostics array by file/span/level. | `diagnosticCollectorPrintAll` | `compareDiag` | Stable-ish (insertion sort). Sorts before printing for grouped output. | None [inference] |
| `diagnosticArrayListInit` | pub | Init empty `DiagnosticArrayList`, zero len/capacity, undefined items pointer. | `diagnosticCollectorInit` | (none) | Arena allocation lazily. | None [inference] |
| `diagnosticArrayListEnsureCapacity` | pub | Grow Diagnostic array. 2x growth, min 8. Tries `sandTryReallocInPlace` first, else `sandAlloc(@sizeOf(Diagnostic) * new_cap, 4)` + copy. | `diagnosticArrayListAppend` | `alloc_mod.sandTryReallocInPlace`, `alloc_mod.sandAlloc` | Aligned to 4 bytes; tail-realloc fast path. | None [inference] |
| `diagnosticArrayListAppend` | pub | Ensure capacity for +1, store value at `items[len]`, increment len. | `diagnosticCollectorAdd` | `diagnosticArrayListEnsureCapacity` | Standard append. | None [inference] |
| `diagnosticArrayListGetSlice` | pub | Return `items[0..len]` as `[]Diagnostic`. | `diagnosticCollectorPrintAll` | (none) | Returns slice of live data. | None [inference] |
| `diagnosticCollectorInit` | pub | Init collector. Allocates `DiagnosticArrayList` on arena (16 bytes, 4-aligned). Takes `*SourceManager` and `*StringInterner`. Counts start at 0, `max_diagnostics=MAX_DIAGNOSTICS`, dedupe set empty. | `main.zig` setup | `alloc_mod.sandAlloc`, `diagnosticArrayListInit` | DiagnosticArrayList heap-allocated (pointer stable). | None [inference] |
| `diagnosticCollectorIntern` | pub | Convenience: intern a string via the collector's interner. | places that want to intern via collector | `interner_mod.stringInternerIntern` | Thin delegation. | None [inference] |
| `diagnosticCollectorAdd` | pub | Add a diagnostic. If `code==9999` (ERR_TOO_MANY_ERRORS), early return 0. If overflow (`len >= max_diagnostics`), emits ERR_9999 with overflow message. Otherwise: intern message, append Diagnostic, increment error/warning count. Returns diagnostic index. | All phases that report errors/warnings | `interner_mod.stringInternerIntern`, `diagnosticArrayListAppend` | Overflow protection (ERR_9999). Returns index for note/related-span attachment. | None [inference] |
| `diagnosticCollectorHasErrors` | pub | Return `error_count > 0`. | `runCompiler` phase checks | (none) | Quick check for abort/continue decision. | None [inference] |
| `diagnosticCollectorErrorCount` | pub | Return `error_count` as u32. | reporting | (none) | Trivial accessor. | None [inference] |
| `diagnosticCollectorWarningCount` | pub | Return `warning_count` as u32. | reporting | (none) | Trivial accessor. | None [inference] |
| `diagnosticCollectorMarkNodeOnce` | pub | Per-node "already diagnosed" guard: linear scan of `diag_seen_items`; returns false if present, else records `node_idx` (growing the set, min 16, 2x) and returns true. | `type_resolver.zig` (array-size `ERR_3050` diagnostic) | `alloc_mod.sandAlloc` | Dedupes a node diagnosed by more than one resolution pass (e.g. front_resolution then sema/type resolution). | None [inference] |
| `diagnosticCollectorAddNote` | pub | Add a note (max 3) to existing diagnostic. Interns note text, stores in `note_ids[]`. No-op if `diag_idx` out of range or `note_count >= 3`. | phases that want to attach notes | `interner_mod.stringInternerIntern` | Bound check on diag_idx and note_count. Silent discard if full. | None [inference] |
| `diagnosticCollectorAddRelatedSpan` | pub | Attach a related source span to a diagnostic. Interns message, grows `related_span_items` (2x, min 8; `sandTryReallocInPlace` fast path), appends RelatedSpan, sets `diagnostic.related_span_idx`. | phases wanting secondary locations | `interner_mod.stringInternerIntern`, `alloc_mod.sandTryReallocInPlace`, `alloc_mod.sandAlloc` | Own arena-based dynamic array (not wrapped in ArrayList struct). Manual growth w/ 2x factor. | None [inference] |
| `diagnosticCollectorFlushAndExit` | pub | Print all diagnostics, then `pal.exit(exit_code)`. | fatal error paths | `diagnosticCollectorPrintAll`, `pal.exit` | Combines print + exit. | None [inference] |
| `diagnosticBuilderMakeMsg` | pub | Build a concatenated message from multiple parts. Allocates contiguous buffer on interner's arena, copies all parts, interns the result, returns interned string. Falls back to `"diagnostic message too long"` on OOM. | diagnostics that construct messages from parts | `alloc_mod.sandAlloc`, `interner_mod.stringInternerIntern`, `interner_mod.stringInternerGet` | Concatenates parts into arena buffer, then interns. Returns interned ID (looked up by string). Two allocations: temp buf + intern copy. | None [inference] |
| `diagnosticCollectorPrintAll` | pub | Main diagnostic printer. Resets faulted-in source, sorts diagnostics (file/span/level). For each diag: if file_id==0 prints "level[code]: message". Else: prints `file:line:col: level[code]: message`, then source line + caret underline under span, then notes, then related span. | `diagnosticCollectorFlushAndExit`, explicit calls | `sm_mod.sourceManagerResetFaults`, `sortDiagnostics`, `diagnosticArrayListGetSlice`, `getLevelName`, `formatU32`, `writeStr`, `sourceManagerGetLocation`, `sourceManagerGetFileName`, `sourceManagerGetSourceContent`, `sourceManagerGetLineOffsets`, `mem_mod.binary_search` | Sorts before printing. Printer has source context rendering with carets. Fixed-width code formatting. Caret buf capped at 256. Binary search for line from offset. | None [inference] |
| `typeKindSrcStr` | pub | Map `TypeKind` → source-level type string (e.g., `"source: i32"`). Used for diagnostic messages about source types. | diagnostic message construction | (none) | If-else chain over all TypeKind variants. | None [inference] |
| `typeKindTgtStr` | pub | Map `TypeKind` → target-level type string (e.g., `"target: i32"`). Mirror of `typeKindSrcStr` with "target:" prefix. | diagnostic message construction | (none) | Same pattern as src variant. | None [inference] |

### Data Flow — Diagnostics

```
diagnosticCollectorAdd(level, code, file_id, span, message):
  1. if code == 9999 → return 0 (no double-overflow)
  2. if diagnostics.len >= max_diagnostics → emit ERR_9999, return
  3. msg_id = stringInternerIntern(interner, message)
  4. diagnosticArrayListAppend(Diagnostic{.level, .code, .file_id, .span, .message_id=msg_id, ...})
  5. if level==0 → error_count++; if level==1 → warning_count++
  6. return diagnostic index

diagnosticCollectorPrintAll:
  1. sourceManagerResetFaults(source_manager)
  2. sortDiagnostics(diags)
  3. for each diag:
     a. if file_id==0: "level[code]: message"
     b. else:
        - loc = sourceManagerGetLocation(file_id, span_start)   // faults the file in
        - fname = sourceManagerGetFileName(file_id)
        - print "fname:line:col: level[code]: message"
        - print source line (via content + line offsets)
        - print caret underline (^^^^) under span
        - print notes (up to 3)
        - print related span (if any)
```

---

## 4. `source_manager.zig` — Source File Manager

### Structs

**`SourceFile`** — Per-file data: `filename` (arena copy), `content` (source text slice; taken by reference, not copied), `line_offsets` (`*U32ArrayList` of byte offsets for each line start), `len` (declared content length), `loaded` (whether `content` is materialized), `transient` (lazily faulted-in file). [inference]

**`SourceFileArrayList`** — Private dynamic array of `SourceFile`. Same pattern as `DiagnosticArrayList` but non-public. [inference]

**`Location`** — `file_id`, `line` (1-based), `col` (byte offset within line). [inference]

**`SourceManager`** — Holds `*SourceFileArrayList`, `*Sand` allocator, a `*GrowableSand` `fault` arena (for lazily faulted-in diagnostic source), and `fault_ready`. [inference]

### Function Walkthrough

| Function | Vis. | Purpose | Called By | Calls | Key Decisions | Markers |
|----------|------|---------|-----------|-------|---------------|---------|
| `sourceFileArrayListInit` | prv | Init empty `SourceFileArrayList` (zero len/cap, undefined items). | `sourceManagerInit` | (none) | Lazy arena allocation. | None [inference] |
| `sourceFileArrayListEnsureCapacity` | prv | Grow `SourceFile` array by 2x, min 8. Tries `sandTryReallocInPlace` first, else `sandAlloc` + copy. | `sourceFileArrayListAppend` | `alloc_mod.sandTryReallocInPlace`, `alloc_mod.sandAlloc` | Same pattern as other ArrayList helpers, with tail-realloc fast path. | None [inference] |
| `sourceFileArrayListAppend` | prv | Append `SourceFile` to array. | `sourceManagerAddFile`, `sourceManagerAddFileTransient` | `sourceFileArrayListEnsureCapacity` | Standard append. | None [inference] |
| `sourceFileArrayListGetSlice` | prv | Return source files as `[]SourceFile`. | `sourceManagerFaultIn`, `sourceManagerGetFileName`, `sourceManagerGetSourceContent`, `sourceManagerGetLineOffsets`, `sourceManagerGetLocation`, `sourceManagerResetFaults` | (none) | Slice of live data. | None [inference] |
| `sourceManagerInit` | pub | Init SourceManager. Allocates `SourceFileArrayList` and a `GrowableSand` fault arena header on the arena (16 bytes, 4-aligned). | `main.zig` setup | `alloc_mod.sandAlloc`, `sourceFileArrayListInit` | Same heap-alloc pattern as DiagnosticCollector; fault arena created lazily. | None [inference] |
| `sourceManagerAddFile` | pub | Add a source file. Copies the filename to the arena; takes ownership of the caller's `content` slice (no copy — module source is read into the perm arena by the import resolver). Pre-allocates line offsets exactly (`line_count+1`, min 64, from a pre-count pass). Appends 0 as first offset, then `i+1` for each `\n`. Appends `SourceFile` with `loaded=true`, `transient=false`. Returns file_id (1-based). | parser / import resolution | `sourceManagerCopyToArena`, `alloc_mod.sandAlloc`, `ga_mod.u32ArrayListInit`, `ga_mod.u32ArrayListEnsureCapacity`, `ga_mod.u32ArrayListAppend`, `sourceFileArrayListAppend` | file_id = files.len (1-based, 0 reserved as null). Line offsets pre-allocated exactly (no heuristic/×2 doubling). | None [inference] |
| `sourceManagerAddFileTransient` | pub | Register a file without materializing `content`/line offsets: dummy empty `line_offsets`, `loaded=false`, `transient=true`, `len=content.len`. Called by the import resolver during module parse; the content/offsets are produced only if a diagnostic needs them. | `import_resolver.zig` (`moduleRegistryParseModule`), tests | `sourceManagerCopyToArena`, `alloc_mod.sandAlloc`, `ga_mod.u32ArrayListInit`, `sourceFileArrayListAppend` | Lazily faulted in on first content/offset/location request. | None [inference] |
| `sourceManagerFaultIn` | prv | Lazily materialize a transient file's `content` + `line_offsets`. On first use, initializes the pool-backed `fault` growable sand (`"diag_read"`), calls `pal.readFile`, and rebuilds line offsets; on read failure installs empty content and a single `0` offset. | `sourceManagerGetSourceContent`, `sourceManagerGetLineOffsets`, `sourceManagerGetLocation` | `alloc_mod.growableSandInit`, `alloc_mod.poolPtr`, `pal_mod.readFile`, `ga_mod.*` | Reads are bounded by the recorded `len`; missing files degrade to empty content, not a crash. | None [inference] |
| `sourceManagerResetFaults` | pub | Reset the `fault` sand and clear `loaded` on every transient file, so the next print/fault-in re-reads. | `diagnosticCollectorPrintAll` | `alloc_mod.sandReset` | Bounds diagnostic fault-in memory across prints. | None [inference] |
| `sourceManagerGetFileName` | pub | Get filename by file_id (1-based). Returns `""` for id=0 or empty files. Clamps oversized file_id to 1. | `diagnosticCollectorPrintAll` | `sourceFileArrayListGetSlice` | 0 = null file, returns "". Clamp prevents OOB on corrupted file_id. | None [inference] |
| `sourceManagerGetSourceContent` | pub | Get source content by file_id. Same null/clamp logic as GetFileName; faults the file in first. | `diagnosticCollectorPrintAll` | `sourceFileArrayListGetSlice`, `sourceManagerFaultIn` | Same pattern. | None [inference] |
| `sourceManagerGetLineOffsets` | pub | Get line offsets array by file_id. Same null/clamp logic; faults the file in first. | `diagnosticCollectorPrintAll` | `sourceFileArrayListGetSlice`, `sourceManagerFaultIn`, `ga_mod.u32ArrayListGetSlice` | Returns `[]u32` directly. | None [inference] |
| `sourceManagerGetLocation` | pub | Convert byte offset → `Location{file_id, line, col}`. Binary search line offsets for containing line. `line = line_idx + 1`, `col = offset - offsets[line_idx]`. Returns `{0,0,0}` for null/empty file. | `diagnosticCollectorPrintAll` | `sourceFileArrayListGetSlice`, `sourceManagerFaultIn`, `ga_mod.u32ArrayListGetSlice`, `mem_mod.binary_search` | binary_search returns index where offsets[i] <= target. Line = index + 1 (1-based). Col = offset - line_start. | None [inference] |
| `sourceManagerCopyToArena` | prv | Copy byte slice to arena (alignment=1). Returns raw ptr. Undefined for empty slices. **Used only for the filename** — content is referenced, not copied. | `sourceManagerAddFile`, `sourceManagerAddFileTransient` | `alloc_mod.sandAlloc` | Same pattern as `stringInternerCopyToArena`. | None [inference] |

### Data Flow — Source Management

```
sourceManagerAddFile("foo.zig", content):
  1. Copy filename to arena (content taken by reference)
  2. line_count = count of '\n' in content; cap = max(line_count+1, 64)
  3. line_offsets = u32ArrayListInit(alloc); EnsureCapacity(cap)
     u32ArrayListAppend(line_offsets, 0)
     for each \n in content: u32ArrayListAppend(line_offsets, byte_pos + 1)
  4. sourceFileArrayListAppend(SourceFile{filename, content, line_offsets,
                                            len=content.len, loaded=true, transient=false})
  5. return files.len (1-based file_id)

sourceManagerGetLocation(manager, file_id, offset):
  1. sourceManagerFaultIn(file_id)   // no-op if already loaded
  2. offsets = getLineOffsets(file_id)
  3. line_idx = binary_search(offsets, offset)  // last offset <= target
  4. col = offset - offsets[line_idx]
  5. return Location{file_id, line_idx + 1, col}
```

---

## 5. `pal.zig` — Platform Abstraction Layer

### C Externs

Direct C FFI via raw `extern "c"` declarations (no libc wrapper): `fopen`, `fread`, `fwrite`, `fclose`, `fseek`, `ftell`, `c_exit`, `pal_file_open`, `pal_file_write`, `pal_file_read`, `pal_file_close`, `pal_get_default_lib_path`, `pal_dir_exists`, `pal_trap`. [inference]

File I/O constants: `SEEK_END=2`, `SEEK_SET=0`, `MODE_READ="rb"`. [inference]

**F-S9 fd-type** [updated: 2026-08-01] — PAL file descriptors are `usize` (32-bit `unsigned int` in C89), not `i32`. The sentinel is `INVALID_FD: usize = @intCast(usize, 0xFFFFFFFF)` — all-ones matches both the POSIX `-1` failure return (as `unsigned int`) and Win32 `INVALID_HANDLE_VALUE` at 32-bit width. Callers test `fd == pal.INVALID_FD` instead of `fd == -1`. This fixes the Win32 handle truncation bug (a `HANDLE` with bit 31 set was round-tripped through `int` and sign-extended back to a different pointer). The C side (`zig_pal.c`) returns/accepts the `PlatFile` typedef (`void*` on Win32 / `int` on POSIX) and `PLAT_INVALID_FILE` is `((void*)-1)`. `fileOpen` takes `FILE_OPEN_WRITE` (0, truncate/create) or `FILE_OPEN_READ` (1, read-only).

### Function Walkthrough

| Function | Vis. | Purpose | Called By | Calls | Key Decisions | Markers |
|----------|------|---------|-----------|-------|---------------|---------|
| `readFile` | pub | Read entire file into arena memory. Copies path to null-terminated C buffer (max 511 bytes). Opens with `fopen` ("rb"), seeks to end for size, allocates arena buffer, reads content. Returns `?[]u8`. | import resolver (module source read into the perm arena), main root check, SourceManager `sourceManagerFaultIn` | `fopen`, `fseek`, `ftell`, `fclose`, `fread`, `sandAlloc` | Max path 511 bytes. Binary read. Arena allocation freed only by reset. OOM returns null (not panic). Null covers missing, empty (`ftell <= 0`), and oversize paths indistinguishably. | None [inference] |
| `fileExists` | pub | Check if file exists by attempting `fopen("rb")`. Returns bool. Max path 511 bytes. | import resolution | `fopen`, `fclose` | Opens and closes; no memory allocation. Returns true for empty files (can't distinguish empty). | None [inference] |
| `dirExists` | pub | Check if a directory exists via `pal_dir_exists`. Max path 511 bytes. | CLI output-dir validation | `pal_dir_exists` | C-side directory probe. | None [inference] |
| `fileOpen` | pub | Open/create/truncate (or read) a file, return `usize` fd (`pal_file_open`). | `phase_C89Emission` multi-module branch | `pal_file_open` | Returns `INVALID_FD` on failure; path capped 511 bytes; `flags` is `FILE_OPEN_WRITE`/`FILE_OPEN_READ`. | None [inference] |
| `fileWrite` | pub | Write bytes to fd via `pal_file_write(fd: usize, …)`. | `bufferedWriterFlush` | `pal_file_write` | fd is `usize` (F-S9). | None [inference] |
| `fileRead` | pub | Read up to `buf.len` bytes from fd via `pal_file_read`. Returns bytes read (0 at EOF) or `INVALID_FD` on error. | import/file readers | `pal_file_read` | Negative C return mapped to `INVALID_FD`. | None [inference] |
| `fileClose` | pub | Close fd via `pal_file_close(fd: usize)`. | `phase_C89Emission` multi-module branch | `pal_file_close` | fd is `usize` (F-S9). | None [inference] |
| `stdout_write` | pub | Write bytes to stdout (fd 1) via `ext_c.write`. | `c89_emit.zig` output | `ext_c.write` | Direct syscall wrapper. | None [inference] |
| `stderr_write` | pub | Write bytes to stderr (fd 2) via `ext_c.write`. | diagnostics, allocator OOM, panic, main root check | `ext_c.write` | Direct syscall wrapper. | None [inference] |
| `streamOpen` | pub | Open a C `FILE*` for the LIR spill stream (`fopen` with caller mode). | `spill_store.zig` (`spillOpen`) | `fopen` | Returns `?*void`; path capped 511 bytes. All disk I/O lives here. | None [inference] |
| `streamClose` | pub | Close a spill `FILE*`. | `spill_store.zig` (`spillClose`) | `fclose` | — | None [inference] |
| `streamWrite` | pub | Write a full buffer to a spill `FILE*`; panics on short write. | `spill_store.zig` (`spillWriteAt`) | `fwrite`, `panicHandler` | Short-write is fatal. | None [inference] |
| `streamRead` | pub | Read a full buffer from a spill `FILE*`; panics on short read. | `spill_store.zig` (`spillReadAt`) | `fread`, `panicHandler` | Short-read is fatal. | None [inference] |
| `streamSeek` | pub | Seek a spill `FILE*` to an absolute offset (`SEEK_SET`); panics on failure. | `spill_store.zig` (`spillSeek`) | `fseek`, `panicHandler` | `i32` offset. | None [inference] |
| `getDefaultLibPath` | pub | Compute the compiler-binary-relative default library path via `pal_get_default_lib_path`. | module/import resolution | `pal_get_default_lib_path` | Thin delegation. | None [inference] |
| `exit` | pub | Exit process with code via `c_exit`. Infinite loop after as safety net. | `diagnosticCollectorFlushAndExit`, OOM/ICE, main error paths | `c_exit` | Hard exit. | None [inference] |
| `initArgs` | pub | Store argc/argv from C `main()` into module-level globals. | `main.zig` entry | (none) | Called once from C main. | None [inference] |
| `argCount` | pub | Return saved argc. | CLI parsing | (none) | Accessor. | None [inference] |
| `argGet` | pub | Return argv[i] as `[*]const u8`. | CLI parsing | (none) | Direct pointer access. | None [inference] |
| `markersEnabled` | pub | Set `g_markers_enabled` flag (0=off, nonzero=on). | `main.zig` CLI arg parsing (`--markers`) | (none) | Enable/disable markers. | None [inference] |
| `isMarkersEnabled` | pub | Return whether markers are enabled. | `arenaGrew` and other measurement sites | (none) | Accessor for the global flag. | None [inference] |
| `markerWrite` | pub | Conditional stderr write when both `g_markers_debug` (compile-time, currently 0) and `g_markers_enabled` are nonzero. | `markerWriteInt`, phase debug code | `stderr_write` | Debug-flood marker; compile-time-disabled. | None [inference] |
| `markerWriteInt` | pub | Debug marker: prefix + decimal u32 + newline. Uses `itoa`. | `stringInternerIntern` (`INT:tl`/`INT:t0`/`INT:dup`), phase markers | `markerWrite`, `itoa_mod.itoa` | Fixed-width format; `[12]u8` buffer. | `INT:tl`, `INT:t0`, `INT:dup` [inference] |
| `markerWriteInt64` | pub | Debug marker with **u64** suffix (`itoa64`, `[24]u8` buffer). | `int_literal` lowering marker (`lower.zig`) | `markerWrite`, `itoa_mod.itoa64` | Full u64 rendering. | `ILR:i39v5000000000` [inference] |
| `measureMarkerWrite` | pub | Always-on (when markers enabled) stderr write for the ~30 measurement markers; not gated by `g_markers_debug`. | `arenaGrew`, `--track-memory` output | `stderr_write` | Measurement path stays live with `--markers`. | `arena <name>: grew …` [inference] |
| `measureMarkerWriteInt` | pub | Measurement marker with u32 suffix (`itoa`). | `stringInternerIntern` (`INT:new`) | `measureMarkerWrite`, `itoa_mod.itoa` | `[12]u8` buffer. | `INT:new` [inference] |
| `measureMarkerWriteInt64` | pub | Measurement marker with u64 suffix (`itoa64`). | measurement sites | `measureMarkerWrite`, `itoa_mod.itoa64` | `[24]u8` buffer. | None [inference] |

### C-side PAL architecture & platform branching (I-PAL study) [updated: 2026-08-08]

`pal.zig` is the Z98-side view of a 3-part C-side PAL. All C-side code keys OS-level
branching off **`#ifdef _WIN32`** (covers MSVC 6 AND OpenWatcom — Watcom builds define
`_WIN32` via `wcc386 /bt=nt /d_WIN32`) with an `#else` POSIX arm. Compiler-dialect
differences (int64 typedef, `_vsnprintf`, `__inline`) use a **separate** 3-way chain
`#ifdef _MSC_VER` / `#elif defined(__WATCOMC__)` / `#else` (see emitted
`zig_compat.h`). This 2-level guard discipline (OS vs compiler) is the pattern the
C89 emitter must mirror for the planned std-lib builtins.

| C file | Role | Origin |
|--------|------|--------|
| `zig_pal.c` | `pal_print_stdout/stderr`, `pal_abort`, `pal_trap`, i64/u64/f64→str, `pal_file_open/read/write/close`, `pal_dir_exists`, `pal_get_default_lib_path`. fd = `usize` (F-S9), `PlatFile` = `void*` Win / `int` POSIX, `PLAT_INVALID_FILE=((void*)-1)`. | NEW in sf |
| `zig_runtime.c` | `std_print_*`/`std_panic` (forward to `pal_*`), checked-cast helpers, `@intCast` range-check `__bootstrap_*` helpers, `zig_poison_fill`. Platform-independent. | REWRITTEN from zig0 |
| `net_runtime.c` | 12 `plat_socket_*` (WSAStartup/winsock.h vs sys/socket.h; `SOCKET` casts guarded). | inherited byte-identical from zig0; **[F6 2026-08-13: SUPERSEDED for migrated examples — the 11 socket builtins port the bodies into the emitter (see 08 §6.9); net_runtime.c link removed from mud_server/rogue_mud]** |

Builtin → guard-chain map (zig0 proven patterns):
- **print/write:** `_WIN32` `GetStdHandle(STD_OUTPUT_HANDLE)` → `WriteConsoleA`, fallback
  `WriteFile` (console + redirected output); POSIX looped `write(1,…)`.
- **read/file:** `CreateFileA`/`ReadFile` vs `open`/`read` loop.
- **console gotoxy/setcolor/putchar/clear:** `_WIN32` console API vs ANSI escapes
  `\x1b[%d;%dH`, `\x1b[%s;%sm`, `\x1b[2J\x1b[H`; `putchar` needs no guard.
- **sleep:** `_WIN32` `Sleep(ms)` vs POSIX `usleep(ms*1000)` (requires `_XOPEN_SOURCE 500`).
- **sockets:** per-function `_WIN32`/`#else` arms; `fd_set` kept opaque (Zig caller uses a
  `[128]u32` blob + `u8*`-based fd helpers, mud_server pattern).

Watcom/MSVC6 workarounds to preserve: `platform_win98.h` preamble (`WINVER=0x0410`,
`WIN32_LEAN_AND_MEAN`, `_MBCS`); explicit `struct _MEMORY_BASIC_INFORMATION`; `_vsnprintf`
vs `vsnprintf`; `#pragma comment(lib, "wsock32.lib")`; `SOCKET` is unsigned — compare to
`INVALID_SOCKET`. Builtins improve on zig0 by emitting each guarded body once (zig0
duplicates sockets in both `platform.cpp` and `net_runtime.c`), using libc on the POSIX
arm (hand-roll only `_WIN32`), and folding `plat_is_windows()` to a comptime constant.
**Open issue:** sf-generated `build_owc.bat` defines `ZIG_WIN32` but
the C checks `_WIN32` — fix when the builtin emitter lands.

---

## 6. `growable_array.zig` — Typed Dynamic Arrays

### Array Types

All follow the same pattern: struct with `items`, `len`, `capacity`, `allocator`, plus `Init`, `EnsureCapacity`/`Grow`, `Append`, `GetSlice`. Some also have `PopOrNull`.

| Type | Element | Init | Growth | Special Notes |
|------|---------|------|--------|---------------|
| `U32ArrayList` | `u32` | `u32ArrayListInit(allocator)` — zero-cap lazy | 2x, min 8, 4-byte align | Has `u32ArrayListPopOrNull` (returns `?u32`) |
| `U8ArrayList` | `u8` | `byteArrayListInit(allocator)` | 2x, min 8, 1-byte align | Uses `byteArrayListGrow` (not `EnsureCapacity`) |
| `AstNodeArrayList` | `AstNode` | `astNodeArrayListInit(allocator, initial_capacity)` — eager pre-alloc | 2x, min 8, 4-byte align | `initial_capacity` arg; element size from `@sizeOf(AstNode)` |
| `U64ArrayList` | `u64` | `u64ArrayListInit(allocator, initial_capacity)` — eager pre-alloc | 2x, min 8, 4-byte align | 8-byte elements |
| `F64ArrayList` | `f64` | `f64ArrayListInit(allocator, initial_capacity)` — eager pre-alloc | 2x, min 8, 4-byte align | 8-byte elements |
| `FnProtoArrayList` | `FnProto` | `fnProtoArrayListInit(allocator, initial_capacity)` — eager pre-alloc | 2x, min 8, 4-byte align | Uses `@sizeOf(FnProto)` |

### Function Walkthrough (by pattern, one representative entry)

All arrays share these functions with the same logic, differing only in element type and size:

**U32ArrayList**:

| Function | Purpose | Key Details |
|----------|---------|-------------|
| `u32ArrayListInit` | Init with zero len/cap, undefined items. | Lazy — no allocation. |
| `u32ArrayListEnsureCapacity` | Grow to `new_capacity`. 2x factor, min 8. `sandAlloc(4 * new_cap, 4)`. Copies old. | `@sizeOf(u32) = 4`. |
| `u32ArrayListAppend` | Ensure +1, store at `items[len]`, increment. | Standard. |
| `u32ArrayListPopOrNull` | Decrement len, return old last value. Returns `null` if empty. | Only on U32ArrayList. |
| `u32ArrayListGetSlice` | Return `items[0..len]` as slice. | Standard. |

**U8ArrayList**:

| Function | Purpose | Key Details |
|----------|---------|-------------|
| `byteArrayListInit` | Init with zero len/cap, undefined items. | Lazy. |
| `byteArrayListGrow` | Grow to `new_capacity`. 2x, min 8. Tries `sandTryReallocInPlace` first (arena tail), else `sandAlloc(1 * new_cap, 1)` + copy. | Named `Grow` not `EnsureCapacity`. Alignment=1. |
| `byteArrayListAppend` | Ensure +1, store value, increment. | Standard. |
| `byteArrayListGetSlice` | Return slice. | Standard. |

**AstNodeArrayList**:

| Function | Purpose | Key Details |
|----------|---------|-------------|
| `astNodeArrayListInit` | Init WITH pre-allocation to `initial_capacity`. | Eager — calls `EnsureCapacity`. |
| `astNodeArrayListEnsureCapacity` | 2x, min 8. `sandAlloc(@sizeOf(AstNode) * new_cap, 4)`. | Size via comptime `@sizeOf`. |
| `astNodeArrayListAppend` | Ensure +1, store, increment. | Standard. |
| `astNodeArrayListGetSlice` | Return slice. | Standard. |

**U64ArrayList**:

| Function | Purpose | Key Details |
|----------|---------|-------------|
| `u64ArrayListInit` | Init with pre-allocation to `initial_capacity`. | Eager. |
| `u64ArrayListEnsureCapacity` | 2x, min 8. `sandAlloc(8 * new_cap, 4)`. | 8-byte elements. |
| `u64ArrayListAppend` | Standard. | |
| `u64ArrayListGetSlice` | Standard. | |

**F64ArrayList**:

| Function | Purpose | Key Details |
|----------|---------|-------------|
| `f64ArrayListInit` | Init with pre-allocation. | Eager. |
| `f64ArrayListEnsureCapacity` | 2x, min 8. `sandAlloc(8 * new_cap, 4)`. | 8-byte elements. |
| `f64ArrayListAppend` | Standard. | |
| `f64ArrayListGetSlice` | Standard. | |

**FnProtoArrayList**:

| Function | Purpose | Key Details |
|----------|---------|-------------|
| `fnProtoArrayListInit` | Init with pre-allocation. | Eager. |
| `fnProtoArrayListEnsureCapacity` | 2x, min 8. `sandAlloc(@sizeOf(FnProto) * new_cap, 4)`. | Size via `@sizeOf`. |
| `fnProtoArrayListAppend` | Standard. | |
| `fnProtoArrayListGetSlice` | Standard. | |

All arrays: allocation is fatal on OOM (`catch unreachable`). No shrink. Arena-allocated — never freed individually.

---

## 7. `panic.zig` — ICE Panic Handler

| Function | Vis. | Purpose | Called By | Calls | Key Decisions | Markers |
|----------|------|---------|-----------|-------|---------------|---------|
| `panicHandler` | pub | Print `"ICE: <msg> at <file>:<line>\n"` to stderr, then `pal.exit(3)`. | OOM in `sandAlloc`, plus `stringInternerCopyToArena`, `spill_store.zig`, `pal.zig` stream helpers, `module_registry.zig`, `ast.zig`, `lir_stream.zig`, `resolved_type_table.zig` | `pal.stderr_write`, `itoa_mod.itoa`, `pal.exit` | ICE exit code = 3. Formats line number via itoa. | None [inference] |

---

## 8. `util/mem.zig` — Memory Utilities

| Function | Vis. | Purpose | Called By | Key Decisions | Markers |
|----------|------|---------|-----------|---------------|---------|
| `mem_eql` | pub | Compare two byte slices for equality. Short-circuits on length mismatch. | `stringInternerIntern` (hash chain walk), `token.zig` (keyword match) | O(n) comparison after hash check. | None [inference] |
| `binary_search` | pub | Find last index where `offsets[i] <= target`. Standard lower-bound binary search minus 1. Returns 0 if target before first offset. | `sourceManagerGetLocation`, `diagnosticCollectorPrintAll` (line lookup) | Returns `lo - 1` after standard binary search lower-bound. | None [inference] |

---

## 9. `util/format.zig` — Formatters [updated: 2026-09-18]

| Function | Vis. | Purpose | Called By | Key Details |
|----------|------|---------|-----------|-------------|
| `copyStr` | pub | Copy `s` into `buf` at `*idx`, incrementing idx as bytes are written. | `dump_ast.zig` | Raw byte copy with cursor. |
| `formatU32` | pub | Format u32 to decimal in buf (right-to-left, null-terminated). Returns slice of formatted portion. | `dump_tokens.zig` | Signature `formatU32(val, buf, buf_len)`. Writes from end of buffer backwards. Null-terminated. |
| `formatU64` | pub | Same as formatU32 for u64. | `dump_ast.zig`, `dump_tokens.zig` | Same backward-write pattern. |
| `fmtBnMulSmall` | priv | Multiply a base-1e9 big integer by a small u32 (`2` or `5`) in place, growing `nlimbs`. | `formatF64` | Little-endian limbs; u64 carry; limb cap `FMT_BN_LIMBS = 128`. |
| `fmtCopyOut` | priv | Copy a formatted slice into the caller buffer, cap at `cap-1`, NUL-terminate, return the written slice. | `formatF64` | Shared safe buffer copy. |
| `formatF64` | pub | Self-contained f64 formatter (no libc): recovers the 53-bit significand by exact power-of-two scaling, builds the exact decimal big integer `B` (`m*2^E` or `m*5^-E`), rounds its top 17 digits, and emits normalized scientific notation `d.dddddddddddddddde±XX` with trailing fractional zeros trimmed. | c89_emit (`.float_const`), ast/parser/dump debug | 17 significant digits — IEEE-754 double round-trip. Zero/inf/nan guard emits `0` (no valid C89 literal). Deterministic; no host libc. |

---

## 10. `util/itoa.zig` — Integer to ASCII

| Function | Vis. | Purpose | Called By | Key Details |
|----------|------|---------|-----------|-------------|
| `itoa` | pub | Convert `u32` to decimal string in buffer. Returns character count (not including null terminator). Writes from buffer end, null-terminated. | allocator `printUsize`/`writeUsizeExact`, `panicHandler`, `pal` marker helpers, and many debug markers | Backward fill. Buffer MUST have space. Returns `buf.len - i - 1`. |
| `itoa64` | pub | Same as `itoa` for `u64`. | `pal` `markerWriteInt64`/`measureMarkerWriteInt64`, `lower.zig` debug markers | Same backward-fill pattern. |

---

## 11. `util/util.zig` — Misc Math

| Function | Vis. | Purpose | Called By | Key Details |
|----------|------|---------|-----------|-------------|
| `min` | pub | Return smaller of two u32 values. | (no callers in `sf/src`; test-only) | Simple if-else. |
| `max` | pub | Return larger of two u32 values. | (no callers in `sf/src`; test-only) | If-else. |

---

## 12. `util/hash.zig` — Hash Functions + Hash Maps

### Hash Function

| Function | Vis. | Purpose | Called By | Key Details |
|----------|------|---------|-----------|-------------|
| `fnv1a` | pub | 32-bit FNV-1a non-cryptographic hash. Initial value 2166136261, XOR each byte, multiply by 16777619 (modular). | `stringInternerIntern`, `c89_emit.zig` (name/path hashing) | Standard FNV-1a. Used for string interning and emitter lookups. |

`mapCapacityFromHint(hint)` (private) derives a power-of-two capacity ≥ `ceil(hint*4/3)`, min 8; `hint == 0` yields 0.

### Hash Maps

Three hash map types share one design: open addressing (linear probing), power-of-2 capacity (mask = capacity-1), load factor threshold 75% (count*4 >= capacity*3 triggers grow). [updated: 2026-08-15]

| Type | Key | Value | Init | InitCap | Get | Put | Grow (private) |
|------|-----|-------|------|---------|-----|-----|----------------|
| `U32ToU32Map` | `u32` | `u32` | `u32ToU32MapInit` | `u32ToU32MapInitCap` | `u32ToU32MapGet` | `u32ToU32MapPut` | `u32ToU32MapGrow` |
| `U64ToU32Map` | `u64` | `u32` | `u64ToU32MapInit` | `u64ToU32MapInitCap` | `u64ToU32MapGet` | `u64ToU32MapPut` | `u64ToU32MapGrow` |
| `U32ToU64Map` | `u32` | `u64` | `u32ToU64MapInit` | `u32ToU64MapInitCap` | `u32ToU64MapGet` | `u32ToU64MapPut` | `u32ToU64MapGrow` |

`U32ToU32Map` additionally has `u32ToU32MapGetOrAddDense`, which returns the existing value or assigns a new dense code (`count + 1`).

**`...MapInitCap(alloc, hint)` (added 2026-08-15):** capacity-hint init — `mapCapacityFromHint` derives capacity (ceil(hint×4/3) rounded up to a power of two, min 8; hint==0 → falls back to `...MapInit`), then allocates all 3 arrays (keys, values, occupied) at that capacity in one go and zeroes `occupied`. Used at init sites with a cheap known bound to avoid rehash growth: `keyword_set` (32), `emitted_type_set`/`fwd_decl_set`/`lfwd`/`lemit` (`types_len`), `pointer_only_map` (`pointer_only_len`), `cincludeUnionAll` `seen` (sum of module `c_includes` lengths). Maps WITHOUT a hint keep lazy zero-capacity init (grow on first put).

**Key design for all maps:**
- **Key indexing:** `U32ToU32Map`/`U32ToU64Map` use `@intCast(usize, key) & mask` (low bits of key as probe start). `U64ToU32Map` uses `@intCast(usize, @intCast(u32, key & 0xFFFFFFFF)) & mask` (low 32 bits of key).
- **Probing:** Linear probing with wrap-around: `i = (i + 1) & mask`.
- **Grow:** Double capacity (min 8). Allocates 3 separate arrays (keys, values, occupied byte). Rehashes all entries.
- **Put:** Check load factor first (≥75% triggers grow), then the capacity==0 case. Find slot via probing. If key exists: update value. If empty: fill slot, mark occupied.
- **Get:** Null if capacity=0. Probe from `key & mask`. Return `null` if slot unoccupied.
- **Delete:** Not supported. No tombstone mechanism.
- **Init:** Zero capacity (lazy). First `put` that hits capacity=0 triggers growth.

**U64ToU32Map** — Same structure, key size 8 bytes, value size 4 bytes. Key index uses lower 32 bits.

**U32ToU64Map** — Same structure, key size 4 bytes, value size 8 bytes.

---

## 13. `config.zig` — Host Platform Flip Point

| Constant | Vis. | Value | Purpose |
|----------|------|-------|---------|
| `host_is_windows` | pub | `false` | Declared single flip point for host/target Windows-ness. **Currently unwired:** nothing imports `config.zig`; the `@isWindows` fold reads `comptime_eval.zig`'s own `host_is_windows` field, which `main.zig` sets from `cli.target_is_windows`. |

---

## 14. `util/path.zig` — Path Normalization

| Function | Vis. | Purpose | Key Details |
|----------|------|---------|-------------|
| `normalizePath` | pub | In-place lexical normalization of a `/`-separated path: collapses `.`/`..` segments and `//` runs so syntactically different spellings become byte-equal. Returns the canonical sub-slice of `buf` (aliases `buf`), or `null` if `buf.len < src.len`. | Absolute prefix seeds `/`; `.` dropped; `..` pops the segment stack (or stays leading when relative); trailing slash trimmed; empty result is `/` (absolute) or `.` (relative). Uses a fixed `[512]usize` segment stack. |

---

## Data Flow — Heap / Arena Usage

### Arena Sizing

```
POOL_SIZE          = 268435456 B = 256 MiB  (single static memory_pool_buf)
DEV_MAX_MEM        = 16 MB  (initCompilerAlloc default; main.zig overrides from CLI)
RELEASE_MAX_MEM    = 16 MB
DEFAULT_MAX_MEM_KB = 64 MB  (--max-mem / -mm default pool budget)
```

The allocator no longer uses three fixed-size static buffers. One 256 MiB static
pool (`memory_pool_buf`, a plain `Sand`) backs five **growable** tier arenas:
`permanent`, `module`, `scratch`, `lir_read`, `emission`. Each tier is a
`GrowableSand` seeded with a 4 KB first segment carved from the pool. When a
segment fills, `growableSandGrow` doubles the segment size (capped at 1 MiB,
exact-fit when a single request is larger), reuses a best-fit segment from the
cross-arena free list (`seg_free_head`) after a reset, or carves a new segment +
`SandSegment` node from the pool; `sandAlloc` retries in the new segment. Only a
pool-exhausted carve is fatal.

### Who Allocates Where

| Arena | Contents | Reset Behavior |
|-------|----------|----------------|
| Permanent | StringInterner, SourceManager, DiagnosticCollector, interned strings, ModuleRegistry, SymbolRegistry, keyword table, const-alias prepass, type-name resolution | Never reset |
| Module | AstStore, ResolvedTypeTable, CoercionTable, DepGraph, enum_value_table, call_arg_types/call_param_map, comptime_values, async tables (suspending_fns, frame_sizes, state_widths, awaited_fns, async_hidden_fns, driver_targets, parent_result_*, async_layouts) | Reset once at the lowering→emission boundary (`sandReset` in `runCompiler`); earlier phases share it |
| Scratch | Per-phase temporaries: input source read, parser tokens, per-phase DepGraph, TypeResolver workspace, semantic analyzer state, lowerer BasicBlocks | Reset at phase start; `sandResetPeak` at StaticAnalyzers entry |
| lir_read | LIR functions reloaded from the spill stream during C89 emission | Never reset (separate from emission so reloads do not disturb emission state) |
| emission | LIR slots, error_code_registry, exported, global_decls, name mangler, module/type-group tables, emitted runtime support | Never reset |

Additional pool-backed growable sands live outside `CompilerAlloc`: the
TypeRegistry `type_db_arena`, the import resolver's `parser_arena` /
`import_scratch_gs` / `src_arena`, and the SourceManager diagnostic fault-in
arena (`fault`, created lazily on first fault-in).

> **DepGraph:** the live DepGraph is **scratch-local, one per phase**.
> `phase_SymbolRegistration` and `phase_TypeResolution` each call
> `depGraphInit(&ctx.alloc.scratch)` after their `sandReset`; phase 3 does not
> consume phase 2's graph. The `ctx.dep_graph` field (initialized from the module
> arena) is kept but never populated — a dead field.

### CompilerAlloc Init Sequence (main.zig)

```
initCompilerAlloc():
  pool       ← sandInit(memory_pool_buf[0..POOL_SIZE])
  permanent  ← growableSandInit(&pool, 4096, "perm")
  module     ← growableSandInit(&pool, 4096, "module")
  scratch    ← growableSandInit(&pool, 4096, "scratch")
  lir_read   ← growableSandInit(&pool, 4096, "lir_read")
  emission   ← growableSandInit(&pool, 4096, "emission")
  max_mem = DEV_MAX_MEM

main then overrides max_mem from the parsed --max-mem/-mm value and sets the
spill level (-s<N>); subsystems allocate from the permanent arena:
  stringInternerInit(&permanent, interner_bc)   → buckets/entries
  sourceManagerInit(&permanent)                 → SourceFileArrayList + fault sand
  diagnosticCollectorInit(&permanent, ...)      → DiagnosticArrayList
```

### TrackingAllocator Per-Phase

> **Not wired.** No phase in `sf/src/` calls `trackingAllocatorInit` /
> `trackingAlloc` / `trackingReset` / `trackingPeak`; `TrackingAllocator` is only
> defined (kept for the planned per-allocation `--track-memory` / `--max-mem`
> enforcement). Phases allocate directly through `sandAlloc`; per-tier peaks are
> read from each tier's `peak` field.

Each phase that tracked memory would wrap the scratch arena:

```
var track = trackingAllocatorInit(&compiler.alloc.scratch);
// ... phase work using trackingAlloc(&track, ...) ...
var report = trackingAllocatorReport(&track);  // report.peak / .total / .count
trackingReset(&track);  // also sandReset(scratch)
```

### Memory Budget Checkpoints

`checkCombinedPeak` compares `pool.peak / 1024` against the configured budget
(`max_mem` KB; when `max_mem == 0` it uses the full `POOL_SIZE`). It is called at
phase boundaries in `runCompiler`; exceeding the limit prints the pool peak and
panics.

---

## Debugging — Markers, GDB, Isolation

### Adding a Debug Marker

```
pal.markerWrite("PHASE:start");
pal.markerWriteInt("COUNT:", 42);
```

Output (with `--markers`): `PHASE:start\nCOUNT:42\n`

Markers are conditionally written — disabled by default, enabled via `markersEnabled(1)` from CLI arg `--markers`. The debug-flood markers (`markerWrite` / `markerWriteInt` / `markerWriteInt64`) are additionally gated by the compile-time constant `g_markers_debug` (currently `0`), so they emit nothing even with `--markers`; the ~30 measurement markers (`measureMarkerWrite*`) stay live. When disabled the cost is a couple of compares.

### Known Marker Values from string_interner.zig

| Marker | Emitted In | Meaning |
|--------|------------|---------|
| `INT:tl` | `stringInternerIntern` (`markerWriteInt`) | Total length of text being interned |
| `INT:t0` | `stringInternerIntern` (`markerWriteInt`) | First byte of text (if non-empty) |
| `INT:dup` | `stringInternerIntern` (`markerWriteInt`) | Found duplicate — returning existing ID |
| `INT:new` | `stringInternerIntern` (`measureMarkerWriteInt`) | New internment — allocated new ID |

Arena growth emits `arena <name>: grew <old> -> <new>` via `arenaGrew` / `measureMarkerWrite` in `allocator.zig`.

### GDB on Generated C

zig1 compiles to C89. The generated C can be debugged with GDB directly:

```
$ mkdir -p /tmp/out
$ zig1 --dump-c89 --output-dir /tmp/out source.zig   # N .c + N .h + zig_special_types.h
$ cd /tmp/out
$ gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
$ gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog
$ ./prog
$ gdb ./prog
```

[updated: 2026-08-01] The multi-module build recipe: `--dump-c89 --output-dir DIR` emits
per-module `.c`/`.h` + `zig_special_types.h`; compile each `.c` (`-c`) then link all `.o` with
`zig_runtime.c` + `zig_pal.c`. Run gcc from INSIDE DIR (`cd DIR`, then `-c *.c`) — `gcc -c DIR/*.c`
from outside writes the `.o` files to the caller's CWD and the `*.o` link glob fails. Use absolute
repo paths (`-I /workspace/znineeight/sf/src/include`) since the recipe `cd`s into DIR. `-I` is
REQUIRED (zig1 does not copy `zig_compat.h`/`zig_runtime.h` into the output dir). Bare `--dump-c89`
(no `--output-dir`) keeps the stdout single-file path; `--output-dir` without `--dump-c89` is still
a no-op.

The compiler's `--markers` flag emits phase trace to stderr, which helps identify where in the pipeline a crash occurs. Markers appear interleaved with diagnostic output.

### Isolation Strategy

- Arena corruption: check `sand.pos` progression. Spike in allocation rate at a specific phase pinpoints the offender.
- OOM: tier arenas grow from the 256 MiB pool; raise the budget (`--max-mem`/`-mm`, or `-mm0` for the full pool) or `POOL_SIZE` in `allocator.zig`.
- Interner hash chain: markers `INT:tl`, `INT:t0`, `INT:dup`, `INT:new` show interning pattern.
- Diagnostics: insert `diagnosticCollectorAdd` early to test error paths.
- TrackingAllocator: wrap a phase's allocations to measure peak/total separately.


