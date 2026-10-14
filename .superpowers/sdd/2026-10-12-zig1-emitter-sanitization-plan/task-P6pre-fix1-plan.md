# P6-pre fix round 1 — precise edit plan (I-task deliverable; apply-dispatch executes verbatim)

**Status:** DONE (investigation complete; no source edits made). Tree anchor `d0e5f451` (verified `git rev-parse HEAD`). Scope: the adjudicated gap — `lowerExactIntArg`/`lowerFoldedIntConst` still APPLY the carrier rule at lowering to type the materialization temp; the fix records the disambiguating semantic facts at lowering and the planner derives the carrier at the boundary. After this plan: ZERO carrier-rule application in any lowering site.

**Citation convention:** every `file:line` below was grep/read in the CURRENT tree (`d0e5f451`) unless marked *(report)* — those values are taken from `task-P6pre-report.md` (I.1/I.2 census, O3, probe method) or `task-0-report.md` (frozen anchors) and were spot-checked, not re-derived.

---

## 1. Semantic facts on LIR

### 1.1 The int-const record (`sf/src/lir.zig`)

Current (verified `lir.zig:74`):

```zig
    int_const: struct { value: u64, result: u32 },
```

Change to (facts only — NO carrier fields, ruling (ii)):

```zig
    int_const: struct { value: u64, result: u32, width_bits: u8, is_signed: u8 },
```

**Field semantics (binding for every writer/reader):**
- `width_bits == 0` — "no untyped-materialization width chosen": either a TYPED const (its semantic width/signedness is its carried temp result type — spec §4 "Lowerer-carried decisions"), or a BARE UNTYPED literal whose width/signedness the planner's historical value rule chooses at the boundary (Class A below).
- `width_bits != 0` — the const is an UNTYPED EXACT-VALUE MATERIALIZATION and `width_bits`/`is_signed` are its semantic materialization width/signedness (the sign-collision disambiguator). `width_bits` ∈ {32, 64} and `is_signed` ∈ {0, 1} for this class; typed consts may record their type's width (8/16/32/64/arb `iw`) and signedness.
- `value`/`result` unchanged (the two's-complement u64 pattern + result temp id).

Z98 has NO struct-field defaults (verified `parser.zig:1267-1282`: `field_decl` is `name: T` only) and NO missing-field zero-fill (verified `semantic_analyzer.zig:3990-4019` `semanticAnalyzerInitStructFields` only walks PRESENT inits; seed self-emission `gen/lower_*.c` assigns `zT_N.payload.int_const._0.value/.result` field-by-field). Therefore **every construction site must write all four fields** or the omitted ones are indeterminate — see §1.3/§5.3 for the exact per-site rule and the out-of-touch-set residue.

### 1.2 How the literal's semantic intent is captured at lowering (the sign-collision disambiguator)

NEW helper in `sf/src/lower.zig` (insert beside `lowerExactIntArg`, above `foldPrintArgIntExact` at `lower.zig:1625`):

```zig
// P6-pre fix: the untyped exact-value materialization's semantic intent
// (width-bits/signedness) — the sign-collision disambiguator recorded on the
// int_const record (ruling (ii): never a carrier). The class windows are
// exactly `ce_mod.comptimeIntUntypedType`'s (comptime_eval.zig:1382-1397),
// queried through the shared SEMANTIC fit predicate (type_registry-backed;
// P5 predicates). Returns false outside the 64-bit window (caller reports
// error[3000]).
fn lowerUntypedIntFacts(self: *LirLowerer, v: ce_mod.ComptimeInt, out_w: *u8, out_s: *u8) bool {
    if (ce_mod.comptimeIntFitsType(self.ctx.registry, v, type_mod.TYPE_I32)) { out_w.* = @intCast(u8, 32); out_s.* = @intCast(u8, 1); return true; }
    if (ce_mod.comptimeIntFitsType(self.ctx.registry, v, type_mod.TYPE_U32)) { out_w.* = @intCast(u8, 32); out_s.* = @intCast(u8, 0); return true; }
    if (ce_mod.comptimeIntFitsType(self.ctx.registry, v, type_mod.TYPE_I64)) { out_w.* = @intCast(u8, 64); out_s.* = @intCast(u8, 1); return true; }
    if (ce_mod.comptimeIntFitsType(self.ctx.registry, v, type_mod.TYPE_U64)) { out_w.* = @intCast(u8, 64); out_s.* = @intCast(u8, 0); return true; }
    return false;
}
```

The fit-query order reproduces the historical classes EXACTLY (checked against `comptime_eval.zig:1382-1397` — `comptimeIntFitsType` (`comptime_eval.zig:1344`) windows: neg → `|v| ≤ 2^(w-1)`; nonneg signed → `|v| < 2^(w-1)`; unsigned → `|v| < 2^w`):

| class (historical `comptimeIntUntypedType`) | first fit hit | recorded facts |
|---|---|---|
| neg, `|v| ≤ 2^31` → TYPE_I32 | fits I32 | (32, 1) |
| nonneg, `v < 2^31` → TYPE_I32 | fits I32 | (32, 1) |
| nonneg, `2^31 ≤ v < 2^32` → TYPE_U32 | fits U32 (neg never fits U32) | (32, 0) |
| neg, `2^31 < |v| ≤ 2^63` → TYPE_I64 | fits I64 | (64, 1) |
| nonneg, `2^32 ≤ v < 2^63` → TYPE_I64 | fits I64 | (64, 1) |
| nonneg, `2^63 ≤ v < 2^64` → TYPE_U64 | fits U64 | (64, 0) |
| outside the 64-bit window → null | none | `false` → `error[3000]` (unchanged path) |

Sign-collision pairs (report I.1/I.2 evidence — NOT re-derived): `0 - 3000000000` → (64, 1); the literal `18446744070697051616` → (64, 0). Same u64 pattern `0xFFFFFFFF4D9F2FFF`, now disambiguated on LIR.

### 1.3 Exact write sites (all `.int_const` constructions in `sf/src/lower.zig`, 52 sites)

Two shared emit helpers (insert beside `lowerUntypedIntFacts`):

```zig
fn emitIntConstFacts(self: *LirLowerer, value: u64, result: u32, width_bits: u8, is_signed: u8) void {
    emitInst(self, LirInst{ .int_const = .{ .value = value, .result = result, .width_bits = width_bits, .is_signed = is_signed } });
}
// Typed consts + bare untyped literals: the facts are the carried temp result
// type's semantic width/signedness (P5 predicates; TYPE_INT_LIT / non-int
// kinds give (0, 0) — typeWidthBitsForKind fallback, type_registry.zig:334-341).
fn emitIntConst(self: *LirLowerer, value: u64, result: u32) void {
    var rt = getTempType(self, result);
    var w: u8 = type_mod.typeRegistryIntWidthBits(self.ctx.registry, rt);
    var s: u8 = @intCast(u8, if (type_mod.typeRegistryIntIsSigned(self.ctx.registry, rt)) @intCast(u8, 1) else @intCast(u8, 0));
    emitIntConstFacts(self, value, result, w, s);
}
```

- **Class B (the untyped exact-value materializations — FACT RECORDING, 2 sites):** `lowerExactIntArg` (`lower.zig:1670`) and `lowerFoldedIntConst`'s untyped arm (`lower.zig:3635`) → `emitIntConstFacts(self, ce_mod.comptimeIntMaterialize(fv.v), ctid, fw, fs)` with `fw/fs` from `lowerUntypedIntFacts`.
- **All 50 sibling sites → `emitIntConst(self, <value expr>, <result expr>);`** (each is today's `emitInst(self, LirInst{ .int_const = .{ .value = X, .result = Y } });` at these exact lines): 678, 690, 694, 739, 771, 939, 949, 975, 3861 (`emitTaggedUnionInit` — union-typed result → (0, 0) by the typeWidthBitsForKind fallback), 4093, 4107, 4182, 4228 (int_literal arm — TYPE_INT_LIT temp → (0, 0)), 4259, 4350, 4367, 4373, 4790, 4802, 5138, 5223, 5834, 5937, 6038 (`@asyncFrameSize` — TYPE_INT_LIT temp → (0, 0)), 6074, 6077, 6107, 6109, 6164, 6176, 6207, 6225, 6236, 6255, 6734, 6842, 6931, 7158, 7174, 7232, 7250, 7574, 7820, 7864, 7873, 7900, 7938, 8561, 8664, 8690.

### 1.4 Carrier-influenced LIR spellings reduced to facts

The **materialization temp's carrier-typed result type** (`nextTemp(self, ut)` with `ut = c89_plan.untypedIntCarrier(...)` = TYPE_I32/U32/I64/U64 — a C-spelling choice recorded on LIR) is REDUCED: the temp becomes the untyped `TYPE_INT_LIT` and the width/signedness live on the `int_const` record. After this change LIR carries no carrier-flavored spelling for int consts (ruling (ii)); the carrier appears only in `C89SpellPlan` side-table state.

---

## 2. Planner derivation (`sf/src/c89_plan.zig`)

### 2.1 Derivation fn signatures

Keep the module shape and the per-const-ordinal side table (contract item 4). Change the derivation input to the LIR facts:

```zig
// THE derivation (facts -> carrier). width_bits == 0 is never passed here
// (the caller keeps the historical value rule for that class).
fn carrierFromFacts(width_bits: u8, is_signed: u8) u32 {
    if (width_bits == @intCast(u8, 32)) {
        if (is_signed != @intCast(u8, 0)) { return type_mod.TYPE_I32; }
        return type_mod.TYPE_U32;
    }
    if (is_signed != @intCast(u8, 0)) { return type_mod.TYPE_I64; }
    return type_mod.TYPE_U64;
}

pub fn deriveConstCarrier(reg: *TypeRegistry, semantic_tid: u32, value: u64, width_bits: u8, is_signed: u8) u32 {
    var hty = reg.types_items[@intCast(usize, semantic_tid)];
    if (hty.kind == TypeKind.integer_literal_type) {
        // UNTYPED hoisted: a fact-carryed exact-value materialization takes the
        // facts (the sign disambiguation lives here); a bare untyped literal
        // keeps the historical value rule (I32/U32/U64 — no i64 arm).
        if (width_bits != @intCast(u8, 0)) { return carrierFromFacts(width_bits, is_signed); }
        if (value <= @intCast(u64, 2147483647)) { return type_mod.TYPE_I32; }
        if (value <= @intCast(u64, 4294967295)) { return type_mod.TYPE_U32; }
        return type_mod.TYPE_U64;
    }
    if (semantic_tid == type_mod.TYPE_UNDEFINED) { return type_mod.TYPE_USIZE; }
    return semantic_tid;
}
```

(Replaces `deriveConstCarrier` at `c89_plan.zig:42-51` — the `integer_literal_type` value-rule text at `:45-47` is preserved verbatim.) **DELETE `untypedIntCarrier` (`c89_plan.zig:65-67`)** — after §3 it has 0 callers (verified: only `lower.zig:1664`/`:3622` call it today). Its `ce_mod` import (`c89_plan.zig:14`) becomes unused → delete the import too.

### 2.2 Side-table fill site (unchanged shape)

`spellPlanPlanFn` (`c89_plan.zig:119-165`): the fill call at `:156` becomes

```zig
                    var carrier = deriveConstCarrier(reg, ht, value, ic_width, ic_signed);
```

where `ic_width`/`ic_signed` come from the inst: in the `.int_const` arm (`:136-140`) read `ic.width_bits`/`ic.is_signed`; the `.binary`/`.unary`/`.int_cast` arms (`:141-144`) pass `0/0` (they are not consts yet; the const-fold gate keeps folded consts concrete-hoisted, so those rows take the identity branch — see §5.2). Keep the kind set (`int_const`/`binary`/`unary`/`int_cast`), the per-const flattened ordinal (`spellInstOrd`), and the hoisted-type lookup (`:146-154`) exactly as landed. No marker traffic (the `--markers` stream stays byte-identical).

### 2.3 Derivation-equivalence argument (every class → exactly the previously chosen carrier)

| class | hoisted type at the boundary | facts | old carrier (P6-pre) | new carrier |
|---|---|---|---|---|
| Class B: untyped exact materialization, neg `|v| ≤ 2^31` / nonneg `v < 2^31` | TYPE_I32 (carrier-typed temp) → identity | (32, 1) | TYPE_I32 | TYPE_I32 (`carrierFromFacts`) |
| Class B: nonneg `2^31 ≤ v < 2^32` | TYPE_U32 → identity | (32, 0) | TYPE_U32 | TYPE_U32 |
| Class B: neg `2^31 < |v| ≤ 2^63` / nonneg `2^32 ≤ v < 2^63` | TYPE_I64 → identity | (64, 1) | TYPE_I64 | TYPE_I64 |
| Class B: nonneg `2^63 ≤ v < 2^64` | TYPE_U64 → identity | (64, 0) | TYPE_U64 | TYPE_U64 |
| Class B: outside 64-bit | (no const; error[3000] dummy) | — | — | unchanged diagnostic |
| Class A: bare untyped literal (`lower.zig:4228`) / `@asyncFrameSize` (`lower.zig:6038`) | TYPE_INT_LIT | (0, 0) | value rule I32/U32/U64 (`deriveConstCarrier:45-47`) | same value rule (`:45-47` text preserved) |
| typed consts (all siblings, async, fold-produced) | concrete | (w,s) or indeterminate | identity | identity (facts NOT read — hoisted-kind gate) |
| TYPE_UNDEFINED hoisted | TYPE_UNDEFINED | — | TYPE_USIZE (`:49`) | TYPE_USIZE (unchanged) |

The i32-legacy print/tuple gate (`lowerExactIntArg` today: `if (ut == type_mod.TYPE_I32) return TEMP_NONE;` `lower.zig:1667`) becomes the fact test `fw == 32 and fs == 1` — identical class set. Sign pair: (64,1)→i64 vs (64,0)→u64 — resolved at the boundary from LIR facts (the exact gap fix). Pins 0/8 and probe const-spellings byte-identity expected by construction.

---

## 3. Lowering deletion/change list (`sf/src/lower.zig`)

### 3.1 `lowerExactIntArg` (`lower.zig:1659-1671`) — body replacement

DELETE: `var ut = c89_plan.untypedIntCarrier(fv.v) orelse { ... };` (`:1664-1667`), the `ut == TYPE_I32` gate (`:1667`), `var ctid = nextTemp(self, ut);` (`:1668`), and the 2-field const emit (`:1670`). REPLACE with (fact recording only):

```zig
fn lowerExactIntArg(self: *LirLowerer, node_idx: u32) u32 {
    var rtid: u32 = type_mod.TYPE_VOID;
    if (resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx)) |rt| rtid = rt;
    if (rtid != type_mod.TYPE_INT_LIT) return TEMP_NONE;
    var fv = foldPrintArgIntExact(self, node_idx) orelse return TEMP_NONE;
    var fw: u8 = @intCast(u8, 0);
    var fs: u8 = @intCast(u8, 0);
    if (!lowerUntypedIntFacts(self, fv.v, &fw, &fs)) {
        reportComptimeIntFits(self, node_idx);
        return nextTemp(self, type_mod.TYPE_I32);
    }
    if (fw == @intCast(u8, 32) and fs == @intCast(u8, 1)) return TEMP_NONE;
    var ctid = nextTemp(self, type_mod.TYPE_INT_LIT);
    emitIntConstFacts(self, ce_mod.comptimeIntMaterialize(fv.v), ctid, fw, fs);
    return ctid;
}
```

(The `error[3000]` dummy `nextTemp(self, type_mod.TYPE_I32)` is the historical diagnostic path — unchanged, no const emitted.)

### 3.2 `lowerFoldedIntConst` (`lower.zig:3617-3638`) — untyped arm replacement

DELETE `if (c89_plan.untypedIntCarrier(fv.v)) |ut| { ft = ut; } else { ... }` (`:3622-3628`) and the 2-field const emit (`:3635`). REPLACE with:

```zig
fn lowerFoldedIntConst(self: *LirLowerer, node_idx: u32, rtype: u32, check_fit: u8) ?u32 {
    if (ce_mod.comptimeFoldTableGet(self.ctx.comptime_folds, node_idx)) |fv| {
        if (fv.kind != ce_mod.KIND_INT) return null;
        var ft: u32 = rtype;
        var fw: u8 = @intCast(u8, 0);
        var fs: u8 = @intCast(u8, 0);
        var untyped: u8 = @intCast(u8, 0);
        if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) {
            if (!lowerUntypedIntFacts(self, fv.v, &fw, &fs)) {
                reportComptimeIntFits(self, node_idx);
                return nextTemp(self, type_mod.TYPE_I32);
            }
            ft = type_mod.TYPE_INT_LIT;
            untyped = @intCast(u8, 1);
        } else if (check_fit != @intCast(u8, 0)) {
            if (!ce_mod.comptimeIntFitsType(self.ctx.registry, fv.v, ft)) {
                reportComptimeIntFits(self, node_idx);
                return nextTemp(self, ft);
            }
        }
        var ctid = nextTemp(self, ft);
        if (untyped != @intCast(u8, 0)) {
            emitIntConstFacts(self, ce_mod.comptimeIntMaterialize(fv.v), ctid, fw, fs);
        } else {
            emitIntConst(self, ce_mod.comptimeIntMaterialize(fv.v), ctid);
        }
        return ctid;
    }
    return null;
}
```

### 3.3 Sibling sites + imports + comments

- The 50 sibling sites (§1.3 list) → `emitIntConst(self, X, Y);` (mechanical one-line rewrite per site; edit bottom-to-top).
- DELETE `const c89_plan = @import("c89_plan.zig");` (`lower.zig:39`) — 0 uses remain.
- Update the `foldPrintArgIntExact` comment block (`lower.zig:1608-1624`, names `c89_plan.untypedIntCarrier` at `:1619`) to the fact-recording wording; likewise the `lowerFoldedIntConst` doc comment (`:3611-3616`, "Untyped slots choose the temp type by exact value") → "Untyped slots record the exact value's semantic width/signedness on the int_const; the planner derives the C carrier at the boundary".

### 3.4 Grep-able invariant (apply step must show it)

```bash
grep -n "untypedIntCarrier\|comptimeIntUntypedType\|deriveConstCarrier\|intConstTypeForValue\|c89_plan" sf/src/lower.zig
→ EMPTY (no carrier-rule code in any lowering site)
```

Note: the >64-bit dummy `nextTemp(self, type_mod.TYPE_I32)` (error path) is a diagnostic placeholder, not a carrier decision (no const recorded) — historical, unchanged.

---

## 4. Emitter consumption (`sf/src/c89_emit.zig`)

The three landed side-table reads are UNCHANGED (the derivation behind the table changed): written-type walk `planConstCarrierAt(emitter, bb_idx, ii, hoisted)` (`:2610`), `nestEmitDefRvalue` `.int_const` (`:3508`), `emitInst` `.int_const` (`:6943`). `writeIntConstRvalue` (`:3705`) and the value-keyed suffixes `intLitSuffixUns`/`intLitSuffixNeg` (`:3855`/`:3861`) unchanged (C syntax surface; historical bytes). Because Class B temps become untyped (§1.4), two const-spelling sites must now read the planned carrier where they previously read the carrier-typed temp:

1. **NEW fact-carrier table (built in the existing written-type walk).** `C89Emitter` gains `d4_fcar: [*]u32` (beside `d4_wtype`/`d4_wflag`/`d4_t2p`, `c89_emit.zig:569-571`; init at `:649-651`). Allocate beside `raw_wt` in `emitHoistedDecls` (`:2446-2488` region; size `4 * max_temp`, init `0xFFFFFFFF`), store as `emitter.d4_fcar`. In the walk's `.int_const` arm (`:2606-2613`), after `written_type[dp] = planConstCarrierAt(...)` (`:2610`), add: if `ic.width_bits != 0` AND `lir_fn.hoisted_temps.items[dp].type_id` is `TYPE_INT_LIT` → `fact_carrier[dp] = written_type[dp];` (i.e. the planned carrier of a fact-carryed materialization; Class A `(0,0)` consts and typed consts leave `0xFFFFFFFF`).
2. **`nestScalarEffTid` (`:3201-3216`)** — after the existing `getTempEffType` + kind-whitelist attempt fails, add the fact-carrier read: look up `temp_id` via `emitter.d4_t2p` → pos → `emitter.d4_fcar[pos]`; if valid, return it. Effect: a fact-carryed materialization is a scalar of its planned carrier → `nestEffCType` (`:3218-3223`) casts with `getCTypeName(planned)` and `emitNestCompute` (`:3390`) inlines it exactly as today (byte-identical `printI64((zT_i64)((zT_i64)-3000000000LL))` shapes); Class A (no table entry) keeps returning `0xFFFFFFFF` (non-inlinable — today's `zT_8 = 5000000000ULL;` statement shape preserved). Implement as a small helper `fn factCarrierOfTemp(emitter: *C89Emitter, temp_id: u32) ?u32` (bounds-checked `d4_t2p`/`d4_fcar` read).
3. **`.print_val` scalar route (`:7549-7620`, call `getPrintFnName(emitter, p.type_id, p.fmt)` at `:7600`)** — compute `route_tid`: `if (factCarrierOfTemp(emitter, p.value)) |fc| { route_tid = fc; } else { route_tid = p.type_id; }` and pass `route_tid`. Effect: a fact-carryed materialization routes `printU32`/`printI64`/`printU64`/hex variants from the planned carrier (byte-identical routing); Class A keeps `p.type_id == TYPE_INT_LIT` → `printFnSourceName`'s forced 32/signed fallback (`:4617-4620`, unchanged); typed args unchanged. Update the Task-2 comment at `:4572-4585` to name the fact-carrier read ("the C carrier is planned at the boundary and read from `C89SpellPlan`; the print route reads the same planned carrier for fact-carryed materializations").

The aggregate/field printers (`getPrintFnName` at `:4758`/`:4985`) are type-driven (field types) — unchanged. `printValueRoute(ty.kind)` (`:7553`) sees `integer_literal_type` → scalar for Class B (same route class as the fact carriers' kinds) — unchanged.

---

## 5. Knock-on effects

1. **`lir.zig` record size / `lirStream*` serialization.** `int_const` payload grows 12 → 14 B (padded to the 16 B union slot) — still below `enum_const` (20 B → 24 B), so the Z98-folded `@sizeOf(LirInst)` stays **32 B** (the in-tree claims at `lir.zig:110-119`/`:134-143` remain true). `lir_stream.zig:142`/`:239-246` read/write `@sizeOf(lir_mod.LirInst)` bytes per inst — size-generic, unchanged. Tag ordinals unchanged (`int_const` keeps its union position). The opt's retarget copy (`lir_opt_pass.zig:1476` `var ni = ic; ni.result = newr;`) is a whole-payload copy — the facts ride along.
2. **`lirOptRun` rewrite stability (O3 — the note P12 must keep).** Unchanged properties: in-place rewrites only; fold gate `intKindWidth ≠ 0` (`lir_opt_pass.zig:200-206`) keeps folded consts concrete-hoisted; retarget gate `dt == st` (`:1581`/`:1667`-region) keeps the hoisted class; `int_const.value` never rewritten. Consequence for the fix: the side-table fill at the boundary (pre-opt) is complete exactly as in the report I.2 proof; the fold-produced `int_const`s (`lir_opt_pass.zig:2021`/`:2034`/`:2042`) leave the new fact fields **indeterminate** (file outside the fix's touch set) — SAFE because the planner reads facts **only for `integer_literal_type`-hoisted consts** (fold gate ⇒ never untyped) and the emitter's `d4_fcar` fill requires the same condition. Keep the O3 sentence verbatim in the report/tech-docs (a future rewrite that inserts/moves insts or relaxes those gates must re-evaluate the table).
3. **Out-of-touch-set construction sites (documented residue).** `async_state_machine.zig` (24 `.int_const` constructions) and `lir_opt_pass.zig` (3) cannot be edited (contract touch set). Their fact fields are indeterminate; all async result temps are typed (verified: 0 `TYPE_INT_LIT` in `async_state_machine.zig`) and fold-produced consts are concrete-hoisted, so the §2/§4 gates never read those fields. A P6/follow-up sweep may fill them when those files are in scope. Self-host safety: the fields are copied/serialized but never semantically consumed → hop1==hop2 emission is garbage-independent.
4. **Class B temps become `TYPE_INT_LIT` — consumer deltas beyond §4:**
   - `materializeShiftLhs` (`lower.zig:820-838`): a folded-const shift LHS now takes the existing untyped-LHS path under `-fsafe` (typed materialization `int_cast` + guard bound from the target). `-fsafe`-only; const spellings unaffected. Expected 0 battery impact (narrow shape); any pin delta is this documented consequence.
   - `materializeInto` (`lower.zig:3641-3760`): the optional/EU-layer int-cast guard `cur != src_ty` (`:3710-3712`) now sees `TYPE_INT_LIT` for fact-carryed sources, so `int_literal_coerce` casts fire where the fact type `== cur` previously suppressed them (`var x: ?u32 = <folded untyped>;` class). Same class: `lowerArrayElemTupleCoerce`'s `classifyCoercion(se_tid, te_tid)` (`:8600-8603` region). Const spellings unaffected. Expected 0 battery impact; any pin delta is this documented consequence.
   - `applyCoercion`'s kind-based arms (`:8610+`) are node-recorded-kind dispatch — unchanged.
   - `checkFoldedIntFits` now also runs where the `src_ty == expected` early return used to fire (`:3688`) — the fold fits by construction (its carrier class), so no new diagnostics.
   - `planConstCarrierAt` miss fallback (`:3887-3895`) would now spell from `TYPE_INT_LIT` instead of the carrier — unreachable per the I.2 population proof; note-only.
5. **`main.zig`:** no edits needed (the fill/planner signatures keep `spellPlanPlanFn(plan, alloc, reg, fn_key, lir_fn)`; `phase_EmissionClassification` `main.zig:1222-1240` and `CompilerContext.spell_plan` `:127` are unchanged).

---

## 6. Execution checklist (for the apply-dispatch)

### 6.1 Edit order (X.7: `edit`/`fastedit` only; read each region before editing; per file bottom-to-top; insert = replace the anchor line with new + original)

1. `sf/src/lir.zig:74` — the `int_const` payload (single edit).
2. `sf/src/lower.zig` bottom-to-top: sibling sites `:8690` → `:678` (50 one-line rewrites to `emitIntConst(self, X, Y);`); `lowerFoldedIntConst` `:3611-3638` (comment + body per §3.2); `lowerExactIntArg` `:1608-1671` (comment + body per §3.1, inserting `lowerUntypedIntFacts`/`emitIntConstFacts`/`emitIntConst` above `foldPrintArgIntExact` at `:1625` per the insert rule); delete import `:39`.
3. `sf/src/c89_plan.zig` bottom-to-top: fill call `:156` (facts args + the `.int_const` arm `:136-140` reads `ic.width_bits`/`ic.is_signed`, other kinds pass 0/0); delete `untypedIntCarrier` `:51-67` (comment + fn) and the `ce_mod` import `:14`; `deriveConstCarrier` `:33-51` → the §2.1 body (+ `carrierFromFacts`).
4. `sf/src/c89_emit.zig` bottom-to-top: `:7600` print route (§4.3); `:4572-4585` comment (§4.3); `nestScalarEffTid` `:3201-3216` + `factCarrierOfTemp` (§4.2); written-type `.int_const` arm `:2606-2613` + the `d4_fcar` alloc `:2446-2488` + the emitter field `:569-571`/`:649-651` (§4.1).
5. `sf/docs/tech_docs/`: `INDEX.md` Table A — update rows `deriveConstCarrier` (`:352`), `lowerExactIntArg` (`:661`), `lowerFoldedIntConst` (`:660`), `spellPlanPlanFn` (`:1145`); annotate `untypedIntCarrier` (`:1341`) **deleted (P6-pre fix round 1)**; add rows `lowerUntypedIntFacts`, `emitIntConst`, `emitIntConstFacts`, `carrierFromFacts`, `factCarrierOfTemp` (alphabetical). `07_lir_lowering.md` + `08_c89_emission.md`: title-line `[updated: 2026-10-12 — P6-pre fix round 1 …]` (newest-first) + the fact-fields/derivation/route notes. `09_pipeline_orchestration.md`: the phase-10 planner-step note if the boundary text mentions the derivation input.
6. Verification greps (paste output in the report): §3.4 invariant; `grep -n "width_bits" sf/src/lir.zig sf/src/lower.zig sf/src/c89_plan.zig sf/src/c89_emit.zig`.

### 6.2 Commits (exact messages; nothing else staged)

- (a) `fix(c89_plan): P6-pre — LIR semantic int facts; carrier derivation completes in planner` — `sf/src/**` + `sf/docs/tech_docs/**` ONLY.
- (b) `docs(sdd): P6-pre fix round 1` — the report by EXPLICIT PATH (`git add -f .superpowers/sdd/2026-10-12-zig1-emitter-sanitization-plan/task-P6pre-report.md`; append `## Fix round 1` to it: semantic-facts design, sign-collision resolution, the §2.3 derivation-equivalence proof, the battery). No push; `release/seed/` untouched.

### 6.3 Decision-identity probe (before the battery; the report's method — const-spellings byte-identical pre/post)

Build the P6-pre-fix compiler per QUICK_REF "SUBAGENT CHEAT-SHEET" (`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>`), then dump the carrier-sensitive probe (Finding-1 pairs `18446744073709551615` / `0 - 3000000000`; the i64/u64 window `9223372036854775807` / `9223372036854775808` / `5000000000`; untyped folds `2000000000 + 1000000000`; unannotated/annotated decls; if-join arms) pre/post and require:
- `diff <(grep -o 'z[a-zA-Z0-9_]* t[0-9]* = [^;]*;' OLD.c) <(… NEW.c)` → empty (CONST SPELLINGS IDENTICAL);
- `diff <(sort OLD.c) <(sort NEW.c)` → empty (LINES IDENTICAL UP TO ORDER).

### 6.4 Battery (8 items vs the frozen anchors; commands = QUICK_REF SUBAGENT CHEAT-SHEET copies)

| # | item | frozen anchor | expected |
|---|---|---|---|
| 1 | seed rebuild two-hop (`build_from_seed.sh`) | hop1==hop2 proven; current fixed point `a5e7c03341f014cba52936157f92fdfa` *(report/P6-pre; `progress.md` Task-0 ledger method)* | hop1==hop2; new fixed point recorded (compiler-moving; `FIXED_POINT_MD5` gate mismatch expected) |
| 2 | corpus classify | `task-0-report.md` Appendix A / `progress.md` "## Task 0": 1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH, class file md5 `518eca1a9b5d3e1cc5a48abce214abd8` | byte-identical class file, 0 movers |
| 3 | runtime goldens 5/5 | gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`, lisp `b3d9f8974da24ddbf9d389f3d7d97322`, json `8bda3d5a1ec07d14a301bc343df32bf8`, mud srv `66c8f0abb926cca7baf9a0d1692ab318` / cli `93147d0f0bbd983a9d844fea8b7a6fa7` *(task-0-report / P6-pre report)* | 5/5 byte-identical |
| 4 | mi_matrix anchors 25 + oob | `task-0-report.md` §1.8 / `progress.md` "## Task 0": `run_fixtures.sh` 25 PASS / 0 FAIL; `slice_index_field_store_oob_xmod` rc=133 + empty stdout md5 `d41d8cd98f00b204e9800998ecf8427e` | 25/25 MATCH + oob MATCH |
| 5 | examples/z98/*/ 26 build + 26 run | P6-pre report §5 table (per-dir rc + stdout md5_16; mud rc=124, z9play/z9torr rc=1) | 26/26 identical |
| 6 | stdlib gate | `verify_stdlib.sh` 285 PASS / 0 FAIL | 285/0 green |
| 7 | 8 `--dump-c89` pins old→new | P6-pre values: mud `-fsafe` `8b3c3d72ab59a9ae3c971c6a7759c7c0` / `-ffast` `fa346108ed00d03a037c2f9331d3bdf8`; gol `1b5d49b141ee9c664a82c270454bd75b` / `01a4e2265b33c97a8ca6ff3dfa551231`; lisp `8e5f2bc288d1dc75d7aee284cb35c291` / `e3970e33ac09c8dfaa316d2d69bf61ec`; json `2a12d0aac24d5bcdd694f05e04a4f029` / `24e0e812e7dffa5a43750135405ffe3f` | 0/8 delta expected; any delta explained by §5.4 classes (probe const-spellings must still be identical) |
| 8 | `--markers` telemetry | 3,436 lines / 38,378 B (P2-P6-pre record) | identical counts (planner step emits no markers) |

Report `## Fix round 1` must contain: command + observed output per claim, the §3.4/§6.1 greps, the §6.3 probe evidence, and the §2.3 table.

### 6.5 STOP conditions (verbatim form if hit)

Touch set is `sf/src/lir.zig`, `sf/src/lower.zig`, `sf/src/c89_plan.zig`, `sf/src/c89_emit.zig`, `sf/docs/tech_docs/` (§5.5 `main.zig` not needed). Anything outside, or any battery divergence not covered by §5.4 → `BLOCKED — I found the intention is X, but this is impossible given Y` (Y = evidence `file:line` + command output). Do not invent a variant.
