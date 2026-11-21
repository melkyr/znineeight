# emission_local_dedup_cap_xmod — RED fixture for root cause B (local-name reuse + 128-slot dedup cap)

Task R (2026-08-20). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Minimal reproducer of **root cause B** from the Task D discovery report:
`emitFunctionBody`'s `decl_local` arm (`sf/src/c89_emit.zig:6054-6090`)
dedups local declarations by `name_id` using a **fixed 128-slot**
`dedup_names` array (`:6055-6064`; capacity guard `if (dedup_count < 128)`
at `:6061`). When a function has >128 distinct named locals, the array fills
and every subsequent same-name `decl_local` is emitted again → gcc class-2
`redeclaration of '<name>' with no linkage`. Matches the D-report evidence
`lower_1EB7D337.c:29498` (50× `t` decls in one function, 44 redeclaration
errors).

## Fixture (verbatim)
```zig
const std = @import("std");

pub fn main() void {
    var v0: i32 = 0;
    var v1: i32 = 0;
    ...  (v0..v139: 140 distinct locals, each `var v<N>: i32 = 0;`)
    {
        var t: i32 = 1;
        std.io.printInt(t + v139);
    }
    {
        var t: i32 = 2;
        std.io.printInt(t);
    }
    {
        var t: i32 = 3;
        std.io.printInt(t);
    }
}
```
(Full source in `main.zig`; the 140 `var v0..v139` lines overflow the
128-slot `dedup_names` array, then the name `t` is reused in three nested
blocks.)

## RED baseline (measured 2026-08-20, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rfx main.zig
rc=0
$ cd /tmp/rfx && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class 2, `redeclaration of 't' with no linkage`):
```
main_DCF5BB78.c:582:9: error: redeclaration of 't' with no linkage
main_DCF5BB78.c:583:9: error: redeclaration of 't' with no linkage
```
Emitted C: `int t;` appears **3 times** in the same function's declaration
block (verified `grep -c "int t;"` = 3; `v120..v139` present above it,
confirming >128 distinct names filled the dedup array first).

## Root cause pinned
`sf/src/lower.zig:628-677` (`addLocalDecl`/`maybeDisambiguateCapture` — only
captures are disambiguated, ordinary locals reusing short names keep the same
`name_id`), `sf/src/c89_emit.zig:6055-6064` and `:6061` (128-slot
`dedup_names` cap), `:6080-6088` (decl emission). Root cause B of the D
report.

## Expected post-fix result
After removing the 128-slot cap (or fixing dedup to a growable set), the
redeclared `t` locals are emitted once; gcc `-c` rc=0 and the binary prints
`1 2 3`.
