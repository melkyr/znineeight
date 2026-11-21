# z9play / examples — open compiler defects

Tracks only **open** compiler defects found while building the example programs.
Fixed defects and closed investigations were removed at Phase 2.5 Task 6
(2026-10-29); their history lives in git and the SDD reports. IDs are stable —
deleted numbers are not reused. Next free slot: **D28**.

Open: **D16, D17, D18, D19, D20, D21, D22, D23, D24, D25, D26**.

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
   `semanticAnalyzerResolveAssign` returns the LHS type. Zig has no assignment
   expression; an assignment-ending block is `void`. This is what
   `sw_is_stmt_expr` masks in `semanticAnalyzerResolveSwitchExpr`.
2. **Mixed statement switches.** Z98 accepts
   `switch { 0 => 1, else => true }`; Zig rejects it.
3. **Comptime-known selector.** Zig analyzes only the taken prong and accepts an
   untaken mismatching prong; the D15 spec rule (“each prong assignable”) rejects
   it. This is a Zig/spec disagreement, not a clear Z98 bug.
4. **`anyerror`.** Zig accepts it; Z98 rejects `error[20]` in both pre-D15 and
   current. Pre-existing keyword/type limitation.
5. **Typed assignment-ended blocks.** `const y: ?i32 = { g = 1; };` and the
   `E!i32` form are accepted by Z98 (no diagnostic in the current probe); Zig
   rejects them. This is a pre-existing typed-init diagnostic gap, not
   introduced by D15.

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
  - Couplings: `lowerCompoundAssignRest` in `sf/src/lower.zig`
    (compound-assignment op-temp typing); `scanFrameLocals` in
    `sf/src/async_analysis.zig` (frame sizing). Async frames moved:
    `mud_server` 712→720; `z9torr` 12808→12688 in variant A.
  - Switch-only option (c): 12/12 D15 cases, 34/35 reproduced statement entries,
    statement-switch emission byte-identical, **19** expected value-switch
    coercion shifts, one genuine `stdlib_tls_alpn_xmod` fixture migration.
  - Count discrepancy: 38 reported vs 35 reproduced statement entries; three
    remain unaccounted and are not claimed fixed.
  - `z15/z16` typed optional/error-union assignment-block false accepts remain
    warning-only (superseded 2026-11-17: the current probe emits no diagnostic at
    all — see the re-verification below).
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

**Task 3b-D current-compiler re-verification (2026-11-17).** Binary
`/tmp/zig3bC_r1/zig1_5_clean` (md5 `0f72ce60ae90f426696b47a6826a3061`); probes
under `/tmp/t3bD/`; `--check -ffast` and `--dump-c89 -ffast --output-dir <out>`
rc and `.c` count recorded. None of the five sub-items now matches Zig; all are
kept.

- (a) assignment-ending block still takes the LHS type:
  `const block: i32 = { g = 2; };` (`/tmp/t3bD/d16a/main.zig`) check/dump rc=0,
  5 `.c`. Bool-typed twin `/tmp/t3bD/d16a_bool/main.zig` emits `warning[3000]`
  (`source: i32`, `target: bool`) and still rc=0/5 `.c`; confirmed a warning, not
  an error (`/tmp/zig3bC_r1/zig1_5_clean --check -ffast
  /tmp/t3bD/d16a_bool/main.zig` → rc=0, same text; `--dump-c89` → rc=0, 5 `.c`).
  Zig rejects because the block is `void`. A bare `(g = 1)`
  (`/tmp/t3bD/d16a_paren/main.zig`, check/dump rc=2, 0 `.c`) is a parse
  `error[2000] expected ')' but found token` (Z98 also has no assignment
  expression), so only the block typing diverges.
- (b) mixed statement switch accepted: `/tmp/t3bD/d16b/main.zig`
  (`switch (v) { 0 => 1, else => true }`) check/dump rc=0, 5 `.c`, no
  diagnostics. Zig rejects.
- (c) comptime-known selector still rejects the untaken mismatching prong:
  `/tmp/t3bD/d16c/main.zig` (`return switch (0) { 0 => 1, else => true };`)
  check/dump rc=2, 0 `.c`, `error[3000]` type mismatch (`source: bool`,
  `target: i32`). Zig accepts.
- (d) `anyerror!i32` still rejected: `/tmp/t3bD/d16d/main.zig` check/dump rc=2,
  0 `.c`, `error[20]: identifier 'anyerror' is not declared or imported`.
- (e) typed assignment-ended optional/error-union blocks still accepted:
  `/tmp/t3bD/d16e1/main.zig` (`const y: ?i32 = { g = 1; };`) and
  `/tmp/t3bD/d16e2/main.zig` (`const y: E!i32 = { g = 1; };`) check/dump rc=0,
  5 `.c`, no diagnostic (also under `--warn-all`). Zig rejects.

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
`sf/src/lower.zig` (`lowerCompoundAssignRest`);
`sf/src/async_analysis.zig` (`scanFrameLocals`); Task 9i `280a3b12`; Task 9j/9l/9k/9f reports;
`repro/mi_matrix/known_excluded/d15_parity/`,
`repro/mi_matrix/known_excluded/d15_assignment_void/`.

## D17 — Optional array return emits a non-assignable C array assignment (`?[N]T`)

**Status:** OPEN (deferred — documented workaround, no compiler fix authorized).

**Symptom.** A function returning `?[2][]const u8` dumps cleanly (`-ffast
--output-dir` rc=0), but the emitted C does not compile: the optional payload is
copied with a plain C assignment, and C arrays are not assignable.

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

Command (Task 3b-D re-run):
`/tmp/zig3bC_r1/zig1_5_clean -ffast --output-dir /tmp/t3bD/d17/out /tmp/t3bD/d17/main.zig`
→ dump rc=0, then
`sh /tmp/t3bD/d17/out/build_target.sh linux /tmp/t3bD/d17/out/prog`
→ build rc=1:

```text
main_3DF5832C.c:83:17: error: assignment to expression with array type
   83 |     zT_30.value = parts;
main_3DF5832C.c:125:11: error: assignment to expression with array type
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

**Evidence.** Probe: `/tmp/t3bD/d17/main.zig` (repo-external; re-verified
2026-11-17 with `/tmp/zig3bC_r1/zig1_5_clean`). Task report:
`.superpowers/sdd/2026-11-12-undersanded-m01-std-audit-plan/task-2-report.md`.
Fix commit: `22cfbfe6 feat(std): str splitOnce`.

**Note.** Doc-only entry. Any compiler fix (structural optional-array
return/unwrap emission) is separately authorized and out of scope here.

---

## D18 — Indexed write to a nested array field targets a struct temporary

**Status:** OPEN (deferred — documented workaround, no compiler fix authorized).

**Symptom.** A write of the form `outer.inner.arr[i] = v` dumps cleanly
(`-ffast --output-dir` rc=0), links, and runs — but the store is lost. The emitted C
copies `outer.inner` by value into a local temporary and writes that
temporary's array, so the original object is unchanged. There is no gcc
diagnostic; this is a silent **dump-time** miscompile.

**Minimal repro (Zig source shape).**

```zig
const io = @import("std_io");

const Exp = struct { hold: [4]i32, hold_n: i32 };
const State = struct { exp: Exp };

fn reset(s: *State) void {
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        s.exp.hold[i] = 0;
    }
    s.exp.hold_n = 0;
}

pub fn main() void {
    var s: State = State{ .exp = Exp{ .hold = [4]i32{ 1, 2, 3, 4 }, .hold_n = 4 } };
    reset(&s);
    io.printInt(s.exp.hold[0]); // prints 1, expected 0
    io.write(" ");
    io.printInt(s.exp.hold_n);  // prints 0 (this write is emitted correctly)
    io.write("\n");
}
```

Command (Task 3b-D re-run):
`/tmp/zig3bC_r1/zig1_5_clean -ffast --output-dir /tmp/t3bD/d18/out /tmp/t3bD/d18/main.zig`
→ dump rc=0.
`sh /tmp/t3bD/d18/out/build_target.sh linux /tmp/t3bD/d18/out/prog`
→ build rc=0. Run → `1 0` (expected `0 0`), run rc=0.

**Exact emitted C** (`main_*.c`, the `reset` function):

```text
    zT_8 = s->exp;
    zT_9 = (int*)zT_8.hold;
    zT_9[i] = zT_7;
```

`zT_8` is a by-value `Exp` temporary; the indexed store lands in the
temporary. The following `hold_n` write is emitted correctly as
`zT_15 = &s->exp; zT_15->hold_n = ...`.

**Classification.** Emitted-C nested aggregate lvalue lowering: an indexed
element store through a nested struct field uses a by-value inner-struct
temporary instead of addressing the original lvalue. Not a C compile error;
the failure is wrong behavior from valid Zig at dump time.

**Scope / impact.** Found in `game.startFight` while zeroing
`s.exp.hold[i]` field-wise; any indexed write into an array nested under a
struct field has the same shape. No `sf/src` surface is affected.

**Workaround.** Initialize the whole nested struct with a fully initialized
struct literal (`s.exp = def.Expedition{ ..., .hold = [def.MAX_PARTS]i32{
... }, ... }`) instead of per-element writes. Shipped in
`examples/z98/undersanded/game.zig` (`startFight`).

**Evidence.** Probe: `/tmp/t3bD/d18/main.zig` (repo-external; re-verified
2026-11-17 with `/tmp/zig3bC_r1/zig1_5_clean`). Dump/build both rc=0; runtime
output `1 0` vs expected `0 0`; emitted C lines above. Task report:
`.superpowers/sdd/2026-11-12-undersanded-m02-fight-core-plan/task-3-report.md`.

**Note.** Doc-only entry. Any compiler fix (base-lvalue addressing for indexed
writes into nested arrays) is separately authorized and out of scope here.

---

## D19 — Module/type values rejected in value positions (parity gap, deferred)

**Status:** OPEN (parity gap, deferred — no compiler fix authorized).

**Symptom.** Z98 rejects module values in all measured positions, including the
legal binding `const a = h.sub;`, while it silently accepts some type values in
value positions (`_ = i32;`). Zig 0.17.1 accepts module bindings and rejects
both module and type values in value positions with `expected value, found
type`.

**Measured table (Task 3b-D, 2026-11-17).** Binary
`/tmp/zig3bC_r1/zig1_5_clean` (md5 `0f72ce60ae90f426696b47a6826a3061`); each
shape in its own `/tmp/t3bD/d19/` probe with `helper.zig` containing
`pub const sub = @import("sub.zig");` and `sub.zig` containing
`pub const x: i32 = 1;`.

| Shape | `--check` rc | dump rc | `.c` | Diagnostics |
|---|---|---|---|---|
| `const a = h.sub;` | 0 | 2 | 0 | `error[3042] non-value base expression in field access` + `warning[3023] module used as value expression` |
| `_ = h.sub;` | 0 | 2 | 0 | same pair |
| `_ = &h.sub;` | 0 | 3 | 0 | `warning[3023] module used as value expression` + `error[3043] internal: unsupported address-of l-value (node 6)` |
| `_ = i32;` | 0 | 0 | 5 | none — silently accepted |
| `const g = h.sub; _ = g.nope;` | 0 | 2 | 0 | two `error[3042]` + `warning[3023]` |

The address-of row differs from the earlier controller table (which expected
the 3042/3023 pair): the current compiler emits `error[3043]` and exits 3.
The `error[3043] internal: unsupported address-of l-value (node 6)` failure is
a **separate internal-error defect**, not part of the module/type parity gap;
it is recorded under D19 for the address-of module shape without consuming a
new ID (the next free slot remains **D24**).

**Representability.** `typeRegistryGetOrCreateModule(module_id)` exists in
`sf/src/type_registry.zig` and creates a `module_type`, so module values are
representable; the gap is in expression/sema value-position handling, not the
type system.

**Zig oracle.** 0.17.1 (recorded in D16 / Task 9j; archive
`sha256 3581863e…`, binary `sha256 58959f01…`): `const a = h.sub;` is legal;
value positions reject with `expected value, found type`.

**Workaround.** Do not bind a module or type to a variable; reference members
through the module path (`h.sub.x`) or import the module directly. Doc-only
entry; any parity fix is separately authorized.

---

## D20 — Sema error cascades only partially suppressed

**Status:** OPEN (partial fix; residual cascades).

Task 3b-C (`f9886640 fix(sema): suppress dependent diagnostics after a level-0
error`) added `semaInitializerReportedError` (`sf/src/semantic_analyzer.zig`)
and the read-only mark query `diagnosticCollectorNodeWasMarked`
(`sf/src/diagnostics.zig`). The `decl_type == TYPE_VOID` check skips
`error[3000] cannot declare variable of type void` only when the initializer
subtree carries a `diagnosticCollectorMarkNodeOnce` mark from a level-0
diagnostic. The walk uses kind-guarded `child_0`/`child_1` and extras, with a
depth limit of 8.

**Fixed scope (verified).** `/tmp/t3bD/d20/simple.zig`:
`const p = &h.nope;` with `h = @import("helper.zig")` and no `nope` member →
`--check -ffast` rc=2, 0 `.c`, single `error[3060]` (`no field or member
function named 'nope' in module`); no `error[3000]`. The mark on the
`field_access` node suppresses the dependent void-declaration cascade.

**Remaining verified cases.**

- Depth > 8: `/tmp/t3bD/d20/deep9.zig`
  (`const p = &(((((((((h.nope)))))))));`) → rc=2, 0 `.c`, `error[3000]` plus
  `error[3060]`. The mark is deeper than the 8-node walk.
- Genuine void initializer is not over-suppressed:
  `/tmp/t3bD/d20/genuine_void.zig` (`_ = h.nope; const x = h.vf();`) → rc=2,
  `error[3060]` + `error[3000]` (non-vacuity preserved).
- Other `TYPE_VOID`-returning rejects were not audited by Task 3b-C and are not
  claimed fixed.

**Workaround.** Avoid deriving a declaration from a missing-member expression;
fix the member name. Doc-only entry; no further compiler fix authorized here.

---

## D21 — Current-source 0.15.2 references are stale (vs 0.17.1)

**Status:** OPEN (documentation debt).

The recorded parity oracle is **Zig 0.17.1** (D16 / Task 9j; archive
`sha256 3581863e…` in
`repro/mi_matrix/known_excluded/d15_parity/results/compilers.txt`; binary
`sha256 58959f01…` in
`repro/mi_matrix/known_excluded/d15_assignment_void/results/compilers.txt`, also
`repro/mi_matrix/known_excluded/d15_31_diff/compilers.txt`). Current source
comments/docs still contain **0.15.2** references, mostly describing behavior
rather than naming the oracle.

**Measured (Task 3b-D, 2026-11-17).**
`grep -rn '0\.15\.2' sf/src sf/docs/tech_docs docs/reference docs/sf | wc -l`
→ **131** occurrences (an earlier count of 95 is stale): `sf/src` 54,
`sf/docs/tech_docs` 34, `docs/reference` 26, `docs/sf` 17. The same
`grep -rn '0\.17\.1'` over those paths → 0.

**Impact.** Comments such as those in `sf/src/type_resolver.zig` and
`sf/src/c89_emit.zig` describe behavior as "Zig 0.15.2", which no longer names
the oracle used by the parity probes. No runtime behavior depends on the label.

**Policy.** Treat Zig 0.17.1 as authoritative for parity evidence. Do not bulk
rewrite comments/docs here: this task is doc-only for this ledger. Historical
`docs/superpowers/plans|specs` and `repro/` stay frozen.

**Workaround.** Cite the 0.17.1 oracle hashes for parity claims; treat 0.15.2
strings in current-source comments as stale metadata pending a separate
cleanup.

## D22 — OpenWatcom bare/cdecl function-pointer types are not cdecl

**Status:** OPEN (deferred, doc-only).
**Backend:** OpenWatcom 1.9 (Win32).

A bare function-pointer type (no explicit calling convention) is not treated as
cdecl on OpenWatcom, so indirect calls through such a pointer use the wrong
convention. The z9gb workaround shipped in `1cb44c39`: machine-code entry
points and helpers use `extern "stdcall"`, `Z98_STDCALL`-qualified
function-pointer typedefs, and callee-clean glue (`ret 4`). The general
bare/cdecl case remains unfixed; any parity fix is separately authorized.

---

## D23 — MinGW GCC 3.4.2 traps incompatible Win32 function-pointer casts

**Status:** OPEN (emitted-C UB; direct-call workaround proved).

**Backend:** MinGW GCC 3.4.2 (mingw-special), Win32, Pentium 4 / Win98.

**Root cause.** The emitted C calls Win32 imports through a cast to a
mismatched function-pointer type:

```c
zT_47 = ((zT_04A29DB2_FS_void__unsigned_c)CreateFileA)(...);
zT_24 = ((zT_4E5CC50D_FS_int_void__unsign)ReadFile)(...);
zT_24 = ((zT_4E5CC50D_FS_int_void__unsign)WriteFile)(...);
zT_38 = ((zT_4D39C164_FS_int_unsigned_cha)MoveFileA)(...);
```

GCC warns `function called through a non-compatible type`. GCC 3.4.2
replaces the call with `int $5`; the call disappears. Modern GCC warns but
still emits the call. `CloseHandle` is already emitted as a direct
`call _CloseHandle@4` and never traps. This is UB in the emitted C, not a
control-flow or block-layout problem.

**Evidence.**

- All 20 control-flow shapes (while/do/for/goto/if-else/switch/out-param/
  helper/separate TU) still had 8 `int $5` and no
  `CreateFileA`/`ReadFile`/`WriteFile`.
- Bool-lift shape 21 and bool+goto shape 23: 8 `int $5`, no calls.
- Direct-call shape 22: 4 `int $5`; `CreateFileA`, `ReadFile`, `WriteFile`,
  `MoveFileA` each present as direct `call _CreateFileA@28`,
  `_ReadFile@20`, `_WriteFile@20`, `_MoveFileA@8`.
- The remaining four traps are `exists` (`GetFileAttributesA`), `remove`
  (`DeleteFileA`), `openDir` (`FindFirstFileA`), `readDir`
  (`FindNextFileA`) — outside z9gb's open/read/write/seek/size path.
- `-mno-stack-arg-probe`, `-fno-bounds-check`, O0/O1/O2/Os, and every
  control-flow shape did not help.
- Object-name collisions were ruled out: the final shape matrix used
  distinct files and explicit `-o`; all still trapped except shape 22.
- The `function called through a non-compatible type` warnings are present
  on the P4 build.

**Why.** `std_file_pal.zig` declares these imports `extern "stdcall"`;
`std_file.zig` calls `pal.CreateFileA` etc. The emitter chooses a generic
function-pointer typedef and emits the cast form. When the cast's prototype
is not the real stdcall prototype, GCC 3.4.2 treats the call as invalid and
emits the trap.

**Fix.** Emit direct extern calls for these imports (the path already used
for `CloseHandle`), or cast to the exact compatible stdcall prototype. Do
not chase control-flow shapes. The root `std_file_428B49AE.c` is now the
direct-call shape-22 source (MD5 `4bb81fd8d991772e6539f5c3f59166e8`), and
`build_mingw_full.bat` builds `prog.exe` for the P4.

**Why an emitter fix works, and what it should look like.** The cast is
deliberate: `emitCalleeExpr` (`sf/src/c89_emit.zig:2054`) wraps a stdcall
extern in the `FS_...` fn-pointer typedef to force the ABI when the C compiler
may not have a prototype; `emitFnPtrType` (`:1810`) builds that typedef from
the Z98 types. The bug is that those Z98 types are not the Win32 C types:
`u32` → `unsigned int` vs `DWORD` = `unsigned long`; `[*]const u8` →
`unsigned char*` vs `LPCSTR` = `const char*`; `[*]u8` → `unsigned char*` vs
`LPVOID` = `void*`; `*u32` → `unsigned int*` vs `LPDWORD` =
`unsigned long*`; `*void` vs `LPSECURITY_ATTRIBUTES`/`OVERLAPPED` struct
pointers. `CloseHandle` survives because `void*`/`i32` exactly match
`HANDLE`/`BOOL`; that is the proof.

The C backend does not need to know the prototype; it needs to know whether
the C compiler will see the header declaration. It already has that signal:
`moduleClosureHasCIncludes` (`c89_emit.zig:2240`) is used by
`emitExternDeclFor` (`:2206`) to decide whether to emit an extern declaration.
The fix should reuse a **precise** version of that signal at the call site:

1. Thread the call-site module id into `emitCalleeExpr`.
2. If the module closure includes the platform prelude/Windows header that
   declares the symbol, emit `name(args)` directly; the header's `WINAPI`
   stdcall prototype is authoritative for the C call.
3. Otherwise keep `((FS_x)name)(args)`; this preserves the stdcall ABI for
   header-less externs.
4. Do not use “has any `@cInclude`” blindly: a module can include `<stdio.h>`
   without `<windows.h>`. Restrict the direct-call path to the platform
   prelude/Windows include, or add a per-extern flag that says the header
   provides the prototype.
5. The Z98 extern declaration remains the source of truth for other backends;
   `@cInclude` is a C-backend hint, not a language dependency.

This fixes every Win32 import whose header is visible, including `std_os`,
DirectDraw/DirectSound/DirectInput. It avoids modeling every C struct pointer
in Z98 and keeps the C-specific decision in the C backend.

**Option 3 is complementary, not a substitute.** Z98 has `c_char` → `char`
(`type_registry.zig:546`; `*const c_char` → `char*`, `:594`) but no
`c_ulong`/`c_long`/`c_ushort`/`c_uint`/`c_int`/`c_void`. Adding scalar aliases
improves `DWORD`/`LPCSTR`/`LPDWORD` fidelity, but `LPSECURITY_ATTRIBUTES`,
`LPOVERLAPPED`, COM/DirectX struct pointers still need exact C type names;
`void*` is not compatible with a struct pointer. Matching those in Z98 would
need opaque structs with exact C typedef names or a `c_type("...")` escape
hatch — more C-specific, not more backend-neutral. Option 3 alone cannot make
the cast types match the headers.

**Fix validation.** Add a focused emitter test: a stdcall extern declared by
an `@cInclude`d platform header emits a direct call; the same extern without
the header still emits the cast. Then regenerate and run the full battery:
dump pins, compiler/std tests, all example gates, OWC and modern GCC, then the
P4 GCC 3.4.2 build (`build_mingw_full.bat`). The shape-22 C is the current
diagnostic/workaround, not the shipping fix.

**Scope.** The other P4 object-scan counts (`std_os` 10, `std_dsound_pal` 9,
`std_ddraw_pal` 8, `cache` 3, `std_time` 2, `std_dinput_pal` 2, `std_io` 1,
`input_config` 1, `emu` 1) include other indirect casts. z9gb's headless
open/read/write path is clean with the direct `std_file`; the full windowed
showcase still needs the global emitter fix, or the same direct-call edit in
those modules.

**Not this defect.** Block dropping after `return`, stack probe, bounds
check, optimization level, and basename collisions were all tested and ruled
out.

---

## D24 — Untyped nested array literal of structs is zero-filled as int (invalid C / silent drop)

**Status:** OPEN (deferred — documented workaround, no compiler fix authorized).

**Symptom.** A struct field of array-of-struct type initialised with an untyped
nested array literal (`.cost = .{ slot(...), ... }`) dumps cleanly
(`-ffast --output-dir` rc=0) but the emitted C does not materialise the rows:
the module initializer builds a tuple temporary, discards it
(`(void)zT_1.cost;`), then zero-fills the field with a scalar
(`zT_1.cost[_j] = 0;`). For struct elements that is invalid C
(`incompatible types when assigning to type 'CostSlot' from type 'int'`); for
an element type that accepts scalar `0`, the same zero-fill would compile and
silently drop the rows (that variant was not separately probed).

**Minimal repro (Zig source shape).**

```zig
const CostSlot = struct { kind: i32, amt: i32 };
const ToolRow = struct { id: i32, cost: [3]CostSlot };

fn slot(kind: i32, amt: i32) CostSlot {
    return CostSlot{ .kind = kind, .amt = amt };
}
const NONE_SLOT = CostSlot{ .kind = 0, .amt = 0 };

pub const TOOLS = [_]ToolRow{
    .{ .id = 1, .cost = .{ slot(2, 3), NONE_SLOT, NONE_SLOT } }, // untyped: broken
};
pub const TOOLS_TYPED = [_]ToolRow{
    .{ .id = 1, .cost = [3]CostSlot{ slot(2, 3), NONE_SLOT, NONE_SLOT } }, // control
};
```

Command:
`/tmp/seed151_build/zig1_5_clean -ffast --output-dir /tmp/d24_probe/out /tmp/d24_probe/main.zig`
→ dump rc=0; then
`sh /tmp/d24_probe/out/build_target.sh linux /tmp/d24_probe/out/prog`
→ build rc=1:

```text
main_3DF5832C.c: In function 'zF_780653D2___module_init':
main_3DF5832C.c:127:25: error: incompatible types when assigning to type 'zT_5F22A424_CostSlot' from type 'int'
  127 |         zT_1.cost[_j] = 0;
```

plus `warning: variable 'zT_00790750_Tup_564 zT_4' set but not used` for the
discarded tuple. The explicit-type control emits an array temporary and a byte
copy instead (`zT_19` / `memcpy`-style loop) and compiles.

**Classification.** Lowering of an untyped nested array literal whose elements
come from helper calls / named constants (the observed trigger) produces a
tuple expression plus a scalar zero-fill of the array field, instead of
materialising the array. With an explicit element type the same values lower
correctly. Observed on seed v151 (md5 `a2fc81055dc1cb7a67099fe3934d22ee`),
found during Undersanded M5 Task 0 while authoring `tables_t1.zig`.

**Scope / impact.** No `sf/src` table uses untyped nested array literals, so
the shipped std surface is unaffected. In-repo workaround is effective: every
table row array carries an explicit element type
(`examples/z98/undersanded/tables_t1.zig:182+`, e.g. `[3]CostSlot{...}`), and
the content/tier gates keep it pinned. Any program using the untyped form gets
invalid C (struct elements) or silently zeroed rows (scalar elements).

**Workaround.** Annotate the nested literal: `[N]T{ ... }` (the shipped tables
form).

**Evidence.** Probe `/tmp/d24_probe/main.zig` (repo-external; re-verified
2026-11-19 with seed v151). Generated `out/main_3DF5832C.c` module-init region
shows the discarded tuple and `zT_1.cost[_j] = 0;`. Discovery record:
`/tmp/undersanded-m5-ledger-final.md:50` (ruling R14).

**Note.** Doc-only. Emitting the tuple copy for untyped nested literals (or
rejecting the form with a diagnostic) is separately authorized.

---

## D25 — Returning a fixed-size array emits a C function returning an array

**Status:** OPEN (deferred — documented workaround, no compiler fix authorized).

**Symptom.** A function with return type `[N]T` dumps cleanly
(`-ffast --output-dir` rc=0) but the emitted C is invalid: the prototype is a
C function returning an array type, and the call site assigns to an array.
gcc rejects both.

**Minimal repro (Zig source shape).**

```zig
const MaterialAmt = struct { kind: i32, amt: i32 };

fn costRow() [3]MaterialAmt {
    var out: [3]MaterialAmt = [3]MaterialAmt{
        .{ .kind = 1, .amt = 2 },
        .{ .kind = 3, .amt = 4 },
        .{ .kind = 5, .amt = 6 },
    };
    return out;
}

pub fn main() void {
    var row: [3]MaterialAmt = costRow();
    ...
}
```

Command: seed v151
`-ffast --output-dir /tmp/d25_probe/out /tmp/d25_probe/main.zig` → dump rc=0;
then `sh /tmp/d25_probe/out/build_target.sh linux /tmp/d25_probe/out/prog`
→ build rc=1:

```text
main_3DF5832C.h:10:33: error: 'zF_EAC2F6BC_costRow' declared as function returning an array
main_3DF5832C.c:3:33: error: 'zF_EAC2F6BC_costRow' declared as function returning an array
main_3DF5832C.c:55:12: warning: returning 'zT_7974CA2A_MaterialAmt *' from a function with return type 'int' makes integer from pointer without a cast
main_3DF5832C.c:73:10: error: assignment to expression with array type
   73 |     zT_1 = zF_EAC2F6BC_costRow();
```

**Classification.** C cannot return or assign arrays by value, so an
array-typed return must be lowered structurally (out-param, hidden result
pointer, or copy into a caller slot). The emitter instead uses the array
typedef as the C function's return type, making both the prototype and the
call site invalid. Same C-level root as D17 (`?[N]T` optional payload copy) but
a distinct surface: D17 covers optional-array unwrapping; this covers a plain
fixed-array return and call-site assignment.

**Scope / impact.** No `sf/src` function returns a fixed array, so the shipped
std surface is unaffected. Found while adding `economy.upgradeCost`
(Undersanded M5 Task 1). Shipped workaround is
`upgradeCost(axis, tier, out: *[3]MaterialAmt) void`
(`examples/z98/undersanded/economy.zig:62`) with every call site and test on
the out-param form. D17 already blocks the optional variant.

**Workaround.** Return via out-param (`*[N]T`) or a struct wrapper; shipped
out-param.

**Evidence.** Probe `/tmp/d25_probe/main.zig` (repo-external; re-verified
2026-11-19 with seed v151). Generated `out/main_3DF5832C.h` / `.c` lines above.
Discovery record: `/tmp/undersanded-m5-ledger-final.md:51` (ruling R15).

**Note.** Doc-only. Structural array-return emission (or a reject diagnostic)
is separately authorized; a D17 fix, if taken, should cover both surfaces.

---

## D26 — Cross-module function alias (`pub const f = sub.f`) emits invalid C with an empty function typedef

**Status:** Open — confirmed 2026-11-20 (seed v151).

**Symptom.** A module-level const bound to a function imported from another
module type-checks and dumps, but the generated C declares an empty function
typedef and an invalid const initializer, so the C build fails. Value and
array aliases are unaffected; only function values hit this.

**Minimal repro.**
```zig
// sub/sub.zig
pub fn ping() void {}

// alias.zig
const sub = @import("sub/sub.zig");
pub const ping_alias = sub.ping;
pub fn main() void { ping_alias(); }
```
```sh
/tmp/seed151_build/zig1_5_clean -ffast --output-dir o_alias alias.zig   # rc 0
sh o_alias/build_target.sh linux o_alias/alias                        # rc 1
```

Emitted C:
```c
/* zig_special_types.h:19-21 — guard emitted, typedef BODY missing */
#ifndef ZIG_FNPTR_zT_9EF551F0_FN_void
#define ZIG_FNPTR_zT_9EF551F0_FN_void
#endif

/* alias_<hash>.h:12 */
extern zT_9EF551F0_FN_void const zG_D44F5D4E_ping_alias;

/* alias_<hash>.c:2 */
zT_9EF551F0_FN_void const zG_D44F5D4E_ping_alias = (zT_9EF551F0_FN_void)zF_165DF089_ping;
```
gcc (first errors): `expected ';' before 'const'`, `type defaults to 'int'`,
then `expected ',' or ';' before 'zF_165DF089_ping'` at the cast.

**Classification.** const-init function values (`c89_emit.zig` `CIE_FN`, around
`:2903`) are typed as the by-value `fn_type`; the fn-pointer typedef body is
not emitted (only its `ZIG_FNPTR_…` guard), and the emitted cast uses that
non-existent function type instead of a function-pointer type. The declaration
also puts `const` after an invalid type spelling. Pre-existing D17/D19/D25
surfaces are different (optional arrays, module/type values, array returns).

**Scope / impact.** Compile-time only, no runtime risk. Blocks clean module
aliasing; workaround is trivial but forces boilerplate.

**Workaround (shipped).** Forwarding wrapper functions
(`pub fn f(a) R { return sub.f(a); }`). Undersanded M9 hubs use them
(`fight.zig:21-98`, `data.zig:30-121`, `persist.zig:42-85`,
`render_term.zig:37-65`); values/arrays still alias directly
(`creatures_t1.zig:13-39`).

**Evidence.** Probes `/tmp/m9def/{sub/sub.zig,alias.zig}` and generated C
under `/tmp/m9def/o_alias/`; discovery in
`.superpowers/sdd/2026-11-12-undersanded-m09-pixel-tier-plan/task-9-report.md:36-39`.

---

## D27 — `[ROW_MAX]T` array-length const workaround (closed: not reproduced)

**Status:** Closed — not a compiler defect (2026-11-20, seed v151).

**Reported symptom.** The kv scanner allegedly had to use literal `[80]`
instead of `[ROW_MAX]` in `parseRowKV`'s parameter and local
(`data_scan.zig:77/:81`) because `[ROW_MAX]RowField` "generated errors".

**Re-check.** Replaced both sites with `[ROW_MAX]`; `data_test` compiled
`-fsafe -W -osl` rc 0, and the generated C was correct:
`zT_F02D80A2_Arr_zT_4C1EEE25_Row*` (pointer to the array typedef). Minimal
probes also compile cleanly: same-module `[N]T` param/local, cross-module
`[m.N]T`, and array value copy/assignment (`a: [N]T = src; dst = a;`), each
dump rc 0 + build rc 0.

**Conclusion.** No compiler defect found; the `[80]` literals are unnecessary
(source of the "magic 80" smell) and can be replaced with `ROW_MAX` as
cleanup. If the original failing form reappears, record the exact snippet and
gcc diagnostic before opening a numbered defect.

**Evidence.** `/tmp/m9def/{arr_same.zig,arr_cross.zig,arr_copy.zig}` and
`/tmp/m9def/o_rowmax/` (compiled with the two `[ROW_MAX]` edits applied to a
temporary checkout, then reverted).