# D2 — enum `switch` range prongs are dropped at emission (RED, silent wrong code)

## Claim
`switch` on an enum with inclusive (`a...b`) and exclusive (`a..b`) range
prongs emits no `case` labels for those prongs (only `default`), so every value
takes the `else` branch. Silent wrong code: rc 0, wrong stdout.

## Chapter impact
Chapter 6 (enums, sample `color.z98`) and chapter 10 (control flow, sample
`control.z98`) — the spec-promised enum ranges cannot be taught until fixed.

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/D02_enum_switch_ranges
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D02_enum_switch_ranges \
    repro/vol2_defects/D02_enum_switch_ranges/main.zig
cd /tmp/vol2_defects_out/D02_enum_switch_ranges && timeout 120 sh build_target.sh linux main
timeout 120 ./main
```

## OBSERVED
- `main.zig`: compile rc 0, build rc 0, run rc 0. stdout:
  ```
  incl 20 20 20
  excl 40 40 40
  mixed 70 70 50
  ```
  Every range value fell to `else`; only the exact `Color.Blue => 50` prong in
  `mixed` matched.
- Emitted C (`main_F1092652.c`, `incl`), **no case labels**:
  ```c
  switch (c) {
  default: goto z_bb_2;
  }
  ```
  Same for `excl`. For `mixed`:
  ```c
  switch (c) {
  case 2: goto z_bb_1;
  default: goto z_bb_3;
  }
  ```
- `xmod_main.zig` (enum type from `colors.zig`): `incl 20 20 20`, `excl 40 40 40` — same.
- `red_exclusive_only.zig`: `excl 40 40 40`. `red_mixed_prongs.zig`: `mixed 70 70 50`.
- `control_int_ranges.zig`: `incl 10 10 20`, `excl 30 30 40`; its emitted C has
  real labels (`case 1: ... case 5: goto z_bb_1;`).

## EXPECTED
Language Spec §3.1: switch "Ranges ... Inclusive `start...end` ... Exclusive
`start..end` ... Bounds: compile-time constants of the same type as the switch
condition. Enums: Ranges on enum conditions use the underlying integer values
of the enum members. Expansion: Ranges are lowered into sequential C `case`
labels" and §1.3 gives `enum { Red, Green, Blue }` with
`Color.Red...Color.Green => handleWarm()`. Expected output (see
`expected.txt`): `incl 10 10 20`, `excl 30 30 40`, `mixed 60 60 50`.
Zig 0.15.2 oracle (comparison only): enum ranges are rejected by Zig
(`error: ranges not allowed when switching on type 'Color'`) and exclusive
`a..b` switch prongs are a Z98-specific extension (`error: expected '=>',
found '..'`); inclusive integer ranges work in Zig (`incl 10 10 20`). The
expected values therefore rest on the Z98 spec, not on Zig.

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| In-module inclusive + exclusive + mixed | `main.zig` | RED | all-`else`, `incl 20 20 20` |
| Cross-module enum | `xmod_main.zig` + `colors.zig` | RED | all-`else` |
| Exclusive only | `red_exclusive_only.zig` | RED | `excl 40 40 40` |
| Exact + range mix | `red_mixed_prongs.zig` | RED | `mixed 70 70 50` |
| Integer ranges | `control_int_ranges.zig` | control | `incl 10 10 20`, `excl 30 30 40` |

## Boundary
The drop is at emission for enum-typed range prongs; integer range prongs emit
labels correctly. Exact enum prongs emit labels. Whether `enum(uN)` with
non-default backing behaves identically is left to the D2 investigation.
