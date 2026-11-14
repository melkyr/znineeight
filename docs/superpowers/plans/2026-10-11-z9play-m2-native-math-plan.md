# z9play M2 — Native float math in `std_math` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add pure-Z98 `f64` math to `sf/src/std_math.zig` — at minimum `sqrt`, `sin`, `cos` — implemented as portable algorithms (no C `libm` externs, no compiler builtins), so z9play's native Vorbis decoder can be written in Z98 and still run on Win9x.

**Architecture:** This is the one z9play milestone that edits the **standard library**, not the example. Z98 has `f64` arithmetic (`+ - * /`, `@floatCast`, `@intToFloat`) but **no `@sqrt`/`@sin`/`@cos` builtins** and `std_math` is integer-only. Mirror real Zig's approach (Zig implements these *without* `libm`): port fdlibm/musl-style algorithms. `std_math` is re-exported as `std.math`, so no `std.zig` change is needed.

**Tech Stack:** Z98 (`zig1`, `gcc -m32`, `-fsafe`), `std_crypto` (SHA-1 for the fixture), the stdlib fixture harness.

**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` §3 (binding).

**Sequence:** PREVIOUS: `2026-10-11-z9play-m1-setup-codebooks-plan.md`. NEXT: `2026-10-11-z9play-m3-audio-decode-plan.md`.

## Global Constraints

- Modify **only** `sf/src/std_math.zig` (+ its fixture + registration). **No compiler change** (`sf/src` main closure, `c89_emit`, `lower`, `pal`, `emit_support`, `include` untouched) → the compiler fixed point must stay unchanged.
- `scripts/stdlib/verify_stdlib.sh <seed-built zig1>` MUST stay green.
- Z98 rules as in M0/M1 (NOTE 2026-10-11: compiler defects D1–D6 are FIXED in seed v97 — no union-tag/synthetic-slice/async-frame/lvalue/`@ptrFromInt` workarounds are needed). Build `-fsafe`. `edit`/`fastedit` only. **NO push.** git hard rule. Plan is the only authority (STOP-present).
- Reports under `.superpowers/sdd/2026-10-11-z9play-m2-native-math-plan/`.

## File Structure

- `sf/src/std_math.zig` — add `pub fn sqrt(x: f64) f64`, `pub fn sin(x: f64) f64`, `pub fn cos(x: f64) f64` (and any helper the decode milestones require — confirm from M1 Task 5).
- `repro/mi_matrix/stdlib_math_f64_xmod/{main.zig, expected.txt, expected.rc}` — stdlib fixture.
- `scripts/stdlib/expected_dirs.txt` — pin the fixture dir.
- `docs/sf/QUICK_REF.md` — note the new `std_math` f64 surface.

---

### Task 0: Preflight — confirm the required function set + baseline

- [ ] Read M1 Task 5's amendment review output. Confirm the exact f64 functions M3 needs (`sqrt`, `sin`, `cos`, and any other). If the set differs from this plan, amend this plan first (operator-approved). Record the `verify_stdlib` baseline count (expect 284).

### Task 1: `sqrt` (f64)

**Files:** `sf/src/std_math.zig`; fixture.
**Interfaces:** `pub fn sqrt(x: f64) f64` — handle `x < 0` (return `nan` via `0.0/0.0` or a defined quiet-NaN), `x == 0`, `inf`; otherwise a bit-twiddling initial guess + Newton iterations to full f64 precision (or a correctly-rounded integer-seeded method).
- [ ] Failing fixture test: `sqrt` of `{0, 1, 4, 2, 1e6, 0.25, 2.25}` vs exact expected (integer/known values exact; irrationals to full precision). Implement. PASS. Commit `feat(std_math): f64 sqrt (pure Z98)`.

### Task 2: `sin` / `cos` (f64)

**Files:** `sf/src/std_math.zig`; fixture.
**Interfaces:** `pub fn sin(x: f64) f64`, `pub fn cos(x: f64) f64` — argument reduction (Payne–Hanek-lite or Cody–Waite with a `2/π` split constant) + a minimax polynomial (fdlibm `__kernel_sin/cos` port). Accurate across the decoder's input range.
- [ ] Failing fixture test: `sin`/`cos` at `{0, π/6, π/4, π/3, π/2, π, 3π/2, 2π, -π/4, 100π}` vs published f64 values within a stated ULP bound. Implement. PASS. Commit `feat(std_math): f64 sin/cos (pure Z98)`.

### Task 3: Fixture registration + `verify_stdlib`

**Files:** `repro/mi_matrix/stdlib_math_f64_xmod/`, `scripts/stdlib/expected_dirs.txt`.
- [ ] Ensure the fixture has `main.zig` + `expected.txt` + `expected.rc`, pin it in `expected_dirs.txt` (sorted), and run `bash scripts/stdlib/verify_stdlib.sh <seed-built zig1>` → `STDLIB GATE OK` (284 + new). Commit `test(std_math): f64 fixture + registration`.

**Gate:** `verify_stdlib` green; compiler fixed point unchanged (`hop1==hop2 ==` the current seed closure).

### Task 4: z9play math tier

**Files:** `examples/z98/z9play/tests/tier_math.sh` (and, if useful, a tiny `examples/z98/z9play/mathtest.zig`).
- [ ] `tier_math.sh`: build a small z9play-local program under `-fsafe` that computes the same identities as the std fixture and diffs against the committed expected values; asserts the build uses **no libm symbol** (`nm`/`objdump` shows no `sqrt`/`sin`/`cos` imports). Run PASS. Commit `test(z9play): M2 math tier`.

**Gate:** `tier_math.sh` green; no `libm` linkage.

### Task 5: Docs + commit

- [ ] Update `docs/sf/QUICK_REF.md` (`std_math` f64 surface) and `examples/z98/z9play/NOTES.md`. Commit `docs(z9play): M2 native math`.

### Task 6: Next-milestone amendment review (M3)

- [ ] Read `2026-10-11-z9play-m3-audio-decode-plan.md`. Judge whether M2's actual `std_math` surface (signatures, precision, error/NaN behavior, any extra helpers added) invalidates M3's assumptions (which functions it calls, expected accuracy). If so, **STOP-present** the M3 amendment; else record "no amendment needed".

**Gate:** approved M3 amendment or justified "no amendment needed".
