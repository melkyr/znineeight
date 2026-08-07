# 08 — C89 Emission [updated: 2026-08-07 — null_src null construction skips the dead `null_const` temp (Option B); prior null-payload temp typed `"int"` (null_type fallback); prior 2026-08-06 — va_* emission + `stdarg.h` gating + extern variadic prototypes + `@intCast` range-check helper; stale c89_emit.zig line ref corrected (emitTaggedUnionType :1348)]

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

Emission follows a strict 2-phase ordering per module, enforced in `emitModule` (`c89_emit.zig:2072`):

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

`mangleTempName` (`c89_emit.zig:1667`): Format `zT_<temp_id>`. Used for hoisted temporaries in function bodies. No collision check needed — temp_ids are unique per function.

#### Local Name Mangling

`mangleLocalName` (`c89_emit.zig:1436`): If the name_id is a C89 keyword, prefix with `z_`. Otherwise return original name. Used for function parameters and local variables.

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

`emitSpecialTypes` (`c89_emit.zig:1182`) drives type header output for the stdout single-file
path. For the multi-module path (`--output-dir`), the shared-header writer
`emitSharedHeader` (`c89_emit.zig:1086`) performs the equivalent partition into
`zig_special_types.h` (see §1.17):

```
emitSpecialTypes(emitter, reg):
  1. sorted = tstTopologicalSort(reg)           ← Kahn order
  2. fwd_decl pass: for each struct/tagged_union/union with name_id:
       emit "typedef struct <cname> <cname>;\n"
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

`emitTypeDefinition` (`c89_emit.zig:1195`) dispatches by `TypeKind`:

| TypeKind | Emitter Function | Output |
|----------|-----------------|--------|
| `slice_type` | `emitSliceType` (1736) | `typedef struct { <elem>* ptr; unsigned int len; } Slice_<elem>;` |
| `optional_type` | `emitOptionalType` (1768) | `typedef struct { <type> value; int has_value; } Opt_<payload>;` (void payload: omit value). Null-payload temps for this type are emitted as `Opt_` (set_optional_null writes `has_value = 0;`) — see §1.4 [updated: 2026-08-07] |
| `error_union_type` | `emitErrorUnionType` (1812) | `typedef struct { union { <type> payload; int err; } data; int is_error; } EU_<payload>;` |
| `error_set_type` | `emitErrorSetType` (1633) | `typedef int <cname>;` + `#define <cname>_<tag> <N>` per tag |
| `tagged_union_type` | `emitTaggedUnionType` (1348) | Complex struct + union + tag constants |
| `enum_type` | `emitEnumType` (1688) | `typedef <backing> <cname>;` + `#define <cname>_<member> <val>` per member |
| `struct_type` | `emitStructType` (1481) | `struct <cname> { <type> <field>; ... };` |
| `union_type` | `emitStructType` (1481) | Same struct format |
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

#### emitFunctionSignature (`c89_emit.zig:1452`)

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
  extern-prototype guards (`emitModuleHeader` at `c89_emit.zig:1996` and the
  `:2143`-era twin) are `is_extern==0 OR is_variadic!=0`, so a variadic `extern
  fn printf(fmt, ...)` emits its C prototype (`int printf(unsigned char*, ...);`,
  name-passthrough) while non-variadic externs still rely on `@cInclude`'d
  headers.

#### emitHoistedDecls (`c89_emit.zig:1684`)

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
arm, c89_emit.zig:2857), **every function** also gets a `z_bb_0:` label for its entry block,
emitted after the hoisted temp decls and local decls and before the first entry-block statement:

```
ret_zF_fn(params) {
    <hoisted temp decls zT_N;>      (emitHoistedDecls)
    <local decls name;>             (emitFunctionBody decl_local hoist)
    z_bb_0:                         ← .loop_header arm (c89_emit.zig:2857)
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

Every `LirInst` variant handled in `emitInst` (`c89_emit.zig:2272`):

| LirInst | C89 Output | Line |
|---------|-----------|------|
| `.nop` | (nothing) | 2275 |
| `.ret_void` | `return;` | 2276 |
| `.loop_header` | `z_bb_0:` (entry-block label — TCO self-recursion jump target; since F-S3 emits `z_bb_0:\n`, NOT `tco_restart:`) | 2857 |
| `.label` | (nothing — waits for block label) | 2282 |
| `.decl_local` | Emitted by hoisting pass in emitFunctionBody | 2283 |
| `.assign` | `dst = src;` (array: `{ unsigned int _i=0; while(_i<N) { dst[_i]=src[_i]; _i++; } }`) | 2284 |
| `.assign_field` | `base.field = src;` (struct/union/ptr/slice/tagged_union) | 2358 |
| `.assign_index` | `base[idx] = src;` or `(*base)[idx] = src;` | 2370 |
| `.jump` | `goto z_bb_<id>;` | 2384 |
| `.branch` | `if (cond) goto z_bb_<then>; else goto z_bb_<else>;` | 2398 |
| `.ret` | `return val;` | 2423 |
| `.load_local` | `result = name;` (array: `{ ... for-loop copy ... }`) | 2432 |
| `.store_local` | `name = val;` (`_` → `(void)val;`) | 2481 |
| `.load_global` | `result = name;` | 3094 |
| `.store_global` | `name = val;` | 3140 |
| `.load_field` | `result = base.field;` (slice → `.ptr`/`.len`; tagged_union → `.tag`/`.payload`; ptr → `->field`; struct → `.field`) | 2533 |
| `.store_field` | `base.field = val;` (same field resolution as load_field) | 2654 |
| `.load_index` | `result = base[idx];` or `result = (*base)[idx];` | 2764 |
| `.load` | `result = *ptr;` | 2768 |
| `.store` | `*ptr = val;` | 2780 |
| `.addr_of` | `result = &operand;` | 2793 |
| `.binary` | `result = lhs op rhs;` (op: `+` `-` `*` `/` `%` `&` `\|` `^` `<<` `>>` `==` `!=` `<` `<=` `>` `>=`) | 2804 |
| `.unary` | `result = op operand;` (op: `-` `!` `~`) | 2841 |
| `.int_const` | `result = <value>;` (signed: cast + neg magnitude to avoid warnings; tagged_union: `.tag = <value>;`) | 2854 |
| `.enum_const` | `result = <type>_<member>;` | 2928 |
| `.float_const` | `result = <d.ddd>;` (via `formatF64`) | 2945 |
| `.string_const` | `result = "<escaped>";` (escape: `\n`, `\t`, `\r`, `\\`, `\"`) | 2962 |
| `.null_const` | `result = NULL;` (optional type → `result.has_value = 0;`) | 3900 — note: null_src null construction (return/catch null → optional) no longer emits `.null_const`; the lowerer emits `.set_optional_null` directly (Option B, 2026-08-07) |
| `.set_optional_null` | `result.has_value = 0;` | 3914 |
| `.bool_const` | `result = 1;` or `result = 0;` | 3017 |
| `.undefined_const` | `result = 0;` (arrays: `{ ... for-loop zero ... }`; tagged union arrays: `[_i].tag = 0;`; nested struct arrays: recursive loop) | 3029 |
| `.call` | `result = callee(args...);` (indirect call through function pointer) | 3103 |
| `.call_direct` | `result = fn_name(args...);` (extern return wrapping for optional/error_union) | 3129 |
| `.tail_call` | `result = fn_name(args...); return result;` — call+ret **fallback**, NOT a jump (cross-function TCO is semantic only until an asm backend); void return → `fn_name(args...); return;`; extern override (AMENDMENT 6) → original name; indirect callee via `resolveTempName` | 3954 |
| `.switch_br` | `switch (cond) { case <val>: goto z_bb_<target>; ... default: goto z_bb_<else>; }` | 3262 |
| `.wrap_optional` | `result.has_value = 1;\n result.value = src;` | 4256 |
| `.int_cast` | `result = (type)src;` (checked: `result = __bootstrap_<DST>_from_<SRC>(src);`) | 4214 |
| `.int_to_float` | `result = (type)src;` | 3366 |
| `.float_cast` | `result = (type)src;` | 3381 |
| `.make_slice` | `result.ptr = ptr;\n result.len = len;` | 3396 |
| `.print_str` | `std_print("literal");` | 3415 |
| `.print_val` | `std_print_<type>(val);` (slice → `std_print_str(val.ptr, val.len)`) | 3424 |
| `.ptr_cast` | `result = (type)src;` | 3444 |
| `.check_error` | `result = src.is_error;` | 3459 |
| `.unwrap_error_payload` | `result = src.data.payload;` | 3470 |
| `.unwrap_error_code` | `result = src.data.err;` (void-payload → `src.err;`) | 3496 |
| `.wrap_error_ok` | `result.data.payload = src;\n result.is_error = 0;` (void-payload → `result.err = 0;\n result.is_error = 0;`) | 3525 |
| `.wrap_error_err` | `result.data.err = src;\n result.is_error = 1;` (void-payload → same pattern, `.err`) | 3554 |
| `.check_optional` | `result = src.has_value;` | 3586 |
| `.unwrap_optional` | `result = src.value;` (void-payload → nothing) | 3599 |
| `.unwrap_optional_abi` | `result = src.has_value ? src.value : NULL;` | 3625 |
| `.int_to_ptr` | `result = (type)(unsigned int)src;` | 3639 |
| `.ptr_to_int` | `result = (usize)src;` | 3654 |
| `.func_ref` | `result = fn_name;` (function pointer) | 3669 |
| `.va_start` | `va_start(vl, last_param);` | 4589 |
| `.va_arg` | `res = va_arg(vl, TYPE);` (TYPE = `getCTypeName(type_id)`) | 4602 |
| `.va_end` | `va_end(vl);` | 4617 |

Any unhandled variant falls through the `else => {}` at line 3681 (no-op).

**`@intCast` range-check emission (F1, 2026-08-06):** the `.int_cast` checked arm
(`c89_emit.zig:4214-4260`) builds `__bootstrap_<DST>_from_<SRC>` from the target's
`getCastTypeSuffix` and the source temp's `getTempTypeByIndex`, falling back to a
raw `(type)` cast when the source type is unknown. The 19 helpers are `static` in
`sf/src/include/zig_runtime.h` (per-TU, oracle pattern) + `extern` in
`sf/src/include/zig_runtime.c`; the message is `"integer cast overflow in
@intCast"` and the unchecked `(type)` path is unchanged. **`stdarg.h` gating
(F5, 2026-08-06):** `emitStdargInclude` (`c89_emit.zig:1959`) emits `#include
<stdarg.h>` only when `moduleHasVaInsts` (`:1938`) finds a `va_start`/`va_arg`/
`va_end` LirInst in the TU — gated on actual `va_*` usage (not `is_variadic`), so
mud/gol's anytype-print (`is_variadic=1`, no `va_*`) stays byte-identical. The
include is emitted at all 3 sites (`emitModuleHeader` `:1972`,
`emitModuleHeaderFile`, `emitModuleFile`).

**C89 cross-function TCO limitation — [updated: 2026-08-03]:** `.tail_call` (c89_emit.zig:3954) is
emitted as a **call followed by a `return`** (`zT = fn(args); return zT;`), i.e. it preserves a C
stack frame — it is semantically a tail call but not a jump. Only **self-recursion** TCO achieves
O(1) stack (rebind assigns + `goto z_bb_0;` back-edge to the entry label). Real frame-reusing
cross-function tail calls (jump to the callee without a new frame) require a backend that can emit a
proper tail-jump; until such an asm backend exists, cross-function TCO is call+ret. The `.tail_call`
written-type-scan case (`c89_emit.zig:2376`) marks the result temp as a call-result (written_flag=2)
so it is not flagged UNWRITTEN by the decl pass.

### 1.10 emitModule — Top-Level Orchestration

`emitModule` (`c89_emit.zig:2072`) drives one module's output for the **stdout single-file
path only** (bare `--dump-c89`). [updated: 2026-08-01] When `--dump-c89 --output-dir DIR` is
set, `phase_C89Emission` instead emits `zig_special_types.h` once via `emitSharedHeader` and
loops modules emitting per-module `.h`/`.c` via `emitModuleHeaderFile`/`emitModuleFile`
(see §1.17); `emitModule` is unchanged for the stdout path. Note that `phase_C89Emission`
(`main.zig:610`) runs BEFORE it: it creates a separate `BufferedWriter` (`cwriter`), emits the
fixed `emitIncludes` preamble (`#include "zig_compat.h"` + `#include "zig_runtime.h"`,
`c89_emit.zig:722-727`), flushes it (`main.zig:723-726`), then calls `emitModule` with the
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

#### emitModuleHeader (`c89_emit.zig:1558`)

```
/* Module: <name> */
#include "zig_compat.h"
#include "zig_special_types.h"
<c-includes...>

/* Forward declarations */
<func-forward-decls...>
```

C-includes: if starts with `<`, emit raw (`#include <foo.h>`). Otherwise wrap in quotes (`#include "foo.h"`).

### 1.11 emitModuleFooter (`c89_emit.zig:1595`)

```
/* EOF */
```

### 1.12 emitFunctionForwardDecl (`c89_emit.zig:1518`)

Emits `return-type fn-name(param-types...);` — same mangling as signature but without param names.

### 1.13 emitBaseIdxAccess (`c89_emit.zig:144`)

Handles indexed load/store with ptr-to-array detection:

- Ptr-to-array: `result = (*base)[idx];` or `(*base)[idx] = src;`
- Normal: `result = base[idx];` or `base[idx] = src;`

`isBasePtrToArray` (`c89_emit.zig:130`) checks if a temp's type is ptr-to-array.

### 1.14 emitFieldAssign (`c89_emit.zig:181`)

Resolves field access for `.assign_field`:

| Base Type | Access Pattern |
|-----------|---------------|
| `slice_type` | `.ptr` (field 0), `.len` (field 1), `.f_<N>` (N>1) |
| `tagged_union_type` | `.tag` (field 0), `.payload.<variant-name>._<sub>` or `.payload` (field 1) |
| `ptr_type`/`many_ptr_type` → `struct_type` | `->field` |
| `struct_type` | `.field` (with array copy: `{ ... while(_j < len) { base.field[_j] = src[_j]; _j++; } }`) |
| unknown | `.f_<field_id>` (numeric fallback) |

### 1.15 Helper Functions

| Function | Line | Purpose |
|----------|------|---------|
| `getBinOpStr` | 2189 | Maps binary op u8 → C operator string (+, -, *, /, %, &, \|, ^, <<, >>, ==, !=, <, <=, >, >=) |
| `getUnOpStr` | 2209 | Maps unary op u8 → C operator string (-, !, ~) |
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

With `--dump-c89 --output-dir DIR`, `phase_C89Emission` (`main.zig:610`) switches from the single
stdout stream to **per-module file emission**. Output set: `DIR/<qualified>.c` (one per module) +
`DIR/<qualified>.h` (one per module) + `DIR/zig_special_types.h`. Bare `--dump-c89` (no
`--output-dir`) keeps the stdout single-file path (§1.10) byte-identical — the two paths are
branched on the CLI, never mixed.

- **Qualified filename scheme (F-S7)** — output stems come from `moduleQualifiedName`
  (`c89_emit.zig:1926`): `DIR/<basename clamped 64>_<FNV1a8>.c/.h`, where `<basename>` is the
  module path's last `/` component with `.zig`/`.z98` stripped (clamped to 64 chars) and
  `<FNV1a8>` is the 8-uppercase-hex FNV-1a hash of the **full module path**
  (`hash_mod.fnv1a` + `writeHex`, the same pair the mangler uses). **NO module_id** in the
  filename. This eliminates the F-S7 basename-collision bug (two same-named files in different
  dirs silently overwrote each other in `DIR/`); every filename is unique per path, so a module
  importing two same-basename deps now gets two distinct `.h` files and two distinct `#include`
  lines (previously the same `#include "util.h"` was emitted twice).
- **Length guard (F-S7)** — `main.zig:665` checks `od.len + 1 + base.len + 3 > 511` before
  constructing each path; if exceeded, `error: output filename too long` + `pal.exit(1)`. This
  replaces the old silent truncation at `main.zig:685`/`:712` (bytes were dropped past 510/511
  with no diagnostic, and the truncated filename mismatched the include chain).
- **Shared header** — `emitSharedHeader` (`c89_emit.zig:1086`): calls `computeSharedSet`
  (`c89_emit.zig:1025`), then emits `zig_special_types.h` with file guard `ZIG_SPECIAL_TYPES_H`,
  preamble `#include "zig_compat.h"` + `#include "zig_runtime.h"`, an unfiltered fwd-decl pass
  (`typedef struct X X;` for every named struct/tagged_union/union), sub-pass 2a restricted to
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
  `ctypeGuardWrite` (`c89_emit.zig:951`): `ZIG_STRUCT_`, `ZIG_UNION_`, `ZIG_ENUM_`,
  `ZIG_ERROR_SET_`, `ZIG_SLICE_`, `ZIG_OPTIONAL_`, `ZIG_ERRORUNION_`, `ZIG_ARRAY_`,
  `ZIG_FNPTR_`, `ZIG_I64_`, `ZIG_U64_`, fallback `ZIG_TYPE_`.
- **Per-module `.h`** — `emitModuleHeaderFile` (`c89_emit.zig:1969`): module guard
  `ZIG_MODULE_<UPPER(qualified)>_H` (the **qualified** stem uppercased, non-alnum → `_`; since
  F-S7 the stem already embeds the unique path hash, so guards auto-unique even for two
  same-basename modules — e.g. `ZIG_MODULE_UTIL_7F9D0FD1_H`); includes `zig_compat.h`
  + `zig_special_types.h`; the module's own `@cInclude` directives (`entry.c_includes`,
  per-module — NOT the global `cincludeUnionAll` union); each direct-import dep's `.h` by its
  **qualified** name (`#include "<moduleQualifiedName(emitter,d)>.h"`, skipping self —
  `c89_emit.zig:1983`); owned CLS:p
  type full-definitions (name_id≠0, `module_id==M.id`, struct/TU/union/enum/error_set,
  `pointer_only_map`, not in `shared_set` — each guarded); fn fwd-decls (non-extern).
- **Per-module `.c`** — `emitModuleFile` (`c89_emit.zig:2193`): `#include "<qualified>.h"`, then the
  module's own fn bodies (externs skipped; `switch_cases`/`dl_hoisted` reset per fn). The
  `int main(void)` wrapper is emitted only for `module_id==0`'s public `main`
  (`emitMainWrapper`, `c89_emit.zig:2107`).
- **Embedded build-script templates are DEAD CODE** — `emitBuildTargetSh` (`c89_emit.zig:4482`) /
  `emitBuildTargetBat` (`c89_emit.zig:4495`) / `emitBuildTargetOwcBat` are never called by any
  pipeline path (explicit `// Reference-only:` comment at `c89_emit.zig:4478`). They exist as
  frozen templates only; the real multi-module build flow is the glob-based gcc recipe in
  QUICK_REF/NOTES.md.

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
emitModule(c89_emit.zig:2072)
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

`cincludeUnionAll` (`cinclude.zig:7-26`, called at `main.zig:728`) dedups by interned name_id
across ALL modules; `emitModuleHeader` emits `zig_compat.h` + `zig_special_types.h` then the
deduped list (`[source]` `c89_emit.zig:1562-1581`). `<...>` form emitted raw, `"..."` quoted
(`:1570-1578`).

| Example | @cInclude directives (by module) | Emitted module-header includes | Dedup |
|---------|----------------------------------|-------------------------------|-------|
| mud_server | main.zig:4 zig_runtime.h, :5 net_runtime.h; std_debug.zig:1 zig_runtime.h (dup) | `zig_runtime.h` + `net_runtime.h` (mud_server.c:47-48) | **exercised** — 3 directives → 2 lines |
| game_of_life | main.zig:3 zig_runtime.h, :4 `<stdlib.h>`; std_debug.zig:1 zig_runtime.h (dup) | `zig_runtime.h` + `<stdlib.h>` (gol.c:30-31) | **exercised** |
| json_parser | main.zig:4-6 zig_runtime.h, `<stdio.h>`, `<stdlib.h>`; file.zig:1-2 `<stdio.h>`, `<stdlib.h>` (dups) | `zig_runtime.h` + `<stdio.h>` + `<stdlib.h>` (json.c:64-66) | **exercised** — 5 directives → 3 lines |
| lisp_interpreter_curr | main.zig:11-12 zig_runtime.h, `<stdio.h>` | `zig_runtime.h` + `<stdio.h>` (lisp:100-101) | no dups |

**Observation**: `zig_compat.h` and `zig_runtime.h` appear TWICE in every output — once in the
fixed `emitIncludes` preamble (`c89_emit.zig:722-727`, flushed from `main.zig:723-726`) and
once in the module header (`[c89]` mud_server.c:1-2 vs :45-48). Dedup applies only WITHIN the
collected `@cInclude` list, not against the preamble — benign (include guards), undocumented
elsewhere.

### 6.4 Function Body Emission Order (Q4)

Emission iterates `fns` in list order, skipping externs (`[source]` `c89_emit.zig:1607-1611`).
The list is built in module-registration order × source decl order (`[source]` `main.zig:513-608`:
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

Marker sequence `[markers]`: `C` (main.zig:611) → `FL:p49`/`FE:p0` (preamble flush, main.zig:726)
→ `E2A:`/`E2B:` type passes → fwd-decl/fn-body markers → `FINAL_FLUSH` (main.zig:730; exactly 1
per trace). The preamble is a SEPARATE `BufferedWriter` (`cwriter`, main.zig:723-726) flushed
before `emitModule`; the module name is hardcoded `"output"` (main.zig:627) — hence
`/* Module: output */` in every file.

### 6.6 extern "c" Functions (Q6, mud_server)

extern "c" socket functions are emitted as **bare, unmangled C calls with NO declarations in
the output** (grep `extern` → 0 hits in mud_server.c `[c89]`). Prototypes come from the
`@cInclude`d `net_runtime.h` (net_runtime.h:6-17). Examples: `zT_0 = plat_socket_init();`
(mud_server.c:553), `zT_8 = plat_create_tcp_server(zT_6);` (:567),
`zT_97 = plat_accept(zT_96);` (:798), `zT_159 = plat_socket_fd_isset(zT_153, zT_154);` (:954),
`plat_close_socket(zT_145);` (:926).

Mechanism `[source]`: signature uses original name if `is_extern` (`c89_emit.zig:1462`); externs
get no fwd decl (`:1587`) and no body (`:1611`); call sites use the original name
(`:3142`). Discarded extern results: `_ = plat_send(...)` → `zT_126 = plat_send(...);
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
