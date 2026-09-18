# Z98 std-lib test hardening — Design

> **Status:** Approved 2026-09-18 (operator). Program-level spec for the
> per-band test-hardening plans. Each `plan_<X>_test_hardening.md` argues
> from this document.

**Goal:** Make the std lib's **runtime behavior** a real, automated gate —
not just a compile gate — and add a hand-written stress/adversarial tier,
so a regression in a std function's behavior is caught by the harness
rather than only by a human re-running a fixture.

## §1 The gap this closes

`scripts/corpus/classify` is **compile-only**: it runs `zig1 -ffast
--dump-c89`, counts `.c` files, and gcc-compiles them. It never builds,
links, or runs a fixture. Consequences:

- The ~35 Plan A fixtures' `ck(...)` assertions and their documented
  stdout contracts are verified **manually by the implementer** for that
  task; nothing re-runs them.
- A later change could silently break `std_str.split`'s view semantics,
  `std_buf`'s endian encoders, `std_time`'s monotonicity, or the OOM/trap
  semantics, and the corpus would stay green.
- Expected failures (the `extract`/`insert` out-of-range trap,
  `std_os.exit`'s exit code, the abort/probe paths) are only partially
  asserted.

Std libs are runtime-behavior libraries, so this is the highest-value
testing gap in the program.

## §2 The runtime gate

A new, opt-in harness — **`scripts/stdlib/run_fixtures.sh`** — separate
from the corpus classifier (which stays compile-only for speed across all
dirs).

**Discovery:** every `repro/mi_matrix/stdlib_*_xmod/` and every
`stdlib_test/*/` (resolved with the same `emit_dir` entry rule as
`scripts/corpus/list_corpus_dirs.sh`).

**Per fixture:**
1. `zig1 -ffast -o <tmp> <entry>` (the standard per-program emission).
2. Compile every emitted `.c` with the binding gcc flag-set
   (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
   -Wno-implicit-function-declaration -I <inc>`).
3. `sh <tmp>/build_target.sh linux <prog>`.
4. Run under `timeout 120`; capture stdout bytes + exit code.

**Comparison — per-fixture committed goldens:**
- `repro/mi_matrix/<dir>/expected.txt` — the exact stdout bytes.
- `repro/mi_matrix/<dir>/expected.rc` — the expected exit code.
Captured from the known-good compiler at the plan's baseline. The harness
diffs bytes and rc; any mismatch is a failure.

**Probe fixtures (expected failures):** a fixture that intentionally
aborts/traps ships an `expected.rc` of its signal code (e.g. `133`
SIGTRAP, `134` SIGABRT) and an empty `expected.txt`, so the expected
failure is itself asserted.

**Determinism (R6):** each fixture runs 3×; the stdout must be identical
across runs and equal to `expected.txt`.

**Contract note — exact-multiple long line (Task 5a-I).** The
`std_stdin.readLine` / `std_stream.readLineSync` contract specifies the
"longer than `buf`" overflow case but historically left the exact-multiple
boundary (`len % buf.len == 0`) unspecified. It is now specified: a line
whose length is an exact multiple of the buffer length must NOT yield a
trailing empty line (a 4-byte buffer over `"abcd\nz\n"` yields `["abcd",
"z"]`, not `["abcd", "", "z"]`). The two RED pins
(`stdlib_stdin_multiple_xmod`, `stdlib_stream_multiple_xmod`) assert this
desired behavior; Task 5a-F fixes `sf/src` to turn them GREEN.

**Wiring:** the harness is invoked by the closeout (either a new
`C*`-prefixed phase in `scripts/closeout/verify_upgraded.sh`, or a sibling
`scripts/stdlib/verify_stdlib.sh` called from it). A fixture with no
committed golden fails the gate (no silent skip).

## §3 The stress / adversarial tier

Hand-written large/adversarial input tables (no PRNG — inputs are explicit
and reproducible by construction). Per band, alongside the existing unit
fixtures, under `repro/mi_matrix/stdlib_<module>_stress_xmod/` (and/or the
`stdlib_test/` container where a workflow-level stress makes sense):

- **Round-trips:** `insert∘extract` identity over a table of field
  layouts; `join∘split` identity over adversarial separators/empties;
  encoder∘decoder byte round-trips.
- **Scale:** many appends across many doublings; long inputs; maximum
  sizes the arena allows.
- **Adversarial:** leading/trailing/consecutive separators, all-separator
  input, empty input, whitespace-only, high-bit bytes, embedded NUL/`\r\n`.
- **Expected-failure pins:** the currently-unasserted expected failures
  (`std_bits.extract`/`insert` out-of-range trap, `std_os.exit`'s rc,
  `std_str`/`std_buf` misuse) become probe fixtures with declared
  `expected.rc`.

## §4 Plan sequence

The program becomes:

```
Task 0 -> Plan A -> Plan A hardening -> Plan B -> Plan B hardening -> Plan C -> Plan C hardening
```

- `docs/superpowers/plans/2026-09-18-plan-A-test-hardening.md` — the
  harness + the Plan A goldens + the Plan A stress/expected-failure tier.
- A `plan-B-test-hardening.md` is written before Plan B executes (it
  reuses the Plan A harness and adds the L3/L6 goldens + stress tier).
- A `plan-C-test-hardening.md` likewise for L4/L5.

Each hardening plan's Global Constraints require that its band's modules
are complete only when the runtime gate is GREEN and the band's stress
fixtures pass (this extends R7b).

## §5 Conventions (binding)

- **No `sf/src` change.** The hardening plans touch only the harness
  script, the fixtures, and the goldens → the compiler fixed point is
  UNMOVED and the seed is NOT rotated. If a hardening task finds a real
  compiler/std bug, it STOPS and reports it as a separate I/F pair (as
  Plan A's Task 4b/6b did) — it does not fix it in place.
- **Binding gcc flag-set + `timeout 120`** on every binary.
- **Seed-model build only** for the compiler; never invoke `zig0`.
- **Determinism (R6):** fixtures must not depend on addresses, the wall
  clock, or the PID; the 3× gate enforces this.
- **No silent skips:** every discovered fixture must have a committed
  golden, or the harness fails.

## §6 Risks

- **Golden brittleness.** Goldens captured from one compiler could drift
  when the compiler legitimately changes emission. Mitigation: the gate is
  runtime-only (stdout + rc), not emitted-C bytes; the Plan A goldens are
  captured at the hardening plan's baseline and re-captured only on an
  intentional behavior change.
- **`time`/`os` nondeterminism.** The `stdlib_time_*` and `stdlib_os_*`
  fixtures print stable summary lines (`time monotonic ok`, `os argc ok`)
  rather than raw values, so they are golden-stable; any fixture that
  cannot be made stable is declared a probe (rc-only).
- **Harness runtime.** ~40 fixtures × (build+link+run) is slower than the
  compile-only sweep; the harness is opt-in/closeout-only, not per-commit.

## §7 Plan index

1. `docs/superpowers/plans/2026-09-18-plan-A-test-hardening.md` — **next.**
2. `plan-B-test-hardening.md` — written before Plan B.
3. `plan-C-test-hardening.md` — written before Plan C.
