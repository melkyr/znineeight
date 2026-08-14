# 08 — C89 Emission [updated: 2026-08-13 — Defect E FIXED (F6): bare `union_type` now emits a real C `union` (max-member layout matching `@sizeOf`'s union-max) instead of a stacked `struct` — the `aggregateKeyword(kind)` helper (`c89_emit.zig:542`) is the single keyword source of truth at all 3 named-aggregate sites (`emitUnionType` def :1535, `emitSharedHeader` fwd-decl :1130-era, `emitSpecialTypes` fwd-decl :1260-era), closing the struct/union tag-namespace split-brain (a one-keyword swap failed gcc: 'defined as wrong kind of tag'); `union_emission_layout_xmod` prints 7+8 (@sizeOf(Data)=8 = runtime union), `sizeof_struct_union_xmod` still 24; lisp_interpreter + json_parser_workaround no longer SEGFAULT (arena sized by @sizeOf no longer overflows the 3x-stacked struct); tagged_union/struct sites stay `struct`, anonymous wrappers unaffected; prior 2026-08-13 — F6 networking builtins: 11 socket builtins (socketCreate/BindListen/Accept/Connect/Send/Recv/Select/FdZero/FdSet/FdIsset/Close) PORT net_runtime.c's 12 plat_* bodies inline (`#ifdef _WIN32/#else` per-builtin), `emitBuiltinIncludes` net-gated socket include block, std_net.zig + mud_server/rogue_mud migrated off net_runtime.c link (see §6.9); prior 2026-08-08 — F4 std-lib cleanup: the F2 console builtins' emitted `__bootstrap_write(...)` calls repointed to `std_print_len(...)` (the example-facing wrapper was removed from zig_runtime.c; `console_builtin_test` re-verified gcc-clean) — preamble + `emitConsoleClear`/`emitConsoleGotoxy`/`emitConsoleSetColor` (c89_emit.zig:3249, :3302, :3346; **[F3 line-ref pass 2026-08-13: console emit refs corrected]**); prior 2026-08-08 — 3 console builtins emit the `#ifdef _WIN32 / #elif defined(__WATCOMC__) / #else` ANSI-escape/Win32 guard chains via `emitConsoleClear`/`emitConsoleGotoxy`/`emitConsoleSetColor` + Win98-forcing console include block in `emitBuiltinIncludes` (single- AND multi-module) — `console_builtin_test` gcc-clean; `@isWindows()` emits NO C (comptime-folded, see 05/07) (F2); prior 2026-08-08 — 6 core I/O builtins emit `putchar(c)`/`fwrite(ptr,1,len,stdout)`/`fwrite(ptr,1,len,stderr)`/`zT = getchar()`/`exit(code)`/`#ifdef _WIN32 Sleep(ms) #else usleep(ms*1000) #endif`; gated `#include` via `emitBuiltinIncludes` (`<stdio.h>`/`<stdlib.h>`/`_WIN32`→`<windows.h>`/else→`<unistd.h>`) in BOTH the single-stream `emitModuleHeader` and the multi-module `emitModuleFile` paths — `io_builtin_test` gcc-clean single- AND multi-module (F1); prior — cross-module tagged-union member-access SEGV FIXED (F6): generic field-access dispatch (lower.zig:2174-2206) gained a `tagged_union_type` case mirroring the same-module member path (`tu_items` lookup + `emitTaggedUnionInit` tag value) — `tagged_union_cmp_xmod` dumps rc=0 (was SEGV), isolated `var x = lib_mod.Shape.Circle;` gcc-clean + runs; the repro's `==` form now emits valid C — tagged-union `==`/`!=` emission FIXED (Task F, Option A, operator ruling m0471 SUPERSEDES the zig0 oracle which rejects union `==`): the `.binary` handler (c89_emit.zig:3724-3739) type-resolves each BIN_EQ/BIN_NE operand in `hoisted_temps` and appends `.tag` for `tagged_union_type` operands (mirrors the int_const `.tag =` path c89_emit.zig:3762-3789) — valid Zig semantics (union `==` compares the active tags); `s == lib_mod.Shape.Circle` emits `s.tag == zT_rhs.tag` (gcc-valid); `tagged_union_cmp_xmod` compiles+links+runs printing `1`; same-module union `==` also emits `.tag` (verified); 4 MD5 gates byte-identical, corpus CRASH=0, test_analyzer_bin PASS; **[F3 line-ref pass 2026-08-13: `.binary` handler ref :3724-3739 → :4369; int_const `.tag` path :3762-3789 → :4443.]** earlier — cross-module plain-enum member access FIXED (F3): `mod.Type.Member` now resolves via an `enum_type` case added to the generic base-type dispatch in sema (semantic_analyzer.zig:459) + lower.zig:2193 — emits `.enum_const`, so `zT_missing_fwd_xmod` + `json_parser_workaround` are gcc-clean; earlier — cross-module tagged-union `==`/member-literal SEGV documented (§1.17, I6): `s == lib.Shape.Circle` + `var x = lib.Shape.Circle` + TU VALUE payload access `s.Circle` all SEGV zig1 in `typeRegistryGetStructFields` (lower.zig:2180) — tagged_union_type misrouted to the struct-fields getter (indexes `st_items` with a `tu_items` payload_idx) → garbage slice → SEGV; same-module union `==` emits gcc-invalid C (`binary ==` on structs); zig0 REJECTS `union ==` cleanly (type mismatch) — fix target = graceful rejection (green-guard) + lower.zig:2180 dispatch fix; earlier same day — cross-module enum-literal comparison gap documented (§1.17, I3): `'zT_XX' undeclared` in importing module's `.c` — sema/lowering gap (qualified enum literal → VOID), NOT a header forward-decl gap; prior same day — multi-module emission loop verified (NO silent module drop; §1.17); orphan-module handling + arena_alloc_default runtime-symbol gap documented (§1.17); prior 2026-08-07 — null_src null construction skips the dead `null_const` temp (Option B); prior null-payload temp typed `"int"` (null_type fallback); prior 2026-08-06 — va_* emission + `stdarg.h` gating + extern variadic prototypes + `@intCast` range-check helper; stale c89_emit.zig line ref corrected (emitTaggedUnionType :1348); F7 line-ref re-verification (2026-08-08): all `c89_emit.zig`/`main.zig` refs corrected against source — emitInst :3138, emitModule :2277, emitModuleHeaderFile :2154, emitModuleFile :2399, emitMainWrapper :2313, emitFunctionSignature :1854, emitFunctionForwardDecl :1920, emitStdargInclude :2008, moduleHasVaInsts :1964, moduleQualifiedName :2111, ctypeGuardWrite :997, mangleLocalName :1838, mangleTempName :2349, c_incs list :1996-2013, dep-.h include :2121-2128, extern-name call site :4048, extern-no-fwd :1927, extern-no-body :2333, .loop_header :3071-3073, preamble :744 / main.zig:827-830, length guard :769, cincludeUnionAll call :832, LIR fn-list :543-615, C marker :710, FINAL_FLUSH :834, module name :731, sema comparison :540, lower enum_const :2207; F3 line-ref pass (2026-08-13): re-verified against current source post-F1/F6 — emitInst :3670, emitModule :2146, emitModuleHeaderFile :2233, emitModuleFile :2478, emitMainWrapper :2392, emitFunctionSignature :1875, emitFunctionForwardDecl :1941, emitStdargInclude :2006, moduleHasVaInsts :1985, moduleQualifiedName :2190, ctypeGuardWrite :1016, mangleLocalName :1859, mangleTempName :2505, `.loop_header` arm :3679, `.call_direct` :4718, extern-name call site :4733, extern-no-fwd :2177/:2324, extern-no-body :2370]

> Covers: `c89_emit.zig`, `name_mangler.zig`, `cinclude.zig`
> Cross-ref: [INDEX.md](INDEX.md) §E (NameMangler, BufferedWriter data structures)

## Summary

| Key | Value |
|-----|-------|
| Input | `LirFunction` list (lowered IR functions per module), `TypeRegistry` |
| Output | C89 `.c` file via stdout |
| Phase marker | `C` (entry), `FINAL_FLUSH` (complete) |
| Key structs | `C89Emitter`, `BufferedWriter`, `NameMangler` |
| Key functions | `emitModule`, `emitSpecialTypes`, `emitFunctionBody`, `emitInst`, `nameManglerMangle`, `cincludeUnionAll` |

---

## 1. `c89_emit.zig` — C89 Emitter (4032 lines)

### 1.1 2-Phase Output Architecture

Emission follows a strict 2-phase ordering per module, enforced in `emitModule` (`c89_emit.zig:2201`):

```
Phase 1: Type Headers (emitSpecialTypes)
  ├─ Sub-pass 1: Forward declarations for struct/union/tagged_union types
  │   (typedef struct Foo Foo;)
  ├─ Sub-pass 2a: Pointer-only types (fields all through ptr/slice/wrapper)
  │   (emitTypeDefinition — only if in pointer_only_map)
  └─ Sub-pass 2b: Value-embedding types (structs with inline fields)
      (emitTypeDefinition — only if NOT in pointer_only_map)

Phase 2: Function Bodies (emitModuleHeader → emitFunctionSignature → emitFunctionBody)
  ├─ Module header: includes, forward declarations
  ├─ Per function: signature + hoisted decls + basic blocks
  └─ main() wrapper for non-void return types
```

Phase 1 runs once via `emitSpecialTypes` BEFORE any function body. Phase 2 iterates the function list.

#### Type Topological Sort

Types are emitted in dependency order using Kahn's algorithm (`tstTopologicalSort`, `c89_emit.zig:959`):

```
Input: TypeRegistry (all types 0..types_len-1)
1. Compute indegree for each type — count of C89-relevant field/child types
   (struct/tagged_union/array/error_union that reference another type)
2. Enqueue all types with indegree 0
3. Dequeue → add to result → decrement indegree of dependents → enqueue new 0s
4. Result order: types with no deps first, then their dependents
```

`c89NeedsEmitEdge` (`c89_emit.zig:781`) determines which `TypeKind` forms an edge: slice, struct, union, tagged_union, array, optional, error_union, **enum, error_set**, tuple, unresolved_name.
[updated: 2026-08-01] `enum_type`/`error_set_type` were added in F-S8 — both are embeddable by value
(inline integer typedef aliases), so a target enum/error_set **must** have an emit edge or the fixpoint
(`computeSharedSet` §1.17) never promotes it into `zig_special_types.h`, leaving shared struct bodies
referencing an unknown `typedef`. `tstIsDep` (`c89_emit.zig:922`), `tstEdgesCount` (`c89_emit.zig:807`),
and `tstEdgesFill` (`c89_emit.zig:857`) all gate their source-kind branches on this helper, so the
enum/error_set target support flows through every source branch automatically; no enum/error_set
*source* branch is needed (backing_type/tags are plain integers).

[updated: 2026-08-07] `tstEdgesCount`/`tstEdgesFill` now count each distinct dependent type ONCE
per source (dedupe same-typed field edges) via the new `tstSeenInRange` helper
(`c89_emit.zig:799`): the struct/tagged_union/union field loops and the tagged_union `tag_type`
all skip a target type already seen in the fields scanned so far. This makes the indegree
(`tstEdgesCount`, `c89_emit.zig:807`) exactly equal to the number of `tstIsDep`-true decrements in
the Kahn dequeue (`c89_emit.zig:985-987`, inside `tstTopologicalSort` :959), so count and dequeue
can never drift: a struct with two
fields of the same edge-forming type (e.g. two `Point` fields) previously got indegree 2 but only
1 dequeue decrement, was never dequeued, and was silently dropped from `sorted` (no fwd-decl/body →
gcc `unknown type name`). F1 (commit a5ac4598) fixes `dup_optptr_field_emit`/`dup_val_field_emit`.
`tstEdgesFill` is dead code (0 callers) — the dedupe there is mirrored for consistency, zero
runtime effect.

#### Pointer-only vs Value-embedding Split

`emitModule` receives a `ptr_only_ids` array from the caller (calculated in `phase_C89Emission` in `main.zig`). Types in this set have all their field dependencies reachable through pointers — only a forward declaration is needed for C89 correctness. The split prevents redundant full type definitions:

- **Sub-pass 2a** (`c89_emit.zig:1256`): Iterates types in topo order, skips if NOT in `pointer_only_map`. Emits full definition.
- **Sub-pass 2b** (`c89_emit.zig:1297`): Iterates types in topo order, skips if IS in `pointer_only_map`. Emits full definition.

Both sub-passes dedup via `emitter.emitted_type_set` (hash of C type name string) — same type only emitted once.

### 1.2 BufferedWriter — 4KB Buffered Output

Defined in `c89_emit.zig:27-79`. Fixed-size 4096-byte buffer with auto-flush.
[updated: 2026-08-01] BufferedWriter now carries a **file-descriptor sink** (`fd: usize`) so the
multi-module path can flush each `.h`/`.c`/`zig_special_types.h` to its own open file. Stdout
remains the default (`fd=1`), so the bare `--dump-c89` byte-identical gate is preserved.

| Field | Type | Purpose |
|-------|------|---------|
| `buf` | `[4096]u8` | Circular-ish output buffer — written to sequentially, flushed to sink when full |
| `pos` | `usize` | Current write cursor (0 = empty, 4096 = full, triggers flush) |
| `fd` | `usize` | Output sink fd. `1` (stdout) by default; set per-file via `bufferedWriterInitFd`. `usize` since F-S9 (was `i32`) — an all-ones `INVALID_FD` sentinel (`pal.zig:70`) replaces the `-1` open-fail test |

| Function | Line | Purpose |
|----------|------|---------|
| `bufferedWriterInit` | 34 | Returns new BufferedWriter with `pos=0`, `buf=undefined`, `fd=1` (stdout) |
| `bufferedWriterInitFd` | 38 | Returns new BufferedWriter writing to the given fd (multi-module per-file sink) |
| `bufferedWriterFlush` | 42 | Writes `buf[0..pos]` to `self.fd` via `pal.fileWrite`, resets pos to 0 |
| `bufferedWriterWrite` | 50 | Writes byte slice to buffer. Loops: copies min(remaining, 4096-pos) bytes into buf, increments pos, flushes if full |
| `bufferedWriterWriteByte` | 65 | Single byte write, flush-if-full, store at pos, increment |
| `bufferedWriterWriteIndent` | 71 | Writes `level * 4` spaces (flush-safe, byte-by-byte) |

Markers `FL:p` (flush start, prints current pos) and `FE:p` (flush end, prints 0) bracket each flush.

### 1.3 NameMangler — Deterministic Name Mangling

Defined inline in `c89_emit.zig:83-90`. Separate from the minimal `name_mangler.zig` (which only has a counter — that file is a different/unused impl).

| Field | Type | Purpose |
|-------|------|---------|
| `hash_seed` | `u32` | Currently always 0 |
| `cache` | `U64ToU32Map` | Multi-key: `(module_id << 35) \| (kind << 32) \| name_id` → mangled_id |
| `keyword_set` | `U32ToU32Map` | All 32 C89 keywords (auto..while), interned name_id → 1 |
| `collision_mod` | `U32ToU32Map` | Mangled name_id → module_id (detects collisions) |
| `collision_name` | `U32ToU32Map` | Mangled name_id → original name_id (maps collision back) |
| `interner` | `*StringInterner` | For interning mangled name strings |

#### Mangling Scheme

`nameManglerMangle(name_id, kind, module_id)` (`c89_emit.zig:379`):

```
Format: z<K>_<8-hex-digits>_<original-name>
        ↑  ↑         ↑
        |  kind      hash
        prefix       (FNV-1a of original name)
```

1. **Temp/builtin bypass** (`isTempOrBuiltin`, line 113): Names starting with `__tmp`, `__ret`, `__bootstrap` return unmangled.

2. **C89 keyword escape** (`isC89Keyword` → `mangleC89Keyword`, line 125/288): If the name matches a C89 keyword, prefix with `z_` and return. e.g., `int` → `z_int`.

3. **Cache lookup** (line 384): Key = `(module_id << 35) | (kind << 32) | name_id`. If previously mangled, return cached.

4. **Mangle construction** (line 392-406):
   - `buf[0]` = `'z'` (prefix — avoids leading digit/underscore collision)
   - `buf[1]` = kind char: `F`=function(0), `G`=global(1), `T`=type(2), `L`=local(default)
   - `buf[2]` = `'_'`
   - `buf[3..11]` = 8 hex chars of FNV-1a hash
   - `buf[11]` = `'_'`
   - Followed by original name chars, truncated to fit 31 total

5. **31-char limit** (line 401-405): Total mangled name capped at 31 bytes (C89 standard minimum). Original name truncated if needed.

6. **Collision resolution** (line 410-450): If mangled name already used by a different `(module_id, name_id)`, append `_N` suffix with counter. Original name portion truncated further to stay within 31 chars. Digits counted dynamically before truncation.

7. **Cache population** (line 451-454): Store in `collision_mod`, `collision_name`, and `cache`.

#### Temp Name Mangling

`mangleTempName` (`c89_emit.zig:2349`): Format `zT_<temp_id>`. Used for hoisted temporaries in function bodies. No collision check needed — temp_ids are unique per function.

#### Local Name Mangling

`mangleLocalName` (`c89_emit.zig:1838`): If the name_id is a C89 keyword, prefix with `z_`. Otherwise return original name. Used for function parameters and local variables.

### 1.4 C89Emitter — Central Emitter State

Defined `c89_emit.zig:457-480`. Holds all emission context:

| Field | Type | Purpose |
|-------|------|---------|
| `writer` | `BufferedWriter` | 4KB output buffer |
| `indent` | `u32` | Current indentation level (incremented in fn bodies) |
| `alloc` | `*Sand` | Scratch arena allocator |
| `registry` | `*TypeRegistry` | Type system reference |
| `interner` | `*StringInterner` | String lookups |
| `mangler` | `*NameMangler` | Name mangling |
| `diag` | `*DiagnosticCollector` | Error reporting |
| `switch_cases` | `*SwitchCaseArrayList` | Current function's switch cases |
| `call_args` | `*U32ArrayList` | Temporary call argument buffer |
| `current_fn` | `*LirFunction` | Function currently being emitted |
| `d4_wtype` | `[*]u32` | Type propagation tracking (hoisted temps) |
| `d4_wflag` | `[*]u8` | Written flag: 0=unwritten, 1=resolved, 2=call-result |
| `d4_t2p` | `[*]u32` | Temp ID → hoisted_temps index mapping |
| `dl_hoisted` | `u8` | Whether decl_local hoisting has run (guard against double-emit) |
| `emitted_type_set` | `U32ToU32Map` | Dedup: type name hash → emitted marker |
| `fwd_decl_set` | `U32ToU32Map` | Dedup: forward decl name hash → emitted marker |
| `pointer_only_map` | `U32ToU32Map` | Type ids that need only forward decl |
| `shared_set` | `U32ToU32Map` | [updated: 2026-08-01] Type ids emitted into the shared `zig_special_types.h` — synthetics ∪ CLS:v ∪ i64/u64 ∪ named fn_type, plus CLS:p closure (see `computeSharedSet`). Closure criterion (F-S8): a type joins when it is referenced **by value OR in a way that requires the C type name in scope** — typedef'd kinds (enum/error_set) need the name in scope even through a pointer/slice (a `struct` tag can be implicitly forward-declared, a typedef cannot) |
| `dedup_names` | `[128]u32` | Local variable dedup during hoisting |
| `dedup_count` | `u32` | Count of dedup_names |
| `fl_name_ids` / `fl_temps` | `[128]u32` | Flat lookup: local name_id → temp_id |
| `fl_count` | `u32` | Count of flat lookup entries |

### 1.5 Type Name Generation

`getCTypeName` (`c89_emit.zig:509`) maps `TypeId` → C89 type name string:

| TypeKind | C89 Name | Notes |
|----------|----------|-------|
| `void_type` | `"void"` | Direct |
| `bool_type` | `"int"` | C89 has no bool |
| `i8_type` | `"signed char"` | |
| `i16_type` | `"short"` | |
| `i32_type` | `"int"` | |
| `i64_type` | mangled type | `typedef long long zT_<hash>_<name>` |
| `u8_type` | `"unsigned char"` | |
| `u16_type` | `"unsigned short"` | |
| `u32_type` | `"unsigned int"` | |
| `u64_type` | mangled type | `typedef unsigned long long ...` |
| `f32_type` | `"float"` | |
| `f64_type` | `"double"` | |
| `usize_type` | `"unsigned int"` | |
| `c_char_type` | `"char"` | |
| `enum_type` | mangled type | `typedef <backing> <mangled>;` |
| `array_type` | `Arr_<elem-cname>_<len>` | Typedef'd — `typedef <elem> Arr_<elem>_<len>[<len>];` |
| `ptr_type` / `many_ptr_type` | `<base>*` | Direct pointer syntax; fn ptr → use fn name |
| `slice_type` | `Slice_<elem>` | Typedef'd struct: `typedef struct { <elem>* ptr; unsigned int len; } ...;` |
| `optional_type` | `Opt_<payload>` | Typedef'd struct with `{ <type> value; int has_value; }`. **Payload-temp note [updated: 2026-08-07]:** null construction (`catch return null` / `return null` on a `?T` fn) no longer emits a scalar payload temp — the null_literal lowerer branch emits `set_optional_null` directly on an `Opt_`-typed temp (`zT_M.has_value = 0;`), so the old `int zT_N; zT_N = NULL;` dead store (gcc `-Wint-conversion`) is gone. |
| `error_union_type` | `EU_<payload>` | Typedef'd struct with `{ union { <type> payload; int err; } data; int is_error; }` |
| `fn_type` | `F_<N|P>_<ret>_<p1>_<p2>...` | `F_N_` for non-ptr, `F_P_` for ptr (FN_PTR flag) |
| `error_set_type` | mangled type | `typedef int <mangled>;` + `#define` for each error tag |
| `undefined_type` | `"int"` | Fallback |
| `null_type` | `"int"` | Fallback. **FIXED [updated: 2026-08-07, Option B]:** the dead `null_const` temp (`int zT_N; zT_N = NULL;` at c89_emit.zig:3908-3911, previously emitted when a null literal was coerced to an optional) is no longer produced — the lowerer emits `set_optional_null` directly on an `Opt_`-typed temp for null_src coercions. A `null_type`→`"int"` temp now only appears in the remaining `null_const` cases (uncoerced null / non-optional pointer/fn targets), which are pointer-compatible and gcc-clean. |
| `integer_literal_type` | `"int"` | Fallback |

When `ty.c_name_id != 0` (line 619), returns the cached C name directly (set by `emitErrorUnionType` for error union types).

### 1.6 Type Emission — emitSpecialTypes

`emitSpecialTypes` (`c89_emit.zig:1252`) drives type header output for the stdout single-file
path. For the multi-module path (`--output-dir`), the shared-header writer
`emitSharedHeader` (`c89_emit.zig:1105`) performs the equivalent partition into
`zig_special_types.h` (see §1.17):

```
emitSpecialTypes(emitter, reg):
  1. sorted = tstTopologicalSort(reg)           ← Kahn order
  2. fwd_decl pass: for each struct/tagged_union/union with name_id:
       emit "typedef <struct|union> <cname> <cname>;\n"
       keyword from aggregateKeyword(kind) — "union " for union_type else "struct "
       (F6: bare unions emit `typedef union` so the tag-namespace agrees with the def)
       dedup via fwd_decl_set (hash of cname string)
  3. pointer-only pass: for each type in sorted:
       if NOT in pointer_only_map → skip
       skip void/bool/noreturn/null/undefined/int-lit/type/module type
       if name_id==0 and not composite type → skip
       dedup via emitted_type_set (hash of cname string)
       emitTypeDefinition()
  4. value-embedding pass: for each type in sorted:
       if IS in pointer_only_map → skip
       same skip/filter logic as sub-pass 2a
       dedup via emitted_type_set
       emitTypeDefinition()
```

### 1.7 Type Definition Emission

`emitTypeDefinition` (`c89_emit.zig:1594`) dispatches by `TypeKind`:

| TypeKind | Emitter Function | Output |
|----------|-----------------|--------|
| `slice_type` | `emitSliceType` (1736) | `typedef struct { <elem>* ptr; unsigned int len; } Slice_<elem>;` |
| `optional_type` | `emitOptionalType` (1768) | `typedef struct { <type> value; int has_value; } Opt_<payload>;` (void payload: omit value). Null-payload temps for this type are emitted as `Opt_` (set_optional_null writes `has_value = 0;`) — see §1.4 [updated: 2026-08-07] |
| `error_union_type` | `emitErrorUnionType` (1812) | `typedef struct { union { <type> payload; int err; } data; int is_error; } EU_<payload>;` |
| `error_set_type` | `emitErrorSetType` (1633) | `typedef int <cname>;` + `#define <cname>_<tag> <N>` per tag |
| `tagged_union_type` | `emitTaggedUnionType` (1348) | Complex struct + union + tag constants |
| `enum_type` | `emitEnumType` (1688) | `typedef <backing> <cname>;` + `#define <cname>_<member> <val>` per member |
| `struct_type` | `emitStructType` (1502) | `struct <cname> { <type> <field>; ... };` |
| `union_type` | `emitUnionType` (1535) | `union <cname> { <type> <field>; ... };` — **real C union** (all members at offset 0, size = max member) matching `@sizeOf`'s union-max. **FIXED 2026-08-13 (Defect E, F6):** was emitted as a stacked `struct` via `emitStructType` (24B for 3×8B members vs `@sizeOf`=8 → arena allocators sized by `@sizeOf` overflowed → lisp_interpreter/json_parser_workaround SEGFAULT). Keyword at `:1543` comes from `aggregateKeyword(ty.kind)` (`c89_emit.zig:542`) — the same helper as the two fwd-decl sites (`emitSharedHeader` :1136, `emitSpecialTypes` :1267) so the C89 tag-namespace (struct/union tags share one namespace) always agrees (a one-keyword swap alone fails gcc `'zT_..._Data' defined as wrong kind of tag`). Field loop (`type name;`) is valid for unions unchanged. Guard tag is `ZIG_UNION_` (see §1.17). |
| `array_type` | `emitArrayType` (1541) | `typedef <elem> Arr_<elem>_<len>[<len>];` |
| `i64_type` | `emitInt64Type` (1718) | `typedef long long <cname>;` |
| `u64_type` | `emitUint64Type` (1727) | `typedef unsigned long long <cname>;` |
| `fn_type` | `emitFnPtrType` (1602) | `typedef <ret> (*<cname>)(<params>);` |

#### Tagged Union Emission

`emitTaggedUnionType` (`c89_emit.zig:1348`) handles two cases:

**Enum-tagged** (tag type is enum):
```
#define TU_<name>_<member> <N>
struct <name> {
    <tag-type> tag;
    union {
        char _dummy;
        struct { <field-type> _0; } <field-name>;
        ...
    } payload;
};
```

**Integer-tagged**:
```
#define <name>_<field> <N>
struct <name> {
    unsigned int tag;
    union {
        char _dummy;
        struct { <field-type> _0; } <field-name>;
        ...
    } payload;
};
```

Field constants are `#define`d for integer matching. Tagged union payload access uses `.payload.<field-name>._<sub-field-idx>`.

### 1.8 Function Emission

#### emitFunctionSignature (`c89_emit.zig:1854`)

```
/* <original-name> */
<return-type> <mangled-name>(<param-type> <param-name>, ...) {
```

- Mangled name via `nameManglerMangle(name_id, F, module_id)`
- `extern` functions: use original name, not mangled
- Comment with original name above signature for readability
- Empty params → `(void)`, variadic → `(...)`
- Opens `{` and increments indent
- **Variadic externs get forward declarations (Option B, F5 2026-08-06):** the
  extern-prototype guards (`emitModuleHeader` at `c89_emit.zig:1992` and the
  `:2143`-era twin) are `is_extern==0 OR is_variadic!=0`, so a variadic `extern
  fn printf(fmt, ...)` emits its C prototype (`int printf(unsigned char*, ...);`,
  name-passthrough) while non-variadic externs still rely on `@cInclude`'d
  headers.

#### emitHoistedDecls (`c89_emit.zig:2366`)

Emitted immediately after function signature, before body. Two passes:

**Pass 1: Type propagation** (line 1776-2080): Scans all instructions, tracks written types for temporaries via `d4_wtype`/`d4_wflag` arrays. Resolves `TYPE_UNDEFINED` temps to actual types. Keys:
- `.assign`: propagates src type to dst
- `.call_direct`/`.call`: marks as type 2 (call result — type resolved at runtime analysis)
- `.int_const`, `float_const`, `bool_const`, `string_const`, `enum_const` → set types
- `.binary`/`.unary`: propagates operand types to result
- `.int_cast`, `float_cast`, `ptr_cast`, `int_to_float`, `int_to_ptr`, `ptr_to_int`: use target type
- `.load`, `addr_of`, `load_index`, `load_field`, `make_slice`, `load_local`: set type from hoisted_temp or operand

**Pass 2: Declaration emission** (line 2132-2186): For each hoisted temp (skipping params), emits C declaration:
```
<type> zT_<temp_id>;
```
Skips `TYPE_VOID` temps (type_id == 1). Debug markers `D4:`, `D7:`, `D9:` track type resolution.

#### emitFunctionBody (`c89_emit.zig:4423`)

```
emitFunctionBody:
  1. Emit local variable declarations (decl_local hoisting):
     - Scans all blocks for decl_local instructions
     - Dedups by name_id (emitter.dedup_names[128])
     - Emits "type name;\n" for each unique local
     - Sets dl_hoisted guard
  2. Emit basic blocks:
     - Block 0: label "z_bb_0:" (emitted by the .loop_header inst — see §1.9)
     - Blocks > 0: label "z_bb_<id>:"
  3. Emit each instruction via emitInst()
  4. Close "}\n"
```

Blocks are labeled with `z_bb_<id>:` — C89-style goto labels. Since the TCO feature (F-S2 injects
`loop_header(0)` as the first entry-block inst, lower.zig:4350; F-S3 activates the `.loop_header`
arm, c89_emit.zig:3071-3073), **every function** also gets a `z_bb_0:` label for its entry block,
emitted after the hoisted temp decls and local decls and before the first entry-block statement:

```
ret_zF_fn(params) {
    <hoisted temp decls zT_N;>      (emitHoistedDecls)
    <local decls name;>             (emitFunctionBody decl_local hoist)
    z_bb_0:                         ← .loop_header arm (c89_emit.zig:3071-3073)
    <bb0 entry-block insts>
z_bb_1:
    <bb1 insts>
    ...
}
```

This is the TCO self-recursion jump target: self-tail calls emit rebind assigns + `goto z_bb_0;`
(back-edge to the entry block) instead of a recursive C call — O(1) stack for self-recursion. The
unused-`z_bb_0:` label in functions with no tail call produces a `-Wunused-label` gcc warning
(tolerated; gate is 0 errors). `[updated: 2026-08-03]`

### 1.9 LirInst → C89 Emission Table

Every `LirInst` variant handled in `emitInst` (`c89_emit.zig:3670`):

| LirInst | C89 Output | Line |
|---------|-----------|------|
| `.nop` | (nothing) | 3673 |
| `.ret_void` | `return;` | 3674 |
| `.loop_header` | `z_bb_0:` (entry-block label — TCO self-recursion jump target; since F-S3 emits `z_bb_0:\n`, NOT `tco_restart:`) | 3679 |
| `.label` | (nothing — waits for block label) | 3684 |
| `.decl_local` | Emitted by hoisting pass in emitFunctionBody | 5513 |
| `.assign` | `dst = src;` (array: `{ unsigned int _i=0; while(_i<N) { dst[_i]=src[_i]; _i++; } }`) | 3687 |
| `.assign_field` | `base.field = src;` (struct/union/ptr/slice/tagged_union) | 3763 |
| `.assign_index` | `base[idx] = src;` or `(*base)[idx] = src;` | 3775 |
| `.jump` | `goto z_bb_<id>;` | 3789 |
| `.branch` | `if (cond) goto z_bb_<then>; else goto z_bb_<else>;` | 3803 |
| `.ret` | `return val;` | 3828 |
| `.load_local` | `result = name;` (array: `{ ... for-loop copy ... }`) | 3837 |
| `.store_local` | `name = val;` (`_` → `(void)val;`) | 3886 |
| `.load_global` | `result = name;` | 3916 |
| `.store_global` | `name = val;` | 3962 |
| `.load_field` | `result = base.field;` (slice → `.ptr`/`.len`; tagged_union → `.tag`/`.payload`; ptr → `->field`; struct → `.field`) | 4007 |
| `.store_field` | `base.field = val;` (same field resolution as load_field; ptr-base struct/union pointee → `ptr->field`, :4199-4218) | 4150 |
| `.load_index` | `result = base[idx];` or `result = (*base)[idx];` | 4276 |
| `.load` | `result = *ptr;` | 4280 |
| `.store` | `*ptr = val;` | 4292 |
| `.addr_of` | `result = &operand;` | 4305 |
| `.binary` | `result = lhs op rhs;` (op: `+` `-` `*` `/` `%` `&` `\|` `^` `<<` `>>` `==` `!=` `<` `<=` `>` `>=`; **BIN_EQ/BIN_NE with `tagged_union_type` operands append `.tag` to each operand name** → `s.tag == t.tag`, valid C, active-tag comparison — Task F, 2026-08-08, ruling m0471) | 4369 |
| `.unary` | `result = op operand;` (op: `-` `!` `~`) | 4430 |
| `.int_const` | `result = <value>;` (signed: cast + neg magnitude to avoid warnings; tagged_union: `.tag = <value>;`) | 4443 |
| `.enum_const` | `result = <type>_<member>;` | 4517 |
| `.float_const` | `result = <d.ddd>;` (via `formatF64`) | 4534 |
| `.string_const` | `result = "<escaped>";` (escape: `\n`, `\t`, `\r`, `\\`, `\"`) | 4551 |
| `.null_const` | `result = NULL;` (optional type → `result.has_value = 0;`) | 4585 — note: null_src null construction (return/catch null → optional) no longer emits `.null_const`; the lowerer emits `.set_optional_null` directly (Option B, 2026-08-07) |
| `.set_optional_null` | `result.has_value = 0;` | 4599 |
| `.bool_const` | `result = 1;` or `result = 0;` | 4606 |
| `.undefined_const` | `result = 0;` (arrays: `{ ... for-loop zero ... }`; tagged union arrays: `[_i].tag = 0;`; nested struct arrays: recursive loop) | 4618 |
| `.call` | `result = callee(args...);` (indirect call through function pointer) | 4692 |
| `.call_direct` | `result = fn_name(args...);` (extern return wrapping for optional/error_union) | 4718 |
| `.tail_call` | `result = fn_name(args...); return result;` — call+ret **fallback**, NOT a jump (cross-function TCO is semantic only until an asm backend); void return → `fn_name(args...); return;`; extern override (AMENDMENT 6) → original name; indirect callee via `resolveTempName` | 4853 |
| `.switch_br` | `switch (cond) { case <val>: goto z_bb_<target>; ... default: goto z_bb_<else>; }` | 4899 |
| `.wrap_optional` | `result.has_value = 1;\n result.value = src;` | 4941 |
| `.int_cast` | `result = (type)src;` (checked: `result = __bootstrap_<DST>_from_<SRC>(src);`) | 4967 |
| `.int_to_float` | `result = (type)src;` | 5040 |
| `.float_cast` | `result = (type)src;` | 5055 |
| `.make_slice` | `result.ptr = ptr;\n result.len = len;` | 5070 |
| `.print_str` | `std_print("literal");` | 5089 |
| `.print_val` | `std_print_<type>(val);` (slice → `std_print_str(val.ptr, val.len)`) | 5098 |
| `.ptr_cast` | `result = (type)src;` | 5215 |
| `.check_error` | `result = src.is_error;` | 5230 |
| `.unwrap_error_payload` | `result = src.data.payload;` | 5241 |
| `.unwrap_error_code` | `result = src.data.err;` (void-payload → `src.err;`) | 5267 |
| `.wrap_error_ok` | `result.data.payload = src;\n result.is_error = 0;` (void-payload → `result.err = 0;\n result.is_error = 0;`) | 5296 |

**[updated: 2026-08-14 — F3 review follow-up: all rows in this table grep-verified against
current source (the 2026-08-13 pass left the 19 trailing rows + `.tail_call` stale; F1/F4/F6
additions shifted the arms +~1200 lines); `emitInst` header :3062 → :3670.]**
| `.wrap_error_err` | `result.data.err = src;\n result.is_error = 1;` (void-payload → same pattern, `.err`) | 5325 |
| `.check_optional` | `result = src.has_value;` | 5357 |
| `.unwrap_optional` | `result = src.value;` (void-payload → nothing) | 5370 |
| `.unwrap_optional_abi` | `result = src.has_value ? src.value : NULL;` | 5396 |
| `.int_to_ptr` | `result = (type)(unsigned int)src;` | 5410 |
| `.ptr_to_int` | `result = (usize)src;` | 5425 |
| `.func_ref` | `result = fn_name;` (function pointer) | 5440 |
| `.va_start` | `va_start(vl, last_param);` | 5452 |
| `.va_arg` | `res = va_arg(vl, TYPE);` (TYPE = `getCTypeName(type_id)`) | 5465 |
| `.va_end` | `va_end(vl);` | 5480 |
| `.builtin_put_char` | `putchar(value);` | 5118 |
| `.builtin_stdout_write` | `fwrite(ptr, 1, len, stdout);` (via `emitFwriteCall` :3139) | 5127 |
| `.builtin_stderr_write` | `fwrite(ptr, 1, len, stderr);` | 5130 |
| `.builtin_get_char` | `result = getchar();` (result typed `unsigned char`) | 5133 |
| `.builtin_exit` | `exit(value);` | 5140 |
| `.builtin_sleep_ms` | `#ifdef _WIN32` `Sleep(value);` `#else` `usleep(value * 1000);` `#endif` | 5149 |
| `.builtin_console_clear` | `#ifdef _WIN32` `FillConsoleOutputCharacter/Attribute`+home `#elif __WATCOMC__`/`#else` `__bootstrap_write("\x1b[2J\x1b[H", 7)` `#endif` | 5173 |
| `.builtin_console_gotoxy` | `#ifdef _WIN32` `SetConsoleCursorPosition(COORD)` `#elif __WATCOMC__`/`#else` `sprintf(buf, "\x1b[%d;%dH", y+1, x+1)` + `__bootstrap_write` `#endif` | 5176 |
| `.builtin_console_set_color` | `#ifdef _WIN32` `SetConsoleTextAttribute` `#elif __WATCOMC__`/`#else` `sprintf(buf, "\x1b[%s;%sm", fg_ansi[fg&0x0F], bg_ansi[bg&0x0F])` + `__bootstrap_write` `#endif` | 5179 |

Any unhandled variant falls through the `else => {}` at line 4885 (no-op).

**`@intCast` range-check emission (F1, 2026-08-06):** the `.int_cast` checked arm
(`c89_emit.zig:4214-4260`) builds `__bootstrap_<DST>_from_<SRC>` from the target's
`getCastTypeSuffix` and the source temp's `getTempTypeByIndex`, falling back to a
raw `(type)` cast when the source type is unknown. The 19 helpers are `static` in
`sf/src/include/zig_runtime.h` (per-TU, oracle pattern) + `extern` in
`sf/src/include/zig_runtime.c`; the message is `"integer cast overflow in
@intCast"` and the unchecked `(type)` path is unchanged. **`stdarg.h` gating
(F5, 2026-08-06):** `emitStdargInclude` (`c89_emit.zig:1985`) emits `#include
<stdarg.h>` only when `moduleHasVaInsts` (`:1964`) finds a `va_start`/`va_arg`/
`va_end` LirInst in the TU — gated on actual `va_*` usage (not `is_variadic`), so
mud/gol's anytype-print (`is_variadic=1`, no `va_*`) stays byte-identical. The
include is emitted at all 3 sites (`emitModuleHeader` `:1972`,
`emitModuleHeaderFile`, `emitModuleFile`).

**[updated: 2026-08-08] Builtin include gating (F1):** `emitBuiltinIncludes`
(`c89_emit.zig:2052`) emits `#include <stdio.h>` when any of
`builtin_put_char`/`builtin_stdout_write`/`builtin_stderr_write`/`builtin_get_char`
appear in the TU, `#include <stdlib.h>` for `builtin_exit`, and a guarded
`#ifdef _WIN32` `#include <windows.h>` `#else` `#include <unistd.h>` `#endif` for
`builtin_sleep_ms` — each gated on actual usage (`moduleHasStdioBuiltin` :1996 /
`moduleHasExitBuiltin` :2014 / `moduleHasSleepBuiltin` :2032), so the 4 MD5-gate
examples (which use none of the 6 builtins) stay byte-identical. The includes are
emitted in BOTH the single-stream `emitModuleHeader` and the multi-module
`emitModuleFile` (`:2405`) paths — the multi-module `--output-dir` path does NOT go
through `emitModuleHeader`, so omitting the second site made `io_builtin_test`
gcc-fail on `stdout`/`stderr` undeclared (fixed). `usleep` verified to compile under
`gcc -m32 -std=c89` on the host glibc (declared via default feature macros; the
`_XOPEN_SOURCE 500` note in zig0's runtime is only needed on pre-2.19 glibc).

**[updated: 2026-08-08] Builtin console include gating + emission (F2):**
`emitBuiltinIncludes` (`c89_emit.zig:2073`) emits, when `moduleHasConsoleBuiltin`
(`:2052`) finds any `builtin_console_*` inst, the Win98-forcing preamble + `windows.h`
on `_WIN32` / `<stdio.h>` on `#else` (for `sprintf`), plus an unconditional
`extern void __bootstrap_write(const char* s, unsigned int len);` (the POSIX arms use
the `__bootstrap_write` alias — declared in `zig_runtime.h` for the single-stream path
and self-declared here for the multi-module path which does not include `zig_runtime.h`).
The 3 emission arms (`c89_emit.zig:4789-4797`, helpers `emitConsoleClear` :3186 /
`emitConsoleGotoxy` :3239 / `emitConsoleSetColor` :3283) each emit the
`#ifdef _WIN32 / #elif defined(__WATCOMC__) / #else` guard chain — Win32 arms mirror the
zig0-oracle runtime bodies (zig_runtime.c:301-356); the `__WATCOMC__` and `#else` arms
share the ANSI-escape body (`__bootstrap_write`). Deviation from zig0: the Win32
`@consoleClear` body is restructured (no `return` — it is emitted inline in the user
function, so the zig0 `return`s would exit the caller; `if (hOut != INVALID_HANDLE_VALUE
&& GetConsoleScreenBufferInfo(...)) { … }` instead). `@isWindows()` emits NO C (folded
in sema/comptime to an `int_const` 0/1). `console_builtin_test` is gcc-clean single-
AND multi-module.

**C89 cross-function TCO limitation — [updated: 2026-08-03]:** `.tail_call` (c89_emit.zig:3954) is
emitted as a **call followed by a `return`** (`zT = fn(args); return zT;`), i.e. it preserves a C
stack frame — it is semantically a tail call but not a jump. Only **self-recursion** TCO achieves
O(1) stack (rebind assigns + `goto z_bb_0;` back-edge to the entry label). Real frame-reusing
cross-function tail calls (jump to the callee without a new frame) require a backend that can emit a
proper tail-jump; until such an asm backend exists, cross-function TCO is call+ret. The `.tail_call`
written-type-scan case (`c89_emit.zig:2584`) marks the result temp as a call-result (written_flag=2)
so it is not flagged UNWRITTEN by the decl pass.

### 1.10 emitModule — Top-Level Orchestration

`emitModule` (`c89_emit.zig:2201`) drives one module's output for the **stdout single-file
path only** (bare `--dump-c89`). [updated: 2026-08-01] When `--dump-c89 --output-dir DIR` is
set, `phase_C89Emission` instead emits `zig_special_types.h` once via `emitSharedHeader` and
loops modules emitting per-module `.h`/`.c` via `emitModuleHeaderFile`/`emitModuleFile`
(see §1.17); `emitModule` is unchanged for the stdout path. Note that `phase_C89Emission`
(`main.zig:709`) runs BEFORE it: it creates a separate `BufferedWriter` (`cwriter`), emits the
fixed `emitIncludes` preamble (`#include "zig_compat.h"` + `#include "zig_runtime.h"`,
`c89_emit.zig:744`), flushes it (`main.zig:829-830`), then calls `emitModule` with the
hardcoded module name `"output"` (`main.zig:627`) — hence `/* Module: output */` in every dump.

```
emitModule(emitter, name, fns, c_includes, ptr_only_ids):
  1. Populate pointer_only_map from ptr_only_ids
  2. emitSpecialTypes(emitter, registry)      ← Phase 1: type headers
  3. emitModuleHeader(name, fns, c_includes)  ← Phase 2a: includes + fwd decls
  4. For each function (if not extern):
     a. emitter.switch_cases = &func.switch_cases
     b. emitFunctionSignature(emitter, &func)
     c. emitHoistedDecls(emitter, &func)      ← temp declarations
     d. emitFunctionBody(emitter, &func)       ← basic block insts
     e. If func.is_pub and name=="main":
        - Emit int main(void) wrapper
        - Handles void/error_union/normal return types
  5. emitModuleFooter()                       ← "/* EOF */\n"
```

#### main() Wrapper

When a public function named `main` is found, an additional `int main(void)` wrapper is emitted:

| Return Type | Wrapper |
|------------|---------|
| `void` | `int main(void) { zF_<hash>_main(); return 0; }` |
| `error_union` (void payload) | `int main(void) { ... return result.is_error ? result.err : 0; }` |
| `error_union` (non-void payload) | `int main(void) { ... return result.is_error ? result.data.err : (int)result.data.payload; }` |
| normal | `int main(void) { return (int)zF_<hash>_main(); }` |

#### emitModuleHeader (`c89_emit.zig:1992`)

```
/* Module: <name> */
#include "zig_compat.h"
#include "zig_special_types.h"
<c-includes...>

/* Forward declarations */
<func-forward-decls...>
```

C-includes: if starts with `<`, emit raw (`#include <foo.h>`). Otherwise wrap in quotes (`#include "foo.h"`).

### 1.11 emitModuleFooter (`c89_emit.zig:2030`)

```
/* EOF */
```

### 1.12 emitFunctionForwardDecl (`c89_emit.zig:1920`)

Emits `return-type fn-name(param-types...);` — same mangling as signature but without param names.

### 1.13 emitBaseIdxAccess (`c89_emit.zig:144`)

Handles indexed load/store with ptr-to-array detection:

- Ptr-to-array: `result = (*base)[idx];` or `(*base)[idx] = src;`
- Normal: `result = base[idx];` or `base[idx] = src;`

`isBasePtrToArray` (`c89_emit.zig:130`) checks if a temp's type is ptr-to-array.

### 1.14 emitFieldAssign (`c89_emit.zig:188`)

Resolves field access for `.assign_field`:

| Base Type | Access Pattern |
|-----------|---------------|
| `slice_type` | `.ptr` (field 0), `.len` (field 1), `.f_<N>` (N>1) |
| `tagged_union_type` | `.tag` (field 0), `.payload.<variant-name>._<sub>` or `.payload` (field 1) |
| `ptr_type`/`many_ptr_type` → `struct_type` | `->field` |
| `struct_type` | `.field` (with array copy: `{ ... while(_j < len) { base.field[_j] = src[_j]; _j++; } }`) |
| `union_type` | `.field` (FIXED 2026-08-13, F1): the base-type dispatch (c89_emit.zig:188-307) gained a `union_type` branch (c89_emit.zig:260-274) mirroring the `struct_type` branch but scanning `un_items[payload_idx].fields_start` + `fe_items` for `field_id` (with the same array-copy handling). Previously a union-typed base fell through to the numeric `.f_<field_id>` fallback; now it emits `.member_name` like `store_field`'s ptr-base `->` emitter (c89_emit.zig:4199-4218, struct pointee :4202-4209, union pointee :4210-4218). Emits `zT_3.Int = v;` for a bare-union struct-literal member (repro `union_literal_nested_xmod` prints `42`; was gcc `'zT_3' undeclared`). **[F3 line-ref pass 2026-08-13: ptr-base store_field ref corrected — :4180-4188 → :4199-4218.]** |
| unknown | `.f_<field_id>` (numeric fallback) |

### 1.15 Helper Functions

| Function | Line | Purpose |
|----------|------|---------|
| `getBinOpStr` | 3079 | Maps binary op u8 → C operator string (+, -, *, /, %, &, \|, ^, <<, >>, ==, !=, <, <=, >, >=) |
| `getUnOpStr` | 3099 | Maps unary op u8 → C operator string (-, !, ~) |
| `getCheckedCastFnName` | 2215 | Maps TypeId → checked cast function name (std_checked_cast_i8/u8/i16/u16/i32/u32/i64/u64) |
| `getPrintFnName` | 2229 | Maps TypeId → print function name (std_print_u32/u64/i64/f64/bool/char/str) |
| `emitCStringLiteral` | 2241 | Emits C string literal with escape sequences (\n, \t, \r, \\, \") |
| `resolveTempName` | 2259 | Resolve temp_id → C name. Checks local flat lookup first (fl_temps), falls back to mangleTempName |
| `getTempTypeByIndex` | 696 | Find type_id for a temp_id by scanning hoisted_temps |
| `mangleTempName` | 1667 | Format `zT_<temp_id>` for temp variables |
| `mangleLocalName` | 1436 | Format local: keyword-safe (z_ prefix) or original |
| `writeHex` | 92 | Write 8 hex digits of u32 to buffer |
| `isTempOrBuiltin` | 113 | Check if name starts with `__tmp`, `__ret`, `__bootstrap` |
| `isC89Keyword` | 125 | Check if name_id is in keyword_set |
| `dbgPrintU32` | 75 | Debug: write u32 to stderr |

### 1.16 Marker Reference

| Marker | Location | Meaning |
|--------|----------|---------|
| `C` | emitModule | Start of C89 emission phase |
| `FINAL_FLUSH` | main.zig | Final buffer flush, emission complete |
| `FL:p` | bufferedWriterFlush | Flush start (pos value) |
| `FE:p` | bufferedWriterFlush | Flush end (0) |
| `E2A:t` | emitSpecialTypes sub-pass 2a | Processing type in pointer-only pass |
| `E2B:t` | emitSpecialTypes sub-pass 2b | Processing type in value-embedding pass |
| `D2:t` | emitSpecialTypes 2b | Debug: tagged union type in sub-pass 2b |
| `D6:t` | getCTypeName | C-name lookup debug — fires for every `tid>=20` type (very noisy) |
| `ET:t` | emitTypeDefinition | Emitting type definition (tid + kind) |
| `ES:n` | emitStructType | Struct type emitted (mangled name id) |
| `FE:` | emitStructType | Field entry detail (name_id:type_id) |
| `FWD:n=` | emitFunctionSignature | Forward decl detail (name_id, module_id) |
| `HTT:` | emitHoistedDecls | Hoisted temp type tracking (temp_id, type_id) |
| `P0:` | emitHoistedDecls | Parameter/local count |
| `P1:` | emitHoistedDecls | Local decl discovery (temp, type_id, name_id) |
| `P2:` | emitHoistedDecls | Final local count |
| `P3:` | emitHoistedDecls | Assign propagation (dst, src, type) |
| `D4:` | emitHoistedDecls | Type propagation debug summary |
| `D7:` | emitHoistedDecls | Written type detail |
| `D9:` | emitHoistedDecls | Call-result type (type 2) detail |
| `RST:t` | resolveTempName | Temp resolution (temp_id → name_id) |
| `I` | emitInst | Instruction start |
| `BIN:` | emitInst (.binary) | Binary inst debug (dst, lhs, rhs) |
| `BNR:` | emitInst (.binary) | Binary name resolution lengths |
| `ASX:` | emitInst (.assign) | Assign debug (dst, src) |
| `AS:t` | emitInst (.assign) | Assign type lookup |
| `AIDX:` | emitInst (.assign_index) | Index assign debug (base, index, src) |
| `AFE:` | emitInst (.assign_field) | Field assign debug (base, field_id) |
| `LFD:` | emitInst (.load_field) | Load field debug (base, result) |
| `LFU:` | emitInst (.load_field) | Load field unresolved (field_id) |
| `LL:` | emitInst (.load_local) | Load local debug (name_id, result) |
| `LLd:` | emitHoistedDecls (.load_local) | Load local type debug |
| `STL:` | emitInst (.store_local) | Store local debug (name_id, value) |
| `STN:` | emitInst (.store_local) | Store local name=value |
| `DC2:` | emitInst (.call_direct) | Direct call debug (name_id, result) |
| `AD:` | emitInst (.call) | Call arg count |
| `INSTA:` | emitInst | Instantiation detail (optw, optt, optu, tulf, eup, euc) |
| `INSTC:` | emitInst (.binary) | Constant RHS |
| `VFLOW:` | emitInst | Variable flow tracking (cdv, ldv, spv, rnt, dlt, ehd, ehdv, ehdd, opV, oTV) |
| `WRAP:main` | emitModule | main() wrapper emitted |
| `GAPC:` | emitInst | Gap check markers (coe, cos) |
| `JXP` | emitInst (.jump) | Jump instruction |
| `MTP:ti` | emitHoistedDecls | Type 1 (void) temp skip |
| `T4U:` | emitFunctionBody | Type 4 (?) temp declaration in body |
| `INSTB:` | emitFunctionBody | Instance temp body |
| `DxA:` | emitFunctionBody | Duplicate local skipped |

### 1.17 Multi-Module Emission (`--output-dir`) — [updated: 2026-08-01]

With `--dump-c89 --output-dir DIR`, `phase_C89Emission` (`main.zig:709`) switches from the single
stdout stream to **per-module file emission**. Output set: `DIR/<qualified>.c` (one per module) +
`DIR/<qualified>.h` (one per module) + `DIR/zig_special_types.h`. Bare `--dump-c89` (no
`--output-dir`) keeps the stdout single-file path (§1.10) byte-identical — the two paths are
branched on the CLI, never mixed.

- **Qualified filename scheme (F-S7)** — output stems come from `moduleQualifiedName`
  (`c89_emit.zig:2035`): `DIR/<basename clamped 64>_<FNV1a8>.c/.h`, where `<basename>` is the
  module path's last `/` component with `.zig`/`.z98` stripped (clamped to 64 chars) and
  `<FNV1a8>` is the 8-uppercase-hex FNV-1a hash of the **full module path**
  (`hash_mod.fnv1a` + `writeHex`, the same pair the mangler uses). **NO module_id** in the
  filename. This eliminates the F-S7 basename-collision bug (two same-named files in different
  dirs silently overwrote each other in `DIR/`); every filename is unique per path, so a module
  importing two same-basename deps now gets two distinct `.h` files and two distinct `#include`
  lines (previously the same `#include "util.h"` was emitted twice).
- **Length guard (F-S7)** — `main.zig:769` checks `od.len + 1 + base.len + 3 > 511` before
  constructing each path; if exceeded, `error: output filename too long` + `pal.exit(1)`. This
  replaces the old silent truncation at `main.zig:685`/`:712` (bytes were dropped past 510/511
  with no diagnostic, and the truncated filename mismatched the include chain).
- **Shared header** — `emitSharedHeader` (`c89_emit.zig:1105`): calls `computeSharedSet`
  (`c89_emit.zig:1025`), then emits `zig_special_types.h` with file guard `ZIG_SPECIAL_TYPES_H`,
  preamble `#include "zig_compat.h"` + `#include "zig_runtime.h"`, an unfiltered fwd-decl pass
  (`typedef <struct|union> X X;` for every named struct/tagged_union/union — keyword from
  `aggregateKeyword(kind)` :542, so bare unions forward-decl `typedef union X X;` matching their
  definition; F6), sub-pass 2a restricted to
  `shared_set` (guarded), and all of sub-pass 2b. `computeSharedSet` seeds synthetics
  (`name_id==0` in slice/optional/error_union/tagged_union/union/array/fn_type) ∪ value-embedding
  named types (CLS:v, `pointer_only_map` miss) ∪ i64/u64 ∪ named fn_type, then closes over
  pointer-only named types referenced by shared members (fixpoint over `reg.types_len`, via
  `tstIsDep` `c89_emit.zig:922`).
- **Closure-edge model (F-S8)** — the closure criterion is: a type joins `shared_set` when it is
  referenced **by value OR in a way that requires the C type name in scope** (typedef'd kinds —
  enum/error_set — need the name in scope even behind a pointer/slice, since a typedef cannot be
  implicitly forward-declared like a `struct` tag can). `c89NeedsEmitEdge` admits enum/error_set
  targets; `tstIsDep`/`tstEdgesCount`/`tstEdgesFill` gained **optional_type / slice_type / union_type
  source branches**. Per operator ruling (2026-08-01, F-S8 amendment 4), the optional/slice edges are
  **RESTRICTED** — they only fire when the element target is `enum_type`/`error_set_type`. This
  prevents the recursive-slice 2-cycle hazard (`[]T` inside `T` where `T` is a CLS:p struct would
  otherwise create a shared-set cycle); unrestricted slice/optional edges would also bloat the shared
  header by promoting any CLS:p struct used only as a slice element. `union_type` is unrestricted
  (by-value fields).
- **Slice-elem type-name-in-scope note** — a `Slice_<elem>` holds a *pointer* to `elem`
  (`<elem>* ptr;`), so it is not by-value; but the **elem's C name must still be in scope** when
  the typedef is emitted. For a `struct` elem a fwd-decl suffices; for an **enum/error_set** elem
  (a typedef) the full typedef must precede the slice — this is exactly the F-S8 fix's slice-elem
  target support.
- **Guard scheme** — every type definition is wrapped
  `#ifndef ZIG_<TAG>_<cname> / #define ZIG_<TAG>_<cname> / <def> / #endif`. Tag from
  `ctypeGuardWrite` (`c89_emit.zig:997`): `ZIG_STRUCT_`, `ZIG_UNION_`, `ZIG_ENUM_`,
  `ZIG_ERROR_SET_`, `ZIG_SLICE_`, `ZIG_OPTIONAL_`, `ZIG_ERRORUNION_`, `ZIG_ARRAY_`,
  `ZIG_FNPTR_`, `ZIG_I64_`, `ZIG_U64_`, fallback `ZIG_TYPE_`.
- **Per-module `.h`** — `emitModuleHeaderFile` (`c89_emit.zig:2078`): module guard
  `ZIG_MODULE_<UPPER(qualified)>_H` (the **qualified** stem uppercased, non-alnum → `_`; since
  F-S7 the stem already embeds the unique path hash, so guards auto-unique even for two
  same-basename modules — e.g. `ZIG_MODULE_UTIL_7F9D0FD1_H`); includes `zig_compat.h`
  + `zig_special_types.h`; the module's own `@cInclude` directives (`entry.c_includes`,
  per-module — NOT the global `cincludeUnionAll` union); each direct-import dep's `.h` by its
  **qualified** name (`#include "<moduleQualifiedName(emitter,d)>.h"`, skipping self —
  `c89_emit.zig:2121-2128`); owned CLS:p
  type full-definitions (name_id≠0, `module_id==M.id`, struct/TU/union/enum/error_set,
  `pointer_only_map`, not in `shared_set` — each guarded); fn fwd-decls (non-extern).
- **Per-module `.c`** — `emitModuleFile` (`c89_emit.zig:2323`): `#include "<qualified>.h"`, then the
  module's own fn bodies (externs skipped; `switch_cases`/`dl_hoisted` reset per fn). The
  `int main(void)` wrapper is emitted only for `module_id==0`'s public `main`
  (`emitMainWrapper`, `c89_emit.zig:2237`).
- **Embedded build-script templates are DEAD CODE** — `emitBuildTargetSh` (`c89_emit.zig:4482`) /
  `emitBuildTargetBat` (`c89_emit.zig:4495`) / `emitBuildTargetOwcBat` are never called by any
  pipeline path (explicit `// Reference-only:` comment at `c89_emit.zig:4478`). They exist as
  frozen templates only; the real multi-module build flow is the glob-based gcc recipe in
  QUICK_REF/NOTES.md.

- **Module→file emission loop — NO silent module drop (verified 2026-08-08).** The multi-module
  branch of `phase_C89Emission` loops `mods = moduleRegistryGetModules(ctx.module_reg)`
  (`main.zig:760`) and, for each registered module, emits one `.h`
  (`emitModuleHeaderFile`, `main.zig:796` / `c89_emit.zig:2078`) and one `.c`
  (`emitModuleFile`, `main.zig:819` / `c89_emit.zig:2323`). The loop is over the module registry,
  so **every registered module is emitted — there is no drop path**. Verified on
  `sf/build/out_release/zig1` (2026-08-08): 8 module-graph shapes probed (linear chain, diamond,
  import-only chain, type-only, import cycle, const re-export, 4-deep chain, and json_parser's
  star) — ALL registered modules emit `.c`, gcc compile+link+run rc=0. The
  `mod_silent_drop_xmod` repro (3-module transitive chain) emits `main`/`lib_b`/`lib_a` and links
  clean; it is kept as a **regression guard** for the (false) D2 "silent module drop" theory.
  **The original D2 premise is FALSE**: no registered module is ever silently dropped.
- **Orphan-module handling — un-imported files are never emitted (correct, matches oracle).** A
  `.zig` file with NO incoming `@import` edge is never added to the module registry:
  `phase_ImportResolution` (`main.zig:262-270`) registers only the CLI entry module
  (`moduleRegistryAddModule`, `main.zig:266`), then `moduleRegistryResolveImports`
  (`import_resolver.zig:83-144`) enqueues modules **only** via import edges
  (`import_resolver.zig:134-140`). Orphan files are silently skipped by the emission loop.
  Example: `examples/z98/json_parser/arena.zig` is never `@import`ed (grep confirms) → no
  `arena_*.c` is emitted. The zig0 oracle behaves identically (emits `main.c`/`json.c`/`file.c`,
  NOT `arena.c`). This is correct behavior, not a compiler defect.
- **Cross-module enum-literal comparison gap — I3 (2026-08-08): FIXED (F3). `'zT_XX' undeclared`
  in the importing module's `.c` was the symptom.** Repro `repro/mi_matrix/zT_missing_fwd_xmod/`
  (types.zig declares
  `pub const Tag = enum { Null, Boolean, Number }`; main.zig does `tag == t.Tag.Null`) and
  `examples/z98/json_parser_workaround` (6 sites: `val.tag == json.JsonValueTag.Null` etc.)
  fail gcc with `'zT_2' undeclared` / `'zT_10'/'zT_16'/'zT_28'/'zT_34'/'zT_46'/'zT_91'
  undeclared`. **NOT a header forward-decl gap**: the importing `.h` already `#include`s the
  defining module's `.h` and the enum typedef (`zT_F8835433_Tag` etc.) IS in scope. The defect
  is a **sema/lowering gap** that makes the enum-literal RHS resolve to `TYPE_VOID`, so the
  emitted body references a VOID-typed temp that is never declared (c89_emit skips VOID temps,
  `c89_emit.zig:2897`) and never assigned.
  - **Semantic root** (`semantic_analyzer.zig:232`, `semanticAnalyzerResolveFieldAccess`): the
    `enum_type` member lookup (lines 260-271) fires ONLY when `base_node.kind == ident_expr`
    (same-module `Tag.Null`). A cross-module qualified literal `json.JsonValueTag.Null` is a
    *nested* `field_access` (base = `field_access(json, JsonValueTag)`), so the ident branch is
    skipped and the generic dispatch (lines 374-463) handles struct/union/tagged_union/module/
    slice/error_set — **no `enum_type` case** → falls to the `else` at line 459 → returns
    `TYPE_VOID`. Comparison (`semanticAnalyzerResolveComparison`, line 540) therefore sees
    `lhs=Tag, rhs=VOID` (marker `CPVl23r1`).
  - **Lowering root** (`lower.zig:1953` field_access): the enum-member path (lines 1960-2015,
    which emits `.enum_const`) also fires only for an `ident_expr` base. For `json.JsonValueTag`,
    the module branch (lines 2016-2061) returns `gtemp = nextTemp(res_type_id)` — an enum-typed
    temp with **no init inst** (this is the phantom declared-but-never-assigned `zT_1`). The
    outer `.Null` then hits the generic base-type path (lines 2064-2196, pre-fix refs), which has no
    enum_type/tagged_union member-literal case → `tid = nextTemp(TYPE_VOID)` (line 2143, from
    `fa_box[0]`==VOID) → VOID temp returned, never written. Emission of `tag == zT_void` then
    references an undeclared temp.
  - **Type category of the gap:** **plain `enum` (`enum_type`) literals accessed through a
    qualified cross-module path in a VALUE/comparison position.** Struct-by-value params work
    (the typedef is forwarded via the fn-signature fwd-decl path — verified `dist(p: t.Point)`
    emits `zT_EAA8EF31_Point` cleanly); `union(enum)` tagged-union literals in `switch` cases
    work (they go through the switch enum-literal path, e.g. lisp_curr + working json_parser).
    A cross-module tagged-union literal in a `==` (`.Null` on `t.Val`) additionally SEGVs the
    compiler (separate crash: `typeRegistryGetStructFields` via `lower.zig:2174`-ish path) — a
    related but distinct defect.
  - **Blast radius:** only modules that compare a plain cross-module enum member against a value
    (`== t.Tag.X`) break. lisp_curr (10 modules), mud_server, game_of_life, working
    `json_parser` all compile with 0 gcc errors — they never form this pattern (lisp/json use
    `switch` over `union(enum)`; mud/gol have no cross-module plain-enum compares).
    `json_parser_workaround` is the only gated example affected; the `zT_missing_fwd_xmod`
    repro is the minimal guard. **Fix (F3, 2026-08-08 — Option A implemented):** an `enum_type`
    member-literal case was added to the generic base-type dispatch in `semanticAnalyzerResolveFieldAccess`
    (semantic_analyzer.zig:459 — before the `else`; resolves `mod.Type.Member` to the member value
    via `en_items`/`em_items`, mirroring the same-module ident_expr path at :260-271) and to
    `lower.zig`'s field-access generic base-type path (lower.zig:2207 — after the struct/union/TU
    branch; emits `.enum_const` with the member ordinal, mirroring :1981-1999). The defining
    module's enum is already in the shared type registry, so the member lookup works cross-module.
    Post-fix: `zT_missing_fwd_xmod/` dump rc=0, gcc compile rc=0, run rc=0 (`zT_3 =
    zT_F8835433_Tag_Null;` is now emitted); `json_parser_workaround/` gcc compile rc=0 (all 6
    `zT_10/16/28/34/46/91` resolved); mud/gol/lisp/json 4 MD5 gates byte-identical;
    test_analyzer_bin PASS. Option B (whitelist fwd-decl of enum typedefs in importing headers)
    was rejected — it does NOT fix the real defect (the typedef is already in scope).
- **Cross-module tagged-union `==` / member-literal SEGV — I6 (2026-08-08): FIXED (F6).** Repro
  `repro/mi_matrix/tagged_union_cmp_xmod/` (`lib.zig`: `pub const Shape = union(enum){ Circle: i32,
  Square: i32, Triangle: i32 }`; `main.zig`: `if (s == lib_mod.Shape.Circle)` in a fn param of type
  `lib_mod.Shape`) **SEGVs zig1 in `phase_LIRLowering`** (ASan DEADLYSIGNAL rc=1, 0 `.c` emitted)
  pre-fix. **Fix (F6, 2026-08-08 — Option (a), the lower.zig dispatch fix ONLY):** the generic
  base-type field-access branch (`lower.zig:2174-2206`) gained a dedicated `tagged_union_type`
  case that mirrors the same-module member path (`lower.zig:1966-1979`): the member is looked up
  in `tu_items[ty.payload_idx]` and, on match, the union's tag value is emitted via
  `emitTaggedUnionInit(self, fa_box[0], variant_idx)` (a TU-typed `int_const` → C `.tag = <ordinal>;`)
  instead of calling `typeRegistryGetStructFields` on the TU type. The sema reject-`==`
  diagnostic (Option (b)) was NOT implemented — out of scope per the operator ruling m0406.
  Post-fix: `tagged_union_cmp_xmod` dumps rc=0 (SEGV gone); the isolated member-literal form
  `var x = lib_mod.Shape.Circle;` is gcc-clean and RUNS (tag value emitted). The repro's `==`
  form now emits `zT_3.tag = 0; zT_4 = s.tag == zT_3.tag;` — **gcc-valid** (the separate latent
  union-`==` emission issue — BIN_EQ emitted `lhs == rhs` in C, no union-equality path — is now
  FIXED by Task F, Option A, 2026-08-08: the `.binary` handler appends `.tag` to
  `tagged_union_type` operands for BIN_EQ/BIN_NE, per operator ruling m0471 which supersedes the
  zig0 oracle's rejection of union `==`). The repro compiles, links, and RUNS printing `1`. 4 MD5
  gates byte-identical; corpus CRASH=0 (was 1); test_analyzer_bin PASS.
  `[gdb]`/`[asan]` backtrace: `#0 typeRegistryGetStructFields` ← `#1 lowerExprImpl` ← `lowerExpr`
  ← `lowerStmt` ← `lowerFn` ← `phase_LIRLowering`.
  - **Crash locus:** `lower.zig:2180` — the generic base-type field-access branch (lines 2174-2180)
    routes `tagged_union_type` into the struct/union/TU bucket but calls
    `typeRegistryGetStructFields` (`type_registry.zig:782-787`) for anything that is NOT plain
    `union_type`. `typeRegistryGetStructFields` does `self.st_items[ty.payload_idx]` — a tagged
    union's `payload_idx` indexes `tu_items`, NOT `st_items`, so this reads a garbage
    StructPayload → garbage `fields_start`/`fields_count` → `fe_items[fstart..fstart+fcount]` is an
    out-of-range slice → SEGV (zero-page read).
  - **Mechanism (cross-module member literal):** `lib_mod.Shape.Circle` parses as *nested*
    `field_access(field_access(lib_mod, Shape), Circle)`. The outer `.Circle` has base = a
    `field_access` (NOT `ident_expr`), so the same-module member path is skipped in BOTH sema and
    lower (sema `semantic_analyzer.zig:240` ident branch; lower `lower.zig:1956`). The generic
    base-type dispatch (`lower.zig:2064-2196`) then sees a base whose resolved type is the
    tagged_union type and enters the struct/union/TU branch at line 2174 → line 2180 →
    `typeRegistryGetStructFields(TU_tid)` → SEGV. The same-module `Shape.Circle` control works
    ONLY because its base is an `ident_expr` resolving to a `type_alias` (`lower.zig:1960-1979`
    tagged_union branch → `emitTaggedUnionInit`), never reaching line 2180.
  - **Variant matrix (all measured on `sf/build/out_release/zig1`):**
    | variant | program | zig1 | zig0 oracle |
    |---|---|---|---|
    | same-module `s == Shape.Circle` | union declared in-file | **Task F: rc=0, emits `zT_2 = s.tag == zT_1.tag;` — gcc-valid, runs printing `1`** (was gcc-invalid `zT_2 = s == zT_1;`) | **REJECTS** cleanly (`error: type mismatch`, rc=1) — superseded by ruling m0471 (Option A emits valid C) |
    | cross-module `var x = lib_mod.Shape.Circle;` | member literal, no `==` | **pre-fix SEGV rc=1 → F6: rc=0, gcc-clean, runs** (emits `zT_3.tag = 0; x = zT_3;`) | accepts (emits tag-enum value `enum Shape_Tag x = Shape_Tag_Circle;`, gcc-clean) |
    | cross-module `s == lib_mod.Shape.Circle` | the repro | **pre-fix SEGV rc=1 → F6: rc=0 → Task F: rc=0, gcc-clean, runs printing `1`** (emits `zT_3.tag = 0; zT_4 = s.tag == zT_3.tag;`) | **REJECTS** cleanly (rc=1) — superseded by ruling m0471 (Option A emits valid C) |
    | same-module TU VALUE payload access `s.Circle` | `var v = s.Circle;` | **pre-fix SEGV rc=1 → F6: no longer SEGVs** (member lookup in `tu_items`; still returns the tag value, not the payload — payload-read emission is a follow-up) | accepts (emits `v = s.data.Circle;`, gcc-clean) |
  - **Findings:** (1) the crash is NOT `==`-specific and NOT even cross-module-specific — ANY
    field access whose resolved base type is a tagged_union and which is NOT the same-module
    `ident_expr`→`type_alias` member path hits lower.zig:2180 and SEGVs (includes same-module TU
    VALUE payload access `s.Circle`). (2) The `==` form is a SEPARATE defect: even same-module,
    union `==` emits gcc-invalid C (the emitter had NO union-equality path — `BIN_EQ` just emitted
    `lhs == rhs` in C; `c89_emit.zig:3708`) — **now FIXED by Task F (Option A, `.tag` suffix
    emission, ruling m0471)**. (3) sema silently resolves `union == union` to
    `TYPE_VOID` with NO diagnostic (`semanticAnalyzerResolveComparison`, `semantic_analyzer.zig:563-568`
    returns VOID for same-type non-bool/non-pointer) — so the compiler neither rejects nor emits
    valid C; it just falls through to lowering and crashes.
  - **Oracle reference (fix-target adjudication):** zig0 REJECTS `union == member` with a clean
    type mismatch (`invalid operands for comparison operator '==': 'union Shape' and
    'comptime_int'`) — same-module AND cross-module (verified). It does NOT support union `==` at
    all. The I6 investigation recommended (b) reject-in-sema + the dispatch fix, but the **operator
    ruling m0406 = implement Option (a) ONLY** — the lower.zig dispatch fix. The sema reject-`==`
    diagnostic (Option (b)) is OUT OF SCOPE and NOT implemented. The lower.zig:2180 SEGV fix (a
    `tagged_union_type` case in the generic field-access dispatch so member literals lower to the
    tag value) landed F6: valid programs (`var x = lib.Shape.Circle;`, TU member access) no longer
    crash. The repro's `==` form then emitted gcc-invalid C (`zT_4 = s == zT_3;` — binary `==` on
    the struct union, no union-equality emission path) — a SEPARATE latent issue. **Task F
    (2026-08-08) FIXES that latent issue (Option A, emitter):** per operator ruling m0471, zig1
    SUPERSEDES the zig0 oracle for union `==` — the `.binary` handler (c89_emit.zig:3724-3739)
    now resolves each BIN_EQ/BIN_NE operand's temp type in `hoisted_temps` and appends `.tag`
    to `tagged_union_type` operands (mirroring the int_const `.tag =` path), emitting valid C
    `s.tag == t.tag` with valid Zig semantics (union `==` compares the active tags). This applies
    to BOTH cross-module and same-module union `==`/`!=`. The sema reject-`==` diagnostic (Option
    (b)) remains OUT OF SCOPE.
  - **Blast radius:** gates mud/gol/lisp/json use tagged-union `switch` (works, lower's
    switch-case path), never `==` on union values (`builtins.zig:124` `res = a == b` compares
    `*Value` POINTERS, not union payloads — unaffected). No gated example flips with the crash
    fix or the `==` emission fix. Corpus: `tagged_union_cmp_xmod` is now fully OK (dump rc=0,
    gcc rc=0, link rc=0, runs printing `1`); the same-module `s == Shape.Circle` variant is also
    gcc-valid and runs. No other repro uses cross-module TU member `==`.
- **Runtime-symbol gap (json_parser case) — defect class (b), NOT an emission defect — FIXED
  (F3, std.arena migration, 2026-08-08).** `json.zig` / `file.zig` / `arena.zig` previously
  called `extern fn arena_alloc_default(size: usize) *void` (`json.zig:253`, `file.zig:25`;
  `examples/zig0/json_parser` identical). Externs are link-time-provided — the compiler never
  emits their definitions. The symbol IS declared in `sf/src/include/zig_runtime.h:21` (and
  `extern void* zig_default_arena` at `:22`), IS defined in the legacy
  `src/runtime/zig_runtime.c` (`zig_default_arena` at `:31`; `arena_alloc_default` at `:154-156`;
  documented runtime API — `docs/reference/runtime_api.md:38-48`), but was **MISSING from
  `sf/src/include/zig_runtime.c`** (0 arena matches in 210 lines vs 365 legacy), so the standard
  QUICK_REF-recipe link failed `undefined reference to arena_alloc_default` (5 refs: `json.c` ×4 +
  `file.c` ×1) and the workaround was a legacy-runtime object link. **F3 resolves the gap with a
  Zig-side module instead of a runtime C symbol**: new `sf/src/std_arena.zig` (pure Z98 bump
  allocator — `Arena{data,capacity,used}`, `create/alloc/reset` over a static 1 MB buffer),
  copied into the example dirs so `@import("std_arena.zig")` resolves locally; the examples now
  call `std.create/alloc` (no extern, no runtime change). Verified: multi-module dump rc=0
  (main/json/file/std_arena emit), per-file gcc `-c` rc=0, **standard-recipe link rc=0 (no legacy
  object)**, run rc=0 (parses test.json) for both `json_parser` and `json_parser_workaround`;
  runtime output byte-identical to the pre-fix legacy-linked binary (`diff` empty, F-5 AMENDMENT B
  precedent). The `extern_runtime_symbol_xmod` repro was migrated identically and is now a green
  cross-module std.arena regression guard. `repro/mi_matrix/EXPECTED_FAIL.md` F3 section + both
  example NOTES.md record the fix. [updated: 2026-08-08]

---

## 2. `cinclude.zig` — @cInclude Dedup (26 lines)

### Function

`cincludeUnionAll` (`cinclude.zig:7`):

```
cincludeUnionAll(module_reg, alloc) → []u32:
  1. temp = u32ArrayListInit(alloc)   ← result accumulator
  2. seen = u32ToU32MapInit(alloc)    ← dedup tracker
  3. For each module in module_reg:
     a. For each c_include name_id in module.c_includes:
        i. If seen[ name_id ] exists → skip duplicate
        ii. Else: seen[name_id] = 1, append name_id to temp
  4. Return temp slice
```

This produces a flat deduplicated list of all `@cInclude` directives across all modules. Used by `emitModuleHeader` to emit `#include` lines per module — this applies to the stdout single-file path.
[updated: 2026-08-01] In the multi-module path (§1.17), `emitModuleHeaderFile` does NOT use the
global union — each module `.h` emits its own `entry.c_includes` directives directly (per-module
`@cInclude`), so a directive only appears in the header of the module that declared it.

### Struct — ModuleEntry Fields Touched

From `module_registry.zig`: `ModuleEntry` contains `c_includes: U32ArrayList` — a list of interned name_ids for `@cInclude` strings.

---

## 3. `name_mangler.zig` — Minimal Counter (7 lines)

The standalone `name_mangler.zig` file contains only:

```
pub const NameMangler = struct { counter: u32 };
pub fn nameManglerInit() NameMangler { return .{ .counter = 0 }; }
```

**This file is NOT the primary mangler used by `c89_emit.zig`.** The actual `NameMangler` with hash/cache/keyword handling is defined inline in `c89_emit.zig:83-90`. The standalone file appears to be a separate or deprecated implementation. See §1.3 above for the actual mangler.

---

## 4. Data Flow

```
LirFunction list (per module)
    │
    ▼
emitModule(c89_emit.zig:2201)
    │
    ├─ pointer_only_map populated from caller-provided ids
    │
    ├─ emitSpecialTypes (type headers, topological order)
    │   ├─ tstTopologicalSort (Kahn) ← TypeRegistry
    │   ├─ Forward decls (typedef struct X X;)
    │   ├─ Pointer-only type definitions
    │   └─ Value-embedding type definitions
    │
    ├─ emitModuleHeader (includes + fn forward decls)
    │   └─ cincludeUnionAll → deduped #include lines
    │
    ├─ For each function:
    │   ├─ emitFunctionSignature → "return-type name(params) {"
    │   ├─ emitHoistedDecls → local temp variables
    │   └─ emitFunctionBody:
    │       ├─ decl_local hoisting (dedup)
    │       └─ Basic blocks w/ emitInst
    │
    └─ emitModuleFooter → "/* EOF */\n"
            │
            ▼
        stdout (via BufferedWriter 4KB)
```

### Arena Usage

| Arena | Usage |
|-------|-------|
| Scratch (reset per phase) | `C89Emitter` struct, `NameMangler` hash maps (cache, keyword_set, collision maps), template arrays (dedup_names[128], fl_name_ids[128], fl_temps[128]), type propagation arrays (d4_wtype, d4_wflag, d4_t2p) |

---

## 5. Debugging

### Marker Activation

Run compiler with `--markers` to emit phase trace to stderr:
```
$ zig1 --markers source.zig
C            ← Phase 8 start
FL:p<pos>    ← Buffer flush (Writes to stdout)
FE:p0        ← Flush done
...
FINAL_FLUSH  ← Emission complete
```

### C89 Output Comparison Against zig0

zig0 has `--dump-c89` flag that outputs its generated C89. zig1's output using the same input can be diffed:

```
$ zig0 --dump-c89 source.zig > /tmp/zig0.c 2>/dev/null
$ zig1 source.zig > /tmp/zig1.c
$ diff /tmp/zig0.c /tmp/zig1.c
```

Differences are expected due to:
- Name mangling scheme differences
- zig0 may emit dead code zig1 optimizes out
- zig0 works around C89 portability issues differently

### Type Emission Debug

Markers `D2:t`, `E2A:t`, `E2B:t`, `ET:t`, `ES:n`, `FE:` trace type emission order. Check that types are emitted before they are used in function bodies.

### Temp Type Propagation Debug

Markers `P0:`-`P3:`, `D4:`, `D7:`, `D9:`, `HTT:` show the type resolution for each hoisted temporary. `D7:` shows resolved type vs hoisted type. `D4: MISMATCH` indicates a type mismatch between hoisted and resolved type.

### Common Issues

- **Undefined C89 identifiers**: Check type emission order (topo sort). Forward declarations sufficient for pointer-only types.
- **Identifier too long**: 31-char C89 limit enforced in `nameManglerMangle`. Verify truncated names are still unique.
- **Collision warnings**: `collision_mod` map catches duplicate mangled names. Counter suffix appended automatically.
- **Missing main wrapper**: Check `func.is_pub == 1` and name is exactly `"main"`.
- **C89 keyword conflicts**: `isC89Keyword` + `mangleC89Keyword` adds `z_` prefix.

---

## 6. Empirical Deep-Dive: 4 Working Examples (P8)

> Evidence methods: `[c89]` = direct inspection of the emitted C (`/tmp/dd/*.c`),
> `[markers]` = P0 `--markers` traces (`/tmp/dd/*.mrk`), `[source]` = `c89_emit.zig` /
> `main.zig` / `cinclude.zig`, `[fnv]` = independent FNV-1a recomputation.
> Examples: `examples/z98/{mud_server,game_of_life,json_parser,lisp_interpreter_curr}/main.zig`.
> All 4 emitted files gcc-compile to executables (P0 gate), so the observed orders are
> compilation-valid.

### 6.1 Type Header Emission Order (Q1)

The emitted typedef sequence IS the Kahn sort order: both sub-passes iterate the same
`sorted = tstTopologicalSort(reg)` array (`[source]` `c89_emit.zig:959`, called at `:2206`;
pass 2a `:1256`, pass 2b `:1297`), deduped via `emitted_type_set`. Forward declarations for every named
struct/tagged_union/union are emitted first (`[source]` `c89_emit.zig:1233-1255`; `[c89]`
mud_server.c:3-6, game_of_life.c:3-4, json_parser.c:3-5, lisp_interpreter_curr.c:3-8).

Observed definition order per example (first→last) `[c89]` + `[markers]` (E2A/E2B type-id
sequence, exactly the `sorted` order):

| Example | Type definition order (as emitted) |
|---------|-----------------------------------|
| mud_server | i64, u64, Command (tagged_union), Arr_u32[128], Arr_u8[256], Slice_u8, Opt_41, EU_1, Room, plat_fd_set, Player, Arr_Player[10], Arr_Room[2] |
| game_of_life | i64, u64, Cell (tagged_union), Point, Slice_Cell, Slice_Point, EU_1, Arr_Cell[800], Arr_Point[3], Arr_Point[4], Arr_Point[6], Arr_Point[9] |
| json_parser | i64, u64, FileError, ParseError, Slice_u8, Opt_29, Slice_JsonValue, Slice_JsonItem, Opt_33, Opt_34, EU_1, EU_92, Parser, JsonItem, JsonValue, EU_45, Slice_c_char, Arr_u8[64], EU_52 |
| lisp_interpreter_curr | i64, u64, Sand, LispError, Slice_u8, anon_3546 (Cons), Opt_41, Arr_u64[131072], EU_63, EU_93, EU_7, EU_14, Slice_*Value, FP fn-ptr, Token, Tokenizer, EnvNode, EU_24, Arr_char[2], Arr_u8[4096], Arr_u8[1], Value, EU_23 |

**Is it topological? YES.** Every type embedding another by value is emitted after the
embedded type `[c89]`:
- mud: Room→Slice_u8, plat_fd_set→Arr_u32[128], Player→Arr_u8[256], Arr_Player[10]→Player, Arr_Room[2]→Room.
- json: Parser→Slice_u8; JsonItem→Slice_JsonItem; JsonValue→Slice_JsonValue/Slice_JsonItem; EU_52 (payload by value)→JsonValue.
- lisp: Value→anon_3546 (Cons embedded by value, lisp_interpreter_curr.c:92 vs :41); EU_23 (Token by value)→Token.
- Pointers to not-yet-defined structs are fine (incomplete type in C): e.g. json Opt_29 uses
  `zT_E9CE9840_JsonValue*` with only the fwd decl visible (json_parser.c:24 vs :46).

Sub-pass markers fire even for types that emit nothing `[markers]` (dedup or no-op branch):
mud `E2B:t61` (array, no visible typedef — no `ET:`), mud `E2B:t63` (ptr → no `ET:`),
gol `E2B:t46..t52` (slices/tuples/ptrs → no visible typedef; the arrays t41-45 in the same
pass DO emit). The C-visible typedef set is a strict subset of the sorted iteration.

The sorted tail resolves aggregates LAST (mud `…, 26 Command, 25 Room, 23 plat_fd_set,
24 Player, 62 Arr_Player, 47 Arr_Room, 61 dup`), consistent with P3's documented Kahn
dynamics (degenerate from=0 edge set). This tail is NOT contiguous in the marker stream:
`[markers]` `E2A: … t26 … t60, t25` (pointer-only pass) then `E2B:t63, t23, t24, t62, t47, t61`
(value-embedding pass). `E2A:t25k25` / `E2B:t23k25n43` confirm the
sub-pass split matches the `pointer_only` classification from P3.

### 6.2 Mangled Function Names & 31-char Limit (Q2)

`zF_<8-hex>_<name>` for all non-extern functions `[c89]` (fwd-decl section of each `.c`).
5 key functions per example:

| Example | Mangled names |
|---------|---------------|
| mud_server | `zF_00BC8D75_initRooms`, `zF_59D9CF45_parseCommand`, `zF_EA90E208_main`, `zF_E7D5C1AB_processCommand`, `zF_649527FD_eql` |
| game_of_life | `zF_071EEE2B_setPattern`, `zF_EA90E208_main`, `zF_540CA757_get`, `zF_C6270703_set`, `zF_3313BBE7_countNeighbors` |
| json_parser | `zF_209CECBA_printSlice`, `zF_67463B19_printValue`, `zF_5B859C63_readFile`, `zF_C0DEFC8E_parseJson`, `zF_12860F5B_parseObject` |
| lisp_interpreter_curr | `zF_EA90E208_main`, `zF_08D22E0F_eval`, `zF_24BC4A3B_apply`, `zF_9C1A101A_parse_expr`, `zF_0A23CE02_next_token` |

- **FNV-1a confirmed `[fnv]`**: independent recomputation (offset `0x811C9DC5`, prime
  `0x01000193`) of all 48 unique function names across the 4 examples matches every emitted
  hash exactly (e.g. `main`→`EA90E208` in all 4, `eval`→`08D22E0F`, `apply`→`24BC4A3B`,
  `parserSkipWhitespace`→`2C9F470C`). `[source]` `c89_emit.zig:387`.
- **31-char limit — exactly ONE hit across all 4 examples** `[c89]`:
  `zF_2C9F470C_parserSkipWhitespac` (json_parser) = 31 chars (name "parserSkipWhitespace"
  truncated 20→19; json_parser.c:76 fwd, :1040 def, call sites :1249/:1347). Truncation loop
  `[source]` `c89_emit.zig:401-405` (copy while `p < 31`). Longest other name: 26 chars.
- **Collision resolution unexercised**: no `_N`-suffixed mangled names in any output
  (`[c89]` grep for `zF_<hash>_name_N`; the `EU_<n>`/`Opt_<n>`/`Arr_<n>` suffixes are the
  type-scheme, not collision suffixes). `[source]` collision loop `c89_emit.zig:410-450`.
- **Caveat**: error-set members emit as `#define zT_<hash>_<Set>_<Member> <N>` macros whose
  names exceed 31 chars — `zT_91ED3DBA_ParseError_ExpectedCommaOrEnd` (41, json_parser.c:20),
  `zT_45176AD9_LispError_UnexpectedRParen` (38, lisp:18). Macros compile fine under
  `gcc -std=c89` (no `-pedantic`); the 31-char mangler limit applies to identifiers, not these
  `#define` names.

### 6.3 @cInclude Lists & Dedup (Q3)

`cincludeUnionAll` (`cinclude.zig:7-26`, called at `main.zig:832`) dedups by interned name_id
across ALL modules; `emitModuleHeader` emits `zig_compat.h` + `zig_special_types.h` then the
deduped list (`[source]` `c89_emit.zig:1996-2013`). `<...>` form emitted raw, `"..."` quoted
(`:2006-2013`).

| Example | @cInclude directives (by module) | Emitted module-header includes | Dedup |
|---------|----------------------------------|-------------------------------|-------|
| mud_server | main.zig:4 zig_runtime.h, :5 net_runtime.h; std_debug.zig:1 zig_runtime.h (dup) | `zig_runtime.h` + `net_runtime.h` (mud_server.c:47-48) | **exercised** — 3 directives → 2 lines |
| game_of_life | main.zig:3 zig_runtime.h, :4 `<stdlib.h>`; std_debug.zig:1 zig_runtime.h (dup) | `zig_runtime.h` + `<stdlib.h>` (gol.c:30-31) | **exercised** |
| json_parser | main.zig:4-6 zig_runtime.h, `<stdio.h>`, `<stdlib.h>`; file.zig:1-2 `<stdio.h>`, `<stdlib.h>` (dups) | `zig_runtime.h` + `<stdio.h>` + `<stdlib.h>` (json.c:64-66) | **exercised** — 5 directives → 3 lines |
| lisp_interpreter_curr | main.zig:11-12 zig_runtime.h, `<stdio.h>` | `zig_runtime.h` + `<stdio.h>` (lisp:100-101) | no dups |

**Observation**: `zig_compat.h` and `zig_runtime.h` appear TWICE in every output — once in the
fixed `emitIncludes` preamble (`c89_emit.zig:744`, flushed from `main.zig:829-830`) and
once in the module header (`[c89]` mud_server.c:1-2 vs :45-48). Dedup applies only WITHIN the
collected `@cInclude` list, not against the preamble — benign (include guards), undocumented
elsewhere.

### 6.4 Function Body Emission Order (Q4)

Emission iterates `fns` in list order, skipping externs (`[source]` `c89_emit.zig:1607-1611`).
The list is built in module-registration order × source decl order (`[source]` `main.zig:543-615`:
per module, per top-level `fn_decl`, `lowerFn` appended to `ctx.lir_fns`). Therefore
**emission order == LIR function order == source declaration order**.

| Example | Emitted fn order (first→last) `[c89]` |
|---------|--------------------------------------|
| mud_server | initRooms, parseCommand, main, processCommand, eql (util.zig), copy (util.zig), print (std_debug.zig) |
| game_of_life | setPattern, main, get, set, countNeighbors, print, printInt (std_debug.zig) |
| json_parser | printSlice, printIndent, printValue, main, readFile (file.zig), parserPeek, parserAdvance, parserSkipWhitespace, parserExpect, parseJson, parseValue, parseNull, parseBoolean, parseString, parseNumber, isDigit, parseFloat, parseArray, parseObject (json.zig) |
| lisp_interpreter_curr | print_str, print_value, print_list, read_line, main (main.zig), sand_init, sand_alloc, sand_reset (sand.zig), alloc_value … alloc_builtin (value.zig), is_whitespace, is_digit, skip_whitespace, next_token, peek_token, parse_int_simple (token.zig), parse_expr, parse_list (parser.zig), env_find_node, env_lookup, env_extend (env.zig), eval, env_to_value, apply, value_to_env_real (eval.zig), builtin_cons … builtin_gt (builtins.zig), mem_eql, parse_int, points_to_arena (util.zig), deep_copy (deep_copy.zig) |

Module order == import/registration order: mud main→util→std_debug; gol main→std→std_debug;
json main→file→json (arena.zig is never imported → its `alloc_bytes` is absent from the
output; json uses extern `arena_alloc_default`, json.zig:253); lisp main→sand→value→token→
parser→env→eval→builtins→util→deep_copy (matches main.zig:1-9 import order). Each fn def is
preceded by a `/* original-name */` comment (`[source]` `c89_emit.zig:1464-1468`), which makes
the order directly readable from the `.c`.

Count check: emitted bodies 7/7/19/45; P7 LIR totals 20/11/48/32 include the externs
(mud 13 extern + 7; gol 4 + 7; json 13 + 19; lisp 3 + 45). These counts exclude the
`int main(void)` wrapper (mud:1198, gol:1188, json:697, lisp:2109), emitted last in each
file immediately after the mangled `main` body (8/8/20/46 incl. wrapper).

### 6.5 2-Phase Output Confirmation (Q5)

**Type definitions precede ANY function body** — guaranteed structurally (`emitSpecialTypes`
before the fn loop, `[source]` `c89_emit.zig:1605-1611`) and observed in all 4 outputs `[c89]`:

| Example | typedefs end | first fn def |
|----------|--------------|--------------|
| mud_server | :43 | :59 |
| game_of_life | :26 | :42 |
| json_parser | :60 | :89 |
| lisp_interpreter_curr | :96 | :150 |

Marker sequence `[markers]`: `C` (main.zig:710) → `FL:p49`/`FE:p0` (preamble flush, main.zig:829-830)
→ `E2A:`/`E2B:` type passes → fwd-decl/fn-body markers → `FINAL_FLUSH` (main.zig:834; exactly 1
per trace). The preamble is a SEPARATE `BufferedWriter` (`cwriter`, main.zig:827-830) flushed
before `emitModule`; the module name is hardcoded `"output"` (main.zig:731) — hence
`/* Module: output */` in every file.

### 6.6 extern "c" Functions (Q6, mud_server)

extern "c" socket functions are emitted as **bare, unmangled C calls with NO declarations in
the output** (grep `extern` → 0 hits in mud_server.c `[c89]`). Prototypes come from the
`@cInclude`d `net_runtime.h` (net_runtime.h:6-17). Examples: `zT_0 = plat_socket_init();`
(mud_server.c:553), `zT_8 = plat_create_tcp_server(zT_6);` (:567),
`zT_97 = plat_accept(zT_96);` (:798), `zT_159 = plat_socket_fd_isset(zT_153, zT_154);` (:954),
`plat_close_socket(zT_145);` (:926).

Mechanism `[source]`: signature uses original name if `is_extern` (`c89_emit.zig:1885`, in
`emitFunctionSignature` :1875); externs get no fwd decl (the `emitFunctionForwardDecl` caller
guards on `is_extern == 0`, :2177/:2324) and no body (`if (func.is_extern == 0)` :2370);
call sites use the original name
(`:4733`). **[F3 line-ref pass 2026-08-13: extern mechanism refs corrected — :1864→:1885,
:1927→:2177/:2324, :2333→:2370, :4048→:4733.]**
Discarded extern results: `_ = plat_send(...)` → `zT_126 = plat_send(...);
(void)zT_126;` (mud_server.c:883-884, matches `.store_local` `_`→`(void)val;`).

**Extern-return wrapping unexercised**: every extern in the 4 examples returns plain i32/void,
so the `need_wrap` branch (`c89_emit.zig:3150-3165`) never fires. The only optional-wrapping in
mud is the non-extern `wrap_optional`+`unwrap_optional_abi` for `plat_socket_select`'s `?*u8`
arg: `zT_75.has_value = 1; zT_75.value = zT_74;` then `zT_76 = zT_75.has_value ? zT_75.value :
NULL;` (mud_server.c:707-715).

### 6.7 Instruction Emission vs Actual C89 (Q7)

The §1.9 table matches the actual output for load/store/call (verified against `[source]`
lines and `[c89]`):

| Inst | Source pattern | Emitted C evidence |
|------|----------------|--------------------|
| `.load` | `result = *ptr;` (`:2768`) | lisp:6177 `zT_5 = *fun;`, :5646 `zT_390 = *zT_389;`, :5657 `zT_434 = *zT_433;` |
| `.store` | `*ptr = val;` (`:2780`) | lisp:2322 `*v = zT_8;`, :5033 `*curr_env = zT_172;`, :5079 `*slot = zT_194;` |
| `.call` (indirect) | `result = callee(args...);` (`:3103`) | lisp:6198 `zT_12 = f(zT_10, zT_11);` — the ONLY fn-ptr call in all 4 (apply→builtin); counts 0/0/0/1 |
| `.call_direct` | `result = fn(args...);` (`:3129`, unmangled extern `:3142`) | mud:553 `zT_0 = plat_socket_init();`, :173 `zT_6 = zF_649527FD_eql(zT_1, zT_2);`; MARKER_CALL comments 28/19/127/166 |
| `.load_index` | `result = base[idx];` (`:2764`) | gol:1232 `zT_15 = zT_11[zT_14];` |
| `.assign_index` | `base[idx] = src;` (`:2370`) | gol:645 `zT_85[zT_89] = zT_86;` (+23 more) |
| `.assign` array copy | `{ unsigned int _i=0; while(_i<N){ dst[_i]=src[_i]; _i++; } }` (`:2284`) | gol:490-496 `grid[_i] = zT_1[_i];` |
| `.undefined_const` tagged-union array | `[_i].tag = 0;` (`:3029`) | gol:482-488 `zT_1[_i].tag = 0;` |
| `.branch` | `if (c) goto A; else goto B;` (`:2398`) | lisp:6446 `if (zT_75) goto z_bb_38; else goto z_bb_39;` |
| `.store_local` `_` | `(void)val;` (`:2481`) | gol:908 `(void)zT_243;`, mud:884 `(void)zT_126;` |

Also observed live: `.switch_br` (lisp:6180-6184 `switch (zT_6) { case 5: goto z_bb_1; … }`),
`.ptr_cast` (lisp:6188 `zT_9 = (zT_E323FAA2_FP_zT_4D8485C8_EU_9)f_ptr;`), tagged-union
`.load_field` (lisp:6179 `zT_6 = zT_5.tag;`, :6187 `f_ptr = zT_5.payload.Builtin._0;`).

**In-output debug comments**: the emitter writes `/*==MARKER_CALL n=<id> m=<mod>==*/`
(`c89_emit.zig:3130-3139`), `/*==MARKER_ASSIGN dst=<n> src=<n>==*/`, `/*==LF:f0 b5==*/` and
similar comment markers INTO the emitted C (200 in mud_server.c `[c89]`). These are gated on
`pal.isMarkersEnabled()` (controlled by `--markers` CLI flag) and are distinct from the stderr
`I`/`BIN:`/… markers in §1.16. Without `--markers`, zero MARKER_ comments appear in C89 output.
[updated: 2026-07-31] The `I` marker (per-instruction, `c89_emit.zig:2273`) appears throughout fn-body
emission — a "stray I\n late in the trace" is this documented marker, not a separate artifact.

### 6.8 Gaps & Unexercised Paths Found

- **Tagged unions: only the integer-tagged path is exercised.** All 5 tagged unions in the
  corpus (mud Command, gol Cell, json JsonValue, lisp Value/Token) emit
  `unsigned int tag;` + per-field `#define <name>_<field> <idx>` (`[source]` `c89_emit.zig:1081-1129`;
  `[c89]` mud_server.c:13-19, gol:7-14, json:40-56, lisp:80-95). The enum-tagged branch
  (`TU_`/`zTU_` prefixes, `c89_emit.zig:1008-1080`) never fires.
- **Extern optional/error_union return wrapping unexercised** (see §6.6).
- **Collision resolution unexercised** (see §6.2).
- **Error-set `#define` names exceed 31 chars** (see §6.2) — macro names, not mangler output.
- **Marker-table gap**: `D6` (`c89_emit.zig:511-519`, getCTypeName debug, fires for every
  `tid>=20` cname lookup) was not listed in §1.16 (added above).

### 6.9 Networking builtins inventory (Phase-2 std-lib plan, I-NET) [updated: 2026-08-08]

**Source of truth:** `sf/src/include/net_runtime.c` (153 lines) + `net_runtime.h:6-17`. All 12
`plat_*` socket symbols are emitted as **bare unmangled extern calls** (see §6.6) — prototypes
come from `@cInclude`d `net_runtime.h`, no fwd-decl/body in output. The Phase-2 networking
builtins (plan F6: socketCreate, socketBindListen, socketAccept, socketConnect, socketSend,
socketRecv, socketSelect, socketFdZero, socketFdSet, socketFdIsset, socketClose) replace these
extern calls; 10 of 12 symbols map 1:1, `socketConnect` has **no** existing source (net_runtime.c
has no `plat_connect`; mud_server is server-only), and `socketInit`/`socketCleanup` are not in
the 11-builtin list (lifecycle stays extern or folds into builtin init).

**12-symbol inventory** (fd convention = plain `int`/i32, the arch-independence ruling; `u8*`
buffers/sets):

| # | C signature (net_runtime.c line) | op | builtin map | platform |
|---|---|---|---|---|
| 1 | `int plat_socket_init(void)` (:18) | init/WSAStartup | — (lifecycle, not in 11) | Win-only body, POSIX returns 0 |
| 2 | `void plat_socket_cleanup(void)` (:27) | cleanup | — (lifecycle) | Win-only, POSIX no-op |
| 3 | `int plat_create_tcp_server(unsigned short port)` (:33) | socket+bind (+SO_REUSEADDR) | socketCreate | both; SO_REUSEADDR POSIX-only |
| 4 | `int plat_bind_listen(int sock, int backlog)` (:72) | listen | socketBindListen | both |
| 5 | `int plat_accept(int server_sock)` (:82) | accept | socketAccept | both |
| 6 | `int plat_recv(int sock, u8* buf, int len)` (:92) | recv | socketRecv | both |
| 7 | `int plat_send(int sock, const u8* buf, int len)` (:100) | send | socketSend | both |
| 8 | `void plat_close_socket(int sock)` (:108) | close | socketClose | both (closesocket/close) |
| 9 | `int plat_socket_select(int nfds, u8* readfds, u8* writefds, u8* exceptfds, int timeout_ms)` (:116) | select | socketSelect | both, identical |
| 10 | `void plat_socket_fd_zero(u8* set)` (:131) | FD_ZERO | socketFdZero | both, identical |
| 11 | `void plat_socket_fd_set(int fd, u8* set)` (:139) | FD_SET | socketFdSet | both (SOCKET cast Win) |
| 12 | `int plat_socket_fd_isset(int fd, u8* set)` (:147) | FD_ISSET | socketFdIsset | both (SOCKET cast Win) |

**`#ifdef`/`#pragma` emission pattern** — the exact pattern the builtins must reproduce:
- **Include block (:4-16):** `#ifdef _WIN32` → `windows.h` + `winsock.h` (Winsock **1.1** —
  note: `wsock32.lib`, **not** `ws2_32`) + `#pragma comment(lib, "wsock32.lib")`; `#else` →
  `sys/socket.h`, `netinet/in.h`, `arpa/inet.h`, `sys/select.h`, `unistd.h`, `fcntl.h`.
- **Per-function `#ifdef _WIN32`…`#else`…`#endif` in all 12 bodies** (not block-level).
- **msvc6:** `#pragma comment(lib, "wsock32.lib")` auto-links wsock32 (net_runtime.c:8).
- **OpenWatcom:** NO `__WATCOMC__` branch exists; OW defines `_WIN32` on Windows targets so it
  takes the Win path, but `#pragma comment(lib,…)` is MSVC-only → OW must add `library
  wsock32.lib` to `wlink` manually (mud_server README). Same for MinGW (`-lwsock32`).
- **POSIX:** `#else` branch only; `#pragma comment` excluded.
- `htons`/`htonl` used **inline** inside `plat_create_tcp_server` — no standalone wrap (no
  htons builtin candidate in this file).
- **Blocking model:** all sockets default-blocking; no `O_NONBLOCK`/`FIONBIO` anywhere.
  `select()` + `timeout_ms` (>=0 wait, <0 = infinite via NULL `timeval*`) is the only
  polling primitive. `recv`/`send` are raw returns (byte count, 0=EOF, -1=error); no
  `errno`/`WSAGetLastError` translation — builtins should preserve this raw i32 contract.

**F6 IMPLEMENTED (2026-08-13):** the 11 networking builtins now PORT the 12 plat_* bodies
inline in the emitter (net_runtime.c is superseded for migrated programs — linked WITHOUT for
mud_server/rogue_mud/net_builtin_test). Details:

- **LirInst variants:** `builtin_socket_create/bind_listen/accept/connect/send/recv/select/fd_zero/fd_set/fd_isset/close` (lir.zig:89-99). Lowering + sema follow the console-builtin pattern (name_id interning, `node.child_0` dispatch in lower.zig:2949-3046 / semantic_analyzer.zig:1441-1489). **[F3 line-ref pass 2026-08-13: lower/sema socket dispatch ranges corrected.]**
- **`emitBuiltinIncludes`** gains a net-gated include block (`moduleHasNetBuiltin`, c89_emit.zig:2074-2098): `#ifdef _WIN32` → `windows.h` + `winsock.h` (Winsock 1.1, `wsock32.lib` pragma) + `#else` → `sys/socket.h`, `netinet/in.h`, `arpa/inet.h`, `sys/select.h`, `unistd.h`, `fcntl.h`, plus `#include <string.h>` — mirrors net_runtime.c:4-16.
- **Per-builtin bodies** (c89_emit.zig:3402-3667 helpers `emitSocketWrite`/`emitSocketOptPtrValue`/`emitSocketCreate`/`emitSocketSelect`/`emitSocketClose`; dispatch arms :5182-5214) — each emits the exact `#ifdef _WIN32 … #else … #endif` body ported from net_runtime.c:18-153 (fd = plain `int`/i32; `SOCKET` casts only in the Win branch):
  - `emitSocketCreate` ← `plat_create_tcp_server` (socket+SO_REUSEADDR+bind, INADDR_ANY; Win `(int)s`/`closesocket` on fail, POSIX `close` on fail); init/cleanup stay as std_net.zig no-ops (WSAStartup/WSACleanup NOT auto-emitted — documented Win-only lifecycle caveat).
  - `emitSocketBindListen` ← `plat_bind_listen` (`r = (listen(...) == SOCKET_ERROR) ? -1 : 0` Win / `< 0` POSIX).
  - `emitSocketAccept` ← `plat_accept` (Win: INVALID_SOCKET→-1 else `(int)client`; POSIX raw return).
  - `emitSocketConnect` ← NEW (no source existed; per operator ruling): `connect()` against `sockaddr_in` INADDR_ANY, `== SOCKET_ERROR`/`< 0` → `-1 : 0`.
  - `emitSocketSendRecv` ← `plat_send`/`plat_recv` (`send`/`recv` with `(const char*)`/`(char*)` casts, `0` flags; raw return).
  - `emitSocketSelect` ← `plat_socket_select` (timeval from `timeout_ms`; `(fd_set*)` casts; `emitSocketOptPtrValue` emits `(NAME.has_value ? NAME.value : NULL)` for optional-typed temps — null-coalesce mirroring `.unwrap_optional_abi`, so a null arg (has_value=0) never reads the uninitialized `.value` field; plain `NAME` otherwise). [updated: 2026-08-13]
  - `emitSocketFdZero/FdSet/FdIsset` ← the FD_* macro wrappers (Win `(SOCKET)` cast on fd).
  - `emitSocketClose` ← `plat_close_socket` (`closesocket`/`close`).
- **Consumers:** `sf/src/std_net.zig` (zero `extern "c"`; 13 wrappers incl. `init`/`cleanup`) + migrated `examples/z98/mud_server/main.zig` + `examples/z98/rogue_mud/{lib/net.zig,ui.zig,main.zig}` (local `std_net.zig` copies; `net_runtime.c` link REMOVED). Gate: `repro/mi_matrix/net_builtin_test` dump→gcc→run rc=0 prints `1`; mud_server `timeout`-gated socket interaction rc=0; rogue_mud dump/gcc/link rc=0 (0 `plat_*` refs); 4 MD5 gates gol/lisp/json byte-identical, mud re-baselined to `fd0fdaa4…`.
