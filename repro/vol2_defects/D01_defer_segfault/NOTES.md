# D1 — `defer` segfault: plain-defer fn + loop-body-defer fn in one module (RED)

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
