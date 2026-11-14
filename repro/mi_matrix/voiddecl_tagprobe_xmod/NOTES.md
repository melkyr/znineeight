# voiddecl_tagprobe_xmod — `.tag` discriminator accessor probe (Root 2, F2)

**Status: DONE** (2026-08-19, F2). RED→GREEN probe for the tagged-union `.tag`
discriminator accessor gap in `semanticAnalyzerResolveFieldAccess` — Root 2 of the
voiddecl family, the mechanism behind the 5 residual self-compile error[3000] sites
(`sf/src/lower.zig:5218/5275/5319/5395/5403`).

## Purpose

Task F2 of the voiddecl-family plan (docs/superpowers/plans/
2026-08-18-voiddecl-family-plan.md, lines 411-413). Re-created (committed) `.tag`
probe faithful to lower.zig:5218's real carrier: a fn-local, pointer-deref chain of
struct-typed list-of-union accesses ending in a `.tag` discriminator read consumed by
`var tg = @enumToInt(inst.tag)`.

## Carrier (faithful to lower.zig:5218 `findTailCall`)

Real chain: `var blk = self.func.blocks.items[bi]; var inst = blk.insts.items[ii];
var tg = @enumToInt(inst.tag);` where `self.func: *LirFunction`, `LirFunction.blocks`
is a `BasicBlockArrayList`, `blk` is a `BasicBlock`, `blk.insts` is a
`LirInstArrayList`, `inst` is a `LirInst = union(enum)` (lir.zig:22).

Committed fixture mirrors it 1:1:
- mod.zig: `Item = union(enum)` (the LirInst analogue), `InstList{ items: [*]Item, len: usize }`
  (the LirInstArrayList analogue), `Blk{ id, insts }` (BasicBlock), `BlkList`
  (BasicBlockArrayList), `Func{ blocks }` (LirFunction).
- main.zig: `findTailCall(func: *mod.Func)` walks `func.blocks.items[bi]` →
  `blk.insts.items[ii]` → `inst` (local value copy) → `@enumToInt(inst.tag)`.

## RED baseline (pre-fix, HEAD `27c71619`, binary /tmp/fx_subfolder/zig1)

Recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/tagprobe_red main.zig`
```
dump rc = 2
stderr:
main.zig:11:12: error[3000]: cannot declare variable of type void
            var inst = blk.insts.items[ii];
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```
- stdout (`.c`) = 0 bytes — compile aborts, nothing emitted.
- The reported line (11 = `var tg = @enumToInt(inst.tag);`) is the span's line; the
  caret prints the line above (off-by-one display, as in R1-R4). The `.tag` read
  resolves to TYPE_VOID via the NF/FF2 fallback (semantic_analyzer.zig:588-591); the
  consuming `var tg` hard-errors.
- The whole chain up to `inst` is properly typed (fn-local pointer-deref carrier —
  the R4 matrix row-8 blind spot never reached the `.tag` member read).

## GREEN control (same fixture, /tmp only)

`var tg = @enumToInt(U.num)` where `U` is a union with an explicit `num: u32` field
read through the variant-field path — compiles byte-identically pre/post fix. The
discriminator `.tag` path is the ONLY thing under test.

## Post-fix expectation

`var tg = @enumToInt(inst.tag)` resolves `.tag` → `tp.tag_type`
(`TaggedUnionPayload.tag_type`, type_registry.zig:83) in the tagged_union_type branch
of `resolveFieldAccess`. Fixture flips RED→GREEN: dump rc=0, per-module `.c` emitted,
gcc rc=0, and (this fixture's loops have len=0, so no undefined deref at runtime) the
binary runs and prints `7`.

## Cross-ref

R4-E sibling (module-var carrier + shared Root-1 shape):
`repro/mi_matrix/voiddecl_xmodtype_xmod/`. Root-2 mechanism record: `.superpowers/
sdd/task-I-XMODTYPE-report.md` §2a + §4 (fix B). Plan: docs/superpowers/plans/
2026-08-18-voiddecl-family-plan.md lines 411-413.
