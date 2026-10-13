# P3 report — Canonical `typeCName` (execution order 4/10 per Task 0)

**Status:** DONE (battery all green; emitted-C byte-identity held 0/8 pins; no spelling changes; one scoped observation recorded — the dead `TU_` composition, I.5)
**Scope (plan text):** "P3: Canonical `typeCName`. One derivation (in `type_registry`/`type_resolver`); emitter `getCTypeName` consumes it; remove the emitter's write-back into `type_registry.c_name_map` (`c89_emit.zig:2428`); dedup `emitArrayType:2145`/`emitOptionalType:2373`. Closes D2 residue. Gate: runtime battery."
**Tree at start:** `f29070b4` (P2 fix round 1), fixed point `687bdbaa71c76436da9ba0935608b319`, pins = P2 fix-round-1 values.

---

## Investigate (read-only census + precise edit plan — written before any source edit)

### I.0 Drift re-derivation (brief/plan cite → current `f29070b4`)

| item | brief/plan said | current | note |
|---|---|---|---|
| `getCTypeName` | `:940` (spec §3) | **`c89_emit.zig:709-938`** (body ends `:938`) | P5/P1/P2 deletions shifted lines; full body re-derived |
| `c_name_map` write-back | `:2428` | **`c89_emit.zig:2068`** (last line of `emitErrorUnionType`) | sole `typeRegistryCNameIdSet` caller in the repo (grep evidence I.1) |
| `emitArrayType` | `:2145` | **`c89_emit.zig:1785-1807`** | local `Arr_` mint at `:1788-1794` duplicates `getCTypeName`'s array branch |
| `emitOptionalType` | `:2373` | **`c89_emit.zig:2013-2043`** | local `Opt_` mint at `:2018-2024` duplicates `getCTypeName`'s optional branch |
| `EU_`/`ES_`/`FP_` compositions | "in `getCTypeName`" | `c89_emit.zig:849-864` (EU), `:865-915` (fn: `FS_`/`FP_`/`FN_` via char codes 70/83/80/78), `:916-933` (ES) | same function, P1-era lines 1078/1098/1148 |
| `TU_` composition | brief: "in `getCTypeName` full body" | **`c89_emit.zig:1603-1615`, inside `emitTaggedUnionType`** — and its product `struct_name` is **never read** (grep `struct_name` → only its own 3 assignment lines `:1613-1615`) | NOT a C-type-name spelling; see I.2d observation |
| `sliceElementName` | (P1/F2 cite `:931-937`) | `c89_emit.zig:700-707`, single caller `getCTypeName:830` | part of the derivation; moves |
| `syntheticTypeName` | P1 report cites `:898/:921` | **absent at `f29070b4`** (grep `syntheticTypeName` over `sf/src` → 0 hits); the 3-part rule is inlined at `:765-766` (Arr), `:777-778` (Tup), `:832-833` (Slice), `:841-842` (Opt) + the two dup sites | P1-era function no longer present; compositions themselves unchanged |

### I.1 Census — every place that DERIVES a C type name vs CONSUMES one

Derivation = computes the C type name of a tid/name from parts (moves to `typeCName`). Consume = calls `getCTypeName`/takes a name string as given (stays).

**DERIVES (all move or are deleted) — grep `nameManglerMangle(…, …, @intCast(u8, 2), …)` + `MintSyntheticType` + `CNameId` across `sf/src`:**

| # | site | what it derives | P3 action |
|---|---|---|---|
| D1 | `getCTypeName:709-938` | the full per-kind model (all kinds) | body MOVES to `type_registry.typeCName`; becomes thin wrapper |
| D2 | `sliceElementName:700-707` | slice-element name component (F2 rule) | moves to `type_registry` (private helper of the derivation) |
| D3 | `emitArrayType:1788-1794` | `Arr_<elem>_<len>` (dup of D1's array branch) | DEDUP: `aname = getCTypeName(tid)` |
| D4 | `emitOptionalType:2018-2024` | `Opt_<payload-id>` (dup of D1's optional branch) | DEDUP: `mangled_c_name = getCTypeName(tid)` |
| D5 | `emitErrorUnionType:2068` | (write-back) `typeRegistryCNameIdSet` into registry memo | DELETE (memo ownership moves inside `typeCName`) |
| D6 | `emitStructType:1701-1702` (+ `ES:n` id at `:1743`) | struct C name = `mangle(name_id,2,module_id)` | consume `getCTypeName(tid)`; `ES:n` marker id read via `typeRegistryCNameIdGet` (emitter becomes a pure READER of the memo) |
| D7 | `emitUnionType:1748-1749` | union/packed C name | consume `getCTypeName(tid)` |
| D8 | `emitTaggedUnionType:1594-1595` | tagged-union C name (`base_str`) | consume `getCTypeName(tid)` |
| D9 | `emitEnumType:1946-1947` | enum C name (typedef + macro prefix) | consume `getCTypeName(tid)` |
| D10 | `emitInt64Type:1973-1974`, `emitUint64Type:1982-1983`, `emitF64Type:1991-1992` | carrier typedef names (i64/u64/f64) | consume `getCTypeName(tid)` |
| D11 | `enum_const` arm `writeIntConstRvalue:3875-3876` | enum C name used as `Enum_Member` macro spelling | consume `getCTypeName(ec.type_id)` |
| D12 | `enum_const` inst arm `:7322-7323` | same | consume `getCTypeName(ec.type_id)` |

**CONSUMES (stay):** the ~90 `getCTypeName(...)` call sites in `c89_emit.zig` (decl bodies' field/param/payload types, casts, va_arg, temps, globals, printers, …); `getUnsignedCTypeName:4254` (width-reinterpretation helper, not a canonical name; its internal `getCTypeName` calls stay); `nestEffCType:3569` (consumer). `moduleQualifiedName:2419` derives MODULE names, not C type names (P1 classified it outside the type-name census) — untouched. `typeIdName:5530`-class printer/table names = `MintIndexName` material — untouched. `zTU_*_*`/`ERROR_*`/enum-macro `#define` composites (P1: "not mints") — untouched. No C-type-name derivation exists outside `c89_emit.zig`/`type_registry.zig` (grep `getCTypeName|CNameId` → only those two files; no `main.zig`/`lower.zig` derivation sites).

**Expected touch set (brief):** `sf/src/type_registry.zig` and/or `sf/src/type_resolver.zig`, `sf/src/c89_emit.zig`, `sf/docs/tech_docs/`. **Confirmed:** exactly `type_registry.zig` + `c89_emit.zig` + `tech_docs/{INDEX.md,03_type_resolution.md,08_c89_emission.md}`. Nothing outside → no STOP.

### I.2 The canonical derivation — design

**Home:** `sf/src/type_registry.zig` — `pub fn typeCName(self: *TypeRegistry, mangler: *NameMangler, tid: u32) []const u8` (the plan's `typeCName(tid)` row; the mangler is the P1 authority passed in, exactly as `getCTypeName` takes it today). The plan text says "`type_registry`/`type_resolver`"; home = `type_registry` matches P1's disclosed seam ("P3 relocates the derivation to `type_registry.typeCName`", P1 report §3/§5) and the per-increment commit subject `refactor(type_registry)`. Cost of the choice: `type_registry.zig` gains `const nm_mod = @import("name_mangler.zig")` — a mutual import (`name_mangler.zig:3` already imports `type_registry`). The toolchain's only in-tree mutual-import precedent (`type_resolver`↔`comptime_eval`) is probe-verified compilable; the seed rebuild in the battery is the probe. If the seed rejects the cycle the task is BLOCKED (fallback home `type_resolver` would contradict the fixed commit subject — surfaced, not silently taken).

**Body:** verbatim relocation of `getCTypeName:709-938` (+ `sliceElementName` as private `typeSliceElementName`), with only these mechanical differences:
1. receiver alias `var reg = self;` so every moved expression stays byte-identical;
2. module qualifiers adjusted to `type_registry` scope (`type_mod.TYPE_*`→`TYPE_*`, `type_mod.TypeKind`→`TypeKind`, `type_mod.FN_FLAG_STDCALL`→`FN_FLAG_STDCALL`, `pal.`→`pal_mod.`, `type_mod.typeRegistryCNameIdGet/Set`→unqualified);
3. recursive calls `getCTypeName(reg, mangler, X)` → `typeCName(reg, mangler, X)` (and in `typeSliceElementName`);
4. **memo ownership**: after each post-memo-check derivation (EU / fn / ES-anon / ES-named / final fallback) `typeRegistryCNameIdSet(reg, tid, <the mangled id in hand>)` — the emitter's `:2068` write-back is deleted and the emitter becomes a pure READER (`emitStructType`'s `ES:n` telemetry reads `typeRegistryCNameIdGet`). The read-check position (`:844-847` shape: after the optional branch, before EU) is kept verbatim.

**`getCTypeName` after P3** (`c89_emit.zig:709`): thin wrapper — `return type_mod.typeCName(reg, mangler, tid);`. No derivation logic left in the emitter. All ~90 call sites unchanged (wrapper explicitly sanctioned: "thin wrapper or direct calls").

**Markers:** the `D6:` head marker and `NUL:TYnul` marker move WITH the verbatim body into `typeCName` (doc 08 marker table: `D6:t | getCTypeName | C-name lookup debug — fires for every tid>=20`). Every derivation query keeps firing exactly once (including recursion, which is now `typeCName`→`typeCName`); the ONLY delta is the queries that did not exist before: the 12 D6–D12 rewire sites now ask the canonical derivation for names they previously minted inline (previously unmarked). Marker telemetry is a recorded delta (battery item 8), not a gate.

**Determinism (load-bearing):** same tid → same C name every compilation.
- All spellings are pure functions of registry state (copied verbatim), final identifiers minted through `nameManglerMangle`/`nameManglerMintSyntheticType` (P1 authority), whose own caches make repeats idempotent.
- The `nameManglerMangle` collision suffix is first-mint-wins per mangled string. Every (name_id, kind, module) triple mints through the same cache key as today; the walk order of first mints is unchanged (no emission-order change), so collision winners are unchanged. The dedup sites' old duplicate mints composed the SAME strings (same cache keys) — removing them cannot change any winner.
- The memo write additions are unobservable: a memo hit skips a `nameManglerMangle` call that would itself have hit the mangler cache early (no intern/collision traffic) — identical bytes, identical markers.

### I.3 Per-kind spelling table (old emitter spelling → canonical `typeCName` result; MUST match)

Every row is produced by the SAME expressions after the move (old site column cites `f29070b4`). Excepted spellings: none — F2 already fixed the D2 alias (`[]synthetic` recurses to a distinct element name); no spelling in this table is the D2 alias bug, so **all rows are byte-identical old→canonical** (pins expected 0/8 delta).

| kind | old spelling (site) | canonical | match |
|---|---|---|---|
| `void` | `"void"` (`:714`) | `"void"` | identical |
| `bool` | `"unsigned char"` (`:715`) | same | identical |
| `i8`/`i16`/`i32` | `"signed char"` / `"short"` / `"int"` (`:716-718`) | same | identical |
| `i64` | `mangle(name_id,2,module_id)` text = carrier typedef name (`:719-722`) | same | identical |
| `u8`/`u16`/`u32` | `"unsigned char"` / `"unsigned short"` / `"unsigned int"` (`:723-725`) | same | identical |
| `u64` | `mangle(name_id,2,module_id)` text (`:726-729`) | same | identical |
| `arb_uint` | size 2→`"unsigned short"`; 4→`"unsigned int"`; 8→`typeCName(TYPE_U64)`; else `"unsigned char"` (`:730-736`) | same | identical |
| `arb_int` | size 2→`"short"`; 4→`"int"`; 8→`typeCName(TYPE_I64)`; else `"signed char"` (`:737-743`) | same | identical |
| `f32` | `"float"` (`:744`) | same | identical |
| `f64` | `mangle(name_id,2,module_id)` text (`:745-748`) | same | identical |
| `usize`/`isize` | `"unsigned int"` / `"int"` (`:749-750`) | same | identical |
| `c_char` | `"char"` (`:751`) | same | identical |
| `va_list` | `"va_list"` (`:752`) | same | identical |
| `enum` | `mangle(name_id,2,module_id)` text (`:753-756`) | same | identical |
| `array` | `MintSyntheticType("Arr_", typeCName(elem), itoa(length) digits, 127)` (`:757-767`) | same expressions (moved) | identical |
| `tuple` | `MintSyntheticType("Tup_", "", itoa(tid) digits, 31)` (`:768-779`) | same | identical |
| `ptr`/`many_ptr` whose base is `fn_type` | `typeCName(base)` — the fn typedef NAME itself, no `*` (P2 note; `:783-784`) | same | identical |
| `ptr` string-literal decay (`*const [N]u8`: !vol && const && array-of-`u8`) | `"unsigned char*"` (`:791-797`) | same | identical |
| `ptr` !vol && base `u8`/`u32`/`i32`/`c_char`/`usize` | `"unsigned char*"` / `"unsigned int*"` / `"int*"` / `"char*"` / `"unsigned int*"` (`:798-803`) | same | identical |
| `ptr`/`many_ptr` general | `typeCName(base) + "*"`; volatile non-ptr-base: `"volatile " + base + "*"`; volatile ptr-base: `base + " volatile" + "*"` (interned, `:804-827`) | same | identical |
| `undefined`/`integer_literal`/`null` | `"int"` (`:828-830`; `null` also writes `NUL:TYnul`) | same | identical |
| `slice` | `MintSyntheticType("Slice_", sliceElementName(elem), "", 63)`; element component: `elem.name_id==0` → `typeCName(elem)` (F2 recursion) else `mangle(elem.name_id, 2, 0)` — note **module 0**, F2's preserved spelling (`:831-834`, `:700-707`) | same expressions (moved) | identical |
| `optional` | `MintSyntheticType("Opt_", "", itoa(op.payload) digits, 63)` — payload TYPE ID digits (`:835-842`) | same | identical |
| `error_union` | `"EU_"` + `ep.payload` decimal rendered **least-significant-digit-first** by the `while (pl > 0 or di == p)` loop (e.g. payload 64 → `EU_46`), intern, `mangle(…,2,0)` (`:849-864`) | same expressions (moved); memo Set now here | identical |
| `fn_type` | `fbuf[0]='F'`, `fbuf[2]='_'`, `fbuf[1]='S'` (STDCALL) / `'P'` (ty.flags&1) / `'N'` → `FS_`/`FP_`/`FN_` + return name (` `/`*`→`_`) + `_<param name>`… (cap 95), intern, `mangle(…,2,0)` (`:865-915`) | same expressions (moved); memo Set now here | identical |
| `error_set` (`name_id==0`) | `"ES_"` + `ty.payload_idx` decimal LSB-first (same loop shape), intern, `mangle(…,2,0)` (`:916-931`) | same; memo Set now here | identical |
| `error_set` (named) | `mangle(name_id,2,module_id)` (`:932-934`) | same; memo Set now here | identical |
| fallback: `struct`/`union`/`packed_union`/`tagged_union`/`noreturn`/`unresolved_name`/`type_type`/`module_type`/`anon_*`/`none_sentinel` | `mangle(name_id,2,module_id)` (`:935-937`) | same; memo Set now here | identical |

### I.4 Precise edit plan (per file)

**`sf/src/type_registry.zig`** (additions only; P2 surface `typeRefs`/`typeNeedsFullDef`/… untouched):
1. imports: add `const nm_mod = @import("name_mangler.zig");` + `const NameMangler = nm_mod.NameMangler;` (the only new module edge; mutual with `name_mangler.zig:3` — probed by the battery seed rebuild).
2. after `typeRegistryCNameIdSet` (`:475-477`): add `fn typeSliceElementName(self: *TypeRegistry, mangler: *NameMangler, elem_tid: u32) []const u8` (moved from `c89_emit:700-707`) + `pub fn typeCName(self: *TypeRegistry, mangler: *NameMangler, tid: u32) []const u8` (moved body per I.2, memo Sets added per I.2).

**`sf/src/c89_emit.zig`** (bottom-to-top per AGENTS.md X.7; re-read each region immediately before its edit):
1. `:7322-7324` `enum_const` inst arm → `var e_name = getCTypeName(emitter.registry, emitter.mangler, ec.type_id);`
2. `:3875-3877` `enum_const` const arm → same consume
3. `:2068` delete `type_mod.typeRegistryCNameIdSet(...)` (write-back removal)
4. `:2018-2024` `emitOptionalType` local `Opt_` mint → `var mangled_c_name = getCTypeName(reg, emitter.mangler, tid);` (keep `INSTA:optt`/`VFLOW:opV` markers + both typedef shapes)
5. `:1991-1992` `emitF64Type`, `:1982-1983` `emitUint64Type`, `:1973-1974` `emitInt64Type`, `:1946-1947` `emitEnumType`: `mangled_id`+Get pair → `getCTypeName(emitter.registry, emitter.mangler, tid)`
6. `:1788-1794` `emitArrayType` local `Arr_` mint → `var aname = getCTypeName(reg, emitter.mangler, tid);` (keep `ename = getCTypeName(ap.elem)` + the `typedef …[decl_len];` text)
7. `:1748-1749` `emitUnionType` → `getCTypeName(emitter.registry, emitter.mangler, tid)`
8. `:1743` `emitStructType` `ES:n` marker id → `type_mod.typeRegistryCNameIdGet(emitter.registry, tid)` (pure reader; value identical to today's `mangled_id`)
9. `:1701-1702` `emitStructType` name → `getCTypeName(emitter.registry, emitter.mangler, tid)`
10. `:1594-1595` `emitTaggedUnionType` `base_str` → `getCTypeName(reg, emitter.mangler, tid)` (the dead `TU_` composition at `:1603-1615` is left in place — observation I.5, not a fix)
11. `:709-938` `getCTypeName` body → `return type_mod.typeCName(reg, mangler, tid);` (signature + wrapper comment kept)
12. `:700-707` delete `sliceElementName` (moved; 0 callers after step 11)

**`sf/docs/tech_docs/`** (AGENTS.md 1.1.1; `[updated: 2026-10-12]` on changed sections):
- `INDEX.md` Table A: add `typeCName` → `type_registry.zig`; `typeSliceElementName` row; `getCTypeName` row annotated as consumer wrapper.
- `03_type_resolution.md`: `typeCName`/`typeSliceElementName` signature + memo-ownership rows/section.
- `08_c89_emission.md`: P3 note at top; `getCTypeName` § mapping updated; `D6:t`/`NUL:TYnul` marker rows now owned by `typeCName`; decl-site consume note.

### I.5 Observation (not fixed — "no unrelated fixes")

`emitTaggedUnionType:1603-1615` composes `"TU_" + base_str` and mints `struct_name` — **`struct_name` is never read** (grep: 3 hits, its own assignment chain only). The tagged-union kind's actual C type name is the fallback `mangle(name_id,2,module_id)` (= `base_str`), consistent at decl (`struct <base_str> {…};`) and use. The P1/P3 seam text lists `TU_` among the name-material compositions, but this composition produces **no C type name** and is not a spelling of any kind — it is dead code. The plan's P3 deliverables do not name it, so per "no unrelated fixes" it stays; deleting it is a one-line-range cleanup for a later increment/review decision. Cost if wrong: 13 lines of dead composition ride along (zero emitted-C effect — its product is unread).

### I.6 Determinism / risk check (pre-edit)

- Emitted-C byte-identity expected for every spelling (I.3 all "identical") → pins should hold 0/8; any pin delta = a regression to root-cause before commit, not a re-baseline.
- `nameManglerMangle` collision winners unchanged (I.2). `MintSyntheticType` duplicates removed were same-composition/same-cache-key twins.
- Z98 constraints: the moved body compiles today (same constructs); additions are ordinary fn defs + one import + `u32ToU32MapPut` calls (existing API). Bootstrap-staging risk concentrated in the new mutual import — probed first thing in the battery.

---

## Implement (one compiler-moving commit; edits only via `edit`/`fastedit`, bottom-to-top per file, region re-read before each edit)

### Step 1 — `sf/src/type_registry.zig` (additions only; P2 surface untouched)

- imports: added `const nm_mod = @import("name_mangler.zig");` + `const NameMangler = nm_mod.NameMangler;` (the mutual-import probe; see battery item 1 — the seed compiles it).
- after `typeRegistryCNameIdSet`: added `fn typeSliceElementName(self: *TypeRegistry, mangler: *NameMangler, elem_tid: u32) []const u8` (verbatim F2 helper; recursion → `typeCName`) and `pub fn typeCName(self: *TypeRegistry, mangler: *NameMangler, tid: u32) []const u8` — the verbatim relocated body (receiver aliased `var reg = self;` so every moved expression is byte-identical; `type_mod.`/`pal.` qualifiers dropped to local scope), recursion via `typeCName`, and the memo-ownership change exactly as I.2: `typeRegistryCNameIdSet(reg, tid, <mangled id in hand>)` after each post-memo-check derivation (EU / fn / ES-anon / ES-named / fallback).

### Step 2 — `sf/src/c89_emit.zig` (12 edit points, I.4 order; verified by the battery's byte-identical pins)

1. `:7322` `enum_const` inst arm → `var e_name = getCTypeName(emitter.registry, emitter.mangler, ec.type_id);`
2. `:3875` `enum_const` const arm → same consume.
3. `:2068` **write-back DELETED** (`type_mod.typeRegistryCNameIdSet(...)` in `emitErrorUnionType` — the D2-residue site the plan named `:2428`).
4. `emitOptionalType`: local `Opt_` mint (itoa + `MintSyntheticType`) replaced by `var mangled_c_name = getCTypeName(reg, emitter.mangler, tid);` (`INSTA:optt`/`VFLOW:opV` markers and both typedef shapes kept).
5. `emitF64Type`/`emitUint64Type`/`emitInt64Type`/`emitEnumType`: `mangled_id`+Get pairs → `getCTypeName(…, tid)`.
6. `emitArrayType`: local `Arr_` mint (itoa + `MintSyntheticType`) replaced by `var aname = getCTypeName(reg, emitter.mangler, tid);` (`ename = getCTypeName(ap.elem)` and `typedef …[decl_len];` text unchanged).
7. `emitUnionType` → `getCTypeName(…, tid)`.
8. `emitStructType` `ES:n` marker id → `type_mod.typeRegistryCNameIdGet(reg, tid)` (pure READER; value = the same `nameManglerMangle` result the derivation stored).
9. `emitStructType` name → `getCTypeName(…, tid)`.
10. `emitTaggedUnionType` `base_str` → `getCTypeName(…, tid)` (dead `TU_` composition `:1603-1615` left in place — I.5).
11. `getCTypeName` body (`:709-938`) → `return type_mod.typeCName(reg, mangler, tid);` (pure consumer wrapper, comment added).
12. `sliceElementName` (`:700-707`, F2 comment included) deleted — moved; 0 callers after 11.

### Step 3 — `sf/docs/tech_docs/` (AGENTS.md 1.1.1)

- `INDEX.md` Table A: `getCTypeName` → `typeCName` (P3; pure consumer wrapper); rows added `typeCName` | type_registry.zig, `typeSliceElementName` | type_registry.zig.
- `03_type_resolution.md`: `[updated: 2026-10-12 — P3 …]` header note; fn-table rows for `typeCName`/`typeSliceElementName` (full per-kind inference + memo ownership).
- `08_c89_emission.md`: `[updated: 2026-10-12 — P3 …]` header note; §1.5 intro + the stale `ty.c_name_id` paragraph rewritten to the P3 memo ownership; F2 paragraph's `sliceElementName` cite annotated with the move; marker-table rows `D6:t`/`NUL:TYnul` re-owned by `type_registry.typeCName`, `ES:n` annotated as memo reader.

### Post-edit residue proof (commands + observed)

```
$ grep -n 'sliceElementName\|nameManglerMintSyntheticType\|typeRegistryCNameIdSet' sf/src/c89_emit.zig
(only the P3 wrapper comment line mentions c_name_map; zero code hits)
$ grep -n 'nameManglerMangle' sf/src/c89_emit.zig | grep -v 'nameManglerMangle(self\|nameManglerMangleGlobal'
1377: … struct_mid = …(struct_nid, 2, 0)   # the dead TU_ composition (I.5; kept)
1926/1961/2399/2501/4718/7313/7447/7986 … kind 0 (fn-name mints; not type names)
$ grep -n 'fn typeCName\|fn typeSliceElementName' sf/src/type_registry.zig
491:fn typeSliceElementName(…
501:pub fn typeCName(…
$ sed -n '709,716p' sf/src/c89_emit.zig   # the wrapper
fn getCTypeName(reg: *TypeRegistry, mangler: *NameMangler, tid: u32) []const u8 {
    return type_mod.typeCName(reg, mangler, tid);
}
```
No derivation logic left in the emitter; no dead copies; the only remaining kind-2 mangle in `c89_emit.zig` is the unread `TU_` composition (observation).

### Deviations from the I.4 edit plan

None in scope or shape. (`fastedit` is broken in this environment — `error: undefined is not an object (evaluating 'code.matchAll')` on every call — so the large body relocation used chunked `edit` string-replacements instead, same bottom-to-top discipline and same final tree. Recorded as a tooling note.)

---

## Runtime battery (FULL; every claim = command + observed output)

Final binary: `/tmp/taskP3_work/seed/zig1_5_clean` from `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/taskP3_work/seed` (repo root).

### 1. Seed rebuild + two-hop closure (+ the mutual-import probe)

```
[seed] hop2 binary md5: 25f246289f655f1692657da5cdf124a7
[seed] two-hop closure OK: hop1 == hop2 == 25f246289f655f1692657da5cdf124a7
=== [seed] Done: /tmp/taskP3_work/seed ===
```
Fixed point `687bdbaa71c76436da9ba0935608b319` → **`25f246289f655f1692657da5cdf124a7`** (moved — expected: `sf/src` changed, so the self-emitted compiler binary changes; hop1==hop2 proven). **The new `type_registry` ↔ `name_mangler` mutual import compiles under the seed** (the build IS the probe; rc=0, no diagnostics). Seed NOT rotated (rotation is closeout-only).

### 2. Corpus classify (vs frozen Appendix A)

```
$ bash scripts/corpus/classify /tmp/taskP3_work/seed/zig1_5_clean /tmp/taskP3_work/corpus_p3.txt
wrote /tmp/taskP3_work/corpus_p3.txt: 1124 dirs
$ awk '{print $2}' … | sort | uniq -c
    116 FAIL
     58 GREEN
    950 OK
$ md5sum /tmp/taskP3_work/corpus_p3.txt /tmp/task0_work/corpus_baseline.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/taskP3_work/corpus_p3.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/task0_work/corpus_baseline.txt
$ diff /tmp/task0_work/corpus_baseline.txt /tmp/taskP3_work/corpus_p3.txt → rc=0, 0 lines
```
**1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH — byte-identical to frozen Appendix A. 0 class movers.**

### 3. Runtime goldens (5 md5s, byte-identical)

Build (Task 0 §1.3 recipe): `zig1_5_clean --dump-c89 <ENTRY> > gold/<n>.c` + `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include gold/<n>.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o gold/<n>` — all 4: dump rc=0, gcc rc=0, 0 `error:` (gol 13924-line dump / lisp 19277 / json 15596 / mud 14789).

| golden | command | observed md5 | frozen | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 ./gol > gol.out` (rc=0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7c…` | YES |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 ./lisp` (rc=0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f897…` | YES |
| json | `cd examples/z98/json_parser && timeout 60 gold/json` (rc=0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a…` | YES |
| mud server | `bash examples/z98/mud_server/demo/session.sh gold/mud …` (session rc=0) | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0ab…` | YES |
| mud client | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f…` | YES |

Both mud outputs `cmp`-equal `demo/canonical_expected.txt` / `demo/canonical_client_expected.txt`: `cmp server: IDENTICAL`, `cmp client: IDENTICAL`. **5/5 byte-identical.**

### 4. mi_matrix runtime anchors (25 + oob)

Anchor set re-enumerated by the frozen definition (non-`stdlib_*` ∧ non-empty `expected.txt` ∧ `expected.rc=0`): `for d in repro/mi_matrix/*/; … done | wc -l` → **25** (same 25 names as Task 0 F2). Harness: `bash scripts/stdlib/run_fixtures.sh /tmp/taskP3_work/seed/zig1_5_clean <the 25 dirs>` → **`run_fixtures: 25 PASS / 0 FAIL over 25 dirs`** (incl. `slice_index_field_store_xmod` `PASS` — the `9/11/22/ok` reproducer).

Trap fixture (`-fsafe` recipe): `slice_index_field_store_oob_xmod` — dump rc=0, build rc=0, **run rc=133** (SIGTRAP), stdout 0 bytes, md5 `d41d8cd98f00b204e9800998ecf8427e`; goldens `expected.txt` md5 `d41d8cd98f00b204e9800998ecf8427e`, `expected.rc` = `133`. **MATCH.**

### 5. `examples/z98/*/` matrix (26 build + 26 run)

Build per dir (`zig1_5_clean -ffast -o matrix/<n> <entry>` + `sh build_target.sh linux matrix/<n>/prog`, entry = `main.zig` → `<n>.zig` → first `*.zig`): **26/26 dump=0 / build=0**; per-dir `.c` counts identical to Task 0 §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38).

Run per dir (CWD = example dir, `timeout 25` except mud_server 8; stdin `/dev/null` except rogue* `q\n`): **26/26 rc + stdout md5_16 IDENTICAL to the §1.4 table** — days_in_month `8c0d394cbc6e7f36`, fibonacci `b53b3a3d6ab90ce0`, func_ptr_return `f6a5477970a87a1c`, game_of_life `fcbf7e7cead5082f`, heapsort `8cf0a7844206319d`, hello `746308829575e17c`, json_parser(+upgraded) `8bda3d5a1ec07d14`, json_parser_workaround `dc22fa473650bd3d`, lisp×4 `1c1f0a417d5e9434`, lzw `c3c7765e6faf7b70`, mandelbrot `d596677501e36537`, mud_server rc=124 `9545fe1d245293ef`, prime `d095a94d20dcaf7a`, quicksort `45d2f0fb6fc40654`, rogue×2 `3fb6709e7bbd8964`, sort_strings `c6c047cbc13cdd4f`, tco_defer `264ea6b106a51dde`, tco_factorial `3d70c50b5a37d549`, tco_return_try `7421137aa2d104b4`, z9play rc=1 `2016494de476fcb6`, z9torr rc=1 `f666af15cf2625b3`.

### 6. Stdlib gate

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/taskP3_work/seed/zig1_5_clean
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```
**285/0 — no lost PASS vs the frozen 285.**

### 7. The 8 `--dump-c89` pins (old → new; record only)

| entry | mode | old (P2 fix round 1, `687bdbaa…`) | P3 (`25f24628…`) | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `1b5d49b141ee9c664a82c270454bd75b` | `1b5d49b141ee9c664a82c270454bd75b` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `8e5f2bc288d1dc75d7aee284cb35c291` | `8e5f2bc288d1dc75d7aee284cb35c291` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `2a12d0aac24d5bcdd694f05e04a4f029` | `2a12d0aac24d5bcdd694f05e04a4f029` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8 — emitted C byte-identical**, exactly as the I.3 spelling table predicted ("every row identical"). Command per row: `zig1_5_clean <mode> --dump-c89 examples/z98/<entry>/main.zig 2>/dev/null | md5sum`.

### 8. `--markers` telemetry

`zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk_gol.c 2> mk_gol.bin` — dump rc=0; stderr **3,436 marker lines / 38,378 B** (P2 values: 3,436 / 38,378). Full capture comparison against the P2-fix compiler's own capture (`/tmp/taskP2fix_work/seed/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig`): **`cmp` → byte-identical** (and the full-prefix histograms `diff` → empty: `INT:new` 2005, `DC:k` 423, `FE:p` 240, `P` 195, `FWD:n=` 195, `RaD` 122, `MT` 86, `FE:` 69, `arena` 26, `X:` 17, `IRP:p/n/m` 17, …). The moved `D6:`/`NUL:TYnul`/`ES:n` markers are `pal.markerWrite*` — gated on `g_markers_debug` AND `g_markers_enabled` — so they do not appear in `--markers` captures at all (0 `D6:`/`ES:n` lines both sides); the marker-placement move therefore has **zero telemetry delta** on the recorded stream (doc 08 marker table annotated with the gating).

---

## Concerns (short list)

1. **Pins 0/8 delta** (recorded above) — the expected shape for a spelling-faithful relocation; no re-baseline needed (values unchanged vs P2 fix round 1).
2. **Fixed point moved** `687bdbaa…` → `25f24628…` — expected (any `sf/src` change re-emits the compiler); hop1==hop2 proven; seed not rotated (closeout-only).
3. **Dead `TU_` composition** (`c89_emit.zig` `emitTaggedUnionType`): `"TU_"+base_str` minted into `struct_name`, never read (grep evidence I.5) — left in place per "no unrelated fixes" (the plan's P3 deliverables do not name it); a one-block deletion candidate for review/closeout.
4. **New mutual import `type_registry` ↔ `name_mangler`** — seed-proven compilable (battery item 1), but it puts the type-registry core in an import cycle (`type_resolver`↔`comptime_eval` is the only in-tree precedent). If a future seed/import-rule change tightens cycles, `typeCName`'s sanctioned alternate home is `type_resolver` (plan: "type_registry/type_resolver").
5. **`typeSliceElementName`'s module-0 spelling preserved** (F2's exact rule: named elements mangle `name_id` with module 0, not the element's module). Absent a mangled-string collision this equals the element's typedef name; with a collision the slice NAME component can diverge from the typedef name (pre-existing F2-preserved shape; name-component-only, self-consistent; not the D2 alias bug — left byte-identical as instructed).
6. `fastedit` tool broken in this environment (crashes on every call) — chunked `edit` replacements used instead (same rules; final tree verified by greps + battery). Tooling note only.
7. Pre-existing uncommitted `.superpowers/sdd/…/progress.md` change (15 lines, not P3's) and root `run.err` stray left untouched/not swept (not ours; commits use explicit paths only).

## Verdict

DONE — one derivation (`type_registry.typeCName`), emitter `getCTypeName` a pure consumer, write-back removed (emitter is a pure memo reader), `emitArrayType`/`emitOptionalType` deduped, decl sites consume the same derivation (D2 residue closed at the architecture level; every spelling byte-identical). Full battery green vs the frozen Task 0 anchors; pins 0/8; corpus byte-identical; hop1==hop2.
