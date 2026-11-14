# SDD ledger — investigation: Windows-hosted zig1.exe failure

Date: 2026-10-24. Agent: Zni-005. Branch: `zig1_improvements`.
Task: I task (investigation only), no production fixes.
Brief: `task-brief.md`.

## Operator decisions
- No operator MSVC/OpenWatcom probe; MSVC/OW outcome will be a prediction.
- Temporary probes/binaries allowed.
- Keep v121 seed artifacts uncommitted.
- Include Linux `gen/` C with MinGW CRT as a differential.
- Local MinGW/Wine only.
- First test: compile already-valid emitted C programs with MinGW here, run under Wine.

## Current state
- Seed compiler: `/tmp/seed_v121/zig1_5_clean` + `/tmp/seed_v121/gen` + `/tmp/seed_v121/lib`.
- CRT-only zip: `release/seed/zig1_seed_w9.zip` (uncommitted; two CRT scripts, `win/` compiler C, lib).
- Known failure: MinGW CRT `zig1.exe` from `win/` builds/runs usage; compiling `hello` fails
  (9x `-fsafe` trap `cnameDedupKey`; `-ffast` `std_debug.zig:64 tag.len`; NT MinGW int3).
- z9dbg passes under MinGW/Wine; basic Windows slices work.
- Compiler uses `@sizeOf`/`@offsetOf`; layout conformance is the leading hypothesis.

## Pre-flight
- Phase 1 is the pivot; if it fails, stop before Phase 2.
- No commits, no production edits, no seed changes.
- Probes only under `/tmp` or the investigation workspace.

Proceed.

## Phase 1-2 results (agent A, phase12-report.md)
- Phase 1 PASS: Linux seed emits valid -osw C for hello/lisp; MinGW builds; Wine runs
  (hello "Hello, world!", lisp `> 3`). Emitter/runtime/MinGW program build are fine.
- Phase 2a FAIL: zip `win/` C (default -fsafe) builds with MinGW CRT and runs usage; compiling
  hello traps in `parseU64` at `max_u64 -= 1` (intentional wrap, -fsafe guard). Prior
  cnameDedupKey attribution was wrong. `-ffast -osw` diagnostic compiler gets further but fails
  `std_async.zig:259` `t.state` field resolution.
- Phase 2b FAIL: Linux `gen/` C (same -ffast) built with MinGW CRT builds and runs usage;
  compiling hello fails the same `std_async.zig:259` field resolution.
- Initial (WRONG) conclusion retracted by operator: `-ffast` is not a fix; it silently wraps
  intentional-safe arithmetic and can mask a real overflow. The `parseU64` trap is correct
  `-fsafe` behavior for the source's intentional wrap. The compiler source is not `-fsafe`-clean.
- Revised plan (task-brief-fsafe.md): investigate `-fsafe` first, all the way through the
  compiler's battery. Temp source copy under `/tmp`; classify intentional wraps vs real
  overflows; first real trap is the candidate root cause for the `-ffast` `std_async` failure.
  `-ffast` only as comparison. No commits. The seed zip stays `-fsafe`; source fixes are a
  separate compiler task.
- Next: `-fsafe` baseline (Linux), trap walk, MinGW `-fsafe`, battery, `-ffast` comparison,
  verdict (agent C).

## Agent C report (report.md)
- Temp `-fsafe`-clean source: 12 intentional wraps + 3 real defects (cpp_key u32 pack,
  named-error-set layout 0/0 -> alignUp underflow, parseF64 >800-digit OOB), 7 files.
- Full battery on the temp `-fsafe` compiler: corpus 1014 OK/58 GREEN/116 FAIL/0 ICE/0 CRASH
  (0 movers), stdlib 336/0, crosscheck 10/10, pins 8/8, goldens 5/5, examples 26/26,
  CLOSEOUT OK. Pins/markers recorded.
- MinGW `-fsafe` clean compiler still fails `std_async.zig:259` with NO trap; not masked
  overflow; separate Windows layout/ABI issue.
- Report: `.superpowers/sdd/2026-10-24-win-hosted-zig1-investigation/report.md`; exact temp
  diff `/tmp/inv/logs/src_fsafe.diff`.

## Preservation + rotation (operator approved)
- Apply all 15 fixes; commit `fix(src)` + `docs(sdd)` report.
- Trust the temp `-fsafe` battery if the copied 7 files are byte-identical; run only the full
  `-ffast` battery in production (seed gate).
- One v121 rotation with both Parts A (seed packaging/Win9x zip) and B (safe compiler); no
  v122, no `-ffast` fallback.
- Agent D: copy 7 files, verify diff, commits fix+report, build from committed v120 seed,
  F_new, full `-ffast` battery, report production-validation.md. No seed rotation.
- Agent E (after D): v121 rotation + docs + commit. No operator MSVC/OW confirmation.
