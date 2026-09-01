# voiddecl_boundary_xmod — extra_children 65,536 boundary probe  [R1, 2026-08-19]

## Purpose
Task R1 (AMENDMENT) of the self-compile silent-drop plan
(docs/superpowers/plans/2026-08-18-self-compile-silent-drop-plan.md).
Durable RED repro proving the 65,536-boundary bug in the AST extra-children
payload encoding: `astStoreAddExtraChildren` (sf/src/ast.zig:424) packs
`(start << 16) | count` into the u32 `AstNode.payload`; when
`store.extra_children.len >= 65536`, `start << 16` wraps, so module_root
payloads stored at/after the crossing decode to wrong early regions and those
modules silently register nothing (0 named types). Will flip GREEN after the
F1 whole-class sweep (u16 array-index overflow fix).

## Fixture
`main.zig` imports `std` + `m1.zig`..`m7.zig` (N=7 sibling modules). Each
module has ~10,000 `pub const vNNNN: u32 = NNNN;` lines (v0000..v9999) plus:
```zig
pub const S = struct { v: u32 };
pub fn make() S { var f = S{ .v = K }; return f; }   // K = module number
```
`main.zig` (bare `@import("std")`, Z98 dialect, no anytype/@Type):
```zig
const std = @import("std");
const m1 = @import("m1.zig"); ... const m7 = @import("m7.zig");
pub fn main() void {
    var a = m1.make();
    var b = m7.make();
    std.io.printInt(a.v);
    std.io.writeByte(@intCast(u8, ' '));
    std.io.printInt(b.v);
}
```
Expected GREEN output: `1 7`. Fixture is generator output (script in /tmp,
not committed).

## Boundary crossing rationale
Each 10k-const module contributes ~10,002 top-level decls → ~10,000+
extra_children. N=7 ≈ 70k extra_children > 65,536 → the payload `start` field
(u16 in the low/high packing) wraps for every module_root stored after the
crossing. Boundary pinned by const-count sweep (N=7, run from fixture dir):

| consts/module | 7×consts | verdict |
|---------------|----------|---------|
| 9,300         | 65,100   | GREEN `1 7` |
| 9,350         | 65,450   | RED (empty output) |
| 10,000        | 70,000   | RED (empty output) |

## Parse order (LIFO import queue) — observed, not assumed
Compiler markers (`--markers`, import_resolver.zig:148/171) show module
parse order and each module_root payload/child count:

| parse order | mod | payload | decoded start | decoded count |
|-------------|-----|---------|---------------|---------------|
| 1 | main.zig | 0x000a0009 | 10 | 9 |
| 2 | m7.zig | 0x00172712 | 23 | 10002 |
| 3 | m6.zig | 0x272d2712 | 10029 | 10002 |
| 4 | m5.zig | 0x4e432712 | 20035 | 10002 |
| 5 | m4.zig | 0x75592712 | 30041 | 10002 |
| 6 | m3.zig | 0x9c6f2712 | 40047 | 10002 |
| 7 | m2.zig | 0xc3852712 | 50053 | 10002 |
| 8 | m1.zig | 0xea9b2712 | 60059 | 10002 |
| 9 | **std.zig** | 0x11ad0002 | **4525 (WRAPPED)** | **2** |
| 10 | std_arena.zig | 0x11c70006 | 4551 (WRAPPED) | 6 |
| 11 | std_io.zig | 0x12090007 | 4617 (WRAPPED) | 7 |

`importQueueDequeue` is a **LIFO pop** (module_registry.zig:443-445,
`importQueuePendingPop` returns the LAST item). `main.zig` imports `std` on
line 1 (bare-std convention), so `std` is enqueued first and **parsed LAST**,
after all 7 siblings. The boundary (extra_children.len >= 65536) is crossed
during module #9 (std.zig) — `start=70063` wraps to 4525. **std.zig,
std_arena.zig and std_io.zig are the silently-dropped modules**, NOT an
m-module (all m1..m7 decode correctly with count=10002).

## RED baseline (2026-08-19, /tmp/fx_subfolder/zig1 @ 8ca7beba, run FROM fixture dir)
```
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r1out main.zig
```
- **dump rc=0**, stderr EMPTY (no error text, no error[3000]).
- All 7 module .c files emitted, all `make()` functions emitted with correct
  struct return types (m1 → v=1 … m7 → v=7).
- **std_io.c, std_arena.c, std.c emitted EMPTY** (only `#include` + `/* EOF */`)
  — the std modules registered nothing.
- main.c emitted WITHOUT the printInt/writeByte statements (they silently
  resolve to void and are dropped):
  ```c
  zT_1 = zF_E18C56AF_make();   a = zT_1;
  zT_3 = zF_E18C56AF_make_1(); b = zT_3;
  b = zT_3; b = zT_3; b = zT_3;
  return;
  ```
- `gcc -m32 -std=c89 ... rc=0` (links fine — nothing references the dropped
  std symbols).
- **run rc=0, stdout EMPTY** (expected `1 7`). **RED.**

Verbatim stderr: *(no output — silent drop, no diagnostic emitted)*

Observed deviation from brief prediction: the brief expected error[3000]
"cannot declare variable of type void" on a struct-return call. Instead the
dropped module is the bare-std module (imported first → parsed last), whose
loss silently kills the `std.io` print calls (and main's print statements) —
wrong output with rc=0 and zero diagnostics. This is still a clean, durable
RED proving the boundary wrap (payload decode 0x11ad0002 for std.zig vs
expected ~0x1108_2712).

## GREEN control (below boundary — NOT committed, kept in /tmp/ctrl)
N=2, same module shape, 10k consts each (~20k extra_children < 65,536):
```
dump rc=0 | gcc rc=0 | run rc=0 | stdout: "1 2"   ✓ GREEN
```

## Post-F1 expectation
After the F1 whole-class sweep (u16 array-index overflow fix), this N=7
fixture compiles GREEN: std/std_arena/std_io emit their full bodies, main's
printInt/writeByte calls emit, and the run prints `1 7`.

## Recipe
```bash
cd repro/mi_matrix/voiddecl_boundary_xmod
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r1out main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
  -I /workspace/znineeight/sf/src/include \
  /tmp/r1out/*.c /workspace/znineeight/sf/src/include/zig_runtime.c \
  /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/r1out/x
/tmp/r1out/x
```
