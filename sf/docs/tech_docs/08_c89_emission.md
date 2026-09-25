# 08 — C89 Emission [updated: 2026-09-25 — Task 4 (z98-print-formatting): `.print_val` on struct/union/tagged-union/packed-union/tuple calls a compiler-generated per-type static printer (`z98_printStruct_<tid>`, ...) that emits Zig 0.15.2's `. { .a = 1 }` / `.{ 1, 2, 3 }` form with `std.fmt.default_max_depth = 3`; tuple types gain a `Tup_<tid>` C model (`typedef struct { _0, _1, ... }`), emitted only for `needed_tuple_set` (runtime hoisted temps/globals) so registry-only print-args tuples keep the 4-MD5 dumps byte-identical. See §1.18.] [updated: 2026-09-25 — Task 2 (z98-print-formatting): `printFnSourceName` is a width/signedness dispatcher (`printKindIsIntegerLike` + `typeRegistryIntWidthBits`/`IsSigned`; ≤32 → U32/I32, 33..64 → U64/I64, `{x}` → the matching `printHex*`; Z98 `usize` is 32-bit unsigned; `integer_literal` is the 32-bit signed fallback) and `std.fmt`'s `printHexI32/I64` print `-` + hex magnitude for negative values; `pal_f64_to_str` omits the `.`+fraction for an integral float. Fixture `stdlib_print_dispatch_xmod`.][updated: 2026-09-24 — Task 1 (z98-print-formatting): `.print_val` emits a mangled cross-module call into the Z98 std module `sf/src/std_fmt.zig` (`std.fmt`); `printFnSourceName` picks the std.fmt source name and `getPrintFnName` mangles it against the auto-imported std_fmt module id (new `C89Emitter.std_fmt_module_id`, set in `phase_C89Emission`; a `.print_val` also seeds a `ref_edges` entry so std_fmt stays reachable and its header is included). The C `std_print_<type>` bodies are retired; `std_print`/`std_print_len` remain the raw-bytes helpers for `.print_str`/console. `.print_str` is unchanged.] [updated: 2026-09-22 — `getPrintFnName` gained an `f32_type` arm routing `f32` to the existing `std_print_f64` (Task 7F f32 print dispatch; the prototype widens `float`→`double`, no runtime change)] [updated: 2026-09-20 — refreshed against current source: added `emit_support.zig` (self-contained output dir + companion build scripts), packed/int-width/`volatile`/calling-convention and `-fsafe`/`-ffast` guard emission, emission-core compaction, and module pruning; documented the removed `@socket*` builtin emission; dropped line references and the 4-example evidence appendix]

> Covers: `c89_emit.zig`, `name_mangler.zig`, `cinclude.zig`, `emit_support.zig`
> Cross-ref: [INDEX.md](INDEX.md) §E (NameMangler, BufferedWriter data structures)

## Summary

| Key | Value |
|-----|-------|
| Input | spill-backed function-slot list (`LirFunction`s per module), `TypeRegistry`, `ModuleRegistry` |
| Output | C89 `.c` via stdout (`--dump-c89`), or a self-contained multi-module tree + companion build scripts (`-o DIR` / `--output-dir`) |
| Phase marker | `C` (entry), `FINAL_FLUSH` (complete) |
| Key structs | `C89Emitter`, `BufferedWriter`, `NameMangler` |
| Key functions | `emitModule`, `emitSpecialTypes`, `emitFunctionBody`, `emitInst`, `nameManglerMangle`, `cincludeUnionAll`, `emitSupportFiles`, `emitBuildScripts` |

---

## 1. `c89_emit.zig` — C89 Emitter (9231 lines)


### 1.1 2-Phase Output Architecture

Emission follows a strict 2-phase ordering per module, enforced in `emitModule`:

```
Phase 1: Type Headers (emitSpecialTypes)
  ├─ Sub-pass 1: Forward declarations for struct/union/tagged_union types
  │   (typedef struct Foo Foo; — packed structs/unions skipped)
  ├─ Sub-pass 2a: Pointer-only types (fields all through ptr/slice/wrapper)
  │   (emitTypeDefinition — only if in pointer_only_map)
  └─ Sub-pass 2b: Value-embedding types (structs with inline fields)
      (emitTypeDefinition — only if NOT in pointer_only_map)

Phase 2: Function Bodies (emitModuleHeader → emitFunctionSignature → emitFunctionBody)
  ├─ Module header: includes, forward declarations
  ├─ Per function: signature + hoisted decls + basic blocks
  └─ main() wrapper for non-void return types
```

Phase 1 runs once via `emitSpecialTypes` BEFORE any function body. Phase 2 iterates the
spill-backed function-slot list.

#### Type Topological Sort

Types are emitted in dependency order using Kahn's algorithm (`tstTopologicalSort`):

```
Input: TypeRegistry (all types 0..types_len-1)
1. Compute indegree for each type — count of C89-relevant field/child types
   (struct/tagged_union/union/array/optional/error_union that reference another type)
2. Enqueue all types with indegree 0
3. Dequeue → add to result → decrement indegree of dependents → enqueue new 0s
4. Result order: types with no deps first, then their dependents
```

`c89NeedsEmitEdge` determines which `TypeKind` forms an edge: slice, struct, union, tagged_union,
array, optional, error_union, **enum, error_set**, tuple, unresolved_name. `enum_type`/
`error_set_type` are embeddable by value (inline integer typedef aliases), so a target enum/
error_set **must** have an emit edge or the fixpoint (`computeSharedSet` §1.17) never promotes it
into `zig_special_types.h`, leaving shared struct bodies referencing an unknown `typedef`.
`tstIsDep`, `tstEdgesCount`, and `tstEdgesFill` all gate their source-kind branches on this
helper, so the enum/error_set target support flows through every source branch automatically; no
enum/error_set *source* branch is needed (backing_type/tags are plain integers).

`tstEdgesCount`/`tstEdgesFill` count each distinct dependent type ONCE per source (dedupe
same-typed field edges) via the `tstSeenInRange` helper: the struct/tagged_union/union field loops
and the tagged_union `tag_type` all skip a target type already seen in the fields scanned so far.
This makes the indegree exactly equal to the number of `tstIsDep`-true decrements in the Kahn
dequeue, so count and dequeue can never drift: a struct with two fields of the same edge-forming
type (e.g. two `Point` fields) previously got indegree 2 but only 1 dequeue decrement, was never
dequeued, and was silently dropped from `sorted` (no fwd-decl/body → gcc `unknown type name`).
`tstEdgesFill` has no callers — the dedupe there is mirrored for consistency, zero runtime effect.

#### Pointer-only vs Value-embedding Split

`emitModule` receives a `ptr_only_ids` array from the caller (calculated in `phase_C89Emission` in
`main.zig`). Types in this set have all their field dependencies reachable through pointers — only
a forward declaration is needed for C89 correctness. The split prevents redundant full type
definitions:

- **Sub-pass 2a:** Iterates types in topo order, skips if NOT in `pointer_only_map`. Emits full definition.
- **Sub-pass 2b:** Iterates types in topo order, skips if IS in `pointer_only_map`. Emits full definition.

Both sub-passes dedup via `emitter.emitted_type_set` (hash of C type name string) — same type only
emitted once.

### 1.2 BufferedWriter — 4KB Buffered Output

Fixed-size 4096-byte buffer with auto-flush. `BufferedWriter` carries a **file-descriptor sink**
(`fd: usize`) so the multi-module path can flush each `.h`/`.c`/`zig_special_types.h` to its own
open file. Stdout remains the default (`fd=1`), so the bare `--dump-c89` byte-identical gate is
preserved.

| Field | Type | Purpose |
|-------|------|---------|
| `buf` | `[4096]u8` | Output buffer — written sequentially, flushed to sink when full |
| `pos` | `usize` | Current write cursor (0 = empty, 4096 = full, triggers flush) |
| `fd` | `usize` | Output sink fd. `1` (stdout) by default; set per-file via `bufferedWriterInitFd`. `usize` — an all-ones `INVALID_FD` sentinel (`pal.zig`) replaces the `-1` open-fail test |

| Function | Purpose |
|----------|---------|
| `bufferedWriterInit` | Returns new BufferedWriter with `pos=0`, `buf=undefined`, `fd=1` (stdout) |
| `bufferedWriterInitFd` | Returns new BufferedWriter writing to the given fd (multi-module per-file sink) |
| `bufferedWriterFlush` | Writes `buf[0..pos]` to `self.fd` via `pal.fileWrite`, resets pos to 0 |
| `bufferedWriterWrite` | Writes byte slice to buffer. Loops: copies min(remaining, 4096-pos) bytes into buf, increments pos, flushes if full |
| `bufferedWriterWriteByte` | Single byte write, flush-if-full, store at pos, increment |
| `bufferedWriterWriteIndent` | Writes `level * 4` spaces (flush-safe, byte-by-byte) |

Markers `FL:p` (flush start, prints current pos) and `FE:p` (flush end, prints 0) bracket each flush.

### 1.3 NameMangler — Deterministic Name Mangling

Defined inline in `c89_emit.zig`. Separate from the minimal `name_mangler.zig` (which only has a
counter — that file is a different/unused impl).

| Field | Type | Purpose |
|-------|------|---------|
| `hash_seed` | `u32` | Currently always 0 |
| `cache` | `U64ToU32Map` | Multi-key: `(module_id << 35) \| (kind << 32) \| name_id` → mangled_id |
| `keyword_set` | `U32ToU32Map` | All 32 C89 keywords (auto..while), interned name_id → 1 |
| `collision_mod` | `U32ToU32Map` | Mangled name_id → module_id (detects collisions) |
| `collision_name` | `U32ToU32Map` | Mangled name_id → original name_id (maps collision back) |
| `interner` | `*StringInterner` | For interning mangled name strings |
| `exported` | `?*U64ToU32Map` | Optional set of `(module_id, kind, name_id)` keys whose symbol is `export`ed and must keep its **source name** (bypasses mangling) |

#### Mangling Scheme

`nameManglerMangle(name_id, kind, module_id)`:

```
Format: z<K>_<8-hex-digits>_<original-name>
        ↑  ↑         ↑
        |  kind      hash
        prefix       (FNV-1a of original name)
```

1. **Temp/builtin bypass** (`isTempOrBuiltin`): Names starting with `__tmp`, `__ret`, `__bootstrap` return unmangled.

2. **C89 keyword escape** (`isC89Keyword` → `mangleC89Keyword`): If the name matches a C89 keyword, prefix with `z_` and return. e.g., `int` → `z_int`.

3. **Export bypass:** if `exported` contains the key, return the original `name_id` (source name).

4. **Cache lookup:** Key = `(module_id << 35) | (kind << 32) | name_id`. If previously mangled, return cached.

5. **Mangle construction:**
   - `buf[0]` = `'z'` (prefix — avoids leading digit/underscore collision)
   - `buf[1]` = kind char: `F`=function(0), `G`=global(1), `T`=type(2), `L`=local(default)
   - `buf[2]` = `'_'`
   - `buf[3..11]` = 8 hex chars of FNV-1a hash
   - `buf[11]` = `'_'`
   - Followed by original name chars, truncated to fit 31 total

6. **31-char limit:** Total mangled name capped at 31 bytes (C89 standard minimum). Original name truncated if needed.

7. **Collision resolution:** If mangled name already used by a different `(module_id, name_id)`, append `_N` suffix with counter. Original name portion truncated further to stay within 31 chars. Digits counted dynamically before truncation.

8. **Cache population:** Store in `collision_mod`, `collision_name`, and `cache`.

`nameManglerMangleGlobal(registry, name_id, module_id, type_id)` is the module-global variant:
when the name is a type-storage global (the type's `name_id` equals the global's), identity is
the **stored type** (name + owning module), so every module aliasing the type agrees on one C
symbol; otherwise it falls back to per-module `nameManglerMangle`.

#### Temp Name Mangling

`mangleTempName`: Format `zT_<temp_id>`. Used for hoisted temporaries in function bodies. No
collision check needed — temp_ids are unique per function.

#### Local Name Mangling

`mangleLocalName`: If the name_id is a C89 keyword, prefix with `z_`. Otherwise return original
name. Used for function parameters and local variables.

#### D2 gap — typedef `_N` suffix not mirrored on fn-signature type refs — FIXED (F1)

The `_N` collision suffix (step 7 above) is applied **per mangled name**, keyed by
`(module_id, kind, name_id)`. When the same-named type is defined in two module instances, the
second instance's typedef legitimately mangles to `zT_<hash>_<Name>_1`, and the struct definition
is emitted from that type's own `module_id`.

The fn-signature/return-type references come from `lir_fn.return_type` / `param.type_id` via
`getCTypeName`. Before F1, a bare return type `Arena` resolved to **module 0**'s TypeId, so the fn
reference mangled to the unsuffixed `zT_<hash>_<Name>` while the typedef in the same header was
`zT_<hash>_<Name>_1` — gcc rejected the emitted C (`return type is an incomplete type`).
**FIXED (F1):** the root cause was fixed upstream in `type_resolver.zig` (bare `ident_expr` type
resolution is now module-scoped), so the fn reference mangles to the same `_N`-suffixed name as
the typedef and `arena_multi_inst_xmod` compiles + runs clean. No emitter change was needed; the
`_N` collision mechanism is correct.

### 1.4 C89Emitter — Central Emitter State

`C89Emitter` (initialized by `c89EmitterInit`) holds all emission context:

| Field | Type | Purpose |
|-------|------|---------|
| `writer` | `BufferedWriter` | 4KB output buffer |
| `indent` | `u32` | Current indentation level (incremented in fn bodies) |
| `alloc` | `*Sand` | Per-function scratch arena |
| `persist_alloc` | `*Sand` | Persistent arena (maps, growable tables) |
| `registry` | `*TypeRegistry` | Type system reference |
| `interner` | `*StringInterner` | String lookups |
| `mangler` | `*NameMangler` | Name mangling |
| `diag` | `*DiagnosticCollector` | Error reporting |
| `switch_cases` | `*SwitchCaseArrayList` | Current function's switch cases |
| `call_args` | `*U32ArrayList` | Temporary call argument buffer |
| `current_fn` | `*LirFunction` | Function currently being emitted |
| `spill` / `fn_slots` / `fn_slots_start` / `fn_slots_len` / `spill_arena` | `*LirStream` / `[*]LirSlot` / `usize` | Spill-backed function-slot window for the current module (`faultIn`) |
| `d4_wtype` | `[*]u32` | Type propagation tracking (hoisted temps) |
| `d4_wflag` | `[*]u8` | Written flag: 0=unwritten, 1=resolved, 2=call-result, 3=suppressed |
| `d4_t2p` | `[*]u32` | Temp ID → hoisted_temps index mapping |
| `d4_dead` / `d4_local` / `d4_nodecl` / `d4_lread` | `[*]u8` | DCE / local-mapped / no-decl / load-read suppression flags |
| `d4_max_temp` | `u32` | Max temp id + 1 for the current function |
| `bb_used` / `bb_used_count` | `[*]u8` / `u32` | Referenced-block labels (unused labels pruned) |
| `dl_hoisted` | `u8` | Whether decl_local hoisting has run (guard against double-emit) |
| `nest_ok` / `nest_max` / `nest_inl` | `u8` / `u32` / `[*]u8` | Expression-nesting state: temps inlined into their consumer (def/decl suppressed) |
| `emitted_type_set` | `U32ToU32Map` | Dedup: type name hash → emitted marker |
| `fwd_decl_set` | `U32ToU32Map` | Dedup: forward decl name hash → emitted marker |
| `pointer_only_map` | `U32ToU32Map` | Type ids that need only forward decl |
| `shared_set` | `U32ToU32Map` | Type ids emitted into the shared `zig_special_types.h` — synthetics ∪ CLS:v ∪ i64/u64 ∪ named fn_type, plus the CLS:p closure (see `computeSharedSet`). A type joins when it is referenced **by value OR in a way that requires the C type name in scope** — typedef'd kinds (enum/error_set) need the name in scope even through a pointer/slice |
| `module_reg` | `*ModuleRegistry` | Module registry (qualified names, pruning) |
| `reachable` | `U32ToU32Map` | Value-reference reachability set (module pruning) |
| `prune_active` | `u8` | Whether module pruning is active (multi-module path) |
| `error_code_registry` | `*U32ToU32Map` | Error-tag name_id → dense error code |
| `dedup_names` / `dedup_cap` / `dedup_count` | `[*]u32` / `u32` | Local variable dedup during hoisting (grown on demand) |
| `fl_name_ids` / `fl_temps` / `fl_count` | `[*]u32` / `u32` | Flat lookup: local name_id ↔ temp_id |
| `temp_global_map` | `U32ToU32Map` | Temp → global alias mapping |
| `ts_ref_set` | `U32ToU32Map` | Type-storage global reference set |
| `global_decls` / `global_decls_len` | `[*]ModuleGlobalDecl` / `u32` | Module global declarations |
| `needed_tuple_set` | `U32ToU32Map` | Task 4: tuple type ids that hold a runtime value (hoisted temp / global); only these get a C typedef (registry-only print-args tuples are skipped so the 4-MD5 dumps stay byte-identical) |
| `safe_checks` | `bool` | `-fsafe` (true, default) / `-ffast` (false) |

### 1.5 Type Name Generation

`getCTypeName` maps `TypeId` → C89 type name string:

| TypeKind | C89 Name | Notes |
|----------|----------|-------|
| `void_type` | `"void"` | Direct |
| `bool_type` | `"unsigned char"` | 1 byte; C89 has no bool |
| `i8_type` | `"signed char"` | |
| `i16_type` | `"short"` | |
| `i32_type` | `"int"` | |
| `i64_type` | mangled type | `typedef long long zT_<hash>_<name>` |
| `u8_type` | `"unsigned char"` | |
| `u16_type` | `"unsigned short"` | |
| `u32_type` | `"unsigned int"` | |
| `u64_type` | mangled type | `typedef unsigned long long ...` |
| `arb_uint_type` | `"unsigned char"`/`"unsigned short"`/`"unsigned int"`/u64 | Carrier chosen by `size` (1/2/4/8) |
| `arb_int_type` | `"signed char"`/`"short"`/`"int"`/i64 | Carrier chosen by `size` (1/2/4/8) |
| `f32_type` | `"float"` | |
| `f64_type` | `"double"` | |
| `usize_type` | `"unsigned int"` | |
| `isize_type` | `"int"` | |
| `c_char_type` | `"char"` | |
| `va_list_type` | `"va_list"` | |
| `enum_type` | mangled type | `typedef <backing> <mangled>;` |
| `array_type` | `Arr_<elem-cname>_<len>` | Typedef'd — `typedef <elem> Arr_<elem>_<len>[<len>];` |
| `tuple_type` | `Tup_<tid>` (mangled, module 0) | Task 4 — synthetic (name_id 0), so the name is derived from the global dense type id; typedef'd `typedef struct { <e0> _0; ... } <cname>;` |
| `ptr_type` / `many_ptr_type` | `<base>*` | Direct pointer syntax; fn ptr → use fn name. A `volatile` flag emits the pointee-qualified `volatile T *` (or `T * volatile` for pointer-to-pointer) |
| `slice_type` | `Slice_<elem>` | Typedef'd struct: `typedef struct { <elem>* ptr; unsigned int len; } ...;` |
| `optional_type` | `Opt_<payload>` | Typedef'd struct with `{ <type> value; int has_value; }` (void payload: `{ int has_value; }`). Null construction emits `set_optional_null` directly on an `Opt_`-typed temp (`zT_M.has_value = 0;`), so no scalar null payload temp is produced. |
| `error_union_type` | `EU_<payload>` | Typedef'd struct with `{ union { <type> payload; int err; } data; int is_error; }` |
| `fn_type` | `F_<N\|P\|S>_<ret>_<p1>_<p2>...` | `F_N_` default, `F_P_` fn-ptr flag, `F_S_` stdcall |
| `error_set_type` | mangled type | `typedef int <mangled>;` + `#define` for each error tag |
| `undefined_type` | `"int"` | Fallback |
| `null_type` | `"int"` | Fallback (uncoerced null / non-optional pointer/fn targets — pointer-compatible). A null literal coerced to an optional emits `set_optional_null` directly, so no `null_const` temp is produced. |
| `integer_literal_type` | `"int"` | Fallback |

**`bool` representation (Task 11L, 2026-09-21).** `bool` is 1 byte / align 1 and maps to C89 `"unsigned char"` (C89 has no `_Bool`), matching Zig. The registry (`type_registry.zig`) and the emitter MUST agree — the folded `@sizeOf`/`@offsetOf` come from the registry, the actual layout from the emitted type. `intTypeByteWidth(bool) = 1` and `classifyIntSignedness(bool) = 0` (unsigned) agree with the emitted type. **Accepted residuals (Task 11V / AMENDMENT 16 — operator-ruled no action; NOT full Zig parity):** `?bool` is 8 bytes / align 4 (the optional arm keeps a `max(payload.alignment, 4)` floor) and `E!bool` keeps a 4-byte floor (`max(payload.size, 4)`); `typeWidthBitsForKind(bool)` stays 0 (`@bitSizeOf`/packed layout special-case bool to 1).

When `ty.c_name_id != 0`, returns the cached C name directly (set by `emitErrorUnionType` for
error union types).

### 1.6 Type Emission — emitSpecialTypes

`emitSpecialTypes(emitter, reg, sorted)` drives type header output for the stdout single-file
path. For the multi-module path (`--output-dir`), the shared-header writer `emitSharedHeader`
performs the equivalent partition into `zig_special_types.h` (see §1.17):

```
emitSpecialTypes(emitter, reg, sorted):
  1. fwd_decl pass: for each struct/tagged_union/union with name_id:
       skip packed struct and packed_union (carrier typedef is complete)
       emit "typedef <struct|union> <cname> <cname>;\n"
       keyword from aggregateKeyword(kind) — "union " for union/packed_union else "struct "
       (bare unions emit `typedef union` so the tag-namespace agrees with the def)
       dedup via fwd_decl_set (hash of cname string)
  2. pointer-only pass: for each type in sorted:
       if NOT in pointer_only_map → skip
       skip void/bool/noreturn/null/undefined/int-lit/type/module/arb-int type
       if name_id==0 and not composite type → skip
       dedup via emitted_type_set (hash of cname string)
       emitTypeDefinition()
  3. value-embedding pass: for each type in sorted:
       if IS in pointer_only_map → skip
       same skip/filter logic as sub-pass 2a
       dedup via emitted_type_set
       emitTypeDefinition()
```

`emitModule` calls `emitErrorCodePrologue` before `emitSpecialTypes`; `emitSharedHeader` also
calls `computeSharedSet` first (see §1.17).

### 1.7 Type Definition Emission

`emitTypeDefinition` dispatches by `TypeKind`:

| TypeKind | Emitter Function | Output |
|----------|-----------------|--------|
| `slice_type` | `emitSliceType` | `typedef struct { <elem>* ptr; unsigned int len; } Slice_<elem>;` |
| `optional_type` | `emitOptionalType` | `typedef struct { <type> value; int has_value; } Opt_<payload>;` (void payload: omit value). Null-payload temps for this type are emitted as `Opt_` (`set_optional_null` writes `has_value = 0;`) |
| `error_union_type` | `emitErrorUnionType` | `typedef struct { union { <type> payload; int err; } data; int is_error; } EU_<payload>;` (void payload: `{ int err; int is_error; }`) |
| `error_set_type` | `emitErrorSetType` | `typedef int <cname>;` + `#define <cname>_<tag> <N>` per tag |
| `tagged_union_type` | `emitTaggedUnionType` | Complex struct + union + tag constants |
| `enum_type` | `emitEnumType` | `typedef <backing> <cname>;` + `#define <cname>_<member> <val>` per member (64-bit member values via `itoa64`) |
| `struct_type` | `emitStructType` | `struct <cname> { <type> <field>; ... };` — or, when `typeRegistryIsPacked`, a carrier `typedef struct { unsigned char _[N]; } <cname>;` |
| `union_type` | `emitUnionType` | `union <cname> { <type> <field>; ... };` — real C union (all members at offset 0, size = max member) matching `@sizeOf`'s union-max. Keyword from `aggregateKeyword(ty.kind)` — the same helper as the two fwd-decl sites, so the C89 tag-namespace (struct/union tags share one namespace) always agrees. Guard tag is `ZIG_UNION_` (see §1.17). |
| `packed_union_type` | `emitUnionType` | carrier `typedef struct { unsigned char _[N]; } <cname>;` (untagged, members at bit 0 via bitfield access) |
| `array_type` | `emitArrayType` | `typedef <elem> Arr_<elem>_<len>[<len>];` |
| `tuple_type` | `emitTupleType` | `typedef struct { <e0> _0; <e1> _1; ... } <cname>;` (positional C model; only for tuples in `needed_tuple_set`, see §1.18) |
| `i64_type` | `emitInt64Type` | `typedef long long <cname>;` |
| `u64_type` | `emitUint64Type` | `typedef unsigned long long <cname>;` |
| `fn_type` | `emitFnPtrType` | `typedef <ret> (<Z98_STDCALL >*<cname>)(<params>);` — emitted only when the fn-ptr-used flag is set |

#### Tagged Union Emission

`emitTaggedUnionType` handles two cases:

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

#### emitFunctionSignature

```
/* <original-name> */
<call-conv> <return-type> <mangled-name>(<param-type> <param-name>, ...) {
```

- Mangled name via `nameManglerMangle(name_id, F, module_id)`
- `extern` functions: use original name, not mangled
- Comment with original name above signature for readability
- `stdcall` functions: `Z98_STDCALL ` before the name (`emitCallConv`)
- Empty params → `(void)`, variadic → `(...)` (with a `, ` separator when params exist)
- Param names go through `mangleLocalName` (keyword-safe)
- Opens `{` and increments indent
- **Variadic externs get forward declarations:** the extern-prototype guards in
  `emitModuleHeader` / `emitModuleHeaderFile` are `is_extern==0 OR is_variadic!=0`, so a variadic
  `extern fn printf(fmt, ...)` emits its C prototype (`int printf(unsigned char*, ...);`,
  name-passthrough) while non-variadic externs rely on `@cInclude`'d headers.

#### emitHoistedDecls

Emitted immediately after the function signature, before the body. Two passes:

**Pass 1: Type propagation.** Scans all instructions, tracking written types for temporaries via
`d4_wtype`/`d4_wflag` arrays and resolving `TYPE_UNDEFINED` temps. Keys:
- `.assign`: propagates src type to dst
- `.call_direct`/`.call`/`.tail_call`: marks as type 2 (call result)
- `.int_const`, `float_const`, `bool_const`, `string_const`, `enum_const`, `.poison_init` → set types
- `.binary`/`.unary`: propagates operand types to result
- `.int_cast`, `.int_cast_checked`, `.width_wrap`, `.float_cast`, `.ptr_cast`, `.int_to_float`,
  `.int_to_ptr`, `.ptr_to_int`: use target type
- `.load`, `.addr_of`, `.addr_of_field`, `.load_index`, `.load_field`, `.load_bitfield`,
  `.make_slice`, `.load_local`: set type from hoisted_temp or operand
- `.add_with_overflow`/`.sub_with_overflow`/`.mul_with_overflow`/`.shl_with_overflow`/
  `.neg_with_overflow`/`.overflow_flag`: set result type

**Pass 2: Declaration emission.** For each hoisted temp (skipping params), emits a C declaration
`<type> zT_<temp_id>;` (scalar → `= 0;`, aggregate → `= {0};`, `-fsafe` uninitialized → a
`zig_poison_fill` after the decl block). `TYPE_VOID` temps are skipped. Debug markers `D4:`,
`D7:`, `D9:`, `HTT:`, `HT:` track type resolution. Declaration is suppressed for temps that are
dead (`d4_dead`), local-mapped (`d4_local`), no-decl (`d4_nodecl`), or inlined by expression
nesting (`nest_inl`) — see §6.3.

#### emitFunctionBody

```
emitFunctionBody:
  1. Emit local variable declarations (decl_local hoisting):
     - Scans all blocks for decl_local instructions
     - Dedups by name_id (emitter.dedup_names, grown on demand to dedup_cap)
     - Skips dead names (isDeadLocalName) and TYPE_VOID locals
     - Emits "type name;\n" for each unique local
     - Sets dl_hoisted guard
  2. Emit "(void)name;" for each unused parameter
  3. Emit basic blocks:
     - Block 0: label "z_bb_0:" (emitted by the .loop_header inst — see §1.9)
     - Blocks > 0: label "z_bb_<id>:" only when referenced (bb_used)
  4. Emit each instruction via emitInst() (dead/nested defs skipped)
  5. Close "}\n"
```

Blocks are labeled with `z_bb_<id>:` — C89-style goto labels. Since the TCO feature
(`loop_header(0)` is injected as the first entry-block inst; the `.loop_header` arm emits
`z_bb_0:`), **every function** whose entry block is referenced gets a `z_bb_0:` label, emitted
after the hoisted temp decls and local decls and before the first entry-block statement:

```
ret_zF_fn(params) {
    <hoisted temp decls zT_N;>      (emitHoistedDecls)
    <local decls name;>             (emitFunctionBody decl_local hoist)
    z_bb_0:                         ← .loop_header arm
    <bb0 entry-block insts>
z_bb_1:
    <bb1 insts>
    ...
}
```

This is the TCO self-recursion jump target: self-tail calls emit rebind assigns + `goto z_bb_0;`
(back-edge to the entry block) instead of a recursive C call — O(1) stack for self-recursion.
Unused block labels are pruned (`bb_used`), so a function with no tail call and no jump to its
entry block does not emit a `z_bb_0:` label at all.

### 1.9 LirInst → C89 Emission Table

Every `LirInst` variant handled in `emitInst`:

| LirInst | C89 Output |
|---------|-----------|
| `.nop` | (nothing) |
| `.trap` | `pal_trap();` (unconditional divergence — `unreachable`/`@panic`) |
| `.check_trap` | `if (!(cond)) { pal_trap(); }` (`-fsafe` guard) |
| `.add_with_overflow` / `.sub_with_overflow` / `.mul_with_overflow` / `.shl_with_overflow` | `result = zig_wrap_<op>_<s\|u>((T)lhs, (T)rhs, <w>u);` (`emitWrapOp`) |
| `.neg_with_overflow` | `result = zig_wrap_neg_<s\|u>(value, <w>u);` (`emitWrapNeg`) |
| `.overflow_flag` | `result = zig_overflow_flag_<op>_<s\|u>((T)lhs, (T)rhs, <w>u);` (`emitFlagOp`) |
| `.ret_void` | `return;` (non-void scalar → `return 0;`; aggregate → `{ <type> zT_ret_void = {0}; return zT_ret_void; }`) |
| `.loop_header` | `z_bb_0:` (entry-block label — TCO self-recursion jump target; emitted only when bb0 is referenced) |
| `.label` | (nothing — waits for block label) |
| `.decl_local` | Emitted by hoisting pass in emitFunctionBody |
| `.assign` | `dst = src;` (array: `{ unsigned int _i=0; while(_i<N) { dst[_i]=src[_i]; _i++; } }`; dead name → `(void)src;`) |
| `.assign_field` | `base.field = src;` (struct/union/packed_union/ptr/slice/tagged_union) |
| `.assign_index` | `base[idx] = src;` or `(*base)[idx] = src;` |
| `.jump` | `goto z_bb_<id>;` |
| `.branch` | `if (cond) goto z_bb_<then>; else goto z_bb_<else>;` |
| `.ret` | `return val;` |
| `.load_local` | `result = name;` (array: `{ ... for-loop copy ... }`) |
| `.store_local` | `name = val;` (`_` → `(void)val;`) |
| `.load_global` | `result = name;` |
| `.store_global` | `name = val;` |
| `.load_field` | `result = base.field;` (slice → `.ptr`/`.len`; tagged_union → `.tag`/`.payload`; ptr → `->field`; struct → `.field`) |
| `.store_field` | `base.field = val;` (same field resolution as load_field; ptr-base struct/union pointee → `ptr->field`) |
| `.load_index` | `result = base[idx];` or `result = (*base)[idx];` |
| `.load` | `result = *ptr;` |
| `.store` | `*ptr = val;` |
| `.addr_of` | `result = &operand;` |
| `.addr_of_field` | `result = &base.field;` / `&base->field;` (struct/union field address) |
| `.binary` | `result = lhs op rhs;` (op: `+` `-` `*` `/` `%` `&` `\|` `^` `<<` `>>` `==` `!=` `<` `<=` `>` `>=`; BIN_EQ/BIN_NE with `tagged_union_type` operands append `.tag` to each operand → `s.tag == t.tag`, active-tag comparison) |
| `.unary` | `result = op operand;` (op: `-` `!` `~`) |
| `.int_const` | `result = <value>;` (signed: cast + neg magnitude to avoid warnings; tagged_union: `.tag = <value>;`) |
| `.enum_const` | `result = <type>_<member>;` |
| `.float_const` | `result = <d.ddd>;` (via `formatF64`) |
| `.string_const` | `result = "<escaped>";` (escape: `\n`, `\t`, `\r`, `\\`, `\"`) |
| `.null_const` | `result = NULL;` (optional type → `result.has_value = 0;`) |
| `.set_optional_null` | `result.has_value = 0;` |
| `.bool_const` | `result = 1;` or `result = 0;` |
| `.undefined_const` | `result = 0;` (arrays: `{ ... for-loop zero ... }`; tagged union arrays: `[_i].tag = 0;`; nested struct arrays: recursive loop) |
| `.poison_init` | `zig_poison_fill((void*)&result, (unsigned int)sizeof result);` (`-fsafe` `undefined` poison) |
| `.call` | `result = callee(args...);` (indirect call through function pointer) |
| `.call_direct` | `result = fn_name(args...);` (extern return wrapping for optional/error_union) |
| `.tail_call` | `result = fn_name(args...); return result;` — call+ret **fallback**, NOT a jump; void return → `fn_name(args...); return;`; extern → original name; indirect callee via `resolveTempName` |
| `.switch_br` | `switch (cond) { case <val>: goto z_bb_<target>; ... default: goto z_bb_<else>; }` |
| `.wrap_optional` | `result.has_value = 1;\n result.value = src;` |
| `.int_cast` | `result = (type)src;` (unchecked plain cast; the checked `-fsafe` path is the separate `.int_cast_checked`) |
| `.int_cast_checked` | `result = (type)zig_cast_checked_s/u((unsigned long long)src, <sw>u, <ss>u, <dw>u);` (`-fsafe` width/sign-aware) |
| `.width_wrap` | `result = (type)(src & <mask>);` (signed: `((... ^ <signbit>) - <signbit>)`) |
| `.int_to_float` | `result = (type)src;` |
| `.float_cast` | `result = (type)src;` |
| `.make_slice` | `result.ptr = ptr;\n result.len = len;` |
| `.print_str` | `std_print("literal");` (unchanged: the raw-bytes helper for a format-string literal segment) |
| `.print_val` | mangled `std.fmt.<printer>(val);` cross-module call into the auto-imported `sf/src/std_fmt.zig` (slice → `printStr(val.ptr, val.len)`); the old `std_print_<type>` C-ABI calls are retired. Task 4: an aggregate/tuple type calls its generated per-type printer `<name>(val, 3)` instead (see §1.18) |
| `.ptr_cast` | `result = (type)src;` |
| `.check_error` | `result = src.is_error;` |
| `.unwrap_error_payload` | `result = src.data.payload;` |
| `.unwrap_error_code` | `result = src.data.err;` (void-payload → `src.err;`) |
| `.wrap_error_ok` | `result.data.payload = src;\n result.is_error = 0;` (void-payload → `result.err = 0;\n result.is_error = 0;`) |
| `.wrap_error_err` | `result.data.err = src;\n result.is_error = 1;` (void-payload → same pattern, `.err`) |
| `.check_optional` | `result = src.has_value;` |
| `.unwrap_optional` | `result = src.value;` (void-payload → nothing) |
| `.unwrap_optional_checked` | `if (!(src.has_value)) { pal_trap(); }\n result = src.value;` (`-fsafe`) |
| `.unwrap_optional_abi` | `result = src.has_value ? src.value : NULL;` |
| `.int_to_ptr` | `result = (type)(unsigned int)src;` |
| `.ptr_to_int` | `result = (usize)src;` |
| `.func_ref` | `result = fn_name;` (function pointer; stdcall casts to the `FS_...` typedef) |
| `.va_start` | `va_start(vl, last_param);` |
| `.va_arg` | `res = va_arg(vl, TYPE);` (TYPE = `getCTypeName(type_id)`) |
| `.va_end` | `va_end(vl);` |
| `.load_bitfield` | packed bitfield extract (`emitPackedLoadBitfield`, sign-aware) |
| `.store_bitfield` | packed bitfield insert (`emitPackedStoreBitfield`) |
| `.builtin_put_char` | `putchar(value);` |
| `.builtin_stdout_write` | `fwrite(ptr, 1, len, stdout);` |
| `.builtin_stderr_write` | `fwrite(ptr, 1, len, stderr);` |
| `.builtin_get_char` | `result = getchar();` (result typed `unsigned char`) |
| `.builtin_exit` | `exit(value);` |
| `.builtin_sleep_ms` | `#ifdef _WIN32` `Sleep(value);` `#else` `usleep(value * 1000);` `#endif` |
| `.builtin_console_clear` | `#ifdef _WIN32` `FillConsoleOutputCharacter/Attribute`+home `#elif __WATCOMC__`/`#else` ANSI `std_print_len("\x1b[2J\x1b[H", 7)` `#endif` |
| `.builtin_console_gotoxy` | `#ifdef _WIN32` `SetConsoleCursorPosition(COORD)` `#elif __WATCOMC__`/`#else` `sprintf(buf, "\x1b[%d;%dH", y+1, x+1)` + `std_print_len` `#endif` |
| `.builtin_console_set_color` | `#ifdef _WIN32` `SetConsoleTextAttribute` `#elif __WATCOMC__`/`#else` `sprintf(buf, "\x1b[%s;%sm", fg_ansi[fg&0x0F], bg_ansi[bg&0x0F])` + `std_print_len` `#endif` |

Any unhandled variant falls through the `else => {}` (no-op). Emission is preceded by the LIR
optimization pass (`lirOptRun`) and the dead-temp DCE / expression-nesting suppression (§6.3),
so a declared instruction may be omitted entirely from the emitted C.

**`@intCast` / arbitrary-width emission:** `.int_cast` is the unchecked plain cast — the arm
emits `result = (type)src;` only, with all bound/sign decisions made in lowering. The checked path
is the separate `.int_cast_checked` op, emitted only under `-fsafe` (narrowing or same-width sign
change), which maps to the width/sign-aware `zig_cast_checked_s/u` helpers in `zig_runtime.h`. The
older `__bootstrap_<DST>_from_<SRC>` helpers still exist as retained runtime support (emitted by
`emit_support.zig` as `static` in `zig_runtime.h` + `extern` in `zig_runtime.c`, message
`"integer cast overflow in @intCast"`), but the emitter no longer selects them.

**`stdarg.h` gating:** `emitStdargInclude` emits `#include <stdarg.h>` only when
`moduleHasVaInsts` finds a `va_start`/`va_arg`/`va_end` LirInst in the TU — gated on actual
`va_*` usage (not `is_variadic`). The include is emitted in `emitModuleHeader`,
`emitModuleHeaderFile`, and `emitModuleFile`.

**Builtin include gating:** `emitBuiltinIncludes` emits `#include <stdio.h>` when any of
`builtin_put_char`/`builtin_stdout_write`/`builtin_stderr_write`/`builtin_get_char` appear,
`#include <stdlib.h>` for `builtin_exit`, the `_WIN32`/`unistd.h` guard for `builtin_sleep_ms`,
and the Win98-forcing console preamble (`windows.h` / `<stdio.h>`) plus
`extern void std_print_len(const char* s, unsigned int len);` for `builtin_console_*` — each
gated on actual usage (`moduleHasStdioBuiltin` / `moduleHasExitBuiltin` / `moduleHasSleepBuiltin`
/ `moduleHasConsoleBuiltin`). The includes are emitted in both the single-stream
`emitModuleHeader` and the multi-module `emitModuleFile` paths.

**Builtin console emission:** the 3 console arms emit the
`#ifdef _WIN32 / #elif defined(__WATCOMC__) / #else` guard chain; the `__WATCOMC__` and `#else`
arms share the ANSI-escape body. `@isWindows()` emits NO C (folded in sema/comptime to an
`int_const` 0/1). The Win32 console arms emit inline (no `return` — they run in the user
function, so a `return` would exit the caller).

**C89 cross-function TCO limitation:** `.tail_call` is emitted as a **call followed by a
`return`** (`zT = fn(args); return zT;`), preserving a C stack frame — semantically a tail call
but not a jump. Only **self-recursion** TCO achieves O(1) stack (rebind assigns + `goto z_bb_0;`
back-edge to the entry label). Real frame-reusing cross-function tail calls require a backend
that can emit a proper tail-jump; until then cross-function TCO is call+ret. The `.tail_call`
written-type scan marks the result temp as a call-result (written_flag=2) so the decl pass does
not flag it UNWRITTEN.

### 1.10 emitModule — Top-Level Orchestration

`emitModule(emitter, name, c_includes, ptr_only_ids, ptr_only_len)` drives one module's output
for the **stdout single-file path** (bare `--dump-c89`). With `--dump-c89 --output-dir DIR` (or
`-o DIR`), `phase_C89Emission` instead writes `zig_special_types.h` once via `emitSharedHeader`,
then loops modules emitting per-module `.h`/`.c` via `emitModuleHeaderFile`/`emitModuleFile`
(§1.17), and finally the support files/scripts (§6). `phase_C89Emission` runs the single-file
path as: create a separate `BufferedWriter` (`cwriter`), emit the fixed `emitIncludes` preamble
(`#include "zig_compat.h"` + `#include "zig_runtime.h"`), flush it, then call `emitModule` with
the hardcoded module name `"output"` — hence `/* Module: output */` in every single-file dump.

```
emitModule(emitter, name, c_includes, ptr_only_ids, ptr_only_len):
  1. Populate pointer_only_map from ptr_only_ids
  2. sorted = tstTopologicalSort(registry)
  3. emitErrorCodePrologue
  4. emitSpecialTypes(emitter, registry, sorted)  ← Phase 1: type headers
  5. emitModuleHeader(name, c_includes)           ← Phase 2a: includes + fwd decls
  6. emitGlobalDecls(module 0, all=1)             ← storage globals
  7. For each function slot (skip extern):
     a. emitter.switch_cases = &func.switch_cases
     b. lirOptRun(...)                            ← LIR optimization pass
     c. emitFunctionSignature(emitter, &func)
     d. emitHoistedDecls(emitter, &func)          ← temp declarations + DCE/nest/poison
     e. emitFunctionBody(emitter, &func)          ← local hoist + basic blocks
     f. If func.is_pub and name=="main": emitMainWrapper
  8. emitModuleFooter()                           ← "/* EOF */\n"
```

The fn list is `emitter.fn_slots` (spill-backed `LirSlot`s), not a direct parameter.

#### main() Wrapper

When a public function named `main` is found, an additional `int main(void)` wrapper is emitted.
If `main` takes parameters, the wrapper signature becomes `int main(int argc, char** argv)` and
the call forwards `(argc, <argv-cast>)`. The wrapper first emits `__module_init()` calls for every
reachable module with runtime-initialized globals (`emitModuleInitCalls`), then:

| Return Type | Wrapper |
|------------|---------|
| `void` | `int main(void) { ... zF_<hash>_main(); return 0; }` |
| `error_union` (void payload) | `int main(void) { ... zT_main_result = zF_<hash>_main(); return zT_main_result.is_error ? zT_main_result.err : 0; }` |
| `error_union` (non-void payload) | `int main(void) { ... return zT_main_result.is_error ? zT_main_result.data.err : (int)zT_main_result.data.payload; }` |
| normal | `int main(void) { ... return (int)zF_<hash>_main(); }` |

#### emitModuleHeader

```
/* Module: <name> */
#include "zig_compat.h"
#include "zig_special_types.h"
<stdarg include, iff va_* used>
<builtin includes, gated on use>
<c-includes...>

/* Forward declarations */
<func-forward-decls...>
```

C-includes: if starts with `<`, emit raw (`#include <foo.h>`). Otherwise wrap in quotes (`#include "foo.h"`).
`emitStdargInclude` adds `<stdarg.h>` only when the TU uses `va_start`/`va_arg`/`va_end`;
`emitBuiltinIncludes` adds `<stdio.h>`/`<stdlib.h>`/`<windows.h>`/`<unistd.h>` and the console
preamble gated on actual builtin use.

### 1.11 emitModuleFooter

```
/* EOF */
```

### 1.12 emitFunctionForwardDecl

Emits `return-type fn-name(param-types...);` — same mangling and calling convention as the
signature but without param names.

### 1.13 emitBaseIdxAccess

Handles indexed load/store with ptr-to-array detection:

- Ptr-to-array: `result = (*base)[idx];` or `(*base)[idx] = src;`
- Normal: `result = base[idx];` or `base[idx] = src;`
- Decay forms: `&(*base)[idx]`, `&base[idx]`, or a byte-copy for a by-value array element
  (`decay` 1/2/3).

`isBasePtrToArray` checks if a temp's type is ptr-to-array.

### 1.14 emitFieldAssign

Resolves field access for `.assign_field`:

| Base Type | Access Pattern |
|-----------|---------------|
| `slice_type` | `.ptr` (field 0), `.len` (field 1), `.f_<N>` (N>1) |
| `tagged_union_type` | `.tag` (field 0), `.payload.<variant-name>._<sub>` or `.payload` (field 1) |
| `ptr_type`/`many_ptr_type` → `struct_type` | `->field` |
| `struct_type` | `.field` (with array copy: `{ ... while(_j < len) { base.field[_j] = src[_j]; _j++; } }`) |
| `union_type` / `packed_union_type` | `.field` — the base-type dispatch gained a `union_type` branch mirroring the `struct_type` branch but scanning `un_items[payload_idx].fields_start` + `fe_items` for `field_id` (same array-copy handling). A union-typed base now emits `.member_name` like `store_field`'s ptr-base `->` emitter instead of falling through to the numeric fallback. Regression guard: `union_literal_nested_xmod`. |
| unknown | `.f_<field_id>` (numeric fallback) |

### 1.15 Helper Functions

| Function | Purpose |
|----------|---------|
| `getBinOpStr` | Maps binary op u8 → C operator string (+, -, *, /, %, &, \|, ^, <<, >>, ==, !=, <, <=, >, >=) |
| `getUnOpStr` | Maps unary op u8 → C operator string (-, !, ~) |
| `getCheckedCastFnName` | Maps TypeId → checked cast function name (std_checked_cast_i8/u8/i16/u16/i32/u32/i64/u64) |
| `getPrintFnName` | Maps TypeId → **mangled C name** of the fmt printer: infers `printFnSourceName` then mangles it (`nameManglerMangle` kind 0) against `emitter.std_fmt_module_id`; when that id is absent (`0xFFFFFFFF`) it falls back to the unmangled source name. |
| `printKindIsIntegerLike` | Task 2: true for fixed ints, arbitrary-width ints, `c_char`, `enum`, `integer_literal` — the kinds the width/signedness dispatch routes (everything else keeps an explicit arm or the defensive `printI32` fallback). |
| `printFnSourceName` | Maps TypeId × specifier → the `std.fmt` SOURCE name. Task 2 width/signedness dispatch: integer-like kinds (`printKindIsIntegerLike`) route via `typeRegistryIntWidthBits`/`typeRegistryIntIsSigned` → `printU32`/`printI32` at ≤32 bits, `printU64`/`printI64` at 33..64, and the matching `printHex*` for `{x}` (Z98 `usize` is 32-bit unsigned; `integer_literal` is the 32-bit signed fallback). Non-integer arms unchanged: `printF64` (`f32_type` too — the `float`→`double` widening is implicit via the `void printF64(double)` prototype), `printBool`, `printChar` (u8 `{c}`), `printStr` (slice), default `printI32` (defensive; Task 3 rejects those arguments). |
| `printAggKind` / `aggPrinterName` | Task 4: true for struct/union/tagged_union/tuple/packed_union; the generated static C printer name (`z98_printStruct_<tid>` etc.; see §1.18). |
| `emitGeneratedPrinters` / `collectPrintRoots` / `emitAggPrinterRec` / `emitAggPrinterDef` / `emitAggValue` | Task 4: per-module scan for `.print_val` aggregate roots, dependency-first deduped emission, and the printer body (fields/tag-switch/packed extraction/depth-1 recursion). |
| `emitTupleType` / `emitNeededTupleTypes` / `collectNeededTuples` | Task 4: the tuple `typedef struct { _0, _1, ... }` C model, the needed-tuple emission pass (end of both type-emission paths), and the hoisted-temp/global collector (`C89Emitter.needed_tuple_set`). |
| `aggPackedScratchName` / `aggAccessAppend` / `aggAccessAppendIndex` / `aggIndentStmt` | Task 4 helpers: packed-field scratch local names, `v.field` / `v._N` access-string builders, printer-statement indentation. |
| `emitCStringLiteral` | Emits C string literal with escape sequences (\n, \t, \r, \\, \") |
| `resolveTempName` | Resolve temp_id → C name. Checks local flat lookup first (fl_temps), falls back to mangleTempName |
| `getTempTypeByIndex` | Find type_id for a temp_id by scanning hoisted_temps |
| `mangleTempName` | Format `zT_<temp_id>` for temp variables |
| `mangleLocalName` | Format local: keyword-safe (z_ prefix) or original |
| `writeHex` | Write 8 hex digits of u32 to buffer |
| `isTempOrBuiltin` | Check if name starts with `__tmp`, `__ret`, `__bootstrap` |
| `isC89Keyword` | Check if name_id is in keyword_set |
| `dbgPrintU32` | Debug: write u32 to stderr |
| `aggregateKeyword` | Single source of the `struct `/`union ` keyword for named aggregates (struct/tagged_union → `struct `, union/packed_union → `union `) |
| `ctypeGuardWrite` | Writes the `ZIG_<TAG>_` include-guard prefix for a type kind |
| `emitCallConv` | Writes `Z98_STDCALL ` for a `stdcall` function |
| `emitCalleeExpr` | Writes a callee expression, casting a stdcall callee to its `FS_...` fn-pointer typedef |
| `findCalleeFnTypeId` / `tempFnTypeId` | Locate the fn-type id of a direct/indirect callee for convention casting |
| `moduleQualifiedName` | Computes the `DIR/<basename>_<FNV1a8>` output stem for a module |
| `emitSupportFiles` / `emitBuildScripts` | Write the self-contained support files and companion build scripts (§6) |
| `openSupportOutputFile` | Opens `DIR/<name>` for writing; aborts on path overflow / open failure |
| `emitPackedStoreBitfield` / `emitPackedLoadBitfield` | Shift/mask read/write of a packed bitfield through a byte carrier |
| `emitSatBinary` | Saturating add/sub/mul/shift for arbitrary-width ints |
| `emitWrapOp` / `emitWrapNeg` / `emitFlagOp` | `-fsafe` wrapping (`zig_wrap_*`) and overflow-flag (`zig_overflow_flag_*`) emission |
| `emitValueExpr` / `nestEmitDefRvalue` / `nestEmitBinExpr` / `nestEmitUnaryExpr` | Recursive expression-nesting renderer (emission-core compaction) |
| `dceResultPos` / `dceMarkAllReads` / `dceMarkAllWritten` / `dceReleaseOperands` | Dead-temp DCE marking |
| `isDeadLocalName` | True when a local name is never read (skip its declaration) |
| `emitBuildTargetSh` / `emitBuildTargetBat` / `emitBuildOwcBat` | Companion build-script bodies (`emitBuildScripts`) |
| `emitZigRuntimeC` / `emitZigPalC` | DEAD CODE — stale mirrors, never called (§6) |

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
| `DLD:s` | emitFunctionBody | Dead local name skipped |
| `BFN:p` / `BFX:p` | emitFunctionBody | Function-body buffer position (start / end) |
| `HT:` | emitHoistedDecls | Hoisted-temp declaration detail (temp, type, eff-type, written) |
| `ESTA:` / `ESTB:` | emitSpecialTypes | Synthetic type with `name_id==0` skipped (2a / 2b) |
| `NUL:TYnul` | getCTypeName | `null_type` → `"int"` fallback |
| `UCT:r` | emitInst (.poison_init) | `-fsafe` poison-fill result temp |
| `DBGFNPTR:t` | emitHoistedDecls | Fn-pointer effective-type resolution detail |

### 1.17 Multi-Module Emission (`--output-dir`)

With `--dump-c89 --output-dir DIR` (or `-o DIR`), `phase_C89Emission` switches from the single
stdout stream to **per-module file emission**. Output set: `DIR/<qualified>.c` (one per module) +
`DIR/<qualified>.h` (one per module) + `DIR/zig_special_types.h` + the self-contained support
files/scripts (§6). The stdout single-file path (§1.10) is kept for bare `--dump-c89`; the two
paths are branched on the CLI, never mixed.

- **Qualified filename scheme (F-S7)** — output stems come from `moduleQualifiedName`:
  `DIR/<basename clamped 64>_<FNV1a8>.c/.h`, where `<basename>` is the module path's last `/`
  component with `.zig`/`.z98` stripped (clamped to 64 chars) and `<FNV1a8>` is the
  8-uppercase-hex FNV-1a hash of the full module path (`hash_mod.fnv1a` + `writeHex`). No
  module_id in the filename, so two same-basename deps get distinct `.h`/`#include` lines.
- **Length guard** — before constructing each path, the emitter checks
  `od.len + 1 + base.len + 3 > 511`; if exceeded, `error: output filename too long` +
  `pal.exit(1)`.
- **Shared header** — `emitSharedHeader` calls `computeSharedSet`, then emits
  `zig_special_types.h` with file guard `ZIG_SPECIAL_TYPES_H`, preamble
  `#include "zig_compat.h"` + `#include "zig_runtime.h"`, the error-code prologue, a
  fwd-decl pass (`typedef <struct|union> X X;` for every named struct/tagged_union/union, keyword
  from `aggregateKeyword(kind)`, so bare unions forward-decl `typedef union X X;` matching their
  definition), sub-pass 2a restricted to `shared_set` (guarded), and all of sub-pass 2b.
  `computeSharedSet` seeds synthetics (`name_id==0` in slice/optional/error_union/error_set/
  tagged_union/union/array/fn_type) ∪ value-embedding named types (CLS:v, `pointer_only_map`
  miss) ∪ i64/u64 ∪ named fn_type, then closes over pointer-only named types referenced by
  shared members (fixpoint over `reg.types_len`, via `tstIsDep`). Packed structs and
  `packed_union` skip the fwd-decl pass (their carrier typedef is complete).
- **Closure-edge model (F-S8)** — a type joins `shared_set` when it is referenced **by value OR
  in a way that requires the C type name in scope** (typedef'd kinds — enum/error_set — need the
  name in scope even behind a pointer/slice, since a typedef cannot be implicitly
  forward-declared like a `struct` tag). `c89NeedsEmitEdge` admits enum/error_set targets;
  `tstIsDep`/`tstEdgesCount`/`tstEdgesFill` have optional_type/slice_type/union_type source
  branches. The optional/slice edges are **restricted** to enum/error_set element targets
  (prevents the recursive-slice 2-cycle hazard); `union_type` is unrestricted (by-value fields).
- **Guard scheme** — every type definition is wrapped
  `#ifndef ZIG_<TAG>_<cname> / #define ZIG_<TAG>_<cname> / <def> / #endif`. Tag from
  `ctypeGuardWrite`: `ZIG_STRUCT_`, `ZIG_UNION_` (union + packed_union), `ZIG_ENUM_`,
  `ZIG_ERROR_SET_`, `ZIG_SLICE_`, `ZIG_OPTIONAL_`, `ZIG_ERRORUNION_`, `ZIG_ARRAY_`, `ZIG_FNPTR_`,
  `ZIG_I64_`, `ZIG_U64_`, fallback `ZIG_TYPE_`.
- **Per-module `.h`** — `emitModuleHeaderFile`: module guard
  `ZIG_MODULE_<UPPER(qualified)>_H` (qualified stem uppercased, non-alnum → `_`; the path hash
  makes guards auto-unique); includes `zig_compat.h` + `zig_special_types.h`, the module's own
  `@cInclude` directives (per-module, NOT the global `cincludeUnionAll` union), stdarg/builtin
  includes gated on use, each dependency's `.h` by its **qualified** name (value-ref deps ∪
  import edges, skipping self), owned CLS:p type full-definitions, fn fwd-decls (non-extern),
  storage global `extern` decls, and type-storage global `extern` decls.
- **Per-module `.c`** — `emitModuleFile`: `#include "<qualified>.h"`, stdarg/builtin includes,
  global definitions, then the module's own fn bodies (externs skipped; `switch_cases`/
  `dl_hoisted` reset per fn, `lirOptRun` per fn). The `int main(void)` wrapper is emitted only
  for `module_id==0`'s public `main` (`emitMainWrapper`).
- **Companion build scripts are live** — `emitBuildScripts` (called from `phase_C89Emission`)
  writes `build_target.sh` always, plus `build_target.bat` (MSVC `cl`) and `build_owc.bat`
  (OpenWatcom `wcc386`/`wlink`) when the target is Windows; see §6.1. The old claim that the
  `emitBuildTarget*` templates are dead code no longer holds.
- **Module pruning — needed-only std.** Only modules in the value-reference reachability set are
  emitted and listed by the scripts; see §6.2. This is what makes a stdio-only `@import("std")`
  program emit no `std_net` and link without `-lwsock32`.
- **Module→file emission loop — no silent drop.** The multi-module branch loops
  `moduleRegistryGetModules` and, for each registered reachable module, emits one `.h` and one
  `.c`; every reachable module is emitted. (`mod_silent_drop_xmod` is kept as a regression guard
  for the false "silent module drop" theory.)
- **Orphan-module handling** — a `.zig` file with no incoming `@import` edge is never added to the
  module registry (`moduleRegistryResolveImports` enqueues only via import edges), so un-imported
  files are never emitted. Correct behavior, not a defect.
- **Known Issues (fixed):**
  - **Cross-module enum-literal comparison (I3) — FIXED.** A cross-module qualified enum literal
    (`json.JsonValueTag.Null`) resolved to `TYPE_VOID`, emitting an undeclared temp
    (`'zT_XX' undeclared`). Fixed by adding an `enum_type` member-literal case to the generic
    base-type field-access dispatch in both `semanticAnalyzerResolveFieldAccess` and `lower.zig`
    (Option A). Regression guards: `zT_missing_fwd_xmod`, `json_parser_workaround`.
  - **Cross-module tagged-union `==` / member-literal SEGV (I6) — FIXED.** A tagged-union member
    literal reached `typeRegistryGetStructFields` on a TU `payload_idx`, a garbage read → SEGV.
    Fixed by a `tagged_union_type` case in the generic field-access dispatch
    (`emitTaggedUnionInit`). Separately, BIN_EQ/BIN_NE on `tagged_union_type` operands now append
    `.tag` to each operand, so union `==` emits `s.tag == t.tag` (valid C; per operator ruling
    m0471, zig1 supersedes the zig0 oracle's rejection). Regression guard:
    `tagged_union_cmp_xmod`.
  - **Runtime-symbol gap (json_parser) — FIXED (std.arena migration).** `arena_alloc_default`
    was missing from `sf/src/include/zig_runtime.c`; resolved by the Zig-side `sf/src/std_arena.zig`
    module (`Arena{data,capacity,used}` over a static buffer) imported by the examples, removing
    the extern. Regression guard: `extern_runtime_symbol_xmod`.

### 1.18 Generated aggregate printers (Task 4, z98-print-formatting)

`{}` on `struct`/`union`/`tagged_union`/`packed_union`/`tuple` has no `std.fmt`
primitive (Z98 has no generics), so the emitter generates one `static` C printer
per printed aggregate type and `.print_val` calls it. Output matches Zig
0.15.2's `Io.Writer.printValue` aggregate arms byte-for-byte, including its
recursion cap (`std.fmt.default_max_depth = 3`, `kPrintAggMaxDepth`): a nested
aggregate at `d == 0` prints `.{ ... }`, and an untagged auto union always
prints `.{ ... }` (Zig never reads an untagged field).

- `aggPrinterName` → `z98_printStruct_<tid>` / `z98_printUnion_` /
  `z98_printTaggedUnion_` / `z98_printPackedUnion_` / `z98_printTuple_` (the
  `z98_` prefix avoids collision with `extern` source names).
- `collectPrintRoots` scans the module's fn slots for `.print_val` aggregate
  types; `emitGeneratedPrinters` (called from `emitModule`/`emitModuleFile`
  before the fn bodies) emits each root and its nested aggregate fields
  dependency-first, deduped. No forward declarations are needed; `static` makes
  cross-module duplicates safe.
- `emitAggPrinterDef` emits `static void <name>(<CType> v, int d)`: named fields
  as `v.<field>`, tuple elements as `v._<i>`, tagged unions as
  `switch (v.tag) { case <field-index>: ... v.payload.<field>._0; ... }` (Z98
  tagged unions always carry integer tags), packed struct/union fields via
  `emitPackedLoadBitfield` into declared scratch locals. Scalars route through
  `getPrintFnName(..., 'd')`; nested aggregates call their printer with `d - 1`.
  The emitted literals are Zig's exact separators (`".{"`, `" .a = "`,
  `", .b = "`, `" }"`; tuple `" "`/`", "`; packed-union `".{ "`/`", "`; tagged
  `".{ ."`/`<name>`/`" = "`).
- **Tuple C model**: `getCTypeName` gives tuple types a stable `Tup_<tid>` name
  (the generic `name_id==0` fallback would collapse every tuple onto the
  empty-name mangle); `emitTupleType` emits
  `typedef struct { <e0> _0; ... } <cname>;`; `ctypeGuardWrite` uses
  `ZIG_TUPLE_`; `tstEdgesCount`/`tstEdgesFill`/`tstIsDep` gained tuple element
  arms. Tuple typedefs are emitted ONLY for `C89Emitter.needed_tuple_set`
  (runtime hoisted temps / globals, collected in `phase_C89Emission` by
  `collectNeededTuples`; `emitNeededTupleTypes` runs at the end of
  `emitSpecialTypes` / `emitSharedHeader`): registry-only print-args tuples must
  not add C, or the 4-MD5 single-file dumps move. Needed tuples also join
  `shared_set` so the closure promotes pointer-only named element types into the
  shared header (definition-before-use).

---

## 2. `cinclude.zig` — @cInclude Dedup (32 lines)

### Function

`cincludeUnionAll(module_reg, alloc)`:

```
cincludeUnionAll(module_reg, alloc) → []u32:
  1. temp = u32ArrayListInit(alloc)          ← result accumulator
  2. hint = Σ module.c_includes.len          ← capacity hint
  3. seen = u32ToU32MapInitCap(alloc, hint)  ← dedup tracker
  4. For each module in moduleRegistryGetModules(module_reg):
     a. For each c_include name_id in module.c_includes:
        i. If seen[ name_id ] exists → skip duplicate
        ii. Else: seen[name_id] = 1, append name_id to temp
  5. Return temp slice
```

This produces a flat deduplicated list of all `@cInclude` directives across all modules. Used by
`emitModuleHeader` to emit `#include` lines for the stdout single-file path. In the multi-module
path (§1.17), `emitModuleHeaderFile` does NOT use the global union — each module `.h` emits its
own `c_includes` directives directly (per-module `@cInclude`), so a directive only appears in the
header of the module that declared it.

### Struct — ModuleEntry Fields Touched

From `module_registry.zig`: `ModuleEntry` contains `c_includes: U32ArrayList` — a list of interned
name_ids for `@cInclude` strings.

---

## 3. `name_mangler.zig` — Minimal Counter (7 lines)

The standalone `name_mangler.zig` file contains only:

```
pub const NameMangler = struct { counter: u32 };
pub fn nameManglerInit() NameMangler { return .{ .counter = 0 }; }
```

**This file is NOT the primary mangler used by `c89_emit.zig`.** The actual `NameMangler` with
hash/cache/keyword handling is defined inline in `c89_emit.zig`. The standalone file appears to be
a separate or deprecated implementation. See §1.3 above for the actual mangler.

---

## 4. Data Flow

```
Function-slot list (per module, spill-backed)
    │
    ▼
emitModule(...)
    │
    ├─ pointer_only_map populated from caller-provided ids
    ├─ tstTopologicalSort (Kahn) ← TypeRegistry
    ├─ emitErrorCodePrologue
    │
    ├─ emitSpecialTypes (type headers, topological order)
    │   ├─ Forward decls (typedef struct X X;)
    │   ├─ Pointer-only type definitions
    │   └─ Value-embedding type definitions
    │
    ├─ emitModuleHeader (includes + fn forward decls)
    │   └─ cincludeUnionAll → deduped #include lines
    │
    ├─ emitGlobalDecls (storage globals)
    │
    ├─ For each function:
    │   ├─ lirOptRun (LIR optimization pass)
    │   ├─ emitFunctionSignature → "return-type name(params) {"
    │   ├─ emitHoistedDecls → local temp variables (+DCE/nest/poison)
    │   └─ emitFunctionBody:
    │       ├─ decl_local hoisting (dedup, dead-name skip)
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
| Scratch (`alloc`, reset per function) | Type-propagation arrays (`d4_wtype`, `d4_wflag`, `d4_t2p`, `d4_dead`, `d4_local`, `d4_nodecl`, `d4_lread`), block-label flags (`bb_used`), nesting array (`nest_inl`), per-function DCE maps |
| Persistent (`persist_alloc`) | `C89Emitter` maps (`emitted_type_set`, `fwd_decl_set`, `pointer_only_map`, `shared_set`, `reachable`, `temp_global_map`, `ts_ref_set`), `NameMangler` maps (cache, keyword_set, collision maps), `dedup_names`, `fl_name_ids`, `fl_temps` |

The multi-module path additionally writes into `DIR` via a per-file `BufferedWriter` plus the
`emit_support.zig` support files and companion build scripts (§6).

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

## 6. `emit_support.zig` — Self-Contained Output Support

`emit_support.zig` is the hand-written support-file emitter for the C89 backend. It holds
the canonical bytes of the compiler's runtime/platform support files as Z98 string
constants and writes them into the user's output directory, so the emitted tree is
self-contained (`-I .` + compiling every emitted `.c`). The canonical single sources of
truth on disk are `sf/src/include/zig_compat.h`, `zig_runtime.h`, `net_prelude.h`,
`std_os_prelude.h`, `std_time_prelude.h`, `zig_runtime.c`, `zig_pal.c`, and
`sf/src/c_exit.c`; `scripts/check_emit_support.sh` asserts emitted == canonical
byte-for-byte.

| Function | Writes |
|----------|--------|
| `emitZigCompatHSupport` | `zig_compat.h` (C89 compat typedefs, `bool`, `NULL`, `Z98_STDCALL`) |
| `emitNetPreludeHSupport` | `net_prelude.h` (target-neutral Winsock/libc net include prelude + `_os` aliases) |
| `emitStdOsPreludeHSupport` | `std_os_prelude.h` (target-neutral OS include prelude) |
| `emitStdTimePreludeHSupport` | `std_time_prelude.h` (target-neutral time include prelude + monotonic probe) |
| `emitCExitCSupport` | `c_exit.c` (`void c_exit(int)`) |
| `emitZigRuntimeHSupport(writer, safe_checks)` | `zig_runtime.h` (PAL/print/checked-cast declarations; `-fsafe` adds poison + overflow/checked-cast helpers) |
| `emitZigRuntimeCSupport(writer, safe_checks)` | `zig_runtime.c` (runtime bodies; `-fsafe` adds `zig_poison_fill`) |
| `emitZigPalCSupport` | `zig_pal.c` (PAL: file I/O, printing, `pal_trap`, `pal_i64_to_str`/`pal_u64_to_str`/`pal_f64_to_str`, `pal_get_default_lib_path`) |

`emitSupportFiles` (`c89_emit.zig`) drives the writes through `openSupportOutputFile`
(fixed 512-byte path buffer; `error: output filename too long` + exit on overflow,
`error: cannot open output file` on open failure). It always writes `zig_compat.h`,
`zig_runtime.h`, `zig_runtime.c`, `zig_pal.c`, and `c_exit.c`. The three preludes are
**conditionally emitted**: `net_prelude.h` only when some reachable module's
`c_includes` names `<net_prelude.h>` (`scriptNetEmitted`), and likewise
`std_os_prelude.h` / `std_time_prelude.h` via `scriptStdOsEmitted` / `scriptStdTimeEmitted`.
Self-contained output means present iff referenced, so a stdio-only program carries no
net/OS/time prelude and needs no winsock link.

The `emitZigRuntimeC`/`emitZigPalC` functions in `c89_emit.zig` are **DEAD CODE**
(never called) and are stale mirrors of `zig_pal.c`/`zig_runtime.c`; the live bytes come
from `emit_support.zig`.

### 6.1 Companion build scripts

`emitBuildScripts` writes companion build scripts into the output dir, enumerating the
compiler-known emitted `.c` set (reachable module stems first, runtime sources
`zig_runtime.c`/`zig_pal.c`/`c_exit.c` last — deterministic link order) and passing
`-I .`. `build_target.sh` is emitted always; `build_target.bat` (MSVC `cl`) and
`build_owc.bat` (OpenWatcom `wcc386`/`wlink`) only when the target is Windows. Each adds
the winsock library (`-lwsock32` / `wsock32.lib` / `library wsock32`) **iff** a
`net_prelude.h` c-include was emitted. The scripts carry a warning policy comment (no
warnings-as-errors in `build_target.sh`; `/WX` and `/we` documented as removable in the
MSVC/OW scripts). The `emitBuildTarget*` functions are now live (previously dead
templates); `emitBuildScripts` is invoked from `phase_C89Emission`.

### 6.2 Module pruning in emission

`phase_C89Emission` computes a **value-reference reachability set** (`emitter.reachable`,
`emitter.prune_active`) from the root module: module-level LIR value references
(`call`/`call_direct`/`tail_call`/`func_ref`/`load_global`/`store_global` owning modules),
runtime-init roots, and by-value global type owners — not mere `@import`/re-export edges.
Only reachable modules are emitted (`.c`/`.h`) and listed by the build scripts; a module
header includes the headers of every module it value-references (the cross-module mangled
prototype lives only in the callee's header) unioned with surviving import edges.
`emitModuleInitCalls` also skips unreachable modules. This is what lets a stdio-only
`@import("std")` program emit no `std_net` and link without `-lwsock32`.

### 6.3 Emission-core compaction

Per function, `emitModule`/`emitModuleFile` run `lirOptRun` (the LIR optimization pass: copy
propagation, local const-fold, expression-nesting metadata) before emission. The duplicate
named-local store collapse and copy coalescing from the emission-core-compaction plan land at
their lowering source sites (the emitter stays a dumb printer); the emitter-side compaction is:

- **Dead-temp DCE** — `dceResultPos`/`dceMarkAllReads`/`dceMarkAllWritten` mark unread
  results; `emitter.d4_dead` suppresses their declarations and defs.
- **Expression nesting/coalescing** — `emitValueExpr`/`nestEmitDefRvalue` inline a
  single-use producer's rvalue into its consumer and suppress the temp decl/def
  (`nest_ok`/`nest_inl`, capped at `kEmitNestDepthCap = 32`).
- **Unused block-label pruning** — only blocks targeted by `jump`/`branch`/`switch_br`
  get a `z_bb_<id>:` label (`bb_used`/`bb_used_count`).
- **Dead local/name skip** — `isDeadLocalName` drops locals never read; a store to a dead
  name emits `(void)src;`.
- **Unused-parameter `(void)name;`** suppression for locals not otherwise used.

### 6.4 Packed, int-width, `volatile`, and calling-convention emission

- **Packed struct/union** — `typeRegistryIsPacked` types emit as a byte carrier
  `typedef struct { unsigned char _[N]; } <cname>;` (native C struct-by-value for
  param/return/assign/array/global); field access emits shift/mask via
  `emitPackedLoadBitfield`/`emitPackedStoreBitfield` (`bfByteRefWrite`). `packed_union`
  is a distinct `TypeKind` sharing the carrier shape (untagged, members at bit 0).
- **Arbitrary-width ints/enums** — `arb_uint_type`/`arb_int_type` map to a fixed C carrier
  by `size` (`unsigned char`/`short`/`int`/`unsigned long long`), and `enum(uN)` emits its
  backing carrier plus `#define` members. `width_wrap` masks/sign-extends to the declared
  width; `int_cast_checked` emits `zig_cast_checked_s/u`.
- **`volatile`** — carried on the pointer `Type.flags` bit; `getCTypeName` emits the
  pointee-qualified form (`volatile T *`), and `T * volatile` for pointer-to-pointer.
- **Calling convention** — `emitCallConv` writes `Z98_STDCALL ` before a `stdcall` extern
  signature and forward declaration; `emitFnPtrType` emits the `Z98_STDCALL` fn-pointer
  typedef (`FS_...`); `emitCalleeExpr` casts a stdcall callee at the use site to that
  typedef (the OS header stays the sole declaration source). `Z98_STDCALL` is defined in
  `zig_compat.h`. Unknown conventions are `error[3045]`; variadic `stdcall` is
  `error[3012]`; both are frontend rejects (0 `.c`).

### 6.5 C89-ahead guard emission (`-fsafe` / `-ffast`)

`C89Emitter.safe_checks` is set from the CLI. Under `-fsafe` (default), `zig_runtime.h`
and `zig_runtime.c` gain the poison/overflow/checked-cast helpers, and the emitter maps
the safety LIR ops to them:

- `poison_init` / `lir_fn.poison_uninit` → `zig_poison_fill((void*)&zT_N, sizeof zT_N);`
  (byte-exact `0xAA` fill for `undefined`); `-ffast` keeps deterministic zeroing.
- `add_with_overflow`/`sub_with_overflow`/`mul_with_overflow`/`shl_with_overflow` →
  `zig_wrap_<op>_<s|u>(...)`; `neg_with_overflow` → `zig_wrap_neg_<s|u>`.
- `overflow_flag` → `zig_overflow_flag_<op>_<s|u>(...)`.
- `int_cast_checked` → `zig_cast_checked_s`/`zig_cast_checked_u` (width/sign aware).

All helpers are header-`static` so every emitted TU is self-sufficient; `-ffast` output
is byte-unchanged (the helpers are omitted). The remaining `-fsafe` guards (division by
zero, shift count, null-unwrap, index bounds) are lowered to `pal_trap()` checks; `-ffast`
emits the unchecked form.

### 6.6 Self-contained f64 formatting

Floating-point formatting avoids the host `printf`: float literals emit via
`formatF64` (`util/format.zig`, a Z98 implementation), and runtime
`std.fmt.printF64` (`sf/src/std_fmt.zig`, Task 1) uses `pal_f64_to_str`
(integer part via `pal_i64_to_str`, up to 6 fractional digits, trailing zeros
trimmed) in `zig_pal.c`. Both are part of the emitted self-contained set. Before
Task 1 the printer body lived in the C runtime as `std_print_f64`.

Task 2 added the integral-value omission to `pal_f64_to_str` (both lockstep
copies): when `(f64)(i64)value == value`, the `'.'` + fraction is not emitted
(`7.0` → `7`, `100.0` → `100`, `0.0` → `0`), matching Zig. **Operator-ruled
bounded residuals (Q2, unchanged):** the non-integral path is still the 6-digit
truncating loop (`1.0/3.0` → `0.333333`, Zig `0.3333333333333333`); `1e20` hits
the `(i64)` cast UB and prints `-9223372036854775808…` (Zig
`100000000000000000000`); `-0.0` prints `0` (Zig `-0`). Full shortest-form
decimal is not implemented.

---

## 7. Removed: `@socket*` builtin emission (netbind S3)

The 11 `@socket*` networking builtins (`socketCreate`/`socketBindListen`/`socketAccept`/
`socketConnect`/`socketSend`/`socketRecv`/`socketSelect`/`socketFdZero`/`socketFdSet`/
`socketFdIsset`/`socketClose`) and their inline C-emission ports were **REMOVED**
(netbind S3, 2026-09-04): the emitter's net-gated include block and the per-builtin
`#ifdef _WIN32 / #else` bodies (helpers `emitSocketCreate`/`emitSocketSelect`/
`emitSocketClose`/`emitSocketWrite`/`emitSocketOptPtrValue`) are deleted. A direct
`@socket*` caller now fails `error[3000]: unsupported builtin function` (rc=2, 0 `.c`);
`repro/mi_matrix/net_builtin_test` is the green negative probe.

Networking is now the **std_net extern surface**: target-selected `extern "c"` bindings
(wsock32/libc) under `@cInclude("<net_prelude.h>")`, WSAStartup init in `std_net.init()`,
and the `createTcpClient` factory — see `sf/src/std_net.zig` and the QUICK_REF
"Post-netbind baseline". `emitBuiltinIncludes` now covers only stdio/exit/sleep/console
gating; there is no socket emission path in `c89_emit.zig`.
