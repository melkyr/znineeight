# D1 — `defer` segfault: plain-defer fn + loop-body-defer fn in one module (RED; fixed by FG; traversal extras by FX2)

> **FG status (2026-09-26): FIXED.** `resetDeferQueue` clears
> `defer_queue_items/len/cap` immediately after each of the four
> `sandReset(ctx.alloc)` sites in `runAllAnalyzers` (`sf/src/analyzer.zig`), so
> the queue can never alias recycled scratch memory that now holds a live
> `StateMap`. Fixed point MOVED `6b68ca72bd8919edef0ef7f955a75580` ->
> `c4f10f9e2d33a0833b9882c5dad2539b` (two-hop closure hop1 == hop2, explicit
> `FIXED_POINT_MD5` gate; seed v88 NOT rotated). All four RED entry files now
> compile rc 0 / build rc 0 / run rc 0 and print their EXPECTED output
> (recorded below); the split controls and `control_*` stay byte-identical;
> `run_all.sh` prints `D01_defer_segfault: rc=0 ok` and now additionally
> goldens `main.zig` stdout/rc against `expected.txt`. `--no-leak-check` is no
> longer needed anywhere. The seed-v88 OBSERVED section below remains the
> historical RED evidence.

> **FX2 status (2026-09-27): TRAVERSAL EXTRA FIXED.** `visitStatement`
> (`sf/src/analyzer.zig`) now walks switch-prong and bare-block statements: the
> `swt_ex` arm analyzes the condition then forks/walks/merges each prong body,
> the `expr_stmt` arm recurses the statement-switch wrapper, and a bare `block`
> routes through `walkBlock` — so defers inside them queue at the walked
> `current_depth` and drain at their own block exit. The new sibling
> `red_switch_block.zig` (plain + switch-prong + bare-block defers) compiles/
> builds/runs rc 0 (stdout `plain-body`, `plain-defer`, `switch 2`,
> `switch-defer`, `block-body`, `block-defer`; stderr empty); all three FX2
> shapes SIGSEGV rc 139 on an FX2-only (no-FG) compiler and rc 0 on FG+FX2.
> Fixed point MOVED `98cd68f4a4f99b520f663d6964673e67` ->
> `325f741f0326ebaf177a0503e000312a` (hop1 == hop2); runtime behavior is
> unchanged (analyzer-only). Positive fixture
> `repro/mi_matrix/stdlib_defer_switch_block_xmod`; standalone
> `repro/defer_traversal.z98`.

## FG GREEN evidence

Compiler `/tmp/fg/build1/zig1_5_clean` (md5 `c4f10f9e2d33a0833b9882c5dad2539b`);
each entry `-o <dir> <file>` -> `sh build_target.sh linux <base>` -> `./<base>`,
all under `timeout 120`.

- `main.zig` compile/build/run rc 0 / 0 / 0, stdout:
  `plain-body`, `plain-defer`, `loop 1`, `loop-defer`, `loop 2`, `loop-defer`.
- `xmod_main.zig` rc 0 / 0 / 0, stdout:
  `helper-plain-body`, `helper-plain-defer`, `helper-loop 1`,
  `helper-loop-defer`, `helper-loop 2`, `helper-loop-defer`.
- `red_while.zig` rc 0 / 0 / 0, stdout:
  `plain-body`, `plain-defer`, `while 0`, `while-defer`, `while 1`,
  `while-defer`.
- `red_nested_for.zig` rc 0 / 0 / 0, stdout:
  `plain-body`, `plain-defer`, `nested 1 1`, `nested-defer`, `nested 1 2`,
  `nested-defer`, `nested 2 1`, `nested-defer`, `nested 2 2`, `nested-defer`.
- controls `control_two_plain` / `control_for_only` / `control_nodefer_for` /
  `split_plain_main_loop_helper` / `split_loop_main_plain_helper`: POST stdout
  byte-identical to the pre-FG HEAD compiler (`cmp`), stderr identical (empty).
- leak-analyzer diagnostics on the controls and the four 4-MD5 gate programs:
  byte-identical PRE (HEAD `6b68ca72…`) <-> POST; zero `WARN_7002`;
  self-emission rc 0 / 48 `.c` + 48 `.h` / zero `WARN_7002`.
- Regression fixture `repro/mi_matrix/stdlib_defer_queue_reset_xmod` is RED
  (rc 139) on the pre-FG compiler and GREEN (rc 0, golden 317 B, 3x
  byte-exact) on the FG compiler.

## Claim
A module containing one function with a plain `defer` and another function with
a `defer` inside a `for` body makes the compiler SIGSEGV (rc 139). The same
combination inside a `while` body or a nested `for` body also crashes.

## Chapter impact
Chapter 11 (`defer` and `errdefer`, sample `defer.z98`) — the crash blocks the
chapter until an operator-authorized compiler fix.

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`
(rebuilt with `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed`).

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/D01_defer_segfault
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D01_defer_segfault \
    repro/vol2_defects/D01_defer_segfault/main.zig
# rc=139
```

## OBSERVED
- `main.zig` (in-module): compile rc **139**, stderr `timeout: the monitored
  command dumped core` / `Segmentation fault`. No C is emitted; there is no
  gcc-stage artifact to quote.
- `xmod_main.zig` (plain-defer fn + loop-defer fn BOTH in `helper.zig`): rc
  **139**.
- `red_while.zig`: rc **139**. `red_nested_for.zig`: rc **139**.
- `split_plain_main_loop_helper.zig` (plain in main.zig, loop-defer in
  `helper_loop.zig`): compile rc 0, build rc 0, run rc 0, stdout
  `xmod-plain-body`, `xmod-plain-defer`, `helper-loop 1`, `helper-defer`,
  `helper-loop 2`, `helper-defer` — **no crash**.
- `split_loop_main_plain_helper.zig` (inverse split): rc 0 all stages — **no
  crash**.
- Controls all compile+build+run rc 0:
  `control_two_plain.zig` -> `b1 d1 b2 d2`;
  `control_for_only.zig` -> `loop 1 loop-defer loop 2 loop-defer`;
  `control_nodefer_for.zig` -> `plain-loop 1 plain-loop 2 loop 1 loop-defer loop 2 loop-defer`.

## EXPECTED
The compiler should accept and run both shapes; each is independently
supported (controls above) and Language Spec §3.1 says `defer` statements
execute on all paths out of their scope. This is not a Zig-0.15.2 oracle case
(a compiler crash has no Zig counterpart; the oracle never defines expected
behavior here).

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| In-module plain + `for`-defer | `main.zig` | RED | compile rc 139 |
| Cross-module, both in `helper.zig` | `xmod_main.zig` + `helper.zig` | RED | compile rc 139 |
| In-module plain + `while`-defer | `red_while.zig` | RED | compile rc 139 |
| In-module plain + nested-`for`-defer | `red_nested_for.zig` | RED | compile rc 139 |
| In-module plain + switch-prong/bare-block defers | `red_switch_block.zig` | GREEN after FG+FX2 | compile/build/run rc 0; FX2-only (no FG) rc 139 |
| Split: plain in main, loop in helper | `split_plain_main_loop_helper.zig` + `helper_loop.zig` | control | rc 0, runs |
| Split: loop in main, plain in helper | `split_loop_main_plain_helper.zig` + `helper_plain.zig` | control | rc 0, runs |
| Two plain-defer fns | `control_two_plain.zig` | control | rc 0, runs |
| `for`-defer alone | `control_for_only.zig` | control | rc 0, runs |
| no-defer fn + `for`-defer fn | `control_nodefer_for.zig` | control | rc 0, runs |

## Boundary
The trigger is per-module: BOTH shapes must live in the same module. A module
boundary between them (either direction) avoids the crash. Task 0's `g3` and
reviewer `a2` (plain + `for`-defer) crash; reviewer `a1` (two plain) and `a3`
(`for`-defer only) pass. The investigation (D1) should settle whether the
trigger is "any two defer-bearing functions where one is loop-nested" or a
narrower AST/emitter interaction.
