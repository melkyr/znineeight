# Preserve `-fsafe` fixes + validate `-ffast` (seed rotation follows separately)

**Repo:** /workspace/znineeight, branch `zig1_improvements`, HEAD `c13de0bc`.
**Investigation report:** `.superpowers/sdd/2026-10-24-win-hosted-zig1-investigation/report.md`
**Temp fixed source:** `/tmp/inv/src_fsafe` (7 changed files; exact diff at `/tmp/inv/logs/src_fsafe.diff`).

## Operator decisions
- Apply **all 15** fixes: 12 intentional wraps + 3 real defects (`cpp_key`, named-error-set layout, `parseF64` >800-digit OOB).
- Part A (seed packaging scripts/docs/Win9x zip) is already committed; Part B is the source fixes. Both go into one **v121** rotation; no v122, no `-ffast` fix.
- Commit the investigation report.
- Trust the agent’s full `-fsafe` battery if the copied files are byte-identical; run the full battery **only in `-ffast`** (the seed-rotation gate). No duplicate `-fsafe` battery.
- No seed rotation in this task; the next agent does v121 after this validation.

## Step 1 — apply Part B
- `diff -rq sf/src /tmp/inv/src_fsafe` must list exactly:
  `c89_emit.zig`, `comptime_eval.zig`, `lexer.zig`, `lir_opt_pass.zig`,
  `semantic_analyzer.zig`, `type_registry.zig`, `type_resolver.zig`.
- Copy those 7 files from `/tmp/inv/src_fsafe` into `sf/src` (operator-authorized copy-over).
- Verify `diff -rq sf/src /tmp/inv/src_fsafe` is empty (or only generated/temp noise), and
  `git diff` contains only the 15 intended sites (compare with `/tmp/inv/logs/src_fsafe.diff`).
  No unrelated changes; `git diff --check` clean.
- Commit only the 7 source files:
  `fix(src): make the compiler -fsafe-clean (12 wraps + 3 real defects)`.

## Step 2 — commit the investigation report
- Update the report with a short "Production preservation" section (copy exact, commit hash,
  the `-fsafe` battery is the agent’s evidence, `-ffast` validation below).
- Commit `.superpowers/sdd/2026-10-24-win-hosted-zig1-investigation/` (report, phase12 report,
  briefs, ledger):
  `docs(sdd): -fsafe investigation report`.
- Do **not** stage `release/seed/*` (stale uncommitted v121 artifacts), `run.err`, or P4 docs.

## Step 3 — build from the committed v120 seed
- The working-tree `release/seed/zig1-seed.tgz` is a **stale uncommitted v121**; do not use it.
- Extract the committed v120 seed:
  `git show c13de0bc:release/seed/zig1-seed.tgz > /tmp/v120_seed.tgz`
  (or `git show HEAD^:...` before the fix commit; the fixed commit does not touch the seed).
- Build the fixed source from that seed:
  `bash scripts/seed/build_from_seed.sh /tmp/v120_seed.tgz /tmp/fixed_v121_build`
- Record `hop1`/`hop2` and `F_new` (the fixed point will move from `11de43a…`).
- If the two-hop closure fails, STOP.

## Step 4 — full `-ffast` battery (the gate)
Use `/tmp/fixed_v121_build/zig1_5_clean` as `ZIG` and the canonical commands from
`docs/sf/QUICK_REF.md`:
- corpus frozen-1124 (`0 movers` vs the v120 seed baseline),
- goldens 5/5,
- 8 dump-MD5 pins (record values; `8/8` and no mover),
- markers (record),
- examples 26/26,
- `verify_stdlib` 336/0,
- crosscheck 10/10.
Do **not** rerun the full `-fsafe` battery; the temp copy is byte-identical and the agent
already ran it. A single `-fsafe` hello smoke is allowed only if the byte check was not exact.
- Record exact commands/results in `production-validation.md`.
- If any battery fails or a pin moves, STOP and report; do not proceed to rotation.

## Step 5 — report
Write `/workspace/znineeight/.superpowers/sdd/2026-10-24-win-hosted-zig1-investigation/production-validation.md`:
copy verification, commits, F_new/hop closure, full `-ffast` battery results, the accepted
`-fsafe` battery evidence reference, and the remaining MinGW `std_async` result (no fix here).
Return only: status, commits, F_new, battery one-liner, report path.

## HARD RULES
- No seed rotation; no `release/seed/*` changes/commits in this task.
- No production edits beyond the 7 files. No unrelated fixes.
- Use `copy` for the 7 files (operator-authorized); use edit/fastedit if any hunk needs repair.
- No sed/perl/python source transforms. No destructive git. No push. No subagents.
- If a requirement is ambiguous or a gate fails, STOP and report BLOCKED with evidence.
- Do not use the `compress` tool.
