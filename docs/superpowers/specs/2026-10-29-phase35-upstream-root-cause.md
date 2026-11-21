# Phase 3.5 — Upstream Root-Cause Investigation (Task 0.5)

**Status:** investigation-only; no source fix, no Task 1/Task 7 work.
**Base:** `d3a5a934` on `zig1_improvements`.
**Compiler under test:** `/workspace/znineeight/zig1/zig1_5_clean`
(md5 `cd8d283b917749009961f4445043666b`) — not rebuilt or modified.
**Evidence base:** `docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`
§1–§9; Task 0/0.1/0.2 reports; `examples/torrent_example_defects.md`; the
Phase 3.5 design. Five confirming runs were made for this task (D12, D7.3,
D14-tail, D5, local-untyped-array control); they are recorded in §11.

This report maps each defect to the **first pass where state becomes wrong**,
not the first place the symptom is visible. A “fix contract” binds the fixing
task: it may change the code only in a way that makes the contract true, and it
must run the listed probes before editing.

## 0. Root-cause matrix

| Defect | Repro path | Symptom class | First incorrect pass/layer |
|---|---|---|---|
| **D3** | `repro/mi_matrix/known_excluded/lazy_import_fold_ok/`, `lazy_import_unparsable_dead_ok/` | frontend reject (`error[3048]` / parser `error[2000]`) | parser import resolution (parse-time eager load) |
| **D4** | `tests/analyzers/d4_contract_probe.zig` (+ `--check`) | post-sema analyzer diagnostics (false pos/neg) | analyzer passes (`sf/src/analyzer.zig`) |
| **D5** | `known_excluded/stdcall_def_ok/`, `known_excluded/cdecl_def_ok/` | emitted-C/gcc (`'cb'`/`'cd'` undeclared; no definition) | lowering records `is_extern=1` for a body-carrying decl |
| **D7.3** | `known_excluded/nested_agg_write_ok/` | runtime lost store (+ one sibling ICE) | lowering of slice-expression bases / assignment l-values |
| **D8** | `known_excluded/stdout_order_ok/` | runtime output order (latent; passes by luck pre-fix) | emitter builtin lowering (`fwrite`/`putchar`/`getchar`) |
| **D10** | `known_excluded/stdcall_def_ok/` | same as D5 (cannot define a stdcall function) | same `is_extern` conflation as D5 |
| **D12** | `repro/mi_matrix/module_untyped_array_init_ok_xmod/` | emitted-C/gcc (`assignment to expression with array type`) | module-scope sema leaves the initializer typed as a tuple |
| **D13** | `repro/mi_matrix/enum_u64_max_ok_xmod/` | frontend reject (`error[3000]` range limitation) | enum member storage/eval is `i64` |
| **D14** | `known_excluded/d14_tail_http2_wrapper_ok/`, `d14_original_http2_eu/`, `d14_two_level_matrix/` | emitted-C/gcc tail step ABI; **no** reproducible `error[3043]` | lowering turns a suspending tail call into `.tail_call`; async machine does not await it; `copyTailCall` corrupts the callee name id |

Shared-cause note: **D5 and D10 are one upstream cause** (the `is_extern` flag
conflates “extern declaration” with “definition”), which matches the plan’s
joint Task 5. That is the only cross-defect sharing found; it is called out in
§10 rather than treated as an ambiguity, because the plan already scopes D5 and
D10 together.

---

## 1. D3 — lazy `@import`

### Repro and exact symptom
- `repro/mi_matrix/known_excluded/lazy_import_fold_ok/main.zig`:
  `const impl = if (1 == 1) @import("exists.zig") else @import("missing.zig");`
  Pre-fix `zig1` rc=2, `error[3048]: could not resolve imported file 'missing.zig'`.
- `repro/mi_matrix/known_excluded/lazy_import_unparsable_dead_ok/main.zig`:
  the dead arm is an existing but unparsable file; pre-fix rc=2 with
  `unparsable.zig:2:15 error[2000] ...` plus `unexpected token`.
- Siblings `sibling_switch.zig`, `sibling_and_or.zig`, `sibling_nested.zig`,
  `sibling_live_arm.zig` reproduce the eager-open class (inventory ADJ-8/ADJ-9).

### First incorrect pass/layer and exact lines
- Parse-time fold: `sf/src/parser.zig:166` `parserFoldComptimeBool` handles only
  bool literals, parens, `!`, `and`, `or`, `@isWindows()` and parse-time
  same-module bool consts; it returns `null` for a comparison such as
  `1 == 1` (`cmp_eq`, `sf/src/ast.zig:47`) at `sf/src/parser.zig:227`.
- Because the fold returns `null`, `dead_import_depth` stays 0 and
  `parserParseImportExpr` eagerly resolves the dead arm:
  `sf/src/parser.zig:877-885`.
- That call reaches `moduleRegistryResolveImport`
  (`sf/src/module_registry.zig:365`), which resolves the path
  (`:376-383`, emitting `error[3048]` when it cannot) and enqueues the module
  (`:400-423`). The queue is read/parsed in
  `sf/src/import_resolver.zig:67-99` (file read at `:81`, parse at `:92`), which
  is why the unparsable dead-arm file is opened and parsed.

### Causal chain
`if (1 == 1) … else @import("missing")` → `parserFoldComptimeBool(cmp_eq)`
returns `null` → `dead_import_depth == 0` → `parserParseImportExpr` calls
`moduleRegistryResolveImport` at parse time → the dead module is registered,
queued, opened and parsed → `error[3048]` (missing) or parser errors
(unparsable). The semantic evaluator later knows the condition is dead, but the
file has already been opened.

### Downstream sites that would be patches (not root)
- Add more cases to `parserFoldComptimeBool` (e.g. equality/arithmetic consts):
  still a probe ⊊ evaluator, so another comptime-known shape would keep the bug;
  the defects doc explicitly rejects this as the full fix.
- Special-case a missing/unparsable file in `import_resolver.zig`: hides the
  over-load only for those two error paths; a live import could be mis-typed.
- Suppress `error[3048]` after the fact: loses the diagnostic for genuinely live
  imports.

### Upstream cause
**One cause:** `@import` resolution is performed during parsing, gated by a
conservative parse-time fold, instead of being deferred until after comptime
evaluation selects the live arm. The parse probe is an approximation, not the
language semantics.

### Fix contract
- **Must become true:** for any comptime-known condition (the evaluator’s fold
  class, including comparisons/arith/consts/`@isWindows`/switch prongs), an
  untaken arm’s `@import` is never registered, queued, opened or parsed. A live
  arm resolves exactly as today. Wrong-module selection must remain impossible.
- **Must not change:** live-arm selection and the established
  `@isWindows()` conditional-import idiom (`conditional_import_if_xmod`,
  `conditional_import_switch_xmod`, `conditional_import_lazy_xmod`,
  `iswindows_deadarm_*`); interner id order (the F1 gate: any early intern can
  flip `stdlib_crypto_modpow_xmod` OK→GREEN; see
  `parser.zig:196-201` and design §5.3); frozen-1124 md5.
- **Proof probes:** `lazy_import_fold_ok` and
  `lazy_import_unparsable_dead_ok` rc=0 with the expected stdout; the four D3
  siblings; `conditional_import_*` and `iswindows_deadarm_*`;
  `stdlib_crypto_modpow_xmod` stays OK; open-count/`strace` evidence that the
  dead file is not opened.

---

## 2. D4 — static-analyzer cluster (per analyzer)

### Repro and exact symptom
`tests/analyzers/d4_contract_probe.zig` (source fixture). The committed harness
`testFixture` has no generic/CLI entry; each fixture needs a hard-coded call in
`sf/src/tests/test_analyzer_bin.zig:main()` (`:1794-1859`), so Task 0 captured
the real-pipeline result with `--check` (inventory ADJ-20/ADJ-22):

```text
rc=2
2× warning[3037] potential null pointer dereference      (false positives: unseeded params)
warning[3039] freeing untracked pointer 'q'             (false negative: alias chain)
error[3035] double free of pointer 'p'                  (false positive: comptime-dead arm)
error[3030] returning address of local variable 'x'     (true positive: must stay)
```

### 2.1 Lifetime / Provenance
- **First incorrect state:** `classifyProvenance` asks the symbol table first;
  `sf/src/analyzer.zig:89` (`symbolTableLookup`). Only module-root names are
  registered (`sf/src/symbol_registrator.zig:470-502` iterates module-root
  decls), so locals/params/captures always miss. The T5 workaround uses the
  analyzer-internal state map (`analyzer.zig:100-111`, params seeded at
  `:1243-1266`), but the symbol-table path is structurally dead.
- **Second cause (dead-arm parity):** `analyzerFoldComptimeBool`
  (`analyzer.zig:1040-1071`) is a separate conservative bool-literal probe, and
  the `switch` walk (`analyzer.zig:1125-1142`) does not fold prongs at all. An
  evaluator-foldable dead arm (`if (1 == 0)`) is still analyzed.
- **Downstream patches:** suppress WARN_6010/WARN_6002 at specific sites, or
  special-case the probe; these do not make provenance truthful for locals.
- **Upstream cause:** provenance has no real local/param binding source
  (symbol_registrator is module-only), plus no shared comptime-fold parity.
- **Fix contract:** either register locals/params/captures in the front-end
  scope map consumed by the analyzer, or formally replace the dead symbol-table
  lookup with the analyzer-internal substrate; plumb the shared
  `comptime_folds`/evaluator fold into `AnalyzerContext` and gate `switch`
  prongs. `return &local` true positive must stay; capture tests
  (`tests/analyzers/capture_lifetime.zig`) must stay green.

### 2.2 NullPointer
- **First incorrect state:**
  - `visitStatement` handles `return_stmt` (`analyzer.zig:1149-1158`) but never
    calls `analyzeExpr` on the return expression, so `return p.*` is unchecked.
  - `handleNullVarDecl` (`analyzer.zig:916-926`) classifies the initializer to
    seed a binding’s state but does not walk the initializer, so a deref in
    `var q = p.*` is unchecked.
  - `runNullAnalyzer` (`analyzer.zig:1235-1241`) does not seed parameters
    (unlike `runLifetimeAnalyzer:1243-1266`). Unknown identifiers fall through
    `classifyExpr` to `maybe` (`analyzer.zig:849-853`), so every `param.*`
    warns → the measured 44 false `WARN_6002` on self-source.
- **Downstream patches:** suppress WARN_6002 for parameters by name, or lower
  the diagnostic level; this leaves the un-walked return/init paths and the
  false-negative holes.
- **Upstream cause:** incomplete NullPointer walk/seed coverage.
- **Fix contract:** walk return expressions and `var` initializers through
  `analyzeExpr`; seed pointer-like parameters (non-optional `*T`/`[*]T`/`[]T`
  as safe/non-null, optional as maybe); keep `p.*` on a null/`maybe` value
  reported and keep `if (p) |q|` refinement. No new false positives on corpus.

### 2.3 DoubleFree
- **First incorrect state:** `handleAllocAssign`
  (`analyzer.zig:441-471`) sets the destination to `allocated` only when the
  RHS is an alloc call, to `untracked` for `null`, and to `unknown` for
  everything else (`:470`). An alias assignment/initializer `var q = p;` never
  inherits `p`’s `AllocState`, so the capture binding
  (`bindCaptureState:1009-1031`) sees no state and `free(q)` warns
  “untracked”; cross-name frees are not checked.
- **Downstream patches:** special-case free-through-capture, or silence
  WARN_6006 for untracked names; both leave the alias state wrong.
- **Upstream cause:** ownership state is name-keyed and assignment does not
  propagate alias/allocation state.
- **Fix contract:** propagate the source binding’s allocation state on plain
  assignment and `var` initializer for identifier RHS (and an alias set for
  cross-name frees), while retaining allocation/free/leak/transfer diagnostics
  and the true `free(p); free(p)` double free.

### 2.4 Signature
- **Current state:** the `?Aggregate` / `E!Aggregate` fn-pointer returns,
  arbitrary-width ints, and nested incompletes are validated by
  `analyzeSignature` / `validateSignatureType` (`analyzer.zig:562-577`,
  `:679-727`); T5’s revivals stand. The probe’s Signature surface is expected
  clean.
- **Remaining items are test/doc, not analyzer logic:**
  - (e) vacuous hand-fed-symbol unit tests (`sf/src/tests/test_analyzer_bin.zig`
    `Symbol{...}` records) exercise a path the real pipeline never takes for
    locals/params;
  - (g) most hand-fed `Symbol{...}` initializers omit `file_id`
    (e.g. `:545`, `:571`, `:640`; `:1511` has it) — zig1 zero-fills, zig0
    would reject;
  - (f) docs residue in `docs/design/static_analyzers.md` and
    `docs/sf/STATIC_ANALYZERS_p2.md` §5.3.
- **Fix contract:** fixture-driven tests replace hand-fed symbols; Signature
  must stay clean on the probe surface; no emission change (analyzers are
  post-sema).
- **Proof probes:** `d4_contract_probe.zig` (once the harness is extended),
  `tests/analyzers/**`, the self-source `WARN_6002` count (44-class must
  collapse, not move).

---

## 3. D5 + D10 — `extern fn` body silently dropped; no stdcall definition

### Repro and exact symptom
- `repro/mi_matrix/known_excluded/stdcall_def_ok/main.zig`:
  `pub extern "stdcall" fn cb(x: u32) i32 { … }`; dump rc=0, zero Z98
  diagnostics, emitted C has the call `((FS_int_unsigned_int)cb)(…)` but **no
  definition and no prototype for `cb`**; gcc rc=1 `'cb' undeclared`.
- `repro/mi_matrix/known_excluded/cdecl_def_ok/main.zig`:
  `pub extern fn cd(x: u32) i32 { … }`; dump rc=0, no definition; link rc=1
  `undefined reference to 'cd'`.
- Siblings: `sibling_fnptr.zig` (fn-pointer call also references the undefined
  symbol), `sibling_mismatch.zig` (prototype/definition convention mismatch is
  silently treated as a declaration), `sibling_variadic.zig` (variadic stdcall
  must keep rejecting `error[3012]`).

### First incorrect pass/layer and exact lines
- Parser keeps the body and the convention:
  `parserParseExternDecl` parses `"stdcall"` (`sf/src/parser.zig:1777-1796`) and
  passes the convention to `parserParseFnDecl`; the body is parsed regardless of
  `is_extern` (`parser.zig:1863-1871`) and the convention is stored on the
  `FnProto` (`parser.zig:1880`).
- Lowering then sets
  `func_ptr.is_extern = (node.flags & 0x04) != 0`
  (`sf/src/lower.zig:15006`) before lowering the body (`:15065-15069`). It never
  distinguishes a declaration (no body) from a definition (body present).
- The emitter treats every `is_extern` function as declaration-only:
  forward declarations are skipped at `sf/src/c89_emit.zig:2604` and
  `:3171`, and the definition body is gated at `:3203`
  (`if (func.is_extern == 0) { … emitFunctionSignature/emitFunctionBody … }`).
  Call sites use the original unmangled name (`c89_emit.zig:8417`), so the
  call references a symbol that was never defined.
- The convention itself is already plumbed end-to-end:
  `func_ptr.call_conv = proto.call_conv` (`lower.zig:15010`),
  `emitCallConv` (`c89_emit.zig:2009-2018`) is called from
  `emitFunctionSignature` (`:2118`). Therefore D10 needs no new
  convention-annotation mechanism; it fails only because the definition is not
  emitted.

### Causal chain
`extern "stdcall" fn cb(…) { body }` → parser stores body + `call_conv` →
lowering lowers the body but stamps `is_extern=1` from the `extern` flag →
emitter skips both forward declaration and definition for `is_extern` →
emitted C references `cb`/`cd` with no definition → gcc “undeclared” or link
“undefined reference”.

### Downstream sites that would be patches (not root)
- Emit a prototype for the extern symbol: fixes “undeclared” but not the body /
  the requested definition (and would still be undefined at link).
- Emit the body under a separate mangled name: the call site and any callback
  registration still reference the external name → still undefined.
- Drop `Z98_STDCALL`: makes the call build but silently breaks the
  callee-cleanup ABI (the exact z9play M6 bug).
- Special-case `stdcall` only: leaves bare/`"c"` extern definitions broken
  (D5) and vice versa.

### Upstream cause
**One shared cause for D5 and D10:** `is_extern` is overloaded to mean both
“external declaration” and “name linkage”, so an extern declaration that
carries a body is emitted as a declaration with the body discarded. The
convention is already available on the LIR/emitter, so D10’s “no per-function
convention annotation” wording in the defects doc is stale; D10 is not a second
independent cause.

### Fix contract
- **Must become true:** an `extern fn … { … }` / `extern "c" fn … { … }` is a
  real C definition (original symbol name), and `extern "stdcall" fn … { … }`
  emits `Z98_STDCALL` on the definition. An `extern fn …;` with no body remains
  a declaration (no definition, no body). Sema must verify that a definition and
  its prototype agree on convention (ADJ-11).
- **Must not change:** extern declarations without bodies; existing
  `callconv_*`/`*_stdcall_*` fixtures; fn-pointer type ABI; variadic stdcall
  rejection `error[3012]`; `callconv(...)` stays rejected; declaration-only C
  emission stays byte-identical.
- **Proof probes:** `stdcall_def_ok` and `cdecl_def_ok` rc=0, gcc-clean and run
  with expected stdout; `sibling_variadic` still rejects; `sibling_mismatch`
  rejects at sema; `sibling_fnptr` builds; existing `callconv_*` fixtures
  unchanged. Windows ABI: i686-w64-mingw32-gcc + objdump shows the
  callee-cleanup epilogue (`ret $N`) and a Wine C-host callback invocation
  balances the stack and returns correctly.

---

## 4. D7.3 — nested aggregate write targets a by-value temporary

### Repro and exact symptom
- `repro/mi_matrix/known_excluded/nested_agg_write_ok/main.zig`:
  `fill(peers[1].field[0..])` and `fill(peers[0].field[2..])`; the program
  compiles/links/runs rc=0 but prints `0 0 0 0` (pre-write values) instead of
  `77 88 77 88`, under both `-ffast` and `-fsafe`.
- Sibling `sibling_nested_chain.zig` (`outers[i].mids[j].inner.bytes[0..]`)
  prints `0 0` — same lost store.
- Sibling `sibling_field_array_assign.zig` (`arr[i].field = srcArray`) emits an
  illegal C array assignment (the D12 emission class on a nested lvalue).
- Sibling `sibling_slice_of_array.zig` (`arr[i].field[0..] = src[0..]`) dump
  rc=3, `error[3043]: internal: unsupported assignment l-value (node 38)`.
- Control `sibling_pointer_aggregate.zig` (`var pp: *Peer = &peers[0]`) prints
  `7 8` and must keep working.

### First incorrect pass/layer and exact lines
- Slice base: `lowerExprSlice` lowers the base as an **rvalue** at
  `sf/src/lower.zig:12527` (`var se_base = lowerExpr(self, node.child_0);`).
  For `peers[1].field`, `lowerExprIndex` →
  `lowerIndexAccessRest` emits `load_index` (`lower.zig:6507`) which
  materialises the whole struct element by value; the following field access
  loads `.field` from that copy (`lowerFieldAccessRest:6408/6416`). The slice
  then takes a pointer into the temporary (`lower.zig:12554-12561`
  ptr-cast of the array temp), so the callee writes into the temp.
- Confirming emission (`/tmp/d73_dump`, §11):
  `zT_3 = zG_…_peers[zT_2]; … zT_4 = (unsigned char*)zT_3.field; … fill(zT_0);`.
- Assignment sibling: `lowerAssignLValue` has arms for ident/index/field/deref/
  paren but not `slice_expr`; it falls to
  `iceAssignLValueUnsupported` (`lower.zig:6664-6665`, helper `:5698`), producing
  the `error[3043]` ICE.

### Causal chain
`fill(peers[1].field[0..])` → slice lowering evaluates `peers[1].field` as a
value tree → index access copies `peers[1]` into a temp → field load/slice
point into the temp → callee writes the temp → real `peers[1]` never changes →
read-backs print pre-write values. For the direct slice assignment, there is no
slice l-value arm at all, so lowering ICEs instead of composing `&peers[i].field`.

### Downstream sites that would be patches (not root)
- Patch the emitter to elide the `load_index`/`load_field` copy for aggregate
  reads: value-context reads legitimately need a value and other callers rely on
  it; changing it is broad and risks D12-adjacent breakage.
- Patch `emitCall`/`fill` to detect slice arguments into temps: cannot recover
  the storage address after the copy.
- Special-case `[0..]` slices: misses `[2..]`, nested chains and direct
  assignments.

### Upstream cause
**Primary cause:** slice expressions are treated as value trees; the base is
not composed as an l-value address when it is an array l-value chain
(`index`/`field`/`deref`/`paren`). The existing `lowerLValueAddr`
(`lower.zig:5878`) and the nested-store address logic already have the needed
composition. **Second independent cause:** `lowerAssignLValue` has no
`slice_expr` l-value arm, so the direct `arr[i].field[0..] = src[0..]` form ICEs.
Both are in the same lvalue-composition family but are separate code paths;
Task 2 must decide whether the direct form is in scope (inventory ADJ-3 says it
is in-scope under D7.3).

### Fix contract
- **Must become true:** a slice taken from an array field of an indexed/field
  l-value chain points at real storage, so callee writes land in the aggregate;
  a slice-expression assignment composes the same storage address (or is
  rejected with a clean diagnostic, not an ICE, if deliberately out of scope).
- **Must not change:** value-read semantics; simple `s.f = v`, `a[i] = v`,
  typed slice writes, and nested stores that already work must re-emit
  byte-identically; the pointer-to-aggregate workaround must keep working.
- **Proof probes:** `nested_agg_write_ok` prints `77 88 77 88`; 
  `sibling_pointer_aggregate` prints `7 8`; `sibling_nested_chain` prints the
  written values; `sibling_field_array_assign` and `sibling_slice_of_array`
  build (or reject cleanly, per Task 2’s scoping decision); working-shape
  emitted C diff is empty.

---

## 5. D8 — stdout split across C stdio and the PAL

### Repro and exact symptom
`repro/mi_matrix/known_excluded/stdout_order_ok/main.zig` interleaves
`std.io.print("A\n")` (PAL), `@stdoutWrite("B\n", 2)` and `@putChar` (C stdio),
then `@getChar` and echoes `D` + the read byte. Pre-fix it **passes by luck**
on CRT (`-ffast`/`-fsafe`) and no-CRT/Wine: `A\nB\nC\nDZ\n`. The defect is
latent: buffered `fwrite` is flushed at normal exit after the unbuffered PAL
write; on a trap or different flush timing the order can invert and buffered
data can be lost. This fixture is a regression oracle; its value is the
post-fix proof on **both** paths (inventory ADJ-7).

### First incorrect pass/layer and exact lines
- `sf/src/c89_emit.zig:8896-8922` lowers `.builtin_put_char` → `putchar`,
  `.builtin_stdout_write`/`.builtin_stderr_write` → `emitFwriteCall`
  (`:6933-6953`, `fwrite(…, stdout|stderr)`), `.builtin_get_char` → `getchar`.
- `moduleHasStdioBuiltin` (`c89_emit.zig:2458-2488`) and
  `emitBuiltinIncludes` (`:2547`, stdio include at `:2548-2550`) inject
  `#include <stdio.h>` whenever one of those builtins appears.
- By contrast `std_fmt.zig:23/29` calls `pal_print_stdout`; the two stacks are
  chosen at compile time by which lowering path the source uses, not by any
  runtime policy. The comments in `std_io.zig:63` / `std_debug.zig:3`
  (“no cstdio”) mean “no direct `@cInclude`”, not “no C stdio”.

### Causal chain
`@stdoutWrite`/`@putChar`/`@getChar` → LIR builtin → emitter emits C stdio
(buffered) while `std.fmt`/`std.io.print` emit PAL (unbuffered) → mixed program
order depends on buffering/flush timing → reorder/loss window on the same
stream. The split originates in the emitter’s builtin lowering, not in
`std_fmt` or the PAL.

### Downstream sites that would be patches (not root)
- Flush `stdout` before each PAL write or at exit only: leaves two stacks and
  still loses data on abnormal exit; doesn’t remove the C runtime dependency.
- Make the PAL buffered: changes all PAL users and still leaves two buffers.
- Reorder only the fixture’s writes: hides the class.

### Upstream cause
**One cause:** the stdout/stderr/getchar builtins are lowered to C stdio while
the rest of the formatted-output family uses the PAL. (This is independent of
file I/O, which is already PAL.)

### Fix contract
- **Must become true:** `@stdoutWrite`, `@stderrWrite`, `@putChar`, `@getChar`
  lower to PAL entry points (PAL print + PAL putchar/getchar); the stdout family
  is one unbuffered OS-native stack; program order is preserved on CRT **and**
  no-CRT; buffered C-stdio data cannot be lost on a trap.
- **Must not change:** `std.io.print`/`std.fmt` output, file I/O (already PAL),
  existing program outputs, and warning cleanliness. Support files must be
  generated through `sf/src/emit_support.zig`
  (`scripts/check_emit_support.sh` 8/8).
- **Proof probes:** `stdout_order_ok` byte-exact under gcc CRT and
  `scripts/win32_cross/cross_nocrt.sh` (Wine); stdlib/examples outputs
  unchanged; `gate_warn_clean.sh` GREEN; `check_emit_support.sh` 8/8.

---

## 6. D12 — module-scope untyped array literal

### Repro and exact symptom
`repro/mi_matrix/module_untyped_array_init_ok_xmod/main.zig`:
`pub var arr: [3]u32 = .{ 1, 2, 3 };` plus a mutation/print. `zig1` dump rc=0;
the emitted `__module_init` is:

```c
zT_127FDF6B_Tup_554 zT_0;
zT_0._0 = zT_1; zT_0._1 = zT_2; zT_0._2 = zT_3;
zG_296F1018_arr = zT_0;        /* array = tuple: gcc rejects */
```

gcc rc=1 `error: assignment to expression with array type`. Siblings
`sibling_struct_array_untyped.zig` (1-D struct array) and
`sibling_2d_untyped.zig` (2-D untyped literal) are the same class (ADJ-1/2).

### First incorrect pass/layer and exact lines
- `semanticAnalyzerResolveTupleLiteral` (`sf/src/semantic_analyzer.zig:7207`)
  ignores the expected-type stack and always builds a `tuple_type` from the
  elements (`:7297-7302`); the expected type is pushed by
  `semanticAnalyzerResolveModuleVarDecl` at `:7440`.
- Unlike the function-local `var` path, the module path never applies the
  declared type to the initializer when no coercion was recorded. Local path:
  `sf/src/semantic_analyzer.zig:6681-6685`
  (`if (coercionTableGet(init) == null) resolvedTypeTableSet(init, decl_type)`).
  `semanticAnalyzerResolveModuleVarDecl` (`:7432-7525`) has no equivalent step.
- Lowering therefore sees a tuple-typed literal: `lowerTupleLiteralStep`
  (`sf/src/lower.zig:4601-4618`) materialises a `Tup_*` temp (the array branch
  at `:4605-4611` is only taken when the node’s resolved type is an array).
- `store_global` in the emitter chooses the copy form from the **value temp’s**
  type, not the global’s declared type (`sf/src/c89_emit.zig:7723-7758`):
  a tuple value is not an array, so it emits `name = value;` (`:7750-7757`)
  instead of the element-wise copy used for members (`:7741-7749`).

### Causal chain
`pub var arr: [3]u32 = .{1,2,3}` → module sema resolves `.{}` to a tuple
(expected type ignored, and the local-only resolved-type override is missing) →
lowering emits a tuple temp → `store_global` sees a non-array value type and
emits a whole aggregate assignment → gcc rejects array-to-tuple assignment.
The typed form `[3]u32{…}` is an `array_init` whose resolved type is the array,
so it takes the element-wise path and works.

### Downstream sites that would be patches (not root)
- Patch the emitter `store_global` to look up the global’s declared type and
  field-copy from a tuple temp: fixes this literal shape, but the value still
  has the wrong type (breaks nested arrays, coercions, and any consumer of the
  temp), and the module initializer would still disagree with sema.
- Special-case `.{}` in `lowerModuleInit` by mutating the AST/literal form:
  duplicates the typed-literal path and misses the struct-array/2-D siblings.
- Suppress the gcc error or emit a byte copy of a tuple layout: relies on tuple
  and array C layouts matching and still types the value wrong.

### Upstream cause
**One cause:** the module-scope initializer does not receive the declared type
as its resolved type (the local `var` path’s typing rule is missing at module
scope), so a `.{}` stays a tuple. The fixture’s emitted `Tup_554` is the
evidence that sema, not the emitter, first chose the wrong type.

### Fix contract
- **Must become true:** when a module-scope binding’s declared type is an array
  and its initializer is `.{}`/`array_init`, the initializer is typed as that
  array (or an equivalent typed coercion is recorded and applied), so lowering
  uses the existing element-wise array path and `store_global` copies elements.
- **Must not change:** the typed array-literal path
  (`multiarray_literal_init_xmod`) must re-emit byte-identically; real tuple
  literals (no array expected type) stay tuples; struct-array and 2-D untyped
  siblings must also build; existing aggregate emission for working shapes.
- **Proof probes:** `module_untyped_array_init_ok_xmod` builds, runs, prints
  `1 42 3`; `sibling_struct_array_untyped`, `sibling_2d_untyped`;
  `multiarray_literal_init_xmod` C diff empty.

> **Plan note for Task 1:** the plan lists `sf/src/lower.zig`; the root is the
> module-scope sema typing asymmetry. Mirroring the local rule at
> `semantic_analyzer.zig:6681-6685` (or applying the declared type in
> `lowerModuleInit` before `lowerExpr`) both satisfy the contract; patching
> `c89_emit.zig` would be a symptom patch. Verify the chosen site against this
> contract before editing.

---

## 7. D13 — full `enum(u64)` discriminant range

### Repro and exact symptom
`repro/mi_matrix/enum_u64_max_ok_xmod/main.zig`:
`const E = enum(u64) { A = 18446744073709551615 };` plus a switch/print.
Pre-fix dump rc=2, **two** level-0 diagnostics:

```text
error[3000]: enum member value exceeds the supported enum value range
  (values above 9223372036854775807 require u64 enum storage, not supported yet)
```

Siblings: `sibling_signed.zig` passes (`enum(i64) { A = -1, B = 2 }`);
`sibling_implicit_ok.zig` (`A = u64_max-1, B` implicit) rejects pre-fix;
`sibling_duplicate.zig` already rejects `error[3055]` at max; 
`sibling_const_switch.zig` rejects like the base (ADJ-13/14/15/16).

### First incorrect pass/layer and exact lines
- Storage: `EnumMember = struct { name_id: u32, value: i64 }`
  (`sf/src/type_registry.zig:108`).
- Fold: `evalConstI64Full` (`sf/src/type_resolver.zig:1405-1409`) accepts a
  64-bit unsigned value (`comptimeIntFits64`), then stores the low 64 bits
  **bit-cast to i64** (`:1408`); `0xFFFFFFFFFFFFFFFF` becomes `-1`.
- Shared member walk: `enumMembersResolve` uses `i64` `mval`/`auto_val`
  (`type_resolver.zig:1476-1547`), calls `evalConstI64Full` at `:1486`, and
  writes the i64 slot at `:1525-1530`; the successor is guarded at `i64` max
  (`:1542-1547`).
- Validators treat the wrapped negative value as either a genuine negative or
  the documented limitation: `validateLocalEnumBackingFit`
  (`type_resolver.zig:1761`, `:1787`) and
  `semanticAnalyzerGateEnumTypeDecl` (`semantic_analyzer.zig:2418`, `:2458`);
  the storage-max successor guard is at `:2449`.

### Causal chain
Legal `enum(u64)` max literal → `evalConstI64Full` bit-casts the u64 value into
the i64 `em_items[].value` slot (`-1`) → the unsigned backing validator sees a
negative value / the successor guard sees i64 max → explicit `error[3000]`
range limitation, no `.c`. The representation, not the literal spelling or the
validators’ arithmetic, is the first wrong state.

### Downstream sites that would be patches (not root)
- Relax `validateLocalEnumBackingFit` / the sema gate to accept the negative
  wrapped value: would accept but store/emit the wrong discriminant.
- Special-case `18446744073709551615` or the max literal: misses computed
  values, implicit successors and const-init consumers.
- Widen only the emitter constant: the member is already rejected before
  emission.

### Upstream cause
**One cause:** enum discriminants are represented and folded as `i64` in the
registry and the shared member walk, so the full unsigned 64-bit range cannot
be carried through duplicate detection, implicit successors, backing-fit
validation, const-init/lowering or emission.

### Fix contract
- **Must become true:** the full `u64` range is preserved end-to-end
  (representation, shared walk, duplicate detection, implicit-successor logic,
  backing-fit checks, const-init/lowering consumers, and the C u64 constant
  form); `18446744073709551615` is accepted, read and emitted exactly; an
  implicit successor beyond `u64` max rejects cleanly (no wrap).
- **Must not change:** signed/negative enums, `enum(i64)`/`enum(u63)` values,
  duplicate-tag `error[3055]`, and emitted C for values at/below i64 max
  (byte-identical where the representation does not change).
- **Proof probes:** `enum_u64_max_ok_xmod` (prints `7`), `sibling_implicit_ok`
  (accepts `u64_max-1, B`), `sibling_signed` (prints `1`),
  `sibling_duplicate` (`error[3055]`), `sibling_const_switch`, plus
  `enum_i64_max_ok_xmod`, `enum_i64_max_implicit_reject_xmod`,
  `enum_u63_max_ok_xmod`, `enum_u63_max_implicit_reject_xmod`; C gcc-clean in
  both modes.

---

## 8. D14 — tail-return EU wrapper step ABI

### Repro and exact symptom
- Exact-shape tail: `known_excluded/d14_tail_http2_wrapper_ok/main.zig`
  (`fn wrapperTail(c,id) Http2Error!u32 { return wait2(c, id); }`). Dump rc=0,
  C emitted, gcc rc=1 under both modes:
  `incompatible types when assigning to type 'zT_3B6EA323_EU_01' from type 'int'`
  and `incompatible types when returning type '…EU_01' but '…Opt_82' was expected`.
- Exact original imported two-level shape
  `known_excluded/d14_original_http2_eu/main.zig` and local
  `d14_two_level_matrix/main.zig`: same EU/Opt RED at the outer tail.
- Nested tail/tail `sibling_tail_tail.zig` / `local_tail_tail.zig`: the EU/Opt
  set per tail level **plus** a wrong tail callee
  (`too many arguments to function 'zF_…_main'`, `void value not ignored`).
- Older `sibling_tail.zig` (`error{Boom}`) shows the name corruption directly:
  `stray '@'`, `zF_B6CE39A7_@asyncSuspend`.
- Non-tail exact shape `repro/mi_matrix/async_wrapper_eu_payload_ok_xmod/main.zig`
  already compiles and prints `42 0\n0 1\n` in both modes; all 15 non-tail
  matrix shapes pass (Task 0.1/0.2). **Zero frontend `error[3043]` occurred in
  38 runs.**

### First incorrect pass/layer and exact lines
1. **Lowering turns a suspending tail call into `.tail_call`.**
   `lowerStmtLeafReturn`’s generic tail-call optimization
   (`sf/src/lower.zig:14098-14108`) fires when
   `ci.return_type == self.func.return_type`; it replaces the `call_direct`
   with a `.tail_call` and marks the block terminated.
2. **The async machine only rewrites `.call_direct` awaits.**
   `instSuspendKind` (`sf/src/async_state_machine.zig:163-173`) returns a
   suspension kind only for `.call_direct` to a suspending callee; `.tail_call`
   falls through. The await rewrite at `:1223` (and `emitAwait` at `:438`) never
   runs, so no child-frame init/drive and no parent-result delivery happen.
   `remapInst` copies the raw `.tail_call` (`:356`).
3. **`copyTailCall` corrupts the callee name id.**
   `sf/src/async_state_machine.zig:317-323` does
   `tc.callee = tc.callee + b.base;` — but `tc.callee` is an interned **name
   id**, not a temp index. Adding the temp base lands on another interned name
   (`id`, `main`, `@asyncSuspend` in the observed outputs), so the step calls the
   wrong symbol.
4. **Result typing:** lowering already retypes the return temp to the function
   return type (`lower.zig:14063-14070`, `self.func.return_type` = the EU), but
   the step’s declared ABI return is `Opt_*` (`async_state_machine.zig:952`, and
   the terminal `set_optional_null` return at `:1282-1285`). Because the await
   path is bypassed, the raw tail-call emits `return <EU>;` from a step that
   must return `Opt_*`.

Confirming emission (`/tmp/d14_tail_dump`, §11):

```c
/* __Z98Step_wrapperTail */
zT_3B6EA323_EU_01 zT_6 = {0};
zT_6 = zF_37386AE0_id(zT_4, zT_5);   /* wrong callee; int -> EU */
return zT_6;                          /* step returns Opt_82 */
```

There is no `wait2` step drive (`emitAwait`) in this step at all.

### Causal chain
`return wait2(c, id)` (a suspending callee) → generic TCO rewrites the
`call_direct` to `.tail_call` → async transform does not recognize `.tail_call`
as an await → no child frame / parent-result slot / result delivery;
`copyTailCall` also adds the temp base to the callee **name id**, so the emitted
call names an unrelated symbol → gcc sees an ordinary call assigning `int` to
an `EU` value and a step that `return`s `EU` where `Opt` is required. Non-tail
`try wait(c); return id;` keeps the `call_direct`, so the async rewrite runs and
the shape works — hence the tail-vs-non-tail split.

### Downstream sites that would be patches (not root)
- Patch only `copyTailCall` (drop the `+ b.base`): removes the wrong-callee
  error, but the step still never drives the child / awaits; the raw call to an
  async callee has no ordinary definition and the ABI is still wrong.
- Cast `EU`↔`Opt` in the emitter: hides the result mismatch without an await,
  produces a synchronous call to a function that has no synchronous definition.
- Special-case `wrapperTail`/`http2Wait`: does not fix nested tail/tail or any
  other EU-returning tail wrapper.
- Retype only the step result: does not restore the child-frame drive or the
  parent-result slot.

### Upstream cause
**Two independent causes under the tail-return ABI:**
1. The generic tail-call optimization applies to a **suspending** callee and
   destroys the `call_direct` representation that the async transform requires
   (`lower.zig:14098-14108` vs `async_state_machine.zig:163-173`).
2. `copyTailCall` rebases the callee **name id** as if it were a temp
   (`async_state_machine.zig:317-323`), corrupting the emitted tail callee for
   any tail call inside an async frame; Task 7 must add a synchronous-tail
   probe for this latent path.

Fixing (1) removes the current tail-RED because every RED callee is
transitively suspending; (2) is required latent correctness for synchronous
tail calls inside async frames. The plan's fix contract still requires both.

### Fix contract
- **Must become true:** a tail return of a suspending call is lowered as the
  same implicit await as the non-tail form (child-frame init + drive + result
  delivery into the caller’s return/parent-result path), and the step ABI
  returns `Opt` with the EU payload/error delivered through the result slot.
  `copyTailCall` must preserve callee name ids (and all non-temp fields) while
  rebasing only real temp indices. The nested tail/tail wrong-callee symptom
  disappears.
- **Must not change:** the step ABI for all suspending functions; non-tail,
  two-value-order, mixed void/value, `try`, `catch`, `if` shapes;
  `recvSomeAsync`, `http2Wait`, `mud_server`, z9torr async fixtures; frame
  sizes where possible; the `std_http2` public API (`id_out` remains valid).
- **Proof probes:** `d14_tail_http2_wrapper_ok` builds/runs `42 0\n0 1\n`;
  `d14_original_http2_eu/main.zig` and `sibling_tail_tail.zig` build;
  `d14_two_level_matrix/main.zig` and `local_tail_tail.zig` build/run;
  `sibling_wait_tail.zig` builds; all 15 non-tail matrix shapes stay green;
  existing async stdlib fixtures stay green in both modes. Add a probe for a
  genuine synchronous tail call inside an async function to pin the
  `copyTailCall` name-id fix.

### 8.1 The `[suspicious]` `error[3043]` frontend claim (separate)
The original D14 report claimed the non-tail `Http2Error!u32` wrapper hit
`error[3043]`/“async parent_result slot type mismatch”
(`sf/src/async_state_machine.zig:447-454`, the fail-closed kind-7 slot check).
Task 0.1/0.2 could not reproduce it: the exact original two-level shape and 19
variants emitted C with rc=0 and **zero** frontend `error[3043]` in 38 runs.
The check itself is an assertion, not a cause: it would fire only if P2/P3
(`async_analysis.scanImplicitAwaits`/reservation) and P4 (`emitAwait` slot
consumption) disagreed in order/type, and no evidence of that exists.

**Status:** `[suspicious]`/unreproduced. Do **not** “fix” it by guessing, and do
not treat it as a second D14 bug. If a future report produces the exact frontend
message, the investigation starts at the P2/P3 reservation
(`sf/src/async_analysis.zig:431-530`, kind-7 slots) versus the P4 per-await gate
(`async_state_machine.zig:447-454`), not at the emitter.

---

## 9. Root-cause gate summary (for Tasks 1–9)

| Task | Defect | Verified upstream cause to check first |
|---|---|---|
| 1 | D12 | module-scope sema does not type the initializer as the declared array (missing counterpart of `semantic_analyzer.zig:6681-6685`), not the emitter |
| 2 | D7.3 | slice base lowered as rvalue (`lower.zig:12527`) + no `slice_expr` l-value arm (`:6664`) |
| 3 | D8 | emitter builtin lowering to C stdio (`c89_emit.zig:8896-8922`), not `std_fmt`/PAL |
| 4 | D3 | parse-time eager import at `parser.zig:877-885`; the fold probe (`:166-228`) is only its gate |
| 5 | D5/D10 | `is_extern` conflation at `lower.zig:15006` + emitter definition gate (`c89_emit.zig:3203`), not a missing convention mechanism |
| 6 | D13 | i64 `EnumMember.value` + i64 fold (`type_registry.zig:108`, `type_resolver.zig:1405-1408`), not the validators |
| 7 | D14 | suspending tail call→`.tail_call` (`lower.zig:14098-14108`) bypassing `instSuspendKind` (`async_state_machine.zig:163-173`) **and** `copyTailCall` name-id rebase (`:317-323`) |
| 8/9 | D4 | per-analyzer causes in §2: module-only symbol registration, incomplete null walk/seed, alias-state propagation gap, dead-arm fold parity, test hygiene |

If a fixing task finds its symptom only downstream of these, it must STOP rather
than patch the symptom.

---

## 10. Concerns / ambiguities for the controller

1. **D5 and D10 share one upstream cause** (`is_extern` conflation). This
   matches the plan’s joint Task 5, so it is recorded as one root cause with two
   defect entries, not a STOP-triggering collision. The defects-doc D10 text
   (“no per-function convention annotation”) is stale: `call_conv` is already
   carried from parser → proto → LIR → emitter (`parser.zig:1880`,
   `lower.zig:15010`, `c89_emit.zig:2009/2118`).
2. **D12’s plan file list points at `lower.zig`**, but the first wrong state is
   the module-scope sema typing asymmetry. The plan permits applying the
   declared type “before lowering”, so a lower-side fix is possible, but Task 1
   must not conclude that `c89_emit.zig` is the fix site.
3. **D14 is explicitly two independent causes** for the tail-return ABI (tail
   call bypass + `copyTailCall` name-id rebase), plus the separate
   `[suspicious]` `error[3043]` claim. Task 7 must fix/verify both and must not
   assume the frontend error exists.
4. **D8 has no current RED**; it is a regression oracle. Its value is the
   post-fix proof on CRT and no-CRT.
5. **D4’s probe is not registered in the harness** (ADJ-20); Task 8/9 own the
   harness expansion. The diagnostics above came from the real-pipeline
   `--check` run, not `testFixture`.
6. No unexpected cross-defect shared cause was found beyond D5/D10.

---

## 11. Confirming runs performed for this task

All runs used `/workspace/znineeight/zig1/zig1_5_clean`
(md5 `cd8d283b917749009961f4445043666b`), sequential, with distinct `/tmp`
CWDs. No compiler/source file was changed.

1. D12: `cd /tmp && zig1 -ffast --dump-c89 -o /tmp/d12_dump
   repro/mi_matrix/module_untyped_array_init_ok_xmod/main.zig` → rc=0; emitted
   `zT_127FDF6B_Tup_554 zT_0; … zG_296F1018_arr = zT_0;`.
2. Local untyped-array control (temporary `/tmp/local_untyped.zig`): emitted
   `zT_959EEC26_Arr_unsigned_int_3 zT_1; … a[_i] = zT_1[_i];` — proves the
   local `var` path applies the declared array type and the module path does
   not.
3. D7.3: `zig1 -ffast --dump-c89 -o /tmp/d73_dump
   repro/mi_matrix/known_excluded/nested_agg_write_ok/main.zig` → rc=0; emitted
   `zT_3 = zG_…_peers[zT_2]; … zT_4 = (unsigned char*)zT_3.field; … fill(zT_0);`.
4. D14 tail: `zig1 -ffast --dump-c89 -o /tmp/d14_tail_dump
   repro/mi_matrix/known_excluded/d14_tail_http2_wrapper_ok/main.zig` → rc=0;
   emitted step `zT_6 = zF_37386AE0_id(zT_4, zT_5); return zT_6;` with no child
   drive.
5. D5: `zig1 -ffast --dump-c89 -o /tmp/stdcall_dump
   repro/mi_matrix/known_excluded/stdcall_def_ok/main.zig` → rc=0; call
   `((zT_65668B00_FS_int_unsigned_int)cb)(…)`; no `cb` definition/prototype in
   the emitted files.

These runs confirm the pass/locus identified from the static reading; they do
not add a new defect or alter the Task 0/0.1/0.2 classifications.
