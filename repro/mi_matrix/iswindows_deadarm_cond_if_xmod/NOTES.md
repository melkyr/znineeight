# iswindows_deadarm_cond_if_xmod — T3 sema-gate fixture (RED before T3)

## What it tests
The sema half of the spec §3 Zig rule (Task 3 of the D1/D2 parity plan): when
an `if`/`else` condition is comptime-known (narrow trigger set: `@isWindows()`,
literal `true`/`false`, comptime `const` bool conditions), the untaken arm is
**not semantically analyzed** and the `if` takes the live arm's value/type.
Errors inside a comptime-dead arm vanish (Zig behavior). Runtime conditions
are untouched (not exercised here — the frozen corpus covers them).

Four shapes (see the `main.zig` header for the full contract):
1. literal `false`, dead then-arm with an undeclared ident (`error[20]`).
2. comptime `const use_windows: bool = false`, dead then-arm, undeclared ident.
3. value `if (false) dead_ident else 42` — dead arm never typed; the `if`
   takes the live arm's value (`q == 42` at runtime).
4. `if (@isWindows())` — target-relative dead arm, both arms clean (the D2
   fixture pair pins the emission side of this shape).

## Mechanism (pre-fix)
`semanticAnalyzerResolveIfExpr` (`sf/src/semantic_analyzer.zig`) resolves BOTH
arms unconditionally, and the `if_stmt` statement walker pushes both arms
(`semanticAnalyzerStmtWorkPush`). The only arm-reachability use of the
comptime probe (`semanticAnalyzerConditionComptimeBool`) is the FX9
f32-narrow status. So a dead-arm error is reported (this fixture's RED) and
the dead arm's value/type participates in peer typing.

## Measured pre-fix (2026-10-16, pin compiler `/tmp/d1d2_t2/zig1_5_clean`,
md5 `6e6d1262e4a286486d2f478961fbd040`)
Linux `-ffast --dump-c89 --output-dir`:
- dump rc=2, **0 `.c`**.
- stderr census: `error[20]` ×3 (dead-arm undeclared idents at main.zig
  shapes 1–3) + `warning[3000]` ×2 (assignment mismatch rows feeding the
  undeclared idents). No `error[3000]` rows → class **FAIL** (not GREEN).
- Reject-census pins: `expected.rc` = 2, `expected_error.txt` = `20 3`
  (warnings recorded here, not in the census file).

## Expected classification
- RED pre-fix: **FAIL** (measured above, recorded before the fix).
- After T3 (comptime-if fold: untaken arm not analyzed/not lowered): the dead
  arms vanish; dump rc 0; builds clean; runs deterministic 3x; stdout
  `cond if ok\n` rc 0 (live-arm value pins hold) → class **OK** (this NEW
  fixture's designed FAIL→OK flip; pre-existing corpus class-file anchor is
  untouched). T3 captures the runtime golden at flip (`run_fixtures.sh
  --capture`); `expected.rc` flips `2` → `0` at capture (the T1/T2 coerce
  precedent).

## Why no expected.txt pre-fix
The frontend reject means no runtime output is measurable pre-fix (T0 ruling
R1: reject-shape → `expected.rc` + `expected_error.txt`).

## Post-fix measured (2026-10-16, T3 gate compiler `/tmp/d1d2_t3/zig1_5_clean`,
hop1 == hop2 output; fixed point `362fcfb25d88068388755fc1e0ce6c2d`)
Linux `-ffast --dump-c89`: dump rc 0, 5 `.c`, 0 diagnostics. Built clean
(binding gcc flag-set), runs deterministic 3x: stdout `cond if ok\n` rc 0
(the live-arm value/type pins hold: `x == 2`, `q == 42`). Golden captured at
flip (`run_fixtures.sh --capture`; `expected.rc` flipped `2` → `0`, T2's
coerce precedent — `expected_error.txt` remains the committed RED record).
`-osw` target: dump rc 0, mingw build clean, wine run `cond if ok` rc 0 (the
value pins are target-neutral; only the `@isWindows()` sub-shape's live arm
swaps). Class flip: **FAIL → OK** (designed NEW-fixture flip).
