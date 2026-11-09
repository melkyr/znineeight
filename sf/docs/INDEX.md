# Self-Hosted Compiler Documentation — Index

`sf/docs/` is the single home for self-hosted (`zig1`) documentation. It is
split by the nature of the material:

## Observed implementation — `tech_docs/`

`sf/docs/tech_docs/` records the **observed** implementation: the as-built
pipeline, function cross-references, and subsystem behavior for the current
compiler. Start at [`tech_docs/INDEX.md`](tech_docs/INDEX.md).

## Design intent as first thought — `initial_design/`

`sf/docs/initial_design/` preserves the **design intent as first thought**: the
original p2 design corpus, kept for historical context and comparison with the
as-built docs. Start at [`initial_design/Design_p2.md`](initial_design/Design_p2.md).

- `Design_p2.md`
- `AST_PARSER_p2.md`
- `AST_LIR_Lowering_p2.md`
- `LIR_C89_Emission_p2.md`
- `TYPE_SYSTEM_p2.md`
- `STATIC_ANALYZERS_p2.md`
- `RUNTIME_PAL_p2.md`
- `ERROR_HANDLING_p2.md`
- `TEST_HARNESS_p2.md`
- `Lexer_sf.md`
- `Import_Symbol_reg.md`
- `COMPLEMENT.md`
- `z98_external.md`
- `AI_TASKS_sf.md`

## Operational and user-facing docs — `docs/sf/`

The operational set stays in `docs/sf/`: `AGENTS.md`, `QUICK_REF.md`,
`manuals/`, `std_lib/`, `Debugging.md`, `std_additions.txt`, and
`zig0_zig1_matriuska_bug.md`.

## zig0-era documentation — `docs/reference/` and `docs/design/`

The zig0-era documents (including `docs/reference/compilation_model.md`,
`docs/reference/c89_emission.md`, and all of `docs/design/`) stay untouched so
anyone can compare the bootstrap against `zig1`. They are archived only with
the future `zig0/` packing.

The living language specification remains
[`docs/reference/Language_Spec_Z98.md`](../reference/Language_Spec_Z98.md).
