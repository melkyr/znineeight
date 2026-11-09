# z9play / examples — open compiler defects

Tracks only **open** compiler defects found while building the example programs.
Fixed defects and closed investigations were removed at Phase 2.5 Task 6
(2026-10-29); their history lives in git and the SDD reports. IDs are stable —
deleted numbers are not reused. Next free slot: **D16**.

Open: **D15**.

_(Add new entries at the next free slot as they are found; entries are doc-only
unless a compiler fix is separately authorized.)_

## D15 — Mixed-type value-switch prongs are silently accepted and typed as the first prong

**Status:** OPEN — investigation 2026-11-09 at base `3cec507a`; found while
re-checking the synthetic `testSwitchExprMixed` against the current C89 pipeline.

**Defect.** `semanticAnalyzerResolveSwitchExpr` handles a non-coercible prong
type mismatch in its MIX else-branch by recording `TYPE_VOID` for the switch
node and `continue`ing, but it emits **no diagnostic** and leaves `unified`
holding the first prong's type. The post-loop tail then overwrites the in-loop
`TYPE_VOID` with `unified` and returns it. A value switch with incompatible
prong types is accepted rc=0, typed as the first prong, and the mismatched prong
is silently materialised in that type (`true` becomes `1`).

**Repro.** `repro/mi_matrix/known_excluded/switch_value_mixed_type_repro/`:

```zig
fn pick(n: i32) i32 {
    return switch (n) {
        0 => 1,
        else => true,
    };
}

pub fn main() void {
    var r = pick(0);
    _ = r;
}
```

Expected: clean level-0 type-mismatch reject at the mismatching prong, rc=2,
0 `.c`, under `-ffast` and `-fsafe`. Current: `--check` and `--dump-c89` rc=0,
no `error[...]`, `.c` emitted; gcc accepts; `bool true` is emitted as `1`. The
inferred form and reverse prong orders are also accepted.

**Root cause.** `sf/src/semantic_analyzer.zig:4918`
(`semanticAnalyzerResolveSwitchExpr`): MIX branch `:5187-5202`, tail overwrite
`:5256-5258`. The code contradicts the documented MIX contract in
`sf/docs/tech_docs/05_semantic_analysis.md:537-550`.

**Impact.** Silent acceptance of an ill-typed value switch; the switch takes the
first prong's type and mismatched prongs are silently converted. Type errors are
hidden and inferred bindings get the wrong type; runtime behavior can change with
prong order.

**Workaround.** Do not mix prong types. Coerce all prongs explicitly to one
common type (or restructure as a same-typed `if`) before the switch.

**Reference points.** `sf/src/semantic_analyzer.zig:4918/5187-5202/5256-5258`;
`sf/src/diagnostics.zig` `ERR_3000_TYPE_MISMATCH`; `testSwitchExprMixed`
(`sf/src/tests/test_semantic_bin.zig:736-764`);
`.superpowers/sdd/2026-10-29-phase35-defects-plan/task-d15-investigation-report.md`.
