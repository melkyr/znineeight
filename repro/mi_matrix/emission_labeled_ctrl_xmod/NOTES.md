# emission_labeled_ctrl_xmod — GREEN runtime-correctness fixtures for labeled-statement control flow (A/B/C)

Task 5 R-LABELED (2026-08-25), AMENDMENT 7 of the Self-Hosted zig1_5
Investigation Plan (`docs/superpowers/plans/2026-08-25-self-hosted-zig15-investigation-plan.md`).
Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1` (the WORKING
reference built by zig0 — the self-compiled `zig1_5` crash residual at
`lower.zig:2261-2269` does NOT affect fixture runs). Consumes the existing
labeled_stmt lowering (`lower.zig:4408-4414` stmt, `:4315-4318` expr) and the
labeled-break/continue loop-stack resolution (`lower.zig:5018-5069`).
Build recipe: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`,
link `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c`, run.

## Purpose

Runtime-correctness coverage for labeled-statement control flow (the R-LABELED
rung of the post-fix R-ladder). Three shapes in one build, each printing an
expected value through `std.io.printInt`:
- **A** — labeled block `blk: { … }` containing a labeled loop whose `break :loop`
  escapes the loop; the value AFTER the block is printed (control resumes after
  the labeled block correctly).
- **B** — labeled while with BOTH `break :loop` AND `continue :loop`, printing
  the loop iteration count.
- **C** — labeled statements (`break :loop` / `continue :loop`) nested inside the
  PRONG BODIES of a switch-on-enum, inside a labeled while, printing.

## Fixture (verbatim — single module)

`main.zig`:
```zig
const std = @import("std.zig");
const Kind = enum(u16) { plus, minus, star };

fn shapeA() u32 {
    var a: u32 = 0;
    blk: {
        loop: while (true) {
            a = a + 1;
            if (a == 3) break :loop;
        }
    }
    return a;
}

fn shapeB() u32 {
    var i: u32 = 0;
    var count: u32 = 0;
    loop: while (i < 10) : (i += 1) {
        if (i == 3) { continue :loop; }
        if (i == 7) { break :loop; }
        count = count + 1;
    }
    return count;
}

fn shapeC() u32 {
    var total: u32 = 0;
    var idx: u32 = 0;
    loop: while (idx < 3) : (idx += 1) {
        var k: Kind = Kind.plus;
        if (idx == 1) { k = Kind.minus; }
        if (idx == 2) { k = Kind.star; }
        switch (k) {
            Kind.plus => continue :loop,
            Kind.minus => total = total + 10,
            Kind.star => break :loop,
            else => {},
        }
    }
    return total;
}

pub fn main() void {
    std.io.printInt(@intCast(i32, shapeA()));
    std.io.print("\n");
    std.io.printInt(@intCast(i32, shapeB()));
    std.io.print("\n");
    std.io.printInt(@intCast(i32, shapeC()));
    std.io.print("\n");
}
```

## GREEN evidence (measured 2026-08-25, /tmp/fx_subfolder/zig1)

```
$ cd /workspace/znineeight/repro/mi_matrix/emission_labeled_ctrl_xmod
$ rm -rf /tmp/fx_abc2 && mkdir -p /tmp/fx_abc2
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fx_abc2 main.zig
dump rc=0
$ cd /tmp/fx_abc2 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc rc=0
$ gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include *.c \
    /workspace/znineeight/sf/src/include/zig_runtime.c \
    /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/fx_abc2/bin
link rc=0
$ /tmp/fx_abc2/bin
3
6
10
run rc=0
```

Expected per shape: A → `3` (labeled loop breaks at a==3; control resumes after
the labeled block), B → `6` (continue at i==3 skips one `count` increment,
break at i==7 exits; count++ fires at i∈{0,1,2,4,5,6} = 6), C → `10`
(idx 0 → plus prong `continue :loop`; idx 1 → minus prong `total += 10`;
idx 2 → star prong `break :loop`). Output matches exactly.

Emitted-C control-flow evidence (`main_*.c`, shapeB region): `continue :loop`
at `i == 3` lowers to `z_bb_5: goto z_bb_4;` where `z_bb_4` is the loop
continue-expr block (`i = i + 1; goto z_bb_1;`) — correct continue semantics;
`break :loop` at `i == 7` lowers to `z_bb_7: goto z_bb_3;` (loop exit →
`return count;`). The shapeC switch-on-enum carries real case labels:
`switch (k) { case 0: ... case 1: ... case 2: ... default: ... }`
(posts the Task 2 `5ec13efb` field_access case-label fix).

## Which shape each covers

- **A** → labeled BLOCK (`blk: { … }`, parser `parserParseLabeledStmt` —
  parser.zig:1329-1337) as a transparent prefix over a labeled loop; verifies
  the block lowers, the inner `break :loop` escapes the loop, and control
  continues AFTER the block (the printed value is read post-block). The literal
  Zig shape `blk: { break :blk; }` (direct block escape) is NOT supported by the
  dialect — see dialect-adaptation note below.
- **B** → labeled while with BOTH `break :loop` and `continue :loop`
  (`loop: while (cond) : (inc) { … }` — label registered in the loop-stack at
  lower.zig:4602-4604; break → exit_bb, continue → header_bb at
  lower.zig:5018-5069). Prints the loop iteration count.
- **C** → labeled statements nested inside a switch-on-enum PRONG BODY
  (`Kind.plus => continue :loop,` / `Kind.star => break :loop,` — the
  parser_tests.zig:651 shape `switch (x) { 1 => break :loop, else => {} }`,
  applied to a qualified enum switch inside a labeled while). Also covers the
  qualified-literal case-label path (Task 2 fix) combined with label targets.

## Dialect-adaptation notes (shape A)

The brief's literal A shape — `blk: { … break :blk … }`, control escaping the
BLOCK directly — is **genuinely unsupported by the dialect**: the labeled-break
lowering (`lower.zig:5018-5037`) resolves labels ONLY against `loop_stack`
(entries pushed for `while_stmt`/`for_stmt` at lower.zig:4602-4604/4702-4703/
4756-4757); a labeled_stmt wrapping a plain block pushes NO entry, so
`break :blk` silently returns at `lower.zig:5019` (`loop_stack.len == 0`) or
`:5037` (`exit_target == 0`) and the break is DROPPED.

Measured RED on the literal form (2026-08-25, /tmp/fx_subfolder/zig1):
```zig
var a: u32 = 0;
blk: {
    a = 1;
    break :blk;
    a = 2;
}
std.io.printInt(@intCast(i32, a));
```
dump rc=0, gcc rc=0, link rc=0, run prints **`2`** (expected `1` — the break is
silently dropped, `a = 2` executes). Per the brief's adaptation rule this shape
was NOT forced: shape A uses the closest SUPPORTED form (labeled block as a
transparent prefix over a labeled loop, with the value printed after the block),
and the block-direct-`break :blk` silent-drop is recorded as an out-of-scope
fidelity-gap residual (lower.zig:5018-5069 loop-stack-only label resolution).

## No GREEN impact

Fixture is new-only. gol MD5 spot-check from repo root unchanged
(`timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/game_of_life/main.zig | md5sum`):
`4afb203fdde7a880ec6e7aed32543691`.
