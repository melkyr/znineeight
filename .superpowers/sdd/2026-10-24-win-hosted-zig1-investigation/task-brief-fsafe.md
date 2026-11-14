# I task revision 2 — `-fsafe` first (no `-ffast` fix)

**Repo:** /workspace/znineeight, branch `zig1_improvements`.
**Mode:** investigation only. NO COMMITS. No production edits. Temporary source copy under `/tmp` is allowed.
**Seed artifacts:** v121 tgz/zip/CHANGELOG remain uncommitted; do not touch or commit them.

## Operator decisions
1. Temporary **Z98 source copy** under `/tmp` for the `-fsafe` walk: YES.
2. Stop condition: not just hello/lisp — **the compiler’s whole battery must run/compile under `-fsafe`**. Our own source must be safe by default, even if a user chooses `-ffast`.
3. `-ffast` is **not a fix**. Only a comparison, because the compiler passes the battery under `-ffast`.
4. No commits of any kind.

## Key correction
`lexer.zig:597-598` (`max_u64 = 0; max_u64 -= 1;`) is an intentional wrap. `-fsafe` correctly traps. The compiler source is not `-fsafe`-clean; `cnameDedupKey` and other hash/accumulator loops also use ordinary `*`/`+` that wrap. `-ffast` silently wraps and can mask a real overflow; the `-ffast` `std_async.zig:259 t.state` failure may be downstream corruption from an unchecked overflow.

## Phase A — Linux `-fsafe` baseline (first test)
- Copy `/workspace/znineeight/sf/src` to `/tmp/inv/src_fsafe` (whole tree, including `include`).
- Emit `-fsafe -osl` from the copy with `/tmp/seed_v121/zig1_5_clean` (lib beside it); build with gcc; run `hello`.
- Record the first trap. Expected: `lexer.zig:597-598` `parseU64`.
- This proves the source is not `-fsafe`-clean on any host.

## Phase B — classify all `-fsafe` traps
- Walk the temp source: replace intentional wraps with explicit safe forms (constant `0xFFFFFFFFFFFFFFFF`; wrapping `*%`/`+%` or Z98 equivalents; explicit `@intCast`/`@truncate` as appropriate). Rebuild `-fsafe` Linux after each class; run `hello`, `lisp`, then the battery.
- Record every trap: site, operands, call stack, classification:
  - **intentional wrap** (hash/FNV/max constants);
  - **real overflow** (index/size/length/count) — candidate root cause.
- The first **real** trap is the primary suspect for the `-ffast` corruption. Capture it fully.
- Stop only when the compiler’s whole battery runs under `-fsafe`, or a real trap blocks progress.

## Phase C — MinGW `-fsafe` with the same temp fixes
- Build the temp-patched compiler with `-fsafe -osw` + MinGW CRT; run `hello`, `lisp`, then as much of the battery as feasible.
- Works → the Windows compiler is fine under the correct profile; the `-ffast` failure is masking/`-ffast` emission.
- Traps in **real** code → that trap is the Windows root cause.
- Fails `std_async` with no trap → then layout/ABI investigation on the `-fsafe` build (secondary).

## Phase D — `-ffast` comparison (not a fix)
- Build the same temp source with `-ffast`; run the same programs.
- Determine whether `-ffast` silently wrapped the real overflow and whether fixing it in the temp `-fsafe` source removes the `std_async` failure.
- Compare `-fsafe` vs `-ffast` C/binary at the failing sites; identify masking vs real emission bug.

## Phase E — battery
Use the canonical gate commands from `docs/sf/QUICK_REF.md` with the temp `-fsafe` compiler:
- corpus frozen-1124, goldens 5/5, 8 pins, markers, examples 26/26, `verify_stdlib` + crosscheck.
- Record pass/fail and any movers vs the `-ffast` baseline.
- If the full battery is too long, run it in stages and report exactly what ran; the acceptance is the whole battery.

## Phase F — report (no commit)
Write `/workspace/znineeight/.superpowers/sdd/2026-10-24-win-hosted-zig1-investigation/report.md`:
- `-fsafe` source violations (intentional vs real), exact temp diffs;
- first real trap + evidence;
- battery results under `-fsafe`;
- MinGW `-fsafe` result;
- `-ffast` comparison / masking evidence;
- root cause and whether the `std_async` failure is explained;
- MSVC/OW prediction (unconfirmed; no operator probe);
- seed decision: the zip stays `-fsafe` (no `-ffast` fallback); source fixes are a separate compiler task;
- remaining uncertainty.
Return only: status, root-cause one-liner, battery result, report path.

## HARD RULES
- No commits. No production edits. No changes to `release/seed/*`, `run.err`, `.opencode/memory`, or untracked P4 docs.
- Temp source copy and probes only under `/tmp` or the investigation workspace.
- Use `edit`/`fastedit` for the temp source; no sed/perl/python transforms.
- No subagents. No destructive git.
- If a phase cannot run, STOP and report the exact blocker. Do not fake evidence.
- Do not use the `compress` tool.
