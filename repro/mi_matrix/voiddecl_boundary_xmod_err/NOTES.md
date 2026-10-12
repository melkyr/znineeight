# voiddecl_boundary_xmod_err — extra_children 65,536 boundary probe, error[3000] variant  [R1-variant, 2026-08-19]

## Purpose
Second boundary-repro fixture for the self-compile silent-drop plan
(docs/superpowers/plans/2026-08-18-self-compile-silent-drop-plan.md). The
committed sibling `voiddecl_boundary_xmod` (069b6b35) proves the same
65,536-boundary bug in the AST extra-children payload encoding
(`astStoreAddExtraChildren`, sf/src/ast.zig:424 packs `(start << 16) | count`
into u32; when `store.extra_children.len >= 65536`, `start << 16` wraps), but
its RED was a *silent drop* (std parsed last, dropped, empty stdout, rc=0).
THIS variant reproduces the plan's literal predicted form: **error[3000]
"cannot declare variable of type void"** on a struct-return call into the
dropped module.

## Import-order / LIFO reasoning
`importQueueDequeue` is a LIFO pop (module_registry.zig:443-445), so the
FIRST-imported module is parsed LAST. `main.zig` imports `m1` on line 1,
*before* `@import("std")`, so `m1` is parsed last — after the boundary is
crossed — and is the silently-dropped module. `var a = m1.make();` (make
returns `S` from the dropped module) then fails qualified lookup → Q1VF
fallback TYPE_VOID (semantic_analyzer.zig:424-426) → error[3000]
(semantic_analyzer.zig:1915-1922).

Observed parse order (`--markers`, import_resolver.zig IRP lines; module
root payload = `(start << 16) | count` of top-level decls):

| parse order | mod | decoded start | decoded count | wrapped? |
|-------------|-----|---------------|---------------|----------|
| 1 | main.zig | 3 | 9 | no |
| 2 | std.zig | 12 | 2 | no |
| 3 | std_arena.zig | 38 | 6 | no |
| 4 | std_io.zig | 104 | 7 | no |
| 5 | m7.zig | 115 | 10900 | no |
| 6 | m6.zig | 11019 | 10900 | no |
| 7 | m5.zig | 21923 | 10900 | no |
| 8 | m4.zig | 32827 | 10900 | no |
| 9 | m3.zig | 43731 | 10900 | no |
| 10 | m2.zig | 54635 | 10900 | no |
| 11 | **m1.zig** | **3** | **10900** | **YES — actual start 65539, wrapped to 3** |

m1's true start = 54635 + 10900 + 4 = 65539 >= 65536 → `start << 16`
overflows → decodes to 3 → m1 registers 0 correct children (reads main's
early region). **Dropped module = m1.**

## Boundary pinning (N=7, run from fixture dir, const sweep)
This variant crosses later than the sibling: m1 parses after only 6 sibling
modules (std tree parses early, positions 2-4), so ~10k consts is NOT enough
— K must push 6 modules past 65,536 before m1. Pinned:

| consts/module | 7×consts | m1 true start | verdict |
|---------------|----------|---------------|---------|
| 10,000 | 70,000 | 60,156 | GREEN (prints `1`) |
| 10,896 | 76,272 | 65,527 | GREEN |
| 10,897 | 76,279 | 65,533 | GREEN (prints `1`) |
| 10,898 | 76,286 | 65,539 (WRAPPED→3) | RED (error[3000]) |
| 10,899 | 76,293 | 65,545 (WRAPPED→9) | RED (error[3000]) |

Fixture committed at the minimal RED K=10,898 (each module = 10,898
`pub const vNNNN: u32 = NNNN;` + `pub const S = struct { v: u32 };` +
`pub fn make() S { var f = S{ .v = K }; return f; }`, K = module number).

## RED baseline (2026-08-19, /tmp/fx_subfolder/zig1 @ 8ca7beba, run FROM fixture dir)
```
mkdir -p /tmp/r1e
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r1e main.zig
```
- **dump rc=2**, stdout 0 bytes.
- **No .c files emitted** (compile aborts in semantic analysis, before codegen).
- Verbatim stderr (220 bytes):
```
main.zig:10:4: error[3000]: cannot declare variable of type void
pub fn main() void {
    ^^^^^^^^^^^^^^^^^^
m1.zig:11:3: error[3000]: cannot declare variable of type void
pub const v0009: u32 = 9;
   ^^^^^^^^^^^^^^^^^^
```
- Line 10 of main.zig = `var a = m1.make();` (struct-return call into the
  dropped module) — matches the plan's predicted error[3000] form exactly.

## GREEN control (below boundary — NOT committed, kept in /tmp/ctrl_e)
N=2, same shape (m1 imported first), 10k consts each (~20k extra_children
< 65,536): `dump rc=0 | gcc rc=0 | run rc=0 | stdout: "1"`   ✓ GREEN

## Post-F1 expectation
After the F1 whole-class sweep (u16 array-index overflow fix), this N=7
fixture compiles GREEN: m1 registers its 10,900 children, `m1.make()` resolves
to struct `S`, and the run prints `1`.

## Recipe
```bash
cd repro/mi_matrix/voiddecl_boundary_xmod_err
mkdir -p /tmp/r1e
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r1e main.zig
```
