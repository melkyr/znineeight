# 00 — Shared Infrastructure

> Covers: allocator, string interner, diagnostics, source manager, PAL, growable arrays, panic handler, utility modules
> Cross-ref: [INDEX.md](INDEX.md) §G (arena tier table)

## Summary

| Key | Value |
|-----|-------|
| Input | (none — shared infrastructure, called by all phases) |
| Output | N/A |
| Key structs | `Sand`, `CompilerAlloc`, `StringInterner`, `DiagnosticCollector`, `SourceManager`, `U32ArrayList`, `U32ToU32Map`, `TrackingAllocator` |
| Key functions | `sandAlloc`, `stringInternerIntern`, `diagnosticCollectorAdd`, `sourceManagerGetLocation`, `markerWrite`, `panicHandler` |
| Markers | `INT:tl`, `INT:t0`, `INT:dup`, `INT:new` (from `stringInternerIntern`) |

---

## 1. `allocator.zig` — Bump Arena Allocator (168 lines)

### Structs

**`Sand`** (`allocator.zig:1-7`) — Linear bump allocator state. Fields: `start` (base ptr), `pos` (current offset), `end` (total size), `peak` (high-water mark), `name` (label for diagnostics). No free-list, no per-allocation metadata. [inference]

**`CompilerAlloc`** (`allocator.zig:67-72`) — 3-tier arena container. Holds three `Sand` instances: `permanent`, `module`, `scratch` + `max_mem` (combined peak limit). [inference]

**`TrackingAllocator`** (`allocator.zig:121-126`) — Wraps a `*Sand` with `total_allocated`, `peak_allocated`, `allocation_count` counters. Used for per-phase accounting. [inference]

**`TrackingAllocatorReport`** (`allocator.zig:164-168`) — Snapshot struct: `peak`, `total`, `count`. [inference]

### Static Buffers

`perm_arena_buf[1048576]` (1 MB), `mod_arena_buf[1572864]` (1.5 MB), `scr_arena_buf[1572864]` (1.5 MB) — `allocator.zig:74-76`. Statically allocated, three fixed-size regions backing the three tiers. [inference]

### Constants

**`DEV_MAX_MEM`** = 8 MB (`allocator.zig:78`). **`RELEASE_MAX_MEM`** = 16 MB (`allocator.zig:79`). Combined peak limit across all three arenas. `initCompilerAlloc` uses `DEV_MAX_MEM` by default. [inference]

### Function Walkthrough

| Function | Line | Visibility | Purpose | Called By | Calls | Data Touched | Key Decisions | Markers |
|----------|------|-----------|---------|-----------|-------|-------------|---------------|---------|
| `sandInit` | 12 | pub | Initialize a `Sand` from a byte slice. Sets `start=buf.ptr`, `pos=0`, `end=buf.len`, `peak=0`. Name defaults to `"unknown"`. Adjusts peak if initial pos > 0. | `initCompilerAlloc`, consumers creating arenas | (none) | Sand fields | Caller provides backing buffer; no malloc. | None [inference] |
| `sandAlloc` | 26 | pub | Allocate `size` bytes with `alignment` from arena. Aligns `pos` up to alignment boundary, checks `new_pos <= end`. On OOM: prints `used/new/total` to stderr, calls `panicHandler`. Updates `pos` and `peak`. | any code that needs heap memory | `pal.stderr_write`, `printUsize`, `panic_mod.panicHandler` | Sand.pos, Sand.peak, Sand.end | Alignment via `(pos + mask) & ~mask`. Fatal on OOM (no recovery). | None [inference] |
| `sandReset` | 47 | pub | Reset `pos` to 0. Does NOT modify `peak`. Allows arena reuse. | `trackingReset`, phase transitions | (none) | Sand.pos | Cheap — just integer write. No free. | None [inference] |
| `sandResetPeak` | 51 | pub | Set `peak = pos`. Effectively freezes current high-water mark. | `checkCombinedPeak` callers wanting fresh peak | (none) | Sand.peak | Peak tracking separate from pos for diagnosis. | None [inference] |
| `sandReallocInPlace` | 55 | pub | Try to grow allocation at end of arena. If last-allocated and within bounds, extends `pos` and returns old ptr. Otherwise returns `null`. | places wanting to grow last alloc | (none) | Sand.pos, Sand.peak | Only works for most-recent allocation at arena tail. No copy fallback. | None [inference] |
| `initCompilerAlloc` | 81 | pub | Initialize the 3-tier `CompilerAlloc`. Wraps each static buffer in a `Sand`, sets tier names (`"perm"`, `"module"`, `"scratch"`), sets `max_mem = DEV_MAX_MEM`. | `main.zig` at startup | `sandInit` | static arena buffers | Tier names used in OOM messages. One-time init. | None [inference] |
| `checkCombinedPeak` | 94 | pub | Sum peak usage of all 3 arenas in KB. If total > `max_mem / 1024`, prints peak-per-tier and calls `pal.exit(1)`. | `runCompiler` after phases | `printUsize`, `pal.stderr_write`, `pal.exit` | `CompilerAlloc.permanent/module/scratch.peak` | Hard limit — compiler exits. Separate checkpoints catch runaway alloc. | None [inference] |
| `printUsize` | 114 | private | Format a `usize` as decimal into a 16-byte buffer, right-aligned to 15 chars, write to stderr. Used for OOM/memory-limit messages. | `sandAlloc`, `checkCombinedPeak` | `itoa_mod.itoa`, `pal.stderr_write` | local buffer | Fixed-width right-aligned for readability. | None [inference] |
| `trackingAllocatorInit` | 128 | pub | Init `TrackingAllocator` with a Sand arena, zero counters. | per-phase setup | (none) | TrackingAllocator fields | Wraps existing Sand; no separate memory. | None [inference] |
| `trackingAlloc` | 137 | pub | Allocate via `sandAlloc`, then increment `allocation_count`, add `size` to `total_allocated`, update `peak_allocated`. | phase that tracks per-phase usage | `sandAlloc` | Sand, TrackingAllocator counters | Thin wrapper — same allocation path, just counting. | None [inference] |
| `trackingReset` | 147 | pub | Reset Sand AND zero `total_allocated`. Keeps `allocation_count` and `peak_allocated` as-is (historical). | between phases | `sandReset` | Sand, TrackingAllocator.total_allocated | Partial reset — peak persists for reporting. | None [inference] |
| `trackingPeak` | 152 | pub | Return `peak_allocated` as u32. | reporting | (none) | TrackingAllocator.peak_allocated | Simple accessor. | None [inference] |
| `trackingAllocatorReport` | 156 | pub | Return `TrackingAllocatorReport` snapshot of peak, total, count. | phase end reporting | (none) | TrackingAllocator counters | Value copy, not pointer. | None [inference] |

### Data Flow — Allocator

```
initCompilerAlloc()
  │
  ├─ permanent: sandInit(perm_arena_buf[1048576])  ← never reset
  ├─ module:    sandInit(mod_arena_buf[1572864])    ← never reset
  └─ scratch:   sandInit(scr_arena_buf[1572864])    ← reset per phase

sandAlloc(sand, size, alignment):
  1. mask = alignment - 1
  2. aligned = (sand.pos + mask) & ~mask
  3. if (aligned + size > sand.end) → OOM panic
  4. result = sand.start + aligned
  5. sand.pos = aligned + size
  6. update peak if new_pos > sand.peak
  7. return result
```

Arena layout is strictly linear — no free, no coalesce, no reuse of freed space. Reset is the only reclaim mechanism.

---

## 2. `string_interner.zig` — FNV-1a String Interner (154 lines)

### Structs

**`InternEntry`** (`string_interner.zig:7-11`) — Hash table entry. `text` (slice into arena), `hash` (FNV-1a), `next` (open-chaining link to next entry in same bucket). [inference]

**`StringInterner`** (`string_interner.zig:13-22`) — Interner state. Separate arrays for buckets (`[*]u32`, bucket index → entry ID) and entries (`[*]InternEntry`). Zero entry is sentinel (empty string, hash 0, next 0). Two `*Sand` allocator references: `entries_allocator` and `allocator` (both point to same arena — permanent). [inference]

### Function Walkthrough

| Function | Line | Visibility | Purpose | Called By | Calls | Data Touched | Key Decisions | Markers |
|----------|------|-----------|---------|-----------|-------|-------------|---------------|---------|
| `ensureCapacityBuckets` | 24 | private | Grow bucket array to at least `new_capacity`. Doubles on growth, min 8. Allocates via `sandAlloc`, copies old entries. | `appendBucket`, `stringInternerGrowBuckets` | `alloc_mod.sandAlloc` | `items`, `len`, `capacity`, arena | Growth factor 2x, min 8. Raw memory, no initialization of new slots (caller handles). | None [inference] |
| `ensureCapacityEntries` | 38 | private | Same pattern but for `InternEntry` arrays. Element size = 16 bytes (text ptr + hash u32 + next u32 + padding). | `appendEntry` | `alloc_mod.sandAlloc` | `items`, `len`, `capacity`, arena | Same 2x growth, min 8. | None [inference] |
| `appendBucket` | 52 | private | Ensure capacity for +1, then append `value` at `[*][len]`. | `stringInternerInit`, `stringInternerIntern` | `ensureCapacityBuckets` | bucket array, len | Wraps ensure+store+increment pattern. | None [inference] |
| `appendEntry` | 58 | private | Same pattern for InternEntry. | `stringInternerIntern` | `ensureCapacityEntries` | entry array, len | Same wrapper pattern. | None [inference] |
| `stringInternerInit` | 64 | pub | Create interner with `bucket_count` initial buckets (all set to 0 = empty). Entry 0 is the sentinel (empty string, hash 0, next 0). | `main.zig` setup (`main.zig:137`) | `appendBucket`, `appendEntry` | interner fields, bucket/entry arrays | Entry 0 reserved as null/sentinel. All buckets initially empty. | None [inference] |
| `stringInternerIntern` | 88 | pub | Intern a string. Hash via `fnv1a`, find bucket, walk chain for match. If found, return existing ID. Otherwise: copy to arena, append entry (head-insert into bucket chain), grow buckets if load factor > 0.5. Emits markers for trace. | All phases needing string dedup. Called by `diagnosticCollectorAdd`, `diagnosticBuilderMakeMsg`, lexer/parser. | `hash_mod.fnv1a`, `mem_mod.mem_eql`, `stringInternerCopyToArena`, `appendEntry`, `stringInternerGrowBuckets`, `pal.markerWriteInt` | bucket/entry arrays, hash chain | FNV-1a hash. Open chaining. Bucket doubling at 50% load. String copied to arena (no original ref kept). | `INT:tl` (text len), `INT:t0` (first char), `INT:dup` (existing ID), `INT:new` (new ID) [inference] |
| `stringInternerGet` | 124 | pub | Lookup interned string by ID. Indexes into entries array, returns `entry.text`. ID 0 returns empty string (sentinel). | `diagnosticCollectorPrintAll`, `diagnosticBuilderMakeMsg` | (none) | entries array | O(1) lookup. | None [inference] |
| `stringInternerCopyToArena` | 128 | private | Copy string bytes into arena (byte-level alignment=1). Returns raw ptr. | `stringInternerIntern` | `alloc_mod.sandAlloc` | arena | Byte copy, no null terminator. | None [inference] |
| `stringInternerGrowBuckets` | 136 | private | Double bucket count, rehash all existing entries. Resets bucket_len to 0, re-ensures capacity, fills all buckets with 0, then walks entries 1..N, computing new bucket index = hash % new_count, sets entry.next to current bucket head, sets bucket head to entry ID. | `stringInternerIntern` (when load > 0.5) | `ensureCapacityBuckets` | buckets, entries (next pointers) | Full rehash of all entries. Old bucket array leaked (arena allocated, never freed). | None [inference] |

### Data Flow — Interning

```
stringInternerIntern("foo"):
  1. hash = fnv1a("foo")           -- 32-bit FNV-1a
  2. bucket = hash % buckets_len    -- index into bucket array
  3. Walk chain: entries[buckets[bucket]].next...
  4. If match (hash + mem_eql) → return existing ID
  5. If no match:
     a. Copy "foo" to arena via sandAlloc
     b. appendEntry with .text=copied, .hash=hash, .next=current bucket head
     c. buckets[bucket] = new entry ID
     d. If (entry_count * 2 > bucket_count) → grow buckets (double + rehash)
  6. Return new entry ID
```

---

## 3. `diagnostics.zig` — Error/Diagnostic Reporting (612 lines)

### Types

**`DiagnosticLevel`** (`diagnostics.zig:3-8`) — `enum(u8)`: `err_lvl=0`, `warning=1`, `info=2`, `note=3`. [inference]

**`ErrorCode`** (`diagnostics.zig:10-67`) — `enum(u16)` with 60+ error/warning/info codes, grouped by phase range: 1xxx (lexer), 2xxx (parser), 3xxx (semantic), 4xxx (lowering), 5xxx (C89 emit), 6xxx/7xxx (analyzers), 9xxx (internal). [inference]

**Numeric constants** (`diagnostics.zig:69-77`) — First 8 error codes as standalone `u16` constants (`ERR_1000..ERR_1005`, `WARN_1010`, `WARN_1011`). These are the raw numeric values of the enum discriminants. [inference]

**`Diagnostic`** (`diagnostics.zig:80-90`) — Single diagnostic. Fields: `level` (u8), `code` (u16), `file_id` (u32), `span_start/span_end` (u32 byte offsets), `message_id` (u32 — interned string), `note_count` (u8, max 3), `note_ids` ([3]u32), `related_span_idx` (u16 — into `Collector.related_span_items`). [inference]

**`RelatedSpan`** (`diagnostics.zig:92-97`) — Secondary source location for a diagnostic. Fields: `span_file_id`, `span_start`, `span_end`, `message_id`. [inference]

**`MAX_DIAGNOSTICS`** (`diagnostics.zig:78`) — 256. Hard cap; overflow triggers ERR_9999. [inference]

**`DiagnosticArrayList`** (`diagnostics.zig:175-180`) — Dynamic array of `Diagnostic` on Sand arena. Fields: `items`, `len`, `capacity`, `allocator`. [inference]

**`DiagnosticCollector`** (`diagnostics.zig:215-226`) — Central diagnostic hub. Holds `*DiagnosticArrayList`, `related_span_items` (raw dynamic array of `RelatedSpan`), `*SourceManager`, `*StringInterner`, `error_count`, `warning_count`, `max_diagnostics`. [inference]

### Function Walkthrough

| Function | Line | Vis. | Purpose | Called By | Calls | Data Touched | Key Decisions | Markers |
|----------|------|------|---------|-----------|-------|-------------|---------------|---------|
| `getLevelName` | 109 | prv | Map level u8 → string: 0="error", 1="warning", 2="info", 3="note", else="unknown". | `diagnosticCollectorPrintAll` | (none) | (pure) | Switch over u8. | None [inference] |
| `formatU32` | 134 | prv | Write decimal representation of u32 into buf (right-aligned). Returns character count. | `diagnosticCollectorPrintAll` | (none) | local buf | Manual ascii conversion, right-aligned. | None [inference] |
| `writeStr` | 150 | prv | Shorthand for `pal.stderr_write(s)`. | `diagnosticCollectorPrintAll`, `formatU32` callers | `pal.stderr_write` | (I/O) | Pure delegation. | None [inference] |
| `compareDiag` | 154 | prv | Compare two `Diagnostic` by file_id, then span_start, then level. Returns i32 difference. | `sortDiagnostics` | (none) | (pure) | Insertion sort comparator. | None [inference] |
| `sortDiagnostics` | 161 | prv | Insertion sort diagnostics array by file/span/level. | `diagnosticCollectorPrintAll` | `compareDiag` | Diagnostic array | Stable-ish (insertion sort). Sorts before printing for grouped output. | None [inference] |
| `diagnosticArrayListInit` | 182 | pub | Init empty `DiagnosticArrayList`, zero len/capacity, undefined items pointer. | `diagnosticCollectorInit` | (none) | DiagnosticArrayList fields | Arena allocation lazily. | None [inference] |
| `diagnosticArrayListEnsureCapacity` | 191 | pub | Grow Diagnostic array. 2x growth, min 8, allocate via `sandAlloc(element_size * new_cap, 4)`. | `diagnosticArrayListAppend` | `alloc_mod.sandAlloc` | items, capacity | Aligned to 4 bytes. | None [inference] |
| `diagnosticArrayListAppend` | 205 | pub | Ensure capacity for +1, store value at `items[len]`, increment len. | `diagnosticCollectorAdd`, `diagnosticCollectorFlushAndExit` | `diagnosticArrayListEnsureCapacity` | items, len | Standard append. | None [inference] |
| `diagnosticArrayListGetSlice` | 211 | pub | Return `items[0..len]` as `[]Diagnostic`. | `diagnosticCollectorPrintAll` | (none) | items, len | Returns slice of live data. | None [inference] |
| `diagnosticCollectorInit` | 228 | pub | Init collector. Allocates `DiagnosticArrayList` on arena (16 bytes, 4-aligned). Takes `*SourceManager` and `*StringInterner`. Counts start at 0, `max_diagnostics=MAX_DIAGNOSTICS`. | `main.zig` setup | `alloc_mod.sandAlloc`, `diagnosticArrayListInit` | collector fields | DiagnosticArrayList heap-allocated (pointer stable). | None [inference] |
| `diagnosticCollectorIntern` | 246 | pub | Convenience: intern a string via the collector's interner. | places that want to intern via collector | `interner_mod.stringInternerIntern` | interner | Thin delegation. | None [inference] |
| `diagnosticCollectorAdd` | 250 | pub | Add a diagnostic. If `code==9999` (ERR_TOO_MANY_ERRORS), early return 0. If overflow (`len >= max_diagnostics`), emits ERR_9999 with overflow message. Otherwise: intern message, append Diagnostic, increment error/warning count. Returns diagnostic index. | All phases that report errors/warnings | `interner_mod.stringInternerIntern`, `diagnosticArrayListAppend` | diagnostics array, error_count, warning_count, interner | Overflow protection (ERR_9999). Returns index for note/related-span attachment. | None [inference] |
| `diagnosticCollectorHasErrors` | 286 | pub | Return `error_count > 0`. | `runCompiler` phase checks | (none) | error_count | Quick check for abort/continue decision. | None [inference] |
| `diagnosticCollectorErrorCount` | 290 | pub | Return `error_count` as u32. | reporting | (none) | error_count | Trivial accessor. | None [inference] |
| `diagnosticCollectorWarningCount` | 294 | pub | Return `warning_count` as u32. | reporting | (none) | warning_count | Trivial accessor. | None [inference] |
| `diagnosticCollectorAddNote` | 298 | pub | Add a note (max 3) to existing diagnostic. Interns note text, stores in `note_ids[]`. No-op if `diag_idx` out of range or `note_count >= 3`. | phases that want to attach notes | `interner_mod.stringInternerIntern` | diagnostic.note_count, diagnostic.note_ids | Bound check on diag_idx and note_count. Silent discard if full. | None [inference] |
| `diagnosticCollectorAddRelatedSpan` | 307 | pub | Attach a related source span to a diagnostic. Interns message, grows `related_span_items` (2x, min 8), appends RelatedSpan, sets `diagnostic.related_span_idx`. | phases wanting secondary locations | `interner_mod.stringInternerIntern`, `alloc_mod.sandAlloc` | related_span_items array, diagnostic.related_span_idx | Own arena-based dynamic array (not wrapped in ArrayList struct). Manual growth w/ 2x factor. | None [inference] |
| `diagnosticCollectorFlushAndExit` | 335 | pub | Print all diagnostics, then `pal.exit(exit_code)`. | fatal error paths | `diagnosticCollectorPrintAll`, `pal.exit` | (I/O) | Combines print + exit. | None [inference] |
| `diagnosticBuilderMakeMsg` | 340 | pub | Build a concatenated message from multiple parts. Allocates contiguous buffer on interner's arena, copies all parts, interns the result, returns interned string. Falls back to `"diagnostic message too long"` on OOM. | diagnostics that construct messages from parts | `alloc_mod.sandAlloc`, `interner_mod.stringInternerIntern`, `interner_mod.stringInternerGet` | interner's arena, interner | Concatenates parts into arena buffer, then interns. Returns interned ID (looked up by string). Two allocations: temp buf + intern copy. | None [inference] |
| `diagnosticCollectorPrintAll` | 359 | pub | Main diagnostic printer. Handles empty case. Sorts diagnostics (file/span/level). For each diag: if file_id==0 prints "level[code]: message". Else: prints `file:line:col: level[code]: message`, then source line + caret underline under span, then notes, then related span. | `diagnosticCollectorFlushAndExit`, explicit calls | `sortDiagnostics`, `diagnosticArrayListGetSlice`, `getLevelName`, `formatU32`, `writeStr`, `sourceManagerGetLocation`, `sourceManagerGetFileName`, `sourceManagerGetSourceContent`, `sourceManagerGetLineOffsets`, `mem_mod.binary_search` | SourceManager, interned strings, SourceFile content, line offsets | Sorts before printing. Printer has source context rendering with carets. Fixed-width code formatting. Caret buf capped at 256. Binary search for line from offset. | None [inference] |
| `typeKindSrcStr` | 492 | pub | Map `TypeKind` → source-level type string (e.g., `"source: i32"`). Used for diagnostic messages about source types. | diagnostic message construction | (none) | (pure) | If-else chain over all TypeKind variants. | None [inference] |
| `typeKindTgtStr` | 553 | pub | Map `TypeKind` → target-level type string (e.g., `"target: i32"`). Mirror of `typeKindSrcStr` with "target:" prefix. | diagnostic message construction | (none) | (pure) | Same pattern as src variant. | None [inference] |

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
  1. sortDiagnostics(diags)
  2. for each diag:
     a. if file_id==0: "level[code]: message"
     b. else:
        - loc = sourceManagerGetLocation(file_id, span_start)
        - fname = sourceManagerGetFileName(file_id)
        - print "fname:line:col: level[code]: message"
        - print source line (via content + line offsets)
        - print caret underline (^^^^) under span
        - print notes (up to 3)
        - print related span (if any)
```

---

## 4. `source_manager.zig` — Source File Manager (158 lines)

### Structs

**`SourceFile`** (`source_manager.zig:8-12`) — Per-file data: `filename` (interned arena copy), `content` (full source text, arena copy), `line_offsets` (`*U32ArrayList` of byte offsets for each line start). [inference]

**`SourceFileArrayList`** (`source_manager.zig:14-19`) — Private dynamic array of `SourceFile`. Same pattern as `DiagnosticArrayList` but non-public. [inference]

**`Location`** (`source_manager.zig:54-58`) — `file_id`, `line` (1-based), `col` (byte offset within line). [inference]

**`SourceManager`** (`source_manager.zig:60-63`) — Holds `*SourceFileArrayList` + `*Sand` allocator. [inference]

### Function Walkthrough

| Function | Line | Vis. | Purpose | Called By | Calls | Data Touched | Key Decisions | Markers |
|----------|------|------|---------|-----------|-------|-------------|---------------|---------|
| `sourceFileArrayListInit` | 21 | prv | Init empty `SourceFileArrayList` (zero len/cap, undefined items). | `sourceManagerInit` | (none) | SourceFileArrayList | Lazy arena allocation. | None [inference] |
| `sourceFileArrayListEnsureCapacity` | 30 | prv | Grow `SourceFile` array by 2x, min 8. | `sourceFileArrayListAppend` | `alloc_mod.sandAlloc` | items, capacity | Same pattern as other ArrayList helpers. | None [inference] |
| `sourceFileArrayListAppend` | 44 | prv | Append `SourceFile` to array. | `sourceManagerAddFile` | `sourceFileArrayListEnsureCapacity` | items, len | Standard append. | None [inference] |
| `sourceFileArrayListGetSlice` | 50 | prv | Return source files as `[]SourceFile`. | `sourceManagerGetFileName`, `sourceManagerGetSourceContent`, `sourceManagerGetLineOffsets`, `sourceManagerGetLocation` | (none) | items, len | Slice of live data. | None [inference] |
| `sourceManagerInit` | 65 | pub | Init SourceManager. Allocates `SourceFileArrayList` on arena (16 bytes, 4-aligned). | `main.zig` setup | `alloc_mod.sandAlloc`, `sourceFileArrayListInit` | SourceManager | Same heap-alloc pattern as DiagnosticCollector. | None [inference] |
| `sourceManagerAddFile` | 75 | pub | Add a source file. Copies filename and content to arena. Pre-allocates line offsets (`content.len/40 + 16`, min 64). Appends 0 as first offset. Scans content for `\n`, appends `i+1` for each. Appends `SourceFile`. Returns file_id (1-based). | parser / import resolution | `sourceManagerCopyToArena`, `util_mod.max`, `alloc_mod.sandAlloc`, `ga_mod.u32ArrayListInit`, `ga_mod.u32ArrayListEnsureCapacity`, `ga_mod.u32ArrayListAppend`, `sourceFileArrayListAppend` | SourceFile, filename arena copy, content arena copy, line_offsets array | file_id = files.len (1-based, 0 reserved as null). Line offset heuristic: content.len/40 + 16. Manual `\n` scan. | None [inference] |
| `sourceManagerGetFileName` | 103 | pub | Get filename by file_id (1-based). Returns `""` for id=0 or empty files. Clamps oversized file_id to 1. | `diagnosticCollectorPrintAll` | `sourceFileArrayListGetSlice` | SourceFile array | 0 = null file, returns "". Clamp prevents OOB on corrupted file_id. | None [inference] |
| `sourceManagerGetSourceContent` | 112 | pub | Get source content by file_id. Same null/clamp logic as GetFileName. | `diagnosticCollectorPrintAll` | `sourceFileArrayListGetSlice` | SourceFile array | Same pattern. | None [inference] |
| `sourceManagerGetLineOffsets` | 121 | pub | Get line offsets array by file_id. Same null/clamp logic. | `diagnosticCollectorPrintAll` | `sourceFileArrayListGetSlice`, `ga_mod.u32ArrayListGetSlice` | line_offsets | Returns `[]u32` directly. | None [inference] |
| `sourceManagerGetLocation` | 130 | pub | Convert byte offset → `Location{file_id, line, col}`. Binary search line offsets for containing line. `line = line_idx + 1`, `col = offset - offsets[line_idx]`. Returns `{0,0,0}` for null file_id. | `diagnosticCollectorPrintAll` | `sourceFileArrayListGetSlice`, `ga_mod.u32ArrayListGetSlice`, `mem_mod.binary_search` | SourceFile, line_offsets | binary_search returns index where offsets[i] <= target. Line = index + 1 (1-based). Col = offset - line_start. | None [inference] |
| `sourceManagerCopyToArena` | 151 | prv | Copy byte slice to arena (alignment=1). Returns raw ptr. Undefined for empty slices. | `sourceManagerAddFile` | `alloc_mod.sandAlloc` | arena | Same pattern as `stringInternerCopyToArena`. | None [inference] |

### Data Flow — Source Management

```
sourceManagerAddFile("foo.zig", content):
  1. Copy filename + content to arena
  2. line_offsets = u32ArrayListInit(alloc)
     u32ArrayListEnsureCapacity(line_offsets, max(content.len/40+16, 64))
     u32ArrayListAppend(line_offsets, 0)
     for each \n in content:
         u32ArrayListAppend(line_offsets, byte_pos + 1)
  3. sourceFileArrayListAppend(SourceFile{filename, content, line_offsets})
  4. return files.len (1-based file_id)

sourceManagerGetLocation(manager, file_id, offset):
  1. offsets = getLineOffsets(file_id)
  2. line_idx = binary_search(offsets, offset)  // last offset <= target
  3. col = offset - offsets[line_idx]
  4. return Location{file_id, line_idx + 1, col}
```

---

## 5. `pal.zig` — Platform Abstraction Layer (142 lines)

### C Externs

(`pal.zig:5-10`) — Direct C FFI for `fopen`, `fread`, `fclose`, `fseek`, `ftell`, `c_exit`. No libc wrapper, raw `extern "c"` declarations. [inference]

File I/O constants: `SEEK_END=2`, `SEEK_SET=0`, `MODE_READ="rb"`. (`pal.zig:12-14`) [inference]

[updated: 2026-08-01] **F-S9 fd-type change** — the PAL file descriptors are now `usize`
(32-bit `unsigned int` in C89), not `i32`. The sentinel is
`INVALID_FD: usize = @intCast(usize, 0xFFFFFFFF)` (`pal.zig:70`) — all-ones matches both the
POSIX `-1` failure return (as `unsigned int`) and Win32 `INVALID_HANDLE_VALUE` at 32-bit width.
Callers test `fd == pal.INVALID_FD` instead of `fd == -1`. This fixes the Win32 handle
truncation bug (a `HANDLE` with bit 31 set was round-tripped through `int` and sign-extended
back to a different pointer). The C side (`zig_pal.c`) now returns/accepts the `PlatFile`
typedef (`void*` on Win32 / `int` on POSIX) and `PLAT_INVALID_FILE` is `((void*)-1)` (the
undefined `isize` in the old macro was removed — any `_WIN32` compile was a preprocessor error).

### Function Walkthrough

| Function | Line | Vis. | Purpose | Called By | Calls | Data Touched | Key Decisions | Markers |
|----------|------|------|---------|-----------|-------|-------------|---------------|---------|
| `readFile` | 19 | pub | Read entire file into arena memory. Copies path to null-terminated C buffer (max 511 bytes). Opens with `fopen` ("rb"), seeks to end for size, allocates arena buffer, reads content. Returns `?[]u8`. | parser / import resolver, main.zig root check (F-S10) | `fopen`, `fseek`, `ftell`, `fclose`, `fread`, `sandAlloc` | Sand arena, file system | Max path 511 bytes. Binary read. Arena allocation freed only by reset. OOM returns null (not panic). Null covers missing, empty (`ftell <= 0`), and oversize paths indistinguishably. | None [inference] |
| `fileExists` | 48 | pub | Check if file exists by attempting `fopen("rb")`. Returns bool. Max path 511 bytes. | import resolution | `fopen`, `fclose` | file system | Opens and closes; no memory allocation. Returns true for empty files (can't distinguish empty). | None [inference] |
| `fileOpen` | 72 | pub | Open/create/truncate a file for writing, return `usize` fd (`pal_file_open`). | `phase_C89Emission` multi-module branch | `pal_file_open` | file system | Returns `INVALID_FD` on failure (`pal.zig:79`); path capped 511 bytes. `flags` stays `i32`. | None [inference] |
| `fileWrite` | 84 | pub | Write bytes to fd via `pal_file_write(fd: usize, …)`. | `bufferedWriterFlush` | `pal_file_write` | file system | fd is `usize` (F-S9). | None [inference] |
| `fileClose` | 88 | pub | Close fd via `pal_file_close(fd: usize)`. | `phase_C89Emission` multi-module branch | `pal_file_close` | file system | fd is `usize` (F-S9). | None [inference] |
| `stdout_write` | 62 | pub | Write bytes to stdout (fd 1) via `ext_c.write`. | `c89_emit.zig` output | `ext_c.write` | stdout | Direct syscall wrapper. | None [inference] |
| `stderr_write` | 66 | pub | Write bytes to stderr (fd 2) via `ext_c.write`. | diagnostics, allocator OOM, panic, main.zig F-S10 root check | `ext_c.write` | stderr | Direct syscall wrapper. | None [inference] |
| `exit` | 92 | pub | Exit process with code via `c_exit`. Infinite loop after as safety net. | `diagnosticCollectorFlushAndExit`, OOM/ICE, main.zig error paths | `c_exit` | process | Hard exit. `main.zig` uses `pal.exit(1)` for the F-S10 input-file check. | None [inference] |
| `initArgs` | 100 | pub | Store argc/argv from C `main()` into module-level globals. | `main.zig` entry | (none) | `saved_argc`, `saved_argv` | Called once from C main. | None [inference] |
| `argCount` | 105 | pub | Return saved argc. | CLI parsing | (none) | `saved_argc` | Accessor. | None [inference] |
| `argGet` | 109 | pub | Return argv[i] as `[*]const u8`. | CLI parsing | (none) | `saved_argv` | Direct pointer access. | None [inference] |
| `markersEnabled` | 115 | pub | Set `g_markers_enabled` flag (0=off, nonzero=on). | `main.zig` CLI arg parsing (`--markers`) | (none) | `g_markers_enabled` | Enable/disable debug markers. | None [inference] |
| `markerWrite` | 125 | pub | Conditional stderr write: if `g_markers_enabled != 0`, writes message. | `markerWriteInt`, phase debug code | `stderr_write` | stderr | Guarded by global flag — zero-cost when disabled (just one cmp). | None [inference] |
| `markerWriteInt` | 131 | pub | Conditional stderr write with int suffix: writes prefix + decimal value + newline. Uses `itoa` for formatting. | `stringInternerIntern` (INT: markers), phase markers | `markerWrite`, `itoa_mod.itoa` | stderr, local buf | Fixed-width format. | `INT:tl`, `INT:t0`, `INT:dup`, `INT:new` [inference] |

---

## 6. `growable_array.zig` — Typed Dynamic Arrays (260 lines)

### Array Types

All follow the same pattern: struct with `items`, `len`, `capacity`, `allocator`, plus `Init`, `EnsureCapacity`/`Grow`, `Append`, `GetSlice`. Some also have `PopOrNull`.

| Type | Element | Line | Init | Growth | Special Notes |
|------|---------|------|------|--------|---------------|
| `U32ArrayList` | `u32` | 4 | `u32ArrayListInit(allocator)` — zero-cap lazy | 2x, min 8, 4-byte align | Has `u32ArrayListPopOrNull` (returns `?u32`) |
| `U8ArrayList` | `u8` | 50 | `byteArrayListInit(allocator)` | 2x, min 8, 1-byte align | Uses `byteArrayListGrow` (not `EnsureCapacity`) |
| `AstNodeArrayList` | `AstNode` | 90 | `astNodeArrayListInit(allocator, initial_capacity)` — eager pre-alloc | 2x, min 8, 4-byte align | `initial_capacity` arg; element size from `@sizeOf(AstNode)` |
| `U64ArrayList` | `u64` | 134 | `u64ArrayListInit(allocator, initial_capacity)` — eager pre-alloc | 2x, min 8, 4-byte align | 8-byte elements |
| `F64ArrayList` | `f64` | 176 | `f64ArrayListInit(allocator, initial_capacity)` — eager pre-alloc | 2x, min 8, 4-byte align | 8-byte elements |
| `FnProtoArrayList` | `FnProto` | 218 | `fnProtoArrayListInit(allocator, initial_capacity)` — eager pre-alloc | 2x, min 8, 4-byte align | Uses `@sizeOf(FnProto)` |

### Function Walkthrough (by pattern, one representative entry)

All arrays share these functions with the same logic, differing only in element type and size:

**U32ArrayList** (`growable_array.zig:4-48`):

| Function | Line | Purpose | Key Details |
|----------|------|---------|-------------|
| `u32ArrayListInit` | 11 | Init with zero len/cap, undefined items. | Lazy — no allocation. |
| `u32ArrayListEnsureCapacity` | 20 | Grow to `new_capacity`. 2x factor, min 8. `sandAlloc(4 * new_cap, 4)`. Copies old. | `@sizeOf(u32) = 4`. |
| `u32ArrayListAppend` | 34 | Ensure +1, store at `items[len]`, increment. | Standard. |
| `u32ArrayListPopOrNull` | 40 | Decrement len, return old last value. Returns `null` if empty. | Only on U32ArrayList. |
| `u32ArrayListGetSlice` | 46 | Return `items[0..len]` as slice. | Standard. |

**U8ArrayList** (`growable_array.zig:50-88`):

| Function | Line | Purpose | Key Details |
|----------|------|---------|-------------|
| `byteArrayListInit` | 57 | Init with zero len/cap, undefined items. | Lazy. |
| `byteArrayListGrow` | 66 | Grow to `new_capacity`. 2x, min 8. `sandAlloc(1 * new_cap, 1)`. | Named `Grow` not `EnsureCapacity`. Alignment=1. |
| `byteArrayListAppend` | 80 | Ensure +1, store value, increment. | Standard. |
| `byteArrayListGetSlice` | 86 | Return slice. | Standard. |

**AstNodeArrayList** (`growable_array.zig:90-132`):

| Function | Line | Purpose | Key Details |
|----------|------|---------|-------------|
| `astNodeArrayListInit` | 99 | Init WITH pre-allocation to `initial_capacity`. | Eager — calls `EnsureCapacity`. |
| `astNodeArrayListEnsureCapacity` | 110 | 2x, min 8. `sandAlloc(@sizeOf(AstNode) * new_cap, 4)`. | Size via comptime `@sizeOf`. |
| `astNodeArrayListAppend` | 124 | Ensure +1, store, increment. | Standard. |
| `astNodeArrayListGetSlice` | 130 | Return slice. | Standard. |

**U64ArrayList** (`growable_array.zig:134-174`):

| Function | Line | Purpose | Key Details |
|----------|------|---------|-------------|
| `u64ArrayListInit` | 141 | Init with pre-allocation to `initial_capacity`. | Eager. |
| `u64ArrayListEnsureCapacity` | 152 | 2x, min 8. `sandAlloc(8 * new_cap, 4)`. | 8-byte elements. |
| `u64ArrayListAppend` | 166 | Standard. | |
| `u64ArrayListGetSlice` | 172 | Standard. | |

**F64ArrayList** (`growable_array.zig:176-216`):

| Function | Line | Purpose | Key Details |
|----------|------|---------|-------------|
| `f64ArrayListInit` | 183 | Init with pre-allocation. | Eager. |
| `f64ArrayListEnsureCapacity` | 194 | 2x, min 8. `sandAlloc(8 * new_cap, 4)`. | 8-byte elements. |
| `f64ArrayListAppend` | 208 | Standard. | |
| `f64ArrayListGetSlice` | 214 | Standard. | |

**FnProtoArrayList** (`growable_array.zig:218-260`):

| Function | Line | Purpose | Key Details |
|----------|------|---------|-------------|
| `fnProtoArrayListInit` | 227 | Init with pre-allocation. | Eager. |
| `fnProtoArrayListEnsureCapacity` | 238 | 2x, min 8. `sandAlloc(@sizeOf(FnProto) * new_cap, 4)`. | Size via `@sizeOf`. |
| `fnProtoArrayListAppend` | 252 | Standard. | |
| `fnProtoArrayListGetSlice` | 258 | Standard. | |

All arrays: allocation is fatal on OOM (`catch unreachable`). No shrink. Arena-allocated — never freed individually.

---

## 7. `panic.zig` — ICE Panic Handler (21 lines)

| Function | Line | Vis. | Purpose | Called By | Calls | Data Touched | Key Decisions | Markers |
|----------|------|------|---------|-----------|-------|-------------|---------------|---------|
| `panicHandler` | 4 | pub | Print `"ICE: <msg> at <file>:<line>\n"` to stderr, then `pal.exit(3)`. | `sandAlloc` (OOM), `stringInternerCopyToArena`, etc. | `pal.stderr_write`, `itoa_mod.itoa`, `pal.exit` | stderr | ICE exit code = 3. Formats line number via itoa. | None [inference] |

---

## 8. `util/mem.zig` — Memory Utilities (25 lines)

| Function | Line | Vis. | Purpose | Called By | Calls | Data Touched | Key Decisions | Markers |
|----------|------|------|---------|-----------|-------|-------------|---------------|---------|
| `mem_eql` | 1 | pub | Compare two byte slices for equality. Short-circuits on length mismatch. | `stringInternerIntern` (hash chain walk) | (none) | (pure) | O(n) comparison after hash check. | None [inference] |
| `binary_search` | 9 | pub | Find last index where `offsets[i] <= target`. Standard lower-bound binary search minus 1. Returns 0 if target before first offset. | `sourceManagerGetLocation`, `diagnosticCollectorPrintAll` (line lookup) | (none) | offsets array | Returns `lo - 1` after standard binary search lower-bound. | None [inference] |

---

## 9. `util/format.zig` — Formatters (153 lines)

| Function | Line | Vis. | Purpose | Called By | Calls | Key Details |
|----------|------|------|---------|-----------|-------|-------------|
| `copyStr` | 1 | pub | Copy `s` into `buf` at `*idx`, incrementing idx as bytes are written. | string construction | (none) | Raw byte copy with cursor. |
| `formatU32` | 10 | pub | Format u32 to decimal in buf (right-to-left, null-terminated). Returns slice of formatted portion. | diagnostics, debug output | (none) | Writes from end of buffer backwards. Null-terminated. |
| `formatU64` | 29 | pub | Same as formatU32 for u64. | (future use?) | (none) | Same backward-write pattern. |
| `extractDigit` | 48 | pub | Floor of f64 to integer 0-9. If-then chain: `v >= 9 → 9`, ..., `v >= 1 → 1`, else 0. | `formatF64` | (none) | Integer conversion for float formatting. |
| `formatF64` | 61 | pub | Format f64 to string. Handles negative, normalizes to 1-10 range, extracts 6 significant digits, optionally adds decimal and scientific notation (e±N). | (future use?) | `extractDigit` | 6-digit precision. Handles neg/frac/sci. Null-terminated. |

---

## 10. `util/itoa.zig` — Integer to ASCII (35 lines)

| Function | Line | Vis. | Purpose | Called By | Calls | Key Details |
|----------|------|------|---------|-----------|-------|-------------|
| `itoa` | 1 | pub | Convert `u32` to decimal string in buffer. Returns character count (not including null terminator). Writes from buffer end, null-terminated. | `printUsize`, `markerWriteInt`, `panicHandler`, `diagnosticCollectorPrintAll` | (none) | Backward fill. Buffer MUST have space. Returns `buf.len - i - 1`. |
| `itoa64` | 19 | pub | Same as `itoa` for `u64`. | (future use?) | (none) | Same backward-fill pattern. |

---

## 11. `util/util.zig` — Misc Math (15 lines)

| Function | Line | Vis. | Purpose | Called By | Key Details |
|----------|------|------|---------|-----------|-------------|
| `min` | 1 | pub | Return smaller of two u32 values. | (callers of utility) | Simple if-else. |
| `max` | 9 | pub | Return larger of two u32 values. | `sourceManagerAddFile` (capacity calc) | If-else. |

---

## 12. `util/hash.zig` — Hash Functions + Hash Maps (236 lines)

### Hash Function

| Function | Line | Vis. | Purpose | Called By | Calls | Key Details |
|----------|------|------|---------|-----------|-------|-------------|
| `fnv1a` | 4 | pub | 32-bit FNV-1a non-cryptographic hash. Initial value 2166136261, XOR each byte, multiply by 16777619 (modular). | `stringInternerIntern` | (none) | Standard FNV-1a. Used for string interning. |

### Hash Maps

Three hash map types sharing the same design: open addressing (linear probing), power-of-2 capacity (mask = capacity-1), load factor threshold 75% (count*4 >= capacity*3 triggers grow). Maps are:

| Type | Key | Value | Struct Line | Init | Get | Put (public) | Grow (private) |
|------|-----|-------|-------------|------|-----|-------------|----------------|
| `U32ToU32Map` | `u32` | `u32` | 13 | `u32ToU32MapInit` (line 22) | `u32ToU32MapGet` (line 29) | `u32ToU32MapPut` (line 73) | `u32ToU32MapGrow` (line 40) |
| `U64ToU32Map` | `u64` | `u32` | 88 | `u64ToU32MapInit` (line 97) | `u64ToU32MapGet` (line 104) | `u64ToU32MapPut` (line 148) | `u64ToU32MapGrow` (line 115) |
| `U32ToU64Map` | `u32` | `u64` | 163 | `u32ToU64MapInit` (line 172) | `u32ToU64MapGet` (line 179) | `u32ToU64MapPut` (line 223) | `u32ToU64MapGrow` (line 190) |

**Key design for all maps:**
- **Key indexing:** `U32ToU32Map`/`U32ToU64Map` use `@intCast(usize, key) & mask` (low bits of key as probe start). `U64ToU32Map` uses `@intCast(usize, @intCast(u32, key & 0xFFFFFFFF)) & mask` (low 32 bits of key).
- **Probing:** Linear probing with wrap-around: `i = (i + 1) & mask`.
- **Grow:** Double capacity (min 8). Allocates 3 separate arrays (keys, values, occupied byte). Rehashes all entries.
- **Put:** Check load factor first (≥75% triggers grow). Find slot via probing. If key exists: update value. If empty: fill slot, mark occupied.
- **Get:** Null if capacity=0. Probe from `key & mask`. Return `null` if slot unoccupied.
- **Delete:** Not supported. No tombstone mechanism.
- **Init:** Zero capacity (lazy). First `put` that hits capacity=0 triggers growth.

**Detailed: U32ToU32Map functions:**

| Function | Line | Vis. | Purpose | Key Details |
|----------|------|------|---------|-------------|
| `u32ToU32MapInit` | 22 | pub | Zero-capacity lazy init. | No allocation. |
| `u32ToU32MapGet` | 29 | pub | Lookup key, return `?u32`. Returns null if not found or capacity=0. | Linear probe via `(i+1) & mask`. |
| `u32ToU32MapGrow` | 40 | prv | Double capacity (min 8). Allocate keys (4*cap, 4-align), values (4*cap, 4-align), occupied (1*cap, 4-align). Zero all occupied. Rehash old entries. | 3 separate allocs. Copies old arrays then rehashes. |
| `u32ToU32MapPut` | 73 | pub | Insert or update key-value. Check load ≥75% first. Then probe for slot. | Update-if-exists semantics. Grows before insert if needed. |

**U64ToU32Map** — Same structure, key size 8 bytes, value size 4 bytes. Key index uses lower 32 bits. (`hash.zig:88-161`)

**U32ToU64Map** — Same structure, key size 4 bytes, value size 8 bytes. (`hash.zig:163-236`)

---

## Data Flow — Heap / Arena Usage

### Arena Sizing

```
perm_arena_buf[1048576]   = 1 MB
mod_arena_buf[1572864]    = 1.5 MB
scr_arena_buf[1572864]    = 1.5 MB
Combined: 4 MB (DEV_MAX_MEM=8 MB allows 2x headroom)
```

### Who Allocates Where

| Arena | Contents | Reset Behavior |
|-------|----------|----------------|
| Permanent | StringInterner, SourceManager, DiagnosticCollector, interned strings, ModuleRegistry, SymbolRegistry, TypeRegistry, hash maps, const_alias_prepass, type_resolver intermediates | Never reset |
| Module | AstStore (all AST nodes), ResolvedTypeTable, CoercionTable, LirFunctionArrayList, call_arg_types/comptime_values | Never reset |
| Scratch | Per-phase temporaries: parser tokens, DepGraph per phase, TypeResolver workspace, analyzer state, lowerer BasicBlocks, c89 emitter | Reset at phase start |

> **DepGraph correction (P10, `[fprintf]`):** the live DepGraph is **scratch-local, one per
> phase**. `phase_SymbolRegistration` (`main.zig:262`) and `phase_TypeResolution`
> (`main.zig:292`) each call `depGraphInit(&ctx.alloc.scratch)` after their `sandReset`;
> phase 3 does not consume phase 2's graph. The module-arena DepGraph referenced here is the
> `ctx.dep_graph` field (`main.zig:154`), which the pipeline **never populates** (len stays 0
> in all 4 example runs) — it is a dead field.

### CompilerAlloc Init Sequence (main.zig)

```
initCompilerAlloc():
  permanent ← sandInit(perm_arena_buf)
  module    ← sandInit(mod_arena_buf)
  scratch   ← sandInit(scr_arena_buf)
  set tier names: "perm", "module", "scratch"
  max_mem = DEV_MAX_MEM (8 MB)

Then subsystems allocate from permanent arena:
  stringInternerInit(&permanent, 64)    → interner buckets/entries
  sourceManagerInit(&permanent)         → SourceFileArrayList
  diagnosticCollectorInit(&permanent)   → DiagnosticArrayList
```

### TrackingAllocator Per-Phase

> **P10 correction `[grep]`:** the pattern below is **aspirational — not used.** No phase in
> `sf/src/` calls `trackingAllocatorInit`/`trackingAlloc`/`trackingReset`/`trackingPeak`;
> `TrackingAllocator` (allocator.zig:121-164) is only defined, never wired in. Phases allocate
> directly through `sandAlloc`. Per-phase peaks were measured in P10 by reading each tier's
> `peak` field at phase boundaries, not via `TrackingAllocatorReport`.

Each phase that tracks memory creates a `TrackingAllocator` wrapping the scratch arena:

```
var track = trackingAllocatorInit(&compiler.allocator.scratch);
// ... phase work using trackingAlloc(&track, ...) ...
var report = trackingAllocatorReport(&track);
// report.peak, report.total, report.count
trackingReset(&track);  // also sandReset(scratch)
```

### Memory Budget Checkpoints

`checkCombinedPeak` is called at phase boundaries (after import resolution, after type resolution). If `perm_kb + mod_kb + scr_kb > max_mem_kb`, compiler exits with error.

### Empirical Arena Peaks — P10 evidence `[markers]` + `[fprintf]`

`--track-memory` final values (release zig1, all 4 examples, exit 0, zero diagnostics) confirm
the tier sizing is ample:

| Example | perm | mod | scr | total |
|---------|------|-----|-----|-------|
| `mud_server` | 72K | 103K | 184K | 359K |
| `game_of_life` | 65K | 92K | 186K | 343K |
| `lisp_interpreter_curr` | 118K | 412K | 844K | 1374K |
| `json_parser` | 52K | 197K | 376K | 625K |

**Behavior confirmed empirically** `[fprintf]` (per-phase `peak` reads at each phase boundary,
debug build — identical to release `--track-memory` final values):

1. **`sandResetPeak` (allocator.zig:51) masks earlier scratch usage.** `phase_StaticAnalyzers`
   calls `sandReset` + `sandResetPeak` at entry (`main.zig:472-473`), zeroing the scratch
   `peak`. The final `track-memory` `scr=` therefore reports only the max of LIR lowering /
   C89 emission scratch (phases 6-8), **not** the pipeline-wide high-water mark. Pre-reset
   scratch peaks (phases 1-5) were ~100K (mud/gol/json) and ~208K (lisp) — all below the
   post-reset phase-8 values here, so the reported `scr=` happens to be the global max, but
   only by coincidence.
2. **Scratch is dominated by C89 emission**, not parsing: per-example max scratch was
   import≈103/100/208/101K but c89 reached 184/186/844/376K.
3. **Module arena grows most during sema** (ResolvedTypeTable/CoercionTable/enum_value_table
   writes): mud 62→96K, gol 61→90K, lisp 238→399K, json 121→191K across phase 5.
4. **Permanent arena grows most during C89 emission** (type/ident name interning): mud 33→72K,
   gol 19→65K, lisp 87→118K across phase 8.
5. **`TrackingAllocator` is currently unused by `main.zig`** — the pipeline calls plain
   `sandAlloc`; `trackingAlloc*`/`trackingReset` exist in `allocator.zig:121-164` but no phase
   wires one in. Per-phase peaks were obtained in P10 by reading `peak` directly, not via
   `TrackingAllocatorReport`.
6. The **`TypeRegistry` type_db sand** is a separate 128KB **stack** buffer (`main.zig:145-146`),
   not part of `CompilerAlloc`; `track-memory` does not include it.

---

## Debugging — Markers, GDB, Isolation

### Adding a Debug Marker

```
pal.markerWrite("PHASE:start");
pal.markerWriteInt("COUNT:", 42);
```

Output (with `--markers`): `PHASE:start\nCOUNT:42\n`

Markers are conditionally written — disabled by default, enabled via `markersEnabled(1)` from CLI arg `--markers`. Zero overhead when disabled (single compare).

### Known Marker Values from string_interner.zig

| Marker | Location | Meaning |
|--------|----------|---------|
| `INT:tl` | `stringInternerIntern:89` | Total length of text being interned |
| `INT:t0` | `stringInternerIntern:90` | First byte of text (if non-empty) |
| `INT:dup` | `stringInternerIntern:102` | Found duplicate — returning existing ID |
| `INT:new` | `stringInternerIntern:108` | New internment — allocated new ID |

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
- OOM: increase arena sizes in `allocator.zig:74-76` or widen `DEV_MAX_MEM`.
- Interner hash chain: markers `INT:tl`, `INT:t0`, `INT:dup`, `INT:new` show interning pattern.
- Diagnostics: insert `diagnosticCollectorAdd` early to test error paths.
- TrackingAllocator: wrap a phase's allocations to measure peak/total separately.
