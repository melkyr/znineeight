# emission_enum_switch_xmod — RED fixture for the enum-value stmt-switch case-label drop (R1)

Task 3 R-ENUMSWITCH (2026-08-25), AMENDMENT 7 of the Self-Hosted zig1_5
Investigation Plan (`docs/superpowers/plans/2026-08-25-self-hosted-zig15-investigation-plan.md`,
lines 275-385). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`
(the WORKING reference built by zig0 — it parses `+` correctly, but its OWN emission
shows the drop). Build recipe: emit with `--dump-c89 --output-dir`, compile emitted C
with `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`,
link `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c`, run.

## Purpose

Minimal single-module reproducer of the self-compile residual class **enum-value
stmt-switch case-label drop**: zig1 emits `switch (k) { default: goto z_bb_4; }`
(0 `case` labels) for a switch over an enum-typed discriminant whose case values are
qualified enum literals (`Kind.plus =>`). Every prong block is emitted but
unreachable; the switch always takes `default` and the program prints the wrong value.

This is the FIRST rung (R1) of the R-ladder. It stopped the ladder — no later rung
was executed.

## Fixture (verbatim — R1 source, single module)

`main.zig`:
```zig
const std = @import("std.zig");
const Kind = enum(u16) { plus, minus, star };
fn pick(k: Kind) u32 {
    var r: u32 = 0;
    switch (k) {
        Kind.plus => r = 1,
        Kind.minus => r = 2,
        Kind.star => r = 3,
        else => {},
    }
    return r;
}
pub fn main() void {
    std.io.printInt(pick(Kind.minus));
}
```

## RED evidence (measured 2026-08-25, /tmp/fx_subfolder/zig1)

```
$ cd /workspace/znineeight
$ rm -rf /tmp/fx_check_out && mkdir -p /tmp/fx_check_out
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fx_check_out \
    repro/mi_matrix/emission_enum_switch_xmod/main.zig
dump rc=0           (no diagnostics — zig1 accepts the program)
$ cd /tmp/fx_check_out && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=0            (emits clean C — the mis-emission is silent, wrong runtime only)
$ gcc -m32 -std=c89 ... *.c <repo>/sf/src/include/zig_runtime.c <repo>/sf/src/include/zig_pal.c -o /tmp/fx_bin
$ /tmp/fx_bin
0                   (EXPECTED 2 — Kind.minus is the 2nd member; all prongs unreachable)
run rc=0
```

Exact 0-case emitted-C excerpt (`main_94E9328A.c:20-45` — the drop):
```c
switch (k) {
default: goto z_bb_4;
}
    z_bb_1:
    zT_4 = 1;
    zT_5 = (unsigned int)zT_4;
    r = zT_5;
    r = zT_5;
    goto z_bb_6;
    z_bb_2:
    zT_6 = 2;
    zT_7 = (unsigned int)zT_6;
    r = zT_7;
    r = zT_7;
    goto z_bb_6;
    z_bb_3:
    zT_8 = 3;
    zT_9 = (unsigned int)zT_8;
    r = zT_9;
    r = zT_9;
    goto z_bb_6;
    z_bb_4:
    goto z_bb_6;
```
`switch (k)` carries ZERO `case` labels — only `default: goto z_bb_4;`. The three prong
blocks `z_bb_1/z_bb_2/z_bb_3` are dead; control always falls to `z_bb_4` (default),
so `r` keeps its init `0`. Same 0-case shape byte-for-byte as the self-compile's
`parser_61A67AF1.c:1992` (see root-cause pin below). Module-hash suffix (`94E9328A`)
varies by dump CWD; content is invariant.

## Root-cause pin (from Task 2 I-LEXER-DIFF evidence)

The lexer is CLEAN. The real mis-emission is the enum-value stmt-switch case-label
drop, confirmed at `parserAddBinary` (self-compiled `parser_61A67AF1.c:1992`):

```
parser_61A67AF1.c:1992  switch (zT_9) { default: goto z_bb_46; }        // 0 case labels (45 prong blocks z_bb_1..45 unreachable)
ref_zig1.c:47969        switch (zT_9) { case 20: goto z_bb_8; ... }     // 45 case labels (working zig0 reference)
```

Same 0-case shape x3 at `symbol_registrator_757C4BC5.c:2165/2308/2689` (registerDecl)
and `ast_2FA12982.c:2193` (nodeHasExtraChildren). Exactly 5 zero-case switches in all
gen/ modules, none in the lexer. Runtime: `zig1_5_clean` on `1 + 2` ->
`error[2000] invalid token in expression` at `+` (parserAddBinary found==0).

Suspected locus: `sf/src/lower.zig:3946-3976` — the stmt-switch case collection only
collects int/char/enum/error-literal case nodes; `else { continue; }` at :3969-3971
drops the `field_access` case items (the node shape `parserParseExprPrec` yields for
qualified labels `Kind.plus`, cf. `enum_literal` only from `parserParseEnumLiteral`
parser.zig:765) -> `sf/src/c89_emit.zig:5668-5709` emits exactly `cases_count` labels,
0 here -> bare `switch (k) { default: goto z_bb_4; }`.

## Which rung stopped the ladder

**R1** (just the enum + qualified-literal switch, single module, local enum, local
discriminant). RED at R1: the drop is the qualified enum-literal label alone — no
struct-field discriminant, cross-module import, enum arity, or block-bodied prongs are
needed. Rungs R2-R5 were NOT executed (ladder rule: STOP at first RED).

## Expected post-fix result

After the fix, `switch (k)` carries `case zT_3FF50C63_Kind_plus:` /
`case zT_3FF50C63_Kind_minus:` / `case zT_3FF50C63_Kind_star:` labels and the run
prints `2`.
