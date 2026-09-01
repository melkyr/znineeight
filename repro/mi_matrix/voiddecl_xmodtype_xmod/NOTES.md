# voiddecl_xmodtype_xmod — RED trigger: cross-module struct/tagged-union refs via untyped module-level carriers

**Status: DONE** (2026-08-19). Reproduces `error[3000] cannot declare variable of
type void` for shapes D+E — the last of the 4 shape classes behind the 9 residual
self-compile blockers:
- shape D = `main.zig:588` `var sem_ctx: SemanticContext = SemanticContext{ … }`
  where `SemanticContext` is the **untyped module-level alias**
  `const SemanticContext = lower_mod.SemanticContext;` (main.zig:30, cross-module
  struct with pointer fields).
- shape E = `lower.zig:5218/5275/5319/5395/5403` `var inst = blk.insts.items[ii];`
  where `LirInst` is a tagged `union(enum)` (lir.zig:22) reached by multi-hop field
  access (`blk = self.func.blocks.items[bi]`, blk.insts = `LirInstArrayList`,
  `.items[ii]` = LirInst).

## Purpose
Task R4 of the voiddecl-family plan (docs/superpowers/plans/
2026-08-18-voiddecl-family-plan.md). Minimal RED repro + GREEN control isolation +
type-kind matrix for the cross-module struct/tagged-union void collapse.

## Escalation (brief Step 1 ladder — literal fixture was GREEN, as R1/R2/R3 predicted)
The brief's literal main.zig (`var c: mod.Ctx = mod.Ctx{…}`, `var inst =
blk.insts.items[0]` from `mod.makeBlk()`) compiles clean (rc=0). The poison is the
**untyped module-level carrier referenced from value position** (R1/R2/R3 lesson),
and the **two-step cross-module type alias in an annotation** (the real
main.zig:30 shape). The committed fixture carries shape D through the alias
(`const SC = mod.Ctx;` = main.zig:30's `const SemanticContext = lower_mod.
SemanticContext;`) and shape E through an untyped module-level struct var
(`pub var gblk = Blk{…}`), exactly mirroring the module-var/const carrier shape the
R3 fixture (`var node = Node{…}`) established.

## Fixture (committed)

main.zig (md5 `596306a47e38ee8eb38335c9977f5255`):
```zig
const std = @import("std");
const mod = @import("mod.zig");
const SC = mod.Ctx;
pub fn main() void {
    var c: SC = SC{ .store = undefined, .v = 7 };
    var inst = mod.gblk.insts.items[0];
    std.io.printInt(c.v);
}
```

mod.zig (md5 `3ba9471aa8a27455c20be14548cfdee9`) — brief's types + the two untyped
module-level carriers:
```zig
pub const Item = union(enum) { num: u32, none: void };
pub const InstList = struct { items: [*]Item, len: u32 };
pub const Blk = struct { insts: InstList };
pub const Inner = struct { v: u32 };
pub const Ctx = struct { store: *Inner, v: u32 };
pub var gctx = Ctx{ .store = undefined, .v = 7 };
pub var gblk = Blk{ .insts = InstList{ .items = undefined, .len = 0 } };
pub fn makeBlk() Blk {
    var b = Blk{ .insts = InstList{ .items = undefined, .len = 0 } };
    return b;
}
pub fn makeCtx() Ctx {
    var c = Ctx{ .store = undefined, .v = 7 };
    return c;
}
```

## RED baseline (brief Step 2, from fixture dir)
Recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig`
```
rc = 2
stderr:
main.zig:5:4: error[3000]: cannot declare variable of type void
main.zig:6:4: error[3000]: cannot declare variable of type void
```
- stdout (`.c`) = 0 bytes — compile aborts, nothing emitted.
- Error at 5:4 = shape D (`var c: SC = SC{…}`); error at 6:4 = shape E (`var inst =
  mod.gblk.insts.items[0]`). Both fire in the same run (BOTH shapes independently
  trip — see GREEN control isolation below). Caret/line display off-by-one as in
  R1-R3 (reports the span's line, prints the line above).

## GREEN control isolation (brief Step 3, /tmp only)
| construct | form | dump rc | gcc rc | run | verdict |
|-----------|------|---------|--------|-----|---------|
| shape D alone | `var c = mod.makeCtx();` (fn-call carrier, inferred) | 0 | 0 | prints `7`, rc=0 | GREEN |
| shape E alone | `var blk = mod.makeBlk(); var inst = blk.insts.items[0];` (fn-call carrier) | 0 | 0 | SIGSEGV* (undefined many-ptr deref) | GREEN compile |
| shape D alone (module-var carrier) | `var c = mod.gctx;` | 2 | — | — | RED |
| shape E alone (module-var carrier) | `var inst = mod.gblk.insts.items[0];` | 2 | — | — | RED |
Each construct trips independently; committed fixture fires both.
\* ctlE runs but derefs `undefined` items pointer → SIGSEGV at runtime; this is
fixture data, not a compiler defect (dump+gcc both clean). The committed fixture's own
line 6 (`var inst = mod.gblk.insts.items[0];`) carries the same undefined-deref
implication — hence the fixture is compile-gate only and can never print `7` (see
Post-fix expectation).

## Escalation ladder (brief Step 1 ladder + extras, all probed in /tmp)
| # | form | dump rc | verdict |
|---|------|---------|---------|
| 1 | **brief literal** (`var c: mod.Ctx = mod.Ctx{…}` + `var inst = blk.insts.items[0]` from makeBlk) | 0 | GREEN |
| 2 | `var c = mod.makeCtx();` inferred struct | 0 | GREEN |
| 3 | `var c: mod.Ctx = mod.makeCtx();` annotated | 0 | GREEN |
| 4 | `var c = mod.Ctx{…}` inferred struct-literal | 0 | GREEN |
| 5 | `var blk = mod.makeBlk(); var inst = blk.insts.items[0];` (fn-call) | 0 | GREEN |
| 6 | `var f = mod.makeFunc(); var blk = f.blocks.items[0]; var inst = blk.insts.items[0];` (multi-hop, fn-call) | 0 | GREEN |
| 7 | `var inst = mod.makeFunc().blocks.items[0].insts.items[0];` (chained) | 0 | GREEN |
| 8 | `self.func.blocks.items[0]` pointer-deref chain (findTailCall-faithful) | 0 | GREEN |
| 9 | `var inst = mod.gblk.insts.items[0];` (untyped module-var carrier) | 2 | RED |
| 10 | `var blk = mod.gblk; var inst = blk.insts.items[0];` (module-var → local hop) | 2 | RED |
| 11 | `var c: SC = SC{…}` two-step alias (COMMITTED shape D) | 2 | **RED** |
| 12 | `var c: SC = mod.makeCtx();` alias + fn-call | 2 | RED |
| 13 | `var c: SC = mod.gctx;` alias + module-var | 2 | RED |
| 14 | `var c = mod.gctx;` module-var carrier, inferred (no alias) | 2 | RED |
| 15 | `var c = mod.Item{ .num = 5 };` union struct-literal local | 0 | GREEN |
| 16 | `const gblk = Blk{…}; var inst = mod.gblk.insts.items[0];` (module-const carrier) | 2 | RED |
Key: annotation + fn-call/struct-literal carriers all GREEN; the untyped module-level
carrier (var OR const) in an inferred var-init is RED; the two-step alias
(`const SC = mod.Ctx`) in an annotation is RED (matches main.zig:30 + :588 exactly).

## Type-kind matrix (brief Step 4)
| # | variant | dump rc | verdict |
|---|---------|---------|---------|
| 1 | struct annotation + struct-literal init `var c: mod.Ctx = mod.Ctx{…}` (brief's D) | 0 | GREEN — direct cross-module annotation masks |
| 1' | **same via two-step alias `const SC = mod.Ctx` (main.zig:30-faithful, committed)** | 2 | **RED** |
| 2 | struct inferred `var c = mod.makeCtx();` | 0 | GREEN |
| 2' | struct inferred via module-var carrier `var c = mod.gctx;` | 2 | RED |
| 3 | tagged-union field-access inferred `var inst = blk.insts.items[0]` (fn-call carrier) | 0 | GREEN |
| 3' | **tagged-union field-access inferred via module-var carrier `var inst = mod.gblk.insts.items[0]` (committed)** | 2 | **RED** |
| 4 | union type in annotation `var it: mod.Item = mod.gi;` | 0 | GREEN (warning[3000] type mismatch — void computed, downgraded) |
| 5 | plain enum cross-module annotation `var e: mod.E = mod.ge;` | 0 | GREEN (warning[3000]) |
| 6 | error-set cross-module annotation `var e: mod.ESet = error.A;` | 0 | GREEN (no warning) |
| 7 | array/slice cross-module annotation `var a: mod.Arr = mod.garr;` | 0 | GREEN (warning[3000]) |
| 8 | field-access depth (fn-call carrier): 1 hop `blk.insts` / 2 `blk.insts.items` / 3 `[i]` | 0 / 0 / 0 | GREEN — depth innocent |
| 8' | same depths via module-var carrier `mod.gblk.insts` / `.items` / `.items[0]` | 2 / 2 / 2 | RED — depth does NOT matter; the module-var is the poison |

## Blast-radius lead (feeds I-XMODTYPE)
RED requires an **untyped module-level var/const referenced in value position in an
inferred var-init** — the identical R1/R2/R3 poison (module-level reference → void
in value position) — carried here by the cross-module struct/tagged-union shape. The
brief's hypothesis "cross-module struct/tagged-union refs in annotation +
field-access resolve to void" is only half right: cross-module **direct** annotation
(matrix 1) is GREEN and masks; the **two-step module-level alias** in the annotation
(matrix 1') is RED and is the exact main.zig:30 + :588 shape. Field-access depth
(matrix 8 vs 8') is innocent; fn-call/struct-literal carriers are innocent. The
tagged-union KIND is innocent (direct union annotation matrix 4 GREEN). Poison =
untyped module-level carrier; the cross-module struct/tagged-union is the carrier.
I-XMODTYPE should pursue the same untyped module-level const/var resolution path as
I-IFEXPR / I-SWITCHEXPR / I-U64CAST, PLUS the two-step alias-in-annotation path
(`const T = other_mod.T;` used as a type).

## Post-fix expectation
Committed fixture flips RED→GREEN as a **compile gate**: dump rc=0, gcc rc=0. It does
NOT print `7` — main.zig:6 (`var inst = mod.gblk.insts.items[0];`) derefs the
`undefined [*]Item` carrier and SIGSEGVs at runtime BEFORE the printInt on line 7
(identical undefined-deref to ctlE). The print-`7` vehicle is the D-alone control
(`var c = mod.makeCtx();`), not this fixture. Escalation rows 9/10/11/12/13/14/16
(7 of 16 ladder rows RED) and matrix 1'/2'/3'/8' (4 of 12 matrix rows RED) flip too —
the exact RED sets in the tables above. main.zig:588 should leave the self-compile
error set. Whether the 5 lower.zig sites (5218/5275/5319/5395/5403) flip is NOT
established here: the committed E-shape proves the module-var tagged-union
field-access path trips, but lower.zig:5218's exact carrier
(`blk = self.func.blocks.items[bi]`, a fn-local pointer-deref chain) was GREEN in the
matrix (row 8 — probed only to BasicBlock, never the full `blk.insts.items[ii]` →
LirInst chain, never the tagged-union member access). I-XMODTYPE must confirm the
real-site mechanism before claiming all 5 sites flip.

## Cross-ref
R1 sibling (if-expr carrier): `repro/mi_matrix/voiddecl_ifexpr_xmod/`. R2 sibling
(switch-expr carrier): `repro/mi_matrix/voiddecl_switchexpr_xmod/`. R3 sibling (u64
`&`/intCast carrier): `repro/mi_matrix/voiddecl_u64cast_xmod/`. Self-compile
9-error set re-verified on this binary: main.zig:588, symbol_registrator.zig:258/:357,
lower.zig:4410/:5218/:5275/:5319/:5395/:5403.
