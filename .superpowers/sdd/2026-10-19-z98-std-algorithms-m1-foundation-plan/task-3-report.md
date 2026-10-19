# M1 Task 3 report — `std_map` Robin Hood upgrade

Status: DONE
Commit (a): `0be9ae82` refactor(std_map): Robin Hood + backward-shift deletion (M1)
Commit (b): `8e0a47f6` docs(sdd): M1 T3 report

## What changed

- `sf/src/std_map.zig` internals rewritten; public API/field names unchanged
  (`entries`, `capacity`, `len`; `mask: usize` added).
  - Slots = smallest power of two with `slots * 3 >= capacity * 4`
    (`capacity/0.75` ceiling); capacity 0 -> 0 slots, capacity 1 -> 2 slots.
    Home index = `hash & mask`.
  - Entry gains `dist: u8`; ctrl `state` is `0x80` empty or the 7-bit hash
    fragment `hash & 0x7F`. `0xFE` remains reserved and is never written.
  - Insertion is Robin Hood (carry record, swap when carried `dist` is greater);
    existing-key replacement happens before insertion and never allocates.
  - Deletion is backward-shift: shift while next `dist > 0`, stop at empty or
    `dist == 0`; no tombstones.
  - Caller capacity still bounds entries: a new key when `len == capacity`
    returns `error.OutOfMemory` with the map untouched. String keys are copied
    only for a new key after the capacity check and before table mutation.
  - Header comment updated to Robin Hood / backward-shift / ctrl encoding /
    0.75 load factor / slot-ascending iteration.
- New fixture `repro/mi_matrix/stdlib_map_robinhood_xmod/`
  (`main.zig`, `expected.txt` = `map robinhood ok\n`, `expected.rc` = `0`):
  reverse insertion (1000), delete+reinsert (500), delete-half verification,
  overwrite len/value, fill to capacity then OOM, 10k-cycle churn over a
  bounded key space with periodic and final survivor verification.
- `scripts/stdlib/expected_dirs.txt`: new fixture added in sorted position
  (between `stdlib_map_oom_xmod` and `stdlib_map_stress_xmod`).
- `stdlib_map_determinism_xmod/main.zig`: comment-only truth-up
  (`slot-ascending`, backward-shift/no tombstones). No behavior change.

## Per-step evidence

### Step 1/2 — write invariants fixture, run before upgrade

Created the fixture and ran it against the pre-upgrade seed compiler:

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m1_t2_seed/zig1_5_clean \
    repro/mi_matrix/stdlib_map_robinhood_xmod
PASS repro/mi_matrix/stdlib_map_robinhood_xmod
run_fixtures: 1 PASS / 0 FAIL over 1 dirs
```

Observed: it passed on the tombstone implementation as well (the brief allows
“or pass but reveal unreachable keys”). No keys were unreachable in that run;
the fixture still pins the required invariants for the new implementation.

### Step 3/4 — rebuild against edited source, map fixtures

```
$ FIXED_POINT_MD5=b299b4b435e624d0ddbd2edde681cbc3 \
    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m1_t3_seed
[seed] hop2 binary md5: b299b4b435e624d0ddbd2edde681cbc3
[seed] two-hop closure OK: hop1 == hop2 == b299b4b435e624d0ddbd2edde681cbc3
[seed] recorded fixed point OK: b299b4b435e624d0ddbd2edde681cbc3
```

```
$ cmp sf/src/std_map.zig /tmp/m1_t3_seed/lib/std_map.zig
(no output; match)
```

Targeted map/usage run:

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m1_t3_seed/zig1_5_clean \
    stdlib_map_{map32x32,map32ptr,mapstrptr,oom,stress,determinism,robinhood}_xmod \
    stdlib_test/map_sort_heap_usage
PASS ... (all 8)
run_fixtures: 8 PASS / 0 FAIL over 8 dirs
```

Existing map goldens remained byte-identical: no `expected.txt`/`expected.rc`
files were modified; only the determinism fixture's comments changed.

### Step 5 — determinism 3x

```
$ <emit/build determinism fixture with /tmp/m1_t3_seed/zig1_5_clean>
$ /tmp/t3det/prog > r1; /tmp/t3det/prog > r2; /tmp/t3det/prog > r3
$ cmp r1 r2 && cmp r1 r3 && cmp r1 expected.txt
map determinism ok
```

The full gate harness also runs every fixture 3x and checks stdout equality.

### Full gate

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m1_t3_seed/zig1_5_clean
run_fixtures: 292 PASS / 0 FAIL over 292 dirs
run_crosscheck: 2 PASS / 0 FAIL over 2 modules
STDLIB GATE OK
GATE_RC=0
```

## Deviations

None. No unrelated files changed; `run.err` was left untouched and not staged.
No push performed.

## Concerns

None blocking. The new invariants fixture also passed on the old tombstone
implementation, so it is a forward-looking invariant pin rather than a
pre-upgrade failing test; all required legs pass under the new implementation
and all existing goldens are unchanged.

## Fix round 1

Operator ruling A: no stored distance. Base `8e0a47f6`; round-0 commit (b) SHA
is `8e0a47f6` (now recorded above as well).

### What changed

- `sf/src/std_map.zig`: dropped `dist: u8` from all three entry structs.
  Probe distance is now computed on demand per map as
  `(slot - home) & mask` (`dist32x32` / `dist32Ptr` / `distStrPtr`), using
  `mix32(key)` for integer maps and `hashBytes(key)` for the string map.
  Insertion carries `(key, val, state, dist)` and swaps against the occupant's
  on-demand distance; backward-shift stops on empty or on-demand distance 0.
  No stored-distance updates remain. Ctrl-state encoding, capacity semantics,
  string-copy timing, `mask` indexing, and slot sizing are unchanged.
- `docs/superpowers/specs/...design.md` §6.2: layout bullet no longer adds a
  distance field; probe-distance bullet now states on-demand computation and
  records the operator ruling (u8 wraps at 256 under same-home clustering).
  Ctrl encoding and load-factor bullets retained.
- `stdlib_map_robinhood_xmod`: added an adversarial same-home cluster
  (fixture-side `mix32`; 257 keys sharing one home slot in a capacity-300 map;
  insert all, check all, delete the head, check every survivor and the deleted
  key) and steady-state/post-deletion ctrl-byte assertions over `0..mask`
  (each slot `0x80` or `<= 0x7F`, fragment equals the record's own hash
  fragment, `0xFE` absent).
- `stdlib_map_determinism_xmod` header: corrected coverage-bound wording — the
  loop compares slots `0..capacity`, while the internal slot array is larger;
  it does not compare every internal slot.

### Evidence

Old u8 implementation, copied from `0be9ae82` into a scratch compiler lib,
against the updated fixture:

```
$ <emit/build updated fixture with /tmp/m1_t3_u8/zig1_5_clean>
panic: adversarial survivor
OLD_U8_RC=133
```

New implementation, rebuilt compiler:

```
$ FIXED_POINT_MD5=b299b4b435e624d0ddbd2edde681cbc3 \
    bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m1_t3_seed
[seed] two-hop closure OK: hop1 == hop2 == b299b4b435e624d0ddbd2edde681cbc3
[seed] recorded fixed point OK: b299b4b435e624d0ddbd2edde681cbc3
$ cmp sf/src/std_map.zig /tmp/m1_t3_seed/lib/std_map.zig
(no output; match)
```

Targeted map fixtures (new adversarial fixture passes):

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m1_t3_seed/zig1_5_clean \
    stdlib_map_{map32x32,map32ptr,mapstrptr,oom,stress,determinism,robinhood}_xmod \
    stdlib_test/map_sort_heap_usage
run_fixtures: 8 PASS / 0 FAIL over 8 dirs
```

Capacity 0/1/2/3 + full-capacity replace scratch check:

```
$ <emit/build/run /tmp/t3_caps/main.zig with /tmp/m1_t3_seed/zig1_5_clean>
map caps ok
CAPS_RC=0
```

Determinism 3x (explicit):

```
$ <emit/build determinism fixture>
$ /tmp/t3det/prog > r1; /tmp/t3det/prog > r2; /tmp/t3det/prog > r3
$ cmp r1 r2 && cmp r1 r3 && cmp r1 expected.txt
map determinism ok
```

Full gate:

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m1_t3_seed/zig1_5_clean
run_fixtures: 292 PASS / 0 FAIL over 292 dirs
run_crosscheck: 2 PASS / 0 FAIL over 2 modules
STDLIB GATE OK
GATE_RC=0
```

Existing map goldens remained byte-identical; `map_sort_heap_usage` unchanged.
No unrelated files touched; `run.err` untouched and unstaged. No push.

### Commits

- (a) `fix(std_map): on-demand probe distance (no u8 wrap)`
- (b) `docs(spec): std_map distance computed on demand`
- (c) `docs(sdd): M1 T3 fix round 1` (this append)
