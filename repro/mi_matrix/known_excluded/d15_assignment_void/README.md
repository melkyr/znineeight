# D15 assignment/expression `void` audit probes (Task 9l)

Investigation/test-only evidence for
`docs/superpowers/specs/2026-10-29-phase35-assignment-void-investigation.md`.
No `sf/src` file was changed.

`probes/z01..z28` are small programs run through the verified Zig 0.17.1 oracle
and through the clean HEAD Z98 compiler plus throwaway diagnostic variants.
They establish Zig's semantics for assignment statements, assignment-ending
blocks, expression statements, chained/conditional assignment, switch prongs,
`_ =`, `defer`, and optional/error-union blocks.

Key result: Zig 0.17.1 has no assignment *expression*; assignment is a
statement. An assignment-ending block has type `void`. `(x = 1)`, `x = y = 1`,
assignment in `if`/`while` conditions, call arguments, `return`, `@TypeOf`, and
parenthesized statements are parse errors. Assignment-ended blocks are valid
only where `void` is expected or the value is discarded.

Files:

- `probes/` — 28 Zig/Z98-compatible probes.
- `results/zig_0_17_1.tsv` — oracle rc + first diagnostic per probe.
- `results/z98_probe_matrix.tsv` — rc/C-file matrix for HEAD and diagnostic
  variants A, B, C, D, E, G, H.
- `results/corpus_all_1278.tsv` — full canonical corpus `--check` status for
  HEAD vs global assignment-void (A) and A + statement-peer (B).
- `results/corpus_switch_185.tsv` — the 185 canonical entries containing
  `switch`, HEAD vs statement-peer (C), A+peer (B), switch-only normalization
  (G), and G + expected-first (H).
- `results/statement_switch_repro35.tsv` — the 35 reproduced entries that the
  9k statement rule rejects at HEAD, with G/H outcomes.
- `results/emission_switch_185.tsv` — emitted `.c`/`.h` hashes for HEAD/A/D/E/G/H.
- `results/d15_parity_under_H.tsv` — the 12 D15 cases, negatives and selectors
  under the combined switch-only-normalization + expected-first shape (H).
- `results/compilers.txt`, `results/commands.txt` — exact provenance/commands.
- `variants/` — diagnostic-only diffs against clean HEAD. These were applied in
  throwaway `/tmp` copies for measurement, never to this repo, and are **not**
  the uncommitted Task 9k candidate.

Variants:

| Tag | Shape |
|---|---|
| A | global assignment returns `void` only |
| B | A + remove `sw_is_stmt_expr` |
| C | remove `sw_is_stmt_expr` only |
| D | A + compound-assignment op-temp type fix in `lower.zig` |
| E | D + async `scanFrameLocals` assignment-node type fix |
| G | remove `sw_is_stmt_expr` + normalize valueless/assignment prongs to `void` |
| H | G + expected-type-first (the proposed 9k target) |

`H` is the only variant that both accepts the 12 D15 cases and avoids the 35
statement-switch regressions, with the single exception of
`repro/mi_matrix/stdlib_tls_alpn_xmod`, whose prongs genuinely mix `void` with a
tagged-union result and therefore need a fixture migration under any rule that
removes the statement exemption.
