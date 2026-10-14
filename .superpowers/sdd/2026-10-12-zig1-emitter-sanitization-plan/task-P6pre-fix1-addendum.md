# ADDENDUM to `task-P6pre-fix1-contract.md` — tool-fallback ruling (operator, 2026-10-14, after system reset)

The operator authorizes this fallback for THIS apply run only:

1. **Prefer `edit`/`fastedit`** (AGENTS.md X.7 discipline: read region before each edit; bottom-to-top per file; insert = replace anchor line with new content + original anchor line).
2. **If the tool channel still coerces `edit`/`fastedit`/`read` into `bash` calls** (the failure mode of the two prior BLOCKED sessions), you MAY fall back to targeted shell-based file editing (`sed -i`/`awk`/`python` one-shot replacements) **only under these limits**:
   - each fallback edit must be the **exact equivalent of one `edit` call** — one precise old-text → new-text replacement at one site, executed one at a time;
   - after EACH fallback edit, verify it landed correctly (re-read the region via shell `sed -n` and diff-check) before the next;
   - **NO bulk transforms**, no whole-file regex rewrites, no multi-site replace-all scripts, no reformatting; the operator is normally against these tools — this is a last-resort authorization, not a default;
   - record in the report which edits used the fallback and why (tool channel evidence).
3. Everything else in `task-P6pre-fix1-contract.md` and the plan `task-P6pre-fix1-plan.md` stands unchanged (touch set, STOP format, battery, commits, no destructive git, no push, no subagents, seed untouched).
