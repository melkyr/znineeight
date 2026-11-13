# z9play / examples — open compiler defects

Tracks only **open** compiler defects found while building the example programs.
Fixed defects and closed investigations were removed at Phase 2.5 Task 6
(2026-10-29); their history lives in git and the SDD reports. IDs are stable —
deleted numbers are not reused. Next free slot: **D18**.

Open: **D16, D17**.

_(Add new entries at the next free slot as they are found; entries are doc-only
unless a compiler fix is separately authorized.)_

---


## D16 — Parity decision: assignment-expression/switch semantics beyond option (d)

**Status:** OPEN as a tracking/parity decision, not an ordinary broken-code defect.
Operator decision 2026-11-09: do not pursue full assignment/switch parity in
Phase 3.5. D15 is closed for value-result switches by Task 9k; this entry records
why the remaining Zig divergences are deferred and what evidence exists.

**Why this is a decision, not a bug by itself.**
Z98’s current behavior is stable for valid code. The 35 reproducible statement
switches remain accepted; D15’s 12 valid expected-type cases are fixed; the five
mixed value-switch negatives remain rejected. The divergences below appear in
contexts Zig treats as statements or as comptime-pruned arms, and changing the
root typing is a multi-file semantic change with no demonstrated pipeline gain.

**Parity questions deferred here.**
1. **Assignment expression / assignment-ending block.** Z98
   `semanticAnalyzerResolveAssign` returns the LHS type
   (`sf/src/semantic_analyzer.zig:4725`, `:4729`). Zig has no assignment
   expression; an assignment-ending block is `void`. This is what
   `sw_is_stmt_expr` masks (`:5039-5044`).
2. **Mixed statement switches.** Z98 accepts
   `switch { 0 => 1, else => true }`; Zig rejects it.
3. **Comptime-known selector.** Zig analyzes only the taken prong and accepts an
   untaken mismatching prong; the D15 spec rule (“each prong assignable”) rejects
   it. This is a Zig/spec disagreement, not a clear Z98 bug.
4. **`anyerror`.** Zig accepts it; Z98 rejects `error[20]` in both pre-D15 and
   current. Pre-existing keyword/type limitation.
5. **Typed assignment-ended blocks.** `const y: ?i32 = { g = 1; };` and the
   `E!i32` form are accepted with a warning by Z98; Zig rejects them. This is a
   pre-existing typed-init diagnostic gap, not introduced by D15.

**Evidence gathered (do not minimize).**

- **Task 9j — Zig 0.17.1 parity, 119 probes.**
  - Oracle: Zig 0.17.1, archive `sha256 3581863e…`, binary `sha256 58959f01…`.
  - Zig semantics: assignment is a statement; assignment-ending block is
    `void`; `const y: ?i32 = { g = 1; };` rejects.
  - 12/12 valid corpus switches and 35/35 expected-type-sensitive matrix cells:
    accept under Zig and pre-D15, reject under interim D15.
  - 5/5 mixed value negatives: reject under Zig/current, accept pre-D15.
  - `stmt_mixed_int_bool` / `stmt_mixed_int_void`: reject under Zig, accept
    current.
  - Comptime-known mixed selector: Zig accepts (untaken prong not analyzed);
    spec/current reject.
  - `anyerror!i32`: Zig accepts; Z98 `error[20]` in both pre-D15 and current.
- **Task 9l — assignment/void audit, 28 Zig probes, 1278 corpus, 185 switch entries.**
  - Global assignment-void is not safe as two sema lines: 27 emission diffs
    before lowering fixes; 2 after compound-assign; 1 after async frame sizing.
  - Couplings: `lower.zig:6105` compound-assignment op-temp typing;
    `async_analysis.zig:396` frame sizing. Async frames moved:
    `mud_server` 712→720; `z9torr` 12808→12688 in variant A.
  - Switch-only option (c): 12/12 D15 cases, 34/35 reproduced statement entries,
    statement-switch emission byte-identical, **19** expected value-switch
    coercion shifts, one genuine `stdlib_tls_alpn_xmod` fixture migration.
  - Count discrepancy: 38 reported vs 35 reproduced statement entries; three
    remain unaccounted and are not claimed fixed.
  - `z15/z16` typed optional/error-union assignment-block false accepts remain
    warning-only.
- **Task 9k — option (d), value-result switches only.**
  - Kept `sw_is_stmt_expr`; expected-type-first only for value-result switches.
  - 12/12 corpus, 35/35 matrix, 5/5 negatives; mixed statement switches remain
    accepted; statement-switch emission unchanged.
  - 19 expected value-switch emission shifts accepted.
- **Task 9f final — D4 revalidation, 1278 corpus.**
  - Against pre-Task-9 base, **31** emission diffs:
    **19** Task 9k value-switch shifts + **12** D15-recovered
    `*_err_switch`/`*_null_switch` cases.
  - All 31 are value-result switches; no statement switch and no non-switch entry.
  - `rc_mismatch=0`; 12/12 recovered cases emit C; 30/31 diffs are in frozen-1124.
  - **Certified by Task 9f.1 (`e8a300db`):** 31/31 gcc `-m32 -std=c89`
    compile; 29/31 direct run with identical base/final rc+stdout; 2/2
    compile-only entries equal under the fixture’s intentional `getp` stub;
    12/12 recovered cases match pre-D15 Z98; 0 statement-switch C changes.
    `z9play` is mixed value+statement, but only its value-result `return switch`
    emission changed; no statement-switch C changed.
  - D4 revalidates 0/0; suites green; D16 remains open.

**Why it was deferred.** Full parity requires either global assignment-void
(sema + lower + async frame changes, 27→1 emission diffs, async constants) or
switch-only normalization (a special rule, 19 shifts, one fixture migration).
Neither has a demonstrated code/analysis gain over option (d), and both risk the
38 valid statement switches. The conservative decision is to keep the current
valid-code behavior and document the Zig divergence.

**What a future study must decide.**
- Whether Z98 should follow Zig’s statement/void typing at all, or keep the
  current expression-value model.
- If assignment-void is pursued: exact sema/lower/async changes, async-frame
  regression, full corpus build/run, and whether `z15/z16` become rejects.
- If switch-only is pursued: whether the special normalization is acceptable,
  the `tls_alpn` migration, and gcc build/run of all 31 shifts.
- Whether comptime-prong pruning and `anyerror` are worth separate parity work.
- Runtime/golden evidence for any future parity change; the current 31 diffs
  are certified by Task 9f.1, not a reason to revisit them.

**Workaround.** Add explicit type annotations; avoid assignment-ended blocks in
typed optional/error-union positions; do not rely on mixed statement switches.
Full Zig parity is not claimed.

**Reference points.** `semanticAnalyzerResolveAssign`,
`semanticAnalyzerResolveSwitchExpr`, `semanticAnalyzerResolveIfExpr`,
`topExpectedTypeKind`/`topExpectedTypeId`, `typeRegistryIsAssignable`;
`sf/src/lower.zig:6105`;
`sf/src/async_analysis.zig:396`; Task 9i `280a3b12`; Task 9j/9l/9k/9f reports;
`repro/mi_matrix/known_excluded/d15_parity/`,
`repro/mi_matrix/known_excluded/d15_assignment_void/`.

## D17 — Optional array return emits a non-assignable C array assignment (`?[N]T`)

**Status:** OPEN (deferred — documented workaround, no compiler fix authorized).

**Symptom.** A function returning `?[2][]const u8` dumps cleanly (`-ffast -o`
rc=0), but the emitted C does not compile: the optional payload is copied with a
plain C assignment, and C arrays are not assignable.

**Minimal repro (Zig source shape).**

```zig
fn splitOnce(s: []const u8, sep: u8) ?[2][]const u8 {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == sep) {
            var parts: [2][]const u8 = undefined;
            parts[0] = s[0..i];
            parts[1] = s[i + 1 .. s.len];
            return parts;
        }
    }
    return null;
}
```

Command: `zig1_5_clean -ffast -o /tmp/probe_splitonce/out /tmp/probe_splitonce/main.zig`
→ dump rc=0, then
`sh /tmp/probe_splitonce/out/build_target.sh linux /tmp/probe_splitonce/out/prog`
→ build rc=1:

```text
main_A67D5914.c:83:17: error: assignment to expression with array type
   83 |     zT_30.value = parts;
main_A67D5914.c:125:11: error: assignment to expression with array type
  125 |     zT_12 = zT_8.value;
```

**Classification.** Emitted-C assignment of an array-typed optional payload
(`?[N]T`, where `T` is an array or a slice-array element type). C cannot assign
arrays, so an optional unwrap/return must be emitted structurally (field copy or
`memcpy`), not as `lhs = rhs`.

**Scope / impact.** No `?[N]T` returns exist in `sf/src`, so the shipped std
surface is unaffected. Found while adding `std_str.splitOnce` (commit
`22cfbfe6`); the brief pre-authorized a shape fallback for exactly this case.

**Workaround.** Return `bool` + a 2-field out-param struct (or an
optional-of-struct `?S`). Shipped as
`pub const SplitOnce = struct { first: []const u8, second: []const u8 };` and
`pub fn splitOnce(s: []const u8, sep: u8, out: *SplitOnce) bool` in
`sf/src/std_str.zig`.

**Evidence.** Probe: `/tmp/probe_splitonce/main.zig` (repo-external). Task
report:
`.superpowers/sdd/2026-11-12-undersanded-m01-std-audit-plan/task-2-report.md`.
Fix commit: `22cfbfe6 feat(std): str splitOnce`.

**Note.** Doc-only entry. Any compiler fix (structural optional-array
return/unwrap emission) is separately authorized and out of scope here.
