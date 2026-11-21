# M1 Task 4 report — M1 closeout: docs + seed rotation

Status: DONE
Commit (a): `21443e21` docs(std_lib): rand + map internals (M1)
Commit (b): `cde50be2` chore(seed): rotate v103 with lib manifest (M1)
Commit (c): `f5b675d3` docs(sf): QUICK_REF current seed v103
Commit (d): this commit — docs(sdd): M1 T4 report

## What changed

- Created `sf/docs/std_lib/rand.md` per `_template.md`:
  - `Pcg32` (16 B) / `Xoshiro256` (32 B) state types and all seven public
    functions (`pcg32Init`, `pcg32Next`, `pcg32Bounded`, `pcg32Advance`,
    `xoshiroInit`, `xoshiroNext`, `xoshiroBounded`).
  - Explicit-seed contract (R6: std never reads clock/env/address),
    `Z98_SEED` as a user-program convention only, rejection sampling (never
    modulo), `bound == 0` `@panic`, determinism, SplitMix64 expansion, and the
    `O(log delta)` advance equivalence.
- Updated the `std_map` module-overview paragraph in
  `sf/docs/std_lib/collections.md`: Robin Hood insertion, backward-shift
  deletion (no observable tombstones), ctrl state `0x80` empty / `0x00..0x7F`
  fragment / `0xFE` reserved, stored `dist: u32`, pow2 slots + mask, load
  factor ≤ 0.75, `capacity` = max entries, entry sizes 16/16/20 B, and the
  Swiss-table deferral rationale (SIMD probe needs asm; PII/PIII lacks SSE2).
  Public API section left unchanged.
- `scripts/seed/archive_seed.sh`:
  - Generates `lib/manifest.md5` after the lib copy loop with
    `( cd "$SEED/lib" && LC_ALL=C md5sum *.zig > manifest.md5 )` and captures
    `MANIFEST_MD5`.
  - `SEED_README.txt` Contents gains the `zig1-seed/lib/manifest.md5` line
    (33 std files, per-file md5).
  - Fixed the stale `std install: ... lib/ with the 29 std .zig` line to 33.
  - CHANGELOG entry gains
    `| lib manifest | \`lib/manifest.md5\` (33 std files; md5 \`$MANIFEST_MD5\`) |`.
- Rotated `release/seed/zig1-seed.tgz` v102 → v103 and prepended the
  `release/seed/CHANGELOG.md` entry via `--update-changelog`.
- Truth-up in `docs/sf/QUICK_REF.md`: current seed v103 + new archive md5;
  v103 rotation-history line; `verify_stdlib` 292/0 on v103; 8-pin table
  heading v103 (values unchanged vs v102) + v103 archive md5.

## Per-step evidence

### Clean working compiler from the current tree

```
$ FIXED_POINT_MD5=b299b4b435e624d0ddbd2edde681cbc3 \
    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m1_t4_seed
[seed] hop2 binary md5: b299b4b435e624d0ddbd2edde681cbc3
[seed] two-hop closure OK: hop1 == hop2 == b299b4b435e624d0ddbd2edde681cbc3
[seed] recorded fixed point OK: b299b4b435e624d0ddbd2edde681cbc3
=== [seed] Done: /tmp/m1_t4_seed ===
```

### Rotation

HEAD captured by the script before commit (b): `21443e21` (commit (a)).

```
$ bash scripts/seed/archive_seed.sh /tmp/m1_t4_seed/zig1_5_clean \
    /tmp/m1_t4_seed/gen release/seed/zig1-seed.tgz --update-changelog
[archive] gcc-only rebuild of archive C md5 (fixed point): b299b4b435e624d0ddbd2edde681cbc3
[archive] wrote release/seed/zig1-seed.tgz (archive md5 c4d1e7a6f3d7403dee2c683a3a5ab438)
## 2026-10-19 — seed v103 (HEAD 21443e21)
| fixed point | `b299b4b435e624d0ddbd2edde681cbc3` |
| lib manifest | `lib/manifest.md5` (33 std files; md5 `74771fa978e6644b194690783bff21cc`) |
| archive md5 | `c4d1e7a6f3d7403dee2c683a3a5ab438` |
[archive] prepended entry to release/seed/CHANGELOG.md
```

### Rotation verification

```
$ tar -tzf release/seed/zig1-seed.tgz | grep 'lib/manifest.md5'
zig1-seed/lib/manifest.md5
$ tar -xOf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 | wc -l
33
$ tar -xOf release/seed/zig1-seed.tgz zig1-seed/zig1 | md5sum
b299b4b435e624d0ddbd2edde681cbc3  -
$ tar -xOf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 | md5sum
74771fa978e6644b194690783bff21cc  -
```

The archived `SEED_README.txt` contains the manifest line and the corrected
`std install` text (33 std `.zig`).

### Rebuild from the rotated archive

```
$ FIXED_POINT_MD5=b299b4b435e624d0ddbd2edde681cbc3 \
    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m1_t4_check
[seed] hop1 binary md5: b299b4b435e624d0ddbd2edde681cbc3
[seed] hop2 binary md5: b299b4b435e624d0ddbd2edde681cbc3
[seed] two-hop closure OK: hop1 == hop2 == b299b4b435e624d0ddbd2edde681cbc3
[seed] recorded fixed point OK: b299b4b435e624d0ddbd2edde681cbc3
=== [seed] Done: /tmp/m1_t4_check ===
```

### Full std gate

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m1_t4_seed/zig1_5_clean
run_fixtures: 292 PASS / 0 FAIL over 292 dirs
run_crosscheck: 2 PASS / 0 FAIL over 2 modules
STDLIB GATE OK
```

### Script syntax

```
$ bash -n scripts/seed/archive_seed.sh
(no output; rc 0)
```

## Deviations

None.

## Concerns

None blocking. The Task 4 context/prose says “the six functions”, but the
binding spec §6.1 and `sf/src/std_rand.zig` expose seven (4 PCG32 + 3
xoshiro256**); the doc documents all seven from source. A later
`docs/sf/QUICK_REF.md` std-module inventory paragraph still describes the
pre-M1 31 `std_*.zig` set; it was outside the four binding QUICK_REF edits in
the Task 4 context and was left unchanged.
