# emission_lower_crash_xmod — RED fixture for the self-compiled lowering crash (R-LOWERCRASH, B1)

Task B1 R-LOWERCRASH (2026-08-25), `docs/superpowers/plans/2026-08-25-labeled-break-and-selfcompile-crash-plan.md`
(lines 88-107). Branch `zig1_start`. Reference: `/tmp/fx_subfolder/zig1` (working zig0-built
reference). Self-compiled: `/tmp/zig1_5/zig1_5_clean` (rebuild via `scripts/self_compile/build_zig1_5.sh`
— the prior build predated the A2 labeled-break fix, so it was rebuilt for this task).

## Purpose

Minimal single-module, **ZERO-switch** std-importing program that SEGVs the self-compiled
`zig1_5` binary in LIR lowering. The trigger class is the std import itself: the self-compiled
binary crashes at `sf/src/lower.zig:2261-2269` (ident_expr path) for ANY std-importing program
regardless of switches. `binexpr_test.zig`-style body: a local `var a: i32 = 1 + 2;` read via a
function call (`std.io.printInt(a)`).

## Fixture (verbatim — B1 source, single module)

`main.zig`:
```zig
const std = @import("std.zig");
fn run() void {
    var a: i32 = 1 + 2;
    std.io.printInt(a);
}
pub fn main() void {
    run();
}
```

## RED evidence (measured 2026-08-25)

### Reference (zig0-built /tmp/fx_subfolder/zig1) — GREEN

```
$ cd /workspace/znineeight/repro/mi_matrix/emission_lower_crash_xmod
$ rm -rf /tmp/fx_lc_out && mkdir -p /tmp/fx_lc_out
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fx_lc_out main.zig
dump rc=0          (emits main_3DF5832C.c + std_*.c via default lib path <exe>/lib)
$ cd /tmp/fx_lc_out && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc rc=0
$ gcc -m32 -std=c89 ... *.c <repo>/sf/src/include/zig_runtime.c <repo>/sf/src/include/zig_pal.c -o /tmp/fx_lc_bin
link rc=0
$ /tmp/fx_lc_bin
3
run rc=0           (EXPECTED — 1 + 2 = 3 via std.io.printInt)
```

### Self-compiled (/tmp/zig1_5/zig1_5_clean) — RED (rc=139 SEGV)

```
$ rm -rf /tmp/sc_lc_out && mkdir -p /tmp/sc_lc_out
$ timeout 120 /tmp/zig1_5/zig1_5_clean --dump-c89 --output-dir /tmp/sc_lc_out main.zig
Segmentation fault
dump rc=139        (0 .c files emitted; "timeout: the monitored command dumped core")
```

### ASan top frame (rebuild's /tmp/zig1_5/zig1_5_asan, same source)

```
==84333==ERROR: AddressSanitizer: SEGV on unknown address 0x00000009 (pc 0x57dfe4e2 ...)
==84333==The signal is caused by a READ memory access.
==84333==Hint: address points to the zero page.
    #0 0x57dfe4e2 in zF_941073CF_lowerExprImpl (/tmp/zig1_5/zig1_5_asan+0x1404e2)
    #1 0x57dd52b3 in zF_6AC3874D_lowerExpr (/tmp/zig1_5/zig1_5_asan+0x1172b3)
    #2 0x57ddcdcb in zF_B3048E04_lowerLValueAddr (/tmp/zig1_5/zig1_5_asan+0x11edcb)
    #3 0x57dfafd9 in zF_941073CF_lowerExprImpl (...)
    #4 0x57dd52b3 in zF_6AC3874D_lowerExpr (...)
    ...
    #12 0x57e805ae in zF_1F21ABE7_phase_LIRLowering (/tmp/zig1_5/zig1_5_asan+0x1c25ae)
    #13 0x57e77c06 in zF_74055C03_runCompiler (...)
```

Top frame `zF_941073CF_lowerExprImpl` reached via `phase_LIRLowering`, matching the plan's
crash site `sf/src/lower.zig:2261-2269` (ident_expr path): `types_items[garbage]` where
`garbage` is a stale id returned by `resolvedTypeTableGet(node_idx)`. READ on the zero page.

## Root-cause status

**ADJUDICATED pre-existing masked self-emission fidelity gap.** NOT a regression from the
enum-switch fix (`5ec13efb`) or the labeled-block break fix (A2, `ee092e3b`): the crash site
is outside those diffs and reproduces on a zero-switch program that exercises neither change.
Pre-fix `zig1_5` never reached lowering (parser died earlier at `+`), masking the latent
emission defect. **Root cause NOT yet traced — that is Task B2 (read-only trace).**

## Expected post-fix result

After the B2-traced self-emission fix: self-compiled dump rc=0, emitted C compiles/links with
the same recipe, and the run prints `3` — byte-equivalent to the reference path.
