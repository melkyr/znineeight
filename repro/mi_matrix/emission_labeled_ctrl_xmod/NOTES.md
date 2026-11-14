# emission_labeled_ctrl_xmod — GREEN runtime-correctness fixtures for labeled-statement control flow (A/B/C + literal-A)

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
rung of the post-fix R-ladder). Four shapes in one build, each printing an
expected value through `std.io.printInt`:
- **A** — labeled block `blk: { … }` containing a labeled loop whose `break :loop`
  escapes the loop; the value AFTER the block is printed (control resumes after
  the labeled block correctly).
- **literal-A** — the LITERAL `blk: { a = 1; break :blk; a = 2; }` shape:
  `break :blk` must exit the block directly (skip `a = 2`), printing `1`. This is
  the shape that was silently dropped pre-fix (see AMENDMENT-1 note below).
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

fn shapeALit() u32 {
    var a: u32 = 0;
    blk: {
        a = 1;
        break :blk;
        a = 2;
    }
    return a;
}

pub fn main() void {
    std.io.printInt(@intCast(i32, shapeA()));
    std.io.print("\n");
    std.io.printInt(@intCast(i32, shapeB()));
    std.io.print("\n");
    std.io.printInt(@intCast(i32, shapeC()));
    std.io.print("\n");
    std.io.printInt(@intCast(i32, shapeALit()));
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
1
run rc=0
```

Expected per shape: A → `3` (labeled loop breaks at a==3; control resumes after
the labeled block), literal-A → `1` (break :blk exits the block, `a = 2`
skipped), B → `6` (continue at i==3 skips one `count` increment,
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
  continues AFTER the block (the printed value is read post-block).
- **literal-A** → the literal Zig shape `blk: { a = 1; break :blk; a = 2; }`
  (direct block escape via `break :blk`). This is the F-LABELBREAK (A1a) fix
  target: `break :blk` resolves to the labeled-block exit BB pushed by the
  labeled_stmt block-body entry (`LoopInfo{ .is_loop = 0 }`), jumps there, and
  `a = 2` is skipped → prints `1`. See AMENDMENT-1 note below.
- **B** → labeled while with BOTH `break :loop` and `continue :loop`
  (`loop: while (cond) : (inc) { … }` — label registered in the loop-stack at
  lower.zig:4602-4604; break → exit_bb, continue → header_bb at
  lower.zig:5018-5069). Prints the loop iteration count.
- **C** → labeled statements nested inside a switch-on-enum PRONG BODY
  (`Kind.plus => continue :loop,` / `Kind.star => break :loop,` — the
  parser_tests.zig:651 shape `switch (x) { 1 => break :loop, else => {} }`,
  applied to a qualified enum switch inside a labeled while). Also covers the
  qualified-literal case-label path (Task 2 fix) combined with label targets.

## F-LABELBREAK fix (Task A2, AMENDMENT 1) — literal-A now GREEN

Pre-fix, `break :blk` on a plain labeled block was **silently dropped**: the
labeled-break lowering (`lower.zig:5018-5037`) resolved labels ONLY against
`loop_stack`, and a labeled_stmt wrapping a plain block pushed NO entry, so
`break :blk` silently returned at `:5019`/`:5037` and the break was DROPPED
(measured RED: printed `2`, expected `1`).

Post-fix (A1a, applied in Task A2 F-LABELBREAK, commit `ee092e3b`): `labeled_stmt`
lowering (`lower.zig:4442-4461`) now pushes a breakable loop-stack entry when
`child_0.kind == AstKind.block` (`LoopInfo{ header_bb = exit_bb, exit_bb =
block-exit BB, scope_depth = self.scope_depth, label_id = current_label,
is_loop = 0 }`), lowers the block body between push/pop, and emits a fall-through
`jump exit_bb` if the body is not self-terminating. `break :blk` resolves the
block entry via the existing label scan (jump to its `exit_bb`); `continue`
skips `is_loop == 0` entries (continue-on-block stays invalid / silent-fallthrough
as before). `LoopInfo` gained `is_loop: u8` (1 = real while/for loop, 0 =
labeled-block entry). Measured: the literal shape now prints **`1`**, rc=0.

**AMENDMENT 1 dead-code note:** because the block-body push is unconditional on
`child_0.kind == AstKind.block` (operator ruling `ebb01f59`, "no guard
refinement"), expression-position labeled blocks in the GREEN corpus whose body
self-terminates (e.g. `orelse blk: { return null; }` in
`emission_orelse_labeled_xmod` / `emission_catch_labeled_xmod`) now leave an
extra DEAD `z_bb_N` block behind: the block-exit BB is created and set as
`current_bb` even though the body's `return` fires first, so each affected
function emits an orphan, never-referenced `z_bb_N:` label with no body. Runtime
is correct; the extra block is dead code — ACCEPTED per AMENDMENT 1. Those two
fixtures' emitted BYTES change (re-baseline-default, NOT a gate violation); A2
verifies they still RUN correctly (prints `0` / `7`).

## No GREEN impact

Fixture is new-only. gol MD5 spot-check from repo root unchanged
(`timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/game_of_life/main.zig | md5sum`):
`4afb203fdde7a880ec6e7aed32543691`.
