# D3 — missing mandatory `else`: unmatched value reads an uninitialized temp (RED, silent wrong value)

## Claim
A `switch` expression without `else` is accepted; when no prong matches, the
result temp is never assigned and the program reads uninitialized storage
(garbage that varies run to run). Language Spec §3.1 says the `else` prong is
mandatory in all switch expressions.

## Chapter impact
Chapter 10 (control flow, sample `control.z98`) — silent wrong value in the
flagship switch sample.

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/D03_missing_else
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D03_missing_else \
    repro/vol2_defects/D03_missing_else/main.zig
cd /tmp/vol2_defects_out/D03_missing_else && timeout 120 sh build_target.sh linux main
timeout 120 ./main
```

## OBSERVED
- `main.zig`: compile rc 0, build rc 0, run rc 0:
  ```
  matched_no_else=100
  unmatched_no_else=1536851956
  matched_else=100
  unmatched_else=-1
  if_no_else_statement=ok
  ```
  The unmatched no-`else` value is stack garbage (repeated runs are not
  guaranteed stable; Task 0 saw `1`, reviewer `c_missing_else` saw
  `1699094516`, this run `1536851956`).
- `red_unmatched_only.zig`: `unmatched_no_else=1705099252`.
- `xmod_main.zig` (switch in `picker.zig`): `matched=100`,
  `unmatched=1633099764`, `unmatched_else=-1`.
- Emitted C for the no-`else` function (`main_B013C04A.c`) — `zT_1` is declared
  and never assigned on the default path:
  ```c
  int zF_06373A06_pickNoElse(int x) {
      int zT_1;
      int zT_2;
      int zT_3;
  switch (x) {
  case 1: goto z_bb_1;
  case 2: goto z_bb_2;
  default: goto z_bb_3;
  }
      z_bb_1: zT_2 = 100; zT_1 = zT_2; goto z_bb_4;
      z_bb_2: zT_3 = 200; zT_1 = zT_3; goto z_bb_4;
      z_bb_3:
      z_bb_4:
      return (int)((int)zT_1);
  }
  ```
- `control_else_and_if.zig`: `matched_else=100`, `unmatched_else=-1`,
  `if_no_else_statement=ok` (an `if` statement without `else` is legal).

## EXPECTED
Language Spec §3.1: "`else`: An `else` prong is **mandatory** in all switch
expressions." The compile should reject `pickNoElse`. Zig 0.15.2 oracle
(comparison only): `error: switch must handle all possibilities` on the
same shape. There is no valid runtime output to compare, because the program
should not build.

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| In-module matched + unmatched + else control | `main.zig` | RED | `unmatched_no_else=1536851956` |
| Cross-module no-`else` switch | `xmod_main.zig` + `picker.zig` | RED | `unmatched=1633099764` |
| Unmatched value only | `red_unmatched_only.zig` | RED | `unmatched_no_else=1705099252` |
| `else` + `if`-without-`else` statement | `control_else_and_if.zig` | control | correct values |

## Boundary
The value-taken path is correct; only the unmatched path is wrong. The
value varies between processes, so `run_all.sh` cannot diff a golden file for
this case; the verdict is the fact that the program compiles and runs at all.
