# Allocation-savings census — zig1 `-s0` self-compile

Plan: `docs/superpowers/plans/2026-10-06-zig1-live-set-reduction-plan.md` (Task 1)
Spec: `docs/superpowers/specs/2026-10-06-zig1-live-set-reduction-design.md` (§Workstream 1)
Task 0 baseline: `task-0-report.md` (post-L3: pool 14,924K; carve module 5,382,144 / diag_read 4,655,313 /
perm 2,558,152 / import_scratch 1,385,155 / type_db 1,032,192 / scratch 223,519 / Σ 15,236,475).
Frozen HEAD: `1bb72f62`; seed binary `/tmp/liveset_seed/zig1_5_clean` (md5 `2293f756…`).

READ-ONLY. No `sf/src` file was modified, no seed rotated, no dump-MD5 re-baselined.
**Fix round 1 applied** (10 reviewer findings) — see `task-1-report.md` §Fix round 1.

## Method (all numbers measured in-session)

1. **Closure.** The self-compile emits 48 `.c`; mapping basenames back to source gives the
   **45-module closure** listed in `task-1-report.md`. Everything below is restricted to it.
2. **Enumerate.** `sandAlloc(` occurrences, `*ArrayList` ensure/grow/init/append definitions and
   call sites, `growableSandInit`, `*ArrayList` box allocations, `SpillStore` opens, inline `[N]`
   fields.
3. **Instrument (throwaway).** A `/tmp` gdb Python probe breaks at `zF_1395EB68_sandAlloc`, reads the
   hidden-sret args at `[ebp+0xc]` (sand) / `[ebp+0x10]` (size), the arena name from `sand+16/20`, and
   the return address, aggregating `(caller, arena, size) -> (calls, bytes)` over the whole run.
   **682,537 `sandAlloc` calls; 272,667,671 B cumulative** (churn, not footprint). No repo artifact.
   The probe's per-arena cumulative reproduces the frozen baselines **exactly**:
   `module 5,418.7K` == prior max-live 5,419K; `diag_read 2,913.4K` == prior live 2,913.4K;
   `unknown` (pool) `14,924.5K` == `pool=14924K`. This validates the method.
4. **Touched vs carved (L3 lesson).** `sandAlloc` is a bump: it does **not** zero. Bytes that are
   *allocated but never written* are carved-but-not-touched and do **not** raise RSS. Conversely,
   old buffers read during an alloc+copy grow **are** touched (resident) and then abandoned. Every
   estimate below states which it is. (Exception found in this census: pre-sized arrays like the
   interner entries are allocated in full but only the used prefix is written, so their tail is
   carved-but-not-touched — see §Over-sizing.)

## Site-count verification (spec cited "~249 sandAlloc/ArrayList sites")

| entry-point class | count in closure |
|---|---:|
| `sandAlloc(` textual occurrences (232 in all `sf/src`) | 215 |
| `sandAlloc` direct call lines (212 lines total incl. the definition; 3 lines hold two calls) | **211 lines / 214 calls** |
| `*ArrayList` struct types | 23 |
| `*ArrayList` ensure/grow allocation functions (`…EnsureCapacity`/`…Grow`/`ArrayGrow`/`ArrayListEnsureCapacityBytes`) | 33 |
| `growableSandInit` **call** sites (`allocator.zig:272-276` ×5, `import_resolver` ×3, `main` ×1, `source_manager` ×1) | **10** (line 99 is the def) |
| `SpillStore`-bearing structs / `spillOpen` **call** sites | 5 / **7** |
| inline `[N]` buffer fields (non-zero) | **16** |

**Verified total: 214 `sandAlloc` call occurrences + 33 ArrayList allocator fns + 10 growableSandInit
calls + 7 spillOpen calls + 16 inline `[N]` fields = 280 entry points** (matches the reviewer's
corrected ~280; the spec's ~249 was an approximation closest to `sandAlloc` occurrences + ArrayList
ensure/grow call sites).

**Fix round 1 corrections to the earlier draft:** spillOpen 9→**7**; growableSandInit 11→**10**
(10 calls + 1 def); inline fields 14→**16**; `spill_path` singletons 5→**8 live buffers** (four
`AstValuePool` instances embedded in `AstStore` each own one, `ast.zig:326`; see §Inline buffers).

## Table 1 — per allocator entry point (measured)

`bytes` is the cumulative `sandAlloc` traffic attributed to the function containing the call
(682,537 calls total). For never-reset arenas (`module`/`perm`/`type_db`) this equals the carved
footprint (modulo allocated-but-unwritten tails); for reset arenas
(`scratch`/`lir_read`/`source`/`import_scratch`/`diag_read`) it is churn.

| allocator entry point (fn) | file:line | arena breakdown | calls | bytes | direct `sandAlloc` sites in fn |
|---|---|---|---:|---:|---:|
| `lirStreamReadFunction` | `sf/src/lir_stream.zig:184` | lir_read 154990.4K | 363692 | 158710144 | 9 |
| `lirInstArrayListEnsureCapacity` | `sf/src/lir.zig:263` | scratch 37634.2K | 49775 | 38537472 | 1 |
| `growableSandGrow` | `sf/src/allocator.zig:118` | unknown 14880.0K | 68 | 15237155 | 2 |
| `emitHoistedDecls` | `sf/src/c89_emit.zig:3187` | scratch 11093.5K, emission 58.0K | 24243 | 11419170 | 23 |
| `readFile` | `sf/src/pal.zig:25` | source 2790.2K, diag_read 2711.1K, import_scratch 2686.3K, scratch 103.9K | 137 | 8490448 | 1 |
| `allocU32Raw` | `sf/src/lir_opt_pass.zig:2137` | scratch 7637.8K | 70814 | 7821064 | 1 |
| `tempDeclArrayListEnsureCapacity` | `sf/src/lir.zig:389` | scratch 3748.9K | 6299 | 3838848 | 1 |
| `lowererInit` | `sf/src/lower.zig:402` | scratch 3097.5K | 14868 | 3171840 | 9 |
| `u32ToU32MapInitCap` | `sf/src/util/hash.zig:39` | scratch 2859.8K, emission 145.1K, perm 1.1K | 9942 | 3078144 | 3 |
| `u32ToU32MapGrow` | `sf/src/util/hash.zig:66` | module 1763.7K, emission 367.5K, scratch 154.9K, perm 3.4K, type_db 0.5K | 651 | 2344896 | 3 |
| `allocU32With_1` | `?:0` | scratch 2065.0K | 4836 | 2114568 | 0 |
| `basicBlockArrayListInit` | `sf/src/lir.zig:300` | scratch 1918.1K | 3144 | 1964160 | 0 |
| `allocU8Raw_1` | `?:0` | scratch 1548.8K | 14508 | 1585926 | 0 |
| `comptimeFoldTableGrow` | `sf/src/comptime_eval.zig:70` | module 1535.2K | 11 | 1572096 | 1 |
| `stringInternerInit` | `sf/src/string_interner.zig:64` | perm 1474.2K | 2 | 1509576 | 2 |
| `allocU64Raw` | `sf/src/lir_opt_pass.zig:2142` | scratch 1376.7K | 1612 | 1409712 | 1 |
| `stateMapFork` | `sf/src/state_map.zig:62` | scratch 1214.6K | 51822 | 1243728 | 1 |
| `lirSideEntryArrayListInit` | `sf/src/lir.zig:214` | scratch 1160.5K | 1973 | 1188320 | 0 |
| `stateMapEnsureCapacity` | `sf/src/state_map.zig:27` | scratch 1121.4K | 16262 | 1148352 | 1 |
| `astSlotEnsureNodeCap` | `sf/src/ast.zig:739` | module 862.5K | 14 | 883200 | 1 |
| `u64ToU32MapGrow` | `sf/src/util/hash.zig:174` | type_db 440.0K, emission 207.9K, module 207.8K | 198 | 876200 | 3 |
| `emitNestCompute` | `sf/src/c89_emit.zig:4142` | scratch 464.2K | 1612 | 475299 | 1 |
| `u32ArrayListEnsureCapacity` | `sf/src/growable_array.zig:20` | module 259.9K, diag_read 201.6K, emission 0.5K | 78 | 473112 | 1 |
| `stringInternerCopyToArena` | `sf/src/string_interner.zig:145` | perm 418.5K | 34020 | 428506 | 1 |
| `growLocalDecls` | `sf/src/lower.zig:1935` | scratch 345.0K | 414 | 353280 | 9 |
| `typeRegistryEnsureCapacity` | `sf/src/type_registry.zig:179` | type_db 255.0K | 8 | 261120 | 1 |
| `arrayListEnsureCapacityBytes` | `sf/src/lower.zig:119` | scratch 219.9K | 2801 | 225184 | 1 |
| `arrayGrow` | `sf/src/type_registry.zig:160` | type_db 211.6K | 77 | 216640 | 1 |
| `lowerFn` | `sf/src/lower.zig:8894` | scratch 196.5K | 1623 | 201252 | 1 |
| `coercionTableEnsureCapacity` | `sf/src/coercion.zig:51` | module 191.9K | 11 | 196512 | 1 |
| `lirParamArrayListEnsureCapacity` | `sf/src/lir.zig:349` | scratch 148.9K | 1569 | 152448 | 1 |
| `astSlotEnsurePayloadCap` | `sf/src/ast.zig:755` | module 143.8K | 14 | 147200 | 1 |
| `valuePoolEnsureCache` | `sf/src/ast.zig:590` | module 128.0K | 4 | 131072 | 1 |
| `constAliasPrepass` | `sf/src/const_alias_prepass.zig:61` | perm 109.3K | 6 | 111892 | 6 |
| `u64ToU32MapInitCap` | `sf/src/util/hash.zig:147` | emission 104.0K | 3 | 106496 | 3 |
| `semanticAnalyzerAllocCopyU32` | `sf/src/semantic_analyzer.zig:565` | scratch 99.2K | 691 | 101632 | 1 |
| `classifyTypeEmissionGroups` | `sf/src/type_resolver.zig:662` | perm 95.3K | 6 | 97560 | 6 |
| `allocU32` | `sf/src/async_analysis.zig:51` | module 86.6K | 5 | 88712 | 2 |
| `u32ArrayListAppendInner` | `sf/src/ast.zig:148` | parser 69.6K | 1429 | 71296 | 2 |
| `lowerModuleInit` | `sf/src/lower.zig:9016` | scratch 67.1K | 348 | 68694 | 12 |
| `u32ArrayListAppen_1` | `?:0` | module 64.0K | 11 | 65504 | 0 |
| `fnProtoArrayListAppendInner` | `sf/src/ast.zig:240` | module 63.9K | 9 | 65408 | 1 |
| `depGraphEnsureCapacity` | `sf/src/symbol_registrator.zig:39` | scratch 48.1K | 6 | 49280 | 1 |
| `lirSlotArrayListEnsureCapacity` | `sf/src/lir.zig:476` | emission 48.0K | 10 | 49104 | 1 |
| `astBlockTableEnsure` | `sf/src/ast.zig:686` | module 45.0K | 72 | 46080 | 1 |
| `emitFunctionBody` | `sf/src/c89_emit.zig:9089` | scratch 29.9K, emission 15.0K | 1617 | 45932 | 2 |
| `growableSandInit` | `sf/src/allocator.zig:99` | unknown 44.5K | 13 | 45568 | 1 |
| `switchCaseArrayListInit` | `sf/src/lir.zig:420` | scratch 39.8K | 109 | 40704 | 0 |
| `u64ArrayListEnsureCapacity` | `sf/src/growable_array.zig:163` | module 30.0K | 4 | 30720 | 1 |
| `tstTopologicalSort` | `sf/src/c89_emit.zig:1454` | emission 29.3K | 3 | 29964 | 3 |
| `phase_C89Emission` | `sf/src/main.zig:1183` | emission 28.0K | 48 | 28660 | 4 |
| `valuePoolEnsureHead` | `sf/src/ast.zig:549` | module 16.0K | 4 | 16384 | 1 |
| `rttEnsureCache` | `sf/src/resolved_type_table.zig:113` | module 16.0K | 1 | 16360 | 1 |
| `symbolTableEnsureCapacity` | `sf/src/symbol_table.zig:43` | perm 10.3K | 47 | 10528 | 1 |
| `nameScopeGrowPair` | `sf/src/type_resolver.zig:100` | scratch 8.7K | 186 | 8896 | 2 |
| `typeResolverBuild` | `sf/src/type_resolver.zig:508` | scratch 8.5K | 1 | 8672 | 1 |
| `inDegreeEnsureCapacity` | `sf/src/type_resolver.zig:240` | scratch 8.5K | 1 | 8672 | 1 |
| `joinPath` | `sf/src/module_registry.zig:135` | import_scratch 8.1K, scratch 0.0K | 400 | 8328 | 1 |
| `globalDeclArrayListInit` | `sf/src/lir.zig:560` | emission 7.1K | 4 | 7232 | 0 |
| `moduleEntryArrayListInit` | `sf/src/module_registry.zig:47` | perm 6.1K | 4 | 6240 | 0 |
| `byteArrayListGrow` | `sf/src/growable_array.zig:66` | module 4.0K, scratch 0.3K | 49 | 4408 | 1 |
| `importEdgesEnsureCapacity` | `sf/src/module_registry.zig:248` | perm 4.0K | 7 | 4064 | 1 |
| `sourceFileArrayListInit` | `sf/src/source_manager.zig:25` | perm 3.3K | 4 | 3360 | 0 |
| `semanticAnalyzerGrowCapU32` | `sf/src/semantic_analyzer.zig:573` | scratch 3.0K | 122 | 3048 | 0 |
| `moduleRegistryFaultInPathToId` | `sf/src/module_registry.zig:487` | perm 2.2K | 3 | 2304 | 3 |
| `symbolRegistryEnsureCapacity` | `sf/src/symbol_table.zig:94` | perm 1.9K | 4 | 1920 | 1 |
| `c89EmitterInit` | `sf/src/c89_emit.zig:809` | emission 1.5K | 3 | 1536 | 3 |
| `sourceManagerCopyToArena` | `sf/src/source_manager.zig:255` | perm 1.0K | 47 | 1025 | 1 |
| `sourceManagerAddFile` | `sf/src/source_manager.zig:96` | perm 0.7K | 47 | 752 | 1 |
| `lexerInit` | `sf/src/lexer.zig:30` | scratch 0.7K | 47 | 752 | 1 |
| `sourceManagerFaultIn` | `sf/src/source_manager.zig:148` | diag_read 0.7K | 43 | 688 | 2 |
| `importQueuePendingEnsureCapacity` | `sf/src/module_registry.zig:555` | perm 0.5K | 4 | 480 | 1 |
| `initKeywordTable` | `sf/src/token.zig:149` | perm 0.4K | 1 | 456 | 1 |
| `f64ArrayListAppendInner` | `sf/src/ast.zig:210` | module 0.4K | 3 | 448 | 1 |
| `rawArrayEnsureCapacity` | `sf/src/type_resolver.zig:196` | scratch 0.3K | 2 | 320 | 1 |
| `diagnosticArrayListInit` | `sf/src/diagnostics.zig:389` | perm 0.3K | 1 | 320 | 0 |
| `deferQueueEnsureCapacity` | `sf/src/analyzer.zig:392` | scratch 0.3K | 3 | 288 | 1 |
| `diagnosticCollectorInit` | `sf/src/diagnostics.zig:453` | perm 0.2K | 3 | 208 | 1 |
| `sourceManagerInit` | `sf/src/source_manager.zig:82` | perm 0.1K | 2 | 76 | 2 |
| `computeModuleInitOrder` | `sf/src/main.zig:1043` | scratch 0.0K | 1 | 48 | 1 |
| `searchDirArrayListEnsureCapacity` | `sf/src/module_registry.zig:100` | perm 0.0K | 1 | 8 | 1 |

## Table 2 — every direct `sandAlloc` call site with the mandated per-site columns

211 rows (the `sandAlloc` definition is excluded). `calls (fn)`/`bytes (fn)` are the enclosing
function's measured aggregate (shared when a function has several `sandAlloc` sites; explicitly
marked). The five spec-mandated columns are filled per row, with `n/a` stated explicitly where a
column does not apply. `object + count` is derived from the allocation expression; `per-object
overhead` from the alignment argument; `alloc+copy redundancy`/`over-sizing` from the sibling ensure
class; `live-vs-dead` from the owning arena (when a site spans arenas the `arena` column has the
full split and this column is `mixed`). **Fix round 1 (finding 4):** these columns were previously
only class-level prose — they are now present in every row.

| site | enclosing fn | arena | calls (fn) | bytes (fn) | object + count | per-object overhead | alloc+copy redundancy | over-sizing | live-vs-dead |
|---|---|---|---:|---:|---|---|---|---|---|
| `sf/src/allocator.zig:100` | growableSandInit | unknown 44.5K | 13 | 45568 | blob/struct (fn calls=13; shared) | ≤3 B pad (align 4) | n/a (single allocation) | fixed first segment (4096/256) | pool carve (segment) |
| `sf/src/allocator.zig:146` | growableSandGrow | unknown 14880.0K | 68 | 15237155 | blob/struct (fn calls=68; shared) | ≤3 B pad (align 4) | n/a (segment carve, no copy) | new=max(2*last,req) ≤1MiB | pool carve (segment) |
| `sf/src/allocator.zig:147` | growableSandGrow | unknown 14880.0K | 68 | 15237155 | SandSegment[] (fn calls=68; shared) | ≤3 B pad (align 4) | n/a (segment carve, no copy) | new=max(2*last,req) ≤1MiB | pool carve (segment) |
| `sf/src/allocator.zig:329` | trackingAlloc | - | 0 | 0 | blob/struct (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/analyzer.zig:397` | deferQueueEnsureCapacity | scratch 0.3K | 3 | 288 | DeferEntry[] (fn calls=3; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/ast.zig:166` | u32ArrayListAppendInner | parser 69.6K | 1429 | 71296 | u32[] (fn calls=1429; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/ast.zig:198` | u64ArrayListAppendInner | - | 0 | 0 | u64[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/ast.zig:228` | f64ArrayListAppendInner | module 0.4K | 3 | 448 | u64[] (fn calls=3; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/ast.zig:258` | fnProtoArrayListAppendInner | module 63.9K | 9 | 65408 | FnProto[] (fn calls=9; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/ast.zig:551` | valuePoolEnsureHead | module 16.0K | 4 | 16384 | blob/struct (fn calls=4; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | exact (fixed block constant) | live (arena never reset) |
| `sf/src/ast.zig:592` | valuePoolEnsureCache | module 128.0K | 4 | 131072 | blob/struct (fn calls=4; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | exact (fixed block constant) | live (arena never reset) |
| `sf/src/ast.zig:691` | astBlockTableEnsure | module 45.0K | 72 | 46080 | NodeBlockInfo[] (fn calls=72; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/ast.zig:745` | astSlotEnsureNodeCap | module 862.5K | 14 | 883200 | AstNode[] (fn calls=14; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/ast.zig:761` | astSlotEnsurePayloadCap | module 143.8K | 14 | 147200 | u32[] (fn calls=14; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/async_analysis.zig:54` | allocU32 | module 86.6K | 5 | 88712 | u32[] (fn calls=5; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/async_frame_layout.zig:77` | fieldArrayListInit | - | 0 | 0 | AsyncFrameField[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/async_frame_layout.zig:91` | fieldArrayListEnsureCapacity | - | 0 | 0 | AsyncFrameField[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/async_frame_layout.zig:124` | allocU32With | - | 0 | 0 | u32[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/async_frame_layout.zig:134` | allocU8Raw | - | 0 | 0 | u8[] (fn calls=0; shared) | 0 B (align 1) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/async_frame_layout.zig:141` | allocU8With | - | 0 | 0 | u8[] (fn calls=0; shared) | 0 B (align 1) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/async_frame_layout.zig:674` | asyncLayoutPublish | - | 0 | 0 | AsyncFrameLayout[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/async_state_machine.zig:92` | bumpAlloc | - | 0 | 0 | blob/struct (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/async_state_machine.zig:98` | allocPrArray | - | 0 | 0 | blob/struct (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/async_state_machine.zig:865` | emitMainDriver | - | 0 | 0 | FrameInitParam[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/c89_emit.zig:853` | c89EmitterInit | emission 1.5K | 3 | 1536 | u32[] (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/c89_emit.zig:856` | c89EmitterInit | emission 1.5K | 3 | 1536 | u32[] (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/c89_emit.zig:857` | c89EmitterInit | emission 1.5K | 3 | 1536 | u32[] (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/c89_emit.zig:1456` | tstTopologicalSort | emission 29.3K | 3 | 29964 | blob/struct (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/c89_emit.zig:1462` | tstTopologicalSort | emission 29.3K | 3 | 29964 | blob/struct (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/c89_emit.zig:1464` | tstTopologicalSort | emission 29.3K | 3 | 29964 | blob/struct (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/c89_emit.zig:3195` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3196` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3197` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u8[] (fn calls=24243; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3198` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3199` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u8[] (fn calls=24243; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3200` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u8[] (fn calls=24243; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3201` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u8[] (fn calls=24243; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3202` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u8[] (fn calls=24243; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3203` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u8[] (fn calls=24243; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3204` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u8[] (fn calls=24243; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3241` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3242` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3249` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3250` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3251` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3252` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3285` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3286` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3287` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3288` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | u32[] (fn calls=24243; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3576` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | blob/struct (fn calls=24243; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3646` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | blob/struct (fn calls=24243; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:3667` | emitHoistedDecls | scratch 11093.5K,emission 58.0K | 24243 | 11419170 | blob/struct (fn calls=24243; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:4151` | emitNestCompute | scratch 464.2K | 1612 | 475299 | blob/struct (fn calls=1612; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/c89_emit.zig:9116` | emitFunctionBody | scratch 29.9K,emission 15.0K | 1617 | 45932 | u32[] (fn calls=1617; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/c89_emit.zig:9166` | emitFunctionBody | scratch 29.9K,emission 15.0K | 1617 | 45932 | blob/struct (fn calls=1617; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live-until-reset, transient) |
| `sf/src/coercion.zig:67` | coercionTableEnsureCapacity | module 191.9K | 11 | 196512 | CoercionEntry[] (fn calls=11; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/comptime_eval.zig:75` | comptimeFoldTableGrow | module 1535.2K | 11 | 1572096 | ComptimeVal[] (fn calls=11; shared) | ≤7 B pad (align 8) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/const_alias_prepass.zig:47` | growDep | - | 0 | 0 | u32[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/const_alias_prepass.zig:49` | growDep | - | 0 | 0 | u32[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/const_alias_prepass.zig:76` | constAliasPrepass | perm 109.3K | 6 | 111892 | blob/struct (fn calls=6; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/const_alias_prepass.zig:78` | constAliasPrepass | perm 109.3K | 6 | 111892 | blob/struct (fn calls=6; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/const_alias_prepass.zig:83` | constAliasPrepass | perm 109.3K | 6 | 111892 | blob/struct (fn calls=6; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/const_alias_prepass.zig:91` | constAliasPrepass | perm 109.3K | 6 | 111892 | blob/struct (fn calls=6; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/const_alias_prepass.zig:95` | constAliasPrepass | perm 109.3K | 6 | 111892 | blob/struct (fn calls=6; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/const_alias_prepass.zig:97` | constAliasPrepass | perm 109.3K | 6 | 111892 | blob/struct (fn calls=6; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/diagnostics.zig:414` | diagnosticArrayListEnsureCapacity | - | 0 | 0 | Diagnostic[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/diagnostics.zig:454` | diagnosticCollectorInit | perm 0.2K | 3 | 208 | blob/struct (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/diagnostics.zig:529` | diagnosticCollectorMarkNodeOnce | - | 0 | 0 | blob/struct (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/diagnostics.zig:564` | diagnosticCollectorAddRelatedSpan | - | 0 | 0 | 16B-object[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/diagnostics.zig:590` | diagnosticCollectorAddRelatedSpan | - | 0 | 0 | blob/struct (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/diagnostics.zig:600` | diagnosticCollectorAddRelatedSpan | - | 0 | 0 | blob/struct (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/diagnostics.zig:703` | diagnosticBuilderMakeMsg | - | 0 | 0 | blob/struct (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/growable_array.zig:25` | u32ArrayListEnsureCapacity | module 259.9K,diag_read 201.6K,emission 0.5K | 78 | 473112 | u32[] (fn calls=78; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | mixed (live, live-until-reset, per-module live) |
| `sf/src/growable_array.zig:82` | byteArrayListGrow | module 4.0K,scratch 0.3K | 49 | 4408 | u8[] (fn calls=49; shared) | 0 B (align 1) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | mixed (live, transient) |
| `sf/src/growable_array.zig:126` | astNodeArrayListEnsureCapacity | - | 0 | 0 | AstNode[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/growable_array.zig:168` | u64ArrayListEnsureCapacity | module 30.0K | 4 | 30720 | u64[] (fn calls=4; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/growable_array.zig:210` | f64ArrayListEnsureCapacity | - | 0 | 0 | u64[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/growable_array.zig:254` | fnProtoArrayListEnsureCapacity | - | 0 | 0 | FnProto[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/util/hash.zig:42` | u32ToU32MapInitCap | scratch 2859.8K,emission 145.1K,perm 1.1K | 9942 | 3078144 | u32[] (fn calls=9942; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live, live-until-reset, transient) |
| `sf/src/util/hash.zig:43` | u32ToU32MapInitCap | scratch 2859.8K,emission 145.1K,perm 1.1K | 9942 | 3078144 | u32[] (fn calls=9942; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live, live-until-reset, transient) |
| `sf/src/util/hash.zig:44` | u32ToU32MapInitCap | scratch 2859.8K,emission 145.1K,perm 1.1K | 9942 | 3078144 | u8[] (fn calls=9942; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | mixed (live, live-until-reset, transient) |
| `sf/src/util/hash.zig:72` | u32ToU32MapGrow | module 1763.7K,emission 367.5K,scratch 154.9K,perm 3.4K,type_db 0.5K | 651 | 2344896 | u32[] (fn calls=651; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | mixed (live, live-until-reset, transient) |
| `sf/src/util/hash.zig:73` | u32ToU32MapGrow | module 1763.7K,emission 367.5K,scratch 154.9K,perm 3.4K,type_db 0.5K | 651 | 2344896 | u32[] (fn calls=651; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | mixed (live, live-until-reset, transient) |
| `sf/src/util/hash.zig:74` | u32ToU32MapGrow | module 1763.7K,emission 367.5K,scratch 154.9K,perm 3.4K,type_db 0.5K | 651 | 2344896 | u8[] (fn calls=651; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | mixed (live, live-until-reset, transient) |
| `sf/src/util/hash.zig:150` | u64ToU32MapInitCap | emission 104.0K | 3 | 106496 | u64[] (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/util/hash.zig:151` | u64ToU32MapInitCap | emission 104.0K | 3 | 106496 | u32[] (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/util/hash.zig:152` | u64ToU32MapInitCap | emission 104.0K | 3 | 106496 | u8[] (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/util/hash.zig:180` | u64ToU32MapGrow | type_db 440.0K,emission 207.9K,module 207.8K | 198 | 876200 | u64[] (fn calls=198; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | mixed (live, live-until-reset) |
| `sf/src/util/hash.zig:181` | u64ToU32MapGrow | type_db 440.0K,emission 207.9K,module 207.8K | 198 | 876200 | u32[] (fn calls=198; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | mixed (live, live-until-reset) |
| `sf/src/util/hash.zig:182` | u64ToU32MapGrow | type_db 440.0K,emission 207.9K,module 207.8K | 198 | 876200 | u8[] (fn calls=198; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | mixed (live, live-until-reset) |
| `sf/src/util/hash.zig:241` | u32ToU64MapInitCap | - | 0 | 0 | u32[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/util/hash.zig:242` | u32ToU64MapInitCap | - | 0 | 0 | u64[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/util/hash.zig:243` | u32ToU64MapInitCap | - | 0 | 0 | u8[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/util/hash.zig:271` | u32ToU64MapGrow | - | 0 | 0 | u32[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/util/hash.zig:272` | u32ToU64MapGrow | - | 0 | 0 | u64[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/util/hash.zig:273` | u32ToU64MapGrow | - | 0 | 0 | u8[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/lexer.zig:31` | lexerInit | scratch 0.7K | 47 | 752 | blob/struct (fn calls=47; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lir.zig:228` | lirSideEntryArrayListEnsureCapacity | - | 0 | 0 | LirSideEntry[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/lir.zig:268` | lirInstArrayListEnsureCapacity | scratch 37634.2K | 49775 | 38537472 | LirInst[] (fn calls=49775; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/lir.zig:314` | basicBlockArrayListEnsureCapacity | - | 0 | 0 | BasicBlock[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/lir.zig:354` | lirParamArrayListEnsureCapacity | scratch 148.9K | 1569 | 152448 | LirParam[] (fn calls=1569; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/lir.zig:394` | tempDeclArrayListEnsureCapacity | scratch 3748.9K | 6299 | 3838848 | TempDecl[] (fn calls=6299; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/lir.zig:434` | switchCaseArrayListEnsureCapacity | - | 0 | 0 | SwitchCase[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/lir.zig:481` | lirSlotArrayListEnsureCapacity | emission 48.0K | 10 | 49104 | LirSlot[] (fn calls=10; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live until emission reset |
| `sf/src/lir.zig:585` | globalDeclArrayListEnsureCapacity | - | 0 | 0 | ModuleGlobalDecl[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/lir_opt_pass.zig:243` | allocU32 | module 86.6K | 5 | 88712 | u32[] (fn calls=5; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/lir_opt_pass.zig:248` | allocU64 | - | 0 | 0 | u64[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/lir_opt_pass.zig:253` | allocU8 | - | 0 | 0 | u8[] (fn calls=0; shared) | 0 B (align 1) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/lir_opt_pass.zig:2128` | allocU32With | - | 0 | 0 | u32[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/lir_opt_pass.zig:2138` | allocU32Raw | scratch 7637.8K | 70814 | 7821064 | u32[] (fn calls=70814; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lir_opt_pass.zig:2143` | allocU64Raw | scratch 1376.7K | 1612 | 1409712 | u64[] (fn calls=1612; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lir_opt_pass.zig:2148` | allocU8Raw | - | 0 | 0 | u8[] (fn calls=0; shared) | 0 B (align 1) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/lir_stream.zig:217` | lirStreamReadFunction | lir_read 154990.4K | 363692 | 158710144 | lir_mod.LirParam[] (fn calls=363692; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lir_stream.zig:226` | lirStreamReadFunction | lir_read 154990.4K | 363692 | 158710144 | lir_mod.BasicBlock[] (fn calls=363692; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lir_stream.zig:242` | lirStreamReadFunction | lir_read 154990.4K | 363692 | 158710144 | lir_mod.LirInst[] (fn calls=363692; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lir_stream.zig:254` | lirStreamReadFunction | lir_read 154990.4K | 363692 | 158710144 | lir_mod.TempDecl[] (fn calls=363692; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lir_stream.zig:263` | lirStreamReadFunction | lir_read 154990.4K | 363692 | 158710144 | lir_mod.SwitchCase[] (fn calls=363692; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lir_stream.zig:272` | lirStreamReadFunction | lir_read 154990.4K | 363692 | 158710144 | lir_mod.LirSideEntry[] (fn calls=363692; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lir_stream.zig:282` | lirStreamReadFunction | lir_read 154990.4K | 363692 | 158710144 | u32[] (fn calls=363692; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lir_stream.zig:283` | lirStreamReadFunction | lir_read 154990.4K | 363692 | 158710144 | u32[] (fn calls=363692; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lir_stream.zig:284` | lirStreamReadFunction | lir_read 154990.4K | 363692 | 158710144 | u8[] (fn calls=363692; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:131` | arrayListEnsureCapacityBytes | scratch 219.9K | 2801 | 225184 | blob/struct (fn calls=2801; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/lower.zig:533` | lowererInit | scratch 3097.5K | 14868 | 3171840 | blob/struct (fn calls=14868; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:534` | lowererInit | scratch 3097.5K | 14868 | 3171840 | blob/struct (fn calls=14868; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:535` | lowererInit | scratch 3097.5K | 14868 | 3171840 | blob/struct (fn calls=14868; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:536` | lowererInit | scratch 3097.5K | 14868 | 3171840 | blob/struct (fn calls=14868; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:537` | lowererInit | scratch 3097.5K | 14868 | 3171840 | blob/struct (fn calls=14868; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:538` | lowererInit | scratch 3097.5K | 14868 | 3171840 | blob/struct (fn calls=14868; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:539` | lowererInit | scratch 3097.5K | 14868 | 3171840 | blob/struct (fn calls=14868; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:540` | lowererInit | scratch 3097.5K | 14868 | 3171840 | blob/struct (fn calls=14868; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:541` | lowererInit | scratch 3097.5K | 14868 | 3171840 | blob/struct (fn calls=14868; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:1937` | growLocalDecls | scratch 345.0K | 414 | 353280 | u32[] (fn calls=414; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:1938` | growLocalDecls | scratch 345.0K | 414 | 353280 | u32[] (fn calls=414; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:1939` | growLocalDecls | scratch 345.0K | 414 | 353280 | u32[] (fn calls=414; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:1940` | growLocalDecls | scratch 345.0K | 414 | 353280 | u32[] (fn calls=414; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:1941` | growLocalDecls | scratch 345.0K | 414 | 353280 | u8[] (fn calls=414; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:1942` | growLocalDecls | scratch 345.0K | 414 | 353280 | u8[] (fn calls=414; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:1943` | growLocalDecls | scratch 345.0K | 414 | 353280 | u32[] (fn calls=414; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:1944` | growLocalDecls | scratch 345.0K | 414 | 353280 | u32[] (fn calls=414; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:1945` | growLocalDecls | scratch 345.0K | 414 | 353280 | u32[] (fn calls=414; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:6030` | lowerExprImpl | - | 0 | 0 | async_state_machine.FrameInitParam[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/lower.zig:8923` | lowerFn | scratch 196.5K | 1623 | 201252 | LirFunction[] (fn calls=1623; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:9021` | lowerModuleInit | scratch 67.1K | 348 | 68694 | LirFunction[] (fn calls=348; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:9040` | lowerModuleInit | scratch 67.1K | 348 | 68694 | u32[] (fn calls=348; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:9041` | lowerModuleInit | scratch 67.1K | 348 | 68694 | u32[] (fn calls=348; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:9090` | lowerModuleInit | scratch 67.1K | 348 | 68694 | blob/struct (fn calls=348; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:9091` | lowerModuleInit | scratch 67.1K | 348 | 68694 | blob/struct (fn calls=348; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:9092` | lowerModuleInit | scratch 67.1K | 348 | 68694 | u32[] (fn calls=348; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:9093` | lowerModuleInit | scratch 67.1K | 348 | 68694 | u32[] (fn calls=348; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:9094` | lowerModuleInit | scratch 67.1K | 348 | 68694 | u32[] (fn calls=348; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:9095` | lowerModuleInit | scratch 67.1K | 348 | 68694 | u32[] (fn calls=348; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:9096` | lowerModuleInit | scratch 67.1K | 348 | 68694 | u32[] (fn calls=348; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:9097` | lowerModuleInit | scratch 67.1K | 348 | 68694 | u32[] (fn calls=348; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/lower.zig:9112` | lowerModuleInit | scratch 67.1K | 348 | 68694 | u32[] (fn calls=348; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/main.zig:897` | phase_LIRLowering | - | 0 | 0 | LirFunction[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/main.zig:1047` | computeModuleInitOrder | scratch 0.0K | 1 | 48 | blob/struct (fn calls=1; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/main.zig:1404` | phase_C89Emission | emission 28.0K | 48 | 28660 | u32[] (fn calls=48; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/main.zig:1405` | phase_C89Emission | emission 28.0K | 48 | 28660 | u32[] (fn calls=48; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/main.zig:1419` | phase_C89Emission | emission 28.0K | 48 | 28660 | lir_mod.LirSlot[] (fn calls=48; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/main.zig:1478` | phase_C89Emission | emission 28.0K | 48 | 28660 | u32[] (fn calls=48; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live until emission reset |
| `sf/src/module_registry.zig:74` | moduleEntryArrayListEnsureCapacity | - | 0 | 0 | ModuleEntry[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/module_registry.zig:116` | searchDirArrayListEnsureCapacity | perm 0.0K | 1 | 8 | u32[] (fn calls=1; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/module_registry.zig:137` | joinPath | import_scratch 8.1K,scratch 0.0K | 400 | 8328 | blob/struct (fn calls=400; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/module_registry.zig:161` | appendZigExt | - | 0 | 0 | blob/struct (fn calls=0; shared) | 0 B (align 1) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/module_registry.zig:264` | importEdgesEnsureCapacity | perm 4.0K | 7 | 4064 | u32[] (fn calls=7; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/module_registry.zig:518` | moduleRegistryFaultInPathToId | perm 2.2K | 3 | 2304 | u32[] (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/module_registry.zig:519` | moduleRegistryFaultInPathToId | perm 2.2K | 3 | 2304 | u32[] (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/module_registry.zig:520` | moduleRegistryFaultInPathToId | perm 2.2K | 3 | 2304 | u8[] (fn calls=3; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/module_registry.zig:571` | importQueuePendingEnsureCapacity | perm 0.5K | 4 | 480 | u32[] (fn calls=4; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/pal.zig:43` | readFile | source 2790.2K,diag_read 2711.1K,import_scratch 2686.3K,scratch 103.9K | 137 | 8490448 | blob/struct (fn calls=137; shared) | 0 B (align 1) | n/a | exact (on-disk size) | mixed (per-module live, transient) |
| `sf/src/parser.zig:591` | u32ArrayListAppendInner | parser 69.6K | 1429 | 71296 | u32[] (fn calls=1429; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/resolved_type_table.zig:115` | rttEnsureCache | module 16.0K | 1 | 16360 | blob/struct (fn calls=1; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/semantic_analyzer.zig:566` | semanticAnalyzerAllocCopyU32 | scratch 99.2K | 691 | 101632 | u32[] (fn calls=691; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/semantic_analyzer.zig:582` | semanticAnalyzerGrowLocalDecls | - | 0 | 0 | blob/struct (fn calls=0; shared) | 0 B (align 1) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/semantic_analyzer.zig:6485` | semanticAnalyzerResolveTupleLiteral | - | 0 | 0 | u32[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/source_manager.zig:50` | sourceFileArrayListEnsureCapacity | - | 0 | 0 | SourceFile[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/source_manager.zig:83` | sourceManagerInit | perm 0.1K | 2 | 76 | blob/struct (fn calls=2; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/source_manager.zig:86` | sourceManagerInit | perm 0.1K | 2 | 76 | alloc_mod.GrowableSand[] (fn calls=2; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/source_manager.zig:106` | sourceManagerAddFile | perm 0.7K | 47 | 752 | blob/struct (fn calls=47; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/source_manager.zig:133` | sourceManagerAddFileTransient | - | 0 | 0 | blob/struct (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/source_manager.zig:163` | sourceManagerFaultIn | diag_read 0.7K | 43 | 688 | blob/struct (fn calls=43; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | per-module live; reset by L3 |
| `sf/src/source_manager.zig:184` | sourceManagerFaultIn | diag_read 0.7K | 43 | 688 | blob/struct (fn calls=43; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | per-module live; reset by L3 |
| `sf/src/source_manager.zig:257` | sourceManagerCopyToArena | perm 1.0K | 47 | 1025 | blob/struct (fn calls=47; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/spill_store.zig:115` | ramEnsure | - | 0 | 0 | blob/struct (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/spill_store.zig:125` | ramEnsure | - | 0 | 0 | blob/struct (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/state_map.zig:32` | stateMapEnsureCapacity | scratch 1121.4K | 16262 | 1148352 | StateEntry[] (fn calls=16262; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/state_map.zig:63` | stateMapFork | scratch 1214.6K | 51822 | 1243728 | StateMap[] (fn calls=51822; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/string_interner.zig:29` | ensureCapacityBuckets | - | 0 | 0 | u32[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/string_interner.zig:43` | ensureCapacityEntries | - | 0 | 0 | 16B-object[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/string_interner.zig:82` | stringInternerInit | perm 1474.2K | 2 | 1509576 | u32[] (fn calls=2; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/string_interner.zig:93` | stringInternerInit | perm 1474.2K | 2 | 1509576 | 16B-object[] (fn calls=2; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/string_interner.zig:146` | stringInternerCopyToArena | perm 418.5K | 34020 | 428506 | blob/struct (fn calls=34020; shared) | 0 B (align 1) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/symbol_registrator.zig:53` | depGraphEnsureCapacity | scratch 48.1K | 6 | 49280 | DepEdge[] (fn calls=6; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/symbol_registrator.zig:69` | depGraphFinalize | - | 0 | 0 | u32[] (fn calls=0; shared) | ≤3 B pad (align 4) | n/a (unwired/def) | n/a | n/a (not reached) |
| `sf/src/symbol_table.zig:59` | symbolTableEnsureCapacity | perm 10.3K | 47 | 10528 | Symbol[] (fn calls=47; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/symbol_table.zig:110` | symbolRegistryEnsureCapacity | perm 1.9K | 4 | 1920 | SymbolTable[] (fn calls=4; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/token.zig:150` | initKeywordTable | perm 0.4K | 1 | 456 | KeywordEntry[] (fn calls=1; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/type_registry.zig:162` | arrayGrow | type_db 211.6K | 77 | 216640 | blob/struct (fn calls=77; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/type_registry.zig:184` | typeRegistryEnsureCapacity | type_db 255.0K | 8 | 261120 | Type[] (fn calls=8; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | live (arena never reset) |
| `sf/src/type_resolver.zig:102` | nameScopeGrowPair | scratch 8.7K | 186 | 8896 | blob/struct (fn calls=186; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/type_resolver.zig:103` | nameScopeGrowPair | scratch 8.7K | 186 | 8896 | blob/struct (fn calls=186; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/type_resolver.zig:203` | rawArrayEnsureCapacity | scratch 0.3K | 2 | 320 | blob/struct (fn calls=2; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/type_resolver.zig:244` | inDegreeEnsureCapacity | scratch 8.5K | 1 | 8672 | blob/struct (fn calls=1; shared) | ≤3 B pad (align 4) | yes — new alloc + copy prefix + abandon old | cap=2×need (geometric) | transient (arena reset) |
| `sf/src/type_resolver.zig:516` | typeResolverBuild | scratch 8.5K | 1 | 8672 | blob/struct (fn calls=1; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | transient (arena reset) |
| `sf/src/type_resolver.zig:665` | classifyTypeEmissionGroups | perm 95.3K | 6 | 97560 | blob/struct (fn calls=6; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/type_resolver.zig:669` | classifyTypeEmissionGroups | perm 95.3K | 6 | 97560 | blob/struct (fn calls=6; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/type_resolver.zig:671` | classifyTypeEmissionGroups | perm 95.3K | 6 | 97560 | blob/struct (fn calls=6; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/type_resolver.zig:673` | classifyTypeEmissionGroups | perm 95.3K | 6 | 97560 | blob/struct (fn calls=6; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/type_resolver.zig:679` | classifyTypeEmissionGroups | perm 95.3K | 6 | 97560 | blob/struct (fn calls=6; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |
| `sf/src/type_resolver.zig:855` | classifyTypeEmissionGroups | perm 95.3K | 6 | 97560 | blob/struct (fn calls=6; shared) | ≤3 B pad (align 4) | n/a (single allocation) | n/a (fixed/exact request) | live (arena never reset) |

## Other allocation entry-point classes

### Growable arena constructors (`growableSandInit` — 10 calls; line 99 is the definition)

| site | arena | first segment | notes |
|---|---|---|---|
| `allocator.zig:272` | perm | 4096 | tier ctor |
| `allocator.zig:273` | module | 4096 | tier ctor |
| `allocator.zig:274` | scratch | 4096 | tier ctor |
| `allocator.zig:275` | lir_read | 4096 | tier ctor |
| `allocator.zig:276` | emission | 4096 | tier ctor |
| `import_resolver.zig:57` | parser arena | 4096 | per resolve pass |
| `import_resolver.zig:61` | import_scratch | 256 | transient; reset per `@import` |
| `import_resolver.zig:65` | source | 4096 | per-module read; reset per module |
| `main.zig:200` | type_db | 4096 | tier ctor |
| `source_manager.zig:158` | diag_read | 4096 | lazy; per-module reset (L3, present) |

(Probe: `growableSandInit` 13 calls / 45,568 B — includes the 5 tier ctors plus per-resolve/re-fault
calls; `growableSandGrow` 68 carves / 14,880K from the pool = the `unknown` arena.)

### `*ArrayList` box allocations (heap-allocated list headers)

List *headers* are boxed with `sandAlloc` before init, e.g. `source_manager.zig:83/106/133/163/184`
(`*U32ArrayList`, 16 B), plus AST/string-pool/diagnostic seed boxes. 16-B-per-list single
allocations — negligible individually; all appear as rows in Table 2.

### `SpillStore` opens — **7 call sites across 5 stores** (finding 1)

| store | field | open sites | backend |
|---|---|---|---|
| `AstStore.spill` | `ast.zig:372` | `ast.zig:706` | disk default |
| `AstValuePool.spill` (×4 pools) | `ast.zig:325` | `ast.zig:546` | disk default (s_side/s_extra) |
| `LirStream.spill` | `lir_stream.zig:21` | `lir_stream.zig:44` (write) / `:58` (read) | disk default |
| `ModuleRegistry.spill` | `module_registry.zig:242` | `:471` (write) / `:495` (read) | disk only |
| `ResolvedTypeTable.spill` | `resolved_type_table.zig:23` | `:78` | disk default |

That is exactly **7** `spillOpen(` calls (`ast.zig:546,706`; `lir_stream.zig:44,58`;
`module_registry.zig:471,495`; `resolved_type_table.zig:78`). At `-s0` all are disk, so `spillOpen`
is an `fopen` (no pool bytes); Ram buffers only appear at `-s1`+ via `ramEnsure`
(`spill_store.zig:109`, realloc-in-place first).

### Inline `[N]` buffer fields — **16** (finding 10)

| field | size | where it lives |
|---|---|---|
| `ast.zig:326` `spill_path:[512]u8` (`AstValuePool`) | 512 each | **stack; instantiated 4×** inside `AstStore` |
| `ast.zig:367` `slots:[8]AstSlot` | large | stack |
| `ast.zig:368` `slot_block:[8]u32` | 32 | stack |
| `ast.zig:373` `spill_path:[512]u8` (`AstStore`) | 512 | stack |
| `lir_stream.zig:22` `path:[512]u8` | 512 | stack |
| `module_registry.zig:240` `hash_spill_path:[512]u8` | 512 | stack |
| `resolved_type_table.zig:24` `spill_path:[512]u8` | 512 | stack |
| `resolved_type_table.zig:28` `slot_block:[8]u32` | 32 | stack |
| `resolved_type_table.zig:29` `slot_dirty:[8]u8` | 8 | stack |
| `c89_emit.zig:33` `buf:[4096]u8` | 4096 | stack (`C89Emitter` local) |
| `comptime_eval.zig:22` `mag:[8]u32` | 32 | stack |
| `parser.zig:47` `la:[3]Token` | 72 (Token 24 B, Task 2) | stack |
| `diagnostics.zig:295` `note_ids:[3]u32` | 12 | stack |
| `main.zig:93` `include_dirs:[16][]const u8` | 128 | stack |
| `semantic_analyzer.zig:81` `defer_label_stack:[16]u32` | 64 | stack |
| `semantic_analyzer.zig:82` `defer_label_isloop:[16]u8` | 16 | stack |

**Fix round 1 (finding 6):** `AstStore` embeds `AstValuePool` **four times**
(`extra_children`, `identifiers`, `int_values`, `extra_ranges`; `ast.zig:337-360`), each carrying its
own `spill_path:[512]u8` (`ast.zig:326`), plus `AstStore.spill_path` (`ast.zig:373`) — **5 buffers in
AST alone**; plus `lir_stream.zig:22` (named `path`) + `module_registry.zig:240` (`hash_spill_path`) +
`resolved_type_table.zig:24` = **8 live `[512]u8` buffers, 8×512 = 4,096 B total**. All on `main`'s
stack, touched once at init. Conclusion unchanged: negligible RSS.

## Shortlist — save-allocation candidates (ranked by expected touched-RSS)

Estimates are bounded by measured per-function cumulative bytes. **Abandoned-only** means old grow
buffers that were touched during the copy and then abandoned in a never-reset arena; `realistic`
discounts for in-place-at-tail wins / not-all-grows-abandon. Every row's gate is the spec's battery +
a `median≥3` pool/RSS remeasure.

**Row 1 — single reconciled derivation (finding 3).** `u32ToU32MapGrow` + `u64ToU32MapGrow`
(`util/hash.zig:66,174`), from Table 1 exact sums:

```
u32ToU32MapGrow: module 1,806,048 + emission 376,272 + perm 3,456 + type_db 504 + scratch 158,616 = 2,344,896 B (2,289.9K)
u64ToU32MapGrow: type_db  450,528 + emission 212,888 + module 212,784                        =   876,200 B (  855.7K)
full cumulative (both maps, all arenas)                                                        = 3,221,096 B (3,145.6K), 849 calls
resident = full - scratch 158,616                                                              = 3,062,480 B (2,990.7K)
abandoned-only upper = resident / 2 (geometric doubling: allocated ~= 2x final)                = 1,531,240 B (1,495.4K)
realistic touched-RSS (in-place wins only at arena tail)                                       = ~0.5-0.9M
```

The earlier draft quoted 2,729.5K / ~1,365K (census) and ~1,285K (report); those mixed maps, dropped
per-arena terms, and rounded inconsistently. The numbers above are the one derivation used in both
files.

| # | mechanism / sites | arena | full cumulative | abandoned-only (upper) | realistic touched-RSS | risk | notes / exhaust? |
|---|---|---|---:|---:|---:|---|---|
| 1 | hash-map `u32ToU32MapGrow`+`u64ToU32MapGrow` add `sandTryReallocInPlace` (`util/hash.zig:66,174`; 849 calls) | module/type_db/perm/emission | 3,145.6K (resident 2,990.7K) | 1,495.4K | ~0.5–0.9M | Med | overlaps prior F-HASHMAP; pure doubling, 3 arrays/grow |
| 2 | `comptimeFoldTableGrow` exact-fit / in-place (`comptime_eval.zig:70`; 11 calls) | module | 1,535.3K | ~768K | ~0.4–0.7M | Low–Med | `ComptimeVal` 48 B; no in-place today |
| 3 | AST head-slot growth (`ast.zig:739,755`; 14+14 calls) | module | 1,006.3K | ~503K | ~0.25–0.4M | Med | AST spill window semantics; `AstNode` 24 B |
| 4 | type-registry grow (`type_registry.zig:160,179`; 77+8 calls) | type_db | 466.6K | ~233K | ~0.1–0.2M | Med | dense `Type` array |
| 5 | interner bucket over-provision (`main.zig:188-190` → `string_interner.zig:64`) | perm | 1,474.2K | provisioned buckets 503,192 B **touched** (zeroed); excess over load-factor ≈ 231K | ~0.2M | Low | overlaps S-INTERNER (exhausted); entries tail ~451K is carved-**not**-touched |
| 6 | module `u32ArrayListEnsureCapacity` in-place (`growable_array.zig:20`; 31 calls) | module | 259.9K | ~130K | ~0.1M | Low | generic helper shared by many consumers |

**Mechanism in common for rows 1–4,6:** the doubling ensure/grow functions `sandAlloc` a new array,
copy the old prefix, and *abandon* the old array in a never-reset arena. The same one-line
`sandTryReallocInPlace`-first attempt (`allocator.zig:219`) is **already used at 21 call sites
(finding 2)** — grep-verified across the closure:

```
source_manager.zig:40                symbol_registrator.zig:43
symbol_table.zig:49, 100             type_resolver.zig:200
ast.zig:154, 186, 216, 246           coercion.zig:57
diagnostics.zig:404, 581             growable_array.zig:72
lir.zig:575                          lower.zig:125
module_registry.zig:64, 106, 254, 561 parser.zig:579
spill_store.zig:120
```

(The earlier draft said "four functions"; the reviewer's 17 is itself a miscount of the 21 sites
listed above. Rows 1–4,6 are the remaining growers that lack the attempt.)

**Explicitly not shortlisted (measured, not levers):**

- `lirStreamReadFunction` (`lir_stream.zig:184`): 154,990K churn into `lir_read`, but the arena is
  `sandReset` per function (`:185`) and exact-fit per array — **carve 0 at `-s0`; peak = one function**.
- `lirInstArrayListEnsureCapacity`/`tempDecl…`/`basicBlock…`/`lowererInit`/`allocU32Raw`/
  `emitHoistedDecls` (scratch): 78,424K churn, but `scratch` carve collapsed to 223,519 B post-L3
  because its segments are reused from `seg_free_head`. Resets leave ~no touched peak.
- `diag_read` text + line index (`pal.zig:25` via `source_manager.zig:161/163/174`): 2,711.1K text +
  201.6K index live; **L3 per-module reset already landed in `sf/src`**. Remaining index lever
  `u32→u16` ≤ ~101K live and ≈0 pool (prior L1).
- `import_scratch`/`source` whole-file reads (`module_registry.zig:384`): 2,686K/2,790K churn,
  exact-fit and reset per import/module; prior L5 disconfirmed (module reuses 1,276,415 B) — ≈0 pool.
- `c89EmitterInit` `buf:[4096]u8`, `spill_path` buffers, boxed list headers: sub-KB to a few KB.

## Method caveats

1. Counts are **per enclosing function**, not per individual `sandAlloc` line (no DWARF line info in
   the seed binary); a function with N `sandAlloc` sites shares its aggregate (Table 2 marks the
   shared rows).
2. `bytes` is cumulative churn; footprint attribution uses the arena carve (Task 0) and the
   never-reset/reset classification above.
3. The probe's arena is read from `Sand.name`; a segment carved by one arena but written by another
   is attributed to the writer (correct for touched-bytes accounting).
4. Numbers are data-dependent on the current worktree; small source changes shift them by tens of KB.
