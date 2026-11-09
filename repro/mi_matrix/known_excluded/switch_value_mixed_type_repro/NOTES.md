# switch_value_mixed_type_repro — D15 RED

Phase 3.5 D15 investigation repro. Value-switch prongs have non-unifiable types:
`int_literal` (1) and `bool` (`true`). Expected (Zig 0.15.2 and the intended
Z98 unification contract): a clean level-0 type-mismatch reject at the switch
prong, rc=2, 0 `.c`.

Current behavior (HEAD 3cec507a, compiler md5
`1bdedb7419952ed10be80f1cca7b5476`): accepted rc=0 for `--check` and
`--dump-c89` under `-ffast` and `-fsafe`; the switch is typed as the first
prong (`TYPE_INT_LIT` -> `int`), the `bool` prong is emitted as `1`, gcc
`-m32 -std=c89` accepts the C. See
`.superpowers/sdd/2026-10-29-phase35-defects-plan/task-d15-investigation-report.md`.

The equivalent inferred form (`var x = switch (n) { 0 => 1, else => true };`)
is also accepted and inferred as `int`; a use (`x + 1`) compiles too.

Do NOT add this directory to the live corpus; it stays under `known_excluded/`
until D15 is fixed and this file is updated to the reject contract.
