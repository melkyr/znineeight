# Phase 1 M2 Task 1C-I report — `const`-global rodata (investigation, report-only)

- Plan authority: `docs/superpowers/plans/2026-10-21-phase1-m2-crypto-core-plan.md` Task 1C-I
- Brief: `task-1c-i-brief.md`; context: `task-1c-i-context.md`
- HEAD: `bc48ec9c` (clean except untracked `run.err`, left in place)
- Compiler under test: `/tmp/m1_build/zig1_5_clean`, md5 `21c957730d268f1e7883176fa5413b65` (= v111 fixed point, verified)
- All probes under `/tmp/t1ci_*`. No source/plan/spec/seed edits.

## 0. Verdict

The fix is implementable with no tech debt for every `const` shape present in
`sf/src`, `examples/z98`, `repro/mi_matrix`, and `scripts/stdlib/ref` at HEAD,
plus the multi-D/struct/nested shapes required by the plan. One C89
representability limit exists (non-first-member union initializers, and
tagged-union payloads whose active union member is not first): see STOP-1.
One plan-text contradiction surfaced (fixed-point anchor vs compiler-fix
rotation): see STOP-2. Neither blocks 1C-F for the M2 corpus (0 occurrences of
the STOP-1 shape in any of the four trees; recommended resolution attached).

Trigger reproduced (probe `t1ci_probe2`, 1-D const array):

```
nm -S m.o | grep arr1d
0000000000000000 0000000000000010 B zG_8693C83D_arr1d
```

`B` = writable `.bss`, matching `task-2-report.md` T-table evidence
(`B SBOX`, `B Te0..Te3`, `sf/src/std_cipher.zig:468-635`).

---

## 1. Shape enumeration (Step 1)

Method: `/tmp/t1ci_enum/classify2.sh` (read-only awk over `^const ` lines) +
hand verification + compiler probes. Trees scanned: `sf/src`, `examples/z98`,
`repro/mi_matrix`, `scripts/stdlib/ref`. Total file-scope `const` lines: 4889.
Of these: 3116 `@import` module aliases (no C storage, `SymbolKind.module`),
648 type decls (`struct`/`union`/`enum`/`error` — become `SymbolKind.type_alias`,
no C storage, `sf/src/symbol_registrator.zig:320-337` + `const_alias_prepass.zig:187`),
237 single-line type aliases (`const Sand = alloc_mod.Sand;` etc., same
type_alias path). The remaining ~890 are value constants. Shapes below.

Per-shape table. "Today" = emitted storage at HEAD (verified by probe where
marked ▸); "Post-fix" = required form per plan.

| # | Shape | In-tree examples (file:line) | Today | Post-fix |
|---|-------|------------------------------|-------|----------|
| S1 | scalar int/float/char literal | `sf/src/async_frame_layout.zig:41` `const INVALID: u32 = 0xFFFFFFFF;` (60 hex-literal int consts, e.g. `sf/src/std_rand.zig:20-21`, `examples/z98/z9play/ogg.zig:89`); float: 19 (`examples/z98/z9play/decode.zig:100` `PI_BITS` is int-bit-pattern, float consts e.g. in std_math use) | **no C symbol** — folded at use (`main.zig:966-975` kind test; `lower.zig:5038-5057` use-site literal fold) | `static const T name = <lit>;` (rodata) + use-site folding kept |
| S2 | scalar bool literal | `examples/z98/rogue_mud/main.zig:15` `const MULTIPLAYER_ENABLED: bool = false;` (7 total) | `.bss` + dead `__module_init` store ▸ (`bool_literal` not in `main.zig:971` kind test); some uses fold via if-condition folding (`main.zig:698+`) | `static const T name = 0/1;` |
| S3 | scalar constant-expression (`3+4`, `@intCast(u8,0)`, `-10`, `64*1024`, `a+1` for const `a`) | `sf/src/async_state_machine.zig:49-54` (`@intCast` forms), `examples/z98/z9play/platform/audio_win9x.zig:68-69` `STD_INPUT_HANDLE: i32 = -10`, `examples/z98/z9play/platform/audio_wavfile.zig:30` `ARENA_BUF: usize = 64 * 1024`, `repro/mi_matrix` (103 ARITH + 117 BUILTIN_EXPR class) | `.bss` + `__module_init` folded assign `= (unsigned int)(7);` ▸ (`main.zig:966-1004`, fold at `main.zig:686-697`) | `static const T name = <folded>;` |
| S4 | 1-D array of scalars (`[_]T{...}` / `[N]T{...}`) | `sf/src/std_cipher.zig:468` `RCON`, `:470` `SBOX`, `:489,:524,:559,:594` `Te0..Te3` (the M2 trigger); `sf/src/std_zstd.zig:31-85` (LL/ML base/bits/default tables); `sf/src/std_pathfind.zig:373-374`, `sf/src/std_hpa.zig:67-68` `DIR_DX/DY`; `repro/mi_matrix/stdlib_lz4_basic_xmod/main.zig:85-402` (12 tables), `stdlib_zstd_basic_xmod/{main.zig,vectors_data.zig}` (11 tables), `stdlib_pathfind_plus_xmod/main.zig:9` | `.bss` + `emitArrayCopyLoop` in `__module_init` ▸ (`c89_emit.zig:3898-3918`) | `static const zT_ArrN name = { e0, e1, ... };` |
| S5 | multi-D array | **none at file-scope in the four trees** (probe-only shape; local `var` multi-D exists, e.g. `sf/src/type_resolver.zig:1870`) | `.bss` + `emitArrayByteCopyLoop` ▸ (`c89_emit.zig:3921-3933`) | `static const zT_Arr2x2 name = { { .. }, { .. } };` |
| S6 | struct init (named/positional) | `repro/mi_matrix/stdlib_print_tuple_fwd_ok_xmod/main.zig:109,116` `Pair{ .a = 1, .b = 2 }`, `stdlib_print_unrelated_ident_xmod/main.zig:21` `Config{ .print = 3 }` | `.bss` + field stores into temp + struct copy ▸ | `static const zT_Pair name = { 1, 2 };` (C89 positional, field decl order) |
| S7 | tuple / anonymous agg `.{...}` | `repro/mi_matrix/stdlib_print_aggregate_xmod/main.zig:53` `.{ 33, 44 }`; `stdlib_const_decay_ok_xmod/main.zig:35-36` | `.bss` + init + copy ▸ | `= { 33, 44 };` positional |
| S8 | struct init referencing other consts (decay/address) | `repro/mi_matrix/stdlib_const_decay_ok_xmod/main.zig:35` `gh: Holder = .{ .m = garr }` (slice field ← const array), `:36` `gmh: ManyHolder = .{ .mp = &garr }` (many-ptr ← `&const arr`); `stdlib_const_field_decay_ok_xmod/main.zig:32` `gs: S = .{ .a = garr }` (array field ← const array) | `.bss` + runtime slice/ptr build + copy ▸ (`t1ci_decay` probe: `zT_8.ptr = zG_garr; zT_8.len = 3; zG_gc = zT_8;`) | `= { (T*)zG_garr, 3 };` / `= { (T*)zG_garr };` / `= { { 1, 2, 3 } };` — all C89 address/aggregate constants |
| S9 | slice/many/ptr const from const array | `stdlib_const_decay_ok_xmod/main.zig:31-32` `gc: []const i32 = garr`, `gcm: [*]const i32 = garr` | `.bss` + module_init ▸ | `= { (int*)zG_garr, 3 };` / `= (int*)zG_garr;` |
| S10 | string literal → `[]const u8` slice | `sf/src/main_dump.zig:199-221` (24 CLI-flag slices), `examples/z98/z9play/tests/*.zig:33-39`, `repro/mi_matrix/module_value_*_xmod/leaf.zig:10` `pub const BUF: []const u8 = "hi"` (12 leafs), `stdlib_const_decay_ok_xmod/main.zig:33` | `.bss` + module_init slice build ▸ | `= { (u8*)"abc", 3 };` (slice typedef `struct { T* ptr; unsigned int len; }`, `zig_special_types.h` e.g. `zT_AA143F04_Slice…`) |
| S11 | string literal → many/ptr | `stdlib_const_decay_ok_xmod/main.zig:34` `gstrp: [*]const u8 = "abc"`; probe `const str = "hello"` (`unsigned char*`) | `.bss` pointer + module_init `= "hello";` ▸ | `static unsigned char *const name = (unsigned char*)"hello";` |
| S12 | `[N]u8 = "string"` (array from string literal) | **none in the four trees** (probe-only) | **INVALID C89 today** ▸ (`zG_arr = zT_35;` array assignment, gcc error) | `static const unsigned char name[N] = "string";` (valid C89) |
| S13 | union init (first-member active) | **none at file-scope in the four trees** (probe `U1{ .a = 7 }`) | `.bss` + field store + copy ▸ | `static const zT_U name = { 7 };` |
| S14 | union init (NON-first-member active) | **none** (probe `U1{ .b = 5 }`) | `.bss` + `zT_0.b = 5; copy` ▸ | **NOT representable as one C89 constant initializer** → STOP-1 |
| S15 | tagged-union const (tag-only payload) | **none at file-scope** (probe `Cell{ .Dead = {} }`) | `.bss` + `zT_0.tag = 0; copy` ▸ (C type is `struct { tag; … }`) | `= { tag_val, … };` when payload is empty/first-member |
| S16 | tagged-union const w/ payload member ≠ first | **none** (probe) | `.bss` + field store ▸ | STOP-1 (nested union rule) |
| S17 | optional/error-union const, constant payload | probe `const o1: ?u32 = 5` — folds at use, **no symbol** ▸ | folded at use (init is `int_literal` → `main.zig:971` skip) | scalar-literal path unchanged (S1); non-literal `?T`/`E!T` constant payloads are struct/union inits → S6/S13 rules |
| S18 | const referencing other const (scalar value chain) | probe `const ref_other: u32 = scalar_lit + 1` | `.bss` + `__module_init` `= (unsigned int)(8);` (folded ▸) | `static const T name = 8;` (fold via `comptime_eval`) |
| S19 | non-constant const initializer (var read / call) | probe `const nonconst: u32 = runtime_x + 1` | `.bss` + runtime `__module_init` ▸ | **unchanged**: `.bss` + `__module_init` |
| S20 | `const` with `undefined` init | none found in trees | `.bss`, `has_runtime_init=0` (zero-filled, `main.zig:993-994`) | unchanged `.bss` (not a value; cannot be a constant initializer) |
| S21 | fn-pointer in aggregate const | none at file-scope found | n/a | C89 address constant (`&fn`) — representable |
| S22 | empty array `[_]u32{}` | none (probe: degenerate, `empty.len` mis-typed `int` ▸) | broken/degenerate today | **out of scope** (see Lateral L8) |
| S23 | partial init `[4]u32{1,2}` | none | n/a (Z98 rejects or infers; not exercised) | if accepted: `{1,2,0,0}` C89 zero-fills remainder — matches; untested, see Lateral L9 |
| S24 | C-side reference tables (`scripts/stdlib/ref`) | `scripts/stdlib/ref/std_lz4/ref.c:1301-1302` `static const unsigned inc32table[8]`, `:1462` `ctz7_tab[128]`, `:1095` scalar `static const int` | already `static const` (reference C, crosscheck side) | **unchanged** (in-tree proof the target form is accepted by the same gcc/mingw/watcom toolchains) |

Counts by shape across the trees (value consts only, first-line classification):
`ARRAY_INIT` 55, `STRING` 38 (24+ slices, rest `[]const u8`/ptr), `INT_LIT`
360 + 60 hex, `FLOAT_LIT` 19, `CHAR_LIT` 1, `BOOL_LIT` 7, `ARITH_EXPR` 103,
`BUILTIN_EXPR` 117, `NAME_REF` 30 (const-to-const refs/aliases), `AGG_INIT` 3,
`ANON_AGG` 5. The big `ARRAY_INIT` sites are std tables + lz4/zstd fixtures;
they are exactly the M2-relevant rodata win.

Probe evidence for "today" column (representative, `t1ci_probe1` — full emitted
C captured under `/tmp/t1ci_probe1/out/`):

```
/* definitions (main_38598F0B.c:2-14) — ALL .bss */
unsigned int zG_3C802431_scalar_expr;
unsigned char zG_F01B522A_scalar_bool;
zT_989EF0DF_Arr_unsigned_int_4 zG_8693C83D_arr1d;
zT_95DDFB73_Arr_zT_969EEDB9_Arr zG_A496360E_arr2d;
unsigned char* zG_C24BD190_str;
zT_EAA8EF31_Point zG_A04ED67A_p1;
...
/* __module_init (main_38598F0B.c:210-331) */
zG_3C802431_scalar_expr = (unsigned int)(7);       // S3: folded assign
zG_F01B522A_scalar_bool = (unsigned char)(1);      // S2
{ unsigned int _i = 0; while (_i < 4) { zG_8693C83D_arr1d[_i] = zT_3[_i]; _i++; } }   // S4
{ unsigned int _i = 0; while (_i < sizeof(zG_A496360E_arr2d)) { ((unsigned char*)&zG_A496360E_arr2d)[_i] = ((unsigned char*)&zT_21)[_i]; _i++; } }  // S5
zT_34 = "hello"; zG_C24BD190_str = zT_34;          // S11
zG_6C707680_str_arr = zT_35;                       // S12 — INVALID C89 (gcc error)
zG_A04ED67A_p1 = zT_36;                            // S6
zG_0B7BEE53_ref_other = (unsigned int)(8);         // S18
zG_E10AE5FF_nonconst = zT_61;                      // S19 runtime
```

Use-site behavior today (same probe, `main` fn): S1 literal consts fold
(`printU32((unsigned int)(7))`, `printF64((f64)(1.5e+0))`, `printU32((unsigned
char)(65))`); S3/S4+ load globals (`printU32(zG_3C802431_scalar_expr)`,
`zT_11 = zG_8693C83D_arr1d[zT_8]`). This split is the current kind-test debt
and is removed by the design (§3) in classification only — use-site emission is
untouched.

---

## 2. Complete data-flow trace (Step 2)

### 2.1 Parser flags

`sf/src/parser.zig:1701-1746` `parserParseVarDecl`:
`flags` bit0 (0x01) = `is_mutable` (`var`), bit1 (0x02) = `is_pub`, bit2
(0x04) = `is_extern`, bit3 (0x08) = `is_export`. `const` = bit0 clear. Node:
`astStoreAddNode(store, AstKind.var_decl, flags, …, type_node, init_node, 0,
name_id)` — `child_0`=type node, `child_1`=init node, payload=name id
(`parser.zig:1743-1745`). Immutable decls with init also register a parse-time
const-alias entry (`parser.zig:1739-1742`).

### 2.2 Symbol registration

`sf/src/symbol_registrator.zig:337-343`: `Symbol{ .flags = node.flags, … }` —
symbol flags = var_decl flags verbatim. Kind `global` for value decls; type
decls become `type_alias` (`symbol_registrator.zig:320-337`,
`const_alias_prepass.zig:187`). Predicates in `sf/src/lower.zig:4235-4247`:
`symbolIsConstGlobal` = kind global ∧ flags bit0 clear.

### 2.3 Global-decl collection (the root-cause loop)

`sf/src/main.zig:931-1010` (module-root decl walk inside the marker/phase
loop), specifically `main.zig:960-1006`:

- `main.zig:961`: skip `extern` (flags & 0x04).
- `main.zig:965-975` `gv_is_storage`: set for `var` (flags bit0), or for
  `const` whose init kind ∉ {`int_literal`,`float_literal`,`char_literal`}
  (this is the known root cause; `bool_literal`/`string_literal`/aggregates
  all fall in).
- `main.zig:976-984`: un-set for `import_expr` and `field_access` of
  `import_expr` (module identity / type-alias inits — no C storage).
- `main.zig:987-990`: export flag recorded in `ctx.exported`.
- `main.zig:991-995` `gv_has_ri`: 1 iff init exists ∧ init kind ≠
  `undefined_literal`.
- `main.zig:996`: `gv_has_ri` ⇒ `mod_has_ri` (drives `lowerModuleInit`).
- `main.zig:997-1004`: `ModuleGlobalDecl{ name_id, module_id, type_id =
  resolvedTypeTableGet(decl_idx), has_runtime_init = gv_has_ri }` appended.
- `main.zig:1012-1018`: if `mod_has_ri`, `lowerModuleInit(...)` produces the
  `__module_init` LIR function for the module.

### 2.4 `ModuleGlobalDecl` representation

`sf/src/lir.zig:577-582`:
```zig
pub const ModuleGlobalDecl = struct {
    name_id: u32, module_id: u32, type_id: u32, has_runtime_init: u8,
};
```
Array container `GlobalDeclArrayList` `lir.zig:584-634` (sand-allocated,
`@sizeOf(ModuleGlobalDecl)` stride — any field addition moves the stride at
`lir.zig:608-617`). No const bit, no initializer payload. Consumers:
`c89_emit.zig:606` (`global_decls: [*]lir_mod.ModuleGlobalDecl` + len),
`main.zig:1467` (runtime-init scan), `c89_emit.zig:2446-2452`.

### 2.5 `lowerModuleInit` (initializer lowering)

`sf/src/lower.zig:9529-9730`:
- Candidate filter `lower.zig:9551-9584`: `var_decl`, not extern, has init,
  symbol kind global, init ∉ {`undefined_literal`,`import_expr`,
  struct/enum/union/error_set `*_decl` (type decls), `field_access` of import,
  import-alias-shaped (`lowerInitIsImportAliasShaped`)}, and for `const`
  (flags bit0 clear) init ∉ {`int_literal`,`float_literal`,`char_literal`}
  (`lower.zig:9581-9583` — the same kind test as `main.zig:971`, duplicated).
- Dependency walk `lower.zig:9605-9705`: iterative DFS over `lowerInitDepScan`
  edges (same-module name refs order candidates; cross-module refs record
  module-dep edges into `ctx.module_init_deps`, `lower.zig:336` comment,
  consumed by `main.zig:1359-1382` `phase_LIRLowering` to order
  `ctx.module_init_order`, `main.zig:1099-1139`); cycles → `error[3064]`.
- Emit: `lowerExpr(init)` then `store_global` per candidate
  (`lower.zig:9711-9721`).

### 2.6 `store_global` emission and copy loops

- LIR opcode `lir.zig:106` `store_global { name_id, module_id, value }`.
- Emitter `c89_emit.zig:6655-6693` (function body) and
  `c89_emit.zig:3456+` (alternate emit path): array-typed target with
  non-array elem → `emitArrayCopyLoop` (`c89_emit.zig:3898-3918`,
  `dst[_i] = src[_i]` loop); array-of-array target →
  `emitArrayByteCopyLoop` (`c89_emit.zig:3921-3933`, byte loop over
  `sizeof(dst)`); scalar/struct → `name = value;` or struct copy.
- `load_global` emission: `c89_emit.zig:6647-6653` — only aliases the result
  temp to the mangled C name in `temp_global_map` (`c89_emit.zig:599`,
  pre-scan `c89_emit.zig:8319-8334`); no code. Uses render the name.
- `addr_of` emission: `c89_emit.zig:6876-6885` `result = &op;` (operands that
  alias globals render `&zG_…`, incl. `&zG_x[i]` forms).

### 2.7 Definition / extern-decl emission

- `emitGlobalExternDecls` `c89_emit.zig:2135-2195` — shared by header
  (`want_extern=1`, `emitModuleHeaderFile` `c89_emit.zig:2294`) and body
  (`emitGlobalDecls` `c89_emit.zig:2442-2444`, `want_extern=0`; multi-file
  `emitModuleFile` `c89_emit.zig:2427-2439`, single-file `emitModule`
  `c89_emit.zig:2348`). Emits `extern T name;` (header) or `T name;` (body —
  a C89 **tentative definition**, i.e. `.bss`). No `const`, no initializer,
  no linkage split. The type-synonym tail (`c89_emit.zig:2173-2194`) is
  unrelated (type-alias globals).

### 2.8 `__module_init` / `has_runtime_init` / ordering

- `moduleHasRuntimeInit` `c89_emit.zig:2446-2452`: any decl of the module with
  `has_runtime_init != 0`.
- `emitModuleInitCalls` `c89_emit.zig:2455-2481`: walks `module_init_order`
  (dependency-ordered module ids from §2.5), skips unreachable under
  `prune_active`, emits `__module_init();` per module having runtime init,
  into the `main` wrapper (`c89_emit.zig:2407`).
- Wrapper calls: `c89_emit.zig:2396-2441` (single-file `main`) /
  multi-file equivalents; always `__module_init(); user_main();`.

### 2.9 Header externs

`emitModuleHeaderFile` `c89_emit.zig:2199-2302` emits
`/* Storage globals (extern decls) */` via `emitGlobalExternDecls(...,
want_extern=1)` (`c89_emit.zig:2292-2294`) — every module global, including
non-`pub` ones (probe `t1ci_xmod`: `extern zT_… zG_…_hidden_tbl;` appears even
though cross-module reference to it is rejected by pub enforcement — error at
`lib.zig:1` note).

### 2.10 Const use-site lowering (why some consts have no symbol)

`sf/src/lower.zig:5018-5060` (ident arm of `lowerExprImpl`): for a
`symbolIsConstGlobal` whose init kind ∈ {`int_literal`,`float_literal`,
`char_literal`} it materialises a literal temp and never emits `load_global`
(the fold). All other const globals (incl. `bool_literal`, `3+4`,
aggregates) fall through to `lowerGlobalRef` `lower.zig:4259-4273` →
`load_global` (`lower.zig:4270`). Separately `phase_ComptimeEvaluation`
`sf/src/main.zig:648-697` folds const initializers of op kinds 33-42, 62, 64
(`add..shr`, `negate`, `bit_not` — `sf/src/ast.zig:35-74`) into
`ctx.comptime_folds` keyed by the **init node**; `lowerExpr` consults the
table (`lower.zig:3783-3790`, `lower.zig:1807-1810`). Three overlapping kind
tests (`main.zig:971`, `lower.zig:9583`, `lower.zig:5038-5057`) define
today's inconsistent classification; the design replaces all three with one
predicate (§3.1).

### 2.11 Cross-module facts (probe-verified)

- `pub const K: u32 = 42` used from another module: folds at use in the
  importer (`printU32((unsigned int)(42))`), **no symbol anywhere** — so pub
  scalar literals currently have no C address.
- `pub const KE: u32 = 40 + 2` used from another module: `load_global` →
  `extern unsigned int zG_KE;` + `.bss` def + `__module_init` assign in the
  owner TU (`t1ci_xsc` probe).
- Non-`pub` const referenced cross-module: rejected (error + `lib.zig:1`
  note), so `static` linkage for module-private consts is safe.
- `&mod.global` (module-value address) works via `load_global`+`addr_of`
  (`repro/mi_matrix/module_value_addr_global_xmod/main.zig:1-40` comments +
  `sf/src/lower.zig:2531-2543`).

---

## 3. Exact design (Step 3)

### 3.1 One classification pass — `sf/src/const_init_eval.zig` (new)

New module (single purpose, no tech debt): evaluates a file-scope `const`
initializer to a **constant-init tree** or reports "not constant". Reuses
`sf/src/comptime_eval.zig` scalars (`ComptimeVal`, `comptimeEvalEvaluate` —
already folds arith/bitwise/shift/neg/not on int/bool/float and resolves
const refs, `comptime_eval.zig:19-40`, `main.zig:686-697` precedent) and adds
the aggregate walk. No recursion: flat pools, explicit stack (repo style —
cf. `lowerModuleInit`'s iterative DFS).

```zig
// lir.zig (or const_init_eval.zig): flat constant-init tree
pub const ConstInitKind = enum(u8) {
    zero,        // omitted / zero-fill
    int_val,     // a = ComptimeInt pool idx OR inline u64 + b = wide flag (FoldVal pattern, comptime_eval.zig:63-72)
    float_val,   // a = f64 bits
    bool_val,    // a = 0/1
    char_val,    // a = u8
    string_addr, // a = interned str id (address of C string literal)
    global_addr, // a = name_id, b = module_id, c = type_id of the target global (decay/&/slice-of forms flattened by the renderer)
    fn_addr,     // a = fn name_id, b = module_id
    agg,         // array/struct/tuple/union composite: children = [child_start, child_start+child_count)
};
pub const ConstInitNode = struct { kind: u8, a: u32, b: u32, c: u32, child_start: u32, child_count: u32 };
```

Evaluation rules (`constInitEvaluate(store, registry, symbol_reg, ce, decl_idx) ?u32`
returns root index; `null` = non-constant):

- scalars: literals; `paren_expr`/`negate`/`bit_not`/`bool_not`/binops
  (`ast.zig:33-50`) over constants; `@intCast`/`@truncate`/comptime-cast
  builtins already folded by `comptimeEvalEvaluate`; `ident_expr` to a
  `symbolIsConstGlobal` whose own tree/fold resolves — value-copy (S18);
  `enum_literal` → tag int.
- `array_init`: every element constant → `agg` of children (repeats `[_]T{x}`
  length inference uses the resolved type, never AST shape).
- `struct_init`/`tuple_literal`/anonymous `.{`: every field constant → `agg`
  with children **reordered to the type's field declaration order**
  (`type_registry` field entries) because C89 initializers are positional.
- `string_literal`: `string_addr` (renderer picks pointer vs char-array form
  from the resolved type — S10/S11/S12).
- `address_of`/decay of a **global** (const or var — C89 address constants
  may name any static/extern object): `global_addr` (S8/S9). `address_of` of
  a function: `fn_addr` (S21).
- `undefined_literal`, `null_literal` (only as pointer-valued 0), calls,
  runtime loads of `var` **by value**, `@import` shapes, blocks/ifs with
  non-constant conditions: `null` (→ runtime path). A comptime-`if`/
  `switch` with fully constant condition folds via `comptime_eval` first.
- unions: first-member-active → `agg` of 1 child; **non-first-member-active →
  `null`** (STOP-1: not a C89 constant initializer; stays `.bss` +
  `__module_init` exactly as today — a representability boundary, not a
  classification shortcut). Same for tagged-union payload unions (S16).

Call sites (both must use this one predicate — the three kind tests of §2.10
are deleted):

1. `main.zig:965-1004` — replace the `gv_is_storage` literal-kind test with
   `constInitEvaluate(...)`: const ∧ tree ≠ null ⇒ `gv_is_storage = 0`,
   `has_runtime_init = 0`, decl recorded with `const_init = tree_root`;
   const ∧ tree = null ⇒ today's `.bss` path (`has_runtime_init` per
   `main.zig:991-995`); `var` ⇒ today's path, `const_init = NONE`.
2. `lower.zig:9581-9583` — skip module-init candidates whose decl has a
   constant tree (consult the same result: `LirLowerer` receives the
   decl→tree map built in `phase_ConstInit`; **never** a second evaluator).
3. `lower.zig:5038-5057` — use-site literal fold: extend the kind test to
   "decl has a constant tree AND the tree is a scalar int/float/bool/char
   val" so scalar literal/constant scalars keep folding exactly as today
   (bool gains the fold it half-had; behavior for int/float/char unchanged).
   Aggregates keep `load_global`. No use-site text churn for S1.

Resulting storage matrix:

| class | storage | `__module_init` entry | header extern |
|---|---|---|---|
| `var` | `T name;` (.bss) | yes (if init) | `extern T name;` |
| const, non-constant init | `T name;` (.bss) | yes | `extern T name;` |
| const, `undefined` init | `T name;` (.bss) | no | `extern T name;` |
| const, constant tree, private | `static const T name = <init>;` | **no** | **none** |
| const, constant tree, `pub`/`export` | `const T name = <init>;` | **no** | `extern const T name;` |

### 3.2 `ModuleGlobalDecl` representation

```zig
pub const ModuleGlobalDecl = struct {
    name_id: u32,
    module_id: u32,
    type_id: u32,
    has_runtime_init: u8,
    const_init: u32,   // 0xFFFFFFFF = none; else root idx into the ConstInit pool
    link_visible: u8,  // 1 = pub|export (external linkage); 0 = module-private
};
```

- Stride change is contained to `lir.zig:584-634` (`globalDeclArrayList*`,
  sand alloc stride `@sizeOf(...)`) and the two construction/consumption
  sites (`main.zig:997-1004`, `c89_emit.zig:2135-2195` / `:2446-2452`).
- The ConstInit pool lives next to `comptime_folds` (`main.zig:119`,
  module-arena) and is handed to the emitter alongside `global_decls`
  (`c89_emit.zig:606` context fields). `link_visible` comes from decl flags
  bit1|bit3 (`parser.zig:1711-1714`). Type-only/import decls never enter
  `global_decls` (unchanged).

### 3.3 C89 rendering (`sf/src/c89_emit.zig`)

New `emitConstInitValue(emitter, node_idx, type_id, depth)` (iterative or
depth-limited recursive; trees are bounded by source nesting) used only from
the global-definition path. Text forms (all gcc `-std=c89 -pedantic`-proven,
probes `t1ci_c89*`; zero warnings with exact casts):

| tree | C89 text |
|---|---|
| `int_val` | decimal/hex with the existing literal style; prefer a typed cast `(unsigned int)(7)` matching `__module_init` folds today (a cast of an arithmetic constant is a C89 constant expression) |
| `float_val` | existing float literal rendering (`1.5e+0` style, `c89_emit.zig` float-const path) |
| `bool_val` | `0` / `1` (`bool` = `int`, `zig_compat.h:65`) |
| `char_val` | integer (same as `int_val` of the char code) |
| `string_addr`, target `*const`/`[*]const`/`[]const` ptr | `(unsigned char *)"…"` via `emitCStringLiteral` (`c89_emit.zig:5846`) — cast to the exact pointer type |
| `string_addr`, target `[N]u8`/`[N:0]u8` | `"…"` (C89 string-initializes char arrays) |
| `global_addr`, target pointer/many | `(T *)zG_target` (array decay is automatic; cast to exact pointee/qualifier of the field) |
| `global_addr`, slice target | two-element positional `{ (T *)zG_target, LEN }` (`len` from the resolved slice/array type) |
| `agg` of array type | `{ e0, e1, … }` (omit trailing zeros optional; simpler: always full) |
| `agg` multi-D | nested `{ { … }, { … } }` per array-type depth |
| `agg` of struct/tuple | positional `{ f0, f1, … }` in field-declaration order; omitted Zig fields → `0`/`{0}` zero-fill |
| `agg` of union (first member) | `{ v }` (only shape allowed; STOP-1 otherwise) |
| `agg` of tagged-union | `{ tag, { payload } }` (struct layout `c89_emit.zig` `emitTypeDefinition` tagged-union struct; payload sub-tree obeys the union rule) |
| `zero` | `0` or `{ 0 }` per type |

Definition emission — extend `emitGlobalExternDecls` (`c89_emit.zig:2135`)
with the `const_init` branch (both `want_extern` values):

- body (`want_extern=0`): `static const T name = <init>;` (private) /
  `const T name = <init>;` (visible) — **replacing** the tentative
  `T name;`. Keep today's `T name;` for the non-constant rows of the matrix.
- header (`want_extern=1`): `extern const T name;` for visible consts;
  **skip** private constant consts entirely (a `static` definition in the
  owner TU must not be preceded by a conflicting `extern` declaration — the
  owner's `.c` includes its own header, `c89_emit.zig:2427-2431`).
  Today's "declare every global in the header" behavior is kept for the
  non-constant rows (no behavior change there).
- single-file mode (`emitModule`, `c89_emit.zig:2348`): same body forms;
  `all=1` already emits one definition per global before any function
  (`emitGlobalDecls` before `emitFunctionSet`), so `static` ordering is safe.

Linkage rationale: `static` for module-private is safe (pub enforcement
rejects cross-module use of non-`pub`, probe §2.11) and yields `nm` `r`;
`pub`/`export` keep external linkage (`R`) with `extern const` headers.
(If the operator prefers zero linkage change, the fallback variant is
"external `const` for everything" — still rodata `R`, one-line simpler
headers — but the brief's `static const` wording and the `R/r` gate wording
match the split design above.)

Qualifier-discard prevention (C89 conformance): any emitted borrow of a
`const`-qualified global into an unqualified pointer gets an **explicit cast
to the destination pointer type** at exactly three renderers:
`addr_of` (`c89_emit.zig:6876-6885`, wraps `&op`/`&name[i]`),
`make_slice` ptr operand (`c89_emit.zig:7614` body path; type-side
`:2804`), and the
`global_addr` initializer form above. Rationale: Z98 rejects writes through
such loans (`ERR_3002`, probe `t1ci_cw`: `x = 5;` and `a[0] = 7;` both
rejected), so removing the qualifier in the emitted loan is
semantics-preserving; the alternative (const-propagating pointee types
through the whole type registry) is unbounded and rejected as scope creep.

### 3.4 `__module_init` / `store_global` skip rules

- Constant-tree decls produce **no** `store_global` and no module-init
  candidate (`lower.zig:9581-9583` extended per §3.1). Their
  `emitArrayCopyLoop`/`emitArrayByteCopyLoop` traffic disappears.
- `has_runtime_init` for these decls is 0 (`main.zig:991` region), so
  `moduleHasRuntimeInit` (`c89_emit.zig:2446`) naturally stops emitting their
  module's `__module_init()` call when the module's only globals were
  constant consts (`emitModuleInitCalls` `c89_emit.zig:2455-2481` unchanged).
  Const-only modules lose their `__module_init` symbol entirely (expected nm
  movement; wrapper still calls nothing for them).
- `mod_has_ri` (`main.zig:996`, `:1012-1018`) unchanged in logic; fewer
  modules qualify.
- Module-init **ordering** (`main.zig:1099-1139`, `:1359-1382`) unchanged:
  constant consts create no `store_global`/`load_global`-at-init edges.
  Cross-module address constants need no C-level order (C89 address
  constants may name any static/extern object regardless of TU order).
- Dependency ordering of const→const **values** is solved at compile time by
  the evaluator (§3.1 `ident_expr` rule): values are folded into literals,
  so there is no C-level ordering problem. A const cycle of value refs
  evaluates to `null` and falls to the runtime path, where the existing
  `ERR_3064` check (`lower.zig:9668-9680`) still fires — unchanged.

### 3.5 Non-constant `const` stays `.bss`

Exactly today's path: `T name;` tentative def + `__module_init`
`store_global` (scalar assign / `emitArrayCopyLoop` / `emitArrayByteCopyLoop`)
+ `extern T name;`. No `const` keyword added (the object is mutated at init).

### 3.6 C89 validity evidence (probes `/tmp/t1ci_c89*.c`, gcc `-std=c89 -pedantic -Wall -Wextra`)

- `static const` scalars/1-D/2-D/typed-alias arrays/union-first-member → `nm`
  `r` + `.rodata`. Zero warnings.
- Address-bearing consts (slices/pointers to strings or static objects) → `nm`
  `d` + `.data.rel.ro` on ELF (relocation required; `readelf -S` shows
  `.data.rel.ro` PROGBITS, not `.bss` NOBITS). On PE/COFF (mingw/MSVC6/Watcom
  targets) they land in `.rdata` (`R`). **Gate consequence:** value-only
  consts assert `R/r` exactly (this is the M2 T-table requirement);
  address-bearing consts assert "not `B/b`, not `.bss`/COMMON" and accept
  `R/r/D/d` (§5).
- Pointer casts of address constants in static initializers
  (`(unsigned char*)"abc"`, `(int*)zG_arr`) compile warning-free when the cast
  matches the destination pointer type exactly (probe `t1ci_c89c.c`).

---

## 4. Blast radius (Step 4)

### 4.1 Emitted-construct movement

| construct | movement |
|---|---|
| constant-init const defs | tentative `T name;` → `static const`/`const T name = <init>;` |
| their `__module_init` blocks | deleted (scalar assigns + array/byte copy loops) |
| `__module_init` presence | gone for const-only modules; shrinks for mixed modules |
| headers | private constant consts dropped from extern block; visible ones become `extern const T name;` |
| use sites (S1 literal scalars) | **byte-identical** (fold preserved) |
| use sites (S2-S19) | **byte-identical** (load_global / field / index rendering untouched) |
| `addr_of`/`make_slice` of const globals | + explicit `(T*)` cast |
| var / non-constant const | byte-identical |
| `zig_special_types.h` typedefs | unchanged (no type-registry change) |

### 4.2 Gates / pins / corpus

- **Corpus frozen-1124 class file** (`scripts/corpus/classify`; md5
  `518eca1a9b5d3e1cc5a48abce214abd8`, 950 OK / 58 GREEN / 116 FAIL): expected
  **0 movers** — the fix changes storage class + removes init code but every
  emitted-C compile class is preserved (S12/S22 broken shapes are absent from
  the corpus; §1). If any FAIL class turns OK (a currently-broken emitted C
  becomes valid) that is a **mover** → STOP-2 procedure: record and seek
  operator ruling, do not silently accept.
- **8 `--dump-c89` md5 pins** (`docs/sf/QUICK_REF.md` §"8-pin table"): **all 8
  move** (every entry has file-scope consts; `.bss`→`static const` + module
  init removal changes the bytes). Battery rule already allows this: "pins
  recorded old→new (MAY move — operator-approved)".
- **z9play `--dump-c89` pins** (QUICK_REF z9play notes): move likewise.
- **Runtime goldens 5/5** (gol, lisp, json, mud×2): byte-identical required —
  values unchanged, only storage.
- **mi_matrix 25+oob / `scripts/stdlib/run_fixtures.sh`**: stdout/rc goldens
  byte-identical. `stdlib_const_decay_ok_xmod` /
  `stdlib_const_field_decay_ok_xmod` / `module_value_*` fixtures exercise the
  S8-S10 shapes and are the de-facto runtime proof.
- **`verify_stdlib.sh` (285/0 class) + `run_crosscheck.sh`**: unchanged
  outputs (Z98 tables vs `scripts/stdlib/ref` C — the ref C is already
  `static const`, §1 S24).
- **examples 26/26 build+run**: unchanged stdout; z9play/rogue boolean consts
  and string-slice consts re-render.
- **markers / `check_emit_support.sh`**: no change (support-file bytes not
  touched; markers unaffected).
- **Compiler self-emission**: **yes, changes** — the compiler's own C89 self
  dump (`sf/src` const tables e.g. `c89_emit.zig:145` `GLOBVAR_MAX_STACK_ARRAY_BYTES`,
  `main.zig`/`main_dump.zig` string-slice consts, all `const S_HELP = "…"`
  slices) emits `static const` — self-compile is part of seed two-hop; both
  hops must still converge.

### 4.3 Seed version consequence (M2)

- `scripts/seed/archive_seed.sh` embeds a 40-file lib copy list
  (`archive_seed.sh:31-39`, counts at `:166,:178,:318`); `std_cipher`/
  `std_ecc` are not in it yet (Task 4 adds them → 42).
- Global Constraints: "Task 1C-F is a compiler fix → full compiler battery +
  seed rotation". Task 4: "Closeout rotates seed **v112** (42 lib files);
  fixed point `21c95773…` must not move."
- **Consequence / assignment:** 1C-F rotates seed **v112** = compiler fix +
  unchanged 40-file copy list; fixed point **moves** off
  `21c957730d268f1e7883176fa5413b65` (record new archive/manifest/binary/
  fixed-point; hop1==hop2 required). Task 4 closeout then rotates seed
  **v113** = +`std_cipher` +`std_ecc` (42 lib files), whose fixed point must
  equal v112's (that is the sense of "must not move" — re-anchor the plan
  text from `21c9…` to the 1C-F fixed point). Plan edits needed at Task 4
  step 3 + Global Constraints (version/anchor truth-up) — performed by the
  respective tasks, not by 1C-I.
- Alternative (single rotation at Task 4, v112=42 files incl. the compiler
  fix) contradicts the explicit "1C-F … + seed rotation" constraint;
  rejected unless operator overrides.

### 4.4 No-contradiction check against plan

Plan Task 1C-F files list (`lir.zig`, `main.zig`, `lower.zig`, `c89_emit.zig`)
covers §3 change sites exactly; the only addition is the new
`const_init_eval.zig` (justified: no existing pass owns aggregate const-init
evaluation; putting it in `comptime_eval.zig` would couple scalar folding to
emission-tree building). No `std.zig`, example, or unrelated-pass change is
required. STOP-1 is the only plan-text tension ("structs/unions" vs C89
first-member rule) and is reported, not silently dropped.

---

## 5. Test strategy (Step 5) — committed, non-vacuous

### 5.1 Value fixture (runtime)

Create `repro/mi_matrix/stdlib_const_rodata_xmod/{main.zig,expected.txt,expected.rc}`
(pattern: existing `stdlib_const_decay_ok_xmod`). Covers:
scalar-expr const (S3), 1-D table (S4, e.g. a 256-entry u32 table mirroring
T-table shape), multi-D (S5), struct (S6), tuple (S7), struct-of-slice (S8),
slice-of-const-array (S9), string slice (S10), string ptr (S11), nested
array-of-struct-with-array (S18-style ref chain), and a non-constant const
(S19) whose value is computed at `__module_init` and must still be correct.
3× determinism via harness. Asserts byte-exact stdout.

### 5.2 Section-type gate (the non-vacuous core)

Create `scripts/compiler/gate_const_rodata.sh` (new dir mirroring
`scripts/check_emit_support.sh` style; wired into the battery). It:
1. compiles two probe programs (committed as
   `repro/mi_matrix/const_rodata_gate/{value_shapes.zig,runtime_shapes.zig}`)
   with the compiler under test + `gcc -std=c89 -c`;
2. runs `nm -S` on the objects and asserts, per symbol class:
   - `const` scalar-expr / 1-D array / multi-D array / struct / tuple /
     union-first-member / nested → `R` or `r`, **never** `B`/`b`/`C`;
   - address-bearing consts (slices/pointers) → not `B`/`b`, and
     `readelf -S`/`objdump -h` shows the defining section is not `.bss`;
   - non-constant const + `var` → `B`/`b` (negative case: must remain `.bss`);
   - `undefined`-init const → `B`/`b` (negative case);
3. asserts `__module_init` no longer stores to the const symbols (grep the
   emitted `.c` for `zG_…_Te0[` assignment / `store` patterns = empty) while
   the S19 symbol **is** assigned there (negative of the negative);
4. asserts header text: `extern const` present for `pub` const, absent for the
   private one (`grep`), and the private definition is `static const`;
5. value check: the `stdlib_const_rodata_xmod` fixture run (§5.1).
Non-vacuity mutation requirement (per plan Task 1C-F step 3): with the
emitter's `const_init` branch stubbed to emit `.bss`, gate step 2 must FAIL;
with a non-constant const forced to the const path, the negative case must
FAIL. (1C-F implements both mutations at least once and records output.)

### 5.3 Cross-module fixture

Extend or companion `repro/mi_matrix/module_value_*` style:
`const_rodata_xmod_xmod` variant with a `pub const` table read cross-module +
`&` of a pub const array (exercises `extern const` + `addr_of` cast path).

### 5.4 Full compiler battery (1C-F step 4, unchanged vocabulary)

frozen-1124 class file 0 movers (or operator-recorded), goldens 5/5,
mi_matrix 25+oob (`scripts/stdlib/run_fixtures.sh`), examples 26/26
build+run, `verify_stdlib.sh` full, `run_crosscheck.sh` affected modules +
3× determinism, pins recorded old→new, `--markers` telemetry,
`scripts/check_emit_support.sh` 7/7, seed two-hop hop1==hop2.

---

## 6. Lateral issues (Step 6)

| # | issue | status | reason |
|---|---|---|---|
| L1 | `has_runtime_init` / `mod_has_ri` / `moduleHasRuntimeInit` | **in scope** | §3.4: driven by the shared predicate; no logic rewrite |
| L2 | multi-D initializer syntax (`{{…},{…}}`) | **in scope** | §3.3; probe-proven C89 |
| L3 | struct/tuple positional rendering (C89 has no designated initializers) | **in scope** | field-order remap in the evaluator (§3.1) |
| L4 | string literals (S10-S12) | **in scope** | §3.3; S12 also repairs today's invalid C89 array assign |
| L5 | extern/header declarations | **in scope** | §3.3 header rules; `extern const` + private skip |
| L6 | const-only modules losing `__module_init` | **in scope** | §3.4; nm symbol set shrinks by design |
| L7 | dependency ordering const→const | **in scope** | §3.4: values folded, addresses order-free |
| L8 | empty arrays `[_]u32{}` | **out of scope** | degenerate today (`t1ci_edge2`: type mis-inferred as `int`, `.len` errors); zero occurrences in trees; C89 zero-length arrays are a GCC extension anyway — fix separately under its own defect if ever needed |
| L9 | zero-length/partial initializers | **out of scope** (with rule) | no tree occurrences; if the parser accepts `[4]T{1,2}` the evaluator zero-fills (C89 does this natively) — the rule is specified but no fixture exists; do not invent one in 1C-F |
| L10 | union non-first-member / tagged-union non-first payload (S14/S16) | **STOP-1** | not a C89 constant initializer; specified fallback = keep `.bss` path for that exact shape; 0 tree occurrences |
| L11 | `const x: T = undefined` (S20) | **out of scope** (kept `.bss`) | `undefined` is not a value; freezing `{0}` would invent semantics |
| L12 | bool-literal const today half-folds/half-stores | **in scope** | fixed by §3.1 classification + §3.3 rendering |
| L13 | `const s = "hello"; s[i]` indexing emits invalid C today (`(*ptr)[i]` on `unsigned char*`, `t1ci_probe1` gcc error) | **out of scope** (pre-existing type-model bug) | unrelated to storage class; zero file-scope occurrences in trees that index such a const; do not entangle with 1C-F |
| L14 | empty-union/zero-size payloads, packed structs in const inits | **out of scope** | no occurrences; packed layout initializer rendering would need its own test; reject shape via `constInitEvaluate` returning `null` (safe `.bss` fallback) rather than emitting wrong bytes |
| L15 | `@export`/extern-C consts | **in scope** (rule) | `link_visible=1` row of §3.1 matrix; `export` name mangling untouched |
| L16 | optional/error-union consts with constant payloads (S17) | **in scope** (rule) | render via their struct/union typedefs; non-first union payloads follow L10 |
| L17 | slice `len` for `[*]const` (many-pointer) targets has no len | **in scope** (rule) | many-ptr = single pointer initializer; slice = `{ptr,len}` (§3.3) |
| L18 | const globals taking address of **var** globals in initializers | **in scope** (rule) | C89 address constants may name mutable statics (`&ext_obj` probe) — emit `global_addr` regardless of target mutability |
| L19 | `-Wunused-const-variable` warnings for fold-only scalar symbols | **accepted** | build scripts do not `-Werror`; symbol set is uniform (no DCE pass — that would be the tech debt); size negligible |
| L20 | `@intToPtr`/`@ptrFromInt` consts | **out of scope** | cannot be C89 address constants (integer→pointer); `constInitEvaluate` returns `null` → `.bss` fallback |
| L21 | qualification discard at loans of const objects | **in scope** | explicit casts at 3 renderers (§3.3) |

---

## 7. STOP items

### STOP-1 — non-first-member union const initializer is not a C89 constant initializer

Evidence: ANSI C89 §3.5.7 — the initializer for a union object with static
storage duration initializes its **first** member only. Probe
`/tmp/t1ci_edge/main.zig` (`const ub = U1{ .b = 5 };`, `union { a: u32, b: u8 }`):
today emits `zT_0.b = 5; zG_ub = zT_0;` in `__module_init` (correct values).
A single static initializer `= { 5 }` would set `.a`, not `.b` — wrong object.
No reordering/typedef trick preserves cross-TU type compatibility and C
interop (`@cInclude`d unions). Same rule nests inside tagged-union payloads.

Scope: **0 occurrences** of file-scope const unions in `sf/src`,
`examples/z98`, `repro/mi_matrix`, `scripts/stdlib/ref` at `bc48ec9c`
(enumeration §1; S13-S16). The plan's "structs/unions" coverage is therefore
achievable for every union shape the trees actually use, but the general
non-first-member case cannot be represented — a plan/C89 tension.

Recommended resolution for 1C-F (operator choice):
(a) implement §3 as specified with `constInitEvaluate` returning `null` for
    S14/S16 (documented C89 boundary, `.bss` fallback preserves today's
    correct values) — **recommended**;
(b) or defer the whole union class to `.bss` (more conservative, still
    correct, slightly less rodata);
(c) or redesign union typedefs around a first-member raw-bytes overlay —
    rejected: churns every union type and breaks C-interop unions.

### STOP-2 — plan fixed-point anchor vs compiler-fix seed rotation

`docs/superpowers/plans/2026-10-21-phase1-m2-crypto-core-plan.md` Global
Constraints say Task 4 closeout rotates seed v112 and "fixed point
`21c957730d268f1e7883176fa5413b65` must not move", but the same section
requires 1C-F (a compiler fix) to rotate a seed. A compiler change **must**
move the fixed point. Resolution: two rotations, v112 (1C-F, new fixed point)
then v113 (Task 4, 42 lib files, fixed point = v112's) — §4.3. The plan text
needs a version/anchor truth-up at 1C-F/Task-4 time; no plan edit is made in
1C-I (report-only). If the operator instead wants a single Task-4 rotation,
the "1C-F … + seed rotation" clause must be amended — contradiction is in the
plan text, not in the design.

---

## 8. Probe index (all under /tmp, HEAD `bc48ec9c`, compiler md5 `21c95773…`)

| dir | purpose | key result |
|---|---|---|
| `t1ci_probe1` | full shape matrix emission | §1 "today" column; S12 invalid C89 confirmed (gcc: "assignment to expression with array type") |
| `t1ci_probe2` | T-table repro | `nm -S`: `B zG_8693C83D_arr1d` |
| `t1ci_xmod` | cross-module pub enforcement | non-pub const rejected; header still `extern`s it |
| `t1ci_xsc` | cross-module scalar consts | `K=42` folds at importer; `KE=40+2` becomes `.bss` global |
| `t1ci_cw` / `t1ci_cw2` | const-write rejection | `ERR_3002` for `x = 5` and `a[0] = 7` |
| `t1ci_decay` | `stdlib_const_decay_ok_xmod` emission | S8-S10 module_init forms captured |
| `t1ci_edge` | union first/non-first member | `zT_0.b = 5` path; STOP-1 evidence |
| `t1ci_edge2` | empty array | degenerate typing; L8 |
| `t1ci_edge3` | optional const | folds at use, no symbol |
| `t1ci_edge4` | tagged-union const | `zT_0.tag = n; copy` path |
| `t1ci_c89{,b,c}.c` | C89 static-initializer legality | `r`/`.rodata` for value consts; `d`/`.data.rel.ro` for address-bearing; zero warnings with exact casts |

Commands (representative):

```
md5sum /tmp/m1_build/zig1_5_clean    # 21c957730d268f1e7883176fa5413b65
/tmp/m1_build/zig1_5_clean --dump-c89 -o OUT main.zig
gcc -std=c89 -c main_*.c -o m.o && nm -S m.o
gcc -std=c89 -pedantic -Wall -Wextra -c /tmp/t1ci_c89b.c   # see §3.6
```

---

## 9. Change-site summary for 1C-F (exact)

| file | site | change |
|---|---|---|
| `sf/src/const_init_eval.zig` | new | §3.1 evaluator + tree pool |
| `sf/src/lir.zig` | `:577-582`, `:584-634` | `ModuleGlobalDecl` += `const_init`, `link_visible` |
| `sf/src/main.zig` | `:965-1004` (classification), `:997-1004` (construction), `:1012-1018` (unchanged logic) | call evaluator; record tree + linkage |
| `sf/src/lower.zig` | `:9581-9583` (module-init skip), `:5038-5057` (use-site fold kind test) | consult shared result |
| `sf/src/c89_emit.zig` | `:2135-2195` (defs/externs), `:6876-6885` (`addr_of` cast), slice/`make_slice` renderers, new `emitConstInitValue` | §3.3 |
| `repro/mi_matrix/stdlib_const_rodata_xmod/` | new | §5.1 value fixture |
| `repro/mi_matrix/const_rodata_gate/` | new | §5.2 probe sources |
| `scripts/compiler/gate_const_rodata.sh` | new | §5.2 nm gate |
| `scripts/seed/*`, `release/seed/`, plan seed refs | 1C-F step 5 | §4.3 v112 rotation |

No `std.zig`, no example edits, no unrelated pass edits.

