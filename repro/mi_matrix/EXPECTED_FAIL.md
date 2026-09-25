# mi_matrix corpus — expected-fail manifest (v238 2026-09-25)

## Task 6 — pointer/fn-pointer `{}` and float `{x}` (v237 -> v238, 2026-09-25)

**What.** `{}` on a one-pointer now prints official Zig 0.15.2's actual form
(`Writer.zig:1337-1352`; frozen rows G1/G2/G5, operator ruling R3): the
lowercase-hex address with **NO `0x`** (`i32@7fff8668af48`), or, for a pointee
Zig delegates, the pointee printer: `*struct`/`*union`/`*tagged_union`/`*tuple`/
`*packed_*` → the Task-4 generated aggregate printer with `*(value)` (depth
unchanged by the pointer arm), `*enum` → the Task-5 name printer. The
non-delegating form is emitted inline at the call site —
`std_print("<@typeName(child)>@")` + the EXISTING std.fmt `printHexU64` — and
the child name comes from the new `zigPrintNameAppend` (exact for the
Z98-expressible space: fixed/arb ints, `usize`/`isize`, `c_char`, `bool`,
`f32`/`f64`, `void`/`noreturn`, `error{A,B}` (comma, no space), `?T`, `E!T`,
`[]`/`[]const`, `[N]`, `*`/`[*]` with quals, `fn (p, ...) [callconv(.c)] ret`).
No function was added to `std_fmt.zig`, so the 4-MD5 pins hold. Float `{x}`
prints Zig's `printFloatHex` bit-for-bit (`0x1.8p0`, `0x0.0p0`, `-0x0.0p0`,
denormals, `nan`/`inf`) through compiler-generated static helpers
`z98_printFloatHex32/64`, emitted on demand (`need_fhex32/64`) with the decimal
exponent written by the existing mangled `std.fmt.printI32`. The Task-4 field
closure is extended for pointer / fn-pointer / many-pointer FIELDS (Zig's
`{any}` pointer route — `struct { f: fn() void }` →
`.{ .f = fn () void@addr }`, `[*]i32` field → `i32@addr`, `*?i32` field →
`?i32@addr`), and a pre-existing "typedef used before emitted" type-ordering
defect is fixed for pointer members whose C type IS the pointee typedef (a
`fn_type` value-embedding edge plus `emitTypeDefOnce`/`emitTypeDeps`/
`emitPointeeDep`/`emitDepMember`; the four special-types sub-pass emitters were
factored onto the shared guarded writer, dedup via the pass's `seen` map).

**Fixtures.** Positive `repro/mi_matrix/stdlib_print_ptr_hexfloat_xmod`
(golden 936 B / 19 lines, rc 0, 3x byte-exact). Determinism: every address row
reaches the printer through `@intToPtr` with a fixed integer, so the golden pins
the printer FORMAT (`i32@1234`, `fn (i32, u8) i32@2300`, `error{A,B}@1500`)
without pinning ASLR/link layout; real globals are used only for
pointee-delegation rows (`*S`/`*E`/tagged/untagged/packed), whose output has no
address. The 18 oracle rows are byte-identical to the Zig-0.15.2 twin
`/tmp/t6/oracle/fixture_twin.zig` (931 B / 18 lines); Z98 appends its own `done`
marker. Standalone `repro/print_ptr_hexfloat.z98` (same rows, `cmp` == golden).
The Task-4 reject fixture `print_aggregate_noprinter_reject_xmod` lost its
one-pointer-field and tuple-pointer sites (they are now pinned positive);
census **7 -> 5 x `error[3063]`**, rc 2 / 0 `.c` / 0 x `error[3013]`.

**Gates.** Fixed point hop1 `feeabb7d0c294700c0069a9b705ee59c` != hop2 == hop3
== **`f8a549c1a211e5efe638dbd7de2b20aa`**. **4-MD5 emitted-C UNCHANGED**
(8/8: gol `9e0b708e…` / lisp `dfa69f32…` / json `a4a73461…` / mud `2e92c1f2…`)
— the emitted C of the gate programs is byte-identical, so their recorded
execution hashes (`fcbf7e7c…` / `b3d9f897…` / `8bda3d5a…` / mud
`66c8f0ab…`+`93147d0f…`) are inherited. Corpus `-s0` **1027 = 886 OK / 46
GREEN / 95 FAIL / 0 ICE / 0 CRASH**; join-diff vs the Task-5 final over the
1026 common dirs = exactly the new fixture, **zero other movement**. Stdlib
runtime gate **239 PASS / 0 FAIL** (pin 238 -> 239); example matrix **24/24**;
`check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; seed stays
**v84** (R2-print).

**Bounded residuals (documented, not fixed).**

1. A composite pointee name containing a NAMED struct/enum/union (`*?S`,
   `**S`, `*?E`) rejects `error[3063]`: Zig's `@typeName` container-qualifies
   those (`main.S`) and Z98 has no faithful spelling. A DIRECT pointer to an
   enum still delegates to `.member`; `**i32`/`*?i32`/`*[]const u8`/`*E` all
   print (oracle-verified).
2. A one-pointer-to-array aggregate FIELD rejects `error[3063]` (Zig prints it
   as a slice `{ 1, 2, 3 }` — the array/slice residual); the one-pointer-to-
   array ARGUMENT stays 3013 and `*const [N]u8 {s}`/`{x}` stays 3063 (Q3).
3. Pre-existing float-literal residuals (NOT the `{x}` printer): `5e-324`
   parses as `0.0`, `1e-310` is 1-2 ULP off, and `@bitCast` rejects an
   f64↔u64 pair — so the fixture's denormal row is computed at runtime
   (`1e-308 / 1e10` → `0x0.00000000316a2p-1022`, twin-identical).
4. `*const fn(...)` (the double-pointer spelling, `FP_void*`) keeps its
   pre-existing assignment anomaly; the canonical fn-pointer spelling
   (`fn() void` / `&f`) is what the fixture and frozen row G5 pin.

## Task 5 — enum member names and error-set names (v235 -> v236, 2026-09-25)

**What.** `{}` on an `enum` now prints Zig 0.15.2's `.member` and `{}` on an
`error_set` prints `error.Name` (frozen-table rows B1/F1; explicit enum
`{d}`/`{x}` keep the Task-2 numeric route, explicit error-set specs stay
`error[3013]`). The compiler emits, per printed type, a static name table
(`z98_etab_<tid>` blob + `z98_eoff_`/`z98_elen_` byte offset/length arrays +
`z98_eval_` member values; error sets add `z98_escode_` global codes from
`error_code_registry`) and a `static` printer (`z98_printEnum_<tid>` /
`z98_printErrorSet_<tid>`) that linearly scans the value array and writes the
matching name through the EXISTING std.fmt `printStr` primitive. `std_fmt.zig`
is deliberately untouched: `--dump-c89` carries the reachable std_fmt module C
in full, so adding a function there moves all four pinned 4-MD5 dumps (evidence
in the Task-5 report §1.4); the §4 `printEnumName`/`printErrorName` names are
realized as the generated helpers. A new `print_val.implicit` bit distinguishes
a bare `{}` from an explicit `{d}`/`{x}`; `printFmtAggFieldKindOk` and the
emitter (`emitAggValue`/`emitAggPrinterRec`/`collectPrintRoots`) are extended
for NON-packed enum/error-set fields. Fallbacks: an enum value with no member
prints Zig's non-exhaustive form `@enumFromInt(<n>)`; an out-of-set error code
prints the defined `error.UnknownError` (Zig panics on an unknown code in safe
modes).

**Fixtures.** Positive `repro/mi_matrix/stdlib_print_enum_errset_xmod` (golden
304 B / 16 lines, rc 0, 3x byte-exact; the 15 oracle rows are byte-identical to
the Zig-0.15.2 twin `/tmp/t5/oracle/fixture_twin.zig` — 299 B / 15 lines — and
Z98 appends its own `done` marker line): top-level/parameter/module-const/direct
enum `{}`, the `{d}`/`{x}` numeric controls, non-contiguous member values
(`enum(u8){red=3,green=9,blue=12}`), a wide `enum(u64)` member above u32 max
via `@intToEnum`, two error sets, enum/error-set fields in a struct, a nested
struct, a tagged-union payload and a tuple element, and an untagged-union
`{ ... }` control. Standalone `repro/print_enum_errset.z98` (same rows).
The Task-4 reject fixture `print_aggregate_noprinter_reject_xmod` lost its
enum-field site (census 8 -> 7 x `error[3063]`, rc=2, 0 `.c`, 0 x `error[3013]`;
the aggregate-with-enum-field shape is now pinned positive).

**Gates.** Self-compile moving point hop1 `b5a6fcd1…` != hop2 == hop3 ==
**`6c3d33b5c640e817220e11a2823163dd`**; **4-MD5 emitted-C UNCHANGED** (8/8:
gol `9e0b708e…` / lisp `dfa69f32…` / json `a4a73461…` / mud `2e92c1f2…`) with
runtime identity proven by execution (gol `fcbf7e7c…`, lisp `b3d9f897…`, json
`8bda3d5a…`, mud server `66c8f0ab…` + client `93147d0f…`, all rc 0); corpus
`-s0` **1026 = 885 OK / 46 GREEN / 95 FAIL / 0 ICE / 0 CRASH** (join-diff vs
the Task-4 fix-round final over the 1025 common dirs = exactly the new fixture,
zero other movement); stdlib runtime gate **238 PASS / 0 FAIL** (pin
237 -> 238); example matrix **24/24**; `check_emit_support.sh` 7/7;
`verify_upgraded.sh` CLOSEOUT OK; seed stays **v84** (R2-print).

**Bounded residuals (documented, not fixed).**

1. A PACKED struct's enum/error-set field rejects the aggregate argument with
   `error[3063]` (the Task-4 packed-VALUE C model; the packed-field admission
   gate also has a pre-existing multi-enum type-resolution defect — e.g. two
   enums declared before the packed struct make the gate resolve the wrong
   field type — which this task deliberately does not expose through print).
2. An enum member literal whose value exceeds u32 max truncates **at the
   literal** in Z98 (`enum(u64){ big = 5000000001 }` -> `.big` is
   `@enumFromInt(705032705)`): sema stores literal values in a
   `U32ToU32Map` (`semantic_analyzer.zig` `enum_value_table`,
   `@intCast(u32, member.value)`); the runtime value and the Task-5 name lookup
   are exact (the `@intToEnum(EW, 5000000001)` path prints `.big` correctly).
   Pre-existing defect, distinct root cause, outside Task 5's sites.
3. A bare `error.X` print argument with no expected type resolves to void and
   rejects `error[3063]` — **operator ruling R10, a DOCUMENTED DIVERGENCE, not
   parity.** Official Zig 0.15.2 accepts the shape
   (`std.debug.print("e={}\n", .{error.A})` -> `e=error.A`, rc 0; re-verified
   2026-09-25, `/tmp/t5/oracle/errlit.out`), so Z98's reject is an
   operator-ruled bounded residual in the same class as the Q3 list.

**Fix round 1 (R10 + Minors 2/3, 2026-09-25; commit
`docs(print): record the bare-error-literal residual and fix the enum fallback
text`).** (R10) The three false-parity claims (here, the fixture header and
QUICK_REF) were corrected and the exception recorded in spec §6; the reject is
kept. (Minor 2) `emitNamePrinterDef`'s error-set fallback now emits
`std_print("error.UnknownError")`, matching its documentation (was
`std_print("UnknownError")`; unreachable for valid programs). (Minor 3) the
golden-vs-twin claim is now "15 oracle rows byte-identical + Z98-only `done`
marker". Re-verified with the rebuilt compiler: bare error literal rc 2 / 1 ×
`error[3063]` / 0 `.c`; fixture golden byte-unchanged (304 B, rc 0); out-of-range
enum fallback `@enumFromInt(7)`; **4-MD5 emitted-C UNCHANGED** (8/8). The code
edit moved the fixed point (recorded in the Task-5 report fix-round section).

## Task 4 fix round 1 — tuple globals + nested-packed reject (v234 -> v235, 2026-09-25)

**Critical 1 (module-level inferred tuple var/const emitted uncompilable C).**
`front_resolution.zig`'s module-var repeat loop re-resolves every global
initializer; `semanticAnalyzerResolveTupleLiteral` created a FRESH tuple type per
pass (`typeRegistryGetOrCreateTuple` never dedupes), so the global symbol kept
pass 1's `Tup_N` while lowering used a later `Tup_M` and `__module_init` emitted a
cross-type struct assignment (`var g = .{ 11, 22 };` + `{}` -> gcc `incompatible
types when assigning to type 'zT_…_Tup_327' from type 'zT_…_Tup_328'`; same for
`const`, and with no print at all). Fix
(`sf/src/semantic_analyzer.zig`): tuple-literal resolution is now **idempotent per
node** — it returns the type already recorded in the resolved-type table (anything
but `TYPE_UNDEFINED`) before creating a new tuple, so the global symbol, the
lowered temp and the generated printer share ONE C type. New positive fixture rows:
module-level `var g_tupv = .{ 11, 22 };` / `const g_tupc = .{ 33, 44 };` printed
through `showTuple()` (read from a separate function), golden lines
`gtupv=.{ 11, 22 } gtupc=.{ 33, 44 }`; `stdlib_print_aggregate_xmod` golden
re-captured (454 -> 490 bytes, still byte-identical to the Zig-0.15.2 twin) and the
standalone `repro/print_aggregate.z98` gained the same rows.

**Important 2 / controller ruling R8 (nested packed aggregates).** A packed
struct/packed union field inside another aggregate was admitted by the validator
(the parent's `is_packed` only covered packed parents), and the generated printer
then walked the pre-existing broken packed-VALUE C model (gcc `invalid use of void
expression` / unknown carrier type; the no-print variant fails on the seed compiler
too — pre-existing, out of Task 4 scope). R8: `printFmtAggFieldKindOk`
(`sf/src/lower.zig`) now rejects a nested `packed struct` / `packed union` field
with `error[3063]` at the aggregate argument. New reject site 8 in
`print_aggregate_noprinter_reject_xmod` (`const NonPackedPacked = struct { p: PS2,
b: i32 };`, `np={}`; Zig 0.15.2 accepts and prints `np=.{ .p = .{ .x = 1 }, .b = 2
}` — oracle-twin verified). Census is now **8 x `error[3063]`, 0 other errors, rc
2 / 0 `.c`**.

**Gates.** Fixed point hop1 `fd6a4e021653912a25f4ed68af2ec779` != hop2 == hop3 ==
**`b1680ac74ec5dd5ca68843ff6fc5b93a`**. **4-MD5 emitted-C UNCHANGED** (gol
`9e0b708e…` / lisp `dfa69f32…` / json `a4a73461…` / mud `2e92c1f2…`, 8/8). The
positive fixture + standalone repro are byte-identical to the oracle twin; reject
census 8 x `error[3063]`. Seed stays **v84** (R2-print).

## Task 4 (I/F) — aggregate and tuple printers (v233 -> v234, 2026-09-25)

`{}` on `struct` / `union` (untagged) / `tagged_union` / `packed_union` / `tuple` now prints official
Zig 0.15.2's aggregate form. There are no `std.fmt` primitives for aggregates (Z98 has no
generics), so `sf/src/c89_emit.zig` generates one **static per-type C printer** for every aggregate
type a `.print_val` names (and, dependency-first, for its nested aggregate fields):
`z98_printStruct_<tid>` / `z98_printUnion_` / `z98_printTaggedUnion_` / `z98_printPackedUnion_` /
`z98_printTuple_`. `collectPrintRoots` scans the current module's fn slots; `emitGeneratedPrinters`
runs from `emitModule`/`emitModuleFile` before the fn bodies, so no forward declarations are needed
and the `static` copies of two modules printing the same type are link-safe. The walk reproduces
Zig's `Io.Writer.printValue` aggregate arms byte-for-byte, including the recursion cap
(`std.fmt.default_max_depth = 3`): named struct `.{ .a = 1, .b = 2 }`, tuple `.{ 1, 2, 3 }`, active
tagged-union field `.{ .a = 1 }` (Z98 tags are integer; `switch (v.tag) { case <field-index>: ... }`),
untagged auto union `.{ ... }` (a field is never read), packed union all fields
(`.{ .a = 7, .b = 7 }`), packed struct via the existing `emitPackedLoadBitfield`, and `.{ ... }` at
depth 0. Scalar fields route through `getPrintFnName(..., 'd')`; nested aggregates recurse with
`d - 1`; packed fields extract into declared scratch locals.

**Tuple C model + need gating.** Tuple types are synthetic (`name_id 0`), so `getCTypeName` gives
them a stable `Tup_<tid>` name, `emitTupleType` emits `typedef struct { <e0> _0; <e1> _1; ... }`,
`ctypeGuardWrite` uses `ZIG_TUPLE_`, and `tstEdgesCount`/`tstEdgesFill`/`tstIsDep` gained tuple
element arms. Tuple typedefs are emitted ONLY for `C89Emitter.needed_tuple_set` — the tuples that
hold a runtime value (hoisted temps/globals; `collectNeededTuples` + `emitNeededTupleTypes` at the
end of both type-emission paths). The registry also holds print-args tuple types (e.g. gol has 2);
emitting those would add C to every printing program and move the 4-MD5 single-file dumps, so they
stay unemitted. `lower.zig`'s `AstKind.tuple_literal` arm now materialises a real tuple value
(`nextTemp(tuple_type)` + `assign_field` per element; before, only the first element survived:
`const t = .{1,2,3}` assigned `t = zT_1` and a direct `print("{}", .{.{1,2,3}})` printed `1`), and
`semanticAnalyzerResolveTupleLiteral` (`sf/src/semantic_analyzer.zig`) resolves every element BEFORE
appending the element types to `xt`, so a nested tuple literal can no longer shift the outer tuple's
element range (the outer C model/printer saw `i32` instead of the nested tuple type).

**Bounded residual (documented).** `printFmtCheck`'s aggregate arm recurses through the value the
printer would read (`printFmtAggFieldsOk`/`printFmtAggFieldKindOk`, `sf/src/lower.zig`) and accepts
only integer-like kinds (minus `enum`), `bool`, `f32`/`f64`, `u8` and nested aggregates (packed
aggregates: scalars <=32 bits only). An aggregate with a field outside that closure — `enum` /
`error_set` (Task 5), a pointer (Task 6), an array / slice / optional / error-union / `void` (no
owning task) — rejects the ARGUMENT with `error[3063] "print argument type is not supported (no
std.fmt printer)"` (rc 2 / 0 `.c`) instead of emitting C that cannot compile. Official Zig 0.15.2
ACCEPTS and prints every such site (`{ 1, 2, 3 }`, `{ 104, 105 }`, `.green`, `i32@…`, payload/`null`,
nested packed `.{ ... }`), so these are Zig-accepted bounded residuals, the same operator-principle
class as Task 3's Q3 list. An untagged auto union with unsupported fields is still accepted (its
printer never reads a field) — pinned by the positive fixture's `uctrl` row. A pre-existing
empty-struct registry defect (`struct {}` resolves with unrelated field entries) means empty named
aggregates reject too; not pinned (out of scope).

**Fixtures.** Positive runtime `repro/mi_matrix/stdlib_print_aggregate_xmod` (15-line / 454-byte
golden, rc 0, 3x byte-exact, Zig-0.15.2-twin byte-identical; struct/tuple/nested-tuple/mixed-tuple/
tagged/untagged+control/packed-struct/packed-union/nested-struct/mixed-width/depth-cap/parameter/
global/direct-tuple rows; stdlib pin **236 -> 237**). Reject
`repro/mi_matrix/print_aggregate_noprinter_reject_xmod` (`expected.rc` = 2; 7 sites, 7 x
`error[3063]`, 0 `.c`, FAIL; array/slice/enum/pointer/optional/packed-nested/tuple-pointer fields;
each site oracle-accepted). Standalone `repro/print_aggregate.z98` (rc 0, byte-identical to the
same Zig twin).

**Gates.** Self-compile **moving point** hop1 `864994319f4005ae99696ceb3214ba7d` != hop2 == hop3
== **`6e2cef8bc82fc0e1963aaab638c4c858`**. **4-MD5 emitted-C UNCHANGED** (gol `9e0b708e…` /
lisp `dfa69f32…` / json `a4a73461…` / mud `2e92c1f2…`, 8/8 dump checks, 2x each) — the STOP rule is
satisfied and runtime identity is re-confirmed by execution (gol `fcbf7e7c…` / lisp `b3d9f897…` /
json `8bda3d5a…` / mud server `66c8f0ab…` + client `93147d0f…`). Corpus `-s0` **1025 = 884 OK /
46 GREEN / 95 FAIL / 0 ICE / 0 CRASH**; the full-classifier join-diff vs Task 3 over the 1023
common dirs is **empty (zero class movement)** — the 2 new dirs are the positive fixture (OK) and
the reject fixture (FAIL). Stdlib runtime gate **237 PASS / 0 FAIL**; example matrix **24/24**;
`check_emit_support.sh` **7/7**; `verify_upgraded.sh` **CLOSEOUT OK**. Seed stays **v84** (R2-print:
rotation is closeout-only).

## Task 3 (F) — print-format validator + rejects (v232 -> v233, 2026-09-25)

`lowerPrintFmt` (`sf/src/lower.zig`) now validates each `print` argument's static type against
its specifier before emitting `.print_val` (spec §6 / frozen table
`.superpowers/sdd/2026-09-22-z98-print-formatting-plan/task-0-report.md`): new level-0
`error[3013]` `ERR_3013_INVALID_PRINT_SPECIFIER` for Zig-rejected spec/type mismatches and the
new level-0 `error[3063]` `ERR_3063_PRINT_TYPE_NOT_SUPPORTED` for no-printer kinds, both at the
**argument node's** span → rc=2 / 0 `.c`. **Operator ruling Q1:** the code is 3063, not the
plan's original 3058 (`3058` is live `ERR_3058_CONDITION_NOT_BOOL`); the design spec §6 and the
plan's `3058` references are corrected. **Crash guard (mandatory):** the argument deref is now
guarded against `TEMP_NONE`/out-of-range temps — `std.io.print("{}", .{f()})` with `f() void`
previously SIGSEGV'd the compiler (dump rc=139 at `lower.zig:1015`; the validator now rejects it
cleanly with `error[3063]`). The validator tracks a bare `{}` separately from an explicit `{d}`
(aggregates/error sets accept the former, reject the latter), uses sema's resolved type as
authority (lowered temp type fallback; primitive-type values such as `. {u32}` are detected via
the symbol table / type name cache), emits once per argument node
(`diagnosticCollectorMarkNodeOnce`), and suppresses the type check for an unknown specifier (the
existing fmt-span `error[3013]` is not doubled).

**Operator-ruled Q3 bounded residuals (Zig accepts; Z98 rejects 3063, documented):** `{}` on
`void`/`null`/`type`; `[]const u8 {x}`; `[N]u8 {s}`/`{x}`; `*const [N]u8 {s}`/`{x}`;
`[*c]u8 {s}`/`{x}` (unparseable in Z98). **R5 residual:** `{c}` on an `integer_literal` stays
`error[3013]` (Zig accepts an in-range comptime literal). `[*]u8 {s}`/`{x}`, `undefined`,
arrays, optional / error-union and function-body values are Zig-rejected too, so their clean
reject matches the oracle.

**Fixtures.** Reject `repro/mi_matrix/print_fmt_type_reject_xmod` (`expected.rc` = 2; 60 sites,
60 × `error[3013]`, 0 × `error[3063]`, FAIL; the H9 `{q}` on bool is the no-double-report
control — one diagnostic, not two) and reject
`repro/mi_matrix/print_fmt_noprinter_reject_xmod` (`expected.rc` = 2; 20 sites, 20 ×
`error[3063]`, 0 × `error[3013]`, FAIL). Positive runtime
`repro/mi_matrix/stdlib_print_fmt_valid_xmod` (27-row oracle-twin-matched golden, rc 0, 3×
byte-exact; stdlib pin **235 → 236**). Standalone `repro/print_fmt_valid.z98` (rc 0, golden
stdout) + `repro/print_fmt_reject.z98` (rc 2 / 0 `.c` / 3 × `error[3013]` + 3 × `error[3063]`).

**Gates.** Self-compile **moving point** hop1 `5843a377eec246ffb01a5d317e37db21` ≠ hop2 == hop3
== **`1dd9d76dc43422e2d9ea17be63d905f1`**; **4-MD5 emitted-C UNCHANGED** (gol `9e0b708e…` /
lisp `dfa69f32…` / json `a4a73461…` / mud `2e92c1f2…`, 2× each — the validator is reject-only,
so the STOP rule holds) with runtime identity re-confirmed by execution (gol `fcbf7e7c…` / lisp
`b3d9f897…` / json `8bda3d5a…` / mud server `66c8f0ab…` + client `93147d0f…`, all rc 0); corpus
`-s0` **1023 = 883 OK / 46 GREEN / 94 FAIL / 0 ICE / 0 CRASH** (full-classifier join-diff vs the
Task-2 1020-dir baseline = exactly the 3 new fixture dirs, **zero other class movement**);
stdlib runtime gate **236 PASS / 0 FAIL**; example matrix **24/24**; `check_emit_support.sh`
**7/7**; `verify_upgraded.sh` **CLOSEOUT OK**. Seed stays **v84** (R2-print: rotation is
closeout-only). Docs: design spec §6 (`3058` → `3063`, Q3/R5 boundaries, argument span) + plan
`3058` references, `sf/docs/tech_docs/{00_shared_infra,07_lir_lowering,INDEX}.md`,
`docs/sf/QUICK_REF.md`.

## Task 2 ruling applied — 4-MD5 re-baseline + negative-`{x}` oracle confirmed (v231 -> v232, 2026-09-25)

**Operator ruling (2026-09-25).** (1) The Task-2 4-MD5 movement is **re-baselined with runtime
identity**: the dump carries the changed `std_fmt` module C (`std_fmt.zig` `printHexI32/I64`; the
lockstep `pal_f64_to_str` integral branch is runtime-only and dump-invisible — the dump carries PAL
*calls*, not bodies), no gate-program call-site route changed, and the runtime stdout is
byte-identical PRE<->POST for all four. New authoritative rows: gol `c56ff666…` -> **`9e0b708e18b6fd2b15f9b1e84b6b1571`**,
lisp `573dbd70…` -> **`dfa69f32f33f21b75e8c03e4a151611f`**, json `b01005d4…` -> **`a4a7346153557c9e85a8d112d3866a64`**,
mud `f9e5bb58…` -> **`2e92c1f22efedd8ae0c6aa2fc2c45d0e`** (+1994 B each; re-dumped 2x with
`/tmp/t2/build_final/zig1_5_clean`). Runtime identity re-confirmed by execution: gol
`fcbf7e7cead5082f0a8caadd5a8f0ff9` / lisp `(+ 1 2)` `b3d9f8974da24ddbf9d389f3d7d97322` / json
`8bda3d5a1ec07d14a301bc343df32bf8` / mud server `66c8f0abb926cca7baf9a0d1692ab318` + client
`93147d0f0bbd983a9d844fea8b7a6fa7` (all `cmp` byte-identical, rc 0). (2) The negative-`{x}` form is
the **oracle** form — `-` + hex magnitude (`-10` -> `-a`, `-549755813888` -> `-8000000000`) —
confirmed against Zig 0.15.2; the plan/7G "signed decimal" prose was imprecise. The Task-2 section
below keeps the pre-ruling wording with this note; `docs/sf/QUICK_REF.md`'s 4-MD5 table + Task-2
bullet carry the applied ruling.

## Task 2 (F) — width/signedness dispatch + `{x}`/float format fixes (v230 -> v231, 2026-09-25)

`printFnSourceName` (`sf/src/c89_emit.zig`) is now a width/signedness dispatcher over integer-like
kinds (new `printKindIsIntegerLike`: fixed ints, arbitrary-width ints, `c_char`, `enum`,
`integer_literal`): `typeRegistryIntWidthBits`/`typeRegistryIntIsSigned` route a ≤32-bit
unsigned/signed type to `printU32`/`printI32` and a 33..64-bit type to `printU64`/`printI64` (with
the matching `printHex*` for `{x}`); Z98 `usize` is 32-bit unsigned; `integer_literal` is the
32-bit signed fallback. This fixes the pre-Task-2 fallthrough to `printI32`: `usize` 3000000000
printed `-1294967296` (now `3000000000`), a size-8 `u40` printed `-1` (now `1099511627775`), an
`i40` printed `0` (now `-549755813888`).

`std_fmt.zig`'s `printHexI32/I64` now print **`-` + hex magnitude** for a negative value (Zig
0.15.2 oracle: `-10` → `-a`, `-549755813888` → `-8000000000`, `i32` min → `-80000000`), replacing
the two's-complement form (`fffffffb`). **Controller-ruling note:** the frozen table A12 / Task-2
Step-2 prose said "signed decimal when `val < 0`"; the oracle — and A12's own recorded evidence
`p_ints ix=-8000000000` — print `-` + hex magnitude, which is what was implemented. The design
spec §4 wording was corrected.

`pal_f64_to_str` (both lockstep copies) omits the `'.'`+fraction when the value is integral
(`7.0` → `7`, `100.0` → `100`, `0.0` → `0`). **Documented Q2 bounded residuals (unchanged):**
non-integral values keep the 6-digit truncation (`1.0/3.0` → `0.333333`, Zig
`0.3333333333333333`); `1e20` hits the `(i64)` cast UB and prints `-9223372036854775808…` (Zig
`100000000000000000000`); `-0.0` → `0` (Zig `-0`).

**Fixtures (1 new dir, OK; stdlib pin 234 -> 235):**
- `repro/mi_matrix/stdlib_print_dispatch_xmod` — 18 rows: wide `usize` `{}`/`{x}`, `u40`
  `{}`/`{x}`, `i40` `{}`/`{x}`, `u16 {x}`, `i8` negative/positive `{x}`, `i32`/`i64` negative
  `{x}` incl. both minima, `c_char {x}`, integral f64/f32 `{}`; every value `@panic`-guarded;
  golden byte-identical to the official Zig 0.15.2 twin, rc 0, 3x deterministic.
- `repro/mi_matrix/stdlib_f32_print_xmod` golden **re-captured** (`f32-calc = 7.0` -> `7`);
  header updated.
- standalone `repro/print_dispatch.z98`; `repro/print_std_fmt_seam.z98` header re-captured
  (`neghex=-5`).

**Gates (Task-2 compiler `/tmp/t2/build_final/zig1_5_clean`, hop1):** self-compile **moving
point** hop1 `da7baa2836e536699257b92d2cb23200` != hop2 == hop3 ==
**`475e9a920934583a23a90a7ac1bb4e52`**; **4-MD5 emitted-C MOVED** (gol `c56ff666…` ->
`9e0b708e…`, lisp `573dbd70…` -> `dfa69f32…`, json `b01005d4…` -> `a4a73461…`, mud `f9e5bb58…`
-> `2e92c1f2…`) — the dump carries the changed `std_fmt` module C (both new `printHexI32/I64`
bodies + the consequent type/temp interning shifts); the lockstep PAL integral branch is runtime-only
and dump-invisible, **runtime output
byte-identical PRE<->POST for all four** (gol `fcbf7e7c…` / lisp `b3d9f897…` / json
`8bda3d5a…` / mud server `66c8f0ab…` + client `93147d0f…`); operator-authorized re-baseline with
runtime identity (2026-09-25 ruling — see the v232 section above); corpus `-s0` **1020 = 882 OK / 46 GREEN /
92 FAIL / 0 ICE / 0 CRASH** (join-diff vs the Task-1 fix-round classification on the 1019
common dirs **empty**; the only new dir is `stdlib_print_dispatch_xmod`, OK); stdlib runtime
gate **235 PASS / 0 FAIL**; example matrix **24/24**; `check_emit_support.sh` **7/7**;
`verify_upgraded.sh` **CLOSEOUT OK**. Seed stays **v84** (R2-print: rotation is closeout-only;
`release/seed/` untouched).

## Task 1 (F) fix round 1 — auto-import std_fmt for aliased print callees (v229 -> v230, 2026-09-24)

**Finding (review Important, verbatim summary).** The Task-1 auto-import scan
(`sf/src/main.zig` `astStoreHasPrintCall`) only matched `fn_call` callees named `print`, so
`const io = @import("std_io.zig"); const p = io.print; p("alias={}\n", .{7});` (direct std_io
import, no `std`) lowered through the print special case (`lower.zig`, keyed on the resolved fn
`name_id`) with **no std_fmt in the graph**: dump rc 0, emitter wrote an **unmangled
`printI32(zT_0);`**, link failed `undefined reference to 'printI32'` — a regression vs the base
compiler (`/tmp/t0/build/zig1_5_clean` emitted `std_print_i32(...)`, linked, printed `alias=7`).
The `std`-import variant was masked because `std.zig` re-exports `fmt`.

**Fix (preferred option: broaden the scan; no new diagnostic — Task 3 owns diagnostics).**
`astStoreHasPrintCall` → **`astStoreHasPrintRef`**: it now matches ANY `ident_expr`/`field_access`
payload named `print`, which includes a direct callee AND the alias initializer `io.print`.
Over-approximation is safe: an unreferenced std_fmt is pruned at emission. Evidence: the alias
repro now dumps with `std_fmt_*.c/.h` present and a mangled `zF_…_printI32(...)` call, builds and
runs `alias=7` rc 0; variants `const p = @import("std_io.zig").print;` and `const q = io.print;`
also auto-import (both mangled + rc 0). **No known escaping shape remains** — a print fn value can
only be obtained through some `ident_expr`/`field_access` referencing the name; the only residual
is the silent unmangled fallback in `getPrintFnName` when std_fmt is absent, which the broadened
scan makes unreachable in practice (kept defensive; a level-0 diagnostic is Task 3's scope).

**Fixtures (1 new dir, OK; stdlib pin 233 -> 234):**
- `repro/mi_matrix/stdlib_print_alias_xmod` — `const p = io.print; p("alias={}\n", .{7});
  p("bool={}\n", .{true});` (direct `std_io` import), golden `alias=7` / `bool=true`, rc 0, 3x.
- standalone `repro/print_std_fmt_alias.z98`.

**Gates (fix-round compiler):** self-compile **moving point** hop1 `38cc3974721e5e49792725bd8a5772f7`
!= hop2 == hop3 == **`4061adac1424c7dccb256931ea2a88fa`**; **4-MD5 emitted-C UNCHANGED at the
Task-1 re-baselined values** (gol `c56ff666…` / lisp `573dbd70…` / json `b01005d4…` / mud
`f9e5bb58…`; no gate program aliases print); corpus `-s0` **1019 = 881 OK / 46 GREEN / 92 FAIL /
0 ICE / 0 CRASH** (join-diff vs the Task-1 classification on the 1018 common dirs **empty**; the
new alias dir is OK); stdlib runtime gate **234 PASS / 0 FAIL**; example matrix **24/24**;
`check_emit_support.sh` **7/7**; `verify_upgraded.sh` **CLOSEOUT OK**. Seed stays **v84**
(R2-print: rotation is closeout-only; `release/seed/` untouched).

## Task 1 (F) — create `std.fmt` and migrate the print primitives (v228 -> v229, 2026-09-24)

The print-formatting plan's Task 1 moved the formatting layer out of the C runtime into the new Z98
std module `sf/src/std_fmt.zig` (re-exported as `std.fmt`). The compiler now emits **mangled
cross-module `std.fmt` calls** for `.print_val`, **auto-imports std_fmt** whenever the parsed
program contains a call whose callee is named `print` (`phase_ImportResolution`), and locates the
module at emission (`moduleIdForBasename` + a `.print_val` `ref_edges` seed). The `.print_val`
C-ABI names (`std_print_i32/u32/i64/u64/f64/bool/char/str/hex_*`) are retired from the call sites
and their DEFINITIONS are removed in lockstep from `sf/src/include/zig_runtime.c` and
`sf/src/emit_support.zig` (the `zig_runtime.h` declarations are retained for compatibility);
`std_print`/`std_print_len` remain the raw-bytes helpers. std_fmt uses the same PAL primitives the
retired bodies used (`pal_print_stdout` + `pal_i64/u64/f64_to_str`) so output bytes AND ordering are
unchanged.

**Fixtures (2 new dirs, both OK; stdlib pin 231 -> 233):**
- `repro/mi_matrix/stdlib_std_fmt_seam_xmod` — every pre-seam route (i32/u32/i64/u64 `{}`/`{d}`,
  non-negative `{x}`, u8 `{c}`, `bool {}`, `[]const u8 {s}`, f32/f64 `{}`, literal segments) +
  a direct `std.fmt.printI32` through the re-export; 13-line exact golden, rc 0.
- `repro/mi_matrix/stdlib_print_autoimport_xmod` — imports `std_io.zig` directly (no `std`), so the
  auto-import is the only way std_fmt enters the graph; golden `auto=9 ok=true`, rc 0.
- standalone `repro/print_std_fmt_seam.z98`.

**Gates (Task-1 compiler; deterministic 3x per fixture via the stdlib harness):** self-compile
**moving point** hop1 `2e5e7530a37487e4fddee9084bd31bb5` != hop2 == hop3 ==
**`c1949a3d032c9414f40ef42ec7d38d16`**; **4-MD5 emitted-C ALL FOUR MOVE (sanctioned re-baseline —
the dump now carries std_fmt's C)**: gol `e7bde571…` -> `c56ff666f8dec9eb16f0dab4ed9207e4`, lisp
`4afb601f…` -> `573dbd707e9bcb24cbe50ce1dee45b0e`, json `09fb55e5…` ->
`b01005d4083c7302cd36a43166d73d1c`, mud `5a1cc65e…` -> `f9e5bb583121364f5577e331a826f375`, 2x
each with PRE<->POST runtime byte-identity (gol `40cfee96…` PRE==POST, json `8bda3d5a…`, lisp
`(+ 1 2)` `b3d9f897…`, mud session `66c8f0ab…`/`93147d0f…`); corpus `-s0`
**1018 = 880 OK / 46 GREEN / 92 FAIL / 0 ICE / 0 CRASH** (1016 common dirs, full-classifier
join-diff vs the pre-task baseline **empty — zero class movement**; the 2 new dirs are OK);
stdlib runtime gate **233 PASS / 0 FAIL**; example matrix **24/24**; `check_emit_support.sh`
**7/7**; `verify_upgraded.sh` **CLOSEOUT OK**. Seed stays **v84** (operator R2-print: rotation is
closeout-only; `release/seed/` untouched).

**No manifest/expectation change for any pre-existing fixture** — this is a pure class-neutral
seam move; the version bump records the 2 new fixtures + the census.

## Task 19 (F) — whole-plan closeout (v228; NO BUMP, 2026-09-24)

The trailing-issue parity plan's whole-plan closeout re-verified this manifest with the final
compiler (seed rebuild of HEAD `c3b1401f`; moving point hop1 `252ad3e361daee241b4d7c32c513b2bd` ->
closure hop2 == hop3 == **`b7a7da2673d60852006e9ea87909be1d`**): the frozen Step-0 35-shape table
normalized byte-identical to the Part-I closeout final (28 accepted shapes all Zig-0.15.2-equal,
3x deterministic; 7 rejects oracle-rejecting too), 4-MD5 emitted-C unchanged (mud `5a1cc65e…` /
gol `e7bde571…` / lisp `4afb601f…` / json `09fb55e5…`, 2x each, hop1 and hop2), corpus `-s0`
**1016 = 878 OK / 46 GREEN / 92 FAIL / 0 ICE / 0 CRASH** (join-diff vs the Task 18 fix-round
classification **empty**), stdlib 231 PASS / 0 FAIL, example matrix 24/24, `check_emit_support.sh`
7/7, `verify_upgraded.sh` CLOSEOUT OK, build_test 0/9 (pre-existing retired-zig0 baseline).
**No version bump**: no fixture expectation and no fixture class changed. Seed rotated v83 -> v84
(archive md5 `50501c4bc00beed12ce06688d3b64664`; archived binary md5 = fixed point; post-rotation
rebuild closure hop1 == hop2 == `b7a7da26…`).

**Recorded census drift (Part II Task 14 side effect; verdict/class unchanged).**
`comptime_coerce_reject_xmod` was recorded at Task 6 as 12 x `error[3000]`; the Task 14 sema-phase
call-argument gate now clean-rejects its `takeOpt8(@as(i32, 300))` site (`error[3000] "type mismatch
in function argument"` + `note: parameter type declared here`) before lowering, so the current
compiler emits **1 x `error[3000]` + 2 x `warning[3000]`** and the 11 lowering-phase rejects no
longer run (the fixture is still rc=2 / 0 `.c` / GREEN, and Zig 0.15.2 rejects it). The fixture
header contract comment is updated accordingly; probe evidence: dropping the `takeOpt8` call from a
`/tmp` copy re-exposes 11 x `error[3000]`.

## Task 18 (F) fix round (review Important 1) — wire the remaining Zig location-note sites (v227 -> v228 2026-09-24)

**Finding (verbatim).** *"The brief explicitly asks for related spans at 'any other site where Zig
emits a note'; `error[3061]`/`error[3007]`/`error[3060]`/`error[3000]`-call-arg have Zig location
notes and none were wired ... Either wire them ... or obtain an operator ruling bounding the clause,
and correct report.md:22-25 + QUICK_REF's 'the only Zig-note-with-location family' statement."*

**Fix (four families wired; Zig-0.15.2-oracle cross-checked).**

* `error[3061]` arity -> `note: function declared here` at the callee's `fn_decl` node
  (`semanticAnalyzerReportCallArity` gains `decl_node`/`decl_file`; `main.zig:32`/`:36` in
  `call_arity_reject_xmod`, matching Zig's `main.zig:29:1` on the pristine fixture — the fixture's
  header comment shifted the sites when the expected-note block was added).
* `error[3007]` visibility -> `note: declared here` at the non-`pub` declaration's own location in
  its own file: `helper.zig:10/14/15/16`, `inner.zig:10/14` in `pub_visibility_reject_xmod` (Zig:
  `helper.zig:10:1`). `Symbol` gained `file_id`, set from the declaring module in all six
  `symbol_registrator.registerDecl` arms; both `semanticAnalyzerCheckMemberVisibility` and
  `type_resolver.typeResolverCheckMemberVisibility` use it.
* `error[3060]` member-not-found -> `note: struct declared here` / `note: union declared here` /
  `note: enum declared here` at the aggregate declaration (`main.zig:40/45/54/59` in
  `method_syntax_reject_xmod`; Zig: `main.zig:37:15`). New `semanticAnalyzerFindTypeDecl` reverse
  lookup through the owning module's `type_alias` symbols (`ReportUnknownMember` now takes the base
  type id). An anonymous type or an error set correctly gets no note (Zig prints none for an error
  set).
* `error[3000]` call-arg -> `note: parameter type declared here` at the callee's parameter
  (`main.zig:37/41/45/53/57` in `call_arg_type_reject_xmod`; Zig: `main.zig:34:19`). New
  `semanticAnalyzerParamDeclNode`; `semanticAnalyzerCalleeDeclSymbol` resolves ident and single-level
  `mod.fn` / `@import("x.zig").fn` callees for both the arity and the argument note
  (cross-module probe `helper.addOne(1, 2)` -> `helper.zig:1: note: function declared here`).

**Bounded residual (documented, not silently skipped):** a **nested-module** callee
(`std.io.print()`, `call_arity_reject_xmod`'s last site) still gets no note — the callee's symbol
sits behind a multi-level module chain that `semanticAnalyzerCalleeDeclSymbol` does not walk. The
review's four pinned fixture cases are all wired; Zig's own early-stop prevents an oracle note pin
for the nested site.

**Claim correction.** The base entry's "This is the only Zig-note-with-location family in Z98's
diagnostics" was WRONG and is corrected in place below; the QUICK_REF bullet and tech doc 05/INDEX
headers were corrected the same way.

**Fixtures.** Expected-note blocks added to the four reject fixtures' headers (with the exact note
lines) and to the standalone `repro/call_arity_types.z98`, `repro/pub_visibility.z98`,
`repro/method_syntax.z98`, `repro/pub_visibility_fold.z98` headers.

**Gates (fix round).** self-compile moving point hop1 `252ad3e361daee241b4d7c32c513b2bd` != hop2 ==
hop3 == `b7a7da2673d60852006e9ea87909be1d` (explicit `FIXED_POINT_MD5=b7a7da26…` gate OK,
deterministic); 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `4afb601f…` / json `09fb55e5…` /
mud `5a1cc65e…`, 2x on hop2 too); corpus `-s0` **1016 = 878 OK / 46 GREEN / 92 FAIL / 0 ICE / 0
CRASH** (join-diff vs the Task 18 base run **empty**, zero class/set movement — the changes are
stderr-rendering + symbol bookkeeping only); std-lib runtime gate **231 PASS / 0 FAIL** (pin
unchanged); example matrix **24/24**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK;
build_test **0/9** (pre-existing zig0 baseline); self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC.
Seed stays **v83** (operator R2: rotation is closeout-only — `release/seed/` untouched).

## Task 18 (F) — related-span diagnostics + non-ASCII message audit (v226 -> v227 2026-09-24)

**Defects.** (i) `diagnosticCollectorAddRelatedSpan` (`sf/src/diagnostics.zig`) had zero call sites, so
no diagnostic could point at the earlier declaration the way Zig's `note:` does (and the renderer's
`related_span_idx > 0` guard meant an index-0 span could never print). (ii) Five `error[3000]` message
strings embedded a raw UTF-8 em dash (`sf/src/semantic_analyzer.zig`) — an ASCII/ISO-8859-1 manual page
cannot quote them byte-exactly.

**Fix (1) related spans.** The collector now reserves related-span slot 0 as the "no related span"
sentinel before the first emission, so the first real span lands at index 1 and renders. The two
`error[3057]` paths of `semanticAnalyzerCheckLocalShadow` now emit related spans: the local/param/
capture/redeclaration hit reads the new parallel `local_decl_spans_start`/`local_decl_spans_end` arrays
(written at every registration site; `registerLocalDecl` takes the name span; `semanticAnalyzerGrowLocalDecls`
grows/copies them), and the container-level path uses the symbol's `decl_node` span. Rendering:
`<file>:<line>: note: previous declaration here` (or `note: declared here` for a container-level decl) —
the same note locations Zig 0.15.2 prints. All 14 sites in `shadow_reject_xmod` now point at the right
earlier line (22/23/36/43/14/14/15/16/17/67/71/77/87/100). **CORRECTED by the Task 18 fix round
above:** this is NOT the only Zig-note-with-location family — the arity (`error[3061]`), visibility
(`error[3007]`), member-not-found (`error[3060]`) and call-argument (`error[3000]`) families now
emit related spans too (see the v227 -> v228 section). The remaining `AddNote` sites are the
Z98-specific `source:`/`target:` type notes (no Zig location-note counterpart).

**Fix (2) ASCII audit.** The five `error[3000]` messages now use ASCII ` -- `:
`type mismatch in return statement -- ...`, `type mismatch in function argument -- ...` (two sites),
`type mismatch in assignment -- ...`, `type mismatch in variable declaration -- ...`. Audit command
`LC_ALL=C grep -rnP '"[^"]*[^\x00-\x7F]' sf/src --include=*.zig | grep -vP ':\s*//'` (plus the
whole-tree non-ASCII census) finds no non-ASCII diagnostic message string; the only surviving non-ASCII
string literals live in `emit_support.zig` and are emitted-C **prelude comments**, not diagnostics —
deliberately untouched (changing emitted C would move the 4-MD5 gates). The new `error[3060]`/`[3061]`/
`[3062]` messages were already ASCII. `diag_excerpt_multifile_xmod`'s rendered warning now reads
`type mismatch in assignment -- internal type representations differ; generated code may be incorrect`
(rc=0 / 5 `.c` / class OK unchanged).

**Fixtures.** Reject `repro/mi_matrix/shadow_related_span_xmod` (`expected.rc` = 2; param /
outer-local / same-scope / `if`-capture / container-level sites): **rc 2 / 0 `.c` / 5 x `error[3057]` /
5 related-span lines** (stderr pinned in `NOTES.md`); Zig 0.15.2 prints notes at the same lines
(`14->13`, `23->21`, `35->34`, `42->10`). Standalone `repro/shadow_related_span.z98`. Pre-existing
`parsergap_shadow_local_xmod` (reject) now shows `main.zig:3: note: previous declaration here`.

**Known divergence (pre-existing Task 7D, NOT addressed).** Z98 reports every shadow site in a function;
Zig 0.15.2 suppresses later in-function shadow errors after one has been reported (the fixture's
same-scope `const twice` is Z98-only) — a diagnostic-count divergence, not a related-span one.

**Gates.** self-compile moving point hop1 `c64e8e6e0039158b1ab0cd7f8a5eac6f` != hop2 == hop3 ==
`13e9458114537ca669f21816762a4f30` (explicit `FIXED_POINT_MD5=13e94581…` gate OK, deterministic);
4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `4afb601f…` / json `09fb55e5…` / mud
`5a1cc65e…`); corpus `-s0` **1016 = 878 OK / 46 GREEN / 92 FAIL / 0 ICE / 0 CRASH** (join-diff vs the
Task 17 fix-round baseline 1015 = exactly the new fixture dir, **zero class movers**); std-lib runtime
gate **231 PASS / 0 FAIL** (pin unchanged); example matrix **24/24**; `check_emit_support.sh` 7/7;
`verify_upgraded.sh` CLOSEOUT OK; build_test **0/9** (pre-existing zig0 baseline); self-emission rc 0 /
48 `.c` + 48 `.h` / no PANIC. Seed stays **v83** (operator R2: rotation is closeout-only —
`release/seed/` untouched).

## Task 17 (F) fix round (review Important 1) — runtime-end slice no longer over-rejected (v225 -> v226 2026-09-24)

**Finding (verbatim).** *"Slice check over-rejects comptime-start / runtime-end beyond length
(`sf/src/semantic_analyzer.zig:929-933`): when `child_2 != 0` but end doesn't fold, `end_eff` falls
back to `alen`, so `scores[7..ri]` (ri runtime) → rc2 `start index 7 is larger than end index 5`;
Zig 0.15.2 accepts it (`build-exe -fno-emit-bin`, only unused-var diagnostics). BASE compiled it
(runtime panic rc133). Not in the report's residual list. Fix: use `alen` as `end_eff` only for the
open form (`child_2 == 0`); skip the start check when a present end is runtime."*

**Fix** (`sf/src/semantic_analyzer.zig` `semanticAnalyzerCheckComptimeSliceBounds`): the start check
now runs only against a comptime-known effective end — `alen` for the open form (`child_2 == 0`),
the folded `end_ci` for a closed form with a comptime end; a closed form whose PRESENT end is runtime
is skipped entirely (no comptime end to compare against). The function comment documents the rule.

**Regression coverage.**

* New fixture `repro/mi_matrix/slice_runtime_end_xmod` (`main.zig`, no `expected.rc` — a runtime
  trap fixture like `safe_bounds_read_xmod`): `var ri: usize = 3; var s: []i32 = scores[7..ri];`
  then prints `@intCast(i32, s.len)`. Contract, identical to the pristine compiler and emitted C
  byte-identical in both modes: `-fsafe` compile rc 0 / run rc 133
  (`panic: integer cast overflow in @intCast`); `-ffast` compile rc 0 / run rc 0,
  stdout `len=-4`. Official Zig 0.15.2 accepts the shape (`build-exe -fno-emit-bin`, rc 0, no
  diagnostics in the harness twin).
* Runtime-end control added to `repro/mi_matrix/stdlib_comptime_index_ok_xmod`:
  `var re: usize = 4; var s6: []i32 = scores[1..re];` (comptime start in range, runtime end) checks
  `s6.len == 3` and `s6[0] == 20`; golden now `50 50 40 10 3 30 5 0 0 2 3 3 3`, rc 0, 3x
  byte-exact, Zig-0.15.2 twin byte-identical (twin stderr md5 `a886f4ef107c083e5fa552d3e12dae3d` ==
  golden; the twin prints the same 13 values). Stdlib pin unchanged at 231.
* Closed/known rejects unchanged: `scores[6..]` (`start index 6 is larger than end index 5`),
  `scores[1..10]` (`end index 10 out of bounds for array of length 5`), `scores[3..1]`
  (`start index 3 is larger than end index 1`), field `st.arr[4..1]` — `slice_range_oob_reject_xmod`
  still 7 x `error[3062]`; `index_oob_reject_xmod` still 8 x `error[3062]`.

**Gates.** self-compile **moving point** hop1 `43b01ac464f4d289f9f2bc1116bee413` != hop2 == hop3 ==
**`ea5d77ea5c1f4fddd7cd0ab213476923`** (explicit `FIXED_POINT_MD5=ea5d77ea…` gate OK, deterministic
across two out-dirs); 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `4afb601f…` /
json `09fb55e5…` / mud `5a1cc65e…`, 2x each); corpus `-s0` **1015 = 878 OK / 46 GREEN / 91 FAIL /
0 ICE / 0 CRASH** (join-diff vs the Task 17 base 1014 = exactly the new regression dir,
**zero other movement**); std-lib runtime gate **231 PASS / 0 FAIL** (pin unchanged); example matrix
**24/24**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test **0/9**
(pre-existing zig0 baseline); self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC / memory
`track-memory: perm=883K mod=1020K scr=1024K pool=17814K type_db=500K total=2927K`.
Seed stays **v83** (operator R2: rotation is closeout-only). Review Minors (empty-array message,
>u64 magnitude text, stale comment) deferred as instructed.

## Task 17 (F) — reject a comptime-known out-of-bounds index at compile time (v224 -> v225 2026-09-24)

**Defect.** A comptime-known out-of-bounds array index compiled rc=0 with no diagnostic: `scores[5]` /
`scores[scores.len]` on a `[5]i32` trapped at runtime under the default `-fsafe` (rc 133 through the A5F
`check_trap{kind=5}` guard) but silently read the wrong value under `-ffast`; the constant slice-range
analogue produced a wrong slice length with no diagnostic (`scores[1..10]` gave len 9). Official Zig
0.15.2 rejects each shape at compile time (`index 5 outside array of length 5`, `end index 10 out of
bounds for array of length 5`, `start index 3 is larger than end index 1`,
`type 'usize' cannot represent integer value '-1'`).

**Fix.** New level-0 `error[3062]` `ERR_3062_INDEX_OUT_OF_BOUNDS` (`sf/src/diagnostics.zig`).
`semanticAnalyzerResolveIndexAccess` and `semanticAnalyzerResolveSliceExpr`
(`sf/src/semantic_analyzer.zig`) run `semanticAnalyzerCheckComptimeIndexOob` /
`semanticAnalyzerCheckComptimeSliceBounds` when the base is a fixed-size array — an array value, a
`*[N]T`, or a struct/union array field (length via `semanticAnalyzerStaticArrayLen` /
`semanticAnalyzerArrayFieldLength`, the Task-11N `.len` declaration walk factored out). The
index/bound folds through `semanticAnalyzerComptimeIntValue` (literals, `const` chains, constant
arithmetic; `.len` of a fixed array is recovered from the base's declared type because the fold
evaluator has no field-access arm). Messages are Zig-0.15.2 ASCII-exact; rejects are deduped per node
(`diagnosticCollectorMarkNodeOnce`) and produce rc=2 / 0 `.c`. **Unchanged:** the runtime-index path
keeps the `-fsafe` `check_trap{kind=5}` guard; slices / `[*]T` have no compile-time length; a string
literal is skipped (Zig's implicit sentinel makes its bound `N + 1`, and Z98 has no sentinel array
kind — bounded residual).

**Fixtures.** Reject `repro/mi_matrix/index_oob_reject_xmod` (`expected.rc` = 2): 8 sites —
`[5]` literal, `.len`, `const` chain, negative, `*[N]T`, struct array field, field `.len`, and
`4294967296` — GREEN **rc 2 / 0 `.c` / 8 x `error[3062]` / 0 x `error[3000]`** (FAIL class).
Reject `repro/mi_matrix/slice_range_oob_reject_xmod` (`expected.rc` = 2): 7 sites — `1..10`,
`10..12`, `3..1`, `6..`, `-1..2`, ptr `1..10`, field `1..4` — GREEN **rc 2 / 0 `.c` /
7 x `error[3062]` / 0 x `error[3000]`** (FAIL class). Positive runtime
`repro/mi_matrix/stdlib_comptime_index_ok_xmod` (in-range comptime indexes incl. a typed `const`, a
pointer, a struct field and `scores.len - 1`; a runtime index; every legal slice boundary
`[0..5]`/`[5..]`/`[5..5]`/`[1..3]`/field/ptr; every check `@panic`-guarded; golden
`50 50 40 10 3 30 5 0 0 2 3 3`, rc 0, 3x byte-exact, Zig-0.15.2 twin byte-identical md5
`e336823a…`; stdlib pin **230 -> 231**). Standalone `repro/comptime_index_oob.z98` (5 sites,
5 x `error[3062]`; RED pre-fix rc 0 / 4 `.c`).

**Oracle (Zig 0.15.2).** Every reject site was independently compiled and rejected with the exact
wording above (one probe per site); the positive fixture's twin accepts and prints the same golden.
Controls: `safe_bounds_read_xmod` still traps rc 133 under `-fsafe` and reads garbage under `-ffast`
(emitted C byte-identical pre/post), `safe_bounds_inbounds_xmod` unchanged, and the runtime-index
probe's emitted C is byte-identical.

**Gates.** self-compile **moving point** hop1 `91446986a6de3c1e9c49a4a2409a28cd` != hop2 == hop3 ==
**`44a3ce38951732d945a9d3d8c6711671`** (explicit `FIXED_POINT_MD5=44a3ce38…` gate OK, deterministic
across two out-dirs); 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `4afb601f…` /
json `09fb55e5…` / mud `5a1cc65e…`, 2x each); corpus `-s0` **1014 = 877 OK / 46 GREEN / 91 FAIL /
0 ICE / 0 CRASH** (join-diff vs the Task 15 fix-round baseline 1011 = exactly the 3 new fixture dirs,
**zero other movement**); std-lib runtime gate **231 PASS / 0 FAIL**; example matrix **24/24**;
`check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test **0/9** (pre-existing zig0
baseline); self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC / memory
`track-memory: perm=883K mod=1020K scr=1024K pool=18008K type_db=500K total=2927K`.
Seed stays **v83** (operator R2: rotation is closeout-only).

## Task 15 (S3) fix round 1 — gate the const-fold field-access positions (v223 -> v224 2026-09-24)

**Review Important 1 (plan-authorized class: "then any other flat/nested module-member shape the
investigation finds asymmetric").** `evalConstIntFull`'s `field_access` arm (`sf/src/type_resolver.zig`,
entered via `evalConstU32Full` for array sizes and `evalConstI64Full` for enum member values) resolved a
cross-module const with no visibility check, so a non-`pub` const folded through the type resolver:
- `var arr: [helper.hidden_const]u8 = undefined;` compiled rc=0 and emitted the array with the folded
  non-`pub` length 5;
- `const E = enum(u8) { A = helper.hidden_const, B };` compiled rc=0.
Official Zig 0.15.2 rejects both (`'hidden_const' is not marked 'pub'`).

**Fix.** The fold arm now runs `typeResolverCheckMemberVisibility` on the member symbol before using it
(emits the same level-0 `error[3007]`, declines the fold). The array-size caller then adds
`ERR_3050_ARRAY_SIZE_NOT_CONSTANT` and the enum walk adds `ERR_3055_ENUM_VALUE_NOT_CONSTANT` as
cascades. Same-module consts and `pub` consts fold unchanged.

**Fixtures.** New reject `repro/mi_matrix/pub_visibility_fold_reject_xmod` (`main.zig` + `helper.zig` +
`inner.zig`; `expected.rc` = 2): flat and nested array-size and enum-initializer sites — rc 2 / 0 `.c`
/ **4 x `error[3007]` + 2 x `error[3050]` + 2 x `error[3055]`** / FAIL class. This is separate from
`pub_visibility_reject_xmod` because a type-resolution diagnostic short-circuits the pipeline before
semantic analysis (`main.zig` prints + exits after `phase_TypeResolution`), so expression sites and
fold sites cannot be pinned in one program (putting both in one fixture suppressed the 7 sema
diagnostics — observed and reverted). New standalone `repro/pub_visibility_fold.z98` (2 x `error[3007]`
+ `error[3050]` + `error[3055]`). Positive fold controls added to `stdlib_pub_visibility_ok_xmod`
(`[helper.shown_const]u8`, `enum(u8){A = helper.shown_const}`, same-module `[hidden_const]u8` behind
`private_buf_len`) and `repro/pub_visibility_ok.z98`; golden unchanged
`a=22 b=46 c=12 d=7 e=9 f=23 g=3 h=8 i=11`, Zig-0.15.2 twin re-matched (md5 `165d27fb…`).

**Oracle (Zig 0.15.2).** `[helper.hidden_const]u8` and `enum{ A = helper.hidden_const }`:
`'hidden_const' is not marked 'pub'`; all four positive fold controls accept.

**Gates.** self-compile **moving point** hop1 `a92d1faacee3b8a90bf825cd30308654` != hop2 == hop3 ==
**`c9e5d744d089f8f7ad1b1846159b5732`** (explicit `FIXED_POINT_MD5=c9e5d744…` gate OK, deterministic
across two out-dirs); 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `4afb601f…` /
json `09fb55e5…` / mud `5a1cc65e…`, 2x each); corpus `-s0` **1011 = 876 OK / 46 GREEN / 89 FAIL /
0 ICE / 0 CRASH** (join-diff vs the Task 15 baseline = exactly the new fold fixture,
**zero other movement**); std-lib runtime gate **230 PASS / 0 FAIL**; example matrix **24/24**;
`check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test **0/9** (pre-existing zig0
baseline); self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC / memory
`track-memory: perm=883K mod=1020K scr=1024K pool=17767K type_db=455K total=2927K`.
Seed stays **v83** (operator R2: rotation is closeout-only). New commit (does not amend `dc373d5c`).

## Task 15 (S3) — enforce `pub` visibility across modules (v222 -> v223 2026-09-24)

**Defect.** A cross-module reference to a non-`pub` declaration was accepted everywhere:
`helper.secret(21)` compiled rc=0, built, ran and printed `21`; a flat non-`pub` const read folded its
value silently; a non-`pub` type annotation resolved; a non-`pub` cross-module `var` store compiled; the
nested `mod.sub.member` shape had no check at all; and the direct `@import("x.zig").secret(21)` callee
emitted gcc-invalid C (`undefined reference to 'zT_1'`). Official Zig 0.15.2 rejects each with
`error: '<name>' is not marked 'pub'`. `ERR_3007_VISIBILITY_VIOLATION` was declared
(`sf/src/diagnostics.zig`) but had zero emit sites — this task is its first emitter.

**Fix.** `sf/src/semantic_analyzer.zig` gains `semanticAnalyzerCheckMemberVisibility`, run by all three
module-member arms of `semanticAnalyzerResolveFieldAccess` (flat `SymbolKind.module` — the reported
defect; direct `import_expr`; nested `module_type`) before the field symbol is used; type positions are
gated by the twin `typeResolverCheckMemberVisibility` (`sf/src/type_resolver.zig`, `resolveTypeExprFull`
`field_access` ident-base + `module_type` sites; emits only when `env.diag` is live). Both emit level-0
`error[3007]` `ERR_3007_VISIBILITY_VIOLATION` (explicit `= 3007`) with the ASCII message
`'<name>' is not marked 'pub'` (Zig wording, deduped per node via `diagnosticCollectorMarkNodeOnce`) and
map the expression to `TYPE_VOID`/`TYPE_UNDEFINED` — rc=2, 0 `.c`. Same-module references never route
through these arms and are unchanged.

**Operator-authorized migrations (2 rulings).** The gate made the new compiler reject its own source
(`ce_mod.ciIntVal` at `lower.zig:2175/2182`, declared non-`pub` in `comptime_eval.zig`), which the
binding STOP RULE reserved for operator authorization; the operator then authorized the full sweep of
invalid-Zig non-`pub` cross-module references the battery exposed:
- `sf/src/comptime_eval.zig:273` `fn ciIntVal` -> `pub fn` (self-compile; without it the hop-2 seed
  closure cannot be established).
- `sf/src/std_net.zig:35` `const IpAddr` -> `pub const` (7 pinned `stdlib_net_udp_*` fixtures name
  `net.IpAddr`; the old comment "Z98 does not gate top-level declarations on `pub`" removed).
- `examples/z98/rogue_mud_upgraded/lib/persistence.zig:28,47` `export fn` -> `pub export fn`
  (`verify_upgraded.sh` B1).
- `examples/z98/json_parser_workaround/file.zig:19` `extern fn strtod` -> `pub extern fn`.
- `examples/z98/lisp_interpreter/value.zig:1` `const sand_mod` -> `pub const sand_mod`.
- `repro/mi_matrix/extern_fn_opt_return_cross/ext.zig:1` `extern fn getp` -> `pub extern fn`.
Every migrated site was independently confirmed as Zig-0.15.2-rejected before the migration (three
reduced oracle probes: `export fn`, `extern fn`, and a non-`pub` import alias are each
`'…' is not marked 'pub'` cross-module). Semantically neutral visibility widenings; the self-emission
fixed point is unaffected by the std-lib migrations (the compiler's import graph reaches no std module).

**Fixtures.**
- Reject `repro/mi_matrix/pub_visibility_reject_xmod` (`main.zig` + `helper.zig` + `inner.zig`;
  `expected.rc` = 2): 7 sites (flat non-`pub` fn/const/type/var, nested non-`pub` fn/const,
  direct-import non-`pub` callee). GREEN: rc 2, 0 `.c`, **7 x `error[3007]`, 0 x `error[3000]`** ->
  FAIL class (the canonical GREEN bucket is `error[3000]` only; a dedicated-code clean reject is the
  established FAIL-bucket pattern, cf. `method_syntax_reject_xmod`).
- Positive runtime `repro/mi_matrix/stdlib_pub_visibility_ok_xmod`: `pub` fn/const/type/var flat +
  nested, and same-module private helpers behind `pub` wrappers (`call_own` -> `secret`/`hidden_const`,
  `uses_hidden` -> `hidden_only`, `call_own2` -> `secret2`). Golden
  `a=22 b=46 c=12 d=7 e=9 f=23 g=3 h=8 i=11`, rc 0, 3x byte-exact
  (md5 `165d27fb509ed3312fa627e60ae0b24e`), **Zig-0.15.2 twin byte-identical** (twin `std.debug.print`
  stderr == golden). Stdlib pin **229 -> 230** (`scripts/stdlib/expected_dirs.txt`).
- Standalone `repro/pub_visibility.z98` (rc=2, 3 x `error[3007]`) and `repro/pub_visibility_ok.z98`
  (rc=0; runs `22 46 23`), both importing the committed fixture modules.

**Oracle (Zig 0.15.2).** Every non-`pub` shape rejects (`'secret'/'hidden_const'/'HiddenAlias'/
'hidden_var'/'secret2'/'hidden_const2'/'HiddenStruct' is not marked 'pub'`); the same-module private
control and every `pub` control accept; cross-module field-access callee resolution is proven live
(`helper.visible(1,2)` -> `error: expected 1 argument(s), found 2` through the Task-14 arity gate).

**Gates.** self-compile **moving point** hop1 `684b6d2e7c627cfc1356f7b5d6ee9bb7` != hop2 == hop3 ==
**`b6bcb1bb4d13729318f5467a9bcc6251`** (explicit `FIXED_POINT_MD5=b6bcb1bb…` gate OK, deterministic
across two out-dirs); 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `4afb601f…` /
json `09fb55e5…` / mud `5a1cc65e…`, 2x each — the `pub` flag does not affect emitted C, so the
`std_net.zig` migration required no re-baseline); corpus `-s0` **1010 = 876 OK / 46 GREEN / 88 FAIL /
0 ICE / 0 CRASH** (join-diff vs the Task 14 baseline = exactly the 2 new fixture dirs,
**zero other movement**); std-lib runtime gate **230 PASS / 0 FAIL**; example matrix **24/24**;
`check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test **0/9** (pre-existing zig0
baseline); self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC / memory
`track-memory: perm=883K mod=1020K scr=1024K pool=17993K type_db=500K total=2927K`.
Seed stays **v83** (operator R2: rotation is closeout-only).

## Task 14 fix round (review Critical 1) — restore the `(b)` call-arg shape rejects (v221 -> v222 2026-09-24)

**Review Critical 1.** The Task 14 call-arg gates replaced `!assignable && isBShapeMismatch(..., false)`
with `!assignable && !semanticAnalyzerCallArgTolerated(...)`, and the new pointer-family tolerance
blanket-accepted every ptr/slice/array pair, so the pre-existing `(b)` call-site rejects stopped firing:
- `*u8` argument to a `[]u8` parameter: base (v221) rc=2 / 0 `.c` / `error[3000]`; broken Task 14 rc=0 /
  4 `.c`, emitting `zT_6 = p;` — gcc `incompatible types when assigning to type 'Slice_…' from type
  'unsigned char *'` (the "rc=0, fails only at gcc" class this task exists to close).
- `[3]i32` argument to a `[4]i32` parameter: base rc=2 / 0 `.c`; broken Task 14 rc=0 / 4 `.c` and gcc
  accepts via array decay (silent length mismatch).

**Fix.** Both gates (`sf/src/semantic_analyzer.zig`) restore the shape arm:
`!assignable and (isBShapeMismatch(self, carg, tgt, false) or !semanticAnalyzerCallArgTolerated(...))`
— the `(b)` shapes (`*T` -> `[]T`, mismatched `[N]T` -> `[M]T`, error-union mismatch, enum -> int) reject
first; the pointer-family tolerance only relaxes the shapes that are not one of those. The tolerance
header comment was corrected (it had claimed the shape rejects were "already covered").

**Regression coverage.** `repro/mi_matrix/call_arg_type_reject_xmod` gains the two oracle-checked sites
(`takeSlice(p)` `*u8` -> `[]u8`; `takeArr4(a3)` `[3]i32` -> `[4]i32`) — now 5 x `error[3000]`, rc 2, 0 `.c`,
class GREEN. `repro/mi_matrix/stdlib_call_arity_types_ok_xmod` gains valid controls (`sumSlice(&arr3)`
`*[3]i32` -> `[]i32`; `firstOf3(arr3)` same-length `[3]i32` -> `[3]i32`), every check `@panic`-guarded;
golden now `s1=3 s2=0 i8v=100 us=4096 fp=42 s3=8 sl=6 f3=1 neg=1`, rc 0, 3x byte-exact, Zig-0.15.2 twin
re-matched (md5 `68491cc7…`).

**Oracle (Zig 0.15.2).** `*u8` -> `[]u8`: `expected type '[]u8', found '*u8'`; `[3]i32` -> `[4]i32`:
`expected type '[4]i32', found '[3]i32'`.

**Gates.** self-compile **moving point** hop1 `a0cc292bc102cbab512bff4d86c5376d` != hop2 == hop3 ==
**`b499fe5f706904cfe2acc74bce300a2b`** (explicit `FIXED_POINT_MD5=b499fe5f…` gate OK, deterministic across
two out-dirs); 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `4afb601f…` / json `09fb55e5…` /
mud `5a1cc65e…`, 2x each); corpus `-s0` **1008 = 875 OK / 46 GREEN / 87 FAIL / 0 ICE / 0 CRASH** —
join-diff vs the base Task 14 run **empty** (zero movement); std-lib runtime gate **229 PASS / 0 FAIL**;
example matrix **24/24**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test **0/9**;
self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC. Seed stays **v83** (operator R2).

## Task 14 (S2) — call arity + argument types (v220 -> v221 2026-09-24)

**SUPERSEDED in part by the fix round above (v222):** the fixed point is `b499fe5f…`; the arg-type
reject fixture now has 5 sites (5 x `error[3000]`) and the positive fixture's golden gained
`sl=6 f3=1`; the "pointer-family invalid shapes stay covered" claim in the original fix description
below was wrong until the fix round restored the shape arm.

**Defect (High — silent miscompile).** `add(2)` / `add(1, 2, 3)` (wrong arity) compiled rc=0
(6 `.c`) and failed only at gcc (`too few`/`too many arguments to function`); `add(1, true)` built,
linked and ran, printing `2` — a silent `bool` -> `i32` coercion. Official Zig 0.15.2 rejects all
three (`expected 2 argument(s), found 1/3`; `expected type 'i32', found 'bool'`).

**Fix.** `sf/src/diagnostics.zig` gains level-0 `ERR_3061_WRONG_ARGUMENT_COUNT = 3061`.
`sf/src/semantic_analyzer.zig`'s `semanticAnalyzerResolveFnCall`:
- **Arity** — the direct-call path reads the resolved fn type's `params_count` + `FN_FLAG_VARIADIC`;
  the fn-value path had the check but silently `return`ed the declared return type. Both now report
  `semanticAnalyzerReportCallArity` ("expected N argument(s), found M"; variadic short call
  "expected at least N argument(s), found M") and CONTINUE analysis (the fn-value loop clamps to
  `min(params_count, args.len)`), so every present argument is still resolved; the sema `hasErrors`
  gate rejects before lowering (rc=2, 0 `.c`).
- **Per-argument assignability** — both paths now reject a typed argument that is neither
  `typeRegistryIsAssignable` nor `semanticAnalyzerCallArgTolerated` with the existing
  `error[3000]` "type mismatch in function argument" + `source:`/`target:` notes. The tolerated
  families (zero-movement constraint: the compiler's own source and the corpus use them pervasively)
  are: integer <-> integer of any width/signedness (incl. `u32` <-> `usize` and narrowing),
  the whole pointer/slice/array interop family (its invalid shapes stay covered by
  `isBShapeMismatch`/lowering), an error-set source into an integer (Z98's
  `@enumToInt(<error set>)` keeps the error-set type), and a void/unresolved source (an undeclared
  identifier already got its single `error[20]`). `bool` is in no family, so the reported defect
  rejects; so do int <-> float, float <-> pointer and aggregate cross-family pairs.

**RED evidence (base `d84f5da4` compiler `1b69e533…`).** `bool_run` probe: rc 0, gcc/link rc 0,
run prints `sum=2`. Wrong-arity probes: rc 0, gcc `too few arguments to function
'zF_3B391274_add'` / `too many arguments to function 'zF_3B391274_add'`.

**GREEN evidence (fix compiler `/tmp/opencode_t14/green/zig1_5_clean`).** `add(2)` ->
`error[3061] expected 2 argument(s), found 1`; `add(1, 2, 3)` -> `error[3061] expected 2
argument(s), found 3`; `add(1, true)` -> `error[3000] ... source: bool / target: i32`;
`std.io.print()` -> `error[3061] expected at least 1 argument(s), found 0`; the indirect
fn-value path rejects the same shapes. Valid controls unchanged: exact-arity correct-type calls,
`@intCast`-based conversions, `u8` -> `i32` and `u32` <-> `usize` implicit calls, `@enumToInt(err)`
into `i32`, `system("cls")` (`*const [N]u8` -> `*const c_char`) and `std.io.print(<string>)`.

**Fixtures.** Reject `repro/mi_matrix/call_arity_reject_xmod` (`expected.rc` = 2; 5 sites —
`add(2)`, `add(1, 2, 3)`, `one(1, 2)`, `one()`, `std.io.print()`; 5 x `error[3061]`, class FAIL).
Reject `repro/mi_matrix/call_arg_type_reject_xmod` (`expected.rc` = 2; 3 sites — `add(1, true)`,
`takeBool(1)`, `takeF(i32)`; 3 x `error[3000]`, class GREEN). Positive runtime
`repro/mi_matrix/stdlib_call_arity_types_ok_xmod` (exact-arity i32 calls, i64 parameter,
`@intCast` into i8/usize, indirect fn-pointer call, bool parameter/return, `u8` -> `i32` control;
every check `@panic`-guarded; golden `s1=3 s2=0 i8v=100 us=4096 fp=42 s3=8 neg=1`, rc 0,
3x byte-exact and Zig-0.15.2-twin-matched) — stdlib pin **228 -> 229**. Standalone
`repro/call_arity_types.z98` (the three reported shapes).

**Oracle (Zig 0.15.2, one probe per site).** `add(2)` / `add(1, 2, 3)` / `one(1, 2)` / `one()` /
`printf()` -> `expected [at least] N argument(s), found M`; `add(1, true)` -> `expected type 'i32',
found 'bool'`; `takeBool(1)` -> `expected type 'bool', found 'comptime_int'`; `takeF(i32)` ->
`expected type 'f32', found 'i32'` (runtime-`i32` twin).

**Corpus movement (intended, oracle-backed).** `-s0` **1008 = 875 OK / 46 GREEN / 87 FAIL /
0 ICE / 0 CRASH**; join-diff vs the Task 13 fix-round baseline (1005 = 876 OK / 45 GREEN / 84 FAIL)
moves exactly the 3 new fixture dirs plus two pre-existing OK -> FAIL arity movements:
`repro/mi_matrix/ice_literal_overflow` and `repro/mi_matrix/comptime_u64_fold_overflow` — both call
a fixed 13-parameter `extern fn printf(...)` prototype with 5/6 arguments. Official Zig 0.15.2
rejects them (`expected 13 argument(s), found 5/6`), so the new `error[3061]` reject is the
Zig-matching outcome; both were gcc-only survivors of the pre-fix leniency. **Zero other movement.**

**Gates.** self-compile **moving point** hop1 `165a762cbfba63a610600233a0857111` != hop2 == hop3 ==
**`cd1b2fcfd0efca09dc136d0a0ac7e39e`** (explicit `FIXED_POINT_MD5=cd1b2fcf…` gate OK, deterministic
across two out-dirs); 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `4afb601f…` /
json `09fb55e5…` / mud `5a1cc65e…`, 2x each); std-lib runtime gate **229 PASS / 0 FAIL**; example
matrix **24/24**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test **0/9**
(pre-existing zig0 baseline); self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC. Seed stays **v83**
(operator R2: rotation is closeout-only).

## Task 13 fix round (C1/I1) — array-field `.len` + non-aggregate member rejects (v219 -> v220 2026-09-24)

**Review Critical C1.** The Task 13 `error[3060]` reject fired before the Task 11N `.len` recovery
for an array field with an aggregate element: a `b: [4]Point` field decays to `*Point`, the
auto-deref lands in the `struct_type` arm, `len` is not a field, and Phase 5 rejected. `.len` on
such a field is valid Z98 (and the lowerer handles it via `fieldStaticLenForBase`). Pre-fix
(`583e43c6`): `h.pts.len` rc=2 / 0 `.c` / `error[3060]`; base (`d290b3d7`): rc=0 built+ran.

**Review Important I1 (operator ruled: fold in).** A member access/call on a NON-aggregate value
was still silent: `const x: i32 = 5; x.foo();` compiled rc=0 and emitted `(void)zT_3();` — a call
to an undeclared temp (the original Task 13 failure class); `_ = e.nope` (enum) / `_ = es.nope`
(error set) were silent too. Official Zig 0.15.2 rejects every one.

**Fix.** `sf/src/semantic_analyzer.zig`: new `semanticAnalyzerArrayFieldLenCheck` (`.len` recovery
consulted in Phase 5 and the enum/error-set/`else` arms before any reject) and new
`semanticAnalyzerReportUnknownMember` (deduped `error[3060]`, ASCII message tail names the base
kind: struct/union/slice/array/enum/error-set/`type`), called from every "member not found" path.
The module arm is untouched (unknown module members keep their `error[3042]` lowering reject).

**Regression coverage.** `repro/mi_matrix/stdlib_method_syntax_ok_xmod` gains the C1 control: a
`Holder { pts: [2]Point, bytes: [3]u8, enums: [2]E, errs: [2]Err }`, `.len` on all four array
fields, `holder.pts[0].x`, and a `[]Point` slice of the aggregate-element field; every check
`@panic`-guarded; golden `free=9 x=3 px=3 nested=7 callx=5 union=11 tu=13 tag=0 enum=2 ptslen=2
byteslen=3 slicelen=2`, rc 0, 3x byte-exact, Zig-0.15.2-twin-matched. New reject fixture
`repro/mi_matrix/nonagg_member_reject_xmod` (8 oracle-rejected sites: `x.foo()`, `x.bar`, `b.foo`,
`s.foo`, `arr.foo`, `e.nope`, `es.nope`, `fl.nope`; rc 2, 0 `.c`, 8 x `error[3060]`, class FAIL).
`repro/method_syntax.z98` gains the `x.foo()` site (3 x `error[3060]`).

**Gates.** self-compile **moving point** hop1 `1b69e53365ab012c1e8ea2c33cc4185e` != hop2 == hop3 ==
**`14b78a59b806a3fc2b343abea450e894`** (explicit `FIXED_POINT_MD5=14b78a59…` gate OK, deterministic
across two out-dirs); 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `4afb601f…` /
json `09fb55e5…` / mud `5a1cc65e…`, 2x each); corpus `-s0` **1005 = 876 OK / 45 GREEN / 84 FAIL /
0 ICE / 0 CRASH** — vs the pre-fix-round Task 13 classification (1004 = 877 OK / 45 GREEN / 82 FAIL)
the join-diff moves EXACTLY two dirs, both INTENDED I1 consequences: the new
`nonagg_member_reject_xmod` FAIL (new dir) and the pre-existing `error_set_unknown_member`
**OK -> FAIL** (`fn f() E { return E.Zzz; }` with `E = error{A,B}` — an unknown error-set member
that was silently accepted rc=0 and emitted `return zT_1;`; official Zig 0.15.2 rejects it
`error: no error named 'Zzz' in 'error{A,B}'`, so the new `error[3060]` reject is the Zig-matching
outcome. That dir's historical 2026-07-16 "Class: OK (not fail)" note is superseded here; its name
is retained). **Zero other movement** — the pinned positive fixture stays OK;
std-lib runtime gate **228 PASS / 0 FAIL**; example matrix **24/24**; `check_emit_support.sh` 7/7;
`verify_upgraded.sh` CLOSEOUT OK; build_test **0/9** (pre-existing zig0 baseline); self-emission
rc 0 / 48 `.c` + 48 `.h` / no PANIC. Seed stays **v83** (operator R2, rotation is closeout-only).

## Task 13 (S1) — reject method-call syntax and unknown struct members (v218 -> v219 2026-09-24)

**SUPERSEDED in part by the Task 13 fix round above (v220): the fixed point is `14b78a59…`, the
corpus is 1005 dirs, the positive fixture golden gains `ptslen=2 byteslen=3 slicelen=2`, and the
`else`/enum/error-set arms now reject too (I1).**

**Defect.** Z98 forbids method syntax — `struct.func()` is not supported; use `func(struct)`
(`docs/reference/Language_Spec_Z98.md` §5 "No Method Syntax"; `docs/sf/AGENTS.md`). But a member
call on a struct value (`nine.square()`) compiled rc=0 with **no error diagnostic**:
`semanticAnalyzerResolveFieldAccess` returned `TYPE_VOID` silently when a struct's member was not
found, so the call lowered to an indirect call with an undeclared callee temp
(`zT_8 = zT_7();`). The C89 compile passed via an implicit function declaration and the **link**
failed (`undefined reference to 'zT_7'`). A plain unknown member (`nine.nope`) was silently typed
`void` too. Pre-fix (`d290b3d7` seed build): `method_syntax_reject_xmod` rc=0 / 4 `.c` / 0 errors;
`repro/method_syntax.z98` rc=0 / 4 `.c` / gcc `'zT_8' undeclared`.

**Fix.** `sf/src/semantic_analyzer.zig`'s `semanticAnalyzerResolveFieldAccess` Phase 5 (member not
found on a `struct_type`/`union_type`/`packed_union_type`/`tagged_union_type` base) now emits the
new level-0 `error[3060]` (`ERR_3060_METHOD_SYNTAX_NOT_SUPPORTED` in
`sf/src/diagnostics.zig`) with message `no field or member function named '<name>' in
struct/union type`, deduped per node via `diagnosticCollectorMarkNodeOnce`, and returns
`TYPE_VOID`. rc=2, 0 `.c`. Official Zig 0.15.2 rejects every site
(`no field or member function named 'square' in 'Point'` / `no field named 'nope' in struct`).
Valid free-function calls (`square(nine)`), real field accesses (value / pointer / nested /
call-result), union fields, tagged-union fields + `.tag`, enum members and error-set members are
unchanged (diagnostics and emitted C byte-identical to the base compiler on the all-valid-shapes
probe).

**Fixtures.** Reject: `repro/mi_matrix/method_syntax_reject_xmod` (8 sites: `nine.square()`,
`nine.nope`, `p.square()`, `outer.inner.area()`, `makePoint().square`, `u.nope`, `tu.nope`,
`Point.square`; rc=2, 0 `.c`, 8 x `error[3060]`; class FAIL). Positive runtime control:
`repro/mi_matrix/stdlib_method_syntax_ok_xmod` (stdlib pin **227 -> 228**; golden
`free=9 x=3 px=3 nested=7 callx=5 union=11 tu=13 tag=0 enum=2`, rc 0, 3x byte-exact and
Zig-0.15.2-twin-matched). Standalone `repro/method_syntax.z98` (rc 2 / 0 `.c` / 2 x `error[3060]`).

**Gates.** self-compile **moving point** hop1 `ba6ff1d4be52652125a5947882f1696b` != hop2 == hop3 ==
**`7c9a1dc0e3a1e7bacd00bc53eb3f07f1`** (explicit `FIXED_POINT_MD5=7c9a1dc0…` gate OK, deterministic
across two out-dirs); 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `4afb601f…` /
json `09fb55e5…` / mud `5a1cc65e…`, 2x each); corpus `-s0` **1004 = 877 OK / 45 GREEN / 82 FAIL /
0 ICE / 0 CRASH** (join-diff vs the pre-fix Task 11 fix-round classification = exactly the 2 new
fixture dirs, **zero other movement**); std-lib runtime gate **228 PASS / 0 FAIL**; example matrix
**24/24**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test **0/9**
(pre-existing zig0 baseline); self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC / memory
`pool=17785K`. Seed stays **v83** (operator R2, rotation is closeout-only).

**Residual (out of scope at the base commit; RESOLVED by the Task 13 fix round above).** An
unknown member on an enum value / error set / non-aggregate base still resolved silently to
`TYPE_VOID` at `583e43c6` (the base reject covered aggregate types only); the fix round extends the
same `error[3060]` reject to those bases (I1).

## Task 11 fix round — for-header evaluation order (v217 -> v218 2026-09-24)

**Review Important I1.** `sf/src/lower.zig`'s explicit-index arm lowered the range `start`/`end`
operands BEFORE the iterable. Zig 0.15.2 evaluates the for-header inputs in source order
(iterable, then start, then end), so the pre-fix order was a silent, observable divergence for
valid programs with side-effecting header expressions.

**Probe (`order.zig`, both compilers rc 0).** `tickA()` returns the iterable and appends `1` to a
global order value, `tickB()` appends `2` (start), `tickC()` appends `3` (end):

* Zig 0.15.2 twin: stdout `80 123` (source order).
* pre-fix Z98 (`6dbfb462`): stdout `80 231`, emitted C calls `tickB`/`tickC` before `tickA`.
* fixed Z98: stdout `80 123`, emitted C calls `tickA`, `tickB`, `tickC` in order.

**Fix.** The `else` (array/slice) branch of the `for_stmt` arm now lowers `iter_node` first, then
`idx_start_node`, then `idx_end_node` (`sf/src/lower.zig`, three statements moved; no other change).

**Regression coverage.** The order row was added to `repro/mi_matrix/stdlib_for_index_range_xmod`
(module-level `g_order` + `tickA`/`tickB`/`tickC`; `@panic` unless `g_order == 123`, `osum == 80`)
and to `repro/for_index_range.z98`; the fixture golden is now
`60 2 6 5 60 7 11 60 1 5 60 10 60 10 60 25 0 34 3 70 6 123 80` (rc 0, 3x byte-exact, full
Zig-0.15.2 twin re-matched, stderr md5 `e3ccbc98dbf0cbec764237d175ab7b26`). The reject fixture is
unchanged.

**Gates.** fixed point **MOVED `0fdee6ac…` → `f44e2c15c827c469620996fc99cf991c`** (moving point
hop1 `1b6843cd…` != hop2 == hop3; explicit `FIXED_POINT_MD5=f44e2c15…` OK); 4-MD5 emitted-C
**UNCHANGED** (gol `e7bde571…` / lisp `4afb601f…` / json `09fb55e5…` / mud `5a1cc65e…`, 2x each);
corpus `-s0` **1002 = 876 OK / 45 GREEN / 81 FAIL / 0 ICE / 0 CRASH** (join-diff vs the pre-fix
Task 11 classification **zero movement**); std-lib runtime gate **227 PASS / 0 FAIL**; example
matrix **24/24**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test **0/9**
(pre-existing zig0 baseline); self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC. Seed stays
**v83** (operator R2, rotation is closeout-only).

## Task 11 — explicit index-range `for (arr, start..end)` (v216 -> v217 2026-09-24)

**SUPERSEDED by the Task 11 fix round above (v218): the fixture golden now ends `123 80`, the fixed
point is `f44e2c15…`, and the header evaluation order is source order (iterable, start, end).**

**Gap.** Zig 0.15.2's explicit index form (`for (arr, start..) |item, index|` /
`for (arr, start..end) |item, index|`) was a parser gap: Z98 rejected the `,` with `error[2000]`
(the `range_inclusive` branch in `lower.zig` was dead), and only the plain `for (arr) |x, i|` form
existed.

**Implementation.** Parser (`sf/src/parser.zig` `parserParseForStmt`): after the iterable, a `,`
introduces the index range — `start` then `..` with an optional end; the new
`AstKind.for_index_range` pattern node (child_0 = iterable, child_1 = start, child_2 = end or 0) is
appended at the end of the `AstKind` enum (`sf/src/ast.zig:112`). Sema
(`semantic_analyzer.zig` `semanticAnalyzerResolveForIndexRange`): the pattern types as its
iterable; bounds must be `usize`-compatible unsigned integers (a literal, or an unsigned int whose
width fits the 32-bit target `usize`); a comptime-known bound must fit `usize`; a comptime-known
span != a fixed array's length is the Zig "non-matching for loop lengths" reject; a comptime-known
`end < start` is the Zig overflow reject; an index range without an index capture is the Zig "for
input is not captured" reject. Lowering (`sf/src/lower.zig` for_stmt arm): the iterable lowers
exactly as the plain form, the 0-based sequence counter drives the iteration (`j < len`), the index
capture is `start + j` (no clamping — Zig semantics), and `start..end` computes a checked `usize`
span (under `-fsafe` an `end < start` underflow traps, Zig's integer-overflow panic) plus an
`-fsafe`-only `span == len` trap (`check_trap{kind=8}`; Zig's ReleaseFast disables the check too).

**Oracle evidence (Zig 0.15.2).** `for (arr, 5..)` / `for (arr, 7..)` iterate every element with
indices 5..9 / 7..11 (no clamping); a runtime `start=1,end=4` on a length-5 array panics "for loop
over objects with non-equal lengths"; `start=5,end=2` panics "integer overflow"; literal `1..4` /
`3..2` are compile errors; an empty peer with `0..0` iterates zero times; `f64` and `i32` bounds
reject ("expected type 'usize'"); `u32`/`u64`/`u40` runtime bounds accept on x86_64 (64-bit
`usize`).

**Fixtures.** Positive runtime `repro/mi_matrix/stdlib_for_index_range_xmod` (array + slice;
runtime and literal bounds; open `..` and explicit `..end`; `start > len`; literal offset; empty
slice `0..0`; `continue`/`break`; the `for (arr) |x, i|` and `for (0..n) |i|` controls; golden
`60 2 6 5 60 7 11 60 1 5 60 10 60 10 60 25 0 34 3 70 6`, rc 0, 3x byte-exact and
Zig-0.15.2-twin-matched; stdlib pin **226 -> 227**) + reject fixture
`repro/mi_matrix/for_index_range_reject_xmod` (six sites: literal length mismatch, comptime
negative bound, `i32` runtime bound, empty span on a non-empty array, `end < start`, missing index
capture; rc 2, 0 `.c`, 6 x `error[3000]`, GREEN) + standalone `repro/for_index_range.z98`
(`-ffast` and `-fsafe` byte-identical for every valid range). Runtime-trap probes: a runtime
mismatch and a runtime `end < start` both trap rc 133 under `-fsafe`.

**Gates.** self-compile **moving point** hop1 `14bebcbe…` != hop2 == hop3 ==
`0fdee6acaf88360534b930c86fbaad7f`; 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp
`4afb601f…` / json `09fb55e5…` / mud `5a1cc65e…`, 2x each); example matrix **24/24**; std-lib
runtime gate **227 PASS / 0 FAIL**; corpus `-s0` **1002 = 876 OK / 45 GREEN / 81 FAIL / 0 ICE /
0 CRASH** (join-diff vs the pre-change compiler = exactly the 2 new fixture dirs: positive
FAIL->OK, reject FAIL->GREEN); `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK;
build_test **0/9** (pre-existing zig0 baseline); self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC;
memory `track-memory: perm=883K mod=1020K scr=1024K pool=19001K type_db=499K total=2927K`. Seed
stays **v83** (operator R2, rotation is closeout-only).

**Residual (bounded, documented).** A runtime unsigned bound wider than 32 bits (u33..u64) is a
clean `error[3000]` reject (`usize` is 32-bit on the Z98 target; the x86_64 oracle accepts it
because its `usize` is 64-bit). Zig's multi-object `for (a, b) |x, y|` stays unsupported (parser
error, out of scope), and an explicit index range over a range iterable (`for (0..5, 0..) |x, i|`)
is also a parser `error[2000]` (Zig 0.15.2 accepts it).

## Task 10 fix round — over-rename narrowing + authorized 4-MD5 re-baseline (v215 -> v216 2026-09-24)

**Ruling.** The Task 10 review left the `maybeDisambiguateCapture` over-rename open; the operator
authorized the narrowing fix AND the re-baseline of the gate dumps it moves, with runtime-identity
proof by execution.

**Fix (`sf/src/lower.zig`).** `maybeDisambiguateCapture` now renames only when an earlier same-named
declaration has a **different type** (`self.local_decl_types[eli] != variant_type_id` — the previously
unused parameter): same-type same-name bindings may share the emitted C variable (the emitter dedupes
`decl_local` by `name_id` across the function and sibling-scope lifetimes never overlap), while
different types cannot — the criterion mirrors `maybeDisambiguateCaptureIfTypeDiffers` and the
var-decl `type_rename` path. Task 10D's scope-chain redirect guard is untouched; the per-function reset
from `4109fd71` scopes the scan, so no fn_seq filter is needed.

**Coverage.** `repro/mi_matrix/stdlib_capture_sibling_reuse_xmod` re-run **PASS** (golden unchanged);
`repro/capture_fn_reuse.z98` re-run 3× byte-exact and Zig-0.15.2-twin-matched
(`fa=7 fb=6 fc=3 fd=9 ff=3 fg0=102 fg1=9 fi=20`, md5 `85dd7796…`). No new corpus dirs; stdlib pin
unchanged (226).

**4-MD5 re-baseline (authorized; identifier-only diffs).** gol `e7bde571649a67291419ce57131a556a`
**UNCHANGED** / mud `5a1cc65ef23f27d1c4c51f4516760c07` **UNCHANGED**; lisp
`353887639f127f4624de8b14b7e43a78` -> **`4afb601f28e15bcb60d4b896cc2684e3`** (−401 B; 89 changed
lines); json `5e1e0050c0c462d76e9ef8dee3f5ae7c` -> **`09fb55e5fc3f846f4602d3b2eef30970`** (−53 B;
18 changed lines). Runtime identity PRE (Task 10 `3f31c1c2…`) ↔ POST proven by execution: gol stdout
`fcbf7e7cead5082f0a8caadd5a8f0ff9` rc 0; json stdout `8bda3d5a1ec07d14a301bc343df32bf8` rc 0; lisp
`(+ 1 2)` stdout `b3d9f8974da24ddbf9d389f3d7d97322` rc 0 + canonical feed stdout
`96654b3910a54d8bb7ec3ddfc0f26c6a` rc 0; mud `demo/session.sh` server
`66c8f0abb926cca7baf9a0d1692ab318` / client `93147d0f0bbd983a9d844fea8b7a6fa7`, session rc 0 — all
PRE == POST byte-identical.

**Gates.** self-compile **moving point** hop1 `e58be1fd…` ≠ hop2 == hop3 ==
`249b38be5c95ebc0f148ae323262201d` (explicit `FIXED_POINT_MD5=249b38be…` gate OK); example matrix
**24/24**; std-lib runtime gate **226 PASS / 0 FAIL**; corpus `-s0` **1000 = 875 OK / 44 GREEN /
81 FAIL / 0 ICE / 0 CRASH** — full-classifier join-diff vs the pre-Task-10 compiler **byte-identical
(zero movement)**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test **0/9**
(pre-existing zig0 baseline); self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC. Seed stays **v83**
(operator R2, rotation is closeout-only).

## Task 10 — capture/lifetime bookkeeping hygiene (v214 -> v215 2026-09-24)

**Decision (no behavior change for valid programs).** Three residuals from the Task 10C investigation,
decided and implemented in `sf/src/lower.zig` + `sf/src/util/hash.zig`:
(1) the eight arm-end `capture_shadow.count = 0` stores were dead writes (`u32ToU32MapGet` scans the
`occupied` flags and ignores `count`) — **DELETED**;
(2) the `capture_shadow` map is now explicitly function-scoped: the new `u32ToU32MapClear` (a real
clear — zeroes `occupied` + `count`) is called together with `local_decl_count = 0` in `lowerFn`'s
entry. `main.zig` already creates a fresh `LirLowerer` per `fn_decl`, so the production path is
unchanged; the explicit reset makes `lowerFn` self-contained for the unit-test caller, which reuses
one lowerer across functions. A mid-function clear was NOT adopted — Task 10C proved it regresses the
capture-referenced-after-nested-loop shape;
(3) `maybeDisambiguateCapture`'s conservative over-rename (ANY earlier same-name declaration forces a
synth name, including closed sibling scopes) is **KEPT**: it is semantically neutral and narrowing it
would churn the emitted C of gate programs (e.g. json_parser's `item_1`/`i_2`), violating the
no-behavior-change constraint. **SUPERSEDED by the Task 10 fix round above (v216): the over-rename is
now type-gated and the two moved 4-MD5 rows are re-baselined under the operator's authorization, with
PRE↔POST runtime identity proven by execution.**

**Coverage.** New standalone `repro/capture_fn_reuse.z98` (cross-function reuse: renamed capture in
`fa`, later plain local `j` in `fb`, clean capture in `fc`, parameter `j` in `fd`, `if` capture in
`ff`, `catch |err|` in `fg`, `for (arr) |x, i|` index capture in `fi`; `@panic`-guarded golden
`fa=7 fb=6 fc=3 fd=9 ff=3 fg0=102 fg1=9 fi=20`, rc 0, 3x byte-exact, Zig-0.15.2 oracle-matched) +
the Task 10D fixture `stdlib_capture_sibling_reuse_xmod` re-run PASS. No new corpus dirs and no
stdlib-pin change.

**Gates.** self-compile two-hop closure hop1 == hop2 == `3f31c1c20f085f840f7d52dff89411e5`; explicit
`FIXED_POINT_MD5=3f31c1c2…` gate OK; 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp
`35388763…` / json `5e1e0050…` / mud `5a1cc65e…`); example matrix **24/24**; std-lib runtime gate
**226 PASS / 0 FAIL** (pin unchanged); corpus `-s0` **1000 = 875 OK / 44 GREEN / 81 FAIL / 0 ICE /
0 CRASH** — full-classifier join-diff vs the pre-fix seed compiler **byte-identical (zero movement)**;
`check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test **0/9** (pre-existing zig0
baseline); self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC. Seed stays **v83** (operator R2,
rotation is closeout-only).

## Task 9 fix round 1 — `ciSignificantBits` multi-limb correction (v213 -> v214 2026-09-24)

**Critical (review).** The Task 9 `ciSignificantBits` counted only the TOP limb's bits and then
subtracted 32 per zero lower limb, so it undercounted multi-limb magnitudes (`2^64 + 1` -> 1,
`2^53 + 1` -> 22, `2^32 + 1` -> 1) and u32-underflowed on a power of two >= 2^32. Consequences:
(a) over-acceptance — `if (((1 << 64) + 1) == 18446744073709551616.0) 1;` is `error[3059]`
pre-Task-9 and in Zig 0.15.2, but the buggy fold accepted it and emitted `x = 1`; (b) a
folded-false empty-else miscompile — `const TU: u64 = 9007199254740993;
if (TU > 9007199254740992.0) 1;` folded FALSE and materialised an uninitialized temp where Zig
yields `1`; (c) false declines for exactly-representable powers of two (`(1 << 32) > 1.0`,
`1 << 63`, `1 << 64`, `1 << 255`).

**Fix.** `ciSignificantBits` now computes `bitlen(magnitude) - trailing_zeros` (`32 * (len - 1)`
plus the top limb's bit count, minus the separately accumulated trailing-zero count).

**Coverage (Important).** `stdlib_comptime_float_compare_xmod` gains the multi-limb rows
(`(1 + 1) == 2.0`, `(1 << 32) > 1.0`, `(1 << 63) > 1.0e18`, `(1 << 64) > 1.0e19`,
`(1 << 64) == 18446744073709551616.0`, typed `P32`/`P63` u64 consts; 30 values, golden 4 lines) and
the new reject fixture `comptime_float_compare_reject_xmod` pins the three Zig-false over-acceptance
sites (`((1 << 64) + 1) == / <= 2^64.0`, `((1 << 53) + 1) == 2^53.0`) at rc 2 / 3 x `error[3059]` /
0 `.c`.

**Gates (fix-round values).** self-compile two-hop closure hop1 == hop2 ==
`e809cf6113088dcd20ea18aeef5ea9e6`; explicit `FIXED_POINT_MD5=e809cf61…` gate OK; 4-MD5 emitted-C
**UNCHANGED** (gol `e7bde571…` / lisp `35388763…` / json `5e1e0050…` / mud `5a1cc65e…`); example
matrix **24/24**; std-lib runtime gate **226 PASS / 0 FAIL** (pin unchanged); corpus `-s0`
**1000 = 875 OK / 44 GREEN / 81 FAIL / 0 ICE / 0 CRASH** — join-diff vs the buggy `a059fa89…`
compiler = exactly `comptime_float_compare_reject_xmod` OK->FAIL +
`stdlib_comptime_float_compare_xmod` FAIL->OK, zero other movement; `check_emit_support.sh` 7/7;
`verify_upgraded.sh` CLOSEOUT OK; build_test 0/9; self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC.
Fixed point moved `a059fa89b151c0f4363e926fc8366505` -> `e809cf6113088dcd20ea18aeef5ea9e6`; seed
stays v83 (R2). **The Task 9 section below is the original commit's record; its 23-value fixture /
`999 = 875/44/80` / fixed point `a059fa89…` claims are superseded by this fix round.**

## Task 9 — comptime float comparisons (v212 -> v213 2026-09-24)

**Defect.** `comptimeEvalCompare` returned null whenever an operand was float-valued, so a
comptime-true float condition never folded and a no-`else` value `if` was rejected `error[3059]`
(e.g. `var x: i32 = if (0.5 < 1.0) 1;`), while official Zig 0.15.2 folds it and accepts.

**Fix (Task 9; `sf/src/comptime_eval.zig`).** `comptimeEvalCompare` keeps the exact integer
`ciCmp` path when both operands are integer/bool and otherwise calls the new
`comptimeEvalCompareFloat`: the float sub-evaluator supplies each float operand at the established
f64 precision (a typed `f32` rounds through f32 first), and an INTEGER operand participates only
when exactly representable in the peer significand (new `ciSignificantBits`; <= 53 bits for an
f64/`comptime_float` peer, <= 24 for f32), so the folded verdict is the mathematical comparison Zig
folds. Peer rules (oracle-checked, Zig 0.15.2): a typed f64 operand makes the peer f64 (an f32
widens exactly); a typed f32 peer folds an untyped operand only when its f64 value is exactly
f32-representable (`comptimeEvalF64IsF32Exact`; Z98's emitted C widens to double, so rounding
would fold a verdict the runtime never computes); no typed float operand evaluates at f64. New
helpers `CmpFloatOperand`, `comptimeEvalCompareOperand`, `comptimeEvalFloatBits`,
`comptimeEvalF64IsF32Exact`, `comptimeEvalFloatOperandType`; `comptimeEvalFloat`'s ident arm now
consults the function-local const scope first.

**Fixtures.** New positive runtime fixture `repro/mi_matrix/stdlib_comptime_float_compare_xmod`
(23 values at this commit — **superseded by fix round 1: 30 values** — all six operators
literal/literal, exponent + `-0.0`, untyped int vs float + an
arithmetic-derived int, module/local f64 consts, typed f32 (f32-vs-f32, f32-vs-f32-exact literal,
f32-vs-int), `@intToFloat(f64,…)`, `@floatCast(f64, <f32>)`, logicals, an integer-comparison
control + four runtime-`if` false-condition controls; every value `@panic`-guarded; golden
`101 … 123` / `f1=0` / `float compare ok`, rc 0, 3x byte-exact and Zig-0.15.2-twin-matched; stdlib
pin **225 -> 226**) + standalone `repro/comptime_float_compare.z98`. RED pre-fix: `error[3059]`
(rc 2) on the fixture's first float condition and on the standalone.

**Gates.** self-compile two-hop closure hop1 == hop2 == `a059fa89b151c0f4363e926fc8366505` (was
`4a7ea965…`; **superseded by fix round 1: `e809cf61…`**); 4-MD5 emitted-C **UNCHANGED** (gol
`e7bde571…` / lisp `35388763…` / json `5e1e0050…` / mud `5a1cc65e…`); example matrix **24/24**;
std-lib runtime gate **226 PASS / 0 FAIL**; corpus `-s0` **999 = 875 OK / 44 GREEN / 80 FAIL /
0 ICE / 0 CRASH** (**superseded by fix round 1: 1000 = 875/44/81**) (full-classifier
join-diff vs the pre-fix seed v83 compiler = exactly the new fixture dir, FAIL->OK); the
integer-comparison fixtures `stdlib_comptime_compare_xmod` + `repro/comptime_compare.z98`
unchanged. Bounded residuals: an f32 operand against a non-f32-exact untyped literal declines (Zig
peer-rounds it to f32); an integer with more significant bits than the peer's significand declines
(Zig compares exactly); `comptime_float` literals compare at f64, not Zig's f128.

## Task 8 — void/value-`if` statement residuals (v211 -> v212 2026-09-24)

**Defects (pre-existing; carried from Task 9D).** (i) `_ = foo();` — discarding a void call — ICEd
with `error[3043]: internal: invalid temp index 0 (len 0)`. A known-direct void call lowers with
result temp 0 (its "no result" marker, not the void-`if` `TEMP_NONE` sentinel), and the
`plain_assign` path ran `getTempType(self, 0)` on it: out of bounds while the temp table was still
empty, and with a non-empty table a spurious `(void)zT_0;` naming an unrelated temp. (ii)
`return if (c) foo();` — a void `if` returned from a void function — compiled rc=0 but emitted
gcc-invalid C (`return zT_4294967295;`, the `TEMP_NONE` sentinel). (iii) fix round
(v211 -> v212; review Important, operator ruling "fix it now in Task 8"):
`fn f(c: bool) !void { return if (c) foo(); }` — the same void `if` returned from an
error-union(void) function — ICEd (`error[3043] invalid temp index 294967295`): `lowerExpr`'s
coercion wrapper applied the recorded void -> `!void` coercion to the `TEMP_NONE` sentinel, so
`materializeInto` dereferenced it with `getTempType` before `return_stmt` was reached.

**Fix (Task 8).** `sf/src/lower.zig`, three sites. (i) `plain_assign` skips the l-value store when the
lowered RHS is the `0` no-value marker and the RHS resolved type is `TYPE_VOID` (the expression is
already lowered into the current block). (ii) `return_stmt` emits `emitValuelessReturn`
(`.ret_void`, or the error-union(void) `wrap_error_ok`) when the return operand is `TEMP_NONE`,
instead of `.ret` on the sentinel. (iii) fix round: `lowerExpr`'s coercion wrapper skips the recorded
coercion when the lowered result is `TEMP_NONE` (a sentinel-aware guard mirroring (i)/(ii)); the
consumer handles the sentinel, so the EU(void) return walks the normal `emitValuelessReturn` path.

**Fixtures.** New positive runtime fixture `repro/mi_matrix/stdlib_void_temp_stmt_xmod` (the reported
empty-temp-table `_ = foo();` + `_ = { foo(); };` + void value-`if` discards + a void call statement
and a non-void `_ = bar();` discard (controls) + `return if (c) foo();` true/false + `return if (c)
foo() else baz();` true/false + `return foo();` (control); fix round adds the EU(void) forms
`fn f() !void { return if (c) foo(); }` and `return if (c) foo() else baz();`, true/false; every
aggregate `@panic`-guarded; golden `hits=220` (was `hits=118`), rc 0, 3x byte-exact and
Zig-0.15.2-twin-matched; stdlib pin **224 -> 225**) + standalone `repro/void_temp_discard.z98` /
`repro/void_return_if.z98`. RED pre-fix: `error[3043] invalid temp index 0 (len 0)` (fixture +
discard repro); emitted `return zT_4294967295;` with gcc `'zT_4294967295' undeclared` (return-if
repro); `error[3043] invalid temp index 294967295 (len 1)` (EU(void) probe).

**Gates (fix-round values).** self-compile two-hop closure hop1 == hop2 ==
`4a7ea9654dcfff5a9fae25a683c698ff` (was `91e9e16d…`); 4-MD5 emitted-C **UNCHANGED** (gol
`e7bde571…` / lisp `35388763…` / json `5e1e0050…` / mud `5a1cc65e…`, 2x each); example matrix
**24/24**; std-lib runtime gate **225 PASS / 0 FAIL**; corpus `-s0` **998 = 874 OK / 44 GREEN /
80 FAIL / 0 ICE / 0 CRASH** with a full-classifier join-diff vs the pre-fix seed v83 compiler moving
EXACTLY the new fixture dir (`stdlib_void_temp_stmt_xmod` ICE -> OK); `check_emit_support.sh` 7/7;
`verify_upgraded.sh` CLOSEOUT OK; build_test 0/9 (pre-existing zig0 baseline); self-emission rc 0 /
48 `.c` + 48 `.h` / no PANIC. Fixed point **MOVED `49a75cf0…` -> `91e9e16d…` (Task 8) ->
`4a7ea9654dcfff5a9fae25a683c698ff` (fix round)**; seed stays **v83** (NOT rotated — operator R2:
rotation is closeout-only).

**Residual (pre-existing, distinct; NOT fixed).** A void `catch` block that lowers to a real temp
(e.g. the compiler's own `std_debug.zig` `_ = writeCoreDump(...) catch {};`) keeps its pre-existing
store — the narrowing that keeps the 4-MD5 gates byte-identical.

## Task 7 — one-argument `@intCast` on a loop capture (v209 -> v210 2026-09-24)

**Defect (pre-existing; found by the Task 10C review).** A one-argument `@intCast(expr)` — the
official Zig 0.15.2 form, whose target is inferred from context — was typed by sema's
single-argument builtin fallback as the operand's own type, but the lowering `builtin_call` arm's
cast block is guarded on `ec_n >= 2`, so the call fell through to the `TYPE_VOID` default and
emitted NO instruction; the emitter never declares void temps, so the consumer referenced an
undeclared `zT_<n>` (emit rc=0, no diagnostic, gcc `'zT_6' undeclared`). Reported shape:
`@intCast(<for-range capture>)` inside the capture's own loop; the hole was general (a non-capture
local, a call result, a copy of the capture all failed pre-fix).

**Fix (Task 7).** `sf/src/lower.zig`'s `builtin_call` arm: before the `ec_n >= 2` cast block, a
one-argument `@intCast` lowers and returns its operand's temp (`lowerExpr(extra_child_0)`); the
consumer applies any context conversion, matching sema's inferred operand type.

**Fixtures.** New positive runtime fixture `repro/mi_matrix/stdlib_intcast_loop_capture_xmod` (the
reported range-capture shape + a renamed capture (an earlier sibling scope declares the same name)
+ a copy of the capture + a non-capture local + a parameter/return-position `@intCast` + a
nested-loop outer capture + an array-element capture; every check `@panic`-guarded; golden
`cap=6 ren=8 cpy=3 loc=2 nest=2 sl=6`, rc 0, 3x byte-exact and Zig-0.15.2-twin-matched; stdlib pin
**223 -> 224**) + standalone `repro/intcast_loop_capture.z98`. RED pre-fix: emit rc=0 with 6
undeclared `zT_<n>` gcc failures.

**Gates.** self-compile two-hop closure hop1 == hop2 == `49a75cf036acef9aca242d4255646b8e`; 4-MD5
emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `35388763…` / json `5e1e0050…` / mud `5a1cc65e…`);
example matrix **24/24**; std-lib runtime gate **224 PASS / 0 FAIL**; corpus `-s0` **997 = 873 OK /
44 GREEN / 80 FAIL / 0 ICE / 0 CRASH** with a full-classifier join-diff vs the pre-fix seed v83
compiler moving EXACTLY the new fixture dir (`stdlib_intcast_loop_capture_xmod` FAIL -> OK);
`check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test 0/9 (pre-existing zig0
baseline); self-emission rc 0 / 48 `.c` + 48 `.h` / no PANIC. Fixed point **MOVED
`1e389c5739aea89550d149015f0031d3` -> `49a75cf036acef9aca242d4255646b8e`**; seed stays **v83** (NOT
rotated — operator R2: rotation is closeout-only).

**Residual (bounded; documented).** A narrowing context (`var x: u8 = @intCast(q)` with `q: u32`)
keeps sema's operand type, so the compiler's strict-coercion rules apply instead of Zig's target
inference. Distinct root cause from the two-argument `@intCast(T, expr)` form, which is unchanged.

## Task 6 — comptime-int core Part I closeout (v209; NO BUMP, 2026-09-24)

Part I (Step 0 + Tasks 1–5) of `docs/superpowers/plans/2026-09-22-z98-comptime-int-parity-plan.md`
is COMPLETE. The closeout re-verified this manifest's expectations with the Part-I final compiler
(fixed point `1e389c5739aea89550d149015f0031d3`): the frozen Step-0 35-shape table (28 accepted
shapes all Zig-0.15.2-equal, 7 preserved rejects), 4-MD5 emitted-C unchanged, corpus `-s0`
996 = 872 OK / 44 GREEN / 80 FAIL / 0 ICE / 0 CRASH (zero class movement vs Task 5),
stdlib 223 PASS / 0 FAIL, example matrix 24/24. **No version bump**: Task 6 changes no fixture
expectation and no fixture class. The retired divergence is recorded in
`docs/reference/Language_Spec_Z98.md` §7.2 and `sf/docs/tech_docs/04_comptime_eval.md`: the Task 9D
bounded divergence is gone, and float comparison folding was **pending Part II Task 9** (landed in
Task 9; see the Task 9 and Task 19 sections).
Seed rotated v82 → v83 at this closeout.

## Task 5 — fold-consumer migration: exact array-size / enum-initializer folds (v208 -> v209 2026-09-23)

**What.** `sf/src/type_resolver.zig`'s two remaining 64-bit evaluators are re-pointed at the
Task-2 `ComptimeInt` core (Task 1 §6.5). New private `evalConstIntFull` (the exact fold, shared by
both public wrappers; deliberate mutual import with `comptime_eval.zig`) + `evalConstIntToSize`.
`evalConstU32Full` (array sizes) keeps the `0xFFFFFFFF` sentinel, the depth cap (16) and its
`@intCast` `error[3000]` arm (now on the exact fit primitive); `evalConstI64Full` (enum member
values) materialises the exact value through the `[i64 min, u64 max]` window into the
two's-complement i64 storage. `intValueFitsType` / `evalConstSignClass` / `EvalSignClass` are
DELETED (the `wb >= 64` syntactic sign-class hack is gone — the exact value decides).

**Verdict changes (all Zig-0.15.2-oracle-checked).**
- Array sizes now fold shifts/bitwise/parens and >64-bit intermediates reduced back into range:
  `[1 << 4]u8` = 16, `[(2 + 1) * 2]u8` = 6, `[3 & 3]u8` = 3, `[MSHIFT]u8` = 32
  (`const MSHIFT: u64 = 1 << 5;`), `[@intCast(u64, 1 << 6)]u8` = 64,
  `[(1 << 200) >> 190]u8` = 1024 — all previously `error[3050]`.
- Enum initializers are exact: `enum(u64) { A = (1 << 200) >> 190, B }` folds 1024/1025 (was
  `error[3055]`); `enum { A = 18446744073709551615 + 1 }` and
  `enum(u64) { A = 18446744073709551615 * 2 }` are clean `error[3055]` (the old wrappers stored
  `0` / `2^64 - 2` silently; Zig rejects both).
- Unchanged: `[0 - 1]u8` / `[4000000000 + 400000000]u8` are `error[3050]`; `[1 << 40]u8` stays the
  sentinel (Z98's array length field is u32 — bounded, documented); `[@intCast(u8, 300)]u8` keeps
  `error[3000]` + the `error[3050]` cascade; the enum cast-range rejects
  (`enum_init_cast{_64}_range_reject_xmod`) keep `error[3055]`.

**Fixtures.** New positive runtime `repro/mi_matrix/stdlib_comptime_constfold_exact_xmod`
(oracle-matched twin `/tmp/task5/oracle/constfold_twin.zig`; stdout `16 6 3 32 64 1024` /
`1024 1025 4096 4097 2 3`; stdlib pin 222 -> 223) and new reject
`repro/mi_matrix/comptime_constfold_reject_xmod` (2 × `error[3055]` enum wraps, `error[3000]` +
`error[3050]` cast size, `error[3050]` over-u32 size; clean-reject GREEN). Standalone repros
`repro/comptime_constfold_exact.z98` (3× byte-exact, rc 0) and
`repro/comptime_constfold_reject.z98` (rc=2, 0 `.c`, 2 × `error[3055]`). RED on the Task 4
fix-round compiler: the positive fixture failed to emit (1 × `error[3055]`; the array shapes
`error[3050]`), and `repro/comptime_constfold_reject.z98` compiled silently (rc=0, 630 B `.c`).

**Corpus.** `-s0` **996 dirs = 872 OK / 44 GREEN / 80 FAIL / 0 ICE / 0 CRASH** (v208 994 =
871/43/80). Full-classifier join-diff vs the Task 4 fix-round final: exactly the two new fixture
dirs (`stdlib_comptime_constfold_exact_xmod` OK, `comptime_constfold_reject_xmod` GREEN); **zero
class movement on all 994 common dirs**.

**Other gates.** 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `35388763…` / json
`5e1e0050…` / mud `5a1cc65e…`, 2× each); stdlib **223 PASS / 0 FAIL** (pin 222 -> 223); example
matrix 24/24 (`examples/z98/*` all OK in the classifier); frozen Step-0 35-shape table
**byte-identical** to the Task 4 final; `check_emit_support.sh` 7/7; `verify_upgraded.sh`
CLOSEOUT OK; `build_test.sh` **0/9** (pre-existing zig0 baseline); self-emission rc 0 /
0 `error[...]` / no PANIC; `track-memory: perm=883K mod=1020K scr=1024K pool=18793K type_db=490K
total=2927K`. Fixed point **MOVED `a8ea33f75f239f2255adeb8cc2426a7c` →
`1e389c5739aea89550d149015f0031d3`** (two-hop closure hop1 == hop2; seed stays v82, NOT rotated
per R2). Bounded divergences documented (spec §7.2 + docs 03/04): `const BIGFOLD = 1 << 100;`
rejects `error[3000]` where Zig accepts; `(~u) == 4294967295` wrapped-complement false-reject;
over-u32 array sizes reject; the Task 4 review residuals (literals >= 2^64 clamp, `+%`, module
annotated `i8` const, runtime-typed optional payloads) are recorded in doc 04 Known Issues 11–12.


## Task 4 fix round — four coercion escape holes + @intCast masking coverage (v207 -> v208 2026-09-23)

**What.** Review Importants 1–4 on `dcb60038`, all reproduced on the Task 4 build and fixed.

1. **`var` local arithmetic/unary inits.** The phase sweep stores only const inits, so
   `var y: u32 = 0 - 1;` had no fold entry: rc=0, no diagnostic, ran `4294967295` (Zig:
   `type 'u32' cannot represent integer value '-1'`). New `checkDeclInitFits` (DECL mode of the
   shared `foldNodeIntExact`/`checkIntFitsMode`/`scalarTargetOf` fit check) folds such an init on
   demand and rejects it. Bare POSITIVE literals keep the pre-existing warning[3000] + truncate
   decl path (`const x: i8 = 200;` still accepted, Task 1 §5.3); `negate` literals follow the
   const-decl fold (`var x: i8 = -200;` now rejects like `const x: i8 = -200;`).
2. **Bare-literal parameters/returns.** `f(300)` and `return 300;` in a `u8` function ran `44`
   with no diagnostic. `checkArgReturnIntFits` (ARG mode: fold table + bare int/char literals and
   their `negate`) is called at the four call-argument loops and `return_stmt`; both now reject.
   Binary-argument expressions still lower at runtime (only the pinned fold-table/literal shapes
   are checked).
3. **Unannotated module consts.** `const X = 2000000000 + 1000000000;` emitted `int zG_X;` and
   ran `-1294967296` (Zig: `3000000000`). `semanticAnalyzerResolveModuleVarDecl` now applies the
   same value-based selection as the function-local rule and `front_resolution` stores the
   returned type on the decl node AND the symbol, so the global is `unsigned int zG_X;` and every
   reference agrees (positive control `MX` in the runtime fixture, oracle-matched).
4. **Optional-payload shapes.** `takeOpt8(@as(i32, 300))` was accepted with NO diagnostic and
   emitted gcc-invalid C (`zT_0 = zT_1;`, optional-struct from int); `var o: ?u8 = @as(i32, 300);`
   warned then emitted the same. `scalarTargetOf` unwraps `?T`/`E!T` before every fit check, so
   both (and `takeOpt8(300)`) are clean `error[3000]` rejects (Zig: `expected type '?u8', found
   'i32'`).
5. **Coverage carry-item.** The restored non-integer `@intCast` masking now has a committed
   fixture: `repro/mi_matrix/stdlib_comptime_intcast_nonint_mask_xmod` (`@intCast(i32,
   @intCast(f32, 4294967596))` folds 300; Z98-only shape — Zig rejects non-integer `@intCast`
   targets — so no oracle twin; stdout `masked=300`, rc 0, 3×).

**Fixtures.** `stdlib_comptime_coerce_typed_slots_xmod` gains the oracle-matched in-range controls
`MX` (unannotated module const), `vy` (`var u32` arithmetic init) and `takeLit` (bare-literal `u8`
argument) — new golden 2 lines, still byte-matched to the Zig-0.15.2 twin.
`comptime_coerce_reject_xmod` grows 7 → **12** `error[3000]` sites (`varBad`, `takeLit`, `retLit`,
`takeOpt`, `localOpt`). New `stdlib_comptime_intcast_nonint_mask_xmod` (OK) is the only corpus
addition. The two `safe_int_lit_shl_{count,value}_xmod` A6F fixtures used
`var r: u32 = 1 << 40;` / `2 << 31;` — Zig-invalid shapes that the fix round now correctly rejects
(Zig: `type 'u32' cannot represent integer value '1099511627776'` / `'4294967296'`); both were
ADAPTED (their documented `-fsafe` count/value guard coverage moves to a call argument,
`sink(1 << 40)` / `sink(2 << 31)`, which is still lowered at runtime and traps rc 133 under
`-fsafe`, wrapping to `256`/`0` under `-ffast`) and stay OK, so the corpus delta is exactly the new
fixture dir + the touched dirs (all same class).

**Corpus.** `-s0` **994 dirs = 871 OK / 43 GREEN / 80 FAIL / 0 ICE / 0 CRASH** (v207 993 =
870/43/80; +1 = the mask fixture only). Full-classifier join-diff vs the base Task 4 run:
**zero class movement on all 993 common dirs**. Pre-fix RED on the Task 4 base compiler:
`var y: u32 = 0 - 1;` rc=0 ran 4294967295; `f(300)`/`return 300;` rc=0 ran 44;
`const X = 2000000000 + 1000000000;` rc=0 ran -1294967296; both optional shapes rc=0 with
gcc-invalid C.

**Other gates.** 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `35388763…` /
json `5e1e0050…` / mud `5a1cc65e…`); stdlib **222 PASS / 0 FAIL** (pin 221 → 222); example matrix
24/24 (all `examples/z98/*` OK); frozen Step-0 35-shape table **byte-identical**;
`check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; `build_test.sh` **0/9**
(pre-existing zig0 baseline); self-emission rc 0 / 0 `error[...]`; `track-memory: perm=883K
mod=1020K scr=1024K pool=18999K type_db=490K total=2927K`. Fixed point **MOVED
`b4f999b57e4516c2a2c305e8660d5c44` → `a8ea33f75f239f2255adeb8cc2426a7c`** (two-hop closure
hop1 == hop2); seed stays **v82**, NOT rotated (R2).

**Residuals (documented in doc 04 Known Issues 11).** An optional payload whose source is a
RUNTIME value with no recorded wrap (`takeOpt8(runtime_i32)`) keeps the pre-existing assignability
laxness; a bare positive literal into an optional decl (`var o: ?i32 = 3000000000;`) keeps the
warning[3000]+truncate declaration path (valid C, Zig rejects). A `var` arithmetic init that
references a function-local const is not probed (lowering has no local-const scope) — a documented
false negative.

## Task 4 — coercion into typed slots (v206 -> v207 2026-09-23)

**What.** Every materialisation of a folded comptime integer now range-checks the exact value
against the target's width/signedness; before Task 4 the same shapes silently truncated (or, for a
value beyond 64 bits, silently unfolded and ran a wrong value).

**Compiler (`sf/src`).**
1. **Exact fold table.** `comptime_eval.zig` gains `ComptimeFoldTable` (`comptimeFoldTableInit`/
   `Put`/`Get`: node→slot `U32ToU32Map` + a dense `ComptimeVal` array in the module arena);
   `main.zig`'s `ctx.comptime_values` (`U32ToU64Map`) becomes `ctx.comptime_folds` and the three
   store arms put the exact `ComptimeVal`. `comptimeValStoreU64` stays as a test helper.
   Consequence (Task 1 §8 risk 1): `const BIG = 1 << 100;` (Zig-accepted, unused) is now
   `error[3000]` — Z98 has no runtime slot for it and refuses to emit wrong C. Bounded divergence.
2. **Coercion primitive.** `comptimeIntFitsType` is registry-based; new `comptimeIntFits64`,
   `comptimeIntMaterialize`, `comptimeIntUntypedType` (I32/U32/I64/U64 by exact value).
   Non-integer `@intCast` targets restore the pre-Task-2 `size*8` masking (carry item).
3. **Typed-slot fold rule** (`comptimeEvalDeclFits`, Task 1 §5.3): a name whose declared integer
   type cannot hold its initializer no longer folds (the runtime slot would hold the truncated
   value).
4. **Lowering.** `lowerFoldedIntConst` materialises all 14 arithmetic/unary HITs (typed target →
   fit check; untyped → value-based type); `checkFoldedIntFits`/`reportComptimeIntFits` cover
   `materializeInto` (after optional/EU unwrap), `applyCoercion`, the module-init and local-decl
   slots, and `return_stmt`. Failure = `error[3000] "comptime integer value does not fit the
   target type"` (existing `@intCast`/`@as` fold messages unchanged), once per node; the
   post-lowering diag gate exits rc=2 with 0 `.c`. `~` is exempt (Task 3 documented divergence).
   The carry-item local bare-negate i64 min now materialises exactly (`const imin: i64 =
   -9223372036854775808;` printed 0 before).
5. **Untyped local bindings.** An unannotated local whose folded init does not fit i32 takes the
   value-based slot type in BOTH sema and lowering (Task 1 §8 risk 7): `const c = 2000000000 +
   1000000000;` → u32, `(1 << 63) + 7` → u64, `0 - 3000000000` → i64 (each truncated before).
6. **Array sizes** (`type_resolver.zig`): `evalConstU32Full` is exact (`0..0xFFFFFFFE`;
   `0xFFFFFFFF` stays the sentinel) and the `array_type` arm routes every size expression through
   it (the inline u32-wrapping `add`/`sub`/`mul` arms are gone). `[0 - 1]u8` and
   `[4000000000 + 400000000]u8` now reject via the existing `error[3050]`.

**Fixtures (3 new dirs).**
- `repro/mi_matrix/stdlib_comptime_coerce_typed_slots_xmod` — positive runtime: in-range coerced
  slots per target (u8/i8/u32 bounds, `@intCast(i8,-128)`, `@as(u64, u64max)`, `[4*8]u8`,
  `[10-3]u8`, `enum(u8){A=250+5}`, folded u8 param/optional param/return, module typed fold) plus
  the carry-item local i64 min; Oracle Zig-0.15.2 output byte-matched; **class OK**; harness PASS
  (3×, expected.txt/expected.rc); stdlib pin **220 → 221**.
- `repro/mi_matrix/comptime_coerce_reject_xmod` — 7 lowering-phase `error[3000]` sites:
  `const U8FOLD: u8 = 250 + 60`, `const BIGFOLD = 1 << 100` (documented Zig divergence),
  `const NEGU: u64 = @as(i64, -1)`, `const NEGI8: i8 = @as(i32, -200)`, a `u8` parameter arg,
  a `u8` return, and a local `u8` decl; **class GREEN** (0 `.c` + `error[3000]`).
- `repro/mi_matrix/array_size_negative_reject_xmod` — `[0 - 1]u8` + an over-u32 sum, both
  `error[3050]`; **class FAIL** (a clean non-`error[3000]` reject; earlier FAIL-bucket convention).
- `repro/mi_matrix/comptime_cast64_range_reject_xmod` gains **site D** `@intCast(u64, 0 - 1)`
  (the Task 4 brief's explicit class; still GREEN).
- Standalone reps: `repro/comptime_coerce_typed_slots.z98` (positive; RED on the pre-Task-4 build
  panics `imin`, GREEN rc 0 3×) and `repro/comptime_coerce_reject.z98` (dump rc=2, 0 `.c`; RED on
  the old build = rc=0 + emitted C).

**Corpus.** `-s0` **993 dirs = 870 OK / 43 GREEN / 80 FAIL / 0 ICE / 0 CRASH** (v206 990 =
869/42/79; +3 = the new fixture dirs only). Full-classifier join-diff vs the Task 3 fix-round-2
baseline: **zero class movement on all 990 common dirs**; new = exactly the 3 Task 4 dirs.
Pre-fix RED on the old compiler: the positive fixture emits rc=0 and traps (`panic: imin`,
rc=133); both reject fixtures emit C and exit rc=0.

**Other gates.** 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `35388763…` /
json `5e1e0050…` / mud `5a1cc65e…`); stdlib **221 PASS / 0 FAIL**; example matrix 24/24 (all
`examples/z98/*` OK); frozen Step-0 35-shape table **byte-identical**; `check_emit_support.sh`
7/7; `verify_upgraded.sh` CLOSEOUT OK; `build_test.sh` **0/9** (pre-existing zig0 baseline);
self-emission rc 0 / 0 `error[...]` / 0 PANIC; `track-memory: perm=883K mod=1020K scr=1024K
pool=19213K type_db=362K total=2927K`. Fixed point **MOVED
`f533e834fdfdedb83991b7adf72da22d` → `b4f999b57e4516c2a2c305e8660d5c44`** (two-hop closure
hop1 == hop2); seed stays **v82**, NOT rotated (operator R2: rotation is closeout-only).

**Residuals (documented, not fixed; see doc 04 Known Issues 10/11).** An unannotated MODULE
const's C slot still comes from its symbol type (`const X = 2000000000 + 1000000000;` at module
scope truncates at runtime; the local case is fixed); an optional-payload coercion that records no
wrap (`takeOpt8(@as(i32, 300))`) is accepted with `warning[3000]` where Zig rejects.

## Task 3 fix round 2 — `bit_not` peer-fit revert + unit-test wiring (v205 -> v206 2026-09-23)

**What.** Fix round 1 gave BOTH unary folds the peer fit. For `bit_not` that over-rejects valid Zig:
`ciBitNot` is the exact `-x-1`, so for any TYPED UNSIGNED operand the result is always negative and
can never fit the operand type → every `~u` fold declined. Review probe
(`const u: u32 = 0; const x: i32 = if ((~u) != 0) 1;`): Zig 0.15.2 accepts and runs (`bnotNe ok`,
rc 0); the pre-round-1 Task 3 build accepted and ran (Zig-equal); the round-1 build rejected
`error[3059]`. Sema's `ResolveBitNot` types `~x` as x's type and the runtime complement wraps
(`~0u32` = 4294967295), so the fit is not a faithful mirror there.

**Fix (`sf/src/comptime_eval.zig`).** `bit_not` is EXEMPT from the peer fit again (as in Task 1 §4's
exact `~x = -x-1`); `negate` keeps the fit, so `-umax < 0` stays rejected. The accepted
`(~u) != 0` class is Zig-equal and regression-pinned. Declared divergence (documented in doc 04
Known Issues 9, NOT pinned): a shape that depends on the WRAPPED complement
(`(~u) == 4294967295` with `u: u32`) folds with the exact `-1` and false-rejects where Zig accepts —
the pre-existing Z98 `~` divergence (Task 1 §4, out of scope).

**Coverage defect.** `testComptimeCompareCore` (added in fix round 1) was never called from
`test_semantic_bin.zig`'s `main()`; it is now wired in after `testComptimeBigIntCore` and the probe
was re-run against the current source (`emit rc=0 / build rc=0 / cmp probe ok / run rc=0`).

**Fixtures.** `repro/mi_matrix/stdlib_comptime_compare_xmod` gains the fix-round-2 `~` shapes
(`(~UZERO) != 0` module operand and `(~uz) != 0` local operand; new golden line `400 401`; the
oracle twin prints the same) — **class OK**, harness PASS. Pin unchanged (220). Reject fixture and
noreturn fixture unchanged (9 × `error[3059]`; `5 6 7 8 9`).

**Gates.** Self-compile two-hop closure hop1 == hop2 == `f533e834fdfdedb83991b7adf72da22d`
(previous `04272a88…`); 4-MD5 emitted-C **UNCHANGED**; corpus `-s0` **990 = 869 OK / 42 GREEN /
79 FAIL / 0 ICE / 0 CRASH** (same dir set; join-diff vs Task 2 = exactly the 3 fixture dirs, 0 moved
on the 987 common dirs); stdlib **220 PASS / 0 FAIL**; example matrix **24/24**; frozen 35-shape
table **byte-identical** to the pre-round-1 run; `check_emit_support.sh` 7/7; `verify_upgraded.sh`
CLOSEOUT OK; build_test **0/9** (pre-existing).

## Task 3 fix round 1 — noreturn folded `if`, unary peer fit, unannotated-const init (v204 -> v205 2026-09-23)

**What.** Three review findings on Task 3 (`e720a99c`), all reproduced on HEAD and fixed.

1. **(Critical) Condition-store vs noreturn then-arm.** The Task 3 condition store feeds every
   capture-free no-`else` `if_expr`, but `lower.zig`'s `ie_fold` sub-path handled only `void`: for
   `const x: i32 = if (true) return 5;` it lowered the `return` arm as a VALUE (`lowerExpr` has no
   statement arm) and left `x` uninitialised. Official Zig prints `5`; the Task 2 compiler printed
   `5`; HEAD emitted `int zT_1; int x; zT_1 = x; x = zT_1; return x;` and printed garbage. Same for
   `if (T: bool = true)`, `if (1 < 2)` and `if ((1 + 1) == 2)`. Fix (`sf/src/lower.zig`): the fold
   sub-path now lowers the arm with `lowerIfArmValue` (which `lowerStmt`s a
   `return`/`break`/`continue`), returns the "no value" sentinel when the arm set
   `block_terminated` (the caller skips its store), and skips the shortcut entirely when the
   if_expr resolves to `TYPE_NORETURN`.
2. **(Important) Unary `-` escaped the peer-fit rule.** `-umax < 0` (`umax: u64`) was accepted and
   wrong; Zig rejects (`negation of type 'u64'`), Task 2 rejected (`error[3059]`). Fix
   (`sf/src/comptime_eval.zig`): the `negate` fold now requires the exact result to fit
   the operand's type (`comptimeEvalOperandType` + `comptimeIntFitsType`), mirroring sema's
   `semanticAnalyzerResolveNegate`. (`bit_not` got the same fit here; fix round 2 REVERTS it — see
   the v205 → v206 entry above.)
3. **(Important) Operand-type mirror missed an unannotated const's initializer.**
   `const c = @as(u8, 200); if ((c + 300) == 500) 7;` was accepted; Zig rejects (`type 'u8' cannot
   represent integer value '300'`), Task 2 rejected. Fix: `comptimeEvalOperandType` recurses into
   the initializer of an unannotated const (the deleted `comptimeEvalSignClass` did this too), so
   `c` types as u8 and the untyped 300 declines.

**Fixtures.** New positive runtime fixture `repro/mi_matrix/stdlib_comptime_noreturn_if_xmod`
(`main.zig` + `expected.txt` + `expected.rc`; bool-literal / function-local-const / folded-
comparison / folded-arithmetic-comparison / module-const conditions over
`if (<comptime-true>) return N;`; golden `5 6 7 8 9`, rc 0, byte-exact 3x, Zig-0.15.2-oracle twin
matched) — **class OK**; stdlib pin **219 → 220**. `repro/mi_matrix/comptime_compare_reject_xmod`
gains the two Important sites (`negUmaxLt0`, `unannotatedConstAddLt0`) — now **9 × `error[3059]`**,
rc=2, 0 `.c`, **class FAIL**. Unit coverage: `ciCmp` made `pub` and `test_semantic_bin.zig` gains
`testComptimeCompareCore` (runtime-verified via a probe against the real core: `cmp probe ok`,
rc 0). RED evidence: crit1/crit1b printed garbage (`-142108613`/`-152717253`) and imp2/imp3 were
accepted before the fixes; after: `5 5 5` (3x) and `rc=2, 1 × error[3059], 0 .c` each.

**Gates.** Self-compile two-hop closure hop1 == hop2 == `04272a883bb00c7afc3364660b2adc4d`
(previous `88c6b4c9…`); 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `35388763…` /
json `5e1e0050…` / mud `5a1cc65e…`); corpus `-s0` **990 dirs = 869 OK / 42 GREEN / 79 FAIL /
0 ICE / 0 CRASH** (989 → 990: the new fixture; join-diff vs the Task 2 baseline moves EXACTLY the
3 fixture dirs, zero class movement on the 987 common dirs); stdlib runtime gate **220 PASS /
0 FAIL**; example matrix **24/24**; frozen Task 0 shape table **byte-identical to the pre-fix
Task 3 run**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test **0/9**
(pre-existing zig0 baseline).

## Task 3 — signedness-free comparisons + logical folds (v203 -> v204 2026-09-23)

**What.** Two defects, one root cause. (1) The Task 9D comparison fold recovered each operand's
signedness syntactically (declared type / literal sign / `0 - X` / `@intCast`/`@as` target) and made
any arithmetic-derived comparison unfoldable, so the documented bounded divergence rejected
`(umax - 1) > 0`, `0 < (umax - 1)`, `(umax - 1) > zero`, `umax > (0 + 0)`, `(a + 1) == 2`,
`(imin + 1) < 0`, `(imax - 1) > 0` in a no-`else` value `if` (`error[3059]`) although official Zig
0.15.2 accepts them. (2) Accepted module-scope mixed-signedness shapes (`uu > -1` S3, `uu > (0 - 1)`
S5, `-9223372036854775808 < 0` E12, and S4 coincidentally) folded TRUE in the sema probe but
lowering emitted a FALSE runtime branch (unsigned materialisation) plus an uninitialised result
temp — a silent miscompile (step-0 §3).

**Fix (Task 3; Task 1 design §4/§5.4/§7).** `sf/src/comptime_eval.zig`:
`comptimeEvalCompare` now compares the exact magnitude+sign of the two `ComptimeInt`s via the new
private `ciCmp` (`-0` normalized; bools compare as 0/1) — no sign class, no declared-type lookup,
no 64-bit `ciValToOldBits` bridge; `comptimeEvalSignClass`, `SignClass`,
`comptimeEvalOperandCompareSigned`, `comptimeEvalOperandDeclaredSigned` and the `0 - X` special
case are DELETED, and `comptimeEvalOperandDeclaredSigned`'s type lookup is repurposed as
`comptimeEvalOperandType`. The arithmetic fold gains the operand peer-fit rule: the peer type P is
a typed operand's integer type (both typed → `comptimeEvalWiderIntType`, wider wins, ties keep
lhs); each UNTYPED operand's exact value and the exact result must fit P
(`comptimeIntFitsType`), else the fold declines — this keeps the Zig-rejected shapes rejected
(`(u - 300) < 0` with `u: u8`, `(u + 1000) < 0`, `(0 - umax) < 0`; Zig reports "cannot represent
integer value '300'/'1000'" and "overflow of integer type 'u64'"). `comptimeEvalOperandType`
mirrors sema's integer typing RECURSIVELY (negate/bit_not propagate; binops use the INT_LIT/numeric
arm + the wider-wins/ties-lhs rule), so nested arithmetic like `((u - 1) - 300) < 0` declines too
(without the recursion the fold computed -101 and accepted a program whose runtime u8 arithmetic
wraps to 155 — a silent miscompile caught in self-review). Comparisons are exempt from
peer-fit (oracle: `u8 200 > -1` is true, `u8 200 > 300` is false). `sf/src/main.zig`
`phase_ComptimeEvaluation` gains a third visitor arm: the condition of every capture-free
(`payload == 0`) no-`else` `if_expr` is folded and stored (bool 0/1) — exactly the domain where
`semanticAnalyzerConditionIsComptimeTrue` grants acceptance — so lowering's existing `if_expr`
`ie_fold` path elides the untaken branch and the module-scope shapes are runtime-equal to Zig.
`if_stmt` conditions and `if_expr` with an `else` are deliberately not stored; a function-local
condition operand is invisible to the module-scope sweep, so its (C-correct) runtime branch is kept.

**Fixtures.** New positive runtime fixture `repro/mi_matrix/stdlib_comptime_compare_xmod`
(`main.zig` + `expected.txt` + `expected.rc`; 22 values: function-local D1-D5 + local `imax` and
`@as`-spelled local `imin`, the same shapes with module-scope consts plus S3/S4/S5/E12 and
module-scope i64 extremes, and `and`/`or`/`!` over 2^100 magnitudes; every value `@panic`-guarded;
golden stdout below, rc 0, byte-exact 3x and Zig-0.15.2-oracle-matched) — **class OK**; stdlib pin
**218 → 219**. New reject fixture `repro/mi_matrix/comptime_compare_reject_xmod` (7 sites:
`umax < 0`, `(umax - 1) < 0`, `(u - 300) < 0`, `(0 - umax) < 0`, `(u + 1000) < 0`, nested
`((u - 1) - 300) < 0`, module `MUMAX < 0`; rc=2, 0 `.c`, 7 × `error[3059]`) — **class FAIL** (the
canonical classifier GREENs
only `error[3000]`). The old `repro/mi_matrix/comptime_compare_diverge_reject_xmod` (7-site
bounded divergence) is REPLACED by the pair. Standalone repro `repro/comptime_compare.z98`.
RED pre-fix: the positive fixture rejects 18 × `error[3059]` / 0 `.c`; standalone rejects
5 × `error[3059]`. Known residual (pre-existing, out of scope): the bare local
`const imin: i64 = -9223372036854775808` spelling materialises as 0 (32-bit HIT materialisation,
`print(imin)` prints 0 at HEAD too); the fixture spells it `@as(i64, …)`. Task 4/5 own the
lowering HIT migration.

**Gates.** Self-compile two-hop closure hop1 == hop2 == `88c6b4c9b8b0ce154385f6c382b251ea`; 4-MD5
emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `35388763…` / json `5e1e0050…` / mud `5a1cc65e…`);
corpus `-s0` **989 dirs = 868 OK / 42 GREEN / 79 FAIL / 0 ICE / 0 CRASH** (988 → 989; join-diff vs
the Task 2 post-fix compiler moves EXACTLY `stdlib_comptime_compare_xmod` (+OK),
`comptime_compare_reject_xmod` (+FAIL), `comptime_compare_diverge_reject_xmod` (−FAIL) — zero class
movement on the 987 common dirs); stdlib runtime gate **219 PASS / 0 FAIL**; example matrix
**24/24**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK; build_test **0/9**
(pre-existing zig0 baseline). Frozen Task 0 shape table: D1-D5/E10/E11 reject → accept (values
1/1/3/4/5/1/1 == oracle), E12 4 → 1, S3 4 → 3, S5 4 → 5 (all == oracle), D6/D7/E5/S6 still
reject (== oracle rejects), all other rows unchanged.

```
101 102 103 104 105 110 111 201 202 203 204
205 206 207 208 209 210 211 301 302 303 304
compare ok
```

## Task 2 — `ComptimeInt` core + arithmetic (v202 -> v203 2026-09-23)

**What.** Z98's comptime integers were 64-bit (`ComptimeVal { bits: u64, sig, width_bits }`) and
every arithmetic fold wrapped/truncated at 64 bits (a shift count ≥ 64 declined, so `1 << 100`
never folded at all). Exact intermediate magnitudes beyond 2^64 therefore ran WRONG at runtime:
`((1 << 64) + 1) / 2` printed `1` (Zig `9223372036854775808`), `(1 << 100) + 12345 % (1 << 90)`
printed `12361` (Zig `12345`), `(1 << 64) - 1` printed `0` (Zig `18446744073709551615`), etc.
The old compiler traps on the fixture's own `@panic` guard (`panic: bigint mod`, 3x).

**Fix (Task 2; Task 1 design §2–§4).** `sf/src/comptime_eval.zig` now implements a fixed-cap
arbitrary-precision core: `ComptimeInt { mag: [8]u32, len: u8, neg: bool }` (256-bit little-endian
magnitude; `len == 0` ⟺ zero; `-0` normalizes to `0`) wrapped in
`ComptimeVal { v, kind, float_bits }` with `KIND_INT`/`KIND_BOOL`/`KIND_FLOAT` replacing the old
`width_bits`/`sig`/`WIDTH_FLOAT` sentinel. add/sub/mul/div/mod/negate/bitand/bitor/bitxor/bitnot/
shl/shr are exact limb ops (`ci*`, `pub`): division and `%` truncate toward zero, `>>` is floor,
`&`/`|`/`^` use infinite two's-complement semantics. Every op is exact or declines (unfoldable) —
cap > 256 magnitude bits, division by zero, negative/oversized shift counts; no wrap/truncation.
`comptimeValFitsType` became the exact `comptimeIntFitsType`; `@intCast`/`@as` range-check the
exact value and fold it exactly (same `error[3000]` messages/location); `@intToFloat` converts from
the limbs; `comptimeEvalOperandSigned` and `WIDTH_FLOAT` are deleted. Comparison and logical folds
deliberately keep their pre-Task-3 semantics (`kind == KIND_BOOL`, `ciValToOldBits` reconstructs
the old 64-bit view and declines ≥ 2^64) so the frozen comparison table does not move; Task 3
rewrites them. `main.zig` stores folds via `comptimeValStoreU64` (bool 0/1, float bit pattern, int
two's-complement when it fits `[i64 min, u64 max]`; otherwise not stored), keeping the fold table's
`U32ToU64Map` ABI until Task 5. `semanticAnalyzerConditionIsComptimeTrue` now tests
`kind == KIND_BOOL` + `ciIsZero`.

**Fixtures.** New positive runtime fixture `repro/mi_matrix/stdlib_comptime_bigint_arith_xmod`
(`main.zig` + `expected.txt` + `expected.rc`; 31 values, every one Zig-0.15.2-oracle-checked:
2^64/2^100/2^200 magnitudes across add/sub/mul/div/mod, truncating-division and floor-shift signs,
bitwise AND/OR/XOR/NOT on negatives, u64 max, far shifts, multi-word shift controls (`y1`/`y2`),
and in-range no-over-rejection controls; golden stdout below, rc 0, byte-exact 3x; stdlib pin
**217 -> 218**) + standalone `repro/comptime_bigint_arith.z98`. RED pre-fix: guard panic rc 133
(or the wrong raw values shown above). Unit coverage: `test_semantic_bin.zig`
`testComptimeBigIntCore` (cap declines incl. the review's `word > 0` shapes, div-by-zero,
negative shift counts, division/floor-shift/bit-op signs) + the seven `comptimeEvalEvaluate` tests
migrated to the new representation.

**Review fix (Critical, 2026-09-23).** `ciShl` built all shifted source limbs but only consumed
those whose target limb started below 8, so a multi-word cap overflow (`(1 << 200) << 64`,
`2^32 << 224`, `2^64 << 192` — all exactly 2^256+) dropped the high limbs and returned `true` with
a silently truncated/garbage value. Fixed: a nonzero shifted limb whose target starts at/beyond
limb 8 now declines (`return false`); the fixture gains reduced-result controls `y1 = (2^100 << 64)
>> 164 = 1` and `y2 = (2^32 << 32) >> 32 = 2^32`, and `testComptimeBigIntCore` gains the
`word > 0` cap declines plus those two exact controls. Post-fix gates: closure hop1 == hop2 ==
`e0efd63178aea4edd1f818a058ba2b32`; 4-MD5 unchanged; corpus unchanged (zero movement); stdlib
**218 PASS / 0 FAIL**; frozen 35 shapes unchanged; the amended fixture run rc 0 (3x).

```
a=9223372036854775808  b=1024  c=12345  d=6148914691236517205
e=-9223372036854775808 f=-1    g=-9223372036854775808
h=1024 i=255 j=18446744073709551615 k=9223372036854775808 l=-2 m=0
n=1099511627781 o=-1537228672809129301 p=9223372036854775805
r=48 s=-48 t=17 u=-1 v=-2 w=-4611686018427387905
x1=-1 x2=0 x3=-3 x4=-3 x5=-1 x6=1 x7=3
y1=1 y2=4294967296
```

**Gates.** self-compile two-hop closure hop1 == hop2 == `e0efd63178aea4edd1f818a058ba2b32` (MOVED
`cd38f3167ca3e39982cc2d817b16dc70` → `e4246b19…` → `e0efd631…`, the last post-review-fix); 4-MD5
emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `35388763…` / json `5e1e0050…` / mud
`5a1cc65e…`); corpus `-s0` **988 dirs = 867 OK / 42 GREEN / 79 FAIL / 0 ICE / 0 CRASH** (v202 987
→ 988: the new fixture dir; full-classifier join-diff on the 987 common dirs **byte-identical, zero
movement**); stdlib runtime gate **218 PASS / 0 FAIL**; example matrix **24/24** dump/gcc/link; the
35 frozen Task-0 comparison/coercion shapes re-run **verdict-identical**; `check_emit_support.sh`
7/7; `verify_upgraded.sh` CLOSEOUT OK; `--track-memory -s0` pool **16883K** (matches the pre-change
compiler on the same source, so no memory regression). Test binaries via `sf/scripts/build_test.sh`
**0/9 — pre-existing failure** (retired zig0 cannot parse current `sf/src`; verified identical at
pristine HEAD). Seed NOT rotated (operator R2: closeout-only). Fixed point **MOVED
`cd38f316…` → `e0efd631…` (via `e4246b19…`)**.

## Task 10D — same-named local after a sibling `for` capture keeps its own variable (v201 -> v202 2026-09-23)

**What.** A pre-existing silent miscompile in `sf/src/lower.zig`: a plain local `var`/`const`
declared after a same-named `for` capture in a **sibling** scope lost its declaration + initializer
in the emitted C and aliased the stale capture temp (its uses redirected through the leaked
`capture_shadow` table). Canonical r3 probe: Zig 0.15.2 `c7=6 g7=2` vs pre-fix `c7=3 g7=5`
(emit/build rc 0, no diagnostic). The name must have appeared in an earlier closed scope (forcing
the capture rename), and the later declaration must sit in a sibling scope shallower than the
capture's registration depth; `while (opt) |v|` / `if (opt) |v|` captures and different names were
unaffected.

**Fix (AMENDMENT 14; Task 10D).** `captureShadowShouldRedirect` (signature and all three call sites
untouched) now walks the real scope chain from `cur_scope` through `scope_nodes[...].parent` instead
of comparing depth numbers: a declaration of the original name in a scope nearer than the synth
declaration's scope node suppresses the redirect; reaching the synth scope first redirects. The
`capture_shadow` table remains append-only (the eight arm-end `capture_shadow.count = 0` sites are
dead writes because `u32ToU32MapGet` ignores `count`); the guard renders that harmless for
identifier resolution.

**Fixtures.** New positive runtime fixture `repro/mi_matrix/stdlib_capture_sibling_reuse_xmod`
(canonical shape + later sibling `while`/`for`-body `var j`/`const j` + two renamed captures + bare
block + controls: same-depth nested block, capture-after-nested-loop, different name, no earlier
name, `while`/`if` capture analogues, cross-function reuse; every aggregate `@panic`-guarded; golden
`c7=6 g7=2 s1b=6 cap1=9 post1=57 post2=27 post3=15 cap2=4 cap3=4 post4=18 post5=21 ctl1=1 ctl2=18 ctl3=5 ctl4=20 wc=5 ic=2 xa=10 xb=8`,
rc 0, 3x byte-exact and Zig-0.15.2-twin-matched; stdlib pin **216 -> 217**) + standalone
`repro/var_after_capture.z98`. RED pre-fix: guard panic rc 133. The fixture uses no `@intCast` on a
capture (a separate pre-existing defect emits invalid C for that shape).

**Gates.** self-compile two-hop closure hop1 == hop2 == `cd38f3167ca3e39982cc2d817b16dc70`; 4-MD5
emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `35388763…` / json `5e1e0050…` / mud `5a1cc65e…`),
re-confirmed post-rotation; example matrix **24/24**; std-lib runtime gate **217 PASS / 0 FAIL**;
corpus `-s0` **987 dirs = 866 OK / 42 GREEN / 79 FAIL / 0 ICE / 0 CRASH** with a full-classifier
join-diff vs the pre-fix seed v81 compiler **byte-identical (zero movement**; the new fixture
classifies OK under both — the defect is runtime-only); `check_emit_support.sh` 7/7;
`verify_upgraded.sh` CLOSEOUT OK; Task 7D `shadow_reject_xmod` still rejects 14x `error[3057]` with
0 `.c`. Fixed point **MOVED `8b43b3b4f111cb9bedfebdd49309bd6a` -> `cd38f3167ca3e39982cc2d817b16dc70`**;
seed **v81 -> v82** (archive md5 `617ee1623331f79aae7957ff8e9138b4` -> `98a8b0ef292b31486a37f97c75938f30`;
`gen/` 45 `.c` + 46 `.h`, 9226676 bytes).

**Out-of-scope residual (unchanged).** `capture_shadow` has no real scope exit (append-only) and the
local-decl table is never reset between functions; the scope-chain guard's fallbacks make both
harmless for identifier resolution, but a proper scoped-shadow design remains a separate task. The
`maybeDisambiguateCapture` over-rename (any prior same-name declaration forces a synth name) is also
unchanged.

## Task 10B — `for`-loop `continue` runs the implicit step + nested-loop label leak (v200 -> v201 2026-09-23)

**What.** Two silent miscompiles in `sf/src/lower.zig` (AMENDMENT 13; operator rulings
m1318 + m1336). **(A)** `continue` inside a `for` loop (range or slice/array) jumped to the loop's
**condition** instead of its implicit increment — the increment lived inline in the body block and
`LoopInfo.header_bb` was `cond_bb` — so the range/index never advanced and the program hung
(emit/build rc 0, no diagnostic, runtime `timeout` rc 124), contradicting spec §3.2. **(B)** an
unlabeled nested loop inherited `current_label`, so a labeled `break`/`continue` matched the inner
loop first (wrong result, or a hang when combined with A); affected both `while` and `for`, both
transfer kinds.

**Fix.**
- **(A)** Both `AstKind.for_stmt` arms (`sf/src/lower.zig`, range arm and slice/array arm) create a
  dedicated `step_bb`, register `LoopInfo.header_bb = step_bb`, emit the body fall-through as
  `.jump(step_bb)`, and emit the increment **unconditionally** in `step_bb` (then `.jump(cond_bb)`)
  — the `while` `cont_bb` pattern. An always-`continue` body still reaches the step (pre-fix such a
  body had no increment at all).
- **(B)** The `while` arm, both `for` arms, and the labeled-block arm save `current_label`, clear it
  while lowering the body, and restore it at arm end (the `labeled_stmt` save/restore is unchanged),
  so an unlabeled nested loop is pushed with `label_id = 0`; labeled transfers target the loop that
  actually carries the label. Unlabeled transfers are unchanged.

**Fixtures.** New positive runtime fixture `repro/mi_matrix/stdlib_for_continue_xmod` (range /
array / slice / nested / nested-`if` / side-effect-before-`continue` / always-`continue` /
index-capture / `defer`+`continue`, plus `break`-in-`for` and `while` controls; every aggregate
`@panic`-guarded; golden `8 5 70 80 5 6 103 5 4 3 4 6 5 5`, rc 0, byte-exact 3x; stdlib pin
**215 -> 216**) and `repro/mi_matrix/nested_loop_label_xmod` (21 aggregates across
`while`/`for` x `break`/`continue` x unlabeled inner / mixed kinds / labeled block / nested labeled
/ plain-nested control; golden `6 3 3 1 3 6 2 3 2 6 2 6 3 7 3 7 3 6 4 3 103`, rc 0, 3x). Standalone
repros `repro/for_continue.z98` / `repro/nested_loop_label.z98`. All goldens matched against Zig
0.15.2 twins. RED pre-fix: stdlib fixture hang rc=124, nested fixture panic rc=133.

**Gates.** self-compile pre-rotation moving point `43fe3df1…` -> hop1 `6401621a…` ->
hop2==hop3 `8b43b3b4…`; post-rotation two-hop closure hop1==hop2==`8b43b3b4f111cb9bedfebdd49309bd6a`;
4-MD5 emitted-C **RE-BASELINED (authorized; PRE-vs-POST runtime stdout byte-identical + identical rc
for all four programs)**: gol `e7bde571…` / mud `5a1cc65e…` **UNCHANGED**; lisp `552d0a84…` ->
`353887639f127f4624de8b14b7e43a78` (+58 B); json `38b37bdd…` ->
`5e1e0050c0c462d76e9ef8dee3f5ae7c` (+62 B); example matrix **24/24**; std-lib runtime gate
**216 PASS / 0 FAIL**; corpus `-s0` **986 dirs = 865 OK / 42 GREEN / 79 FAIL / 0 ICE / 0 CRASH**
with a full-classifier join-diff vs the pre-fix seed v80 compiler **byte-identical (zero movement**
over the 986 common dirs; +2 vs v80's 984 = the 2 new fixtures); `check_emit_support.sh` 7/7;
`verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `43fe3df1509ffb5728c8250133ab7827` ->
`8b43b3b4f111cb9bedfebdd49309bd6a`**; seed **v80 -> v81** (archive md5
`4a499af291e17445736106d40eb14ab1` -> `617ee1623331f79aae7957ff8e9138b4`; `gen/` 45 `.c` + 46 `.h`,
9226589 bytes).

**Important pre-existing anomaly (found while isolating fixture 2; NOT caused by Task 10B).** A plain
`var` declaration whose name was earlier used as a `for` capture in a sibling scope can silently lose
its declaration + initializer and alias the stale capture storage (e.g. fixture-2's first draft
reused `j`; the emitted C had no `j = 0` init for the later loop and its uses read the previous
capture temp). Reproduced identically with the v80 seed and the fixed compiler; the permanent
fixtures avoid it via unique local names. Reported per m1336; a separate I/F pair is required.

## Task 9D — comptime-true no-`else` `if` fold + void-then value-`if` lowering (v196 -> v197 2026-09-22)

**What.** Two residuals from Task 9B. **(i)** The comptime-true no-`else` allowance used Z98's
comptime fold, which did **not** fold comparisons/logical ops and could not see function-local
consts, so `const a: i32 = 1; var x: i32 = if (a == 1) 1;` was rejected although official Zig
0.15.2 accepts it (too narrow a downgrade). **(ii)** A void-then value `if` (`_ = if (c) foo();`)
was front-end-accepted (correctly) but lowered to an undeclared result temp — gcc
`'zT_<n>' undeclared`.

**Fix (AMENDMENT 12; operator ruling m1251).**
- **(i) fold — Gap A** (`sf/src/comptime_eval.zig`): `comptimeEvalEvaluateDepth` gains
  `cmp_eq`/`cmp_ne`/`cmp_lt`/`cmp_le`/`cmp_gt`/`cmp_ge` (new `comptimeEvalCompare`, signedness
  mirrors the existing div/mod sign handling; float operands stay unfolded — a bounded residual)
  and `bool_and`/`bool_or`/`bool_not` (new `comptimeEvalLogical`, `and`/`or` **short-circuit**:
  `true or <runtime>` folds true, `false and <runtime>` folds false).
- **(i) fold — Gap B** (`sf/src/comptime_eval.zig`, `sf/src/semantic_analyzer.zig`): the
  `ident_expr` arm consults the enclosing function's `type_resolver.LocalConstScope` before the
  module symbol registry, and `semanticAnalyzerConditionIsComptimeTrue` sets
  `ce.local_consts = &self.local_consts` so the probe sees local `const`s.
- **(ii) lowering** (`sf/src/lower.zig`, `AstKind.if_expr`): when the result type is
  `TYPE_VOID`, no result temp is allocated; the arm-value assigns are guarded; the `else` arm is
  lowered only when `child_2 != 0`; the join returns `TEMP_NONE`. `return_stmt`'s
  `hoisted_temps[val]` deref is guarded against `TEMP_NONE`. (The adjacent pre-existing void-expr
  defects `_ = foo();` and `return foo();` are out of scope and unchanged.)

**Fixtures.** New positive runtime fixture
`repro/mi_matrix/stdlib_comptime_true_if_xmod/` (`main.zig` + `expected.txt` + `expected.rc`;
local-const `==`/`!=`/`<`/`<=`/`>`/`>=`, `and`/`or`/`!`, `true or <runtime>`, an arithmetic-derived
comparison, const-of-const, a module const, and the void-then value `if` forms
`_ = if (c) foo();` / `_ = if (c) foo() else bar();` / the capture form; every result
`@panic`-guarded; golden `10 11 12 13 14 15 16 17 18 19 30 32 34\nFFF`, rc 0, byte-exact 3x and
oracle-matched against `/tmp/zig-x86_64-linux-0.15.2/zig`). New standalone repros
`repro/if_noelse_comptime.z98` and `repro/void_value_if.z98`. `repro/mi_matrix/if_noelse_reject_xmod`
gained a `false and <runtime>` row (`andFalse`) — now 6 `error[3059]`; runtime `var`-comparison and
non-optional-capture rows stay rejected. stdlib pin **214 -> 215**.

**Gates.** 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `552d0a84…` / json `38b37bdd…` /
mud `5a1cc65e…`); example matrix **24/24**; std-lib runtime gate **215 PASS / 0 FAIL**; corpus
`-s0` **983 dirs = 863 OK / 42 GREEN / 78 FAIL / 0 ICE / 0 CRASH** with a full-classifier join-diff
vs the pre-fix seed v76 compiler moving EXACTLY `stdlib_comptime_true_if_xmod` (FAIL -> OK, the new
fixture; RED pre-fix = 13 `error[3059]`, GREEN post-fix = rc 0 / 6 `.c`); `check_emit_support.sh`
7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `efa91f8d7c000df51d5547b2628f6e9f` →
`c635bbf952501ca5993e6c60f63a4a5f`** (two-hop closure hop1==hop2); seed **v76 → v77** (archive md5
`d3df69da8b0c029e4373fef816c86ff4` → `6ca3b47c216754a0fb4b11c3cab7bd10`; `gen/` 45 `.c` + 46 `.h`).

**Fix round 1 (v197 -> v198 2026-09-23; review Important A + Minor B).** **(A) The comparison fold
ignored the declared const type.** `comptimeEvalCompare` used `use_signed = l.sig or r.sig`, and the
`ident_expr` arm recursed into the initializer literal without applying the const's declared type,
so a `u64` const ≥ 2^63 carried `sig = true`. Verified consequences against official Zig 0.15.2:
over-rejection (`const umax: u64 = 18446744073709551615; const x: i32 = if (umax > 0) 1;` and the
two-`u64`-const form `if (umax > zero)` — Zig accepts, Z98 rejected `error[3059]`) and
over-acceptance (`var x: i32 = if (umax < 0) 3;` — Zig rejects, Z98 accepted and left `x`
uninitialised). Fix: the new private `comptimeEvalOperandDeclaredSigned` resolves each operand's
declared integer type (function-local consts first, then the module symbol tables; `char_literal` →
unsigned; `@intCast`/`@as` → the integer target), and the comparison is signed when any declared-typed
operand is signed; when neither operand is typed, `comptimeEvalSignClass` decides (signed iff an
operand is syntactically definitely-negative), and that classifier now also consults the local const
scope (only set by the sema probe, so the global `phase_ComptimeEvaluation` fold is unaffected).
**(B) rhs-decisive short-circuit missing.** `comptimeEvalLogical` returned null as soon as the lhs
did not fold, so `if (run or true) 36` (runtime `run`) was rejected. Fix: when the lhs does not fold,
a decisive RHS still decides (`<runtime> or true` → true, `<runtime> and false` → false); other
runtime-lhs forms (`run and true`, `false or run`) stay rejected. Fixtures: the positive
`repro/mi_matrix/stdlib_comptime_true_if_xmod` gains x14–x19 (local-const `u64` above i64 max,
declared `i8` negative, declared `u8` positive, untyped local negative, `run or true`; golden now
`10 11 12 13 14 15 16 17 18 19 30 32 34 40 41 42 43 44 45\nFFF`, 61 bytes, rc 0, 3× oracle-matched)
and `if_noelse_reject_xmod` gains `u64Lt0`/`rhsAndFalse`/`rhsAndTrue`/`rhsOrFalse` (now 10
`error[3059]`). Gates: 4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `552d0a84…` / json
`38b37bdd…` / mud `5a1cc65e…`); example matrix **24/24**; std-lib runtime gate **215 PASS / 0 FAIL**;
corpus `-s0` **983 dirs = 863 OK / 42 GREEN / 78 FAIL / 0 ICE / 0 CRASH** with a full-classifier
join-diff vs the v77 compiler moving EXACTLY `stdlib_comptime_true_if_xmod` (FAIL -> OK); `check_emit_support.sh`
7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `c635bbf952501ca5993e6c60f63a4a5f` →
`4b8a6364ef47e8ebdfc5e4506b7cff02`** (two-hop closure hop1==hop2); seed **v77 → v78** (archive md5
`6ca3b47c216754a0fb4b11c3cab7bd10` → `8fff355b0423235500f044ddc84af62b`; `gen/` 45 `.c` + 46 `.h`).

**Fix round 2 (v198 -> v199 2026-09-23; review Important — a NEW over-rejection from fix round 1).**
Fix round 1's `have_decl` gate suppressed the syntactic-negative fallback, so a declared-**unsigned**
const compared against an **untyped negative** comptime_int was forced unsigned: with
`const uu: u8 = 200;`, `if (uu > -1)`, `if (-1 < uu)` and `if (uu > (0 - 1))` regressed from
v77-accepted (prints `1 2 3`) to `error[3059]` (rc=2, 0 `.c`), while official Zig 0.15.2 accepts all
three. Fix: the new private `comptimeEvalOperandCompareSigned` computes each operand's signedness
independently — a declared integer type wins for its OWN operand, otherwise the syntactic sign class
(`negative` → signed, `non_negative` → unsigned), falling back to `cv.sig` for an unrecognized
untyped shape — and the comparison is signed if either operand is. A declared-unsigned peer therefore
no longer masks a negative counterpart (`uu > -1` is true), while `const umax: u64 = …; if (umax < 0)`
stays unsigned/false and rejected. Fixture: `repro/mi_matrix/stdlib_comptime_true_if_xmod` gains
x20–x22 (`u > -1`, `-1 < u`, `u > (0 - 1)`; golden now
`10 11 12 13 14 15 16 17 18 19 30 32 34 40 41 42 43 44 45 46 47 48\nFFF`, 3× oracle-matched);
`if_noelse_reject_xmod` is unchanged (10 `error[3059]`). Gates: 4-MD5 emitted-C **UNCHANGED**
(gol `e7bde571…` / lisp `552d0a84…` / json `38b37bdd…` / mud `5a1cc65e…`); example matrix **24/24**;
std-lib runtime gate **215 PASS / 0 FAIL**; corpus `-s0` **983 dirs = 863 OK / 42 GREEN / 78 FAIL /
0 ICE / 0 CRASH** with a full-classifier join-diff vs the v78 compiler moving EXACTLY
`stdlib_comptime_true_if_xmod` (FAIL -> OK); `check_emit_support.sh` 7/7; `verify_upgraded.sh`
CLOSEOUT OK. Fixed point **MOVED `4b8a6364ef47e8ebdfc5e4506b7cff02` →
`d5608123de41de68663aa1842fcca9f2`** (two-hop closure hop1==hop2); seed **v78 → v79** (archive md5
`8fff355b0423235500f044ddc84af62b` → `101b8f72037be1e6279c5209391e0a13`; `gen/` 45 `.c` + 46 `.h`).

**Fix round 3 (v199 -> v200 2026-09-23; review Important — the `cv.sig` fallback mis-signs untyped
shapes; operator ruling m1293 option (b)).** `comptimeEvalOperandCompareSigned`'s `cv.sig` fallback
mis-signed unrecognized untyped comptime shapes in both directions: `const umax: u64 =
18446744073709551615; if ((umax - 1) > 0) 1;` (valid Zig, accepted by v78) over-rejected, while
`if ((umax - 1) < 0) 1;` (invalid Zig) over-accepted. Ruling (b) replaces the guess with a bounded,
documented divergence: an operand's signedness is taken ONLY from (i) a declared integer type,
(ii) a literal's own sign / `negate`, or (iii) an explicit `@intCast`/`@as` target; any other shape
makes the whole comparison unfoldable (null), so a no-`else` value `if` rejects `error[3059]`.
`comptimeEvalSignClass` classifies `0 - X` as the negation of X (the one arithmetic shape with a
definite sign), preserving `uu > (0 - 1)`. Consequences (all pinned):
- documented divergence (Zig 0.15.2 accepts): `(umax - 1) > 0`, `0 < (umax - 1)`,
  `(umax - 1) > zero`, `umax > (0 + 0)`, `(a + 1) == 2` -> `error[3059]`;
- Zig also rejects (outcome matches): `(umax - 1) < 0` (`expected type 'i32', found 'void'`) and
  `(u - 300) < 0` (`type 'u8' cannot represent integer value '300'`) -> `error[3059]`;
- still accepted: `umax > 0`, `umax > zero`, `uu > -1`, `-1 < uu`, `uu > (0 - 1)`;
  `umax < 0` still rejected.
New documented-diverge reject fixture `repro/mi_matrix/comptime_compare_diverge_reject_xmod`
(`main.zig` + `NOTES.md`; rc=2, 0 `.c`, 7 `error[3059]`); the positive
`repro/mi_matrix/stdlib_comptime_true_if_xmod` drops the now-unfoldable `a + 1 == 2` (golden
`10 11 12 13 14 15 16 17 18 30 32 34 40 41 42 43 44 45 46 47 48\nFFF`, 3× oracle-matched). Gates:
4-MD5 emitted-C **UNCHANGED** (gol `e7bde571…` / lisp `552d0a84…` / json `38b37bdd…` / mud
`5a1cc65e…`); example matrix **24/24**; std-lib runtime gate **215 PASS / 0 FAIL**; corpus `-s0`
**984 dirs = 863 OK / 42 GREEN / 79 FAIL / 0 ICE / 0 CRASH** with a full-classifier join-diff vs the
v79 compiler **byte-identical (zero movement** over the 984 common dirs; the +1 dir vs v79's 983 is
the new diverge fixture, FAIL under both**)**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed
point **MOVED `d5608123de41de68663aa1842fcca9f2` → `43fe3df1509ffb5728c8250133ab7827`** (two-hop
closure hop1==hop2); seed **v79 → v80** (archive md5 `101b8f72037be1e6279c5209391e0a13` →
`4a499af291e17445736106d40eb14ab1`; `gen/` 45 `.c` + 46 `.h`). Spec `docs/reference/Language_Spec_Z98.md`
§7.2 records the bounded divergence.

## Task 9B — reject invalid condition / `if` forms (v194 -> v195 2026-09-22; fix round 1 v195 -> v196)

**What.** Three shapes where zig1 silently ACCEPTED invalid Z98/Zig (all rejected by official
Zig 0.15.2). **(a)** an assignment in a condition (`if (a = 3)`, `if (a += 1)`,
`while (a = 0)`, `switch (a = 3)`) — assignment is a statement, not an expression; **(b)** a value
`if` expression without `else` (`var x = if (cond) 1;`, `return if (cond) 1;`,
`take(if (cond) 1);`) — Zig types a no-`else` `if` as `void`; **(c)** a non-`bool` condition
(`if (a)` with i32/u32/usize/`*i32`/enum/optional), and (m1240 ruling 5) a non-optional capture
condition (`if (q) |v|` with a non-optional `q`) and assignment-as-expression
(`var x = (a = 3);`). (b) was also a silent **miscompile**: the absent `else` lowered as
`lowerIfArmValue(self, 0)`, reusing the condition's last temp. Root cause + blast radius in the
Task 9A investigation report.

**Fix (AMENDMENT 11; operator rulings m1240).**
- **(a) parser** (`sf/src/parser.zig`): the condition `min_prec` at `parserParseIfExpr`,
  `parserParseSwitchExpr`, `parserParseIfStmt`, `parserParseWhileStmt` is now `Prec.prec_orelse`
  (was `Prec.assignment`/`Prec.none`), so `Prec.assignment` is not consumed and the `)` expect
  fails with `error[2000]`; `parserParseGroupedExpr` likewise parses at `Prec.prec_orelse`, so a
  parenthesized assignment expression is rejected. Matching Zig's parse error.
- **(b) sema** (`sf/src/semantic_analyzer.zig`): `semanticAnalyzerResolveIfExpr`'s `child_2 == 0`
  branch emits the new `error[3059]` (`ERR_3059_IF_WITHOUT_ELSE`) when the then-type is not
  void/noreturn/undefined and the condition is not comptime-known-true. `semanticAnalyzerConditionIsComptimeTrue`
  folds the condition via a fresh `comptime_eval` evaluator (diag null) and accepts a `bool`-width
  true result (bool literal, const-bool chain, or folding builtin), matching Zig's comptime-true
  no-`else` acceptance (m1240 ruling 3).
- **(c) sema**: the new `semanticAnalyzerCheckConditionType`, called by the shared if/while headers
  after the capture block, requires `bool` when there is no capture and an optional/error-union
  condition when there is a capture, else the new `error[3058]` (`ERR_3058_CONDITION_NOT_BOOL`).
  A condition already typed void/undefined/noreturn is skipped (no cascade). `MarkNodeOnce`-deduped.
- **diagnostics** (`sf/src/diagnostics.zig`): `ERR_3058_CONDITION_NOT_BOOL = 3058`,
  `ERR_3059_IF_WITHOUT_ELSE = 3059` (both level 0; next free codes after 3057).

**New fixtures.** Reject controls (all rc=2 / 0 `.c` / FAIL):
`repro/mi_matrix/cond_assign_reject_xmod` (a: `error[2000]`),
`repro/mi_matrix/cond_nonbool_reject_xmod` (c + capture: `error[3058]`),
`repro/mi_matrix/if_noelse_reject_xmod` (b: `error[3059]`). Positive runtime control
`repro/mi_matrix/stdlib_cond_ok_xmod` (valid `if`/`else if`/`else`, value `if` with `else`,
optional capture, null-optional else, `while`, void-then `if` statement; golden
`2 10 7 -1 3 1`, rc 0), pinned in `scripts/stdlib/expected_dirs.txt` (**213 → 214**). Standalone
repros `repro/cond_assign.z98`, `repro/if_noelse.z98`, `repro/cond_nonbool.z98`.

**Blast radius.** 4-MD5 emitted-C gates **UNCHANGED** (gol `e7bde571…` / lisp `552d0a84…` /
json `38b37bdd…` / mud `5a1cc65e…`); example matrix **24/24** dumps byte-identical pre↔post;
std-lib runtime gate **214 PASS / 0 FAIL**; `check_emit_support.sh` 7/7; `verify_upgraded.sh`
CLOSEOUT OK. Corpus `-s0` **982 dirs = 862 OK / 42 GREEN / 78 FAIL / 0 ICE / 0 CRASH** (v194
978 → 982: the 4 new fixture dirs). Full-classifier join-diff vs the pre-fix seed v74 compiler
over the 978 common dirs moves **EXACTLY `emission_void_temp_xmod` (OK→FAIL)** — it uses the
invalid non-optional capture `if (i.a) |v|` (official Zig: "expected optional type, found
'...'"), which m1240 ruling 5 mandates rejecting; zero other pre-existing movement. Fixed point
**MOVED `bea0a1c4c96140ced060d386fc99d145` → `c8f1a76a97e0fe385faf757d5c4015ba`** (two-hop
closure hop1==hop2); seed **v74 → v75** (archive md5 `18e05ec36c7ba13bcc9aaf69d2ed3b8e` →
rotated). Docs: `docs/reference/Language_Spec_Z98.md` §3.1 example fixed; the chapter-8 manual
page (`docs/sf/manuals/en/vol1-08-decisions.html`) "Using `=` where you meant `==`" section
rewritten to document the new rejection.

**Residual (NOT fixed; pre-existing, distinct defect).** A void-then no-`else` value `if` used as
a value (`_ = if (c) foo();`) is accepted by the front end (correctly, per Zig) but the pre-existing
lowering emits an undeclared temp (`gcc: 'zT_<n>' undeclared`); present in the pre-fix compiler
too, so not a Task 9B regression. Documented in the Task 9B report.

**Fix round 1 (v195 -> v196, review Important).** The `error[3059]` emission was gated on the
condition's resolved kind being `bool_type`, but a **capture** condition (`if (o) |v| v`) is
optional/error-union, so the gate suppressed the diagnostic and a value `if` without `else` was
silently accepted (`fn f(o: ?i32) i32 { var x: i32 = if (o) |v| v; return x; }` → rc=0, emitted
uncompilable C `incompatible types`; official Zig 0.15.2 rejects with `expected type 'i32', found
'void'`). The gate now accepts a `bool` condition (no capture) **or** an optional/error-union
condition (capture); an invalid condition still gets only its header `error[3058]` (no double
report). The message is reworded to `"if expression without 'else' cannot be used as a value (its
type is 'void')"`. `repro/mi_matrix/if_noelse_reject_xmod` gained a capture row (`capPick`) —
now 5 `error[3059]`. Verified: valid capture `if` **with** `else` and void-then capture `if`
still compile (rc=0). Fixed point **MOVED `c8f1a76a97e0fe385faf757d5c4015ba` →
`efa91f8d7c000df51d5547b2628f6e9f`** (two-hop closure hop1==hop2); seed **v75 → v76** (archive
md5 `884f00cd4b90a934253e8b3a14e4a8e6` → `d3df69da8b0c029e4373fef816c86ff4`; `gen/` 45 `.c` +
46 `.h`, 9182817 bytes). Gates: 4-MD5 **UNCHANGED**; matrix 24/24; stdlib 214 PASS; corpus `-s0`
**982 dirs = 862 OK / 42 GREEN / 78 FAIL / 0 ICE / 0 CRASH** with a join-diff vs the v75 compiler
**zero movement** (the fix only changes the diagnostic decision for an invalid program; class
stays FAIL); `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK.

## Task 8B — lower `@as(<signed>, <negative>)` operands with the target type (v193 -> v194 2026-09-22)

**What.** `@as(<signed>, <negative literal>)` used as a **binary operand** lost its signed
target. `sf/src/lower.zig`'s `comptime_values` HIT path (the `builtin_call` arm in
`lowerExprImpl`) recovered the folded constant's target type for `@intCast` only; `@as` fell
through to the `TYPE_USIZE` default, so the folded constant was materialised as the unsigned
64-bit literal `18446744073709551614ULL` (`0xFFFFFFFFFFFFFFFE`). As an operand that produced
wrong values or a `-fsafe` trap: `v / @as(i32,-2)` printed `0` (Zig `-3`),
`v + @as(i32,-2)` / `*` / `-` trapped rc 133, `@as(i32,7) > @as(i32,-2)` was `false` (Zig
`true`), `v % @as(i32,-2)` printed `7` (Zig `1`), and the `i64` / `i8` / `i16` / `isize`
operands were also wrong (only a direct print was accidentally correct, by C truncation). The
program was legal Z98/Zig, built cleanly, and produced **no diagnostic** — a silent miscompile
(AMENDMENT 10; root cause + blast radius in the Task 8A investigation report).

**Fix (one condition + comment).** `@as` shares the `@intCast` AST layout
`[target_type, value]` (Task 11U), so the target-recovery condition at `sf/src/lower.zig:4344`
now accepts `self.as_name_id`:

```zig
if (node.child_0 == self.intcast_name_id or node.child_0 == self.as_name_id) {
```

The fold itself (`sf/src/comptime_eval.zig:358-413`) was already correct and is unchanged. The
emitter's `.int_const` arm already renders a signed negative literal once the result temp
carries a signed integer type (as `@intCast` proved).

**New fixture.** `repro/mi_matrix/stdlib_as_neg_operand_xmod` (`main.zig` + `expected.txt` +
`expected.rc`), pinned in `scripts/stdlib/expected_dirs.txt` (**212 → 213**). It pins **every
signed width** (`i8` / `i16` / `i32` / `i64` / `isize`, plus an arbitrary-width signed `i40`,
operator ruling m1210) across `/`, `*`, `+`, `-`, `%`, and comparison operands, plus the
positive/unsigned/direct-print/`const`/literal/non-fold/`@intCast` controls (over-correction
guard). Every check is `@panic`-guarded; golden stdout is byte-exact 3× (`div=-3` … `done`),
`expected.rc = 0`, and independently matched against official Zig 0.15.2. Standalone
`repro/as_neg_operand.z98` (pre-fix: `div=0` then rc 133; `i40-div=0`).

**Gate battery (all on the seed-built fixed compiler).** Self-compile two-hop closure
**`bea0a1c4c96140ced060d386fc99d145`**; 4-MD5 emitted-C gates **UNCHANGED** (gol `e7bde571…` /
lisp `552d0a84…` / json `38b37bdd…` / mud `5a1cc65e…`); example matrix **24/24 dumps
byte-identical** pre↔post; std-lib runtime gate **213 PASS / 0 FAIL**; corpus `-s0` **978 dirs =
862 OK / 42 GREEN / 74 FAIL / 0 ICE / 0 CRASH** with a full-classifier join-diff vs the pre-fix
seed v73 compiler **zero class movement** — the only added dir is the new fixture (OK under both
compilers, since the defect is a silent runtime miscompile, not a build failure). **Emitted C is
NOT byte-identical outside the new fixture** (per the Task 8A review): `noreturn_opt_ctx_xmod`
(positive `@as(i32,0)` — the fix also drops a redundant temp) and `stdlib_comptime_cast64_range_xmod`
(`@as(u64,5)`) dumps change while their class holds; `check_emit_support.sh` 7/7;
`verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `3c55361afc2a898352379aa9a8bfff26` →
`bea0a1c4c96140ced060d386fc99d145`** (two-hop closure hop1==hop2); seed **v73 → v74** (archive
md5 `2c27579e32ee37c4661c5500305cd947` → `18e05ec36c7ba13bcc9aaf69d2ed3b8e`).

## Task 7F — print an `f32` correctly (v192 -> v193 2026-09-22)

**What.** `getPrintFnName` (`sf/src/c89_emit.zig`) had explicit arms only for `u32`/`i32`/`i64`/
`u64`/`f64`/`bool`/`u8`/`slice`; every other `TypeKind` fell through to the final
`std_print_i32` default. An `f32` argument (C `float`) was therefore passed to a C function taking
`int`, and C truncates `float`→`int` toward zero, so `1.5` printed `1`. The program was legal
Z98/Zig, built cleanly, and produced **no diagnostic** — a silent miscompile (AMENDMENT 8; root
cause + blast radius in the Task 7E investigation report).

**Fix (approach (a), one line).** One arm next to the `f64_type` arm:

```zig
if (ty.kind == TypeKind.f32_type) { var s: []const u8 = "std_print_f64"; return s; }
```

No runtime change: `std_print_f64` is already declared/defined in every emitted program, and its
in-scope `void std_print_f64(double val)` prototype widens `float`→`double` (C89 default-argument
promotion would do the same), so the existing decimal printer runs on the widened value. The f64
arm ignores `fmt`, so the new f32 arm does too: `{}`/`{d}` print decimal (Zig-matching), while
`{x}` prints decimal (Zig prints hex-float `0x1.8p0`) and `{c}`/`{s}` print decimal (Zig rejects
them) — pre-existing f64-arm limitations shared by f32, not regressions.

**New fixture.** `repro/mi_matrix/stdlib_f32_print_xmod` (`main.zig` + `expected.txt` +
`expected.rc`), pinned in `scripts/stdlib/expected_dirs.txt` (**211 → 212**). It pins `{}` and
`{d}`, a negative (`-2.25`), a rounding value (`0.1`), an `@intToFloat`-computed value, and a wide
value (`123456.75`); golden stdout is byte-exact 3×, `expected.rc = 0`. The pre-fix compiler prints
`f32-default = 1` / `f32-neg = -2` (truncation); the fixed compiler prints the values above.
Standalone `repro/f32_print.z98`.

**Gate battery (all on the seed-built fixed compiler).** Self-compile two-hop closure
**`3c55361afc2a898352379aa9a8bfff26`**; 4-MD5 emitted-C gates **UNCHANGED** (gol `e7bde571…` /
lisp `552d0a84…` / json `38b37bdd…` / mud `5a1cc65e…`); example matrix **24/24**; std-lib runtime
gate **212 PASS / 0 FAIL**; corpus `-s0` **977 dirs = 861 OK / 42 GREEN / 74 FAIL / 0 ICE / 0
CRASH** with a full-classifier join-diff vs the pre-fix seed v72 compiler **byte-identical (zero
movement)** — the only added dir is the new fixture (OK under both compilers, since the defect is a
silent runtime misprint, not a build failure); `check_emit_support.sh` 7/7; `verify_upgraded.sh`
CLOSEOUT OK. Fixed point **MOVED `e46810b5ec6327f7bdf5288836e55c51` →
`3c55361afc2a898352379aa9a8bfff26`**; seed **v72 → v73** (archive md5
`5ed3debdb199ceafe0117f45183b3a39` → `2c27579e32ee37c4661c5500305cd947`).

**Residuals (NOT fixed; distinct root causes — a kind/width/signedness-aware dispatcher, a separate
task).** The same fall-through mis-routes `usize` > `2^31-1`, arbitrary-width ints wider than 32
bits (`u40`/`i40`), and wide-backed enums; it also drops `{x}`/`{c}` for kinds without a hex/char
arm and accepts aggregate/pointer/function-value/error-set arguments (aggregates then fail at gcc
with `incompatible type for argument 1 of 'std_print_i32'`; `error_set_type` silently prints its
ordinal; array/pointer/function-value print silent garbage).

## Task 7D — reject local declaration shadowing (v190 -> v191 2026-09-22)

**What.** Task 7D makes the compiler reject function-local declaration shadowing, matching official
Zig 0.15.2 ("Variable identifiers are never allowed to shadow identifiers from an outer scope").
Scope 1 = FULL Zig fidelity: shadowing of an identifier from ANY outer scope is rejected, including
function-local -> container/module. The new diagnostic is the dedicated **`error[3057]`**
(`ERR_3057_LOCAL_SHADOW`, level 0, span on the shadowing declaration) in `sf/src/diagnostics.zig`.

**Implementation (`sf/src/semantic_analyzer.zig` only).**
- Re-applied the reverted `fa553205` block-scoped local-decl machinery: the stmt walker pushes a
  scope-pop marker (`0x80000000 | saved_depth`) for blocks and for `if`/`while`/`for` statements
  (captures are registered before the marker, so they are popped after the branches/body); the
  switch-expr drain loop pops per prong; the `catch` payload is popped after resolving the handler
  synchronously.
- **Extended beyond 7C:** expression-position scopes are now popped too — `if_expr` and `orelse_expr`
  in `semanticAnalyzerResolveExpr`, plus the expression-position `block` arm (which drains any
  statement work its trailing child deferred BEFORE restoring, so an `if`/`while`/`for` used as a
  block's last child still sees the block's locals). 7C listed expression-position captures as a
  residual; 7C's 10 predicted `sf/src` sites were GENUINE nested-scope shadows (Task 7M's renames
  stand and were necessary), and only 2 ADDITIONAL sites flagged during 7D's first build were
  expression-position-scope **false positives** (a leaked `if_expr` capture / `orelse`-body local
  re-encountered after its scope closed).
- Added `semanticAnalyzerCheckLocalShadow(name_id, span_start, span_end)` and call it immediately
  before every local-registration site: local `const`/`var`, function parameters, `if`/`while`/`for`
  captures, switch-prong captures, `catch` payloads, and function-local named types. It scans the
  scope-truncated local table newest-first (a hit = strictly-enclosing or same-scope declaration),
  then rejects a container-level symbol (`global`/`function`/`type_alias`/`module`) in the current
  module. `_` (the discard) is exempt.

**Key finding.** 7C's 10 predicted `sf/src` local-shadow sites were **genuine** nested-scope shadows
and Task 7M's de-shadowing renames stand (necessary — Zig 0.15.2 rejects them, e.g.
`sf/src/parser.zig:730` `var tok` shadowing `:713 var tok`). 7D's first build then flagged 2
**additional** `sf/src` sites that were **expression-position-scope false positives** (a leaked
`if_expr` capture / `orelse`-body local re-encountered after its expression scope closed); with
expression-position scoping in place the self-compile passes with **no further `sf/src`
de-shadowing**.

**Non-forms (residuals, per 7C §6):** `else |e|` payload captures (unparseable in Z98 ->
`error[2000]`) and nested `fn` (unsupported -> `error[3020]`) are not enforced.

**New fixtures + repro.**
- `repro/mi_matrix/shadow_reject_xmod/main.zig` — one site per supported form (inner `const`/`var`
  shadow both directions, same-scope redeclare, local-shadows-param, param-shadows-container, local
  shadows container `const`/`var`/`fn`/type, `if`/`while`/`for` capture shadow, switch-prong capture
  shadow, `catch` payload shadow). **14 `error[3057]` diagnostics, one per site**; rc=2, 0 `.c`; FAIL.
- `repro/mi_matrix/shadow_ok_xmod/main.zig` — positive runtime control (sibling-block reuse,
  inner-before-outer declaration, distinct capture names across sibling constructs, `_` re-binding,
  read-only capture). rc=0; deterministic golden stdout `123499565611567` + newline; OK.
- `repro/shadow_local.z98` — standalone reproduction (rc=2, 0 `.c`, 3 `error[3057]`).

**Blast radius (corpus `-s0`).** The corpus is **976 dirs = 860 OK / 42 GREEN / 74 FAIL / 0 ICE /
0 CRASH** (pre-fix seed v70: 976 = 869 OK / 42 GREEN / 65 FAIL). The full-classifier join-diff vs
the pre-fix seed v70 compiler moves **exactly 9 dirs, every one an OK -> FAIL deliberate Zig-matching
shadow reject**. Eight are confirmed illegal by the official 0.15.2 oracle (`build-obj
-fno-emit-bin`); `repro/capture_rename` is correct by Zig's rule (same-scope redeclaration) but the
oracle stops earlier on Z98's 2-arg `@intCast` (see its row):

| dir | site | oracle diagnostic |
|---|---|---|
| `repro/mi_matrix/parsergap_shadow_local_xmod` | block `var x` shadows outer `var x` | `local variable 'x' shadows local variable from outer scope` |
| `repro/capture_rename` | `var err_shadow` + `catch |err_shadow|` same block | `redeclaration of local ...` (oracle stops earlier at `main.zig:47`, Z98 2-arg `@intCast`) |
| `repro/mi_matrix/emission_capture_control_xmod` | `for |s|` capture + local `var s` | `local variable 's' shadows capture from outer scope` |
| `repro/mi_matrix/emission_sibling_payload_ifcap_xmod` | `if |s|` capture + local `var s` | same |
| `repro/mi_matrix/emission_sibling_payload_scale_xmod` | switch-prong `|s|` capture + local `var s` | same |
| `repro/mi_matrix/emission_sibling_payload_catchcap_xmod` | `catch |e|` payload + local `var e` | same |
| `repro/mi_matrix/emission_sibling_payload_nestedarm_xmod` | nested prong `|s|` shadows prong `|s|` | `capture 's' shadows capture from outer scope` |
| `repro/mi_matrix/emission_misc_xmod` | inner `var fb` shadows outer `var fb` | `local variable 'fb' shadows local variable from outer scope` |
| `repro/mi_matrix/emission_opt10_assign_xmod` | `if |rt|` capture shadows local `var rt` | `capture 'rt' shadows local variable from outer scope` |

`repro/mi_matrix/emission_conflation_control_xmod` (sibling `if`/`else` branch blocks reusing `ck`)
is **legal** Zig and stays **OK** — it exposed an expression-position scope leak during development
that the block-arm drain fixed. `parsergap_shadow_local_xmod` deliberately reverses the earlier
"shadowing is valid" intent (its NOTES.md now says so).

**Examples de-shadowed (mechanical, semantics-preserving).** The example matrix's `rogue_mud` and
`rogue_mud_upgraded` had block-local `var i` shadows of the function-level `var i`:
`examples/z98/rogue_mud/main.zig:159,185`, `examples/z98/rogue_mud_upgraded/main.zig:116,142`, and
`examples/z98/rogue_mud_upgraded/demo/net_main.zig:116,142`. The inner bindings were renamed
`sel_i` (fd-set loop) and `acc_i` (accept loop) with every reference in scope updated; the outer
`var i` is untouched. The `examples/zig0/` copies are not in any gate and were left as-is.

**Fixed point / seed.** The self-emission fixed point **MOVED `5c4d6eb627944dd4c5e0ff68a1089f43`
-> `e5ba7d74a78536683d2633c4655e027e`** (two-hop closure hop1 == hop2); seed **v70 -> v71** (archive
md5 `dd805c837557235f5fc5dd576282555e` -> `fae87bb36b621b07642d4db57a8c7212`).

**Gates.** 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp
`552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud
`5a1cc65ef23f27d1c4c51f4516760c07`. Example matrix **24/24** dump/gcc. Std-lib runtime gate
**211 PASS / 0 FAIL**. `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK.

**Fix round 1 (review).** Two review findings touched `sf/src`, so the fixed point moved again.
(1) The `error[3057]` span now points at the shadowing NAME token for `var_decl` (2nd ident after
the keyword), `for` item/index captures (ident after the `)` that closes the iterable), and
switch-prong captures (ident after the prong's `=>`) — those nodes carry the name only as a payload,
so the span is source-scanned (`diagnosticCollectorScanIdentSpan` + `FindFirstByte`/`FindLastByte`
in `diagnostics.zig`); `if`/`while`/`catch`/param already used their name node. (2) The
scope-pop-marker restore, previously duplicated at three sites, is factored into
`semanticAnalyzerPopScopeMarker`. Fixed point **MOVED `e5ba7d74a78536683d2633c4655e027e` ->
`e46810b5ec6327f7bdf5288836e55c51`** (two-hop closure hop1 == hop2); seed **v71 -> v72** (archive
md5 `fae87bb36b621b07642d4db57a8c7212` -> `5ed3debdb199ceafe0117f45183b3a39`). Corpus `-s0`
re-swept: **976 = 860 OK / 42 GREEN / 74 FAIL / 0 ICE / 0 CRASH**, join-diff vs seed v70 still
**exactly the same 9 deliberate shadow rejects** (no further movement); 4-MD5 / matrix 24/24 /
stdlib 211 / check_emit 7/7 / CLOSEOUT OK all unchanged.

## Task 7M fix round 1 — de-shadow `if`-capture sites (v189 -> v190 2026-09-22)

Review found the first Task 7M commit incomplete. **12 `if`-capture sites** in `sf/src/lower.zig` (same function `lowerExprImpl`) remained: `:2716`, `:2741`, `:2759`, `:2777`, `:2798`, `:2821`, `:2837`, `:2853`, `:2868`, `:2883`, `:2898`, `:2915` — each is a `var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;` whose `if`-capture `rt` shadows the function-level `var rt` at `:2539`. Official Zig 0.15.2 rejects this exact pattern, and Task 7D will guard `if`-capture registration, so 7D would have rejected these and broken the self-compile — the exact failure Task 7M exists to prevent.

**Fix (mechanical, semantics-preserving).** Each capture binding `|rt|` was renamed to `|rrt|` (its single use `rt` in the same arm updated); the outer `:2539` binding was not touched. One additional in-scope reference was found and fixed: `sf/src/lower.zig:3402` `if (rt) |rtt|` is inside the scope of the inner `var rt` renamed to `rt_lrb` at `:3338`, so it was updated to `if (rt_lrb) |rtt|` (it previously bound the outer `:2539` only by coincidence — identical initializers).

**Verification.** A brace-scope scanner (comments/strings/char-literals stripped; `var`/`const` declarations AND `|name|` captures) over the non-test `sf/src` self-compile graph now reports **zero** local↔local or capture shadows (only the `extern_c_z98.zig:2` `_` discard false positive). The same scanner run against the previous commit correctly flags exactly the 12 capture sites, confirming coverage.

**Fixed point / seed.** The self-emission fixed point **MOVED `b30033e88075b82243b5601ea3b1c38c` → `5c4d6eb627944dd4c5e0ff68a1089f43`** (two-hop closure hop1 == hop2); seed **v69 → v70** (archive md5 `bbaeab7c4a77e3d20342a5a0cfd78646` → `dd805c837557235f5fc5dd576282555e`; `gen/` 45 `.c` + 46 `.h`, 9134766 bytes; round-trip verified hop1 == hop2 == `5c4d6eb6…`).

**Gates — zero user-program movement.** 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. Example matrix **24/24** dump/gcc. Std-lib runtime gate **211 PASS / 0 FAIL**. Corpus `-s0` **974 dirs = 868 OK / 42 GREEN / 64 FAIL / 0 ICE / 0 CRASH**; a full-classifier join-diff vs both the pre-fix seed v69 and the original seed v68 is **byte-identical (zero class movement)**. `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK.

## Task 7M — de-shadow the compiler source's local-shadow sites (v188 -> v189 2026-09-22)

Task 7C found **10 real function-local shadowing sites** in the compiler's own `sf/src` (all in `main.zig`'s self-compile import graph; test-only files such as `sf/src/tests/*` are excluded — `main.zig` does not import `test_main.zig`). Official Zig 0.15.2 rejects ALL shadowing of an outer identifier, so the shadow-rejection of Task 7D would break the self-compile. Per operator ruling **m1079**, this **M (migration)** task de-shadows them FIRST, so the migration is verified independently of the rejection. It is a **mechanical, semantics-preserving rename** with **no behavior change to the compiler's output on user programs**.

**The 10 sites (each verified against current source; every reference within the inner binding's scope updated; the outer binding untouched):**

| File | Inner binding | Renamed to | Shadows |
|---|---|---|---|
| `sf/src/parser.zig` | `:730` `var tok` | `arg_tok` | `:713` `var tok` |
| `sf/src/lower.zig` | `:3338` `var rt` | `rt_lrb` | `:2539` `var rt` |
| `sf/src/lower.zig` | `:4077` `var rt` | `rt_h` | `:2539` `var rt` |
| `sf/src/lower.zig` | `:4164` `var rt` | `rt_d` | `:2539` `var rt` |
| `sf/src/lower.zig` | `:4345` `var rt` | `rt_fold` | `:2539` `var rt` |
| `sf/src/lower.zig` | `:4849` `var rt` | `rt_ret` | `:2539` `var rt` |
| `sf/src/lower.zig` | `:4975` `var rt` | `rt_oe` | `:2539` `var rt` |
| `sf/src/lower.zig` | `:5111` `var rt` | `rt_arr` | `:2539` `var rt` |
| `sf/src/lower.zig` | `:4023` `var field_name_id` | `inner_field_name_id` | `:3981` `var field_name_id` |
| `sf/src/c89_emit.zig` | `:3973` `var pi` | `poison_i` | `:3140` `var pi` |

A brace-scope scanner over the self-compile graph found **no additional** local↔local shadows (and no local→container shadows in non-test `sf/src`), consistent with Task 7C §5.1.

**Fixed point / seed.** The compiler's own emitted C changes (renamed locals), so the self-emission fixed point **MOVED `02c10559914a7a85704f7eca5c87bbff` → `b30033e88075b82243b5601ea3b1c38c`** (two-hop closure hop1 == hop2); seed **v68 → v69** (archive md5 `462dde37abb64c56292c8deb5f2439b1` → `bbaeab7c4a77e3d20342a5a0cfd78646`; `gen/` 45 `.c` + 46 `.h`, 9135064 bytes; round-trip verified hop1 == hop2 == `b30033e8…`).

**Gates — zero user-program movement.** 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. Example matrix **24/24** dump/gcc. Std-lib runtime gate **211 PASS / 0 FAIL**. Corpus `-s0` **974 dirs = 868 OK / 42 GREEN / 64 FAIL / 0 ICE / 0 CRASH**; a full-classifier join-diff vs the pre-fix seed v68 compiler is **byte-identical (zero class movement)**. `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK.

## Task 7B — enforce `const` assignment (v187 -> v188 2026-09-22)

Assignment to an **immutable l-value** was not enforced. `const x = 1; x = 2;` (plain and compound), a module `const` write, `p.* = 2` through `*const T`, `s[0] = 2` through `[]const T`, const fixed-array elements, scalar/`*const`/`[]const` function parameters, and `for` captures all compiled **rc=0 with no diagnostic** and the emitted C performed the mutation — contradicting spec §1.7 (`docs/reference/Language_Spec_Z98.md`: "The Z98 frontend strictly enforces `const` qualifiers") and `docs/sf/Design_p2.md:1375`. zig0 enforces it (`src/bootstrap/type_checker.cpp:1841`/`:1893` via `isLValueConst`), so this was a regression.

**Root cause (Task 7A).** `semanticAnalyzerResolveAssign` (`sf/src/semantic_analyzer.zig`) — the single choke point for all 19 assignment kinds — resolved the l-value and the r-value with no constness check; the local-decl tracking arrays (`local_decl_names`/`local_decl_types`) carried no const bit.

**Fix (Task 7B).** `semanticAnalyzerResolveAssign` now calls the new `semanticAnalyzerIsLValueConst` after the `_` discard special-case and before the r-value resolution. A true result emits level-0 **`error[3002]` "cannot assign to immutable variable"** at the l-value span (`node.child_0`) and returns `TYPE_VOID`; the post-sema `hasErrors` gate exits rc=2 with 0 `.c`. The numeric literal `3002` is passed directly (the `ERR_3002_INVALID_ASSIGNMENT` enum ordinal is 21; adding `= 3002` would shift `ERR_3003`..`ERR_3007`). `semanticAnalyzerIsLValueConst` mirrors zig0's coverage — an `ident_expr` whose local/param/capture binding is const or whose module symbol is a `var_decl`-backed `global` with `(flags & 1) == 0`; a `deref` whose operand type is `ptr_type`/`many_ptr_type` with `Type.flags & 1`; an `index_access` on a `slice_type`/`ptr_type`/`many_ptr_type` with `flags & 1` or a const array (recurse); a `field_access` through a const pointer or const module member (else recurse); a `paren_expr` (recurse). It only READS the already-populated resolved-type/symbol/local tables, so an undeclared base keeps its single `error[3001]` (no double report), and non-value module symbols (fn/type aliases) are not misclassified. A new parallel `local_decl_consts: [*]u8` bit (grown in `semanticAnalyzerGrowLocalDecls`, written at every registration site) records local constness: params/captures are immutable; a `var_decl` is const iff AST flags bit 0 is clear. `.tag`/optional-member writes on a mutable binding are NOT special-cased (Z98 supports them; the 7A-recommended unconditional `.tag` read-only rule was dropped as out-of-scope — it over-rejected the maintained `repro/field_store_tagged` control, which writes `u.tag` on a `var` union).

**New fixtures (2 dirs + 1 standalone).** Reject fixture `repro/mi_matrix/const_assign_reject_xmod` (12 assignment sites: local plain/compound/nested-block `const`, module `const`, module `const P: *const T` deref, local `const p: *const T` deref, local `const s: []const T` element, const fixed-array element, scalar param, `*const T` param deref, `[]const T` param element, `for` capture) — base rc=0 / 4 `.c` but gcc-invalid (the emitted C mutates the never-emitted module `const G`), class **FAIL**; fixed rc=2 / 0 `.c` / 12 × `error[3002]`, class **FAIL** (the canonical classifier GREENs only `error[3000]`). Positive runtime control `repro/mi_matrix/const_assign_ok_xmod` (mutable `*T`/`[]T` pointee writes through `const` bindings, `var` reassignment/field/element writes, `_ = x;` discard, read-only `for` capture; deterministic golden stdout `3 5 7 8 9 11 23`, rc 0) — class **OK** under both compilers, so the fix cannot over-reject. Standalone `repro/const_assign.z98` (base rc=0 / 4 `.c` → fixed rc=2 / 0 `.c`, 3 × `error[3002]`).

**Gates (seed-built fixed-point compiler `02c10559914a7a85704f7eca5c87bbff`).** Self-compile two-hop closure hop1 == hop2 == `02c10559…`; self-emission rc=0, 0 `error[...]`, 0 PANIC (the compiler's own source contains no const reassignment). 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. Example matrix **24/24** dump/gcc. Std-lib runtime gate **211 PASS / 0 FAIL**. Corpus `-s0` **974 dirs = 868 OK / 42 GREEN / 64 FAIL / 0 ICE / 0 CRASH** (v187 972 → 974: the 2 new fixture dirs); a full-classifier join-diff vs the pre-fix seed v67 compiler over the same 974 dirs is **byte-identical (zero class movement)** — the reject fixture is FAIL under both (base: gcc rejects the emitted mutation of the unemitted module const; fixed: clean reject) and the control is OK under both. `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `923fe0f041704c1e4a21af6c7fbc513f` -> `02c10559914a7a85704f7eca5c87bbff`**; seed **v67 -> v68** (archive md5 `855a88689457f631df7c42c903c69c5a` -> `462dde37abb64c56292c8deb5f2439b1`).

## Task 6F — diagnose an undeclared identifier (v186 -> v187 2026-09-22)

An **undeclared identifier in expression position** was silently accepted. `sf/src/semantic_analyzer.zig`'s `semanticAnalyzerResolveIdent` fallback returned `TYPE_VOID` with no diagnostic, so `nope()` (and `take(nope)`, `return nope;`, `var x = nope;`, `arr[nope]`, `_ = nope;`, `if (nope)`, `while (nope)`, `nope + 1`, `x = nope`, `nope()()`, `(nope)()`, `nope.foo`, cross-module `lib.nope()`) compiled rc=0 with **no diagnostic** and emitted uncompilable C (`zT_0 = nope;` → gcc `'nope' undeclared`).

**Root cause (Task 6G).** The silent `TYPE_VOID` fallback at the end of `semanticAnalyzerResolveIdent` has a single caller — the `ident_expr` arm of `semanticAnalyzerResolveExpr` — so every expression-position use of an undeclared identifier resolved to void.

**Fix (Task 6F, variant S).** The fallback now emits the existing **`error[3001]` (`ERR_3001_UNDEFINED_SYMBOL`, numeric code 20)** "identifier '<name>' is not declared or imported in this module" with a **precise `file:line:col` span** (`self.source_file_id`, `ident.span_start` .. `+span_len`); the `_` discard sentinel (`_stub_0`) still returns `TYPE_UNDEFINED` silently by design. The post-sema `hasErrors` gate (`main.zig:370-373`) exits rc=2 with 0 `.c` before `phase_LIRLowering`, so the Task 6D variant-C `error[3056]` and Task 6B `error[3042]` lowering paths are never reached for an undeclared callee and are unchanged. A companion **dedup** drops the redundant `error[3001]` emission in `semanticAnalyzerResolveFieldAccess`'s `else if (base_rt == TYPE_VOID)` branch (the branch keeps its early return), so `nope.foo`/`nope.len`/`nope.foo.bar` emit exactly ONE `error[20]` instead of two; it also removes a false `error[20]: identifier 'x' is not declared` for a declared-but-void field base (`const x = v(); x.foo;`), which still clean-rejects via the earlier `error[3000]`.

**New fixtures (13 dirs + 1 standalone).** Reject controls `repro/mi_matrix/undef_ident_{call,call_args,arg,return,value,index,discard,cond,binop,call_of_call,paren_call,fieldbase}_reject_xmod` + cross-module `undef_ident_xmod_reject_xmod` (`main.zig` + `lib.zig`), all `error[20]` / 0 `.c` / class **FAIL** (the canonical classifier GREENs only `error[3000]`); `undef_ident_fieldbase_reject_xmod` pins the single-diagnostic dedup; `undef_ident_xmod_reject_xmod` pins the imported-file span (`lib.zig:5:4`). Standalone `repro/undef_ident.z98`. Positive controls unchanged and still OK: `stdlib_nested_mod_call_xmod`, `fn_ptr_local_bare`, plus valid free-fn / forward-reference / mutual-recursion / forward-type / shadowing / enum-member programs.

**Re-baseline — `diag_excerpt_multifile_xmod`.** The fixture deliberately used an undeclared `missing` at `mod.zig:6:6` to pin the per-file diagnostic-excerpt renderer (tolerated `warning[3000]`, rc=0, 5 `.c`). Under variant S that now also emits `error[20]` (rc=2, 0 `.c`, class FAIL). To preserve the renderer pin and the rc=0 / 5 `.c` contract, the span source is a declared `fn nop() void` helper called at the same position (`y = nop();`, line 6 col 6) — the excerpt is byte-identical under the base and fixed compilers. Pre-baseline, the fixed compiler moves this dir OK→FAIL; after the re-baseline it stays OK (no movement).

**Residuals (distinct root causes; NOT covered by variant S).** `undefined()` (literal callee; callability, 6D's domain); `s.nope()` (unknown field on a known aggregate; field resolution); unknown **type names** in parameter/return/pointee position (`fn f(a: nope)`, `fn f() nope`, `var p: *nope`) — resolved by `type_resolver`, silently accepted.

**Gates (seed-built fixed-point compiler `923fe0f041704c1e4a21af6c7fbc513f`).** Self-compile two-hop closure hop1 == hop2 == `923fe0f0…`; self-emission rc=0, 0 `error[...]`, 0 PANIC. 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. Example matrix **24/24** dump/gcc/link (all `examples/z98` classify OK in the corpus universe). Std-lib runtime gate **211 PASS / 0 FAIL**. Corpus `-s0` **972 dirs = 867 OK / 42 GREEN / 63 FAIL / 0 ICE / 0 CRASH** (v186 959 → 972: the 13 new fixture dirs, FAIL under both compilers); a full-classifier join-diff vs the pre-fix seed v66 compiler over the same 972 dirs is **byte-identical (zero class movement)**. `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `d62848983b239405407ad9a2cec9c609` -> `923fe0f041704c1e4a21af6c7fbc513f`**; seed **v66 -> v67** (archive md5 `dbe6b19aa232c56fd1bb8e0aa21af8fa` -> `855a88689457f631df7c42c903c69c5a`).

## Task 6D — diagnose a call whose callee is not a function (v185 -> v186 2026-09-22)

A call whose callee resolves to a **non-function value** was never checked for callability. Official Zig rejects this at compile time (`error: expected type 'fn()', found 'usize'` / "expression is not callable"), but Z98 compiled it **rc=0 with no diagnostic** and emitted C that gcc rejects. For the reported nested-module shape `std.io.INVALID_FD()` (where `INVALID_FD` is a `usize` const) the emitted call was `(void)zG_CC81CC5F_INVALID_FD();` → gcc `called object ... is not a function`. The gap was **general, not nested-specific**: a local `const x: u32 = 5; x();`, a `bool`/struct/enum value called, and a flat non-pub module member (`const io = @import("std_io.zig"); io.INVALID_FD();`) all emitted invalid C on the same path.

**Root cause (Task 6C).** `sf/src/lower.zig`'s generic `fn_call` path lowered the callee as a **value** (`callee_temp = lowerExpr(...)`) and emitted an indirect `LirInst.call` **without verifying the callee was callable**. The semantic analyzer's `semanticAnalyzerResolveFnCall` non-`fn_type` branch (`semantic_analyzer.zig`) also returned `TYPE_VOID` with no diagnostic — the spec's `resolveFnCall` (`docs/sf/TYPE_SYSTEM_p2.md`) says it should emit "expression is not callable".

**Fix (Task 6D, variant C — lowering callability check on the lowered callee temp).** Immediately after `callee_temp = lowerExpr(self, node.child_0)`, `sf/src/lower.zig` inspects the lowered callee temp's type via `getTempType`. If it is neither a `fn_type` nor a pointer to a `fn_type` (and is not `TYPE_VOID`/`TYPE_UNDEFINED`, so the Task 6B undefined-member `error[3042]` path is preserved), it emits the new **`error[3056]: expression is not callable`** (`ERR_3056_CALL_TARGET_NOT_CALLABLE` added to `sf/src/diagnostics.zig`; 3056 was free — 3055 was the max) and returns a `TYPE_VOID` dummy. The post-`phase_LIRLowering` `hasErrors` gate then exits rc=2 with 0 `.c`. Keying on the **lowered** temp type (not the resolved-type table) covers the flat non-pub member (which sema types as `TYPE_VOID`) as well as the nested/local/bool/struct/enum shapes. Valid function calls and function-pointer calls are unchanged.

**New fixtures (4 dirs + 1 standalone).** Reject controls `repro/mi_matrix/nonfn_member_call_reject_xmod` (nested `std.io.INVALID_FD()`), `nonfn_member_call_args_reject_xmod` (`std.io.INVALID_FD(1, 2)`), `nonfn_local_call_reject_xmod` (`const x: u32 = 5; x();`), `nonfn_flat_member_call_reject_xmod` (flat non-pub `io.INVALID_FD()`) — all `error[3056]`, 0 `.c`, class **FAIL** (the canonical classifier GREENs only `error[3000]`). Standalone `repro/nonfn_member_call.z98`. Positive runtime controls unchanged and still OK: `repro/mi_matrix/stdlib_nested_mod_call_xmod` (valid nested `std.io.print`/`printInt`) and `repro/mi_matrix/fn_ptr_local_bare` (valid function-pointer call). The Task 6B undefined-member path is unchanged (`error[3042]` + `warning[3023]`). Stdlib pin **211** (no new stdlib fixture).

**Gates (seed-built fixed-point compiler `d62848983b239405407ad9a2cec9c609`).** Self-compile two-hop closure hop1 == hop2 == `d6284898…`; self-emission rc=0, 0 `error[...]`, 0 PANIC. 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. Example matrix **24/24** dump/gcc/link (all `examples/z98` classify OK in the corpus universe). Std-lib runtime gate **211 PASS / 0 FAIL**. Corpus `-s0` **959 dirs = 867 OK / 42 GREEN / 50 FAIL / 0 ICE / 0 CRASH** (v185 955 → 959: the 4 new fixture dirs); a full-classifier join-diff vs the pre-fix seed v65 compiler over the same 959 dirs is **byte-identical (zero class movement)** — the new reject fixtures were already FAIL pre-fix (invalid C) and are FAIL post-fix (clean reject). `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `845165786674f82870abea053616d0d2` -> `d62848983b239405407ad9a2cec9c609`**; seed **v65 -> v66** (archive md5 `2f2ba33a3239a1b004e9e242b0c01e3b` -> `dbe6b19aa232c56fd1bb8e0aa21af8fa`).

## Task 6B — reject a call to an undefined member of a nested module (v184 -> v185 2026-09-22)

A call to an undefined member of a **nested** module (`std.io.printt("y\n")`) is invalid Zig (official Zig: `error: root source file struct 'std' has no member named 'printt'`), but Z98 compiled it **rc=0 with no diagnostic** and the call was **silently dropped from the emitted C** — the typo changed program behaviour. The flat base `std.nope()` was already correctly rejected (`error[3042]`).

**Root cause (Task 6A).** `sf/src/lower.zig`'s `fn_call` field-access callee path (`:3984-4007`) early-`return`ed temp 0 when the nested-module chain walk failed, bypassing the generic call path (`:4193`) that lowers the callee as a value and emits the existing `error[3042]` + `warning[3023]` with 0 `.c`. A secondary latent defect in the same block: the `chain: [4]u32` buffer overran for a base with >=4 field-access levels (`std.io.a.b.c.d()`, `chain_len` reaches 5) — an out-of-bounds stack write (observed benign).

**Fix (`sf/src/lower.zig` only).** Declare `var chain_valid: u8 = 1;`; bound the chain walk (`while (... and chain_len < 4)`); at every failure point set `chain_valid = 0` (breaking out of the lookup loop for the two in-loop sites) instead of `return 0`; guard the direct cross-module handling with `if (chain_valid == 1) { ... }` so a failed chain falls through to the generic call path. A valid nested call resolves to a `fn_type` at the top of `fn_call` (`:3834`) and never reaches this block, so no valid program's emission changes.

**New fixtures (3 dirs + 1 standalone).** Reject controls `repro/mi_matrix/nested_mod_undef_member_reject_xmod` (`std.io.printt`, `error[3042]`/0 `.c`) + `nested_mod_deep_chain_reject_xmod` (`std.io.a.b.c.d()`, the chain-bound guard; `error[3042]`/0 `.c`) — both class **FAIL** (the canonical classifier GREENs only `error[3000]`). Positive runtime control `repro/mi_matrix/stdlib_nested_mod_call_xmod` (valid nested `std.io.print`/`printInt`; `@panic`-guarded; deterministic stdout `nested-ok` / `int=42` / `done`, rc 0; golden md5 `3ddec145fd468d69e7cb36e04cbf8919`) — class **OK** under both compilers, so the fix cannot over-reject. Standalone `repro/nested_mod_undef_member.z98`. Stdlib pin **210 -> 211**.

**Gates (seed-built fixed-point compiler `845165786674f82870abea053616d0d2`).** Self-compile two-hop closure hop1 == hop2 == `84516578…`; self-emission rc=0, 48 `.c`, 0 `error[...]`, 0 PANIC. 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. Example matrix **24/24** dump/gcc/link. Std-lib runtime gate **211 PASS / 0 FAIL**. Corpus `-s0` **955 dirs = 867 OK / 42 GREEN / 46 FAIL / 0 ICE / 0 CRASH** (v184 952 → 955: the 3 new fixture dirs); a full-classifier join-diff vs the pre-fix seed v64 compiler moves EXACTLY `nested_mod_undef_member_reject_xmod` + `nested_mod_deep_chain_reject_xmod` (OK→FAIL) — **zero other pre-existing class movement**. `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `17a476d2543c2ca9dcf0d7e7cb09ba01` -> `845165786674f82870abea053616d0d2`**; seed **v64 -> v65** (archive md5 `0abd7af67a38bb26d92953245e32944e` -> `2f2ba33a3239a1b004e9e242b0c01e3b`).

## Task 5B — win32 default-lib-path lookup: `pal.fileExists` → `pal.dirExists` (v183 -> v184 2026-09-22)

The default standard-library lookup `<exe_dir>/lib` was guarded by `pal.fileExists`, which is `fopen(path,"rb")` + `fclose` (`sf/src/pal.zig:54-66`). On win32 the CRT **refuses to `fopen` a directory**, so `phase_ImportResolution` never added `<exe_dir>/lib` as a search dir and a bare `@import("std")` failed `error[3048]: could not resolve imported file 'std'` unless the user passed `-I lib`. On Linux glibc `fopen`s a directory, so the same layout worked and the defect was invisible there.

**Fix.** `sf/src/main.zig:437` `pal.fileExists(lib_path)` → `pal.dirExists(lib_path)`. The default lib path always names a directory (`pal_get_default_lib_path` appends the literal `lib` to `<exe_dir>`), so the existence probe must be a directory probe; `pal.dirExists` → `pal_dir_exists` uses `GetFileAttributesA`/`FILE_ATTRIBUTE_DIRECTORY` on win32 and `stat`/`S_IFDIR` on POSIX (already used at `main.zig:164` for the output-dir check). `pal.fileExists` itself is UNCHANGED — its remaining callers (`sf/src/module_registry.zig:174,177`) resolve candidate `.zig` **files**, and broadening it would let a directory named `std` intern as a module path.

**Linux gates cannot discriminate this fix** (glibc `fopen`s a directory). The real RED/GREEN proof is win32: pre-fix `error[3048]` rc=2 / 0 `.c`; post-fix rc=0 with the full std closure. It is pinned by the new gate `scripts/win32_cross/default_lib_lookup.sh` (builds the win32 compiler from the seed's self-emission C, copies `lib/` beside `zig1.exe`, runs a `std`-importing program from the exe dir with no `-I` under `wine`).

**New fixtures (1 dir + 1 standalone).** Linux positive control `repro/mi_matrix/stdlib_default_lib_lookup_xmod` (bare `@import("std")` plus a `std_parse.zig` path import, NO `-I`; pulls in `std_io`/`std_str`/`std_math`/`std_parse`; `@panic`-guarded; deterministic stdout `default-lib-lookup-ok / len=3 / max=9 / parsed=-42 / done`, rc 0). Standalone `repro/default_lib_lookup.z98`. Stdlib pin **209 -> 210**.

**Gates (seed-built fixed-point compiler `17a476d2543c2ca9dcf0d7e7cb09ba01`).** Self-compile two-hop closure hop1 == hop2 == `17a476d2…`; self-emission rc=0, 48 `.c`, 0 `error[...]`, 0 PANIC. 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. Example matrix **24/24** dump/gcc/link. Std-lib runtime gate **210 PASS / 0 FAIL**. Corpus `-s0` **952 dirs = 866 OK / 42 GREEN / 44 FAIL / 0 ICE / 0 CRASH** (v183 951 → 952: the 1 new fixture dir, OK under both compilers); a full-classifier join-diff vs the pre-fix seed v63 compiler is **byte-identical (zero class movement)**. `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `5d792f50cea61b9ef09fbd353c4557b0` -> `17a476d2543c2ca9dcf0d7e7cb09ba01`**; seed **v63 -> v64** (archive md5 `71880fbdabf20b542389031ab5cbdc11` -> `0abd7af67a38bb26d92953245e32944e`).

## Task B2 final fix wave — compound/var local type values + >32-field local aggregates (v182 -> v183 2026-09-21)

Final whole-branch review of the function-local / inline named-type plan (Goal: function-local / inline named types must emit valid C, or cleanly reject — never emit C that fails to compile). Four findings fixed.

**Finding 1 (Important) — compound function-local type aliases leaked `TYPE_TYPE` → uncompilable C.** Inside a function, `const P = *E;` (also `const Q = E!i32;`, `const R = [N]E;`, `const S = ?E;`, where `E` is a local type) returned `TYPE_TYPE` from `semanticAnalyzerResolveExpr`'s ptr/array/optional/error-union arms and leaked to emission: dump rc=0, a `warning[3000]`, then gcc `unknown type name 'zT_5127F14D_type'`. Official Zig accepts these (local `type` aliases); the plan's B2 decision is "local type alias → clean-reject", and the existing guard only checked `vd_init_node.kind == AstKind.ident_expr` (so only the bare `const F = E;` clean-rejected). Fix: the `var_decl` guard now also rejects a compound type-expression initializer via the new `type_resolver.isCompoundTypeExprKind` (`*E`/`[*]E`/`[N]E`/`[]E`/`?E`/`E!T`/`fn(...)T`), matching the bare-alias behavior.

**Finding 3 (Minor) — `var x = struct {…};` leaked `TYPE_TYPE` → uncompilable C.** Invalid Zig (a `type` value must be `const`/comptime) but Z98 accepted it and emitted `unknown type name 'zT_5127F14D_type'`. Fix: the guard now fires for a `var` binding of a container type with `error[3000]: a local type value must be declared with 'const'` (folded into the finding-1 guard).

**Finding 2 (Minor) — `[32]`-field buffer silently truncated.** `registerContainerType`'s fixed `[32]` field scratch buffers silently truncated a function-local/inline aggregate with more than 32 fields, then emitted a truncated C struct and miscompiled field access beyond the cap (`s.f32` aliased `s.f0`; a named-type field could reference an undeclared `zT_*`). Fix: a new `containerFieldCount` pre-count clean-rejects `> MAX_CONTAINER_FIELDS` (32) with `error[3000]` and 0 `.c` before registering; the field buffers/loops now share the `MAX_CONTAINER_FIELDS` constant.

**Finding 4 (Minor) — stale comments.** `scripts/check_emit_support.sh:16` and `scripts/seed/build_from_seed.sh:24` said "20 std .zig"; corrected to 29 (`lib/` holds 29).

**New fixtures (4 dirs + 2 standalone).** Reject controls `local_type_alias_compound_reject_xmod` (`*E`/`E!i32`/`[2]E`/`?E`), `local_type_var_container_reject_xmod` (`var x = struct{…}`), `local_type_fieldcap_reject_xmod` (33-field struct) — all `error[3000]`, 0 `.c`, GREEN. Positive runtime control `stdlib_local_type_fieldcap_xmod` (exactly 32 fields; `@panic`-guarded, deterministic stdout `fieldcap-32-ok / done`, rc 0). Standalones `repro/local_type_alias_compound_reject.z98` and `repro/local_type_fieldcap_reject.z98`. Stdlib pin **208 -> 209**.

**Gates (seed-built fixed-point compiler `5d792f50cea61b9ef09fbd353c4557b0`).** Self-compile two-hop closure hop1 == hop2 == `5d792f50…`; self-emission rc=0, 48 `.c`, 0 `error[...]`, 0 PANIC. 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. 21-example matrix **21/21**. Std-lib runtime gate **209 PASS / 0 FAIL**. Corpus `-s0` **951 dirs = 865 OK / 42 GREEN / 44 FAIL / 0 ICE / 0 CRASH** (v182 947 → 951: the 4 new fixture dirs); a full-classifier join-diff vs the pre-fix seed v62 compiler moves EXACTLY `local_type_alias_compound_reject_xmod` (FAIL→GREEN) + `local_type_fieldcap_reject_xmod` (OK→GREEN) + `local_type_var_container_reject_xmod` (FAIL→GREEN) — **zero other pre-existing class movement** (the new positive control is OK under both). `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `6322cd4f916a7cc47c883b22f1f44905` -> `5d792f50cea61b9ef09fbd353c4557b0`**; seed **v62 -> v63** (archive md5 `e083175349cef5e1369d961aa0795837` -> `71880fbdabf20b542389031ab5cbdc11`). Declared divergence: a function-local `type` value — a bare local alias (`const F = E;`) AND a compound type expression (`const P = *E;`, `const Q = E!i32;`, `const R = [N]E;`, `const S = ?E;`), as well as a `var` container binding — clean-rejects although official Zig allows it; Z98 does not model function-local `type` values.

## Task B5 — cleanly reject runtime payload-differing error-union coercions (v181 -> v182 2026-09-21)

A runtime error-union→error-union coercion whose payloads differ (`F!i32 → E!i64`) is **invalid Zig**. Official Zig's EU→EU rule requires the destination error set to be a superset (`E1 ⊆ E2`) **and the payloads to be in-memory identical**; only comptime-known values may coerce (verified on Zig 0.13.0 by Task B4, and on 0.10.1/0.14.1 by the reviewer). Z98 **accepted** the invalid program and emitted C that failed to compile (`incompatible types when assigning to type 'zT_..._EU_7' from type 'zT_..._EU_6'`).

**Root cause.** `sf/src/type_registry.zig`'s EU→EU assignability branch (`typeRegistryIsAssignable`) accepted the coercion whenever the payloads were merely *assignable* — integer widening (`i32 → i64`) qualifies — instead of requiring in-memory-identical payloads. That single branch gates every EU→EU context (return, assignment, var-declaration, call argument), so one fix closes all of them.

**Fix.** The branch now requires exact payload TypeId equality: `return eu_src.payload == eu_tgt.payload;`. This is the operator's "option 1" (clean-reject at the type layer, aligning with official Zig), not a rewrap. The same-payload subset path (`F!i32 → E!i32`) is unchanged and emits byte-identical C; the existing `repro/mi_matrix/stdlib_errdefer_dyn_xmod` `subErr` case (Task 10F) remains the positive runtime control. The `try` path (payload→EU, not EU→EU) is unaffected.

**Declared stricter-than-Zig divergences (safe clean rejects; exact payload equality is also what the payload-keyed C EU typedef can represent without a rewrap):** any in-memory qualifier difference in the payload is rejected, e.g. pointer-qualifier EU→EU (`F!*u8 → E!*const u8`) and slice-qualifier EU→EU (`F![]u8 → E![]const u8`), both Zig-accepted; and comptime-known payload-differing EU→EU (`const x: F!i32 = 5; return x;`, Zig-accepted) is rejected.

**New fixtures (2 dirs + 1 standalone).** Reject control `repro/mi_matrix/eu_payload_diff_reject_xmod` (`error[3000]`, 0 `.c`; exercises the ordinary return, the errdefer/dynamic return, var-declaration initialization, assignment, and call-argument shapes in one file). Positive runtime control `repro/mi_matrix/stdlib_eu_samepayload_xmod` (same payload `F!i32 → E!i32`, with and without `errdefer`; error tag and success payload `@panic`-guarded; deterministic stdout `undo / ederr-caught / 7 / noederr-caught / 7 / done`, rc 0). Standalone `repro/eu_payload_diff_reject.z98`. Stdlib pin **207 -> 208**.

**Gates (seed-built fixed-point compiler `6322cd4f916a7cc47c883b22f1f44905`).** Self-compile two-hop closure hop1 == hop2 == `6322cd4f…`; 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. 21-example matrix **21/21**. Std-lib runtime gate **208 PASS / 0 FAIL**. Corpus `-s0` **947 dirs = 864 OK / 39 GREEN / 44 FAIL / 0 ICE / 0 CRASH** (v181 945 → 947: the 2 new fixture dirs); a full-classifier join-diff vs the pre-fix seed v61 compiler moves EXACTLY `eu_payload_diff_reject_xmod` (FAIL→GREEN) — **zero other pre-existing class movement** (the new positive control is OK under both compilers). Same-payload byte-identity: `stdlib_errdefer_dyn_xmod`'s emitted `.c`/`.h` are byte-identical pre/post (verified with both compilers installed at the same path). `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `31f61d870ee93f97bb0e01cc76c629cd` -> `6322cd4f916a7cc47c883b22f1f44905`**; seed **v61 -> v62** (archive md5 recorded in `release/seed/CHANGELOG.md`).

## Task B3 — resolve the carried Phase 0 deferred minors (v180 -> v181 2026-09-21)

Seven independent deferred minors carried from the Phase 0 program (operator ruling 2026-09-21).

**Item 1 — restore the `@intCast` runtime widening-sign-change trap coverage.** The Task 11U option-A re-pin turned `safe_intcast_widen_sign_xmod` into a comptime reject, dropping the A18 runtime trap pin. New pinned runtime fixture `stdlib_intcast_widen_sign_runtime_xmod` (`i8 -1 -> u16` through a runtime helper parameter): `-ffast` prints `65535` (rc 0, the committed golden), `-fsafe` traps (`panic: integer cast overflow in @intCast`, empty stdout, rc 133). Standalone `repro/intcast_widen_sign_runtime.z98`.

**Item 2 — range-check 64-bit-target casts.** `comptimeValFitsType` (`comptime_eval.zig`) and `intValueFitsType` (`type_resolver.zig`) both `return true` for every `wb >= 64` target, so `@intCast(u64,-1)` / `@as(u64,-1)` folded to `18446744073709551615` and `@intCast(i64, @as(u64, 18446744073709551615))` to `-1` — invalid Zig. The 64-bit bit pattern cannot distinguish a negative source from a large non-negative literal (both have the top bit set), so the new syntactic classifiers `comptimeEvalSignClass` / `evalConstSignClass` (tri-state `unknown`/`negative`/`non_negative`; `unknown` is never rejected, so valid programs are not over-rejected) decide: a definitely-negative source cannot fit an unsigned 64-bit target, and a definitely-non-negative source above i64 max cannot fit a signed one. New reject controls `comptime_cast64_range_reject_xmod` (GREEN, `error[3000]`) + `enum_init_cast64_range_reject_xmod` (`error[3055]`, FAIL bucket, consistent with the other `enum_init_*_reject_xmod`); positive `stdlib_comptime_cast64_range_xmod`; standalone `repro/comptime_cast64_range.z98`.

**Item 3 — generalize the `@as` diagnostic wording.** The shared `@intCast`/`@as` reject arm now selects `@intCast value does not fit the target type` vs `@as value does not fit the target type` from `node.child_0` instead of always naming `@intCast`.

**Item 4 — give the comptime-cast reject a real location.** Not feasible without a structural change, and documented: `phase_ComptimeEvaluation` is a single global node sweep with no per-module context and the AST store carries no node→source_file map, so `source_file_id` stays `0` (the message prints without a `file:line`; the node span is still recorded). A real location needs per-module node ranges or a node→module table.

**Item 5 — fix the seed `SEED_README.txt` count.** `scripts/seed/archive_seed.sh` wrote "20 std .zig" while `lib/` holds 29; the generator now says 29 and lists all 29 in the `SEED_README.txt` contents block, the std-install note, and the header comment.

**Item 6 — fix the Task 10D call-site comment.** `sf/src/semantic_analyzer.zig`'s `defer_stmt`/`errdefer_stmt` arm comment corrected: the `semanticAnalyzerCheckDeferBody` walk deliberately does NOT descend into a nested defer/errdefer; the nested body is validated by its own invocation when the statement walk reaches it, with the inner-target state reset here so the nested scope starts from a clean `cur_defer_node` chain (comment only, no behavior change).

**Item 7 — reconcile the EXPECTED_FAIL narration.** The Task 11U section's "202 -> 203 -> 204" narration is reconciled to the actual single pin bump **202 -> 204** (the two fixtures were added and pinned together).

**New fixtures (4 dirs + 2 standalone).** Two pinned `stdlib_*`: `stdlib_intcast_widen_sign_runtime_xmod` (item 1; `-ffast` golden `65535`/rc 0) and `stdlib_comptime_cast64_range_xmod` (item 2 positive: `@as(u64, 18446744073709551615)`, untyped/typed u64-max consts, `@as(i64,-1)`, `@as(u64,5)`, all `@panic`-guarded). Two reject controls: `comptime_cast64_range_reject_xmod` (`error[3000]`) and `enum_init_cast64_range_reject_xmod` (`error[3055]`). Standalones `repro/intcast_widen_sign_runtime.z98` and `repro/comptime_cast64_range.z98`. Stdlib pin **205 -> 207**.

**Gates (seed-built fixed-point compiler `31f61d870ee93f97bb0e01cc76c629cd`).** Self-compile two-hop closure hop1 == hop2 == `31f61d87…`; self-emission rc=0, 48 `.c`, 0 `error[...]`, 0 PANIC. 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. 21-example matrix **21/21**. Std-lib runtime gate **207 PASS / 0 FAIL**. Corpus `-s0` **945 dirs = 863 OK / 38 GREEN / 44 FAIL / 0 ICE / 0 CRASH** (v180 941 → 945: the 4 new fixture dirs); a full-classifier join-diff vs the pre-fix seed v60 compiler moves EXACTLY `comptime_cast64_range_reject_xmod` (OK→GREEN) + `enum_init_cast64_range_reject_xmod` (OK→FAIL) — **zero other pre-existing class movement**. `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `603d835a31d3a8c051f75cc608c477c4` -> `31f61d870ee93f97bb0e01cc76c629cd`**; seed **v60 -> v61** (archive md5 recorded in `release/seed/CHANGELOG.md`).

## Task B2 fix round 1 — union `fields_start` order + inline-enum validation (v179 -> v180 2026-09-21)

Two review defects in the Task B2 implementation.

**(Critical 1) Union payload `fields_start` captured before field-type resolution.**
`registerContainerType`'s union branch captured `un_fstart = fe_len` BEFORE the field-resolution
loop. Resolving a nested anonymous aggregate field appends its own `fe` entries, so the union's
`UnionPayload`/`TaggedUnionPayload.fields_start` pointed into the nested type's fields — e.g.
`const U = union { b: u8, a: struct { x: u32 } };` emitted `union { unsigned int x; unsigned char b; }`
(field `a` gone, spurious `x`), and `var u: U = U{ .a = .{ .x = 5 } }; u.a.x` failed at gcc/at
runtime. The module-level inline form (`var g: union { b: u8, a: struct{x:u32} } = ...`) was affected
too. Fix: capture `un_fstart` AFTER the resolve loop, mirroring the struct branch. New positive
fixture cases `localUnionNested` + `localPackedUnion` + inline `union { b: u8, a: struct{x:u32} }`
in `stdlib_local_type_emission_xmod`.

**(Important 2) Inline `enum` bypassed `semanticAnalyzerCheckLocalEnum`.**
`semanticAnalyzerCheckLocalEnum` ran only for the binding form and the expression arm; an inline
annotation (`var e: enum(u8){...}`) went `resolveTypeExprFull` -> `registerContainerType` ->
`populateTypePayload`, whose `enumMembersResolve(..., strict=false)` result was discarded — so
`var e: enum(u8){ A = 1, B = 1 }` was silently accepted (rc=0) and `enum(u8){ A = @intToFloat(f32,1) }`
silently tagged `A = 0`. Fix: the strict walk + `ERR_3055` emission is factored into ONE shared
`type_resolver.validateLocalEnum(env, enum_node)` (MarkNodeOnce + `enumMembersResolve(check_only,
strict)`); `registerContainerType` calls it for every enum BEFORE the name-cache short-circuit, and
`semanticAnalyzerCheckLocalEnum` now delegates to it. New reject controls
`enum_init_inline_duplicate_reject_xmod` and `enum_init_inline_nonconstant_reject_xmod`
(`error[3055]`, 0 `.c`).

**Minor.** `sf/docs/tech_docs/02_symbol_registration.md` corrected `populateTypePayload` private ->
`pub`. Recorded (not changed): the lower `enum_type` field-access arm mirrors the module `type_alias`
arm (design-permitted); `registerContainerType`'s `[32]` field buffer silently truncates >32-field
local/inline aggregates; `LocalTypeScope` is function-scoped, not block-scoped (design-sanctioned);
the positive fixture now also covers packed unions.

**Gates (seed-built fixed-point compiler `603d835a31d3a8c051f75cc608c477c4`).** Self-compile two-hop
closure hop1 == hop2 == `603d835a…` — the fixed point MOVED (`af757cca…` -> `603d835a…`). Corpus `-s0`
**941 dirs = 861 OK / 37 GREEN / 43 FAIL / 0 ICE / 0 CRASH** (v179 939 -> 941: the 2 new reject fixture
dirs); a full-classifier join-diff vs the pre-fix-round v59 compiler (`af757cca…`, 941 dirs = 860 OK /
39 GREEN / 42 FAIL) moves EXACTLY `stdlib_local_type_emission_xmod` (GREEN -> OK), `local_type_alias_reject_xmod`
(FAIL -> GREEN), and the two new inline-enum reject controls (GREEN -> FAIL — the pre-fix-round compiler
accepted them; the fixed compiler rejects with the dedicated `error[3055]`, which buckets FAIL like the
existing `enum_init_local_duplicate_reject_xmod`) — **zero other pre-existing class movement**. 4-MD5
emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137`
/ json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. 21-example matrix
**21/21**; std-lib runtime gate **205 PASS / 0 FAIL**; `check_emit_support.sh` 7/7; `verify_upgraded.sh`
CLOSEOUT OK. Fixed point **MOVED `af757cca4c6ca77f2197e1e39d8cd818` -> `603d835a31d3a8c051f75cc608c477c4`**;
seed **v59 -> v60**. Rotated-seed round-trip hop1 == hop2 == `603d835a…`.

## Task B2 — function-local / inline named-type emission (v178 -> v179 2026-09-21)

The F half of the operator-inserted B1/B2 pair (B1 is the reviewer-corrected investigation; operator ruling "proceed with A" = full Zig parity for compound local-type uses). A function-local named type (`fn f() void { const E = enum(u8){A=1,B}; var e: E = E.A; }`) and an inline container type in an annotation / return / parameter position emitted C that failed to compile. Root cause: `semanticAnalyzerResolveExpr`'s container-decl arm returned `TYPE_TYPE` without registering a named type, and `lower.zig` lowered the binding as a runtime local of `TYPE_TYPE`; `getCTypeName(TYPE_TYPE)` fell through to `nameManglerMangle("type", ...)` -> `zT_5127F14D_type`, a typedef never emitted (`unknown type name 'zT_5127F14D_type'`). Inline `enum`/`union` additionally had no `resolveTypeExprFull` arm, so an annotation resolved to `TYPE_UNDEFINED` -> `cannot declare variable of type void`; a local error set used in an error union (`E!T`) rejected with a spurious `error[3011]`.

**Fix (5 files).** `sf/src/type_resolver.zig`: ONE shared `registerContainerType(env, node_idx, kind, depth)` registers a synthesized `anon_<node_idx>` type (module 0, extracted `containerAnonNameId`) and populates the payload — struct/union field types are resolved DIRECTLY (the module-only `resolveAggregateFieldTypesAll` never visits local/inline aggregates, and `populateTypePayload` leaves their fields `VOID`), while enum/error-set payloads reuse the now-`pub` `symbol_registrator.populateTypePayload`. `resolveTypeExprFull`'s `struct_decl` arm delegates to it and new `enum_decl`/`union_decl` arms are added; the inline-`struct` registration order/name is preserved so its emitted C stays byte-identical. `TypeResolveEnv` gains a function-local type scope (`LocalTypeScope`, `name_id -> TypeId`, with `localTypeScopeInit`/`Push`/`Lookup`), consulted FIRST in the `ident_expr` arm so compound uses (`E!T`, `*E`, `[N]E`, `?E`) resolve; `layoutEnsure` is now `pub`. `sf/src/semantic_analyzer.zig`: the `var_decl` arm binds a local `const T = <container>{...}` as a TYPE (`registerContainerType` + `layoutEnsure` + `local_decl_names`/`local_decl_types` + `local_types`, NO `nameCachePut`) and skips the value path; `semanticAnalyzerResolveFnBody` resets `local_types.count`. `sf/src/lower.zig`: the `var_decl` arm emits one `decl_local` storage slot of the registered type for a type binding and skips the value initializer (the value path returns early), and `field_access`'s generic base-type path gains an `enum_type` arm (mirroring the existing `error_set_type` arm) so a local enum's `E.A` emits `enum_const`. `sf/src/symbol_registrator.zig`: `populateTypePayload` becomes `pub`.

**New fixtures (2 + standalone).** One positive runtime fixture `stdlib_local_type_emission_xmod` (stdlib pin 204 -> 205): local `enum`/`struct`/`union`/`tagged union`/`packed struct`/`error{...}`/`error{...}!T`, compound uses (`*E`, `[2]E`, `?E`), `_ = E` discard, and inline `enum`/`union`/`struct`/`error{...}` in annotation + return positions — every check `@panic`-guarded, deterministic stdout, rc 0. One clean-reject control `local_type_alias_reject_xmod` (non-`stdlib_*`): `const F = E;` where `E` is a function-local named type is a documented divergence (official Zig allows local `type` values; this compiler does not model them) -> `error[3000]`, 0 `.c`, GREEN. Standalone repro `repro/local_type_emission.z98`. `enum_init_local_duplicate_reject_xmod` stays a reject (`error[3055]`).

**Gates (seed-built fixed-point compiler `af757cca4c6ca77f2197e1e39d8cd818`).** Self-compile two-hop closure hop1 == hop2 == `af757cca…` — the fixed point MOVED (`81339077…` -> `af757cca…`). Corpus `-s0` **939 dirs = 861 OK / 37 GREEN / 41 FAIL / 0 ICE / 0 CRASH** (v178 937 -> 939: the 2 new fixture dirs); a full-classifier join-diff vs the pre-fix seed v58 compiler (`81339077…`, 939 dirs = 860 OK / 37 GREEN / 42 FAIL) moves EXACTLY `stdlib_local_type_emission_xmod` (GREEN -> OK) and `local_type_alias_reject_xmod` (FAIL -> GREEN) — **zero other pre-existing class movement**. 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07` (the lisp gate's inline struct is on the preserved path). 21-example matrix **21/21**; std-lib runtime gate **205 PASS / 0 FAIL**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `81339077a8d0bbec3e02bd914c3b33d1` -> `af757cca4c6ca77f2197e1e39d8cd818`**; seed **v58 -> v59** (archive md5 recorded in `release/seed/CHANGELOG.md`). Rotated-seed round-trip hop1 == hop2 == `af757cca…`.

**Residuals (documented).** (1) `@sizeOf`/`@alignOf` on a function-local or inline aggregate still ICEs (`error[3043]`) because the comptime evaluator (`comptime_eval.zig`, `phase_ComptimeEvaluation`) runs at module scope with no function-local type scope — pre-existing for inline aggregates on the base compiler too. (2) Cross-anonymous-struct/union value assignment (`fn f(u: union{...})` called with a variable declared as a textually-identical but distinct anonymous union) emits a C type mismatch — also pre-existing on the base compiler for inline structs. (3) Local type aliases (`const F = E;`) clean-reject (divergence from official Zig).

## Task 11U — fold `@as` at comptime (integer targets only) (v177 -> v178 2026-09-21)

The F half of the operator-inserted Task 11T/11U pair (11T is the corrected investigation; AMENDMENT 15 ruled the **general fix** plus **option A**). The `@as` gap was real and pre-existing: `sf/src/comptime_eval.zig` interned `@intCast` but never `@as`, and `comptimeEvalBuiltin`'s fold arm was gated on `int_cast_id` only, so `@as` never folded. For a typed `u64` const above `i64` max the const was elided from the emitted C while the un-folded runtime `int_to_float` still referenced it, so a valid Z98 program failed to build (gcc `'zG_..._X' undeclared`); for literal operands the fold was simply skipped. `@as` and `@intCast` share the exact extra-child layout `[target_type, value]`, so the `@intCast` fold/range-check arm is shared by widening its gate.

**Fix (4 edits, `sf/src/comptime_eval.zig`).** `ComptimeEval` gains `as_id`; `comptimeEvalInit` interns `@as` (10-name foldable set); `comptimeEvalBuiltin`'s arm is gated on `int_cast_id OR as_id`; `comptimeEvalOperandSigned`'s `builtin_call` arm mirrors the `@as` case. The shared arm carries a **mandatory integer-target guard** — `if (node.child_0 == self.as_id and !is_int_t) return null;` — because the arm yields an integer `ComptimeVal` that enters the integer binop evaluator: without it, a non-integer `@as` silently miscompiles float arithmetic (`const A: f64 = @as(f64,3)/2` folds as integer `3/2` = `1`, not `1.5`). `@intCast`'s non-integer behavior is deliberately unchanged (out of scope). An out-of-range `@as` integer target emits the same `error[3000]` as `@intCast` (the shared diagnostic names the builtin actually used — `@as` vs `@intCast`, since Task B3 item 3; the canonical classifier keys only on the error code).

**New fixtures (2 + standalone).** The two fixtures were added and pinned together, so the stdlib pin moves **202 -> 204** in one step (no intermediate 203). One positive runtime fixture `stdlib_comptime_inttofloat_as_xmod`: `@intToFloat(f64, @as(u64, U))` with `U: u64 = 18446744073709551615` compared against the runtime `tof_u` oracle, `@intToFloat(f64, @as(i64, -1))`, `@intToFloat(f64, @as(u64, 5))`, `@intToFloat(f32, @as(u32, 7))` — every comparison `@panic`-guarded; deterministic stdout, rc 0. One guard control `stdlib_as_float_guard_xmod` (also `stdlib_*`): `const A: f64 = @as(f64,3)/2` = `1.5`, `@as(f64,3)+2` = `5`, `@as(f64,10)*@as(f64,2)` = `20`; this fixture traps on the unguarded arm and passes on the guarded one. Standalone repro `repro/comptime_inttofloat_as.z98` (fold cases + the float guard). Fold visibility: the emitted `__module_init` spells the four constants as float literals with ZERO `int_to_float`/`float_cast` ops for them.

**Option A re-pin (authorized class movement).** `repro/mi_matrix/safe_intcast_widen_sign_xmod` is re-pinned from OK to GREEN: with `@as` folding, `@as(i8, -1)` is a comptime-known -1 and `@intCast(u16, -1)` is a comptime OUT-OF-RANGE cast, which official Zig rejects (`error[3000]`, 0 `.c`). The A18 RUNTIME widening-sign-change trap stays covered by the runtime-operand cast check (`intcast_range_check`); the in-range control `main_inrange.zig` (`i8 100 -> u16`) is kept and prints `100` rc=0.

**Gates (seed-built fixed-point compiler `81339077a8d0bbec3e02bd914c3b33d1`).** Self-compile two-hop closure hop2 == hop3 == `81339077…` (moving point). Corpus `-s0` **937 dirs = 860 OK / 36 GREEN / 41 FAIL / 0 ICE / 0 CRASH** (v177 935 → 937: the 2 new fixture dirs); a full-classifier join-diff vs the pre-fix seed v57 compiler (`5106cc87…`) moves EXACTLY `stdlib_comptime_inttofloat_as_xmod` (FAIL→OK — the pre-fix compiler reproduces the elided-const build failure) and `safe_intcast_widen_sign_xmod` (OK→GREEN, option A) — **zero other pre-existing class movement** (`stdlib_as_float_guard_xmod` is OK under both, since the guard defect is a runtime value error, not a compile error). 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. 21-example matrix **21/21**; std-lib runtime gate **204 PASS / 0 FAIL**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `5106cc8709c026c60eea113677a3fa5d` -> `81339077a8d0bbec3e02bd914c3b33d1`**; seed **v57 -> v58** (archive md5 `60c9ac10bd4382b6a25d7ef64daf2191` -> `d9059d3573654ddc477034d2e986463f`). Rotated-seed round-trip hop1 == hop2 == `81339077…`. Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-11U-report.md`.

## Task 11S — clean-reject invalid `@intCast` and `[*]T .len` (v176 -> v177 2026-09-21)

The F half of the operator-inserted Task 11R/11S pair (11R is the investigation; AMENDMENT 14 ruled D1 = use the existing `error[3000]` for all three rejects, D2 = include the `comptime_eval.zig` masking case). Three invalid-Zig constructs that were previously accepted with a silent value or a gcc-class failure now clean-reject (dump rc=2, 0 `.c`, `error[3000]`):

1. **(a) Array-size `@intCast` range check** (`sf/src/type_resolver.zig`, `evalConstU32Full`'s `builtin_call` arm). A Task 11F regression: the arm folded the operand (extra-child 1) and ignored the target type (extra-child 0), so `var a: [@intCast(u8, 300)]u8` folded to length 300 and compiled cleanly. The arm now resolves the target, folds the operand **with the U32 evaluator** (so a function-local `const N = 7` still resolves — this is why the i64 twin is not used), and requires `intValueFitsType(env, target, v)`; an out-of-range/non-integer target emits `error[3000]` (once per node) and returns the unfoldable sentinel (the array arm then also reports its pre-existing `error[3050]` cascade for the same source).
2. **(b) `.len` on `[*]T`** (`sf/src/semantic_analyzer.zig`, `semanticAnalyzerResolveFieldAccess`). The many-ptr branch auto-derefs `*T` and `[*]T`, and the final fallback returned `TYPE_VOID` with no diagnostic for an unrecognized field; `p.len` on `[*]u8` lowered to a void-typed temp (gcc `'zT_N' undeclared` in a range position; `cannot declare variable of type void` in a var decl). A new gate on the original `many_ptr_type` kind emits `error[3000]: many-item pointer has no field 'len'` for `.len`, in any position. `*T` keeps its pointee walk.
3. **(c) `comptime_eval.zig` `@intCast` masking** (`sf/src/comptime_eval.zig`). The `@intCast` arm masked to the target width, so `const X = @intCast(u8, 300);` folded to `(unsigned char)(44)` and ran silently. `ComptimeEval` gains a `diag` field (set from `main.zig`), a new `comptimeValFitsType` helper, and the arm now range-checks an integer target before masking; an out-of-range cast emits `error[3000]` (once per node) and stops folding, so `main.zig`'s post-`phase_SemanticAnalysis` diag check exits rc=2 before emission. `wb >= 64` is left as-is (no masking path).

**New fixtures (5).** Four clean-reject controls (non-`stdlib_*`, no stdlib pin): `array_size_intcast_range_reject_xmod` (`[@intCast(u8,300)]` + `[@intCast(u16,100000)]`), `manyptr_len_reject_xmod` (the **silent-lowering** shape: `return p.len` from a helper on a local `[*]u8` and on a struct-field `[*]u8` — OK under the baseline, GREEN only with the fix), `manyptr_len_range_reject_xmod` (the **range** shape: `for (0..p.len)` on a local and a struct-field `[*]u8` — gcc-class FAIL under the baseline, GREEN only with the fix), and `comptime_intcast_range_reject_xmod` (`@intCast(u8,300)` / `@intCast(u8,256)`). All GREEN (0 `.c` + `error[3000]`). One positive runtime fixture `stdlib_intcast_range_xmod` (stdlib pin 201 -> 202): in-range narrow `@intCast(u8,200)`/`@intCast(u16,1000)`, a function-local `const N` operand, `@intCast(u8,200)`, signed `@intCast(i32,-1)`, `[N]T`/slice `.len`, and `for (0..sl.len)`. Standalone repros `repro/array_size_intcast_range.z98`, `repro/manyptr_len.z98`, `repro/comptime_intcast_range.z98`.

**INTWIDTH supersession (authorized class movement).** `repro/mi_matrix/intwidth_cast_xmod` was re-pinned from OK (it deliberately tested out-of-range comptime `@intCast` truncate/mask: `@intCast(u3,255) -> 7`, `@intCast(u8,256) -> 0`) to GREEN (clean reject). AMENDMENT 14 supersedes the INTWIDTH design's truncate/mask rule: `@intCast` is range-checked (matching official Zig and `Language_Spec_Z98.md` §1.2); the truncate/mask behavior is covered by `intwidth_wrap_xmod`'s arithmetic wrap. The design doc §3.4/§5 is annotated accordingly. `repro/for_range_end.z98`'s stale scope note (the `[*]T` range shape was a gcc-class failure) is updated.

**Gates (seed-built fixed-point compiler `5106cc8709c026c60eea113677a3fa5d`).** Self-compile two-hop closure hop1 == hop2 == `5106cc87…` — the fixed point MOVED. Corpus `-s0` **935 dirs = 859 OK / 35 GREEN / 41 FAIL / 0 ICE / 0 CRASH** (v176 930 → 935: the 5 new fixture dirs); a full-classifier join-diff vs the pre-fix seed v56 compiler (`13434b4f…`) moves EXACTLY `array_size_intcast_range_reject_xmod` (OK→GREEN), `comptime_intcast_range_reject_xmod` (OK→GREEN), `manyptr_len_reject_xmod` (OK→GREEN, silent-lowering shape), `manyptr_len_range_reject_xmod` (FAIL→GREEN, gcc-class range shape), and `intwidth_cast_xmod` (OK→GREEN, authorized by the INTWIDTH supersession) — **zero other pre-existing class movement**. 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. 21-example matrix **21/21**; std-lib runtime gate **202 PASS / 0 FAIL**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `13434b4f4d5e5172b5a2422d5b6e043c` -> `5106cc8709c026c60eea113677a3fa5d`**; seed **v56 -> v57** (archive md5 `8073b3f3fef42d772cd58d19fd09ef2b` -> `60c9ac10bd4382b6a25d7ef64daf2191`). Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-11S-report.md`.

## Task 11J fix round 1 — reject invalid `@as`/`@intCast` and function-local duplicate tags (v175 -> v176 2026-09-21)

The operator-approved AMENDMENT 13 fix round on top of the Task 11J enum-initializer fold. Three review findings were fixed:

1. **`@as`/`@intCast` with a NON-INTEGER target** (`@as(f32,3)`, `@intCast(f32,3)`) folded the operand and silently compiled. `evalConstI64Full`'s cast arm now resolves the target type and requires `typeRegistryIsInteger`; otherwise `ERR_3055`.
2. **Out-of-range casts** (`@as(u8,300)`, `@intCast(u8,300)`, `@intCast(u32,-1)`) folded the raw value. The cast arm now range-checks the folded value against the target integer type's width/signedness via the new `intValueFitsType` helper (reusing the registry width/signedness helpers); otherwise `ERR_3055`.
3. **Function-local duplicate tags** (`fn f() void { const E = enum(u8){ A = 1, B = 1 }; }`) were accepted (the post-layout pass only sees module enums). The semantic analyzer's `enum_decl` expression arm now runs the SAME shared member walk (`enumMembersResolve`) in check-only strict mode via `semanticAnalyzerCheckLocalEnum`, so a function-local duplicate/unfoldable tag is a clean `ERR_3055`.

**New fixtures (3).** All are clean rejects (dump rc=2, 0 `.c`): `enum_init_cast_noninteger_reject_xmod` (`@as(f32,3)`/`@intCast(f32,3)`), `enum_init_cast_range_reject_xmod` (`@as(u8,300)`/`@intCast(u8,300)`/`@intCast(u32,-1)`), `enum_init_local_duplicate_reject_xmod` (function-local `A=1,B=1`). All bucket FAIL (the canonical classifier GREENs only `error[3000]`). The positive `stdlib_enum_init_expr_xmod` fixture is unchanged and still OK; the runtime `@panic` guards still pass.

**Gates (seed-built fixed-point compiler `13434b4f4d5e5172b5a2422d5b6e043c`).** Self-compile two-hop closure hop1 == hop2 == `13434b4f…` — the fixed point MOVED. Corpus `-s0` **930 dirs = 859 OK / 30 GREEN / 41 FAIL / 0 ICE / 0 CRASH** (v175 927 → 930: the 3 new fixture dirs only); a full-classifier join-diff vs the previous Task-11J compiler (`618a0115…`) moves EXACTLY `enum_init_cast_noninteger_reject_xmod` (OK→FAIL) and `enum_init_cast_range_reject_xmod` (GREEN→FAIL) — **zero pre-existing class movement** (`enum_init_local_duplicate_reject_xmod` is FAIL under both, since the pre-fix compiler emitted invalid C for the local enum). 4-MD5 emitted-C gates **UNCHANGED**: gol `e7bde571…` / lisp `552d0a84…` / json `38b37bdd…` / mud `5a1cc65e…`. 21-example matrix **21/21**; std-lib runtime gate **201 PASS / 0 FAIL**; `check_emit_support.sh` 7/7; `verify_upgraded.sh` CLOSEOUT OK. Fixed point **MOVED `618a011508fdbed44b02dba3dd26624f` -> `13434b4f4d5e5172b5a2422d5b6e043c`**; seed **v55 -> v56** (archive md5 `e52afcc9d52e763158d5c8e149c287ea` -> `8073b3f3fef42d772cd58d19fd09ef2b`). Rotated-seed round-trip hop1 == hop2 == `13434b4f…`.

**Report corrections (Minor 4/5).** A forward-referenced module-level struct DOES fold in an enum initializer (`@sizeOf(S)`=16, rc=0), and a function-local `enum(u8){ A = @sizeOf(S) }` folds its `@sizeOf(S)` expression to 16 in both the pre- and post-fix compilers — the Task-11J report §5 concerns #3/#4 were inaccurate and are corrected there.

## Task 11J — fold enum initializer expressions (v174 -> v175 2026-09-21)

The F half of the operator-inserted 11I/11J/11Q pair (Task 11I is the root-cause investigation; Task 11Q is the placement/cycle design; AMENDMENT 11 ruled Option B; AMENDMENT 12 fixed the binding fold/reject matrix). `sf/src/type_resolver.zig`'s enum evaluator `evalConstI64Full` had arms only for `int_literal`, `negate`, and `ident_expr` const chains bottoming out in a literal, and `symbol_registrator.zig`'s member loop treated a `null` fold as "no explicit value" and silently kept the auto-increment ordinal — so `enum(u8){ A = 1 + 2 }` emitted `A = 0`, `{ A = @sizeOf(S) }` emitted `A = 0` (S a named struct), and the auto-increment followers were derived from the wrong value. The compile was clean (rc=0, 0 diagnostics); the miscompile only surfaced as a runtime trap. The evaluator also hung (`rc=124`) on `const X = X`.

**Fix (Option B, placement P1).** A post-layout re-evaluation pass (`type_resolver.enumReevaluateAll`) runs at the end of `phase_TypeResolution`, immediately after `typeResolverResolve` (`main.zig`) and before `phase_FrontResolution`. It re-walks every module enum with a fresh `auto_val` cascade through ONE shared member walk (`enumMembersResolve`), overwriting the stored `em_items[].value` in place; the registration loop now calls the same walk (append + lenient), so the two cannot diverge. `evalConstI64Full` gains a depth cap (16, mirroring `evalConstU32Full`) plus `char_literal`, `paren_expr`, the integer binary/bitwise/shift arms, `@intCast`/`@as`, and `@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf`/`@bitOffsetOf` (primitive/alias and named aggregates, complete post-layout). An explicit initializer that still cannot fold, a duplicate tag value, `~`, an enum-member reference, a function call, or a bool/float builtin (`@isWindows`/`@intToFloat`/`@floatCast`) is a clean `ERR_3055_ENUM_VALUE_NOT_CONSTANT` (never a silent auto-increment). The sema enum gate stays a pure backing-width fit-check — it does NOT re-run the evaluator, so no stale value can be re-suppressed.

**New fixtures (8) + standalone repro.**

| fixture | class | contract |
|---|---|---|
| `stdlib_enum_init_expr_xmod` | OK (runtime regression + emitted-C `#define` gate) | arithmetic (`1+2`, `10-3`, `2*3`, `8/2`, `7%3`), bitwise/shift (`6&3`, `6|3`, `6^3`, `1<<4`, `16>>2`), paren `(1+2)`, char `'A'`, builtins (`@sizeOf(u32)`, `@alignOf(u64)`, `@bitSizeOf(u32)`, `@intCast(u8,3)`, `@sizeOf(S)`=16 for `S=struct{u32,u64}`), const chains (`N=2+2`, `@sizeOf(u32)+2`, `N+1`), `@as(u8,3)`, auto-increment after overrides (`A=5,B,C=10,D`), `@offsetOf`/`@bitOffsetOf`; every member checked with `@enumToInt(E.X) != expected -> @panic`. Deterministic 10-line stdout `arith-ok … offset-ok / done`, rc 0 |
| `enum_init_not_constant_xmod` | FAIL (dedicated-code clean reject) | `A = foo()` (function call) → dump rc=2, `error[3055]`, 0 `.c` |
| `enum_init_builtin_reject_xmod` | FAIL (dedicated-code clean reject) | `@isWindows()` / `@intToFloat(f64,3)` / `@floatCast(f32,3.0)` → `error[3055]`, 0 `.c` |
| `enum_init_memberref_reject_xmod` | FAIL (dedicated-code clean reject) | `B = A` / `B = E.A` (official Zig rejects these) → `error[3055]`, 0 `.c` |
| `enum_init_bitnot_reject_xmod` | FAIL (dedicated-code clean reject) | `~0` (result-type/width semantics not modeled) → `error[3055]`, 0 `.c` |
| `enum_init_duplicate_xmod` | FAIL (dedicated-code clean reject) | `A = 1, B = 1` (official Zig rejects duplicate tags) → `error[3055]`, 0 `.c` |
| `enum_init_selfcycle_xmod` | FAIL (clean reject, no hang) | `const X = X; A = X` → depth cap terminates; `error[3055]`, 0 `.c`, NO `rc=124` |
| `enum_init_overflow_expr_xmod` | GREEN (clean reject) | `A = @sizeOf(u64) + 250` (=258 > u8) now stores the true 258 and the backing fit-check rejects → `error[3000]`, 0 `.c` (pre-fix: silent 0) |
| standalone `repro/enum_initializer_fold.z98` (top-level file, not a corpus dir) | — | single-file repro of the defect with header defect/fix/recipe/expected stdout + self-cycle note |

**stdlib pin.** `scripts/stdlib/expected_dirs.txt` 200 → 201 (the positive fixture is `stdlib_*`; the seven clean-reject controls are not).

**Gates (seed-built fixed-point compiler `618a011508fdbed44b02dba3dd26624f`).** Self-compile `-ffast --dump-c89` rc=0, **two-hop closure hop1 == hop2 == `618a0115…`** — the fixed point MOVED (any `sf/src` edit changes the compiler's own emitted `type_resolver`/`symbol_registrator` modules). Corpus `-s0` classifier **927 dirs = 859 OK / 30 GREEN / 38 FAIL / 0 ICE / 0 CRASH** (v174 919 → 927: the 8 new fixture dirs are the only additions); a full-classifier join-diff vs the pre-fix seed v54 compiler moves EXACTLY the new fixtures (5 × OK→FAIL, 1 × OK→GREEN, the positive fixture and the standalone repro stay OK, and `enum_init_selfcycle_xmod` stays FAIL because the pre-fix compiler hangs to the 120 s timeout) — **zero pre-existing class movement**. 4-MD5 emitted-C gates **UNCHANGED** (no gate program uses a non-literal enum initializer): gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. 21-example matrix **21/21** dump/gcc/link rc=0. Std-lib runtime gate **201 PASS / 0 FAIL over 201 dirs**. `check_emit_support.sh` **7/7**; `scripts/closeout/verify_upgraded.sh` **CLOSEOUT OK** (A1-A5, B1-B7, C1). Fixed point **MOVED `cf76c6f13bca6cfce2a4b810af2a67e9` -> `618a011508fdbed44b02dba3dd26624f`**; seed **v54 -> v55** (archive md5 `fa3437ce2cba0f30dc37338c45524eea` -> `e52afcc9d52e763158d5c8e149c287ea`; gen 45 `.c` + 46 `.h`, 9022401 bytes). Rotated-seed round-trip hop1 == hop2 == `618a0115…`. Residuals (out of scope, documented): `@intCast(u8, 300)` in a `u32`-backed enum folds to 300 where Zig errors at the cast (the backing fit-check catches it only for narrow backings); forward-referenced/cross-module/mutual aggregates in an enum initializer stay a safe reject. Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-11J-report.md`.

## Task 11H — fold struct introspection in array sizes (v173 -> v174 2026-09-21)

The F half of the Task 11G/11H operator-inserted pair (Task 11G is the reviewer-verified investigation). `sf/src/type_resolver.zig`'s array-size evaluator `evalConstU32Full` runs inside `typeResolverResolveNames`, BEFORE `typeResolverResolve` computes aggregate layout and sets `state == 2`, and `evalConstScalarKind` deliberately excludes the aggregate kinds — so `[@sizeOf(S)]`/`[@alignOf(S)]`/`[@bitSizeOf(S)]` of a struct hard-errored `error[3050]` at module scope, in an aggregate field, and in a function local. Removing the `state == 2` gate silently folded `[1]` (true 16) for the aggregate-field position, because that field's array type is resolved exactly once, pre-layout, and never re-resolved.

**AMENDMENT 10 (operator ruling).** The fix must NOT duplicate the layout math (divergence is a silent size bug; duplication harms extensibility/maintainability). The former `typeResolverResolveLayout` body is factored into `layoutCompute(registry, tid)`; a new `layoutEnsure(registry, tid, depth) bool` walks every direct dependency first (struct/packed-struct/union/tagged/packed-union fields; tagged/union tag type; enum backing; tuple elements; array element; optional/error-union payload), defers on `0`/`TYPE_UNDEFINED`/`TYPE_VOID` placeholders and past the depth cap (16, mirroring `resolveTypeExprFull`), then runs `layoutCompute` and marks `state == 2`. The normal topological pass calls the same `layoutEnsure` (with a verbatim-math fallback for the legitimate zero-size `void`-field / depth-cap / no-layout-kind cases), so there is exactly ONE layout implementation and ONE dependency walk. The fold completes only a `struct_type` (packed or not) on demand and folds only from `state == 2`; `evalConstScalarKind` stays the integer whitelist, so tuple/slice/union/enum and forward/mutual aggregates stay `ERR_3050` (never silently wrong). `@bitSizeOf` mirrors `comptime_eval.zig`'s packed/integer/enum/bool overrides; `@offsetOf`/`@bitOffsetOf` stay `ERR_3050`.

**New fixtures (7) + standalone repro.**

| fixture | class | contract |
|---|---|---|
| `stdlib_array_size_struct_introspection_xmod` | OK (runtime regression + emitted-C dimension gate) | module `[@sizeOf(S)]`/`[@alignOf(S)]`/`[@bitSizeOf(S)]` (S=`struct{u32,u64}`), packed `[@sizeOf(P)]` (P=`packed struct{u4,u4}`, true `[1]`, never `[2]`), aggregate-field `struct { data: [@sizeOf(S)]u8 }`, local `[@sizeOf(S)]`; each dimension compared with a `@panic` on mismatch. Deterministic 7-line stdout `mod-size=16 / field-size=16 / local-size=16 / align=8 / bits=128 / packed=1 / done`, rc 0 |
| `array_size_struct_introspection_fwd_xmod` | FAIL (clean-reject guard) | forward-referenced aggregate: dump rc=2, `error[3050]`, 0 `.c` |
| `array_size_struct_introspection_mutual_xmod` | FAIL (clean-reject guard) | mutual/cyclic aggregates: depth cap → `error[3050]`, 0 `.c`, no ICE/recursion |
| `array_size_struct_introspection_slice_xmod` | FAIL (clean-reject guard) | slice `[@sizeOf([]u8)]` → `error[3050]`, 0 `.c` |
| `array_size_struct_introspection_tuple_xmod` | FAIL (clean-reject guard) | tuple `[@sizeOf(@TypeOf(.{1,2}))]` → `error[3050]`, 0 `.c` (a tuple is `state == 2` at creation; the whitelist keeps it unfolded) |
| `array_size_struct_introspection_union_xmod` | FAIL (clean-reject guard) | union `[@sizeOf(U)]` → `error[3050]`, 0 `.c` |
| `array_size_struct_introspection_builtin_reject_xmod` | FAIL (clean-reject guard) | `[@isWindows()]`/`[@intToFloat(f64,4)]` → `error[3050]`, 0 `.c` |
| standalone `repro/struct_introspection_array_size.z98` (top-level file, not a corpus dir) | — | single-file repro of the defect with header defect/fix/recipe/expected stdout + packed/negative note |

**stdlib pin.** `scripts/stdlib/expected_dirs.txt` 199 → 200 (the positive fixture is `stdlib_*`; the six clean-reject controls are not).

**Gates (seed-built fixed-point compiler `cf76c6f13bca6cfce2a4b810af2a67e9`).** Self-compile `-ffast --dump-c89` rc=0, **two-hop closure hop1 == hop2 == `cf76c6f1…`** — the fixed point MOVED (any `sf/src` edit changes the compiler's own emitted `type_resolver` module). Corpus `-s0` classifier **919 dirs = 858 OK / 29 GREEN / 32 FAIL / 0 ICE / 0 CRASH** (v173 912 → 919: the 7 new fixture dirs are the only additions); a full-classifier join-diff vs the pre-fix seed v53 compiler over the 912 common dirs is **byte-identical (zero class movement)**. 4-MD5 emitted-C gates **UNCHANGED** (no gate program uses struct introspection in an array size): gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. 21-example matrix **21/21** dump/gcc/link rc=0. Std-lib runtime gate **200 PASS / 0 FAIL over 200 dirs**. `check_emit_support.sh` **7/7**; `scripts/closeout/verify_upgraded.sh` **CLOSEOUT OK** (A1-A5, B1-B7, C1). Fixed point **MOVED `6ed66e8d0d0ba862f014baf76be17a86` -> `cf76c6f13bca6cfce2a4b810af2a67e9`**; seed **v53 -> v54** (archive md5 `ba0f5208a832b8357fb8c51be8e22067` -> `fa3437ce2cba0f30dc37338c45524eea`; gen 45 `.c` + 46 `.h`, 8972440 bytes). Rotated-seed round-trip hop1 == hop2 == `cf76c6f1…`. Residuals (out of scope, documented): forward-referenced/cross-module/mutual aggregates, `@offsetOf`/`@bitOffsetOf`, non-struct aggregates, and enum `@sizeOf` stay `ERR_3050`; a struct with a legitimate `void` field defers (safe false negative — the normal pass still lays it out via the fallback). Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-11H-report.md`.

## Task 11P — resolve the `for`-range end expression (v172 -> v173 2026-09-21)

The Z98 manual Phase 0 plan's operator-inserted compiler fix (the F half of the Task 11O/11P pair; Task 11O is the reviewer-verified investigation). `semanticAnalyzerResolveExpr`'s `range_exclusive`/`range_inclusive` arm typed the range node `u32` and returned WITHOUT resolving `child_0` (start) or `child_1` (end), so neither operand received a resolved-type entry. The lowerer lowers range operands directly, and any operand whose lowering consults the resolved-type table — `.len` on a struct/union ARRAY or SLICE field (`s.a.len`, via `fieldStaticLenForBase`) — found no entry and fell through to an unassigned temp: under `-ffast` a **silent `0`** for the end (`for (0..s.a.len)` iterated 0 times) and a pointer-typed temp / gcc failure for the start (`for (s.a.len..N)`). The capture was fine (the range node was typed); only the operands were unresolved. Fix (one edit, `sf/src/semantic_analyzer.zig`): the range arm now resolves `child_0`, and `child_1` when present, before returning the range type. No `lower.zig` change — the existing Task 11N `.len` machinery then fires for the operands. The fix repairs both the end and the start forms.

**New fixture (1) + standalone repro.**

| fixture | class | contract |
|---|---|---|
| `for_range_end_len_xmod` | OK (runtime regression guard) | `for (0..s.a.len)` on a struct array field / struct slice field / nested field / global field / by-value param / pointer param; regression controls `for (0..arr.len)` (local array), `for (0..n)`, `for (x..y)`, `for (0..@sizeOf(T))`. Each count compared with a `@panic` on mismatch (the silent-`0` guard the compile-only classifier cannot see). Deterministic 2-line stdout `field_len=4 slice_field_len=4 nested=4 global=4 byval=4 byptr=4 local_arr=4 var=4 xy=4 sizeof=8` / `for_range_end ok`, rc 0 |
| standalone `repro/for_range_end.z98` (top-level file, not a corpus dir) | — | single-file repro of the same defect with header defect/fix/recipe/expected stdout + scope note |

No `scripts/stdlib/expected_dirs.txt` pin change (the fixture is not `stdlib_*`; the std-lib runtime gate stays 199).

**Behavior change to watch (11O review).** `for (0..p.len)` on a `[*]T` was a silent-`0`-class shape; after the fix it is a gcc-class failure (undeclared operand temp), NOT a clean front-end reject — the plain-expression `const n = s.p.len` clean `error[3000]` (Task 11N) is unchanged. No corpus dir exercises the range shape, so the full-classifier join-diff is byte-identical. The range capture stays `u32` (the spec's `usize` is a pre-existing, out-of-scope divergence).

**Gates (seed-built fixed-point compiler `6ed66e8d0d0ba862f014baf76be17a86`).** Self-compile `-ffast --dump-c89` rc=0, **two-hop closure hop1 == hop2 == `6ed66e8d…`** — the fixed point MOVED (11O predicted neutral; the source edit changes the compiler's own emitted `semantic_analyzer` module, as for every `sf/src` fix). Corpus `-s0` classifier **912 dirs = 857 OK / 29 GREEN / 26 FAIL / 0 ICE / 0 CRASH** (v172 911 -> 912: the new fixture is the only addition); a full-classifier join-diff vs the pre-fix seed v52 compiler is **byte-identical (zero class movement)** — the new fixture compiles (silent 0) under both. 4-MD5 emitted-C gates **UNCHANGED** (no gate program uses a range operand whose lowering needs the resolved-type table): gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. 21-example matrix **21/21** dump/gcc/link rc=0. Std-lib runtime gate **199 PASS / 0 FAIL over 199 dirs**. `check_emit_support.sh` **7/7**. Fixed point **MOVED `0080736e9637b6993e7539f755f351ea` -> `6ed66e8d0d0ba862f014baf76be17a86`**; seed **v52 -> v53** (archive md5 `b47270f17c7725d02bb0ab405dbe3377` -> `ba0f5208a832b8357fb8c51be8e22067`; gen 45 `.c` + 46 `.h`). Residuals (out of scope): range capture `u32` vs spec `usize`; `for (0..p.len)` on `[*]T` is not cleanly rejected in the range position. Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-11P-report.md`.

## Task 11N — lower `.len` on a struct-field array (v170 -> v172 2026-09-21)

The Z98 manual Phase 0 plan's operator-inserted compiler fix (the F half of the Task 11M/11N pair; Task 11M is the reviewer-verified investigation). `semantic_analyzer.zig`'s generic struct/union field loop decays every field whose declared type is an array `[N]T` to a bare element pointer `*T`, discarding the length. So `s.a` resolves to `*u8`; `.len` on `*u8` matches neither the `array_type` `.len` arm nor the struct/slice arms and falls to the final `TYPE_VOID` fallback. Depending on the consuming position this surfaced as a front-end `error[3000] cannot declare variable of type void` (untyped `const n = s.a.len`), as gcc `'zT_N' undeclared` (comparison / global), or — worst — as a **silent `0`** (return / call-argument). The array-field decay is deliberately PRESERVED (load-bearing for `s.arr[i]` / A5F bounds checks). Two coordinated edits: (a) `sf/src/semantic_analyzer.zig` adds `semanticAnalyzerArrayFieldLen` (recover the declared array field type from a field-access base through a pointer) and calls it in the final fallback so `.len` resolves to `TYPE_USIZE`; (b) `sf/src/lower.zig` intercepts `.len` whose base is a field access with a declared array field (`fieldStaticLenForBase`, the same helper A5F uses) and emits a compile-time `int_const`. The lowerer-only fix was insufficient (the `error[3000] void` is emitted during semantic analysis) and the analyzer-only fix left the lowerer's array arm unreachable — both are required.

**Fix round 1 (v171 -> v172).** Review finding: the analyzer fallback called `semanticAnalyzerArrayFieldLen` for **every** field access reaching the scalar fallback, and the helper only checks whether the *base* field is an array — it never checks the accessed name. So `s.a.foo` (any non-`len` field on an array field) was wrongly accepted as `usize` (pre-fix `error[3000] void`; buggy 11N dump rc=0, silently compiled — a widening). The fallback is now gated on `field_name_id == "len"` (interning `"len"` in that scope, mirroring the lowerer intercept) and stores the helper result once. New negative fixture `len_array_field_reject_xmod` pins the restored clean rejection.

**New fixtures (2) + standalone repro.**

| fixture | class | contract |
|---|---|---|
| `len_array_field_xmod` | OK (runtime regression guard) | local struct array field `.len` (untyped `const n = s.a.len`), by-value param `s.a.len`, pointer param `s.a.len`, global struct field `.len`, union array field `.len`, and nested `n.inner.a.len`; each compared to 4 with a `@panic` on mismatch (the silent-`0` guard the compile-only classifier cannot see). Deterministic 7-line stdout ending `len_array_field ok`, rc 0 |
| `len_array_field_reject_xmod` | GREEN (clean-reject guard; fix round 1) | `s.a.foo` (an unknown field on an array field) is REJECTED: dump rc=2, `error[3000]: cannot declare variable of type void`, 0 `.c` — guards the widening the ungated fallback introduced |
| standalone `repro/len_array_field.z98` (top-level file, not a corpus dir) | — | single-file repro of the same defect with header defect/fix/recipe/expected stdout + negative-case note |

No `scripts/stdlib/expected_dirs.txt` pin change (the fixture is not `stdlib_*`; the std-lib runtime gate stays 199).

**Gates (seed-built fixed-point compiler `0080736e9637b6993e7539f755f351ea`, fix round 1).** Self-compile `-ffast --dump-c89` rc=0, **two-hop closure hop1 == hop2 == `0080736e…`**. Corpus `-s0` classifier **911 dirs = 856 OK / 29 GREEN / 26 FAIL / 0 ICE / 0 CRASH** (v171 910 -> 911: the reject fixture is the only addition); a full-classifier join-diff vs the pre-11N seed v50 compiler moves EXACTLY `len_array_field_xmod` (GREEN -> OK) plus the added `len_array_field_reject_xmod` (GREEN) — zero pre-existing class movement; join-diff vs the buggy 11N compiler is byte-identical plus the added reject fixture. 4-MD5 emitted-C gates **UNCHANGED** (no gate program uses `.len` on a struct array field): gol `e7bde571649a67291419ce57131a556a` / lisp `552d0a84fe54b9cb5ac07c7e30ba2137` / json `38b37bdd45798f6d752cd0aa334491e3` / mud `5a1cc65ef23f27d1c4c51f4516760c07`. 21-example matrix **21/21** dump/gcc/link rc=0. Std-lib runtime gate **199 PASS / 0 FAIL over 199 dirs**. `check_emit_support.sh` **7/7**. Fixed point **MOVED `6cbb52440c2e91e33f735e4e09368fd5` -> `0080736e9637b6993e7539f755f351ea`** (`5dd7874d7a69e015f63874abc30b3222` overall); seed **v51 -> v52** (archive md5 `55694207eaf1f29a98400eb7364bb5d9` -> `b47270f17c7725d02bb0ab405dbe3377`; gen 45 `.c` + 46 `.h`). Residuals (out of scope, documented): `for (0..s.a.len)` remains broken (the for-range end expression is not resolved by the semantic analyzer — separate defect); a `[*]T` field `.len` stays `error[3000]` (correct Zig rejection, unchanged). Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-11N-report.md`.

## Task 11L — `bool` is 1 byte/align 1 to match Zig (v169 -> v170 2026-09-21)

The F half of the Task 11K/11L operator-inserted pair (Task 11K is the reviewer-verified investigation). `sf/src/type_registry.zig:685` registered `bool` with size 4 / align 4 and `sf/src/c89_emit.zig:757` mapped `bool` to C `int`, while Zig's `bool` is 1 byte / align 1 — so `@sizeOf(bool)`/`@alignOf(bool)` folded to 4 and every struct/array with a bool field was oversized. The registry and the C emission MUST change together: the folded `@sizeOf`/`@offsetOf` come from the registry while the actual C layout comes from the emitted type. Fix: registry bool `4/4` → `1/1`; `getCTypeName` bool `"int"` → `"unsigned char"`; `intTypeByteWidth` bool → 1; `classifyIntSignedness` bool → unsigned. No runtime change (`std_print_bool(int)` promotes; `typedef int bool` is runtime-internal). Independently gcc-verified against the emitted C for `bool`, `[4]bool`, bool-field structs, and the previously-missed `union { b: bool }` (4/4 → 1/1) — registry == gcc on every layout line.

**New fixture (1) + standalone repro.**

| fixture | class | contract |
|---|---|---|
| `stdlib_bool_size_align_xmod` | OK (runtime regression + registry↔C self-consistency gate) | `@sizeOf/@alignOf/@bitSizeOf(bool)` = 1/1/1; `[4]bool` 4/1; `struct{bool,bool}` 2 off 0/1; `struct{u8,bool,u8}` 3 off 1; `struct{bool,u32,bool}` 12 off 0/4/8; `struct{5×bool}` 5; `union{b:bool}` 1/1; `@ptrToInt(&s.b)-@ptrToInt(&s) == @offsetOf(SB,"b")`; `[*]bool` stride 3; bool param/return round-trip. Deterministic 22-line stdout ending `done`, rc 0 |
| standalone `repro/bool_size_align.z98` (top-level file, not a corpus dir) | — | single-file repro of the same defect with header defect/fix/recipe/expected stdout |

`scripts/stdlib/expected_dirs.txt` pin grows 198 -> 199 (effective entries).

**Gates (seed-built fixed-point compiler `5dd7874d7a69e015f63874abc30b3222`).** Self-compile `-ffast --dump-c89` rc=0, moving-point closure hop2 == hop3 == `5dd7874d…` (hop1 `caf39573…` ≠ hop2, expected: the v49 seed emits `int` bool into the compiler's own C structs). Corpus `-s0` classifier **909 dirs = 855 OK / 28 GREEN / 26 FAIL / 0 ICE / 0 CRASH** (v169 908 -> 909: the new fixture is the only addition); a full-classifier join-diff vs the pre-fix seed compiler over the 909-dir universe is **byte-identical (zero class movement)** — the compile-only classifier cannot see the runtime layout change. **4-MD5 emitted-C gates ALL MOVE** (every std-importing dump spells a bool param — `std_io.fileOpen(..., unsigned char)`): gol `80287f58bd761e4a551d5d62db5a3551` -> `e7bde571649a67291419ce57131a556a`, lisp `d1d99b597d4ca2a2a75a42c363d54ff4` -> `552d0a84fe54b9cb5ac07c7e30ba2137`, json `f9c9f113b3a7bbd9413b999426daf330` -> `38b37bdd45798f6d752cd0aa334491e3`, mud `91fd711d97bcf9cad91352076be39710` -> `5a1cc65ef23f27d1c4c51f4516760c07`; runtime-identical PRE↔POST by execution (gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`, lisp `b3d9f8974da24ddbf9d389f3d7d97322`, json `8bda3d5a1ec07d14a301bc343df32bf8`, mud `66c8f0abb926cca7baf9a0d1692ab318`/`93147d0f0bbd983a9d844fea8b7a6fa7`). 21-example matrix **21/21** dump/gcc/link rc=0. Std-lib runtime gate **199 PASS / 0 FAIL over 199 dirs**. `check_emit_support.sh` 7/7. Upgraded-demo goldens re-baselined: `demo_expected.txt` `7361d248…` -> `ad947e1e1c51c7f3033389105a28b5b6` and `net_demo_expected.txt` `aa40a52e…` -> `17c958315590d5ca435d9998d665213f` (`size Entity` 16 -> 12); `canonical_move_expected.txt` `b3c5b0e1308bc9a4efde238376c14d9f` -> `cf3c82f93093e6368b0a5ea939ef7cbf` (operator-approved; the final rendered 31×60 screen is byte-identical PRE↔POST, only a transient single-frame draw-sequence difference in `ui.draw`'s frame-diff emission — dungeon generation/entities/raw tile memory identical, emitted `draw`/`renderLocal` differ only in bool types, final screen identical buffered + unbuffered). Fixed point **MOVED `9b292edf64686968c69e0b15f7da762d` -> `5dd7874d7a69e015f63874abc30b3222`**; seed **v49 -> v50** (archive md5 `77cff5d2cb032526e2cad6e0a4b38b1a` -> `a9f303cac8f3710fa51ea475b51bfec9`). Residuals (not full Zig parity): `?bool` stays 8 bytes, `E!bool` keeps a 4-byte floor. Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-11L-report.md`.

## Task 11F — integer-valued builtins fold in array-size positions (v168 -> v169 2026-09-21)

The F half of the Task 11E/11F operator-inserted pair. `sf/src/type_resolver.zig`'s array-size evaluator `evalConstU32Full` had NO `builtin_call` arm, so every builtin in an array-size position returned the `0xFFFFFFFF` unfoldable sentinel and the `array_type` arm emitted `error[3050]: array size is not a constant expression`; the general fold evaluator (`comptime_eval.zig`) is a SEPARATE evaluator that runs in a later pipeline phase and is never consulted by type resolution. `evalConstU32Full` now folds `@intCast(T, e)` by recursing into its operand and `@sizeOf`/`@alignOf`/`@bitSizeOf` for COMPLETE (`state == 2`) primitive/alias types via `resolveTypeExprFull` + the registry (new `evalConstScalarKind` excludes the aggregate kinds). `@isWindows`/`@intToFloat`/`@floatCast` and struct/aggregate introspection (`@offsetOf`/`@bitOffsetOf`, struct `@sizeOf`) stay `ERR_3050` — consistent with `[true]`/`[4.0]`, and struct/aggregate introspection in array sizes is deferred to Task 11G/11H. The `state == 2` completeness gate is MANDATORY — a gate-less in-place read produced a silently wrong `[1]` for an aggregate field. No `comptime_eval.zig`/`lower.zig`/emitter change.

**New fixture (1) + standalone repro.**

| fixture | class | contract |
|---|---|---|
| `stdlib_array_size_builtin_xmod` | OK (runtime regression + emitted-C dimension gate) | module-scope `[@sizeOf(u32)]`, `[@intCast(u32,4)]`, `[@intCast(u32,2+2)]`, `[@alignOf(u32)]`, `[@bitSizeOf(u32)]`, `[@alignOf(u64)]`, `[@bitSizeOf(u16)]`, const-chain `const N: usize = @sizeOf(u32); [N]u8`; field position `struct { data: [@sizeOf(u32)]u8 }`; function-local `[@sizeOf(u32)]` and local-const operand `[@intCast(u32, N)]`. Emitted-C dimension gate: `Arr_unsigned_char_4[4]` (size/intCast/align), `Arr_unsigned_char_3[32]` (`@bitSizeOf(u32)`; the name suffix truncates multi-digit lengths), `Arr_unsigned_char_8[8]` (`@alignOf(u64)`), `Arr_unsigned_char_1[16]` (`@bitSizeOf(u16)`), `Field.data` = `[4]`. Rejected controls (ERR_3050, 0 `.c`): `[@isWindows()]`, `[@intToFloat(f64,4)]`, `[@floatCast(f32,4.0)]`, `[@sizeOf(struct)]`, field `[@sizeOf(struct)]`. Deterministic 13-line stdout ending `done`, rc 0 |
| standalone `repro/array_size_builtin_fold.z98` (top-level file, not a corpus dir) | — | single-file repro of the same defect with header defect/fix/recipe/expected stdout |

`scripts/stdlib/expected_dirs.txt` pin grows 198 -> 199 (effective entries).

**Gates (seed-built fixed-point compiler `9b292edf64686968c69e0b15f7da762d`).** Self-compile `-ffast --dump-c89` rc=0, two-hop closure hop1 == hop2 == `9b292edf…` (re-verified from the rotated seed). Corpus `-s0` classifier **908 dirs = 854 OK / 28 GREEN / 26 FAIL / 0 ICE / 0 CRASH** (v168 907 -> 908: the new fixture is the only addition); a full-classifier join-diff vs the pre-fix compiler over the 908-dir universe moves EXACTLY the new fixture (`stdlib_array_size_builtin_xmod` FAIL -> OK) — zero other class movement. 4-MD5 emitted-C gates **UNCHANGED** (no gate program uses an array-size builtin): gol `80287f58bd761e4a551d5d62db5a3551` / lisp `d1d99b597d4ca2a2a75a42c363d54ff4` / json `f9c9f113b3a7bbd9413b999426daf330` / mud `91fd711d97bcf9cad91352076be39710`. 21-example matrix **21/21** dump/gcc/link rc=0. Std-lib runtime gate **198 PASS / 0 FAIL over 198 dirs**. Fixed point **MOVED `0b717b37c412ce5cd6abd87eeb6a36d8` -> `9b292edf64686968c69e0b15f7da762d`**; seed **v48 -> v49** (archive md5 `e30fbafb93b1253ad007c536883030b6` -> `77cff5d2cb032526e2cad6e0a4b38b1a`). Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-11F-report.md`.

## Task 11D fix round 2 — unwrap parens in float-fold operand signedness (v167 -> v168 2026-09-20)

Residual of the fix-round-1 class: `comptimeEvalOperandSigned` (`sf/src/comptime_eval.zig`) inspected the raw operand node and did not unwrap `paren_expr`, so `@intToFloat(f64, (U))` with `const U: u64 = 18446744073709551615;` fell back to `ComptimeVal.sig=true` and mis-folded to `-1.0` instead of `1.8446744073709552e19`. The helper now recursively unwraps `paren_expr` (depth-guarded) before classifying, so the operand's actual declared type/signedness is honored regardless of parenthesization. `(I)` for `i64` stays signed; `(SRC)` for `f32` still rounds through `f32` (the float sub-evaluator already unwrapped parens).

**Fixture extended (same dir, 1 new case).**

| fixture | class | new contract |
|---|---|---|
| `stdlib_comptime_floatcast_fold_xmod` | OK | `u64-paren-ok` (`@intToFloat(f64, (U))` equals the runtime `tof(U)` result `1.8446744073709552e19`). Deterministic 14-line stdout ending `done`, rc 0 |

**Gates (seed-built fixed-point compiler `0b717b37c412ce5cd6abd87eeb6a36d8`).** Self-compile `-ffast --dump-c89` rc=0, two-hop closure hop1 == hop2 == `0b717b37…` (re-verified from the rotated seed). Fold gate: fixture `__module_init` 0 runtime `int_to_float`/`float_cast`, 12 folded float literals; runtime controls `widen`/`tof` still emit `return (double)((double)x);`. Runtime gate **197 PASS / 0 FAIL**. Corpus `-s0` **907 = 853 OK / 28 GREEN / 26 FAIL / 0 ICE / 0 CRASH**, full-classifier join-diff vs the previous compiler byte-identical (zero class movement). 4-MD5 emitted-C gates **UNCHANGED**: gol `80287f58…` / lisp `d1d99b59…` / json `f9c9f113…` / mud `91fd711d…`. 21-example matrix **21/21**; mandelbrot runtime-identical (`d5966775…`, 1944 B, rc=0). Fixed point **MOVED `109628afa625baca56c2d4b340a802b0` -> `0b717b37c412ce5cd6abd87eeb6a36d8`**; seed **v47 -> v48** (archive md5 `cccc81768445f05b68bea8d3bb780961` -> `e30fbafb93b1253ad007c536883030b6`).

## Task 11D fix round 1 — honor declared float width + operand signedness (v166 -> v167 2026-09-20)

Two review findings in the Task 11D fold code (`sf/src/comptime_eval.zig`). (Critical) `comptimeEvalFloat`'s `ident_expr` arm recursed into a const's initializer as a raw `f64` literal and never rounded through the const's **declared** type, so `const S: f32 = 0.1; const W: f64 = @floatCast(f64, S);` folded to `f64(0.1)` instead of `f64(f32(0.1))` — a silent semantic change vs the runtime path (the fixture's exactly-representable `2.5` masked it). The ident arm now resolves the const's declared type and rounds an `f32` const through `f32`. (Important) `@intToFloat` used `ComptimeVal.sig` for signedness, so a `u64` const above `i64` max (`18446744073709551615`) folded as `-1.0`; the new `comptimeEvalOperandSigned` helper derives signedness from the operand's declared type / literal shape instead. (Minor) `negate` now computes `-fv` so `-0.0` keeps its sign bit in the sub-evaluator.

**Fixture extended (same dir, 2 new cases).**

| fixture | class | new contract |
|---|---|---|
| `stdlib_comptime_floatcast_fold_xmod` | OK | `typed-f32-widen-ok` (`const S: f32 = 0.1` widened to `f64` equals the runtime `widen()` result = `f64(f32(0.1))` = `1.0000000149011612e-1`) and `u64-above-i64-ok` (`const U: u64 = 18446744073709551615` equals the runtime `tof()` result = `1.8446744073709552e19`). Deterministic 13-line stdout ending `done`, rc 0 |

**Gates (seed-built fixed-point compiler `109628afa625baca56c2d4b340a802b0`).** Self-compile `-ffast --dump-c89` rc=0, two-hop closure hop1 == hop2 == `109628afa6…` (re-verified from the rotated seed). Fold gate: fixture `__module_init` 0 runtime `int_to_float`/`float_cast`, 11 folded float literals; runtime controls `widen`/`tof` still emit `return (double)((double)x);`. Runtime gate **197 PASS / 0 FAIL**. Corpus `-s0` **907 = 853 OK / 28 GREEN / 26 FAIL / 0 ICE / 0 CRASH**, full-classifier join-diff vs the previous compiler byte-identical (zero class movement). 4-MD5 emitted-C gates **UNCHANGED**: gol `80287f58…` / lisp `d1d99b59…` / json `f9c9f113…` / mud `91fd711d…`. 21-example matrix **21/21**; mandelbrot runtime-identical (`d5966775…`, 1944 B, rc=0). Fixed point **MOVED `ea159fc2f14af88b3d450f3ca70eca17` -> `109628afa625baca56c2d4b340a802b0`**; seed **v46 -> v47** (archive md5 `0db592d0d00e010a6296674e1e2fd9ce` -> `cccc81768445f05b68bea8d3bb780961`).

## Task 11D — `@floatCast`/`@intToFloat` comptime constant folding (v165 -> v166 2026-09-20)

The Z98 manual Phase 0 plan's fifth inserted compiler fix (`docs/superpowers/plans/2026-09-20-z98-manual-phase0-plan.md`, Task 11C investigation, Task 11D fix; operator-inserted I/F pair). Operator ruling: fold even though Z98's comptime-required positions are integer-only today ("comptime-required positions will eventually include floats"). `sf/src/comptime_eval.zig` interned exactly seven foldable builtins and had no `@floatCast`/`@intToFloat` branch and no float-literal arm, so a comptime-known conversion never entered `ctx.comptime_values`; the lowerer's only fold consumer emitted `int_const` (it cannot represent a float), so the call lowered to a RUNTIME `int_to_float`/`float_cast` in `__module_init` instead of a `float_const` — an emission/folding gap (dump rc=0, zero diagnostics), not a hard error. `comptime_eval.zig` now interns the two names, adds the fold branches plus a private float sub-evaluator, and tags float folds with the `WIDTH_FLOAT` `width_bits` sentinel so the integer binop/negate/bit_not/int_cast paths reject them (no IEEE bits leak into integer arithmetic). `lower.zig`'s `comptime_values` HIT path emits the existing `float_const` with the resolved `f32`/`f64` target. No `lir.zig`/`c89_emit.zig`/`type_resolver.zig` change; the array-size gap (`evalConstU32Full`) is untouched (Task 11E/11F).

**New fixture (1) + standalone repro.**

| fixture | class | contract |
|---|---|---|
| `stdlib_comptime_floatcast_fold_xmod` | OK (runtime regression + emitted-C fold gate) | `@intToFloat(f64,3)`, `@intToFloat(f32,7)`, `@floatCast(f32,1.5)`, `@floatCast(f64, f32 const)`, negative float literal `@floatCast(f32,-1.25)`, precision-losing `@floatCast(f32,16777217.0)`, const-chain `@intToFloat(f64, WIDTH)`, negative int `@intToFloat(f64,-7)`, nested `@floatCast(f64,@intToFloat(f32,5))`, and a runtime-operand control (`widen`); each pinned by an equality probe. The emitted-C fold gate asserts `__module_init` has 0 `int_to_float`/`float_cast` and the folded values as float literals. Deterministic 11-line stdout ending `done`, rc 0 |
| standalone `repro/comptime_floatcast_fold.z98` (top-level file, not a corpus dir) | — | single-file repro of the same defect with header defect/fix/recipe/expected stdout |

`scripts/stdlib/expected_dirs.txt` pin grows 196 -> 197 (effective entries).

**Gates (seed-built fixed-point compiler `ea159fc2f14af88b3d450f3ca70eca17`).** Self-compile `-ffast --dump-c89` rc=0, two-hop closure hop1 == hop2 == `ea159fc2…` (re-verified from the rotated seed). Emitted-C fold gate: fixture `__module_init` 0 `int_to_float`/`float_cast`, 9 float literals; the runtime-operand control still emits a runtime cast. Runtime gate **197 PASS / 0 FAIL over 197 dirs** (3x byte-identical stdout internal). Corpus `-s0` classifier **907 dirs = 853 OK / 28 GREEN / 26 FAIL / 0 ICE / 0 CRASH** (v165 906 -> 907: the new fixture is the only addition); a full-classifier join-diff vs the pre-fix compiler over the 907-dir universe is **byte-identical — zero class movement**. 4-MD5 emitted-C gates **UNCHANGED** (no gate program uses these builtins): gol `80287f58bd761e4a551d5d62db5a3551` / lisp `d1d99b597d4ca2a2a75a42c363d54ff4` / json `f9c9f113b3a7bbd9413b999426daf330` / mud `91fd711d97bcf9cad91352076be39710`. 21-example matrix **21/21** dump/gcc/link rc=0. `examples/z98/mandelbrot` emitted C changed (fold) and is runtime-identical (stdout md5 `d596677501e3653786841195b30d8d64`, 1944 B, rc=0). Fixed point **MOVED `ff54332e2d4418eb663f225bbad6d9c7` -> `ea159fc2f14af88b3d450f3ca70eca17`**; seed **v45 -> v46** (archive md5 `444f0d997867d3ff97d34d45d9720636` -> `0db592d0d00e010a6296674e1e2fd9ce`). Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-11D-report.md`.

## Task 10F — dynamic error-union return runs errdefer (v164 -> v165 2026-09-20)

The Z98 manual Phase 0 plan's fourth inserted compiler fix (`docs/superpowers/plans/2026-09-20-z98-manual-phase0-plan.md`, Task 10E investigation, Task 10F fix; operator-inserted I/F pair). `return <error-union expr>;` where the source and destination error-union types are identical (`src==dst`, so `tryRecordCoercion` early-returns and no coercion is recorded) left `ret_is_error=0`, so Task 10B's classifier skipped the errdefer bodies and no runtime `is_error` branch was emitted — the error value was returned with its `errdefer` silently dropped (a runtime defect: dump rc=0, zero diagnostics). `sf/src/lower.zig` `return_stmt` now, when (a) no static classification, (b) the return expression's resolved type is an error union, (c) `func.return_type` is an error union, and (d) a pending `errdefer` exists, lowers the value, emits `check_error` + `branch` (mirroring the `try` path), and runs `expandDefers(0,1,0)` on the error arm / `expandDefers(0,0,0)` on the success arm before `ret val`. Gating on a pending errdefer keeps every other EU return byte-identical; no emitter/`lir.zig`/sema change.

**New fixture (1) + standalone repro.**

| fixture | class | contract |
|---|---|---|
| `stdlib_errdefer_dyn_xmod` | OK (runtime regression) | dynamic EU variable return (error/success), dynamic EU call return (error/success), `E!void` (error/success), subset `F!i32`->`E!i32`, static `return error.Boom` and `try` controls, and a nested `defer`/`errdefer` dynamic return; each errdefer runs iff the returned union is in its error state. Deterministic 21-line stdout ending `done`, rc 0 |
| standalone `repro/errdefer_dynamic_return.z98` (top-level file, not a corpus dir) | — | single-file repro of the same defect with header defect/fix/recipe/expected stdout |

`scripts/stdlib/expected_dirs.txt` pin grows 195 -> 196.

**Gates (seed-built fixed-point compiler `ff54332e2d4418eb663f225bbad6d9c7`).** Self-compile `-ffast --dump-c89` rc=0, two-hop closure hop1 == hop2 == `ff54332e…` (re-verified from the rotated seed). Runtime gate **196 PASS / 0 FAIL over 196 dirs** (3x byte-identical stdout internal). Corpus `-s0` classifier **906 dirs = 852 OK / 28 GREEN / 26 FAIL / 0 ICE / 0 CRASH** (v164 905 -> 906: the new fixture is the only addition); a full-classifier join-diff vs the pre-fix compiler over the 906-dir universe is **byte-identical — zero class movement**. 4-MD5 emitted-C gates **UNCHANGED** (no gate program uses errdefer): gol `80287f58bd761e4a551d5d62db5a3551` / lisp `d1d99b597d4ca2a2a75a42c363d54ff4` / json `f9c9f113b3a7bbd9413b999426daf330` / mud `91fd711d97bcf9cad91352076be39710`. 21-example matrix **21/21** dump/gcc/link rc=0. Fixed point **MOVED `27e61065a8006183d5f8c55043890c7c` -> `ff54332e2d4418eb663f225bbad6d9c7`**; seed **v44 -> v45** (archive md5 `d5bcddd4fd513a2ca3fe2c0997dee9ec` -> `444f0d997867d3ff97d34d45d9720636`). Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-10F-report.md`.

## Task 11B — `@floatCast` lowering fixed (v163 -> v164 2026-09-20)

The Z98 manual Phase 0 plan's third inserted compiler fix (`docs/superpowers/plans/2026-09-20-z98-manual-phase0-plan.md`, Task 11A investigation, Task 11B fix; operator-inserted I/F pair). `@floatCast` was interned and typed by the front end, but `LirLowerer` never interned it and the cast-dispatch chain in `lowerExprImpl` had no prong for it, so control fell through to `return result;` with a fresh never-assigned temp — the emitted C returned a poison-filled (or, under `-ffast`, zero-initialized) temp instead of the conversion. A silent miscompile: dump rc=0, zero diagnostics, wrong value at runtime. `sf/src/lower.zig` now interns `@floatCast` (`floatcast_name_id`) and adds one `else if (node.child_0 == self.floatcast_name_id)` prong emitting the existing `float_cast` LIR op (`result = (ctype)value;` in `c89_emit.zig`); no emitter/coercion/comptime change.

**New fixture (1).**

| fixture | class | contract |
|---|---|---|
| `stdlib_floatcast_xmod` | OK (runtime regression) | both directions (`f32`->`f64` widen, `f64`->`f32` narrow), a literal argument, a precision-losing narrowing (2^24+1 -> 2^24), and positive controls (`@as` float cast, `@intToFloat`, implicit `f32`->`f64` widening); deterministic 9-line stdout ending `done`, rc 0. Floats have no `std.io` printer, so each conversion is pinned by an equality probe printing `-ok`/`-bad` |

`scripts/stdlib/expected_dirs.txt` pin grows 194 -> 195.

**Gates (seed-built fixed-point compiler `27e61065a8006183d5f8c55043890c7c`).** Self-compile `-ffast --dump-c89` rc=0, two-hop closure hop1 == hop2 == `27e61065…` (re-verified from the rotated seed). Runtime gate **195 PASS / 0 FAIL over 195 dirs** (3x byte-identical stdout internal). Corpus `-s0` classifier **905 dirs = 851 OK / 28 GREEN / 26 FAIL / 0 ICE / 0 CRASH** (v163 904 -> 905: the new fixture is the only addition); a full-classifier join-diff vs the pre-fix compiler over the 905-dir universe is **byte-identical — zero class movement**. 4-MD5 emitted-C gates **UNCHANGED** (no gate program contains `@floatCast`): gol `80287f58bd761e4a551d5d62db5a3551` / lisp `d1d99b597d4ca2a2a75a42c363d54ff4` / json `f9c9f113b3a7bbd9413b999426daf330` / mud `91fd711d97bcf9cad91352076be39710`. 21-example matrix **21/21** dump/gcc/link rc=0. Fixed point **MOVED `1c4f676524f74061d8b459a747f9241d` -> `27e61065a8006183d5f8c55043890c7c`**; seed **v43 -> v44** (archive md5 `f3f9e9bbfd10d6f675cf7a10819f0794` -> `d5bcddd4fd513a2ca3fe2c0997dee9ec`). Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-11B-report.md`.

## Task 10D — defer/errdefer outward control flow rejected (v162 -> v163 2026-09-20)

The Z98 manual Phase 0 plan's second inserted compiler fix (`docs/superpowers/plans/2026-09-20-z98-manual-phase0-plan.md` AMENDMENT 2; Task 10C investigation, Task 10D fix; operator rulings R11/R12). The compiler accepted `return`/`break`/`continue`/`try` inside `defer`/`errdefer`; lowering inlined the body, whose terminator set `block_terminated` and silently dropped the enclosing transfer — so `errdefer { continue; }` turned an explicit `return error.Boom` into a success exit. `sf/src/semantic_analyzer.zig` now rejects, before lowering, only the transfers that leave the body, matching official Zig (`src/AstGen.zig`): dedicated codes `ERR_3051` return / `ERR_3052` break / `ERR_3053` continue / `ERR_3054` try. A `break`/`continue` targeting a loop or labeled block declared INSIDE the body stays legal (Zig's `cur_defer_node`); `return`/`try` are rejected anywhere in the body except inside a nested `fn`. Spec §3.1/§3.2 amended.

**New fixtures (2).**

| fixture | class | contract |
|---|---|---|
| `stdlib_defer_control_flow_xmod` | OK (runtime regression) | accepted side: inner-loop `break`/`continue`, labeled-block and labeled-loop `break`, and an `errdefer` inner-loop transfer all compile and run; stdout 12 lines ending `done`, rc 0 |
| `defer_control_flow_reject_xmod` | FAIL (by design — dedicated-code clean reject) | rejected side: outward `return`/`break`/`continue` and `try` in `defer` + `errdefer` clean-reject rc=2, 0 `.c`, one diagnostic per shape (`ERR_3051`/`ERR_3052`/`ERR_3053`/`ERR_3054`). The canonical classifier GREENs only `error[3000]`, so a dedicated-code clean reject buckets FAIL, like the other dedicated-code rejects (`parsergap_specifier_xmod` `error[3013]`, `async_defer_error_xmod` `error[3019]`) |

`scripts/stdlib/expected_dirs.txt` pin grows 193 -> 194.

**Gates (seed-built fixed-point compiler `1c4f676524f74061d8b459a747f9241d`).** Self-compile `-ffast --dump-c89` rc=0, two-hop closure hop1 == hop2 == `1c4f6765…`. Runtime gate **194 PASS / 0 FAIL over 194 dirs** (3x byte-identical stdout internal). Corpus `-s0` classifier **904 dirs = 850 OK / 28 GREEN / 26 FAIL / 0 ICE / 0 CRASH** (v162 902 -> 904: the 2 new dirs are the only additions); a full-classifier join-diff vs the pre-fix compiler over the 902 common dirs is **byte-identical — zero class movement**. 4-MD5 emitted-C gates **UNCHANGED** (no gate program contains defer control flow): gol `80287f58bd761e4a551d5d62db5a3551` / lisp `d1d99b597d4ca2a2a75a42c363d54ff4` / json `f9c9f113b3a7bbd9413b999426daf330` / mud `91fd711d97bcf9cad91352076be39710`. 21-example matrix **21/21** dump/gcc/link rc=0. Fixed point **MOVED `36c04ebf5f6f3f4afcb4baf8c721a6a0` -> `1c4f676524f74061d8b459a747f9241d`**; seed **v42 -> v43** (archive md5 `fe532ad44b659b8c4a34d0f7932fc04f` -> `f3f9e9bbfd10d6f675cf7a10819f0794`). Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-10D-report.md`.

## Task 10B — errdefer on explicit error returns fixed (v161 -> v162 2026-09-20)

The Z98 manual Phase 0 plan's inserted compiler fix (`docs/superpowers/plans/2026-09-20-z98-manual-phase0-plan.md` AMENDMENT 1; Task 10A investigation, Task 10B fix). `sf/src/lower.zig` `return_stmt` lowering unconditionally passed `is_error_path=0` to `expandDefers`, so `errdefer` bodies were skipped on every explicit `return`; the return is now classified (`wrap_error_err` coercion or `error_literal` -> `ret_is_error=1`) and passed through. Compiler-correctness task, not a manual page.

**New runtime fixture (1).**

| fixture | kind | contract |
|---|---|---|
| `stdlib_errdefer_xmod` | regression (runtime) | explicit `return error.Boom`, conditional explicit return, `try` propagation, and `return err;` each run their `errdefer`; a plain `return;` does NOT. stdout 9 lines ending `done`, rc 0 |

`scripts/stdlib/expected_dirs.txt` pin grows 192 -> 193 (186 `repro/mi_matrix/stdlib_*` + 7 `stdlib_test/*`).

**Gates (seed-built fixed-point compiler `36c04ebf5f6f3f4afcb4baf8c721a6a0`).** Runtime gate **193 PASS / 0 FAIL over 193 dirs** (3x byte-identical stdout internal). Self-compile `-ffast --dump-c89` rc=0, 45 `.c` + 46 `.h`, 0 `error[`, 0 PANIC; two-hop closure hop1 == hop2 == `36c04ebf5f6f3f4afcb4baf8c721a6a0`. Corpus `-s0` classifier **902 dirs = 849 OK / 28 GREEN / 25 FAIL / 0 ICE / 0 CRASH** (v161 901 -> 902: the new fixture classifies OK); a full-classifier join-diff vs the pre-fix compiler over the same 902 dirs is **byte-identical — zero class movement**. 4-MD5 gates **UNCHANGED** (no gate program uses `errdefer`): gol `80287f58bd761e4a551d5d62db5a3551` / lisp `d1d99b597d4ca2a2a75a42c363d54ff4` / json `f9c9f113b3a7bbd9413b999426daf330` / mud `91fd711d97bcf9cad91352076be39710`. 21-example matrix **21/21** dump/gcc/link rc=0. Fixed point **MOVED `197602956b55d1cb59848a922a934fe8` -> `36c04ebf5f6f3f4afcb4baf8c721a6a0`**; seed **v41 -> v42** (archive md5 `fe532ad44b659b8c4a34d0f7932fc04f`). Full report: `.superpowers/sdd/2026-09-20-z98-manual-phase0-plan/task-10B-report.md`.

## Plan D hardening closeout — network/async goldens + stress tier (v160 -> v161 2026-09-20)

Plan D test-hardening (`docs/superpowers/plans/2026-09-18-plan-D-test-hardening.md`) is
**COMPLETE** (Tasks 1-5). Docs/scripts/fixtures only — **no `sf/src` change**. The
self-emission fixed point is **UNMOVED `197602956b55d1cb59848a922a934fe8`**, and the seed is
**NOT rotated** (stays **v41**, archive md5 `c9461ae95e8b6ff3c4cd585663fbca8b`; the hardening
adds no std module, so the archive `lib/` payload is unchanged). This is the final hardening
plan; the std-lib extension program is COMPLETE (see `## Next plan`).

**Golden convention (binding).** Each discovered std fixture dir carries `expected.txt` (exact
stdout bytes) + `expected.rc` (exit code); a missing golden is a FAIL (no silent skips).
`scripts/stdlib/expected_dirs.txt` pins the discovered set so coverage cannot silently shrink.
Goldens are runtime-only (stdout + rc), captured only after the observed output matched the
fixture's documented GREEN contract, and each fixture runs 3x with byte-identical stdout
(determinism R6). Network fixtures are loopback-only and ship `<dir>/ports.txt` (new:
4155/4156/4157/4158/4159/4160); the async-only probes bind no socket.

**New fixtures (8).**

| fixture | kind | contract |
|---|---|---|
| `stdlib_net_recvnonblocking_wouldblock_xmod` | expected-failure probe | idle loopback socket → `recvNonBlocking` yields `error.WouldBlock` (never a count, never 0); stdout `wouldblock ok`, rc 0; port 4155 |
| `stdlib_net_recvnonblocking_close_xmod` | expected-failure probe | after peer close `recvNonBlocking` converges to `0` (EOF), not `WouldBlock`; stdout `close-eof ok`, rc 0; port 4156 |
| `stdlib_stream_msgreader_oversize_xmod` | expected-failure probe | u32 big-endian prefix 17 against a 16-byte reader buffer → `readMsgSync` returns `error.FrameTooLarge` before touching the body; stdout `oversize ok`, rc 0; port 4157 |
| `stdlib_async_suspenduntil_false_xmod` | expected-failure probe | predicate stays false over a bounded 4-tick drive → coroutine stays suspended, never resumes, predicate invoked once per tick; stdout `resume-count 0` / `pred-calls 4` / `suspenduntil-false ok`, rc 0 |
| `stdlib_net_nonblocking_stress_xmod` | stress | 4096-byte payload drained through an 8-byte buffer (512 bounded partial reads, byte-exact); would-block on empty + post-drain; zero-length send; 65536-byte max-chunk drain; peer-close EOF; stdout `net nonblocking stress ok`, rc 0; port 4158 |
| `stdlib_stream_socketlinereader_stress_xmod` | stress | 250-byte line through a 100-byte buffer (100/100/50); final line with no trailing newline; empty source; interleaved readers; async line across ticks (3 suspends); stdout `max-suspends 3` / `socketlinereader stress ok`, rc 0; port 4159 |
| `stdlib_stream_msgreader_stress_xmod` | stress | 40 back-to-back frames (lengths cycling 0..15), full-capacity 16-byte frame, zero-length frame, EOF; async frame split across ticks (3 suspends) + 8-byte full-capacity frame; stdout `max-suspends 3` / `msgreader stress ok`, rc 0; port 4160 |
| `stdlib_async_suspenduntil_stress_xmod` | stress | six coroutines on named `suspendUntil` predicates flipping at ticks {3,1,6,2,7,4}; each resumes on exactly its flip tick and its predicate-call count equals that tick; 13 stdout lines, rc 0 |

Inputs are hand-written deterministic tables (bounded loops, no PRNG, no wall-clock sleep);
Model C is respected (caller drives `tick`; no executor/poll loop). Each probe is a
single-failure-per-process assertion: the wrong outcome `@panic`s (trap = harness FAIL), so a
mistake cannot be mistaken for success.

**Gates (seed-built fixed-point compiler `197602956b55d1cb59848a922a934fe8`).** Runtime gate
**192 PASS / 0 FAIL over 192 dirs** (3x byte-identical stdout internal; pin
`scripts/stdlib/expected_dirs.txt` = **184 -> 192** data lines: 185
`repro/mi_matrix/stdlib_*` + 7 `stdlib_test/*`). `scripts/check_emit_support.sh` **7/7**
byte-identical. Self-compile `-ffast --dump-c89` rc=0, 48 `.c` + 48 `.h`, 0 `error[`,
0 PANIC. Corpus `-ffast` dump+gcc classifier **901 dirs = 848 OK / 28 GREEN / 25 FAIL / 0 ICE
/ 0 CRASH** (Plan D closeout 892 -> 901: the 9 new dirs — the v160 `suspenduntil` fixture + the
8 hardening fixtures — all classify OK; `join`-diff shows **zero class movement on all 892
pre-existing dirs**). `scripts/closeout/verify_upgraded.sh` **CLOSEOUT OK** (A1-A5 / B1-B7 /
C1). Seed v41 round-trip re-verified (two-hop closure hop1 == hop2 == `197602956b55d1cb59848a922a934fe8`).
Full report: `.superpowers/sdd/2026-09-18-plan-D-test-hardening/task-5-report.md`.

## Plan D Task 4 (REVISED) — std.async.suspendUntil (v159 -> v160 2026-09-20)

The original optional `std.async.wait(handle)` was ruled NOT justified under
Model C; the operator replaced it with the Model C suspending primitive
`pub fn suspendUntil(pred: fn() bool) void` in `sf/src/std_async.zig` — yield via
`@asyncSuspend(null)` once per tick until `pred()` is true. The predicate is a
NON-suspending function pointer invoked indirectly and stored in the coroutine
frame across the suspend; `suspendUntil` is called directly by name (the allowed
direction). This is the `sf/src/std_async.zig` change the v159 note recorded as
absent.

**New module fixture (1).**

| fixture | kind | contract |
|---|---|---|
| `stdlib_async_suspenduntil_xmod` | primitive | named non-suspending `fn() bool` predicate increments a per-tick counter; coroutine calls `sa.suspendUntil(isReady)`; driver ticks 3x with the flag clear then sets it; coroutine resumes on tick 4; stdout `resume-tick 4` / `pred-calls 4` / `suspenduntil ok`, rc 0 |

`scripts/stdlib/expected_dirs.txt` pin grows 183 -> 184 (177
`repro/mi_matrix/stdlib_*` + 7 `stdlib_test/*`).

**Gates (seed-built fixed-point compiler `197602956b55d1cb59848a922a934fe8`).**
The change is confined to a std module outside `sf/src/main.zig`'s import graph,
so the self-emission fixed point is **UNMOVED
`197602956b55d1cb59848a922a934fe8`**. Runtime gate **184 PASS / 0 FAIL over 184
dirs** (3x byte-identical stdout per fixture). Seed rotates **v40 -> v41**
(archive `lib/std_async.zig` synced; archive binary byte-identical; archive md5
`0e3250ea5bdcff1ccd79f8954ea17f48` -> `c9461ae95e8b6ff3c4cd585663fbca8b`). Full
report: `.superpowers/sdd/2026-09-18-plan-D-network-async/task-4-report.md`.

## Plan D closeout — network async landed (v158 -> v159 2026-09-19)

Plan D (`docs/superpowers/plans/2026-09-18-plan-D-network-async.md`) is
**COMPLETE** (Tasks 1-3 + this closeout; the original optional Task 4 was later replaced by `std.async.suspendUntil` in v160). It lands the network
half of the `std_stream` two-reader surface: the `std_net` non-blocking socket
primitives (`setNonBlocking`/`recvNonBlocking`/`sendNonBlocking`) and the
`std_stream` `SocketLineReader` / `MsgReader` (length-prefix framing). The
closeout adds the band's R7b usage program and rotates the seed. Unlike Plan C,
this band includes a `sf/src` change: the authorized `net_prelude.h` prelude add
(`#include <fcntl.h>`) in `emit_support.zig` (R8), so the self-emission fixed
point **MOVED `fc9198f6c1a24c92ec136e741c81c975` ->
`197602956b55d1cb59848a922a934fe8`** and the seed rotates **v39 -> v40**
(archive md5 `4e493be2625311fa11c8f421b732c59a` ->
`0e3250ea5bdcff1ccd79f8954ea17f48`). The archive `lib/` file set stays 29 (no
new std module); only the fixed point and payload contents changed.

**Task 4 (OPTIONAL `std.async.wait(handle)`) — SKIPPED, then REPLACED by
`std.async.suspendUntil` (v160 2026-09-20).** Model C is binding: Z98 is
cooperative-yield with no executor and no poll loop (the `answerT4` ruling), so
the poll-based `wait(handle)` was not justified. The operator replaced it with
the Model C primitive `pub fn suspendUntil(pred: fn() bool) void` (see the v160
section above). No compiler change; fixed point UNMOVED.

**New module fixtures (5, all loopback).**

| fixture | kind | contract |
|---|---|---|
| `stdlib_net_setnonblocking_xmod` | primitive | `setNonBlocking` flips the socket (raw `recv` returns `-1` with no data, then the payload); stdout `setnonblocking ok`, rc 0 |
| `stdlib_net_recvnonblocking_xmod` | primitive | no-data -> `error.WouldBlock`; peer send -> exact bytes; peer close -> `0`; stdout `recvnonblocking ok`, rc 0 |
| `stdlib_net_sendnonblocking_xmod` | primitive | full-accept count + intact round-trip (would-block intentionally unpinned); stdout `sendnonblocking ok`, rc 0 |
| `stdlib_stream_socketlinereader_xmod` | L6 reader | sync `[one, abcdefg, hi, last]` (boundary-CR overflow + unterminated tail); async `[abcdef, xyz]` partial across ticks; `max-suspends 2`; stdout `max-suspends 2` / `socketlinereader ok`, rc 0 |
| `stdlib_stream_msgreader_xmod` | L6 framing | u32 big-endian prefix; sync `[abc, "", 0123456789abcdef, xy, z]`; oversize probe -> `error.FrameTooLarge`; async `[hello, "", hi]`; `max-suspends 3`; stdout `frametoolarge ok` / `max-suspends 3` / `msgreader ok`, rc 0 |

**New usage program (R7b, 1).**

| dir | composition | stdout contract (rc 0) |
|---|---|---|
| `stdlib_test/net_stream_usage` | `std_net` + `std_stream` + `std.async` | `net_stream_usage` / `sync: [alpha]` / `sync: [beta]` / `async: [one]` / `async: [two]` / `frame: [hello]` / `frame: []` / `frame: [hi]` / `async-lines: 2` / `async-frames: 3` / `max-suspends: 3` / `net_stream ok` |

**Golden convention (binding).** Each discovered std fixture dir carries
`expected.txt` (exact stdout bytes) + `expected.rc` (exit code); a missing golden
is a FAIL (no silent skips). `scripts/stdlib/expected_dirs.txt` pins the
discovered set so coverage cannot silently shrink. Goldens are runtime-only
(stdout + rc), captured only after the observed output matched the fixture's
documented GREEN contract, and each fixture runs 3x with byte-identical stdout
(determinism R6). A fixture that binds TCP ports ships `<dir>/ports.txt` (new:
4149/4150/4151/4152/4153/4154).

**Gates (seed-built fixed-point compiler `197602956b55d1cb59848a922a934fe8`).**
Runtime gate **183 PASS / 0 FAIL over 183 dirs** (pin
`scripts/stdlib/expected_dirs.txt` = **183** data lines: 176
`repro/mi_matrix/stdlib_*` + 7 `stdlib_test/*`). `scripts/check_emit_support.sh`
**7/7** byte-identical. Self-compile `-ffast --dump-c89` rc=0, 48 `.c` + 48 `.h`,
0 `error[`, 0 PANIC. Corpus `-ffast` dump+gcc classifier **892 dirs = 839 OK /
28 GREEN / 25 FAIL / 0 ICE / 0 CRASH** (886 -> 892: the 6 new dirs all classify
OK; every pre-existing dir class-identical). `scripts/closeout/verify_upgraded.sh`
**CLOSEOUT OK** (A1-A5 / B1-B7 / C1). Seed v40 round-trip re-verified (two-hop
closure hop1 == hop2 == `197602956b55d1cb59848a922a934fe8`). Full report:
`.superpowers/sdd/2026-09-18-plan-D-network-async/task-5-report.md`.

## Plan C hardening closeout — L4/L5 goldens + stress tier (v157 -> v158 2026-09-19)

Plan C test-hardening (`docs/superpowers/plans/2026-09-18-plan-C-test-hardening.md`) is
**COMPLETE** (Tasks 1-5). Docs/scripts/fixtures only — **no `sf/src` change**. The
self-emission fixed point is **UNMOVED `fc9198f6c1a24c92ec136e741c81c975`**, and the seed is
**NOT rotated** (stays **v39**, archive md5 `4e493be2625311fa11c8f421b732c59a`; the hardening
adds no std module, so the archive `lib/` payload is unchanged).

**Golden convention (binding).** Each discovered std fixture dir carries `expected.txt` (exact
stdout bytes) + `expected.rc` (exit code). A missing golden is a FAIL (no silent skips);
`scripts/stdlib/expected_dirs.txt` pins the discovered set so coverage cannot silently shrink.
Goldens are runtime-only (stdout + rc), captured only after the observed output matched the
fixture's documented GREEN contract, and each fixture runs 3× with byte-identical stdout
(determinism R6). `stdlib_map_oom_xmod` / `stdlib_heap_oom_xmod` (pre-existing Plan C
probes, not among the 12 new fixtures below) are the OOM probes.

**New fixtures (12).**

| fixture | kind | contract |
|---|---|---|
| `stdlib_parse_invalid_xmod` | expected-failure probe | malformed numeric input → `null` (all five parsers); stdout `parse invalid ok`, rc 0 |
| `stdlib_base64_invalid_xmod` | expected-failure probe | non-alphabet / bad-length / misplaced-`=` input → `error.InvalidInput`, arena untouched; stdout `base64 invalid ok`, rc 0 |
| `stdlib_utf8_invalid_xmod` | expected-failure probe | invalid continuation / overlong / surrogate / >U+10FFFF / impossible lead → `decode == null`; stdout `utf8 invalid ok`, rc 0 |
| `stdlib_map_stress_xmod` | stress | capacity sweep 8..1024 at 50% load; heavy linear probing; full-table OOM boundary; string-key lifetime; deterministic slot layout |
| `stdlib_sort_stress_xmod` | stress | 4096 full-range u32 (fixed-seed LCG) + bounded histograms; ascending/descending/duplicate/all-equal; `binarySearchU32` present+absent |
| `stdlib_heap_stress_xmod` | stress | 2000 pushes into a capacity-1 heap (every doubling) + full drain; tie stability; interleave; empty-pop boundary |
| `stdlib_rle_stress_xmod` | stress | 128-byte token boundaries (128..4096); alternating; empty; all 256 values; `encodedLen`/`decodedLen` + `decode∘encode` |
| `stdlib_crypto_stress_xmod` | stress | RFC 3174 SHA-1 / FIPS 180-4 SHA-256 / RFC 1321 MD5 / IEEE 802.3 CRC-32 KATs; streaming-vs-one-shot over many chunk splittings; empty |
| `stdlib_parse_stress_xmod` | stress | valid/invalid tables; i32/u32/i64/u64 overflow boundaries; itoa/utoa round-trips; buffer-end writes; ftoa precision/carry |
| `stdlib_base64_stress_xmod` | stress | RFC 4648 §10 vectors; whitespace/malformed rejection; `decode∘encode` over adversarial lengths × patterns; all 256 values |
| `stdlib_hex_stress_xmod` | stress | standard vectors; case-insensitive decode; whitespace/non-hex/odd-length rejection; round-trips; all 256 values |
| `stdlib_utf8_stress_xmod` | stress | boundary code points; invalid continuations/overlong/surrogates; encode rejects + undersized buffer; `countCodepoints` over mixed/all-256 |

Inputs are hand-written deterministic tables (the only "random-looking" inputs are explicit
fixed-literal-seed LCG loops — no external PRNG).

**Gates (seed-built fixed-point compiler `fc9198f6`).** Runtime gate **177 PASS / 0 FAIL over
177 dirs** (3× determinism internal; pin `scripts/stdlib/expected_dirs.txt` = **165 -> 177**
data lines: 171 `repro/mi_matrix/stdlib_*` + 6 `stdlib_test/*`). `scripts/check_emit_support.sh`
**7/7** byte-identical. Self-compile `-ffast --dump-c89` rc=0, 48 `.c` + 48 `.h`, 0 `error[`,
0 PANIC. Corpus `-ffast` dump+gcc classifier **886 dirs = 833 OK / 28 GREEN / 25 FAIL / 0 ICE /
0 CRASH** (874 -> 886: the 12 new dirs all classify OK; every pre-existing dir
class-identical). `scripts/closeout/verify_upgraded.sh` **CLOSEOUT OK** (A1-A5 / B1-B7 / C1).
Seed v39 round-trip re-verified (two-hop closure hop1 == hop2 == `fc9198f6`). Full report:
`.superpowers/sdd/2026-09-18-plan-C-test-hardening/task-5-report.md`.

## Plan C closeout — L4 + L5 landed; std-lib extension program COMPLETE (v156 -> v157 2026-09-19)

Plan C (`docs/superpowers/plans/2026-09-17-std-lib-plan-c-data-codecs.md`) is
**COMPLETE**, and with it the whole std-lib extension program
(`docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md`): all
six blueprint layers have landed. The closeout adds the band's two R7b usage
programs and rotates the seed `lib/` payload. **No `sf/src` change**: the
self-emission fixed point stays **UNMOVED
`fc9198f6c1a24c92ec136e741c81c975`**. The seed rotates **v38 -> v39** (archive
md5 `372385a68099d19269b099ef6e4a5e27` -> `4e493be2625311fa11c8f421b732c59a`)
because the archive embeds `lib/`, which now carries all 28 `std_*.zig` +
`std.zig`. (Plan C's four authorized compiler-defect I/F fixes — Tasks 1b-F,
2b-F, 3b-F, 4b-F — landed earlier and their fixed-point moves are recorded in
v144-v156.)

**New usage programs (R7b, 2).**

| dir | composition | stdout contract (rc 0) |
|---|---|---|
| `stdlib_test/map_sort_heap_usage` | `std_map` + `std_sort` + `std_heap` | `map_sort_heap_usage` / `map-len: 9` / `sorted: 0 0 1 1 2 2 3 4 9` / `search-9: 8` / `search-5: missing` / `heap: 0 0 1 1 2 2 3 4 9` / `stable: 1` / `map_sort_heap ok` |
| `stdlib_test/crypto_codec_usage` | `std_crypto` + `std_base64` + `std_hex` + `std_utf8` + `std_buf` | `crypto_codec_usage` / `codepoints: 5` / `cp-first: 90` / `cp-second: 233` / `b64: Wjk4IMOp` / `hex: 5a393820c3a9` / `sha256: 390edd46037981d883bd4363c30dccc4bc9b01b08dbc43192415539910872f09` / `crc32: f2e959aa` / `roundtrip: 1` / `invalid: 1` / `buf-len: 27` / `buf-crc32: ab387860` / `crypto_codec ok` |

Both are deterministic (no address/clock/PID input), 3x emission-md5 identical,
and byte-identical under `-fsafe` and `-ffast`. `scripts/stdlib/expected_dirs.txt`
pins the discovered set **163 -> 165**.

**Corpus delta.** Universe **872 -> 874** (+2, the two usage programs). Class map
**819 OK / 28 GREEN / 25 FAIL -> 821 OK / 28 GREEN / 25 FAIL**; both new dirs
classify **OK** and all 872 pre-existing dirs are class-identical (no `sf/src`
change). Runtime gate **163 -> 165 PASS / 0 FAIL over 165 dirs** (3x
determinism). `check_emit_support.sh` **7/7**; `scripts/closeout/verify_upgraded.sh`
**CLOSEOUT OK** (A1-A5 / B1-B7 / C1).

## Plan C Task 4b-F fix round 1 — over-read guard + 4-MD5 emitted-C re-baseline (v155 -> v156 2026-09-19)

Review round 1 (operator ruling m1814) fixed one Critical and one Important.

**Important — over-read guard.** The `emitFieldAssign` array branch (v155) copied
`sizeof(dst.field)` bytes from `&src` unconditionally, so the declared residual
`S{ .xs = .{ 1, 2 } }` (whose `src` lowers to a scalar) read past `src`. The byte
copy is now emitted ONLY when the `src` temp is an array of the same element type
and length as the field; otherwise it falls back to the safe zero-fill (field
zeroed, values still wrong — the residual stays declared). `mud_server`'s
`sin_zero` src is the same `[8]u8` array, so the correct byte copy is preserved.

**Critical — the 4-MD5 gate is the `--dump-c89` EMITTED-C hash, not program
stdout** (`docs/sf/QUICK_REF.md` "Byte-identical gate"; recipe
`zig1 --dump-c89 <ENTRY> > /tmp/new.c`). Every gate program emits `std_net`
(`std.zig` re-exports it), so the v155 `sin_zero` byte-copy change moves ALL FOUR
emitted-C dumps, not just mud. Re-baselined (operator-approved, runtime-identical):
gol `75c09bd8…` -> `ce222a5d13ed168368af9ebbfe570d78`, lisp `cad5f491…` ->
`1bcb5270864bb07d2e47654f75e3d3aa`, json `6cb272d1…` ->
`0e6f1db53f5de7aede2d7258258b6030`, mud `b9321f7c…` ->
`409cf8c77b104a194a15e9b926d1b5df`. Runtime PRE vs POST verified byte-identical
by execution: gol stdout `fcbf7e7c…` rc=0, lisp `(+ 1 2)` stdout `b3d9f897…`
rc=0, json stdout `8bda3d5a…` rc=0, mud canonical session server stdout
`66c8f0ab…` / client `93147d0f…`.

Fixed point `1ffd20c1…` -> **`fc9198f6c1a24c92ec136e741c81c975`** (hop1==hop2);
seed **v37 -> v38** (archive md5 `372385a68099d19269b099ef6e4a5e27`). Pin GREEN,
corpus 843 = 790 OK / 28 GREEN / 25 FAIL (only pin `GREEN -> OK`), runtime gate
134 PASS / 0 FAIL, `check_emit_support.sh` 7/7, self-compile 48 `.c` / 0 err /
0 PANIC, `CLOSEOUT OK`.

## Plan C Task 4b-F — array-of-struct-literal defect fixed (v154 -> v155 2026-09-19)

Task 4b-F (the **F** half of the m1787 I/F pair) fixes the void-typing root cause
of the Task 4b-I defect and MOVES the self-emission fixed point
**`bcfa85a40279a5c7bc4d8e6fd5f8df91` -> `1ffd20c17fe28c88238bf3c7a286bdd5`**
(hop1==hop2), seed **v36 -> v37** (archive md5
`14d8ad3e853cfaea91755d3e11d9cd3e`). The `array_of_struct_literal_xmod` pin flips
**GREEN -> OK** (dump rc=0, gcc clean, link+run rc=0, stdout
`array of struct literal ok`).

**Fix (2 loci).**
1. `sf/src/semantic_analyzer.zig` `semanticAnalyzerResolveArrayInit`: derive the
   element type from the literal's own annotation (`[_]T` -> `annot_elem_tid`,
   `[N]T` -> `typeRegistryIndexedElemType(annot_tid)`) and push it as the
   expected type around each element resolution. Anonymous aggregate/enum
   literals now resolve instead of void. This fixes the whole void-typing class:
   plain struct, tagged union, enum, inferred/annotated/explicit-length, and the
   global position (all previously `error[3000]` void or `'zT_0' undeclared`).
2. `sf/src/c89_emit.zig` `emitFieldAssign` array branch + `dceMarkAllReads`:
   an array-typed struct field initialized from an array literal/value is now
   byte-copied from `src` (C89 forbids array assignment) instead of zero-filled;
   the DCE read-mark for `.assign_field` src is no longer skipped for array
   fields (so the source construction is retained). This fixes
   `Box{ .items = [_]Pair{ ... } }` (gcc `'zT_2' undeclared`) and the general
   array-field zero-fill (silent wrong values). Note: this changes the emitted C
   of `std_net.zig` `sin_zero` initialization (all-zero array copy instead of a
   direct zero-fill) — runtime-identical, verified by the runtime gates.

**Deliberately left (distinct bugs, declared).** These were pinned by 4b-I and
are NOT fixed here (they are emission/coercion gaps, not the void-typing root
cause; each warrants its own I/F pair):
- `sf/src/lower.zig:5040` plain `=` element store for optional (needs wrap),
  nested-array (needs aggregate copy), and string-literal->slice (needs
  coercion) element kinds.
- The unannotated tuple-literal shorthand `S{ .xs = .{ 1, 2 } }` (and the
  `[_]Box{ .{ .xs = .{ ... } } }` inner form): the field value is a
  `tuple_literal`, whose resolved type is not context-coerced to the array
  field type, so it lowers to its first element. Explicit `[_]T{...}` /
  `[N]T{...}` field forms are fixed.
- `(literal)[0..]` frontend gap `error[3043]: unsupported slice_expr form/base`.

**Corpus delta.** Universe **843** dirs, class map **790 OK / 28 GREEN / 25
FAIL** (pre-fix **789 / 29 / 25**); the full-classifier diff is exactly the pin
`GREEN -> OK`, zero unexpected movement. Runtime gate **134 PASS / 0 FAIL**;
`check_emit_support.sh` **7/7**; `CLOSEOUT OK`; self-compile **48 `.c`, rc=0,
0 errors, 0 PANIC**. **CORRECTED in v156:** the 4-MD5 gate is the `--dump-c89`
EMITTED-C hash (not program stdout); the `sin_zero` change moves all four
emitted-C dumps — see the v156 section above for the re-baselined values and the
runtime-identity evidence. (The v155 text originally claimed gol/lisp/json emitted
C was byte-identical; that was wrong.)

## Plan C Task 4b-I — array-of-struct-literal defect pinned (v152 -> v153; fix round 1 v153 -> v154 2026-09-19)

Plan C Task 4 (`std_sort`) found a pre-existing compiler defect: an array literal
of a user struct type is typed `void`. The operator ruled it an I/F pin+fix pair
(m1787). This task is the **I** half (pin + investigation only). **No `sf/src`
change**: the self-emission fixed point stays **UNMOVED
`bcfa85a40279a5c7bc4d8e6fd5f8df91`** (seed v36 unchanged). Task 4b-F (the F half)
fixes the typing/lowering and MOVES the fixed point.

**New corpus dir** (auto-listed by `scripts/corpus/list_corpus_dirs.sh`):

| dir | class (pre-pin, fixed point bcfa85a4) | expected GREEN (Task 4b-F) |
|---|---|---|
| `array_of_struct_literal_xmod` | **GREEN** (error[3000] green-guard bucket — a FALSE rejection; see caveat) | dump rc=0, 5 `.c`, gcc clean, link+run rc=0, stdout `array of struct literal ok` |

**Trigger shapes** (both in `main.zig`, plus a typed-element control):

```zig
const Pair = struct { key: u32, val: u32 };
var a = [_]Pair{ .{ .key = 1, .val = 2 }, .{ .key = 3, .val = 4 } };           // inferred length
var b: [2]Pair = [_]Pair{ .{ .key = 5, .val = 6 }, .{ .key = 7, .val = 8 } };   // annotated length
var c = [_]Pair{ Pair{ .key = 9, .val = 10 }, Pair{ .key = 11, .val = 12 } };   // control (already OK)
```

**RED today.** Combined pin: dump rc=2, 0 `.c`,
`error[3000]: cannot declare variable of type void` (inferred shape) plus
`warning[3000]: type mismatch ... note: source: void` (annotated shape).
Isolated annotated shape: dump rc=0, 5 `.c`, gcc rejects
`'zT_2' undeclared (first use in this function)` — the first element's
struct-literal temp is referenced but never declared. Isolated inferred shape:
dump rc=2, 0 `.c`, the same `error[3000]`.

**Root cause / loci.**
- `sf/src/semantic_analyzer.zig:3333` `semanticAnalyzerResolveArrayInit` resolves
  each element (`:3384-3389`) with **no expected type pushed**, so an anonymous
  struct/union literal element `.{...}` reaches
  `semanticAnalyzerResolveStructInit` (`:1794`) with no `topExpectedType`
  (`:1800`) and returns `TYPE_VOID` (`:1801`); the array then short-circuits to
  void at `:3390` before the annotation-derived element type (`:3362-3377`) can
  be used (`:3393-3394`). Enum literal elements hit the same missing-expected-type
  path (`:1743-1791`, `:1790` sets void).
- `sf/src/lower.zig:5012` array-init arm: the resolved type is void, so the
  element temp is allocated void (`:5034`, `:5045`) and the per-element store
  (`:5036-5040`) references it; `sf/src/c89_emit.zig:3893` never declares a
  `TYPE_VOID` (= id 1) temp, hence `zT_2 undeclared`.
- The same per-element store is a plain C `=` (`:5040`), which is also invalid
  for aggregate element kinds (nested array, slice, optional) even when the
  element type resolves.
- **Struct-field initializer path** (`var b: Box = .{ .items = [_]Pair{ ... } };`):
  the field store is emitted by `sf/src/c89_emit.zig:6093-6102` (`.assign_field`).
  For an array-typed field the `emitFieldAssign` array branch
  (`sf/src/c89_emit.zig:365-376`; `is_arr` set at `:329-333`) hardcodes a
  zero-fill `base.field[_j] = 0;` and **ignores `src`**. This is general to any
  array-typed struct field, not only struct elements: `[2]u32` is silently
  zeroed (runtime wrong-value/SIGTRAP), `[2]Pair` fails gcc with
  `incompatible types ... Pair from int`.

**Fix round 1 (v153 -> v154).** Probed the brief-requested `slice-of-struct`
element type and adjacent slice shapes: `[N][]Pair` (slice-of-struct) is
**correct** (dump/gcc/link/run rc=0, values correct), as are `[N][]u32` and
`[N][]const u8` built from genuine slice expressions (`b0[0..]`); the array
element store is a plain struct copy, which is valid C for the slice temp. Only
the **string-literal element** form (`[_][]const u8{ "ab", "cde" }`) fails (the
literal lowers as `unsigned char*` and is not coerced to a slice). The
struct-field zero-fill locus is pinned above. No `sf/src` change; fixed point
UNMOVED `bcfa85a40279a5c7bc4d8e6fd5f8df91`.

**Affected vs correct shapes** (local `var`; measured, fixed point `bcfa85a4`):

| element type / literal | inferred `[_]T{...}` | annotated `var x:[N]T = [_]T{...}` | class |
|---|---|---|---|
| plain struct, anon `.{...}` | `error[3000]` void | gcc `'zT_2' undeclared` | **BUG** |
| plain struct, typed `Pair{...}` | OK | OK | correct |
| tagged union, anon `.{...}` | `error[3000]` void | gcc `'zT_2' undeclared` | **BUG** |
| tagged union, typed `U{...}` | OK | OK | correct |
| enum, anon `.a` | `error[3000]` void | gcc clean but run SIGTRAP (wrong values) | **BUG** |
| enum, typed `E.a` | OK | OK | correct |
| optional `?u32` | gcc int -> optional | gcc int -> optional | **BUG** (element wrap) |
| nested array `[2]u32` | gcc `assignment to expression with array type` | same | **BUG** (aggregate copy) |
| slice `[]const u8`, string-literal elems | gcc slice <- pointer | same | **BUG** (string-literal -> slice coercion missing) |
| slice `[]T`, genuine slice elems (`[N][]Pair`, `[N][]u32`, `[N][]const u8` of real slices) | OK | OK | correct |
| struct w/ array field, anon | `error[3000]` void | gcc `'zT_2' undeclared` | **BUG** |
| struct w/ nested struct, anon | `error[3000]` void | gcc `'zT_2' undeclared` | **BUG** |
| scalar `u32` | OK | OK | correct |

Position sweep (plain struct): local anon `error[3000]` / typed OK; global anon
gcc `'zT_0' undeclared` (no `error[3000]`) / typed OK; struct-field anon gcc
`'zT_2' undeclared` / typed gcc `incompatible types ... Pair from int` (the field
array is zero-filled, values never stored); call argument by value anon gcc
`'zT_3' undeclared` / typed OK; call argument via `(literal)[0..]` frontend
`error[3043]: unsupported slice_expr form/base` (separate gap).

**Workaround** (used by `stdlib_sort`'s vtable fixture):
`var a: [N]Pair = undefined;` + per-element assignment (`a[0] = .{ ... };`).

**RED -> GREEN contract (Task 4b-F).** The inferred and annotated anonymous
struct-literal forms (and the aggregate element kinds the investigation confirms)
lower/emit/run; the fixture prints exactly `array of struct literal ok` (rc 0).
The committed `expected.txt`/`expected.rc` encode this DESIRED GREEN behaviour.

**Green-guard caveat.** The canonical classifier buckets `0 .c + error[3000]` as
GREEN ("documented green-guard"). Here the rejection is a FALSE rejection of
valid Zig, so the combined pin sits in GREEN today; the F fix flips it
**GREEN -> OK** (the classifier-pin movement). The annotated-shape gcc failure
(FAIL class) is only reachable in isolation because the inferred shape aborts the
combined file first.

**Corpus delta.** Universe **842 -> 843** (+1, the new pin). Class delta:
**+1 GREEN** (789 OK / 28 GREEN / 25 FAIL / 0 ICE -> 789 OK / **29 GREEN** /
25 FAIL / 0 ICE); all 842 pre-existing dirs are class-identical (no `sf/src`
change). (The v152 header's 836 predates the six Task-4 `stdlib_sort_*` dirs:
836 + 5 + 1 introsort = 842.) The dir is deliberately **not** added to
`scripts/stdlib/expected_dirs.txt` (compiler-class pin, not `stdlib_*`; cf.
`field_store_continue_xmod`). Full investigation:
`.superpowers/sdd/2026-09-17-std-lib-plan-c-data-codecs/task-4bI-report.md`.

## Plan C Task 3b-F — discarded fallible struct-returning catch fixed (v151 -> v152 2026-09-18)

Operator-ruled pin + fix for the pre-existing lowering defect found while
authoring `std_map` (Plan C Task 3).

**Root cause.** `sf/src/lower.zig` catch lowering: a catch body that produces no
value (an empty block, a statement-only block, or a void expression) leaves
`lowerExprOrBlock` returning temp `0` (its no-value sentinel, which collides with
real temp index 0) or a statement's incidental value (e.g. an assignment's RHS).
The err branch then emitted `join_temp = <that temp>`, storing an integer into
the payload-typed join temp. For a scalar payload this compiles to a harmless
(but bogus, discarded) value; for a **struct** payload it emits an invalid C89
assignment (`incompatible types when assigning to type '...' from type 'int'`).

**Fix.** The catch err branch now skips the join assignment when the catch body
is valueless (`lowerCatchBodyIsValueless`: empty/statement block, assignment
kind, or void-typed result) and just jumps to the join. Value-producing catch
bodies are unchanged. `sf/src/std_map.zig` was authored against the defect with a
bound-variable helper; that helper is now optional (left in place).

**New pin.** `repro/mi_matrix/catch_discard_struct_xmod` — the exact
`_ = f() catch |e| { ... };` shape on a `!Pair` call (error path and success
path), plus the bound form as a control; `ck`-style `@panic` asserts and stable
stdout `catch discard struct ok`.

| dir | class (v151) | class (v152) | evidence |
|---|---|---|---|
| `catch_discard_struct_xmod` | **FAIL** (dump rc=0, 5 `.c`; gcc rejects `zT_.. = <int>` into a struct temp) | **OK** (runtime GREEN) | `run_fixtures.sh` explicit: PASS; stdout `catch discard struct ok`, rc=0, 3x deterministic |

**Corpus delta.** Universe **835 -> 836** (+1, the new pin). Class delta:
**+1 OK / -1 FAIL** (782 OK / 28 GREEN / 25 FAIL / 0 ICE -> **783 OK** / 28 GREEN
/ 25 FAIL / 0 ICE). The full-classifier diff over the 836-dir universe (pre-fix
vs post-fix) is exactly one line: the new pin **FAIL -> OK** — zero unexpected
movement. (The v151 header's 830 predates the five Task-3 `stdlib_map_*_xmod`
fixtures, all OK, already counted in the 835 baseline here.) The 4-MD5 gate
programs (gol/lisp/json/mud) emit byte-identically. Runtime gate **128 PASS / 0
FAIL over 128 dirs**; `check_emit_support.sh` **7/7**; self-compile **48 `.c`,
rc=0, 0 errors, 0 PANIC**; `CLOSEOUT OK` (A1-A5, B1-B7, C1).

The self-emission fixed point **MOVES**
`9265739b7b5e7b1626b8db7ad4255fc5` -> **`bcfa85a40279a5c7bc4d8e6fd5f8df91`**
(hop1 == hop2) and the seed rotates **v35 -> v36** (archive md5
`981d58539c31cd5b66d97aef4ee87ebe` -> `a0a2fc8e49fc888385b0927ada602b06`).

This dir is deliberately **not** added to `scripts/stdlib/expected_dirs.txt`
(compiler-class pin, not `stdlib_*`; cf. `field_store_continue_xmod`). The corpus
manifest + classifier are the pin mechanism.

## Plan C Task 2b-F follow-up — lexer f64 exponent after a decimal point fixed (v150 -> v151 2026-09-18)

Operator-ruled pin + fix for the pre-existing `parseF64` bug found while
replacing `gcvt` (the F half of the lexer-exponent I/F pair).

**Root cause.** `sf/src/lexer.zig` `parseF64`: the fraction loop advanced `i`
past the `e`/`E` before breaking (`i += 1` at the top of the loop), so the
exponent block at `:643` saw the character *after* the `e` and was skipped. A
decimal-point mantissa followed by an exponent (`1.0e300`, `1.5e-3`) therefore
parsed with its exponent silently dropped (`1.0`, `1.5`), while no-dot literals
(`1e300`) decremented `i` first and parsed correctly. This is why the Task 2b-I
`1.7976931348623157e308` -> `1.79769` example was doubly wrong (the exponent was
already lost before the 6-digit formatter saw the value).

**Fix.** The fraction loop now decrements `i` before breaking on `e`/`E`
(`if (c == 'e' or c == 'E') { i -= 1; break; }`), mirroring the integer-part
loop, so the exponent block sees the `e`. No other parsing path changes.

**New pin.** `repro/mi_matrix/lexer_float_exponent_xmod` — a decimal-point +
exponent literal (`1.0e300` vs `1e300`, `1.5e-3`, `2.5e10` vs `25e9`) with
`ck`-style `@panic` asserts and a stable stdout line.

| dir | class (v150) | class (v151) | evidence |
|---|---|---|---|
| `lexer_float_exponent_xmod` | **OK** (runtime RED) | **OK** (runtime GREEN) | `run_fixtures.sh` explicit: PASS; stdout `lexer float exp ok`, rc=0 |

**Corpus delta.** Universe **829 -> 830** (+1, the new pin). Class delta vs v150:
**+1 OK** (776 OK / 28 GREEN / 25 FAIL / 0 ICE -> **777 OK** / 28 GREEN / 25
FAIL / 0 ICE); full-classifier diff over the 830-dir universe is exactly one line
(the new pin). The 4-MD5 gate programs (gol/lisp/json/mud) emit byte-identically.
Runtime gate **123 PASS / 0 FAIL over 123 dirs**; `check_emit_support.sh`
**7/7**; self-compile **48 `.c`, rc=0, 0 errors, 0 PANIC**; `CLOSEOUT OK`
(A1-A5, B1-B6, C1).

The self-emission fixed point **MOVES again**
`b0e7042a26e74d7b744a0a49546149b4` -> **`9265739b7b5e7b1626b8db7ad4255fc5`**
(hop1 == hop2) and the seed rotates **v34 -> v35** (archive md5
`a4d4de3cc7ff131da3a01865b3622ed7` -> `981d58539c31cd5b66d97aef4ee87ebe`).

**Declassification.** `lexer_float_exponent_xmod` remains a permanent regression
pin; the v150 report's "New concern" (the parseF64 exponent drop) is resolved.

## Plan C Task 2b-F follow-up — self-contained f64 formatting (no gcvt) (v149 -> v150 2026-09-18)

Operator follow-up to the v149 fix: replace the non-standard libc `gcvt` with an
in-tree self-contained dtoa. `formatF64` (`sf/src/util/format.zig`) now recovers
the 53-bit significand by exact power-of-two scaling, builds the exact decimal
big integer `B` (`m*2^E` when `E >= 0`, `m*5^-E` when `E < 0`) in base-1e9
limbs, rounds its top 17 digits, and emits normalized scientific notation
`d.dddddddddddddddde±XX` with trailing fractional zeros trimmed. 17 significant
digits guarantee IEEE-754 double round-trip; the implementation is pure Zig/C89
with no `@cInclude` and no libc float formatting. The dead `extractDigit` helper
is removed. The zero/inf/nan guard emits `0` (no valid C89 literal; the previous
`gcvt` emitted the invalid token `inf`, and the pre-gcvt 6-digit formatter looped
forever).

The self-emission fixed point **MOVES again**
`417c435cec303378b224ecdff3f64f26` -> **`b0e7042a26e74d7b744a0a49546149b4`**
(hop1 == hop2) and the seed rotates **v33 -> v34** (archive md5
`799dbca38d211f6a3d962f3773215adf` -> `a4d4de3cc7ff131da3a01865b3622ed7`).

| dir | class (v149) | class (v150) | evidence |
|---|---|---|---|
| `lit64_decimal_xmod` | **OK** (runtime GREEN) | **OK** (runtime GREEN) | `run_fixtures.sh` explicit: PASS; stdout `lit64 ok`, rc=0 |
| `f64_literal_precision_xmod` | **OK** (runtime GREEN) | **OK** (runtime GREEN) | `run_fixtures.sh` explicit: PASS; stdout `f64 lit ok`, rc=0 |

**Corpus delta.** Universe **829 dirs** unchanged; class map **unchanged**
(776 OK / 28 GREEN / 25 FAIL / 0 ICE / 0 CRASH; full-classifier diff empty —
zero unexpected movement vs the v149 `gcvt` compiler). The 4-MD5 gate programs
(gol/lisp/json/mud) emit byte-identically. Runtime gate **123 PASS / 0 FAIL over
123 dirs**; `check_emit_support.sh` **7/7**; self-compile **48 `.c`, rc=0, 0
errors, 0 PANIC**; `CLOSEOUT OK` (A1-A5, B1-B6, C1). A 47-literal `strtod`
round-trip harness confirms the new formatter's text parses to exactly the same
doubles as the v149 `gcvt` formatter. `sf/docs/tech_docs/00_shared_infra.md` §9
updated (`extractDigit` removed; `formatF64` + the two new helpers documented).

**Declassification.** The v149 "Fix (2)" gcvt description is superseded by this
section; both pins remain permanent regression pins.

## Plan C Task 2b-F (F) — 64-bit decimal + f64 literal precision fixed (v148 -> v149 2026-09-18)

The **F** half of the operator-ruled I/F pair (m1703). Both Task 2b-I pins flip
RED -> GREEN; the self-emission fixed point **MOVES**
`ab7187cc988e39dc5907b95ccc182f9f` -> **`417c435cec303378b224ecdff3f64f26`**
(hop1 == hop2) and the seed rotates **v32 -> v33** (archive md5
`799dbca38d211f6a3d962f3773215adf`). This is the second authorized Plan C
`sf/src` change class (m1703).

**Fix (1) — 64-bit decimal literal truncation.** Root cause: the global-`const`
int-literal materialization in `lowerExprImpl`'s `ident_expr` path
(`sf/src/lower.zig:3223`) hardcoded `nextTemp(self, type_mod.TYPE_U32)`, so a
literal that does not fit in 32 bits (e.g. `const TWO63: u64 =
9223372036854775808;`) lowered into a 32-bit `unsigned int` temp and truncated
before widening. The temp type is now selected from the literal value:
`TYPE_U32` when `val <= 0xFFFFFFFF`, else `TYPE_U64`. The emitted C becomes
`zT_79FAE712_u64 zT_1; zT_1 = 9223372036854775808ULL; lim = zT_1;`. Values that
fit in 32 bits keep the exact previous `TYPE_U32` behaviour (zero corpus
movement).

**Fix (2) — f64 literal precision.** Root cause: `formatF64`
(`sf/src/util/format.zig`) hand-extracted only **6** significant digits in f64
arithmetic, so an f64 literal emitted at ~6 digits (`0.3333333333333333` ->
`3.33333e-1`; `1.7976931348623157e308` -> `1.79769`). `formatF64` now delegates
to the host C library `gcvt(value, 17, buf)`, which emits 17 significant digits —
enough for IEEE-754 double round-trip. `0.3333333333333333` now emits
`0.33333333333333331` and the f64-max literal emits `1.7976931348623157e+308`.

| dir | class (v148) | class (v149) | evidence |
|---|---|---|---|
| `lit64_decimal_xmod` | **OK** (runtime RED) | **OK** (runtime GREEN) | `run_fixtures.sh` explicit: PASS; stdout `lit64 ok`, rc=0 |
| `f64_literal_precision_xmod` | **OK** (runtime RED) | **OK** (runtime GREEN) | `run_fixtures.sh` explicit: PASS; stdout `f64 lit ok`, rc=0 |

**Corpus delta.** Universe **829 dirs** unchanged; class map **unchanged**
(776 OK / 28 GREEN / 25 FAIL / 0 ICE / 0 CRASH; full-classifier diff empty —
zero unexpected movement). The two pins were already compile-clean, so their
class stays OK; only their RUNTIME flips RED -> GREEN. The 4-MD5 gate programs
(gol/lisp/json/mud) emit byte-identically to the pre-fix compiler. Runtime gate
**123 PASS / 0 FAIL over 123 dirs**; `check_emit_support.sh` **7/7**;
self-compile **48 `.c`, rc=0, 0 errors, 0 PANIC**; `CLOSEOUT OK` (A1-A5, B1-B6,
C1 PASS).

**Declassification.** Both dirs remain in the corpus (they are the permanent
regression pins for this fix) but are declassified as limitations: the RED
declaration in the v148 section below is superseded — the compiler now lowers
and emits both literals with full width/precision. The `sf/src/std_parse.zig`
workarounds (the `@intCast(u64, 0x8000000000000000)` reference and the
`value != 0.0 and value * 2.0 == value` inf test) are no longer required, but are
left in place (harmless; out of this task's scope).

## Plan C Task 2b-I (I) — 64-bit/f64 literal limitations pinned (v147 -> v148 2026-09-18)

Plan C Task 2 found two pre-existing compiler limitations; the operator ruled
(m1703) each becomes an I/F pair. This task is the **I** half (pin only). **No
`sf/src` change**: the self-emission fixed point stays **UNMOVED
`ab7187cc988e39dc5907b95ccc182f9f`** (seed v32 archive md5
`2eb158f3f24363968e9bf0f085461de8`); no seed rotation. Task 2b-F (the F half)
fixes both and MOVES the fixed point.

**New corpus dirs** (auto-listed by `scripts/corpus/list_corpus_dirs.sh`):

| dir | class | RED today (fixed point ab7187cc…) | expected GREEN (Task 2b-F) |
|---|---|---|---|
| `lit64_decimal_xmod` | **OK** (compile-clean) | dump rc=0, 5 `.c`, gcc clean; link+run rc=133 (SIGTRAP); stdout empty, panic `64-bit decimal literal survives widening` | run rc=0, stdout `lit64 ok` |
| `f64_literal_precision_xmod` | **OK** (compile-clean) | dump rc=0, 5 `.c`, gcc clean; link+run rc=133 (SIGTRAP); stdout empty, panic `f64 literal carries full precision` | run rc=0, stdout `f64 lit ok` |

**Trigger (1).** A decimal integer literal that does not fit in 32 bits,
declared at container scope and assigned to a u64:

```zig
const TWO63: u64 = 9223372036854775808;   // 2^63
...
var lim: u64 = TWO63;
```

**Mis-lowering (1).** The literal materializes in a 32-bit (`unsigned int`) temp
and truncates before being widened, so `lim` is 0 (2^63 mod 2^32). Emitted C:
`unsigned int zT_1; zT_1 = 9223372036854775808ULL; lim = zT_1;`. The
`ck(lim == @intCast(u64, 0x8000000000000000))` assert traps. `sf/src/std_parse.zig`
works around it with `@intCast(u64, 0x8000000000000000)`.

**Trigger (2).** An f64 literal whose value needs more than ~6 significant
digits, compared against the same value computed at runtime:

```zig
var lit: f64 = 0.3333333333333333;   // 16 sig digits
var third: f64 = 1.0 / 3.0;          // same value, computed at runtime
```

**Mis-lowering (2).** The literal emits at ~6 significant digits
(`(double)(3.33333e-1)`), so `lit - (1.0/3.0)` is ~3.33e-7 and the
`ck(d < 1e-15)` assert traps. `sf/src/std_parse.zig` works around it by avoiding
an f64-max literal (`1.7976931348623157e308` -> `(double)(1.79769)`).

**RED -> GREEN contract (Task 2b-F).** Both literals lower/emit with full
width/precision; `lit64_decimal_xmod` runs and prints exactly `lit64 ok` (rc 0)
and `f64_literal_precision_xmod` prints exactly `f64 lit ok` (rc 0). The
committed `expected.txt`/`expected.rc` encode this DESIRED GREEN behaviour, so
both pins are RED until Task 2b-F. The emitted C is gcc-clean in both cases, so
the corpus `-ffast` dump+gcc classifier buckets both dirs **OK**; the RED is
RUNTIME-only (the assert trap).

**Corpus delta.** Universe **827 -> 829** (+2). Class delta vs the 827
pre-existing dirs: **+2 OK** (774 OK / 28 GREEN / 25 FAIL / 0 ICE -> 776 OK /
28 GREEN / 25 FAIL / 0 ICE); all 827 pre-existing dirs are class-identical (no
`sf/src` change). (The v147 header's 817 predates the 10 Task-2 `stdlib_parse_*`
dirs, committed at `5561e4f1` without a manifest bump; 817 + 10 = 827.) Neither
dir is added to `scripts/stdlib/expected_dirs.txt`: that pin drives the std-lib
runtime gate's discovery (`repro/mi_matrix/stdlib_*/` + `stdlib_test/*/`,
all-GREEN), and a runtime-RED compiler pin would both break the discovery-set
equality and make the gate fail. The corpus manifest + classifier are the pin
mechanism for compiler-class dirs (cf. `field_store_continue_xmod`,
`undefined_slice_array_xmod`).

## Plan C Task 1b-F (nested extension) — nested field-store continue-expr fixed (v146 -> v147 2026-09-18)

Operator-ruled extension of Task 1b-F. The v146 lowering fallback fixed the
single-level shape but a **nested** field store as a `while` continue expression
(`while (o.inner.n < 56) : (o.inner.n += 1)`) still ICEd
(`error[3043]: internal: unsupported address-of l-value`) because the nested
base branch (`lowerFieldStore` `child_0_node.kind == field_access`) calls
`lowerLValueAddr`, which also reads the resolved-type table. Root cause is the
analyzer never visiting `while` `child_2`; the extension resolves it in
`semanticAnalyzerResolveWhileHeader` (`sf/src/semantic_analyzer.zig`), after the
capture is registered, so every continue-expression sub-expression gets a
resolved type. The v146 `lower.zig` fallbacks are kept (harmless; now usually a
no-op). This is still the ONE authorized Plan C `sf/src` change class. The
self-emission fixed point **MOVES again**
`6d704d2265096513cf1706f5b414bd27` -> **`ab7187cc988e39dc5907b95ccc182f9f`**
(hop2 == hop3, moving point) and the seed rotates **v31 -> v32** (archive md5
`2eb158f3f24363968e9bf0f085461de8`).

| dir | class (v146) | class (v147) | evidence |
|---|---|---|---|
| `field_store_continue_nested_xmod` | **ICE** (pre-extension) | **OK** | dump rc=0, 5 `.c`; gcc clean; link+run rc=0; stdout `nested field store continue ok` (3x deterministic) |

**Corpus delta.** Universe **816 -> 817** (+1, the new nested pin). Class delta
vs v146: **+1 OK** and the new dir ICE -> OK
(763 OK / 28 GREEN / 25 FAIL / 0 ICE -> **764 OK / 28 GREEN / 25 FAIL / 0
ICE**); all 816 pre-existing dirs are class-identical (full-classifier diff over
the 817-dir universe: exactly one line — the new nested dir ICE -> OK; the
original `field_store_continue_xmod` stays OK). Runtime gate **113 PASS / 0 FAIL
over 113 dirs**; `check_emit_support.sh` **7/7**; self-compile **48 `.c`, rc=0, 0
errors, 0 PANIC**; `CLOSEOUT OK` (A1-A5, B1-B6, C1 PASS).

## Plan C Task 1b-F (F) — field-store-as-continue-expression ICE fixed (v145 -> v146 2026-09-18)

The **F** half of the operator-ruled I/F pair (m1670). `sf/src/lower.zig` now
falls back to the lowered base temp's declared type when a field-access base has
no resolved-type entry — which is exactly the state of a `while` continue
expression, because the semantic analyzer never visits `child_2`
(`semantic_analyzer.zig:3128` pushes only the body). Both the field-store path
(`lowerFieldStore`) and the field-access read path now use that fallback, so a
compound field-store in a continue expression lowers like the body form. This is
the ONE authorized `sf/src` change in Plan C; the self-emission fixed point
**MOVES** `414cccee639bdb61c7a9f1f2ddddb166` -> **`6d704d2265096513cf1706f5b414bd27`**
(hop1 == hop2) and the seed rotates **v30 -> v31** (archive md5
`7ae31cec80cc3726dba042d694c11c25`).

| dir | class (v145) | class (v146) | evidence |
|---|---|---|---|
| `field_store_continue_xmod` | **ICE** | **OK** | dump rc=0, 5 `.c`; gcc clean; link+run rc=0; stdout `field store continue ok` (3x deterministic) |

**Corpus delta.** Universe **816 dirs** unchanged. Class delta vs v145:
**-1 ICE / +1 OK** (762 OK / 28 GREEN / 25 FAIL / 1 ICE -> **763 OK / 28 GREEN /
25 FAIL / 0 ICE**); all 815 other dirs are class-identical (full-classifier diff:
exactly one line). Runtime gate **113 PASS / 0 FAIL over 113 dirs**;
`check_emit_support.sh` **7/7**; self-compile **48 `.c`, rc=0, 0 errors, 0
PANIC**; `CLOSEOUT OK` (A1-A5, B1-B6, C1 PASS).

## Plan C Task 1b-I (I) — field-store-as-continue-expression ICE pinned (v144 -> v145 2026-09-18)

Plan C Task 1 found a pre-existing compiler ICE; the operator ruled it a pin+fix
I/F pair (m1670). This task is the **I** half (pin only). **No `sf/src` change**:
the self-emission fixed point stays **UNMOVED `414cccee639bdb61c7a9f1f2ddddb166`**
(seed v30 archive md5 `c0a218c5e7a74afb11435abe20c7d990`). Task 1b-F (the F half)
fixes the lowering and MOVES the fixed point.

**New corpus dir** (auto-listed by `scripts/corpus/list_corpus_dirs.sh`):

| dir | class | RED today (fixed point 414cccee…) | expected GREEN (Task 1b-F) |
|---|---|---|---|
| `field_store_continue_xmod` | **ICE** | dump rc=3, 0 `.c`; `error[3043]: internal: unsupported field-store base (node 42)` | dump rc=0, gcc clean, link+run rc=0, stdout `field store continue ok` |

**Trigger.** A compound assignment to a struct field used as the continue
expression of a `while` loop:

```zig
pub const S = struct { buf: [64]u8, buf_len: usize };
pub fn fill(s: *S) void {
    while (s.buf_len < 56) : (s.buf_len += 1) {   // <-- continue expression
        s.buf[s.buf_len] = 0;
    }
}
```

The continue-expression lowering has no field-store base and ICEs. The body form
(`s.buf_len += 1;` inside the loop) lowers correctly; `sf/src/std_crypto.zig`
uses that workaround in all three `Final` padding loops (a local counter is used
for the message-schedule loops).

**RED -> GREEN contract (Task 1b-F).** The continue-expression form lowers like
the body form; the fixture runs and prints exactly `field store continue ok`
(rc 0). The committed `expected.txt`/`expected.rc` encode this DESIRED GREEN
behaviour, so the pin is RED until Task 1b-F. `error[3043]` is in the canonical
classifier's ICE regex (`scripts/corpus/classify`), so this dir buckets **ICE**.

**Corpus delta.** Universe **815 -> 816** (+1). Class delta vs the 815
pre-existing dirs: **+1 ICE** (761 OK / 28 GREEN / 25 FAIL / 0 ICE -> 762 OK /
28 GREEN / 25 FAIL / 1 ICE); all 815 pre-existing dirs are class-identical (no
`sf/src` change). (The v144 header's 810 predates five dirs: Task 1's four
`stdlib_crypto_*_xmod` and the Plan B final-review `stdlib_stream_multiple_async_xmod`.)
This dir is deliberately **not** added to
`scripts/stdlib/expected_dirs.txt`: that pin drives the std-lib runtime gate's
discovery (`repro/mi_matrix/stdlib_*/` + `stdlib_test/*/`, all-GREEN), and an
ICE pin would both break the discovery-set equality and make the gate fail. The
corpus manifest + classifier are the pin mechanism for compiler-class dirs
(cf. `module_value_addr_global_xmod`, `taskptr_field_store_xmod`).


## Plan B hardening closeout — harness hardening + probes + stress tier (v143 -> v144 2026-09-18)

Plan B test-hardening (`docs/superpowers/plans/2026-09-18-plan-B-test-hardening.md`) is
**COMPLETE** (Tasks 1-4 + the operator-ruled Task 5a-I/5a-F I/F pair + this closeout).
Docs/scripts/fixtures plus the ONE authorized `sf/src` std-only fix (Task 5a-F, below).
**No compiler-graph change**: the self-emission fixed point is **UNMOVED
`414cccee639bdb61c7a9f1f2ddddb166`** (a std-only change cannot move it — the compiler's
import graph reaches no std module). The seed rotates **v29 -> v30** (archive md5
`c0a218c5e7a74afb11435abe20c7d990`) because the archive embeds `lib/`.

**Harness hardening (Task 1, `scripts/stdlib/run_fixtures.sh`).**
- `--capture <zig1> [dirs...]` writes the observed stdout+rc to the per-fixture goldens,
  with a guard: a nonzero rc not already declared in an existing `expected.rc` is REFUSED
  (`CAPTURE-REFUSED-RC<rc>(undeclared)`, no golden written); a nondeterministic fixture is
  refused (`NONDETERMINISTIC`). Capture is always followed by a human review against the
  fixture's documented GREEN contract.
- Discovery broadened from `stdlib_*_xmod` to any `stdlib_*` dir
  (`^repro/mi_matrix/stdlib_[^/]*/$`) plus `stdlib_test/*/` (pin-neutral today: no
  non-`_xmod` std dir exists). An unpinned-dir guard now ALWAYS fails
  `unpinned-stdlib-dir (<dir>)` if a `repro/mi_matrix/stdlib_*/` or `stdlib_test/*/` dir
  exists on disk but is not in the pin — even in explicit-`<dir>` runs and for a dir with
  no resolvable entry.
- gcc/link diagnostics surfaced: a `GCCFAIL` echoes the first line of `.gccerr`
  (`gcc stderr: ...`); a `BUILD-RC<rc>` echoes the first line of `.builderr`
  (`build stderr: ...`).

**Golden convention (binding).** Each fixture dir carries `expected.txt` (exact stdout
bytes) + `expected.rc` (exit code). A missing golden is a FAIL (no silent skips);
`scripts/stdlib/expected_dirs.txt` pins the discovered set so coverage cannot silently
shrink; a fixture that binds a port ships `ports.txt`. Goldens are runtime-only
(stdout+rc), captured only after the observed output matched the fixture's documented
GREEN contract, and re-captured only on an intentional behavior change.

**New fixtures (7).**

| fixture | kind | contract |
|---|---|---|
| `stdlib_file_openerr_xmod` | expected-failure probe | `open(arena, nonexistent, Read)` -> `FileError.OpenFailed`, caught + asserted in-process; stdout `file openerr ok`, rc 0 |
| `stdlib_file_stress_xmod` | stress | 10000-byte writeAll/readAll round-trip embedding binary `\r`/`\n`/NUL at pinned offsets + 777-byte chunked read to EOF; stdout `file stress ok` |
| `stdlib_stdin_stress_xmod` | stress | 4321-byte line across the overflow boundary + EOF without trailing newline (deterministic stdin via dup2); stdout `stdin stress ok` |
| `stdlib_net_udp_stress_xmod` | stress | max IPv4 UDP payload (65507 B) loopback byte-exact + zero-length + truncation; binds a fixed port (`ports.txt`); stdout `udp stress ok` |
| `stdlib_stream_stress_xmod` | stress | 250-byte line through a 100-byte buffer + final line with no trailing newline + empty source; stdout `stream stress ok` |
| `stdlib_stdin_multiple_xmod` | exact-multiple pin | Task 5a-I RED -> 5a-F GREEN; `"abcd\n"` via a 4-byte buffer yields `abcd` then `z` (no spurious empty line); stdout `stdin multiple ok`, rc 0 |
| `stdlib_stream_multiple_xmod` | exact-multiple pin | Task 5a-I RED -> 5a-F GREEN; same exact-multiple contract for `std_stream.readFileLineSync`; stdout `stream multiple ok`, rc 0 |

**Gates (seed-built fixed-point compiler `414cccee`).** Runtime gate **108 PASS / 0 FAIL
over 108 dirs** (3x determinism internal; pin `scripts/stdlib/expected_dirs.txt` = 108
data lines: 104 `repro/mi_matrix/stdlib_*` + 4 `stdlib_test/*`).
`scripts/check_emit_support.sh` **7/7** byte-identical. Self-compile `-ffast --dump-c89`
rc=0, 48 `.c` + 48 `.h`, 0 `error[`, 0 PANIC. Corpus `-ffast` dump+gcc classifier
**810 dirs = 757 OK / 28 GREEN / 25 FAIL / 0 ICE / 0 CRASH** (803 -> 810: the 7 new dirs
all classify OK; every pre-existing dir class-identical). `scripts/closeout/verify_upgraded.sh`
**CLOSEOUT OK** (A1-A5 / B1-B7 / C1). Seed v30 round-trip re-verified (two-hop closure
hop1 == hop2 == `414cccee`). Full report:
`.superpowers/sdd/2026-09-18-plan-B-test-hardening/task-5-report.md`.

## Plan B hardening Task 5a-F — exact-multiple long-line defect fixed (v142 -> v143 2026-09-18)

Task 5a-F fixes the exact-multiple long-line defect pinned by Task 5a-I, in the ONE
authorized `sf/src` change of this plan. **`sf/src` std-only fix — the self-emission
fixed point stays UNMOVED `414cccee639bdb61c7a9f1f2ddddb166`** (the compiler's import
graph reaches no std module; the std lib is user-side `.zig` resolved from
`<exe_dir>/lib/`). **The seed STILL rotates v29 -> v30** because the seed archive
embeds `lib/`.

Fix shape: `std_stdin.readLine` carries a `pending_overflow` boundary flag; a full
buffer whose last byte is not `\r` sets it, and the next call consumes the line's own
`\n`/`\r\n` terminator before reading the following line. `std_stream.FileLineReader`
gains `overflow_cont`, set by `takeOverflow`, consumed by the new `resolveOverflow`
(wired into `readFileLineSync` and `awaitLine`). Both carries are engaged only when
`buf.len > 1`, preserving the frozen 1-byte-buffer boundary behaviour
(`stdlib_stream_crlf_boundary_xmod`).

**Declassification (both fixtures now GREEN).** The two dirs stay corpus class `OK`
(compile-clean); the RED was RUNTIME-only, so the class map does not move — only the
run gate flips.

| fixture | pre-fix (5a-I, fixed point `414cccee`) | post-fix (5a-F, fixed point `414cccee`) |
|---|---|---|
| `stdlib_stdin_multiple_xmod` | dump/gcc/link rc=0; run rc=133 (SIGTRAP), stdout empty, panic `exact-multiple next line (no spurious empty)` (observed `["abcd", "", "z"]`) | **PASS** — lines exactly `["abcd", "z"]` then null; stdout `stdin multiple ok\n`, rc=0 |
| `stdlib_stream_multiple_xmod` | dump/gcc/link rc=0; run rc=133 (SIGTRAP), stdout empty, panic `exact-multiple next line (no spurious empty)` (observed `["abcd", "", "z"]`) | **PASS** — lines exactly `["abcd", "z"]` then null; stdout `stream multiple ok\n`, rc=0 |

Runtime gate **106 PASS / 2 FAIL -> 108 PASS / 0 FAIL over 108 dirs** (3× deterministic).
Other gates: `check_emit_support.sh` 7/7; self-compile 48 `.c` + 48 `.h`, 0 errors,
0 PANIC; corpus `-ffast` dump+gcc classifier 810 dirs = **757 OK / 28 GREEN / 25 FAIL /
0 ICE / 0 CRASH** (unchanged class distribution vs the Plan B closeout 800 = 747 OK /
28 GREEN / 25 FAIL — the +10 dirs are all new OK); `CLOSEOUT OK`. Seed v30 archive md5
and fixed point recorded in `release/seed/CHANGELOG.md`. Full report:
`.superpowers/sdd/2026-09-18-plan-B-test-hardening/task-5aF-report.md`.

---

## Plan B hardening Task 5a-I — exact-multiple long-line defect pinned (v141 -> v142 2026-09-18)

Task 5a-I pins the exact-multiple long-line defect found in Plan B hardening Task 4 (operator
ruling m1568/m1569). **Fixtures/manifest/docs only — no `sf/src` change; fixed point UNMOVED
`414cccee639bdb61c7a9f1f2ddddb166`; seed v29 NOT rotated.**

The defect: a line whose length is an exact multiple of `buf.len` (`len % buf.len == 0`) makes
both `std_stdin.readLine` (`sf/src/std_stdin.zig:99-122`) and `std_stream.readFileLineSync`
(`sf/src/std_stream.zig:95-104,152-162`) emit a spurious empty line. Probe: a 4-byte buffer over
`"abcd\nz\n"` yields `["abcd", "", "z"]` instead of `["abcd", "z"]`. The blueprint contract only
specified the "longer than buf" case; the exact-multiple boundary was unspecified. It is now
specified (blueprint §3 L3/L6 + hardening spec) as: a line whose length is an exact multiple of
`buf.len` must NOT yield a trailing empty line.

| fixture | RED today (fixed point `414cccee`) | GREEN contract (Task 5a-F) |
|---|---|---|
| `stdlib_stdin_multiple_xmod` | dump/gcc/link rc=0; run rc=133 (SIGTRAP), stdout empty, panic `exact-multiple next line (no spurious empty)` (observed `["abcd", "", "z"]`) | lines exactly `["abcd", "z"]` then null; stdout `stdin multiple ok\n`, rc=0 |
| `stdlib_stream_multiple_xmod` | dump/gcc/link rc=0; run rc=133 (SIGTRAP), stdout empty, panic `exact-multiple next line (no spurious empty)` (observed `["abcd", "", "z"]`) | lines exactly `["abcd", "z"]` then null; stdout `stream multiple ok\n`, rc=0 |

The two dirs are compile-clean (dump/gcc/link rc=0) so the corpus `-ffast` classifier buckets
them `OK`; the RED is RUNTIME-only (the assert trap). `scripts/stdlib/expected_dirs.txt` pins the
discovered set **106 -> 108**. Full report:
`.superpowers/sdd/2026-09-18-plan-B-test-hardening/task-5aI-report.md`.

---

## Plan B cleanup — known-issues residuals (v140 -> v141 2026-09-18)

Plan B cleanup round (`fix(std): Plan B cleanup — stdin Io/EOF/CRLF,
frame-size, fixture tightening`) fixed 7 review minors; the remaining
un-fixed minors are recorded here. Std-side/fixtures/scripts only — no
compiler-graph file; fixed point UNMOVED `414cccee639bdb61c7a9f1f2ddddb166`.

| residual | where | note |
|---|---|---|
| `GetStdHandle(i32)` vs `<windows.h>` `DWORD` | `sf/src/std_stdin_pal.zig` | declared `i32`; Windows `GetStdHandle` takes/returns `DWORD` (unsigned long). ABI-identical on i386; not re-typed this round. |
| blueprint truncation wording (inverted) | `sf/docs/std_lib_extension.txt` §3 L3 `std_file` | the readAll/truncation wording is inverted; docs-only. |
| `__errno_location` glibc-specific | `sf/src/std_file_pal.zig` / `std_net.zig` | the POSIX errno accessor is glibc-specific (musl differs); x86_64-linux/glibc is the only supported POSIX target today. |
| `awaitLine` extra yield | `sf/src/std_stream.zig` | the async reader suspends once more than strictly needed on the last incomplete read. |
| Program C graph-isolation evidence report-only | closeout report | the graph-isolation claim for Program C is report-only (not an automated gate). |
| chunk granularity `buf.len/4` | `sf/src/std_stream.zig` | the async chunk is a fixed quarter of the caller buffer; no adaptive sizing. |
| `file_stdin_usage` seek-check weakness + redundant `feed()` + literal echo | `stdlib_test/file_stdin_usage/main.zig` | the seek check does not assert the post-seek read; `feed()` is called after the file was already written; the final lines echo literals rather than the read data. |
| `off_t` i32 | `sf/src/std_file.zig` | file offsets are `i32` (not `off_t`/i64); >2 GiB files are out of contract. |
| `std_file.zig` `@cInclude("<fcntl.h>")` unused | `sf/src/std_file.zig` | the include is not required by the emitted code path. |
| stale std-count comment | `docs/sf/QUICK_REF.md:36,45` (historically `scripts/check_emit_support.sh`) | QUICK_REF still says "15 std `.zig`"; the canonical set is 20 (`scripts/check_emit_support.sh` already reads 20). |

---

## Plan B closeout — L3 resources + std_stream landed (v139 -> v140 2026-09-18)

Plan B (`docs/superpowers/plans/2026-09-17-std-lib-plan-b-resources-stream.md`) is
**COMPLETE**. The L3 resources and the L6 capstone landed: `std_file` + `std_file_pal`
(binary-safe file I/O; win32 `CreateFileA`/`GetFileSizeEx`, POSIX `open`/`read`/`write`);
`std_stdin` + `std_stdin_pal` (line-based stdin over a `std_file.File`); the `std_net` UDP
extension (`Socket` alias, 8-member `NetError` (no OOM), `IpAddr`,
`udpBind`/`udpSendTo`/`udpRecvFrom`/`udpSetTimeout`); and the file-only `std_stream`
(`FileLineReader`/`initFileLineReader`/`readFileLineSync`/`readFileLineAsync` — Model C
cooperative-yield, a separate chunked async implementation over the `@asyncSuspend`
builtin). `SocketLineReader`/`MsgReader`, the non-blocking socket primitives, and
`std.async.wait(handle)` are Plan D (recorded, not scheduled). This closeout commit is
**docs/scripts/fixtures only — no `sf/src` change**; the self-emission fixed point is
**UNMOVED `414cccee639bdb61c7a9f1f2ddddb166`** and the seed stays **v29** (archive md5
`910a4d673f0fa95f8473c08e143ceb54`). No seed rotation (the fixed point did not move).

**New modules (5):** `sf/src/std_file.zig`, `sf/src/std_file_pal.zig`,
`sf/src/std_stdin.zig`, `sf/src/std_stdin_pal.zig`, `sf/src/std_stream.zig`; the
`sf/src/std_net.zig` UDP extension (edit). Both seed `lib/` copy lists
(`scripts/seed/build_from_seed.sh` + `scripts/seed/archive_seed.sh`) carry all 20 std
`.zig` (Tasks 1/2/4 appended theirs in-commit; Task 5 verified them and fixed the stale
`17`-module inventory comment).

**New fixtures (28) + usage programs (2):** 12 `stdlib_file_*_xmod`; 5
`stdlib_stdin_*_xmod`; 7 `stdlib_net_udp_*_xmod`; 4 `stdlib_stream_*_xmod`; and the R7b
usage programs `stdlib_test/file_stdin_usage` (`std_file` + `std_stdin`) and
`stdlib_test/file_stream_usage` (`std_file` + `std_stream` + `std.async`; per-call
`max-suspends 3`). `scripts/stdlib/expected_dirs.txt` pins the discovered set
**96 -> 98** (68 at the Plan A hardening closeout; +28 Plan B fixtures +2 usage programs).

| field | value |
|---|---|
| fixed point | `414cccee639bdb61c7a9f1f2ddddb166` (UNMOVED) |
| seed | v29 (archive md5 `910a4d673f0fa95f8473c08e143ceb54`); NOT rotated |
| corpus (`-ffast` dump+gcc classifier) | 800 dirs = **747 OK / 28 GREEN / 25 FAIL / 0 ICE / 0 CRASH** |
| runtime gate | **98/98 PASS** (3x determinism internal) |
| `check_emit_support.sh` | **7/7** byte-identical |
| self-compile `-ffast --dump-c89` | rc=0, 48 `.c` + 48 `.h`, 0 `error[`, 0 PANIC |
| `scripts/closeout/verify_upgraded.sh` | **CLOSEOUT OK** (A1-A5 / B1-B7 / C1) |

**Corpus delta through Plan B.** The Plan A hardening closeout was **770** dirs
(EXPECTED_FAIL v138); the Plan B closeout corpus is **800** (+30: the 28 fixtures + the 2
usage programs). Per-dir class movement on the 770 pre-existing dirs is **ZERO** (no
`sf/src` change, fixed point unmoved); all 30 new dirs classify **OK**. Full report:
`.superpowers/sdd/2026-09-17-std-lib-plan-b-resources-stream/task-5-report.md`.

---

## Plan B Task 4 fix round 1 — async frame-layout residual declared (v138 -> v139 2026-09-18)

Plan B Task 4 review Important finding #1 (declare the latent compiler gap). **Docs/manifest
only — no `sf/src` change; fixed point UNMOVED `414cccee639bdb61c7a9f1f2ddddb166`; corpus dirs
unchanged.** A suspending function that contains a `while` loop **and** returns `!?[]u8` (an
error union whose payload is an optional slice) trips the P2/P3 async frame-layout size guard at
`sf/src/async_frame_layout.zig:659` with the exact diagnostic
`panic: async frame layout exceeds authoritative frame size` (the compiler traps during
`-ffast --dump-c89`; no `.c` is emitted).

Minimal trigger shape:
`fn f(lr: *T) FileError!?[]u8 { while (true) { ...; _ = @asyncSuspend(null); } return null; }`.
Bisection on the seed-built compiler (`414cccee`): `loop + !usize` is OK, `non-loop + !?[]u8` is
OK, `loop + !?[]u8` panics — the trigger is the **loop + error-union + optional-slice return** in
one suspending function. `std_stream.readFileLineAsync` avoids it by keeping the loop on an internal
scalar-status helper (`awaitLine` returning `!u8`) and the `!?[]u8` return loop-free. Full report:
`.superpowers/sdd/2026-09-17-std-lib-plan-b-resources-stream/task-4-report.md`.

**Recorded follow-up (not this round).** Pin the shape with an I/F fixture pair
(`async_frame_loop_eu_opt_slice_xmod` + classifier row) and fix the P2/P3 layout. Fixing the
compiler moves the fixed point and needs operator authorization, so no fixture/compiler change is
made here.

---

## Plan A test-hardening closeout — runtime gate + probes + stress tier (v137 -> v138 2026-09-18)

Plan A test-hardening (`docs/superpowers/plans/2026-09-18-plan-A-test-hardening.md`) is
**COMPLETE**. Docs/scripts/fixtures only — **no `sf/src` change**; the self-emission fixed point
is **UNMOVED `414cccee639bdb61c7a9f1f2ddddb166`** and the seed stays **v29** (archive md5
`910a4d673f0fa95f8473c08e143ceb54`). The Plan A std-module runtime behavior is now an automated
gate: `scripts/stdlib/run_fixtures.sh <seed-built-zig1> [<dir>...]` emits (`zig1 -ffast -o`),
gcc-compiles every emitted `.c` with the binding flag-set, links via `build_target.sh linux`,
runs 3x under `timeout 120` from a scratch CWD, and byte-diffs stdout+rc to committed per-fixture
goldens. `scripts/stdlib/verify_stdlib.sh` is the closeout wrapper, wired as **phase C** of
`scripts/closeout/verify_upgraded.sh`, so `CLOSEOUT OK` requires it.

**Golden convention (binding).** Each fixture dir carries `expected.txt` (exact stdout bytes) +
`expected.rc` (exit code). A missing golden is a FAIL (no silent skips);
`scripts/stdlib/expected_dirs.txt` pins the discovered set (68 dirs) so coverage cannot silently
shrink; a fixture that binds TCP ships `ports.txt`. Goldens are runtime-only (stdout+rc),
captured only after the observed output matched the fixture's documented GREEN contract, and
re-captured only on an intentional behavior change.

**New fixtures (7):**

| fixture | kind | contract |
|---|---|---|
| `stdlib_bits_extract_trap_xmod` | expected-failure probe | `extract(0, 28, 8)`, off+len>32 -> SIGTRAP, rc **133**, empty stdout |
| `stdlib_bits_insert_trap_xmod` | expected-failure probe | `insert(0, 0, 28, 8)`, off+len>32 -> SIGTRAP, rc **133**, empty stdout |
| `stdlib_os_exit_xmod` | expected-failure probe | `std.os.exit(42)` -> rc **42**, empty stdout |
| `stdlib_bits_stress_xmod` | stress | 24-row extract/insert field sweep + rotl/rotr inverse (n=0/31/32/33) + mask 0..32; stdout `bits stress ok` |
| `stdlib_buf_stress_xmod` | stress | 1000 appends through every doubling + all 6 encoders byte-decoded + exact-fit arena max; stdout `buf stress ok` |
| `stdlib_str_stress_xmod` | stress | join/split identity over adversarial separators/empties/long inputs + replace aliasing + trim; stdout `str stress ok` |
| `stdlib_debug_stress_xmod` | stress | 32-frame backtrace + 3 writeCoreDump contexts + logInt i32 boundaries; 5 logInt lines + `debug stress ok` |

**Gates (seed-built fixed-point compiler `414cccee`).** Corpus `-ffast` dump+gcc classifier
**770 dirs = 717 OK / 28 GREEN / 25 FAIL / 0 ICE / 0 CRASH** (763 -> 770: the 7 new dirs all
classify OK; every pre-existing dir class-identical). Runtime gate **68/68 PASS** (61 -> 64 -> 68
through Tasks 2/3/4; 3x determinism internal). `scripts/check_emit_support.sh` **7/7**
byte-identical (5 core + 2 conditional preludes). Self-compile `-ffast --dump-c89` rc=0,
48 `.c`, 0 `error[`, 0 PANIC. `scripts/closeout/verify_upgraded.sh` **CLOSEOUT OK**
(A1-A5 / B1-B7 / C1). Seed v29 round-trip re-verified (two-hop closure hop1 == hop2 ==
`414cccee`). Full report:
`.superpowers/sdd/2026-09-18-plan-A-test-hardening/task-5-report.md`.

## Plan A closeout — L0-L2 std-lib foundation landed (v135 -> v136 2026-09-18; re-rotated v136 -> v137 2026-09-18)

Plan A (`docs/superpowers/plans/2026-09-17-std-lib-plan-a-foundation.md`) is **COMPLETE**.
The L0-L2 foundation landed: `std_bits` (L0); `std_os` + `std_os_pal` + the authorized
`std_os_prelude.h` (L1); `std_time` + `std_time_pal` + the authorized `std_time_prelude.h`
(L1); the `std_debug` extension + trap hook (L1, `setTrapHandler` restored to the blueprint
`?fn(*TrapContext) void` by Task 4c); `std_buf` (L2) + `std_debug.backtrace` (the single
documented R3 L1→L2 import); and the `std_str` extension (L2). The two R7b usage programs
(`stdlib_test/bits_buf_str_usage`, `stdlib_test/os_time_usage`) are corpus dirs. This
closeout commit is **docs/seed only — no `sf/src` change**; the self-emission fixed point was
UNMOVED from the Task 6b-F value at the Task 8 closeout (the final-review fix wave then moved
it — see below). The seed is rotated (Plan A moved the fixed point through
the authorized compiler changes) per the QUICK_REF rotation protocol.

**Final-review fix wave + re-rotation (v136 -> v137).** The whole-plan final review
(operator rulings m1323/m1325) authorized the 12-name `std.zig` re-export set, documented the
second R3 exception (`std_debug` -> `std_io`), recorded the fourth authorized compiler change
(the `-ffast` undefined slice/optional/struct-field fix, m1277), and restored the
`int3`/SIGTRAP trap hook with its non-GCC/non-x86 `pal_abort()` fallback. The trap-hook
compiler fix moved the self-emission fixed point `7513a8d5` -> `414cccee`; the seed was
re-rotated **v28 -> v29** at the new fixed point (the v28 archive embedded the pre-fix
`zig_pal.c`).

| field | value |
|---|---|
| fixed point | `414cccee639bdb61c7a9f1f2ddddb166` |
| seed before | v27 (archive md5 `cab32bf6ba4998a2a78de3064a07443e`, fixed point `553a39b42983ce72459698a7aa5817e1`), rotated to v28 at `7513a8d5` (archive `e7bebc14f4b600a7742062ac2ab4c38d`) |
| seed after | v29 (archive md5 `910a4d673f0fa95f8473c08e143ceb54`; archived binary md5 = fixed point `414cccee`) |
| self-emission C | 45 `.c` + 46 `.h` (8739997 bytes) |
| corpus (`-ffast` dump+gcc classifier) | 763 dirs = **710 OK / 28 GREEN / 25 FAIL / 0 ICE / 0 CRASH** |
| EXPECTED_FAIL header | v135 -> v136; v136 -> v137 (final-review re-rotation) |

**Corpus delta through Plan A.** The Task 1 baseline was **728** dirs (EXPECTED_FAIL v130);
the closeout corpus is **763** (+35 dirs): the per-module `stdlib_*` fixtures, the two
`stdlib_test/` usage programs, and the two compiler-defect I/F pins. Per-dir class movement
during Plan A is confined to the tasks' declared flips — `opt_fnptr_extern_xmod` FAIL -> OK
(Task 4b-F) and `undefined_slice_array_xmod` FAIL -> OK (Task 6b-F) — plus the new dirs;
every pre-existing dir is class-identical at closeout (Task 8 changes no `sf/src`, so the
class map cannot move).

**Gates (seed-built fixed-point compiler `414cccee`).** `scripts/check_emit_support.sh`
**7/7** byte-identical (5 core + 2 conditional preludes); `scripts/closeout/verify_upgraded.sh`
**CLOSEOUT OK** (A1-A5 / B1-B7, all goldens byte-identical); self-compile `-ffast --dump-c89`
rc=0, 48 `.c`, 0 `error[`, 0 PANIC; canonical classifier 763 = 710 OK / 28 GREEN / 25 FAIL.
Seed v29 round-trip re-verified (rebuild from the new seed closes hop1 == hop2 == `414cccee`).
Full report: `.superpowers/sdd/2026-09-17-std-lib-plan-a-foundation/task-8-report.md`.

**Known undeclared-fail (recorded, NOT fixed; pending operator ruling).**
`repro/mi_matrix/ptrcast_arity_xmod` classifies **FAIL** but is **not declared in this
manifest**. It is a pre-existing deliberate expected-fail (pins the 1-arg `@ptrCast` ->
`error[3049]` rejection, commit `46cf5e47`, ASYNCTRACK2) that was never added to the
manifest; its "2-arg must compile" line is untestable in the same file. Pre-existing,
out of the current plan scope. No ruling yet.

## Next plan

Plan D hardening complete. The std-lib extension program is COMPLETE.
No successor plan. Program spec: `docs/superpowers/specs/2026-09-17-std-lib-extension-program-design.md`.

---

## Plan A Task 6b-F fix round 1 — nested-struct/tagged-union undefined-field residuals declared (v134 -> v135 2026-09-18)

Task 6b-F fix round 1 (review Important finding: incomplete residual declaration). **Docs/manifest
only — no `sf/src` change; fixed point UNMOVED `7513a8d59a3c317639a055491769a9c5`.** The
struct-element field fallback else (`sf/src/c89_emit.zig:7325-7333`) still emits
`result[_i].field = 0;` for two same-locus element shapes outside the mandated slice/optional set;
both are pre-existing and reproduced pre- and post-fix (declared, NOT fixed this round):

| residual shape | emitted C | gcc (pre- and post-fix) |
|---|---|---|
| `[N]S`, `S` has a nested struct field (`inner: Inner`) | `zT_1[_i].inner = 0;` | **FAIL** `incompatible types when assigning to type 'zT_7E9B6EC7_Inner' from type 'int'` |
| `[N]S`, `S` has a `tagged_union_type` field (`u: U`) | `zT_1[_i].u = 0;` | **FAIL** `incompatible types when assigning to type 'zT_D00C09B0_U' from type 'int'` |

These join the already-declared residuals in the v134 section (error-union element
`[N]!T = undefined`; struct field that is an array of slices/optionals). Full report:
`.superpowers/sdd/2026-09-17-std-lib-plan-a-foundation/task-6b-F-report.md`.

---

## Plan A Task 6b-F — `-ffast` undefined slice-array emission FIXED (v133 -> v134 2026-09-18)

Task 6b-F fixes the compiler defect pinned by Task 6b-I (operator ruling m1277). **Authorized
compiler change; fixed point MOVES `4b1c029de5234ea94dae0e78eac733e8` ->
`7513a8d59a3c317639a055491769a9c5`.**

**Locus + change (`sf/src/c89_emit.zig`, the `.undefined_const` array-fill arm).** Two edits,
both inside the pinned `.undefined_const` arm:
1. the array-element byte-wise fill (the multi-dim/nested path) now also covers `slice_type`
   and `optional_type` element kinds — a 1-D array of slices/optionals is zeroed byte-wise
   (`while (_i < sizeof(result)) { ((unsigned char*)&result)[_i] = 0; _i++; }`) instead of the
   illegal `result[_i] = 0;`;
2. the struct-element field arm gained explicit `slice_type` (`field.ptr = 0; field.len = 0;`)
   and `optional_type` (`field.has_value = 0;`) field paths instead of `field = 0;`.
Scalar/pointer/tagged-union element output is unchanged (verified byte-identical for scalar and
nested-array elements).

**RED -> GREEN (canonical classifier `scripts/corpus/classify`, seed-built compiler).** The
`-ffast` pin flips FAIL -> OK; the off-corpus `-fsafe`/default control stays clean.

| fixture | v133 class | v134 class | emitted C now (fixed point `7513a8d5`) |
|---|---|---|---|
| `undefined_slice_array_xmod` | **FAIL** | **OK** | byte-wise `while (_i < sizeof(zT_1)) { ((unsigned char*)&zT_1)[_i] = 0; _i++; }`; gcc clean, run rc=0, stdout `alpha\|gamma\|5\n` |
| `known_excluded/undefined_slice_array_safe_xmod` | off-corpus (control) | off-corpus (control) | unchanged `zig_poison_fill`; `-ffast`/`-fsafe`/default all rc=0, stdout `alpha\|gamma\|5\n` |

Affected shapes verified (scratch probes, `-ffast` dump+gcc+run): `[N][]const u8` slice element
and `[N]?i32` optional element (both byte-wise), `[N]S` with a slice field (`s.ptr`/`s.len`), and
`[N]S` with an optional field (`o.has_value`) — all FAIL pre-fix, OK + correct stdout post-fix.

**Corpus `-ffast` dump+gcc classifier (761 dirs):**

| | 6b-I `4b1c029d` (v133) | 6b-F `7513a8d5` (v134) | delta |
|---|---|---|---|
| dirs | 761 | 761 | 0 |
| OK | 707 | 708 | +1 |
| GREEN | 28 | 28 | 0 |
| FAIL | 26 | 25 | -1 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir `join` diff = exactly `repro/mi_matrix/undefined_slice_array_xmod` FAIL -> OK; every other
dir class-identical.

**Gates.** 3× `-ffast` emission md5 stable (`main_112EE5B5.c`
`c3e0986e1e95b2b1166d3f1821ad8faf`; all-`.c` concat `e205a5ca2f054704a6752d49e7754aa6`);
`-ffast`/`-fsafe`/default parity (all dump+gcc+link+run rc=0, identical stdout
`alpha\|gamma\|5\n`; `-fsafe`/default use `zig_poison_fill`, `-ffast` the byte-wise fill);
`check_emit_support.sh` **5/5** byte-identical; `verify_upgraded.sh` **CLOSEOUT OK**; self-compile
dump rc=0, 48 `.c`, 0 `error[`, 0 PANIC. Seed NOT re-rotated.

**Residual (declared, tracked).** An `error_union_type` element (`[N]!T = undefined`) still
reaches the scalar else-arm and emits `result[_i] = 0;` (gcc: int -> EU struct) — same root cause,
outside the Task 6b-I measured set (slice/optional/struct), left unfixed. A struct element whose
field is an ARRAY of slices/optionals (`[N]S`, `S` has `[M][]const u8`) also still emits
`result[_i].field[_k] = 0;` (array-field sub-arm); left unfixed. Direct slice/struct locals,
globals, nested arrays, and scalar/pointer elements are unchanged (byte-identical). Full report:
`.superpowers/sdd/2026-09-17-std-lib-plan-a-foundation/task-6b-F-report.md`.

---

## Plan A Task 6b-I — `-ffast` undefined slice-array emission defect pinned (v132 -> v133 2026-09-18)

Task 6b-I investigates the compiler defect found in the Task 6 (`std_str`) review (operator
ruling m1277): under `-ffast`, a 1-D array of slices initialized `undefined` mis-emits its
element fill as a scalar zero, which gcc rejects. **Premise CONFIRMED; no `sf/src` change;
fixed point UNMOVED `4b1c029de5234ea94dae0e78eac733e8`.** Two new dirs: the auto-listed
`-ffast` pin and an off-corpus `-fsafe`/default control.

**Exact emitted C (verbatim), fixed point `4b1c029d`.** Pin
`repro/mi_matrix/undefined_slice_array_xmod`:

`-ffast` (BUG — dump rc=0, 5 `.c`, gcc rc=1):
```c
    zT_4C214FEE_Arr_zT_8F083A69_Sli zT_1;
    ...
    {
    unsigned int _i = 0;
    while (_i < 3) {
        zT_1[_i] = 0;
        _i++;
    }
}
    {
    unsigned int _i = 0;
    while (_i < 3) {
        arr[_i] = zT_1[_i];
        _i++;
    }
}
```
gcc: `main_112EE5B5.c:26:20: error: incompatible types when assigning to type
'zT_8F083A69_Slice_zT_0B42B2F8_u' from type 'int'`.

`-fsafe`/default (CLEAN — dump rc=0, gcc+link rc=0, run rc=0, stdout `alpha|gamma|5\n`):
```c
    zig_poison_fill((void*)&zT_1, (unsigned int)sizeof zT_1);
```
(the A17 lowering routes `undefined` through `poison_init`, `sf/src/c89_emit.zig:7329`;
the default mode is the `-fsafe` path).

**Affected shapes (measured, fixed point `4b1c029d`).** The `.undefined_const` array-element
else-arm (`sf/src/c89_emit.zig:7308-7311`) is reached whenever the 1-D array element kind is
neither `array_type` (multi-dim byte-fill, `:7242-7254`), `tagged_union_type` (`:7267-7270`),
nor `struct_type` (`:7271-7307`):

| shape | emitted fill | gcc |
|---|---|---|
| `[N][]const u8`, `[N][]u8` (slice element) | `zT_1[_i] = 0;` | **FAIL** (int -> slice) |
| `[N]?T` (optional element) | `zT_1[_i] = 0;` | **FAIL** (int -> optional struct) |
| `[N]S` with `S` slice/optional field | `zT_1[_i].s = 0;` (`:7297-7305`) | **FAIL** |
| `[N][M][]const u8` (nested array element) | `((unsigned char*)&zT_1)[_i] = 0;` | OK |
| `[N][*]u8`, `[N]i32` (scalar/pointer element) | `zT_1[_i] = 0;` | OK |
| direct `var s: []const u8 = undefined;` | hoisted temp `= {0}` | OK |
| global `var a: [N][]const u8 = undefined;` | BSS zero | OK |

The `-ffast` defect is confined to 1-D arrays of C-aggregate element kinds the arm does not
special-case; nested arrays are already correct via the byte-wise path.

**Fixtures + classification.** Universe 760 -> **761** (+1; the control under
`known_excluded/` is never enumerated by `scripts/corpus/list_corpus_dirs.sh`).

| fixture | class (pre-fix) | class (post-6b-F contract) | gate |
|---|---|---|---|
| `undefined_slice_array_xmod` | **FAIL** | **OK** | `-ffast` dump rc=0, gcc rejects `zT_1[_i] = 0;`; post-fix gcc clean + stdout `alpha\|gamma\|5\n` |
| `known_excluded/undefined_slice_array_safe_xmod` | off-corpus (control) | off-corpus | `-fsafe`/default dump+gcc+link+run rc=0, stdout `alpha\|gamma\|5\n` pre- and post-fix |

**Corpus `-ffast` dump+gcc classifier (`scripts/corpus/classify`):**

| | pre-6b-I `4b1c029d` (760) | 6b-I `4b1c029d` (761) | delta |
|---|---|---|---|
| dirs | 760 | 761 | +1 |
| OK | 707 | 707 | 0 |
| GREEN | 28 | 28 | 0 |
| FAIL | 25 | 26 | +1 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir `join` diff = exactly `repro/mi_matrix/undefined_slice_array_xmod` (new, FAIL);
every pre-existing dir class-identical (no `sf/src` change).

**Mode-specific gate (explicit).** The corpus classifier is `-ffast`-based, so the pin MUST
classify **FAIL** pre-fix and **OK** post-fix — it does. The `-fsafe`/default control MUST
build/run clean both pre- and post-fix — it does. A `-fsafe`-only defect would be invisible to
the `-ffast` classifier; this one is not, because the defect lives in the `-ffast` path.

**Fix surface for Task 6b-F (no `sf/src` change here).** Locus
`sf/src/c89_emit.zig:7308-7311`, the `.undefined_const` array-element scalar else-arm. Minimal
change: add an `else if (elem_ty.kind == type_mod.TypeKind.slice_type)` arm that zero-fills the
slice's two C fields (`result[_i].ptr = 0; result[_i].len = 0;`) before the final `else`.
General alternative: replace the scalar else with the same byte-wise zero loop the multi-dim
array path uses (`((unsigned char*)&result)[_i] = 0;` over `sizeof(result)`), which is
shape-agnostic and also covers `optional_type` elements. Sibling defect (same round or
declared): the struct-element field arm (`:7297-7305`) emits `result[_i].field = 0;` for
slice/optional fields (blast radius above). Direct slice/struct locals, globals, and nested
arrays are already correct and must stay byte-identical. Full report:
`.superpowers/sdd/2026-09-17-std-lib-plan-a-foundation/task-6b-I-report.md`.

---

## Plan A Task 4b-F — optional-fn-pointer C-emission defect fixed (v131 -> v132 2026-09-17)

Task 4b-F fixes the compiler defect pinned by Task 4b-I (operator ruling m1243): an
`extern "c"` parameter of type `?fn(...)` now materializes the correct function-pointer
argument type instead of an `int`. **Authorized compiler change; fixed point MOVES
`0d3e556036ab4df8eb98899291671d3c` -> `c733d60aa88114118e346ea05d75a2fc`.**

**Locus + change.** `sf/src/type_resolver.zig` `resolveFnSignatures` (`:1528`): the
`fn_start = env.typereg.xt_len` snapshot was taken BEFORE the parameter-type resolution
loop, but resolving a `fn(...)`/`?fn(...)` parameter recurses into the `AstKind.fn_type`
branch and appends the nested fn type's own parameters to the shared `xt_items`
(`type_resolver.zig:1164-1168`), so the recorded `params_start` pointed at the nested
`i32`. The fix buffers every resolved parameter type (`ptypes_buf[64]`), THEN snapshots
`fn_start`, THEN appends the buffer contiguously (mirroring the already-correct
`AstKind.fn_type` path at `:1119-1168`). The resolved-type-table writes are unchanged.
Minimal change, pinned locus only; no other `sf/src` file touched.

**Fixtures declassified (both now OK).** RED → GREEN under the canonical classifier
(`scripts/corpus/classify`, full universe 741):

| fixture | v131 class | v132 class | emitted C now (fixed point `c733d60a`) |
|---|---|---|---|
| `opt_fnptr_extern_xmod` | **FAIL** | **OK** | extern call `take_fn(zT_0)` where `zT_0: zT_430A6DAC_FP_void_int` (`zT_1 = note; zT_2.has_value = 1; zT_2.value = zT_1; zT_3 = zT_2.has_value ? zT_2.value : NULL; zT_0 = zT_3;`); local `?fn` round-trip `localRound(zT_8)` passes the `Opt_65` correctly; gcc clean (only the expected emission-only implicit `take_fn` declaration under the classifier's `-Wno-implicit-function-declaration`). Linked against a conforming C `void take_fn(void (*)(int))`, stdout `1\n` rc=0. |
| `opt_void_extern_xmod` | **OK** (control) | **OK** | unchanged: `zT_6 = zT_7.has_value ? zT_7.value : NULL; take_void(zT_6);` and `take_void((void*)(NULL));` — gcc clean. |

**Corpus class-map delta (pre-fix `0d3e5560` vs post-fix `c733d60a`, 741 dirs):**

| | v131 | v132 | delta |
|---|---|---|---|
| dirs | 741 | 741 | 0 |
| OK | 687 | 688 | +1 |
| GREEN | 28 | 28 | 0 |
| FAIL | 26 | 25 | -1 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir `join` diff = exactly `repro/mi_matrix/opt_fnptr_extern_xmod` FAIL -> OK; every
other dir class-identical (the `?*void` control included).

**Gates.** 3× `-ffast` emission md5 stable (`main_578EE027.c`
`1f55fdfe97b8a98503e88383a88c3cd7`); `-fsafe`/`-ffast` parity (both dump/build/run rc=0,
identical stdout `1\n`; `-fsafe` adds only the expected `pal_trap()`/`zig_poison_fill`
checks); `check_emit_support.sh` **5/5** byte-identical; `verify_upgraded.sh` **CLOSEOUT
OK** (A1-A5/B1-B7, all goldens byte-identical — no closeout program uses a fn-pointer
parameter); self-compile dump rc=0, 0 `error[`, 0 PANIC (48 `.c` + 48 `.h`).
No seed rotation in this task. Full report:
`.superpowers/sdd/2026-09-17-std-lib-plan-a-foundation/task-4b-F-report.md`.

**Residual (declared).** The null payload still renders `NULL` (and a direct `null`
argument to a `?fn` extern parameter renders `(void*)(NULL)`), not the plan's stricter
literal `0`; this is gcc-clean under the project flag set and ABI-identical (all-bits-zero
null pointer), and the `unwrap_optional_abi` `0`-rendering (`c89_emit.zig:8100-8113`)
noted by Task 4b-I is outside the pinned `type_resolver.zig` locus, so it was not applied
here.

---

## Plan A Task 4b-I — optional-fn-pointer C-emission defect pinned (v130 -> v131 2026-09-17)

Task 4b-I investigates the optional-fn-pointer C-emission defect behind the Task 4
`std_debug.setTrapHandler` signature divergence (operator ruling m1243). **No `sf/src`
change; fixed point UNMOVED `0d3e556036ab4df8eb98899291671d3c`.** Two new emission-only
fixtures (auto-listed; the C definitions of `take_fn`/`take_void` live on the C side, so
the gate is gcc compiling the emitted C, not link/run):

| fixture | class | emitted C today (fixed point `0d3e5560`) |
|---|---|---|
| `opt_fnptr_extern_xmod` | **FAIL** | extern call `take_fn(zT_0)` where `zT_0` is an `int` temp (`zT_0 = zT_1;`, `zT_1: void (*)(int)`); the local `?fn` parameter call `localRound(zT_5)` passes an `int` to an `Opt_65` parameter → gcc `error: incompatible type for argument 1 of 'zF_FD3BB730_localRound'`. The bound C prototype must be `void take_fn(void (*)(int))` (null = `0`). |
| `opt_void_extern_xmod` | **OK** (control) | extern call ABI-unwraps correctly: `zT_6 = zT_7.has_value ? zT_7.value : NULL; take_void(zT_6);` and `take_void((void*)(NULL));` — gcc clean. Confirms `?*void` lowers correctly. |

**Root cause (pinned).** `sf/src/type_resolver.zig` `resolveFnSignatures` (`:1528`)
snapshots `fn_start = env.typereg.xt_len` BEFORE resolving the parameter types, but
resolving a `fn(...)`/`?fn(...)` parameter recursively appends the nested fn type's own
parameters to the shared `xt_items` (`type_resolver.zig:1164-1168`). The recorded
`params_start` therefore points at the nested fn's first parameter (`i32`) instead of the
function's own parameter, so `call_arg_types` (`semantic_analyzer.zig:1504`) types the
call-argument temp as `i32` and the extern call passes an `int` where a function pointer is
required. The same wrong `params_start` drives indirect-call parameter typing
(`semantic_analyzer.zig:1555`) and fn-type compatibility (`type_registry.zig:1182`). Fix
surface for Task 4b-F: resolve all parameter types into a buffer, THEN snapshot
`params_start` and append to `xt` (mirror the `AstKind.fn_type` path at
`type_resolver.zig:1119-1168`); fixed point MOVES (authorized). Corpus 739 → **741**
(+1 FAIL, +1 OK; the only tree change is the two new dirs). Full report:
`.superpowers/sdd/2026-09-17-std-lib-plan-a-foundation/task-4b-I-report.md`.

---

## Track-4 Task 9-M-F — AST index-side write-through spill (v129 -> v130 2026-09-17)

Task 9-M-F replaces the two plain `extra_children` / `extra_ranges` arrays with two
`AstValuePool` write-through block pools (EC 1024 elems/block, ER 512 elems/block,
4096 B blocks, 1 resident head + 8-block read cache each), spilled under the new
`SpillId.s_extra` (LAST slot; `SPILL_COUNT` 5 -> 6; `-s0`..`-s5` Disk, `-s6` all RAM;
deactivation order AST -> LIR -> HASH -> RES -> SIDE -> EXTRA). The per-element getter
(`astStoreNodeExtraChildCount` / `astStoreNodeExtraChildAt`) replaces the removed
slice-returning accessors (no shared transient buffer: 7 direct-retaining + ~47
recursive-retaining call sites, all now value-safe). Three new fixtures pin
block-boundary crossing and the packed-range high half. Fixed point MOVED
`b981bc80290bfde5ed5383cd0927e124` -> `dd43612912662fc06a25a10eb194c665` (hop1 == hop2);
seed **v23 -> v24**. Corpus 728 dirs **class-identical** (675 OK / 28 GREEN / 25 FAIL);
`-s0` self-compile `pool=` 19,653 K -> 16,622 K. Runtime stdout md5 stable x3.

| fixture | GREEN (fixed point `dd436129`) |
|---|---|
| `ec_xmod_crossmodule_xmod` | dump rc=0, 6 `.c`, gcc-clean, link+run rc=0, stdout `76` (md5 `fbd7939d…`); module_root / fn_call / block / struct_decl / struct_init extra children across the module boundary |
| `ec_deep_nested_xmod` | dump rc=0, 5 `.c`, gcc-clean, link+run rc=0, stdout `1539` (md5 `17e23e50…`); >1024 EC / >512 ER, crosses both pool block boundaries |
| `ec_packed_range_xmod` | dump rc=0, 5 `.c`, gcc-clean, link+run rc=0, stdout `17` (md5 `70efdf2e…`); late range `start` = 65,600 > 2^16 pins the packed-range u32 high half |

---

## Track-4 Task 8-F — suspending `export fn` synthesized driver landed (v128 -> v129 2026-09-17)

Task 8-F generalizes the synthesized synchronous driver to
`isDriverTarget = isRootMain || lf.is_export` (`sf/src/async_state_machine.zig`), with
`LirFunction.is_export` set from the AST `fn_decl` bit3 `0x08` (`sf/src/lower.zig`,
`sf/src/lir.zig`, `sf/src/lir_stream.zig`). The driver frame-inits through the shared
`asyncEmitFrameInit` helper (also called by the `@asyncInit` builtin lowering), and a
value-returning driver target allocates a local result buffer, points the hidden
`ASYNC_FIELD_RESULT` slot at it, and returns the value stored by the step's terminal
`.ret value` path. `ASYNC_FIELD_RESULT` is now added when
`is_awaited || is_driver_target` in both P2 (`async_analysis.zig`) and P3
(`async_frame_layout.zig`).

The two Task 8-I fixtures flip RED -> GREEN (the absent source-named external symbol is
now emitted; runtime stdout unchanged):

| fixture | GREEN (fixed point `9b3075b1`) |
|---|---|
| `async_export_fn_xmod` | dump/gcc/link rc=0, 5 `.c`, run rc=0, stdout `6\n`; `int bump(int n)` source-named definition present; driver stores `&__az_result` into the frame result slot and `return`s the loaded value |
| `async_export_fn_void_xmod` | dump/gcc/link rc=0, 5 `.c`, run rc=0, stdout `5\n`; `void notify(int n)` source-named definition present; driver ends `return;` |

**Emitted-C assertion (operator ruling S37).** For `bump` the emitted driver must contain
both the source-named external symbol and the result-buffer store/load value path; the
fixture runtime stdout does not exercise it. Evidence in the Task 8-F report.

**Corpus `-ffast` dump+gcc classifier (`scripts/corpus/classify`):**

| | v128 `18e0de5c` | v129 `9b3075b1` | delta |
|---|---|---|---|
| dirs | 725 | 725 | 0 |
| OK | 672 | 672 | 0 |
| GREEN | 28 | 28 | 0 |
| FAIL | 25 | 25 | 0 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir class map is byte-identical to v128 (zero class movement): the fixtures compile
clean both before and after (the RED/GREEN distinction is the source-symbol gate, not the
corpus compile class). No new diagnostic code. Fixed point MOVED to
`9b3075b105ff544f3541d5a621d00d40`; seed rotated (v22).

---

## Track-4 Task 8-I — suspending `export fn` synthesized-driver gap (v127 -> v128 2026-09-17)

A suspending `export fn` keeps **no synchronous export entry**: the async transform
replaces its LIR with the `__Z98Step_<f>` step and never streams the original
(`sf/src/main.zig:770-779`), and only root `pub fn main` is a driver target
(`sf/src/async_state_machine.zig:597` `isRootMain` requires module 0 + `is_pub` +
`"main"`). The emitted C therefore has no source-named external symbol for the
`export fn` — only the temp-mangled step. Task 8-F will generalize the driver to
`isDriverTarget = isRootMain || is_export`; Task 8-I pins the RED with two new
auto-listed fixtures and makes **no `sf/src` change** (fixed point UNMOVED
`18e0de5cf71f4fe0fbf5c560ab24e624`).

| fixture | RED today (fixed point `18e0de5c`) | GREEN contract (Task 8-F) |
|---|---|---|
| `async_export_fn_xmod` | dump/gcc/link rc=0, 5 `.c`, run rc=0, stdout `6\n`; `nm prog` shows only `T zF_<hash>___Z98Step_bump` and no `bump` definition (`grep -E '\bbump\b' main_*.c` = no match) | `bump` non-static source-named definition present; stdout `6\n` (value `n+1` round-trips) |
| `async_export_fn_void_xmod` | dump/gcc/link rc=0, 5 `.c`, run rc=0, stdout `5\n`; only `T zF_<hash>___Z98Step_notify`, no `notify` definition | `notify` non-static source-named void definition present; stdout `5\n` |

Note: because `bump`/`notify` are suspending, `main`'s direct call is an implicit
await, so the awaited value already round-trips *within* main and the runtime
stdout is identical in RED and GREEN — the RED is the absent source-named external
symbol (the missing sync entry), not a runtime-output difference. The corpus
`-ffast` compile classifier therefore buckets both new dirs as `OK` (they compile
clean); the RED is the symbol gate, recorded here.

**Corpus `-ffast` dump+gcc classifier (`scripts/corpus/classify`):**

| | v127 `18e0de5c` | v128 `18e0de5c` | delta |
|---|---|---|---|
| dirs | 723 | 725 | +2 |
| OK | 670 | 672 | +2 |
| GREEN | 28 | 28 | 0 |
| FAIL | 25 | 25 | 0 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir movement = exactly the two new dirs (both compile-clean -> OK); no
`sf/src` change, so no other class movement. No new diagnostic code.

---

## Final whole-branch review fix — `addTask` clears `cancel_requested` + spec scope (v126 -> v127 2026-09-17)

The final whole-branch review found that `addTask`'s idempotent reset never cleared
`t.cancel_requested`. `cancel_requested` is only ever set true (`cancel`/`cancelAll`), so a
re-added **cancelled** `*Task` was immediately re-cancelled by the next `tick` and never
ran — contradicting the doc comment and the landed declaration, which advertise "settled
(done/**cancelled**) -> reset in place to `ready`". The operator ruled to fix it in the same
round as the spec scope reconciliation.

**Changes:** `sf/src/std_async.zig` `addTask` now clears `t.cancel_requested = false` on BOTH
the reset-in-place path (`:148`) and the append path (`:156`); the `addTask` doc comment
states it (`:137`). New auto-listed fixture
`stdlib_async_addtask_restart_cancel_xmod` pins restart-after-cancel on both paths.
`docs/superpowers/specs/2026-09-13-coroutine-integration-design.md` §1/§2/§3.3/§8 now state
the true Track-4 `sf/src` scope (three primary exceptions + the operator-ruled compiler-gap
fix series + the `std.async` additions) instead of the false "example source only ... no
other `sf/src` module" claim. `sf/src/std_async.zig` is not in `main.zig`'s import graph, so
the compiler fixed point is UNMOVED; the seed is NOT re-rotated (v20 stays; a
`std.async`-only change leaves the archive's `lib/std_async.zig` one revision behind
`sf/src`, declared below).

| fixture | RED (fixed point `18e0de5c`, pre-fix lib) | GREEN (post-fix lib) |
|---|---|---|
| `stdlib_async_addtask_restart_cancel_xmod` | dump/gcc/link rc=0, 6 `.c`; run rc=133 (SIGTRAP), stdout `1 1 1 2 1 1 4 1 1 1 1 4 1 4 1 1 2 1 0 4`, panic `restart-after-cancel re-cancelled a reset task` | run rc=0, stdout `1 1 1 2 1 1 4 1 1 0 2 2 3 3 1 1 2 0 1 3` |

Phase A (reset-in-place) restarts a cancelled registered task to completion; Phase B
(append) restarts a task cancelled before registration. All other 22 `stdlib_async_*`
fixtures re-run unchanged (the two intentional-panic fixtures stay rc=133).

**Corpus `-ffast` dump+gcc classifier (`scripts/corpus/classify`):**

| | v126 `18e0de5c` | v127 `18e0de5c` | delta |
|---|---|---|---|
| dirs | 722 | 723 | +1 |
| OK | 669 | 670 | +1 |
| GREEN | 28 | 28 | 0 |
| FAIL | 25 | 25 | 0 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir movement = exactly the new `stdlib_async_addtask_restart_cancel_xmod` dir
(compile-clean -> OK); the pre-fix and post-fix class maps are byte-identical (the fix is
runtime-only for the compile classifier). No new diagnostic code.

**Fixed point UNMOVED `18e0de5cf71f4fe0fbf5c560ab24e624`** (post-edit seed-built closure
hop1 == hop2 == `18e0de5c…`): `check_emit_support.sh` 5/5; self-compile 48 `.c`, rc=0, 0
`[3000]`; 4-MD5 runtime byte-identical (gol `fcbf7e7c…` / lisp `8dc783a3…` / json
`8bda3d5a…` / mud `66c8f0ab…` + client `93147d0f…`); four goldens + `CLOSEOUT OK`. Seed NOT
re-rotated (operator ruling).

---

## Track-4 Task 5a-F fix round 1 — drop `waitFor` on the mud_server disconnect path (v125 -> v126 2026-09-17)

The Task 5a-F review found the blocking-tick fix incomplete: the quit/disconnect path still
called `std.async.waitFor(&client_sched, client_task_ptrs[i])`. The direct `@asyncResume` never
updates `Task.state`, so `waitFor` saw the task unsettled and ran `tick`, which resumes EVERY
registered non-done task — including idle clients blocked in `recv` — so a disconnect by one
client while another is idle still stalled `main`. Operator ruling: **drop the `waitFor` call on
this hot completion path**; the `@asyncResume` null return IS the completion signal, so the slot
is freed directly (close socket, `is_active=false`, `state=.done`, `removeTask`) with no
`waitFor`/`tick`. `std.async.waitFor` itself stays (the correct non-suspending drive for a
genuinely single-task wait).

**Changes:** `examples/z98/mud_server/main.zig` (drop `waitFor` + comment);
`docs/superpowers/specs/2026-09-13-coroutine-integration-design.md` §1/§3.1/§3.2 + the
consumed-surface lists (`removeTask`); the plan Task 5 Step 3 body + Amendment 5;
`repro/mi_matrix/stdlib_async_blocking_tick_two_xmod/main.zig` re-characterized to model the
disconnect-while-peer-idle path. No `sf/src` change.

| fixture | RED (pre-fix `waitFor` drive) | GREEN (corrected drive) |
|---|---|---|
| `stdlib_async_blocking_tick_two_xmod` | run rc=142 (SIGALRM), stdout `accepted 2` (idle peer B resumed by `waitFor`->`tick` and blocks in `recv`) | run rc=0, stdout `accepted 2` `ok`; A resumed once (EOF), B never resumed |
| `stdlib_async_blocking_tick_xmod` | (unchanged) pre-5a-F trailing-tick drive: rc=142 | rc=0, `accepted` `ok` |
| `stdlib_async_addtask_reuse_xmod` | (unchanged) rc=133 | rc=0, `1 1 1 1 1 1 1 2` |
| `stdlib_async_removetask_xmod` | (unchanged) dump rc=2, `error[3042]` | rc=0, `1 1 0 0 1 1 0 0 1 1 1` |
| `stdlib_async_removetask_noop_xmod` | (unchanged) dump rc=2, `error[3042]` | rc=0, `0 1 0 0 0` |
| `stdlib_async_addtask_single_xmod` (control) | GREEN | GREEN `1 1 3 3` |

**Corpus `-ffast` dump+gcc classifier:** v126 = 722 = 669 OK / 28 GREEN / 25 FAIL; the per-dir
map is IDENTICAL to v125 (the two-client fixture source change is class-neutral; no `sf/src`
change).

**Fixed point UNMOVED `18e0de5cf71f4fe0fbf5c560ab24e624`** (hop2 == hop3). `check_emit_support`
5/5; self-compile 48 `.c`, rc=0, 0 `[3000]`; 4-MD5 runtime byte-identical (gol `fcbf7e7c…` /
lisp `8dc783a3…` / json `8bda3d5a…` / mud `66c8f0ab…` + client `93147d0f…`); `CLOSEOUT OK`.
Seed rotation stays at Task 6.

---

## Track-4 Task 5a-F (F) — idempotent addTask + removeTask + readiness-gated mud_server drive LANDED (v124 -> v125 2026-09-17)

`sf/src/std_async.zig` gained the two operator-ruled primitives and
`examples/z98/mud_server/main.zig` dropped the blocking trailing `tick` (readiness-gated
drive) and now retires finished tasks with `removeTask`. All six fixtures are GREEN; the
corpus delta is exactly the 2 `removeTask` dirs FAIL -> OK.

**Primitives (`sf/src/std_async.zig`):**
- `addTask(s, t)` is IDEMPOTENT: it scans the list; an already-registered `t` is never
  appended again — if `t` is settled (done/cancelled) it is reset in place to `ready`
  (`has_waiting_on=false`) and `true` is returned; if `t` is active it is left untouched and
  `false` is returned; otherwise `t` is appended (capacity permitting) as before.
- `removeTask(s, t)` retires `t`: compacts the tail over the matching entry, decrements
  `count`, keeps `current` in range; no-op when `t` is not registered (never added or already
  removed). Valid from a non-suspending context; `t`'s own state is unchanged.

**mud_server drive (`examples/z98/mud_server/main.zig`):** the trailing
`std.async.tick(&client_sched)` is DELETED (readiness-gated drive: only select-ready fds are
resumed; level-triggered `select` re-reports buffered data next iteration) and the
completed-slot path calls `std.async.removeTask(&client_sched, client_task_ptrs[i])` after
`state=.done`.

| fixture | RED (fixed point `18e0de5c`) | GREEN (Task 5a-F) |
|---|---|---|
| `stdlib_async_addtask_reuse_xmod` | dump/gcc/link rc=0, 6 `.c`; run rc=133 (SIGTRAP), stdout `1 1 1 2 2 2 0 2`, panic `addTask registered the same *Task twice` | run rc=0, stdout `1 1 1 1 1 1 1 2` |
| `stdlib_async_removetask_xmod` | dump rc=2, 0 `.c`, `error[3042]` (primitive absent) | dump/gcc/link rc=0, 6 `.c`, run rc=0, stdout `1 1 0 0 1 1 0 0 1 1 1` |
| `stdlib_async_removetask_noop_xmod` | dump rc=2, 0 `.c`, `error[3042]` | dump/gcc/link rc=0, 6 `.c`, run rc=0, stdout `0 1 0 0 0` |
| `stdlib_async_blocking_tick_xmod` | pre-5a-F drive: run rc=142 (SIGALRM), stdout `accepted` | readiness-gated drive: run rc=0, stdout `accepted` `ok` |
| `stdlib_async_blocking_tick_two_xmod` | pre-5a-F drive: run rc=142 (SIGALRM), stdout `accepted 2` | readiness-gated drive: run rc=0, stdout `accepted 2` `ok` |
| `stdlib_async_addtask_single_xmod` (control) | GREEN today, stdout `1 1 3 3` | stays GREEN |

All GREEN rows re-run 3x deterministic. The two blocking fixtures were updated to the
readiness-gated drive; their RED is the pre-5a-F committed fixture source run under the new
compiler (rc=142).

**Corpus `-ffast` dump+gcc classifier (`scripts/corpus/classify`):**

| | 5a-I `18e0de5c` (v124) | 5a-F `18e0de5c` (v125) | delta |
|---|---|---|---|
| dirs | 722 | 722 | 0 |
| OK | 667 | 669 | +2 |
| GREEN | 28 | 28 | 0 |
| FAIL | 27 | 25 | -2 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir movement = exactly the 2 `removeTask` dirs FAIL -> OK; every other dir is
class-identical.

**Fixed point UNMOVED `18e0de5cf71f4fe0fbf5c560ab24e624`** (seed-built moving point hop1
`c963a76c…`, hop2 == hop3 == `18e0de5c…`): `std_async.zig` is not in `sf/src/main.zig`'s
import graph (Task 0b/4c precedent). `check_emit_support.sh` 5/5; self-compile 48 `.c`,
rc=0, 0 `[3000]`; 4-MD5 runtime byte-identical (gol `fcbf7e7c…` / lisp `8dc783a3…` / json
`8bda3d5a…` / mud `66c8f0ab…` + client `93147d0f…`); `CLOSEOUT OK`. Seed rotation stays at
Task 6.

---

## Track-4 Task 5a-I fix round 1 — `removeTask` fixtures (operator ruling) (v123 -> v124 2026-09-17)

Operator ruling on the Task 5a-I Q2/Q5 concerns: hazard (1) is fixed by **two** `std.async`
primitives — an **idempotent `addTask`** (re-adding an already-registered `*Task` is a
no-op) plus a new **`removeTask(s, t)`** — with one fixture per primitive. This round adds
the `removeTask` half (the idempotent-`addTask` half is `stdlib_async_addtask_reuse_xmod`,
v123). No `sf/src` change in this round (pins only).

**`removeTask` contract pinned:** after `removeTask(s, t)`, `t` is no longer registered
(`s.count` drops; a subsequent `tick` does not resume it); a later `addTask(s, t)` of the
same task succeeds and the slot is reusable; `removeTask` of an already-removed or
never-added task is a no-op (`count` unchanged).

| fixture | shape | RED today (fixed point `18e0de5c`) | GREEN contract (Task 5a-F) |
|---|---|---|---|
| `stdlib_async_removetask_xmod` | add `t0`; remove `t0`; tick; re-add `t0`; remove twice; remove never-added `t1`; add `t1`; tick | dump rc=2, **0 `.c`**, `error[3042]` non-value base expression in field access (`removeTask` does not exist) + `warning[3023]` | dump/gcc/link/run rc=0, 6 `.c`, stdout `1 1 0 0 1 1 0 0 1 1 1` (MEASURED with a scratch `removeTask`) |
| `stdlib_async_removetask_noop_xmod` | remove on an empty scheduler; remove the same task twice; remove a never-added task | dump rc=2, **0 `.c`**, `error[3042]` + `warning[3023]` | dump/gcc/link/run rc=0, 6 `.c`, stdout `0 1 0 0 0` (no-op leaves `count` at 0; MEASURED) |

**Corpus `-ffast` dump+gcc classifier (`scripts/corpus/classify`):**

| | 5a-I `18e0de5c` (v123) | 5a-I fix round 1 `18e0de5c` (v124) | delta |
|---|---|---|---|
| dirs | 720 | 722 | +2 |
| OK | 667 | 667 | 0 |
| GREEN | 28 | 28 | 0 |
| FAIL | 25 | 27 | +2 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir movement = exactly the 2 new `removeTask` dirs (compile-RED → FAIL, the intended
class for a not-yet-existing primitive); every pre-existing dir is class-identical. No new
diagnostic code (the RED uses the pre-existing `error[3042]`/`warning[3023]`).

**Fixed point UNMOVED `18e0de5cf71f4fe0fbf5c560ab24e624`** (operator-ruled): a
`std_async.zig`-only change is not in `sf/src/main.zig`'s import graph (Task 0b/4c
precedent), so it leaves the compiler fixed point UNMOVED; only the emitted
`lib/std_async.zig` changes (seed rotation at Task 6).

---

## Track-4 Task 5a-I (I) — pinned RED: `mud_server` duplicate addTask on slot reuse + blocking trailing tick (v122 -> v123 2026-09-17)

Task 5a-I investigates the two Important, plan-mandated Task 5 review findings and pins
them with fixtures. **No `sf/src` change and no example change in this task** — the REDs
below are the contract Task 5a-F must turn GREEN. The four new fixture dirs are
compile-clean (dump rc=0, gcc rc=0, link rc=0), so each classifies **OK**; the RED is
RUNTIME-only and lives here as documented evidence.

**Finding (1) — duplicate scheduler registration on slot reuse.** `addTask`
(`sf/src/std_async.zig:135-142`) appends unconditionally and nothing removes a task when
`mud_server` frees a slot (`state=.done`, `examples/z98/mud_server/main.zig:181-190`), so a
reconnecting client re-adds the SAME `*Task`: the list holds the pointer twice, `count`
grows one per reconnect, `tick` resumes that task once per duplicate entry, and at
capacity 10 `addTask` silently returns false. Fix locus for 5a-F: make `addTask`
idempotent (reset a settled task in place) or add a `removeTask`/reset primitive —
`sf/src/std_async.zig` is NOT in `sf/src/main.zig`'s import graph, so this does **not**
move the compiler fixed point (Task 4c-F precedent).

**Finding (2) — blocking trailing `tick`.** Accepted sockets are blocking (never
`O_NONBLOCK`, `sf/src/std_net.zig:145-155`); the trailing `std.async.tick`
(`examples/z98/mud_server/main.zig:192`) resumes every non-done task, so resuming an idle
client blocks `main` in `recv`. Fix locus for 5a-F: readiness-gated drive (drop the
trailing `tick`, resume only select-ready fds); `O_NONBLOCK` alone is insufficient because
`clientCoroutine` treats `n <= 0` as disconnect. Examples-only, fixed point UNMOVED.

| fixture | shape | RED today (fixed point `18e0de5c`) | GREEN contract (Task 5a-F) |
|---|---|---|---|
| `stdlib_async_addtask_reuse_xmod` | std.async: add `t0`, mark done, re-add `t0`, tick, then add `t1` at capacity 2 | dump/gcc/link rc=0, 6 `.c`; run rc=133 (SIGTRAP), stdout `1 1 1 2 2 2 0 2`, stderr `panic: … addTask registered the same *Task twice` (duplicate entry; count 1→2; one tick resumes `t0` twice; `t1` rejected at capacity) | idempotent `addTask`: stdout `1 1 1 1 1 1 1 2`, run rc=0 (no duplicate; `count` stays 1; one resume; `t1` admitted) — MEASURED with a scratch `addTask` guard |
| `stdlib_async_addtask_single_xmod` | std.async control: one task, registered once, no reuse | **GREEN today**: dump/gcc/link/run rc=0, stdout `1 1 3 3` | stays GREEN (canonical single-client lifecycle) |
| `stdlib_async_blocking_tick_xmod` | real socket: one client sends one line then idles; select → direct `@asyncResume` → trailing `tick`; `alarm(2)` | dump/gcc/link rc=0, 7 `.c`; run rc=142 (SIGALRM), stdout `accepted` (trailing `tick` blocked in `recv`) | readiness-gated drive (no trailing `tick`): stdout `accepted` `ok`, run rc=0 — MEASURED |
| `stdlib_async_blocking_tick_two_xmod` | real sockets: idle client in slot 0, active client in slot 1; same drive | dump/gcc/link rc=0, 7 `.c`; run rc=142 (SIGALRM), stdout `accepted 2` (idle client stalls `main`) | readiness-gated drive: stdout `accepted 2` `ok`, run rc=0 |

The canonical single-client path is the unchanged control: `examples/z98/mud_server`
rebuilt with the same compiler and driven by `demo/session.sh` is **byte-identical** to
both goldens (server stdout `66c8f0abb926cca7baf9a0d1692ab318`, client bytes
`93147d0f0bbd983a9d844fea8b7a6fa7`).

**Corpus `-ffast` dump+gcc classifier (`scripts/corpus/classify`):**

| | 5a-I baseline `18e0de5c` (v122) | 5a-I `18e0de5c` (v123) | delta |
|---|---|---|---|
| dirs | 716 | 720 | +4 |
| OK | 663 | 667 | +4 |
| GREEN | 28 | 28 | 0 |
| FAIL | 25 | 25 | 0 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir movement = exactly the 4 new dirs (all OK); every pre-existing dir is
class-identical (the only tree change is the 4 new dirs, and the compiler is the canonical
fixed point). No new diagnostic code (the runtime REDs emit no compiler diagnostic).

**Fixed point UNMOVED `18e0de5cf71f4fe0fbf5c560ab24e624`** (seed-built moving point hop1
`c963a76c…`, hop2 == hop3 == `18e0de5c…`): no `sf/src` change. Seed rotation stays at
Task 6.

---

## Track-4 Task 4c-F (F) — `std.async.waitFor` non-suspending drive primitive LANDED (v121 -> v122 2026-09-17)

Task 4c-F adds the operator-ruled (S33) non-suspending drive primitive
`pub fn waitFor(s: *Scheduler, t: *Task) FrameError!void` to
`sf/src/std_async.zig` (inserted after `waitAll`, `:204-221`): a plain `tick`
loop that drives the scheduler until `t` is settled (done/cancelled), returns
`error.OutOfFrame` when a resumed task's pool overflowed (`FrameError` =
`error{OutOfFrame}` only), and `@panic`s if `t` is neither registered nor
already settled (the Q3 hang guard). It does NOT suspend and needs no caller
frame, so it is valid from any non-suspending context (main, `export fn`, a
plain helper). `awaitTask` is UNCHANGED (coroutine-internal). The spec
`docs/superpowers/specs/2026-09-13-coroutine-integration-design.md`
§1/§2/§3.1/§3.2/§4/§8 now document `FrameError` + `waitFor` and list Task 4c as
the third authorized `sf/src` exception.

**RED -> GREEN** (`-ffast --dump-c89`, gcc `-m32 -std=c89 -O0 -Wall …`, link
`build_target.sh linux`, `timeout 120`; RED = pre-change lib, GREEN =
seed-built `/tmp/t4cF_build/zig1_5_clean`):

| fixture | RED (waitFor absent) | GREEN (Task 4c-F) |
|---|---|---|
| `stdlib_async_waitfor_xmod` | rc=2, 0 `.c`, `error[3042]` | dump/link/run rc=0, stdout `10` `3` |
| `stdlib_async_waitfor_cancel_xmod` | rc=2, 0 `.c`, `error[3042]` | rc=0, stdout `0` `4` |
| `stdlib_async_waitfor_settled_xmod` | rc=2, 0 `.c`, `error[3042]` | rc=0, stdout `0` `3` |
| `stdlib_async_waitfor_oom_xmod` | rc=2, 0 `.c`, `error[3042]` | rc=0, stdout `1` `1` `1` |
| `stdlib_async_waitfor_helper_xmod` | rc=2, 0 `.c`, `error[3042]` | rc=0, stdout `10` `3` |
| `stdlib_async_waitfor_dep_xmod` | rc=2, 0 `.c`, `error[3042]` | rc=0, stdout `10` `20` `3` |
| `stdlib_async_waitfor_unregistered_xmod` | rc=2, 0 `.c`, `error[3042]` | rc=0, run rc=133, panic `std.async: waitFor called with an unregistered task` |
| `stdlib_async_await_nonctx_xmod` (extended) | (already OK) | rc=0, run rc=133, stdout `10` `20`, panic `awaitTask called from a non-suspending context` |

**Corpus `-ffast` dump+gcc classifier (`scripts/corpus/classify`), universe
716 (unchanged):**

| | 4c-I `18e0de5c` (v121) | 4c-F `18e0de5c` (v122) | delta |
|---|---|---|---|
| dirs | 716 | 716 | 0 |
| OK | 656 | 663 | +7 |
| GREEN | 28 | 28 | 0 |
| FAIL | 32 | 25 | -7 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir movement = **exactly** the 7 `stdlib_async_waitfor_*` dirs (FAIL -> OK);
`stdlib_async_await_nonctx_xmod` stays OK and all other 708 dirs are
class-identical. No new diagnostic code (the RED used the pre-existing
`error[3042]`/`warning[3023]`).

**Fixed point UNMOVED `18e0de5cf71f4fe0fbf5c560ab24e624`** (seed-built moving
point hop1 `c963a76c…`, hop2 == hop3 == `18e0de5c…`): `std_async.zig` is not in
`sf/src/main.zig`'s import graph (the Task 0b precedent), so the compiler
self-emission is byte-identical. Seed rotation stays at Task 6.

**Gates:** `check_emit_support.sh` 5/5 byte-identical; self-compile closure
48 `.c` / 0 `error[3000]` / 0 errors / 0 PANIC; four goldens byte-identical
(rogue boot `3fb6709e…` 221 B, rogue move `b3c5b0e1…` 31071 B, mud stdout
`66c8f0ab…` 75 B, mud client `93147d0f…` 158 B); 4-MD5 **runtime** byte-identical
(gol `fcbf7e7c…`, lisp `8dc783a3…`, json `8bda3d5a…`, mud as above);
`verify_upgraded.sh` -> `CLOSEOUT OK`.

**Declared (not a gate):** adding `waitFor` to the `std`-re-exported
`std_async.zig` changes the emitted C of any program importing `std` (an extra
`ZIG_FNPTR_…` typedef + module ordering) even though `std_async` itself is not
emitted; §3.3 explicitly does NOT gate emitted C, and the runtime bytes are
unchanged. The `docs/sf/QUICK_REF.md` emission-4-MD5 table is path-derived and
was already not reproducible from an arbitrary build dir; it is not re-baselined
here (runtime 4-MD5 is the plan's gate). Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-4c-report.md`.

## Track-4 Task 4c-I (I) — `std.async.waitFor` primitive pinned (v119 -> v120; classifier fix round 1 v121 2026-09-16)

Task 4c-I pins the operator-ruled (S33) `std.async.waitFor` primitive: a
non-suspending drive primitive `pub fn waitFor(s: *Scheduler, t: *Task)
FrameError!void` that ticks `s` until `t` is settled. The landed `awaitTask`
only marks the CURRENTLY-RUNNING task waiting on `t` and `@panic`s when
`!s.in_task`, so `main` (not a task) cannot use it. **No `sf/src` change; fixed
point `18e0de5cf71f4fe0fbf5c560ab24e624` UNMOVED (hop2==hop3).**

**New corpus dirs** (auto-listed; each references the ABSENT `sa.waitFor`, so each
is a compile-time RED today: dump rc=2, 0 `.c`,
`error[3042]: non-value base expression in field access` +
`warning[3023]: module used as value expression`). Fix round 1 (operator ruling
2026-09-16): `error[3042]` was REMOVED from the classifier's ICE regex — a clean
undefined-module-member rejection is a frontend FAIL, not an internal compiler
error — so the 7 new dirs now bucket **FAIL** (they were ICE under the old
regex). Genuine ICE markers (`error[48]`/`error[9001]`/`error[3043]`/
`AddressSanitizer`) stay ICE. The canonical classifier is
`scripts/corpus/classify`. The GREEN contracts below are validated against a
`/tmp` patched `lib/std_async.zig` carrying the proposed `waitFor` (the committed
`sf/src/std_async.zig` is unchanged); each was run 3x deterministic.

| fixture | shape | RED now (waitFor absent) | GREEN contract (Task 4c-F) |
|---|---|---|---|
| `stdlib_async_waitfor_xmod` | `waitFor(&s,&t0)` from main; t0 yields 2x then done | rc=2, 0 `.c`, `error[3042]` | rc=0, link+run rc=0, stdout `10` `3` |
| `stdlib_async_waitfor_cancel_xmod` | `cancel` before `waitFor`; step never resumed | rc=2, 0 `.c`, `error[3042]` | stdout `0` `4` (ticks 0, state cancelled) |
| `stdlib_async_waitfor_settled_xmod` | t0 pre-set `done`; t1 ready + unsettleable; `waitFor(&s,&t0)` must not tick/hang | rc=2, 0 `.c`, `error[3042]` | stdout `0` `3` (t1.ticks==0) |
| `stdlib_async_waitfor_oom_xmod` | step exhausts its pool; `waitFor` propagates `error.OutOfFrame` | rc=2, 0 `.c`, `error[3042]` | stdout `1` `1` `1` |
| `stdlib_async_waitfor_helper_xmod` | control: `waitFor` from a non-suspending helper fn | rc=2, 0 `.c`, `error[3042]` | stdout `10` `3` |
| `stdlib_async_waitfor_dep_xmod` | control: `waitFor(&s,&t1)` where t1 `awaitTask`s t0 (chain) | rc=2, 0 `.c`, `error[3042]` | stdout `10` `20` `3` |
| `stdlib_async_waitfor_unregistered_xmod` | Q3 guard: t0 unregistered + unsettled (no guard => hang) | rc=2, 0 `.c`, `error[3042]` | rc=133 panic `std.async: waitFor called with an unregistered task` |

**Extended `stdlib_async_await_nonctx_xmod`** (stays corpus class **OK**): adds
Part A (a coroutine-internal `awaitTask` chain driven by `waitAll`; stdout `10`
`20`, `fflush`-ed before the trap) before the original Part B (`awaitTask` from
main => `panic: std.async: awaitTask called from a non-suspending context`,
rc=133). `awaitTask`'s coroutine-internal semantics are unchanged.

**Corpus `-ffast` dump+gcc classifier (`scripts/corpus/classify`), universe 709
-> 716:**

| | 4b-F `18e0de5c` | 4c-I `18e0de5c` | delta |
|---|---|---|---|
| dirs | 709 | 716 | +7 |
| OK | 656 | 656 | 0 |
| GREEN | 28 | 28 | 0 |
| FAIL | 25 | 32 | +7 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir movement = exactly the 7 new dirs (all FAIL after the classifier
refinement; they were ICE before it); the modified
`stdlib_async_await_nonctx_xmod` stays OK and no other dir moved. No `sf/src`
change; no new diagnostic code (the RED uses the pre-existing
`error[3042]`/`warning[3023]`).

**Fix surface for Task 4c-F** (no `sf/src` change here): add
`pub fn waitFor(s: *Scheduler, t: *Task) FrameError!void` to
`sf/src/std_async.zig` (proposed insertion after `waitAll`, `:202`) — a plain
`tick` loop plus a registration guard — and update
`docs/superpowers/specs/2026-09-13-coroutine-integration-design.md`
§1/§3.1/§3.2 (see the task report for the exact text). Note: `std_async.zig` is
NOT in `sf/src/main.zig`'s import graph, so the self-emission fixed point is
**UNMOVED** (operator ruling; the plan now records 4c-F as "fixed point
UNMOVED"). Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-4c-report.md`.


## Track-4 Task 4b-F (F) — uninitialized `is_param` frame-layout buffer FIXED (v118 -> v119 2026-09-16)

Task 4b-F zero-inits the P3 live-analysis `is_param` predicate buffer pinned by
Task 4b-I. **`sf/src` change; fixed point MOVES** (see below). The two RED
fixtures now run GREEN; the two controls stay GREEN.

**Fix (`sf/src/async_frame_layout.zig`).** Added an `allocU8With(alloc, n, fill)`
helper (`:138-146`, mirrors `allocU32With`) and changed the `is_param`
allocation (`:572`) from the no-fill `allocU8Raw` to
`allocU8With(alloc, max_temp, 0)`. Every non-parameter entry is now
deterministically 0 before the param loop sets the parameter entries, so the
live scan (`:584`) and field emitter (`:609`) are deterministic. No
ABI/scheduler/state-machine change; `live`/`visited`/`ttype`/`work` were
already initialized (unchanged).

**Audit of the raw primitives (no other uninitialized read found).**
- `async_frame_layout.zig` `allocU8Raw` callers: `visited` (`:533`, cleared at
  `:456-459` before use), `live` (`:579`, zeroed by the loop that follows),
  `is_param` (the bug — now filled). `work`/`ttype` use the filling allocators.
- `lir_opt_pass.zig` raw scratch buffers (`:2070-2086`) are all fully written by
  `resetScratch` (`:268-289`, called at `:2096` and `:647`) before any read;
  `ord_pref` (`:956`) / `ord3` (`:1025`) are filled entry-by-entry (`ord[0]=0`
  then the prefix loop) before reads. The `Ctx` helpers `allocU32`/`allocU64`/
  `allocU8` (`:242-255`) have no callers.
- `async_analysis.zig` `allocU32` callers (`:244-271`): `rev_count`/`rev_off`/
  `rev_pos`/`rev_to`/`queue` are all fully written before any read.

**RED -> GREEN evidence** (fixed compiler `/tmp/t4bf/fixed/zig1_5_clean`,
`-ffast --dump-c89`, gcc `-m32 -std=c89 -O0 -Wall …`, link `build_target.sh
linux`, `timeout 120`):

| fixture | RED (BASE `5c243054`) | GREEN (FIXED `18e0de5c`) |
|---|---|---|
| `async_frame_isparam_xmod` | stdout `701 800`, run rc=133, `panic: …live local was dropped…`, gcc `warning: 'i' may be used uninitialized` | stdout `8 800`, run rc=0, gcc clean |
| `async_frame_isparam_order_xmod` | stdout `8 107`, run rc=133, same panic, gcc `warning: 'j' may be used uninitialized` | stdout `8 800`, run rc=0, gcc clean |
| `async_frame_isparam_resume_xmod` | GREEN: `8 800`, rc=0 | stays GREEN: `8 800`, rc=0 |
| `async_frame_isparam_single_xmod` | GREEN: `8`, rc=0 | stays GREEN: `8`, rc=0 |

Both `may be used uninitialized` gcc warnings disappear post-fix (the dropped
locals are now persisted fields).

**Corpus `-ffast` dump+gcc classifier, universe 709 (v118 = 709):**

| | 4b-I `5c243054` | 4b-F `18e0de5c` | delta |
|---|---|---|---|
| dirs | 709 | 709 | 0 |
| OK | 656 | 656 | 0 |
| GREEN | 28 | 28 | 0 |
| FAIL | 25 | 25 | 0 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir class map **byte-identical** (0 movement): the fix is a runtime-only
live-set correction, so the compile-only classifier is unchanged; the two
intended dirs were already class OK (the pin is RUNTIME-only).

**Other gates.** `check_emit_support.sh` 5/5 byte-identical. Self-compile 48
`.c`, rc=0, 0 `error[3000]` / 0 errors / 0 PANIC. Four goldens byte-identical:
`rogue_mud` boot `3fb6709e7bbd8964ef12aa9c906c0577`, `rogue_mud` move
`b3c5b0e1308bc9a4efde238376c14d9f`, `mud_server` stdout
`66c8f0abb926cca7baf9a0d1692ab318`, `mud_server` client bytes
`93147d0f0bbd983a9d844fea8b7a6fa7`; 4-MD5 runtime byte-identical (gol
`fcbf7e7cead5082f0a8caadd5a8f0ff9`, lisp `8dc783a3d766430c15993ab08cd0f7ec`,
json `8bda3d5a1ec07d14a301bc343df32bf8`); `verify_upgraded.sh` -> `CLOSEOUT OK`.
**NEW fixed point `18e0de5cf71f4fe0fbf5c560ab24e624`** (moving point hop2==hop3;
hop1 `c963a76cf3fbe484a5e5780f98b0828a`; BASE `5c24305437629da54b4e4de1ed52e0e0`).
Seed rotation stays at Task 6. Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-4b-report.md`.

## Track-4 Task 4b-I (I) — uninitialized `is_param` frame-layout buffer pinned (v117 -> v118 2026-09-16)

Task 4b-I pins the real defect behind the Task 4a-F "coroutine only advances
with >=2 tasks" symptom. The original 1-task premise was DISPROVED (the
single-task fixture is GREEN today); the real root cause is an UNINITIALIZED
`is_param` predicate buffer in the P3 frame-live analysis. **No `sf/src`
change; fixed point `5c24305437629da54b4e4de1ed52e0e0` UNMOVED (hop2==hop3).**

**Defect.** `sf/src/async_frame_layout.zig:562` allocates `is_param` with the
NO-FILL primitive `allocU8Raw` (`:131-136`, a raw `sandAlloc` bump) and sets
only the parameter entries (`:564-567`). Every non-parameter entry is stale
heap memory (the compiler's `memory_pool_buf` BSS, reused across phases).
`is_param` gates the live scan (`:584 if (is_param[tu] != 0) continue;`) and
the field emitter (`:609`), so when the stale bytes are non-zero a live local
is silently dropped from the frame. `saveAllFields`/`reloadAllFields`
(`sf/src/async_state_machine.zig:253-279`) faithfully persist only the given
fields; the resume segment reloads nothing and the step reads an
uninitialized C local. `std.async.tick` and the resume routing are correct.

**Deterministic RED form = >=2-coroutine interleave.** A single task alone can
pass by C stack-slot reuse, so the reproducible form is two scheduler tasks.

**New corpus dirs** (auto-listed; all compile-clean => class OK; the pin is
RUNTIME-only so the class map moves only by +4):

| fixture | shape | RED now | GREEN contract (Task 4b-F) |
|---|---|---|---|
| `async_frame_isparam_xmod` | 2 tasks, `coA` first | stdout `701 800`, run rc=133 (SIGTRAP) `panic: ...a live local was dropped from the frame`; gcc `warning: 'i' may be used uninitialized` in `__Z98Step_coA` | stdout `8 800`, rc=0 |
| `async_frame_isparam_order_xmod` | 2 tasks, `coB` first | stdout `8 107`, run rc=133; gcc `warning: 'j' may be used uninitialized` in `__Z98Step_coB` | stdout `8 800`, rc=0 |
| `async_frame_isparam_resume_xmod` | same bodies, direct `@asyncResume`, no `std_async` import | GREEN today: stdout `8 800`, rc=0; `__Z98Step_coA` persists `n`@16/`i`@20 | stays GREEN |
| `async_frame_isparam_single_xmod` | 1 task, no interleave | GREEN today: stdout `8`, rc=0 (gcc may warn `'i'`) | stays GREEN |

The two RED fixtures are declaration-order mirrors: the drop MOVES from `coA`
to `coB`, which is the signature of an uninitialized read (a genuine
data-flow drop would be order-independent). The same order dependence was
first seen at the single-task level: `m8` (`worker` first) drops `worker`'s
`i` (`__Z98Step_worker` saves only `out`@12); `m8b` (`other` first) drops
`other`'s `q` instead and `worker` persists `n`/`i` (`__Z98Step_worker` saves
offsets 12/16/20/...). Deterministic: re-dumping `async_frame_isparam_xmod`
3x produces byte-identical emitted C and the same `701 800`.

**Corpus `-ffast` dump+gcc classifier (`/tmp/t4bf_classify.sh`), universe
705 -> 709:**

| | 4a-F `5c243054` | 4b-I `5c243054` | delta |
|---|---|---|---|
| dirs | 705 | 709 | +4 |
| OK | 652 | 656 | +4 |
| GREEN | 28 | 28 | 0 |
| FAIL | 25 | 25 | 0 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir movement = exactly the 4 new dirs; all 705 pre-existing dirs
class-identical (no `sf/src` change). No new diagnostic code. Fix surface for
Task 4b-F: zero-init `is_param` at `sf/src/async_frame_layout.zig:562-567`
(add an `allocU8With(alloc, max_temp, 0)` helper mirroring `allocU32With`, or
an explicit zero loop as at `:569-573`); audit of `allocU8Raw`/`allocU32`
callers found no other uninitialized read (lir_opt_pass's raw buffers are all
filled by `resetScratch`; async_analysis's `allocU32` callers all fill before
use). Frame SIZE (P2) is unaffected — `is_param` is P3-only. Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-4b-report.md`.

## Track-4 Task 4a-F (F) — `rogue_mud` client-task wiring FIXED (v116 -> v117 2026-09-16)

Task 4a-F fixes all three `rogue_mud` client-task defects (operator ruling
2026-09-16). **Examples-only: no `sf/src` change; fixed point UNMOVED.**

**Changes (`examples/z98/rogue_mud/`):**
- `main.zig:433` `clientFrameCoroutine` — (1) self-gates on
  `cfa.server.clients[cfa.client_idx].active` (a task never touches a non-active
  client's socket), (2) wraps the body in `while (true)` so a connected client
  keeps receiving frames across broadcasts (long-lived task per slot; stays
  `suspended`, never `done`), and (3) INLINES the row loop that was the nested
  `ui_mod.drawToSocketCoroutine` call, so the root coroutine allocates no CHILD
  frame and the root-frame arena may safely alias the async ctx pool
  (`main.zig:105-106`; report finding (3)). S11 preserved: each task still
  builds into its own `cfa.cells`.
- `ui.zig:127` `sendColorANSI` promoted to `pub` so the inlined loop reuses it.

**Defect-3 fixture (new):** `repro/mi_matrix/client_task_arena_xmod` —
imports the REAL example module and drives the REAL `clientFrameCoroutine`
through the REAL scheduler using the example's ALIASING layout (root arena over
`async_storage[HEADER_SIZE..]`, ctx pool over `async_storage[0..]`); slot 0
ACTIVE, slot 1 NON-ACTIVE, real `socketpair(2)` ends, 80 broadcasts. Corpus
class **OK** (runtime-only pin, so the class map only gains the dir).

**RED -> GREEN (both committed fixtures, `-ffast --dump-c89`, gcc `-m32 -std=c89`
clean, link rc=0, `timeout 120 ./prog`):**

| fixture | RED (v116 compiler) | GREEN (v117) |
|---|---|---|
| `client_task_wiring_xmod` | `active_total:3120 inactive_total:3120 active_last:0 active_state:3` rc=133 | `active_total:8080 inactive_total:0 active_last:142 inactive_last:0 active_state:2` rc=0 |
| `client_task_arena_xmod` | `active_total:74 inactive_total:3120 active_last:0 active_state:3` rc=133 | `active_total:8080 inactive_total:0 active_last:142 inactive_last:0 active_state:2` rc=0 |

The arena fixture's RED `active_total:74` is the defect-3 signature (the nested
child frame overwrites the active task's root frame, which dies after one row)
versus a healthy full-frame stream once the row loop is inlined.

**Corpus `-ffast` dump+gcc classifier (`/tmp/t4bf_classify.sh`), universe 704 -> 705:**

| | 4a-I `5c243054` | 4a-F `5c243054` | delta |
|---|---|---|---|
| dirs | 704 | 705 | +1 |
| OK | 651 | 652 | +1 |
| GREEN | 28 | 28 | 0 |
| FAIL | 25 | 25 | 0 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir movement = exactly the one new dir (`client_task_arena_xmod` OK); all
704 pre-existing dirs class-identical (no `sf/src` change). `check_emit_support.sh`
5/5; self-compile closure 48 `.c`, 0 `error[3000]`. Four goldens byte-identical:
`rogue_mud` boot `3fb6709e7bbd8964ef12aa9c906c0577`, `rogue_mud` move
`b3c5b0e1308bc9a4efde238376c14d9f`, `mud_server` stdout
`66c8f0abb926cca7baf9a0d1692ab318`, `mud_server` client bytes
`93147d0f0bbd983a9d844fea8b7a6fa7`; `verify_upgraded.sh` -> `CLOSEOUT OK`.
Fixed point `5c24305437629da54b4e4de1ed52e0e0` UNMOVED (hop2==hop3). Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-4a-report.md`.

## Track-4 Task 4a-I (I) — `rogue_mud` client-task wiring pinned (v115 -> v116 2026-09-16)

Track-4 Task 4a-I pins the two client-task wiring defects found by the Task 4
review (operator ruling 2026-09-16: fix both via I then F). The multiplayer
path is dead in-corpus (`examples/z98/rogue_mud/main.zig` `MULTIPLAYER_ENABLED
= false`), so the pin is a **deterministic runtime repro driver** that imports
the REAL example module and drives the REAL `clientFrameCoroutine` /
`drawToSocketCoroutine` through the REAL `std.async` scheduler, with two real
`socketpair(2)` ends (one ACTIVE, one NON-ACTIVE). **No `sf/src` change.**

Reference compiler = the Task-2g-F fixed point
`5c24305437629da54b4e4de1ed52e0e0`, rebuilt via the binding seed model
(`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz
/tmp/t4aI_build`; gate `=== [seed] Done: /tmp/t4aI_build ===`). The committed
seed predates recent `sf/src` work, so the closure is the moving point
**hop2 == hop3 == `5c243054…`** (hop1 `768479844ce7e64b12f8d871fd918ed0`).
Compiler under test = `/tmp/t4aI_build/zig1_5_clean` (hop1 binary; its sibling
`lib/` carries the 9 std modules).

**New corpus dir** (auto-listed by `scripts/corpus/list_corpus_dirs.sh`):
`repro/mi_matrix/client_task_wiring_xmod` — corpus class **OK** (compile-clean;
the pin is RUNTIME-only, so the class map does NOT move; mirrors the
`async_live_local_across_suspend_xmod` runtime-RED idiom).

**Defect (1) — a client task runs against a NON-ACTIVE client.** The example
adds one task per slot at startup (`main.zig:114-135`) and `tick`s on every
local move (`broadcastDungeon`), so a task for an inactive slot still reads
`clients[i].socket` and streams a full frame. In the single-player path the
slot's `.socket` is `undefined` (only `.active` is initialised), so the send
target is garbage; the fixture substitutes a valid `socketpair` fd to make the
write deterministically observable.

**Defect (2) — one-frame lifecycle.** `clientFrameCoroutine` returns after ONE
pass of `drawToSocketCoroutine`; `tick` marks the task `done` and it is never
re-added, so after ~`rows` broadcasts the connected client receives nothing.

**RED evidence** (`-ffast --dump-c89`, 23 `.c`, gcc `-m32 -std=c89` clean,
link rc=0, `timeout 120 ./prog`):
```
active_total: 3120        # one full frame to the ACTIVE slot
inactive_total: 3120      # DEFECT 1: full frame to the NON-ACTIVE slot
active_last: 0            # DEFECT 2: nothing on the final broadcast
inactive_last: 0
active_state: 3           # TaskState.done
panic: client_task_wiring_xmod: a task wrote to a NON-ACTIVE client socket (defect 1)
run rc=133 (SIGTRAP)
```

**GREEN contract** (validated against a `/tmp` patched example where
`clientFrameCoroutine` self-gates on `.active` and loops `while (true)` across
broadcasts):
```
active_total: 8080  inactive_total: 0  active_last: 142  inactive_last: 0  active_state: 2
run rc=0
```

**Finding (3) — root-frame arena / ctx-pool aliasing blocks the nested client
coroutine (NOT in the Task-4a brief; operator ruling needed).**
`main.zig:105-106` builds `async_arena` over `async_storage[HEADER_SIZE..]`
and `async_ctx = contextInit(async_storage[0..])`, whose `pool_base =
async_storage[16]`. The first `sand_alloc(&async_arena, …)` root frame and the
first `contextAlloc(async_ctx, …)` child frame land at the SAME address, so the
nested `drawToSocketCoroutine` child frame overwrites the first task's root
frame. Measured on the PATCHED example with the example's aliasing layout: the
active task stalls after one row (`active_total: 74`, `active_state: 3`,
`active_last: 0`) → defect-2 panic. Task 4a-F must therefore ALSO separate the
root-frame backing from the ctx pool, or inline the row loop into
`clientFrameCoroutine` so no child frame is allocated (Task-4 review minor #3
previously recorded the aliasing as pre-existing/plan-mandated). The committed
fixture uses a SEPARATE `root_storage` so its RED is attributable to (1)/(2)
alone.

**Corpus `-ffast` dump+gcc classifier (`/tmp/t4bf_classify.sh`), universe 703 -> 704:**

| | 2g-F `5c243054` | 4a-I `5c243054` | delta |
|---|---|---|---|
| dirs | 703 | 704 | +1 |
| OK | 650 | 651 | +1 |
| GREEN | 28 | 28 | 0 |
| FAIL | 25 | 25 | 0 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir movement = exactly the one new dir (`client_task_wiring_xmod` OK); all
703 pre-existing dirs class-identical (no `sf/src` change). No new diagnostic
code. Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-4a-report.md`.

## Track-4 Task 2g-F fix round 1 (F) — `for |row|` by-value array item (v114 -> v115 2026-09-16)

Review finding: the first Task 2g-F cut typed a `for (arr) |row|` item as
`*[N]T` (a row reference), so a whole-row VALUE use
(`for (gc) |row| { var r: [4]Cell = row; }`) emitted `r[_i] = row[_i];` with
`row: Cell(*)[4]` — SILENT invalid C (dump rc=0, stderr EMPTY; gcc
`incompatible types when assigning to type 'Cell' from type 'Cell *'`).
Operator ruling: FIX it (real Zig `for` is by-value), not merely declare it.

**Fix:** the item is materialized as an ARRAY-typed temp and the item load is a
byte-wise element copy via a new `load_index{decay=3}` mode
(`sf/src/c89_emit.zig` `emitBaseIdxAccess`; `sf/src/lower.zig` `for_stmt` arm).
`row` is then a real `[N]T` value: indexing, whole-row copies, and nested `for`
all work. The 2f-F `decay=1`/`2` modes (used by direct element access,
address-of, and the field-store base) are unchanged.

- New fixture `multiarray_for_iter_value_xmod` (auto-listed): copies each row
  into a local `[4]Cell`, asserts the copy's full contents, and mutates the copy
  to prove it does NOT alias the source row. RED at `1e82d6ca` (gcc
  `incompatible types …`), GREEN at the new fixed point.
- `multiarray_row_store_xmod` assertions extended (reviewer Minor #4): all four
  row-0 bytes (incl. the middle) are asserted, and rows 1-2 are asserted
  untouched.
- Reference compiler = NEW fixed point `5c24305437629da54b4e4de1ed52e0e0`
  (seed model; moving point hop2 == hop3 == `5c243054…`, hop1 `76847984…`;
  previous fixed point `495ceae3…`). Full report:
  `.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-2g-report.md`.

**Corpus `-ffast` dump+gcc classifier (`/tmp/t4bf_classify.sh`), universe
702 -> 703:**

| | 2g-F `495ceae3` | fix round 1 `5c243054` | delta |
|---|---|---|---|
| dirs | 703 | 703 | 0 |
| OK | 649 | 650 | +1 |
| GREEN | 28 | 28 | 0 |
| FAIL | 26 | 25 | -1 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir `join` diff = exactly `multiarray_for_iter_value_xmod` FAIL→OK; zero
movement among the other 702 dirs. The five 2g-F class-closing dirs and the two
`for`-iteration controls are unchanged.

## Track-4 Task 2g-F (F) — array-to-array class fully closed (v113 -> v114 2026-09-16)

Task 2g-F closes the five residual members of the array-to-array defect class
(found by the 2g-I investigation; operator ruling 2026-09-16 folded (c)/(d)/(e)
into 2g-F). **`sf/src` change** in three files: `sf/src/lower.zig` (for-loop
item decay; `lowerFieldStore` index base decay), `sf/src/semantic_analyzer.zig`
(non-indexable base → hard `error[3000]`; array-literal annotation resolution),
and `sf/src/c89_emit.zig` (`assign_index` and `store_global` byte-wise array
copies). Reference compiler = the NEW fixed point
`495ceae32a717cb6dac7caf7146fb67f` (seed model:
`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>`; moving
point hop2 == hop3 == `495ceae3…`, hop1 `a2013754…`; prior fixed point
`7f9afa82…`). Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-2g-report.md`.

- **(a) for-loop iteration.** `sf/src/lower.zig` `for_stmt` non-range arm: when
  the item is itself a fixed array, the item temp + `decl_local` capture are
  typed `*[N]T` and the `load_index` carries `decay` (2 for a fixed-array value
  → `&base[idx]`; 1 for a decayed row pointer → `&(*base)[idx]`), reusing the
  2f-F mechanism. `multiarray_for_iter_xmod` + `_3d_xmod` FAIL→OK; the two
  controls stay OK.
- **(b) `pp: *[N]T` element access → HARD `error[3000]`** (option B; the
  operator verified real Zig rejects `pp[0][1]`). `semanticAnalyzerResolveIndexAccess`
  now rejects an index whose base is a concrete non-array/non-pointer/non-tuple
  value (e.g. the scalar yielded by `pp[0]`). `ptr_to_array_index_xmod` FAIL→GREEN
  (rc=2, 0 `.c`, located `error[3000]`).
- **(c) field store through a multi-dim element (SILENT WRONG CODE).**
  `lowerFieldStore`'s `index_access` base branch now takes the element address
  `&(*ptr)[idx]` (`load_index{decay=1}`) when the base is a pointer-to-array,
  instead of a raw `ptr + idx` (which scaled by the whole row). New fixture
  `multiarray_field_store_xmod` pins the value landing in the correct slot (all
  20 slots asserted after `gc[1][2].v = 5`); it classifies OK at the gcc gate
  both pre/post (the defect was silent) but is runtime-RED→GREEN.
- **(d) multi-dim array-literal init.** The `assign_index` emitter and the
  `store_global` emitter now copy an array element/whole array byte-wise
  (`sizeof`-bounded) instead of emitting `base[idx] = src;` / `name[_i] = val[_i];`.
  New fixture `multiarray_literal_init_xmod` (global `[2][3]u8` literal) FAIL→OK.
  The nested literal is also typed by its annotation (u8 rows, not inferred u32)
  via a `resolveTypeExprFull` fallback in `semanticAnalyzerResolveArrayInit`.
- **(e) row store into a multi-dim element.** `g[i] = row;` now byte-copies via
  the same `assign_index` path. New fixture `multiarray_row_store_xmod` FAIL→OK.

**New corpus dirs** (auto-listed): `multiarray_field_store_xmod`,
`multiarray_literal_init_xmod`, `multiarray_row_store_xmod`.

**Corpus `-ffast` dump+gcc classifier (`/tmp/t4bf_classify.sh`), universe
699 -> 702:**

| | 2g-I `7f9afa82` | 2g-F `495ceae3` | delta |
|---|---|---|---|
| dirs | 702 | 702 | 0 |
| OK | 645 | 649 | +4 |
| GREEN | 27 | 28 | +1 |
| FAIL | 30 | 25 | -5 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir `join` diff = exactly the five intended dirs (`multiarray_for_iter_xmod`,
`multiarray_for_iter_3d_xmod`, `multiarray_literal_init_xmod`,
`multiarray_row_store_xmod` FAIL→OK; `ptr_to_array_index_xmod` FAIL→GREEN);
`multiarray_field_store_xmod` is OK both (runtime-RED); the two 2g-I controls
stay OK. Zero movement among the other 697 dirs. No new diagnostic code
(`error[3042]`/`error[3043]` not involved).

## Track-4 Task 2g-I (I) — for-loop iteration + pointer-to-array residuals pinned (v112 -> v113 2026-09-16)

Track-4 Task 2g-I pins the two residual members of the array-to-array defect
class that Task 2f-F did NOT close (found by the 2f-F review; operator ruling
2026-09-16: fix BOTH in Task 2g-F). **No `sf/src` change.** Reference compiler =
the Task-2f-F fixed point `7f9afa82deaa2356633b20a693282cf1`, rebuilt via the
binding seed model (`bash scripts/seed/build_from_seed.sh
release/seed/zig1-seed.tgz /tmp/t2gI_build`; gate
`=== [seed] Done: /tmp/t2gI_build ===`). The committed seed predates recent
`sf/src` work, so the closure is the moving point **hop2 == hop3 ==
`7f9afa82deaa2356633b20a693282cf1`** (hop1 `86c7f0007a0eb3a3352745f6813f017d`).
Compiler under test = `/tmp/t2gI_build/zig1_5_clean` (hop1 binary; its sibling
`lib/` carries the 9 std modules). Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-2g-report.md`.

**Residual (a) — `for`-loop iteration keeps `decay = 0`.** The `for_stmt` arm
(`sf/src/lower.zig:6037`) resolves the iterated array's element type
(`elem_type[0] = [4]u8` for `g: [5][4]u8`, `:6051-6053`) and emits the per-item
load with a HARDCODED `decay = 0` (`:6130-6131`):

```
item_temp = nextTemp(self, elem_type[0]);   // ARRAY-typed temp
load_index{ base=ptr_temp, index=idx, result=item_temp, decay=0 }
```

The capture is declared array-typed (`:6132`). `emitBaseIdxAccess`
(`sf/src/c89_emit.zig:194`, kind==0, decay==0) renders `item = base[idx];` — an
array-to-array C assignment, illegal in C89. The for-loop arm predates the 2f-F
`decay` field and was never updated (2f-F touched only the `index_access`
rvalue arm `:3153-3176` and the address-of arm `:1394-1397`), so the decay
mechanism is bypassed.

**Residual (b) — `pp: *[N]T` element access.** `pp[0]` is typed by
`typeRegistryIndexedElemType` (`sf/src/type_registry.zig:970`): the
`ptr_type`/`many_ptr_type` branch (`:978-984`) sees the pointee is an array and
returns the pointee's ELEMENT (`u8`) instead of the pointee array itself
(`[4]u8`). `semanticAnalyzerResolveIndexAccess` (`sf/src/semantic_analyzer.zig:3228`)
therefore types `pp[0]` as `u8`; the lowerer's 2f-F array-decay branch
(`sf/src/lower.zig:3157`) never fires, so the emitter (base IS ptr-to-array)
renders `zT = (*pp)[idx];` — a scalar — and the following `[1]` subscripts a
scalar. Pre-existing: BASE `8a322dd9` and fix `7f9afa82` byte-identical.

**Five new corpus dirs** (auto-listed by `scripts/corpus/list_corpus_dirs.sh`):

| dir | class | RED today (fixed point 7f9afa82…) | expected GREEN (Task 2g-F) |
|---|---|---|---|
| `multiarray_for_iter_xmod` | **FAIL** | dump rc=0, 4 `.c`, stderr EMPTY; gcc `assignment to expression with array type` ×2 (`row = zG_g[i];` for `[5][4]u8`, `row_1 = zG_gc[i];` for `[5][4]Cell`) | dump rc=0, gcc clean, link+run rc=0, no stdout |
| `multiarray_for_iter_3d_xmod` | **FAIL** | same; 3-D `[3][4][5]u8`, nested `for` (TWO array-typed item temps) | same |
| `multiarray_for_iter_flat_control_xmod` | **OK** (control) | flat 1-D `[20]u8` already emits scalar `x = g[i];` | stays OK |
| `multiarray_for_iter_scalar_control_xmod` | **OK** (control) | range `for (0..5)` reading scalar `g[i][0]` (2f-F path) | stays OK |
| `ptr_to_array_index_xmod` | **FAIL** | dump rc=0, 4 `.c`, stderr EMPTY; gcc `subscripted value is neither array nor pointer nor vector` ×2 (`zT_7 = (*pp)[0]; zT_7[1] = 3;`) | **hard `error[3000]`** (option B): rc=2, 0 `.c`, located `cannot index a value of non-array, non-pointer type` — see the 2g-F section |

Verbatim RED evidence (`multiarray_for_iter_xmod`, fixed point `7f9afa82…`):
```
main_166F9ACE.c:84:    row = zG_E20C2606_g[zT_29];      /* array = array */
main_166F9ACE.c:112:   row_1 = zG_3E2070FF_gc[zT_47];   /* array = array */
gcc: error: assignment to expression with array type   (x2)
```
`multiarray_for_iter_3d_xmod`: `plane = zG_E20C2606_g[zT_14];` /
`row = plane[zT_19];` (x2 `assignment to expression with array type`).
`ptr_to_array_index_xmod`:
```
main_ED1CE020.c:47:    zT_7 = (*pp)[zT_6];   /* zT_7 declared `unsigned char` */
main_ED1CE020.c:51:    zT_7[zT_8] = zT_5;      /* subscript a scalar */
gcc: error: subscripted value is neither array nor pointer nor vector   (x2)
```

**Residual (b) contract — RESOLVED by Task 2g-F (option B, hard error).**
`docs/reference/Language_Spec_Z98.md:32` states `ptr[i]` is "strictly rejected
for single-item pointers". The operator verified against the Zig langref
(2026-09-16) that real Zig REJECTS `pp[0][1]`: `*[N]T` supports index syntax
`array_ptr[i]`, but `pp[0]` yields the ELEMENT (`u8`), not the array, so
indexing the resulting scalar is a type error (the element is reached via
`pp[1]` or `pp.*[1]`). Option **(B)** was chosen: a hard `error[3000]`, not a
compile-clean decay (A). Task 2g-F implements it — see the 2g-F section below.

**Q5 — other array-to-array producers remain (grep of emitter/lowerer).**
`load_index` is emitted at exactly three sites: `lower.zig:1396` (address-of,
decay 1), `:3195` (`index_access` rvalue, 2f-F `ix_decay`), `:6131` (for-loop,
residual (a)). But the class is NOT fully closed. Three additional producers
were found (scratch repros, NOT committed as fixtures — operator to decide
scope):

- **(c) field store through a multi-dim element** — `lowerFieldStore`'s
  `index_access` base branch (`sf/src/lower.zig:1780-1787`) computes the field
  base as a raw `ptr_temp + idx_temp` (BIN_ADD) on the decayed row pointer, so
  `gc[1][2].v = 5` emits `zT_6 = zT_4 + zT_5;` (`zT_4: Arr_Cell_4*`) — scaled
  by the WHOLE row. gcc emits only a `-Wincompatible-pointer-types` WARNING
  (classifier stays OK), so this is SILENT WRONG CODE. Same "fixed-array
  element access bypasses decay" family; reachable from the Track-4
  `client_cells` shape. The rvalue read `gc[1][2].v` is already correct
  (`(*zT_10)[zT_11]`, via 2f-F).
- **(d) multi-dimensional array literal init** — `assign_index` at
  `sf/src/lower.zig:5048` / `:5254` assigns each element array-to-array, e.g.
  `zT_0[zT_8] = zT_1;` (`zT_1: [3]u8`), plus the global-init copy
  `zG_g[_i] = zT_0[_i];`. Repro `var g: [2][3]u8 = [2][3]u8{ [3]u8{1,2,3}, ... };`
  → 3 gcc `assignment to expression with array type` errors.
- **(e) row store into a multi-dim element** — `assign_index` at
  `sf/src/lower.zig:1564`; `g[0] = row;` → `g[0] = row;` array-to-array
  (1 gcc error).

The emitter's `assign_index` path (`sf/src/c89_emit.zig:6064-6076`) always
passes `decay = 0`; any array-typed `src` there is illegal. Task 2g-F's (a)+(b)
fix does NOT cover (c)/(d)/(e).

**Fix surface for Task 2g-F** (presented in the task report; no `sf/src` change
here):
- (a) `sf/src/lower.zig:6130-6132` — decay the for-loop item: type the item
  temp and the `decl_local` capture as `*[N]T`, and emit
  `load_index{decay}` choosing 1 vs 2 via `tempTypeIsPtrToArray` (2 when the
  iterated value is a fixed-array temp, i.e. `&base[idx]`; 1 when the base is
  already a decayed row pointer). Slice/range patterns stay decay 0.
- (b) `sf/src/type_registry.zig:978-984` — return the pointee ARRAY type when
  the pointee is an array (option A), or add the `*T` indexing rejection in
  `semanticAnalyzerResolveIndexAccess` / `semanticAnalyzerResolveExpr`
  (option B). No lowerer change under (A).

**Corpus `-ffast` dump+gcc classifier (`/tmp/t4bf_classify.sh`), universe 694
-> 699:**

| | 2f-F fix `7f9afa82` | 2g-I `7f9afa82` | delta |
|---|---|---|---|
| dirs | 694 | 699 | +5 |
| OK | 642 | 644 | +2 |
| GREEN | 27 | 27 | 0 |
| FAIL | 25 | 28 | +3 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir `join` diff = exactly the five new dirs (3 FAIL, 2 OK); all 694
pre-existing dirs class-identical (no `sf/src` change). **No new diagnostic
code** — the three RED dirs emit NO compiler diagnostic (silent rc=0); gcc's
`assignment to expression with array type` / `subscripted value …` is the only
signal. `error[3042]`/`error[3043]` are not involved.

## Track-4 Task 2f-F (F) — multi-dimensional fixed-array element access FIXED (v111 -> v112 2026-09-16)

Track-4 Task 2f-F closes the silent-invalid-C defect pinned by Task 2f-I. **`sf/src`
change** in four files: `sf/src/lir.zig` (new `load_index.decay: u8` field),
`sf/src/lower.zig` (rvalue `index_access` decay + `lowerLValueAddr` index arm +
new `tempTypeIsPtrToArray` helper), `sf/src/async_state_machine.zig` (carry the
field through the coroutine remap), and `sf/src/c89_emit.zig`
(`emitBaseIdxAccess` decay rendering; multi-dim `undefined`-init byte-wise zero
and array-copy loops). Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-2f-report.md`.

**What landed.**
1. **Decay the multi-dim row to a pointer.** `lowerExpr`'s `index_access` arm
   (`sf/src/lower.zig:3080`) now types the result of an index whose ELEMENT is a
   fixed array as a pointer to that array (`*[N]T`) and emits `load_index` with
   `decay` set, instead of materializing an array-typed temp. The emitter renders
   `&(*base)[idx]` (decay 1: base is a decayed row pointer) or `&base[idx]`
   (decay 2: the base's indexed element IS the array — also correct for a genuine
   `*[N]T`). Downstream indexing uses `(*base)[idx]`, valid C89. This covers the
   rvalue form and (through the shared base lowering) the store form at all
   nesting levels.
2. **Address-of form.** `lowerLValueAddr`'s index arm (`sf/src/lower.zig:1379`)
   uses the same decay `load_index` when the base expression is a fixed array
   (a decayed row) and the base temp is a pointer-to-array, so `&g[i][j]` emits
   `&(*base)[j]` rather than the wrongly-scaled `base + j`. The 1-D `&g[i]` path
   (array base, `BIN_ADD`) is unchanged.
3. **Multi-dim `undefined`-init** (`sf/src/c89_emit.zig`): the `undefined_const`
   array zero-fill and the `assign` array-copy loop now emit a byte-wise
   `((unsigned char*)&dst)[_i] = ...` loop when the array's element is itself an
   array (a row-by-row `dst[_i] = src[_i]` / `dst[_i] = 0` is illegal C89). The
   1-D / struct-element emissions are byte-identical to before.
4. The `Arr_*` array-typedef path (`getCTypeName` `sf/src/c89_emit.zig:710`) is
   the (correct) declaration and was NOT changed.

**Build (binding seed model; fixed point MOVES).**
```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t2fF_fix2
[seed] hop1 binary md5: 86c7f0007a0eb3a3352745f6813f017d
[seed] hop2 binary md5: 7f9afa82deaa2356633b20a693282cf1
[seed] hop3 binary md5: 7f9afa82deaa2356633b20a693282cf1
[seed] three-hop closure OK (moving point): hop2 == hop3 == 7f9afa82deaa2356633b20a693282cf1
```
BASE `8a322dd9221077780202e8ac6dd6983a` → **NEW fixed point
`7f9afa82deaa2356633b20a693282cf1`** (hop2 == hop3; the committed seed predates
recent `sf/src`, so hop1 differs). Compiler under test =
`/tmp/t2fF_fix2/zig1_5_clean` (hop1 binary; its sibling `lib/` carries the 9 std
modules). `zig0` never invoked; seed rotation stays at Task 6.

**Fixtures RED → GREEN** (`-ffast --dump-c89`; gcc `-m32 -std=c89`; link+run):

| fixture | RED (`8a322dd9…`) | GREEN (`7f9afa82…`) |
|---|---|---|
| `multiarray_index_xmod` | dump rc=0, 4 `.c`, stderr empty; gcc `assignment to expression with array type` ×2 | dump rc=0, gcc clean, link+run rc=0, no stdout |
| `multiarray_index_const_xmod` | same (constant `&g[2][0]` / `g[2][3]`) | same |
| `multiarray_index_local_xmod` | 4 gcc errors (element access + `undefined`-init copy/zero) | dump rc=0, gcc clean, link+run rc=0, no stdout |
| `multiarray_index_3d_xmod` | 4 gcc errors (two chained array temps) | same |
| `multiarray_index_struct_control_xmod` | same (`[5][4]Cell`, Task-3/4 shape) | same |
| `multiarray_index_flat_control_xmod` | **OK** (compile class) | stays **OK** (compile class) |

GREEN emitted evidence (`multiarray_index_xmod`): `zT_8 = &zG_g[i];`
`zT_10 = &(*zT_8)[zT_9];` `zT_15 = (*zT_14)[j];` (no array-to-array assignment).
`multiarray_index_3d_xmod`: `zT_12 = &zG_g[i];` `zT_13 = &(*zT_12)[j];`
`zT_15 = &(*zT_13)[zT_14];` `zT_21 = (*zT_20)[k];`.
`multiarray_index_local_xmod`: `((unsigned char*)&zT_1)[_i] = 0;` /
`((unsigned char*)&g)[_i] = ((unsigned char*)&zT_1)[_i];`.

**Flat-control note (pre-existing, NOT a 2f-F regression).** The flat-1D control's
fixture body passes both `&g[i]` AND `i` to `sink`, whose body does `p[i] = 7`, so
it writes `g[i + i]` and then asserts `g[i] == 7` — its declared "run rc=0"
contract is wrong. Measured on BOTH the BASE `8a322dd9` and the fix `7f9afa82`:
dump rc=0, gcc clean, link rc=0, **run rc=133** (`panic: ... element value
mismatch`). The control's corpus class stays **OK** (compile-only classifier), as
required; the fixture body was NOT modified (out of Task 2f-F scope).

**Corpus `-ffast` dump+gcc classifier (`/tmp/t4bf_classify.sh`), 694 dirs** (run
with `zig1_5_clean` so `<exe_dir>/lib` resolves std):

| | BASE `8a322dd9` | fix `7f9afa82` | delta |
|---|---|---|---|
| dirs | 694 | 694 | 0 |
| OK | 637 | 642 | +5 |
| GREEN | 27 | 27 | 0 |
| FAIL | 30 | 25 | −5 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

Per-dir `join` diff = **exactly** the five intended fixtures FAIL→OK. All 689
other dirs class-identical (zero regression). No new diagnostic code.

**Emit-support / self-compile / goldens.**
- `bash scripts/check_emit_support.sh /tmp/t2fF_fix2/zig1_5_clean` → **5/5** support files byte-identical.
- Self-compile: `--markers --dump-c89 sf/src/main.zig` → rc=0, **48 `.c`**, 0 `error[3000]`, 0 errors, 0 PANIC.
- `bash scripts/closeout/verify_upgraded.sh /tmp/t2fF_fix2/zig1_5_clean` → **`CLOSEOUT OK`** (A1–A5, B1–B7); rogue q `3fb6709e…`, rogue move `b3c5b0e1…`.
- 4-MD5 runtime byte-identical: gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`, lisp `8dc783a3d766430c15993ab08cd0f7ec`, json `8bda3d5a1ec07d14a301bc343df32bf8`, mud_server stdout `66c8f0abb926cca7baf9a0d1692ab318` / client bytes `93147d0f0bbd983a9d844fea8b7a6fa7`.
- No seed rotation (Task 6 owns rotation).

## Track-4 Task 2f-I (I) — multi-dimensional fixed-array element access pinned (v110 -> v111 2026-09-16)

Track-4 Task 2f-I pins the SILENT invalid-C defect that blocks Task 4 (E3): an
element access into a multi-dimensional fixed array lowers the OUTER index into
an ARRAY-typed temp, and the emitter assigns array-to-array (illegal C89).
**No `sf/src` change.** Reference compiler = the Task-2e-F fixed point
`8a322dd9221077780202e8ac6dd6983a`, rebuilt via the binding seed model
(`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t2fI_build`;
gate `=== [seed] Done: /tmp/t2fI_build ===`). The committed seed predates recent
`sf/src` work, so the closure is the moving point **hop2 == hop3 ==
`8a322dd9221077780202e8ac6dd6983a`** (hop1 `9d25d1aa2e993a50311241a69da01b3b`).
Compiler under test = `/tmp/t2fI_build/hop2/zig1_hop2`. Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-2f-report.md`.

**Root cause (verified, read-only).** `lowerExpr`'s index_access arm
(`sf/src/lower.zig:3080`) types the indexed result from the resolved type table:
for `g[i]` (with `g: [5][4]u8`) that is the ARRAY `[4]u8`, so `nextTemp` allocates
an array-typed temp (`:3116`) and a `load_index` LIR op is emitted (`:3133`). The
emitter renders `load_index` via `emitBaseIdxAccess` (`sf/src/c89_emit.zig:189`,
`kind==0`) as `result = base[idx];` (`:196-208`) — an array-to-array C
assignment, illegal in C89. The same base lowering is used by the address-of
path (`lowerLValueAddr` index arm `sf/src/lower.zig:1363-1370`) and the store
path (`lowerAssignLValue` index arm `:1509-1532`), so all three forms break.
The `Arr_*` array-typedef path (`getCTypeName` `sf/src/c89_emit.zig:710-728` /
`emitArrayType` `:1833`) is only the (correct) declaration of the array temp and
the global — not the defect. Emit is **rc=0 with 0 target diagnostics (SILENT)**;
only gcc rejects the invalid C.

**Six new corpus dirs** (auto-listed by `scripts/corpus/list_corpus_dirs.sh`):

| dir | class | RED today (`8a322dd9…`) | expected GREEN (Task 2f-F) |
|---|---|---|---|
| `multiarray_index_xmod` | **FAIL** | dump rc=0, 4 `.c`, stderr EMPTY; gcc `assignment to expression with array type`; `zT_8 = zG_g[i];` array=array | dump rc=0, gcc clean, link+run rc=0, no stdout |
| `multiarray_index_const_xmod` | **FAIL** | same; constant `&g[2][0]` / `g[2][3]` | same |
| `multiarray_index_local_xmod` | **FAIL** | same; function-local `[5][4]u8` — PLUS the `undefined`-init array-copy loop `g[_i] = zT_1[_i];` (`c89_emit.zig:5969-5988`) is a SECOND array-to-array site | same |
| `multiarray_index_3d_xmod` | **FAIL** | same; 3-level `[3][4][5]u8` (TWO array temps per access) | same |
| `multiarray_index_struct_control_xmod` | **FAIL** | same; `[5][4]Cell` — the Task-3/Task-4 `client_cells` shape | same |
| `multiarray_index_flat_control_xmod` | **OK** (control) | flat 1D `[20]u8` already emits `zT = zG_g[i];` (scalar) | stays OK |

Verbatim RED evidence (`multiarray_index_xmod`, fixed point `8a322dd9…`):
```
main_B14EE385.c:42:    zT_B5AAF170_Arr_unsigned_char_4 zT_8;
main_B14EE385.c:62:    zT_8 = zG_E20C2606_g[i];
main_B14EE385.c:66:    zT_14 = zG_E20C2606_g[i];
gcc: error: assignment to expression with array type   (x2)
```

**Corpus `-ffast` dump+gcc classifier (`/tmp/t4bf_classify.sh`), 694 dirs:**
universe **688 -> 694** (+6). No `sf/src` change, so the 688 pre-existing dirs
are class-identical by construction. Task-2f-I's own contribution: **+1 OK**
(`multiarray_index_flat_control_xmod`) and **+5 FAIL**
(`multiarray_index_xmod`, `multiarray_index_const_xmod`,
`multiarray_index_local_xmod`, `multiarray_index_3d_xmod`,
`multiarray_index_struct_control_xmod`). Class map: **637 OK / 27 GREEN /
30 FAIL / 0 ICE / 0 CRASH**. **No new diagnostic code** — the defect emits NO
compiler diagnostic at all (silent rc=0); gcc's `assignment to expression with
array type` is the only signal. This is a SILENT-invalid-C pin.

**Fix surface for Task 2f-F** (presented in the task report; no `sf/src` change
here): teach the lowerer's index_access base lowering to DECAY a fixed-array
element to an element pointer (or emit an element address) instead of
materializing an array-typed value — the single common locus is
`sf/src/lower.zig` (`lowerExpr:3080` rvalue, `lowerLValueAddr:1363` address-of,
`lowerAssignLValue:1509` store), covering both index forms and N-level nesting.
The emitter's `emitBaseIdxAccess` array-result emission (`sf/src/c89_emit.zig:189`)
is the defective output but is downstream of the array-typed temp. The local
fixture additionally requires the multi-dim `undefined`-init copy loop
(`sf/src/c89_emit.zig:5969-5988`) to copy leaf elements instead of rows.

## Track-4 Task 2e-F (F) — diagnostic excerpt line FIXED (v109 -> v110 2026-09-16)

Track-4 Task 2e-F fixes the excerpt line-selection defect pinned by Task 2e-I.
**`sf/src` change:** deleted the single extra decrement at
`sf/src/diagnostics.zig:501` (`if (line_idx > 0) line_idx -= 1;`); `line_idx` is
now exactly `mem.binary_search`'s upper_bound-minus-one result, so the excerpt
prints the source line containing `d.span_start`. No change to
`mem.binary_search` (`sf/src/util/mem.zig`) or `source_manager.zig`; the caret
column (`loc.col`) and count (`span_end - span_start`) were already correct.

Reference compiler = the new fixed point
`8a322dd9221077780202e8ac6dd6983a`, rebuilt via the binding seed model
(`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz
/tmp/t2eF_build`). The committed seed predates recent `sf/src` work, so the
closure is the moving point **hop2 == hop3 == `8a322dd9221077780202e8ac6dd6983a`**
(hop1 `9d25d1aa2e993a50311241a69da01b3b`). BASE was `14ffe6b3…`. Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-2e-report.md`.

**Measured GREEN** (fixed compiler) for the three Task-2e-I dirs:
- `diag_excerpt_positions_xmod` — **FAIL** (dump rc=2, 0 `.c`, unchanged): every
  excerpt now shows the span's line (`missing_at_col0.x = 1;` for `33:0`,
  ` missing_at_col1.x = 1;` for `36:1`, `    var y: u32 = middle_line_missing.x;`
  for `39:4`/`39:17`, `    var z: u32 =` for `42:4`, and the previously-missing
  `    var w: u32 = blankprev_missing.x;` excerpts now print for `47:4`/`47:17`).
- `diag_excerpt_line1_xmod` — **FAIL**, RED == GREEN (line-1 control unchanged).
- `diag_excerpt_multifile_xmod` — **OK** (dump rc=0, 5 `.c`, link+run rc=0);
  `mod.zig:6:6` excerpt now prints `    y = missing;` with the caret at col 6.

**Corpus `-ffast` dump+gcc classifier (688 dirs):** BASE vs FIX class map is
**identical** — 636 OK / 27 GREEN / 25 FAIL / 0 ICE / 0 CRASH, per-dir `join`
diff empty. Zero class movement (stderr-rendering only), as predicted.

**Caret-overrun decision (explicit).** The L42 multi-line span keeps its
39-caret run on the 16-char excerpt line (`span_end - span_start` includes the
newline). This is a pre-existing single-line-excerpt cosmetic artifact, identical
in RED and GREEN, does not mask the line off-by-one, and is explicitly LEFT
AS-IS (out of scope for Task 2e-F).

**Gates:** `check_emit_support.sh` 5/5; self-compile closure rc=0, 48 `.c`,
0 `error[`, 0 PANIC; `verify_upgraded.sh` **CLOSEOUT OK**; 4-MD5 runtime
byte-identical (rogue boot `3fb6709e…`, rogue move `b3c5b0e1…`, mud stdout
`66c8f0ab…`, mud client `93147d0f…`). Seed rotation stays at Task 6.

## Track-4 Task 2e-I (I) — diagnostic excerpt wrong-line pinned (v108 -> v109 2026-09-16)

Track-4 Task 2e-I pins the diagnostic-excerpt line-selection defect found by the
Task-2c-F fix round. **No `sf/src` change.** Reference compiler = the Task-2c-F
fix-round-1 fixed point `14ffe6b3d08bb273d74bb92fd9d07c13`, rebuilt via the
binding seed model (`bash scripts/seed/build_from_seed.sh
release/seed/zig1-seed.tgz /tmp/t2e_build`; gate `=== [seed] Done: /tmp/t2e_build
===`). The committed seed predates the recent `sf/src` work, so the closure is
the moving point **hop2 == hop3 == `14ffe6b3d08bb273d74bb92fd9d07c13`** (hop1
`a57734dbe72082b14d0ad981a6ca8c8a`). Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-2e-report.md`.

**Root cause (verified, read-only).** `mem.binary_search`
(`sf/src/util/mem.zig:9-25`) is an upper_bound-minus-one: it returns the index of
the greatest `offsets[i] <= target` — already the 0-based line index.
`sourceManagerGetLocation` (`sf/src/source_manager.zig:155-159`) uses it
correctly (`line = line_idx + 1`, `col = offset - offsets[line_idx]`), so the
`file:line:col` header is right. But `sf/src/diagnostics.zig:500-501` recomputes
`line_idx = binary_search(...)` and then subtracts one again
(`if (line_idx > 0) line_idx -= 1;`). For a span on file line N (N >= 2) the
excerpt prints line N-1. On line 1 the `> 0` guard masks the bug (the excerpt is
correct). When line N-1 is blank the excerpt is skipped entirely
(`l_start == l_end` fails the `:511` guard). Affects every diagnostic's excerpt.

**Three new corpus dirs** (auto-listed by `scripts/corpus/list_corpus_dirs.sh`):

| dir | class | RED today (`14ffe6b3…`) | expected GREEN (Task 2e-F) |
|---|---|---|---|
| `diag_excerpt_positions_xmod` | **FAIL** | dump rc=2, 0 `.c`; col0/col1/mid/multi-line excerpts print the PREVIOUS line; blank-prev diags print NO excerpt | same rc/class; every excerpt = the span's line + caret at `loc.col` |
| `diag_excerpt_line1_xmod` | **FAIL** | dump rc=2, 0 `.c`; line-1 excerpt CORRECT today (control) | unchanged (RED == GREEN) |
| `diag_excerpt_multifile_xmod` | **OK** | dump rc=0, 5 `.c`; `mod.zig:6:6` warning excerpt prints `mod.zig` line 5 | same rc/class; excerpt = `mod.zig` line 6 |

RED excerpts (verbatim) and GREEN contracts are in the task report. The
`line1` fixture keeps its span on file line 1 by putting the explanatory comment
AFTER the code.

**Corpus `-ffast` dump+gcc classifier:** universe **685 -> 688** (+3). No
`sf/src` change, so the 685 pre-existing dirs are class-identical by
construction. Task-2e-I's own contribution: **+2 FAIL**
(`diag_excerpt_positions_xmod`, `diag_excerpt_line1_xmod`) and **+1 OK**
(`diag_excerpt_multifile_xmod`). **No new diagnostic code** — all excerpts are
the pre-existing `error[20]` (`ERR_3001_UNDEFINED_SYMBOL`) / `warning[3000]`
(type-mismatch); no ICE code is used. This is a **stderr-rendering** pin: the
corpus class map does NOT move when Task 2e-F fixes the excerpt (the diagnostics
are real; only the rendered source line changes).

**Fix surface for Task 2e-F:** delete the single extra decrement at
`sf/src/diagnostics.zig:501`. No change to `mem.binary_search` or
`source_manager.zig`; `loc.col` (0-based) and `span_end - span_start` are already
correct (no second off-by-one).

## Track-4 Task 2c-F fix round 1 (F) — cycle depth cap + located error[3050] + header drift (v107 -> v108 2026-09-16)

Fix round on the Task-2c-F work (BASE `9155c74a`, fixed point
`960575b70302c78a19cf6bc0cc129df5`). Closes the two residual gaps found by the
2c-F review plus the declared fixture-header drift. **`sf/src` change** in
`sf/src/type_resolver.zig` + the `TypeResolveEnv` construction sites in
`sf/src/{front_resolution,main,semantic_analyzer,lower,symbol_registrator,comptime_eval}.zig`.

**Finding 1 — const-cycle depth cap.** `evalConstU32Full` gained a `depth: u32`
parameter and a cap mirroring `resolveTypeExprFull` (`depth > 16` →
unfoldable sentinel). The Task-2c-F `binary` case newly enabled
`const A = A + 1` to recurse without bound in array-size position (SIGSEGV,
rc=139); the direct ident cycle `const A = B; const B = A` hung (rc=124). Both
now fold to the sentinel and become the existing hard `error[3050]`.

**Finding 2 — located `error[3050]`.** `TypeResolveEnv` gained
`source_file_id: u32`; the module-iterating passes (`resolveFnSignatures`,
`resolveAggregateFieldTypesAll`, `resolveNamedTypeExpressions`) set it per
module, `front_resolution.resolveTypeExpr`/`resolveStmtTypes` thread it (from
`mods[mi].source_file_id`), and sema sites use `self.source_file_id`. The
array-size fallback passes `env.source_file_id` instead of the hardcoded `0`, so
the diagnostic now renders the filename/line/column of the size expression
(previously `file_id == 0` rendered bare).

**Finding 3 — fixture headers.** All five `const_size_*` fixture headers were
updated from the 2c-I "RED today" state to the post-fix GREEN contract;
`const_size_member_xmod` now records the actual **4** `.c` (the 2c-I contract
line said 5).

**New fixture `const_size_cycle_xmod`** (`const A = A + 1; var x: [A]u8`):
- RED (BASE `960575b7`): `zig1 -ffast --dump-c89` → **rc=139 SIGSEGV** (ICE), 0 `.c`.
- GREEN (fix round 1): **rc=2, 0 `.c`**, and (located)
  `repro/mi_matrix/const_size_cycle_xmod/main.zig:24:8: error[3050]: array size is not a constant expression`.
  Never `error[3042]`/`error[3043]` (ICE), never silent invalid C.

Located-error evidence (`const_size_unfoldable_xmod`, `[N]u8` at col 8):
```
repro/mi_matrix/const_size_unfoldable_xmod/main.zig:24:8: error[3050]: array size is not a constant expression
```

**Build (fixed point MOVES).** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t2cF_fix1_build`:
hop1 `a57734dbe72082b14d0ad981a6ca8c8a`, hop2 == hop3 ==
**`14ffe6b3d08bb273d74bb92fd9d07c13`** (three-hop moving-point closure).
BASE `960575b70302c78a19cf6bc0cc129df5` → **NEW
`14ffe6b3d08bb273d74bb92fd9d07c13`**. Compiler under test =
`/tmp/t2cF_fix1_build/zig1_5_clean`.

**Six `const_size_*` fixtures** (all with the fixed compiler): `arith`,
`member`, `local`, `inline_ctrl` → dump rc=0, 4 `.c`, gcc clean, link+run rc=0,
no stdout; `unfoldable` and `cycle` → dump rc=2, 0 `.c`, located `error[3050]`.

**Corpus `-ffast` dump+gcc classifier (`/tmp/t4bf_classify.sh`), 685 dirs:**

| | BASE `960575b7` | fix round 1 `14ffe6b3` | delta |
|---|---|---|---|
| dirs | 685 | 685 | 0 |
| OK | 635 | 635 | 0 |
| GREEN | 27 | 27 | 0 |
| FAIL | 22 | 23 | +1 |
| ICE | 0 | 0 | 0 |
| CRASH | 1 | 0 | −1 |

Per-dir `join` diff = **exactly** `const_size_cycle_xmod` CRASH→FAIL (the new
fixture's RED→clean-error transition). All 684 other dirs class-identical.

**Emit-support / self-compile / goldens.**
- `bash scripts/check_emit_support.sh /tmp/t2cF_fix1_build/zig1_5_clean` → **5/5** byte-identical.
- Self-compile: rc=0, **48 `.c`**, 0 `error[3000]`, 0 errors, 0 PANIC.
- `bash scripts/closeout/verify_upgraded.sh /tmp/t2cF_fix1_build/zig1_5_clean` → **`CLOSEOUT OK`** (A1–A5, B1–B7).
- 4-MD5 runtime byte-identical: gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`, lisp `8dc783a3d766430c15993ab08cd0f7ec`, json `8bda3d5a1ec07d14a301bc343df32bf8`, mud_server stdout `66c8f0abb926cca7baf9a0d1692ab318`, client bytes `93147d0f0bbd983a9d844fea8b7a6fa7`; rogue boot `3fb6709e7bbd8964ef12aa9c906c0577`, rogue move `b3c5b0e1308bc9a4efde238376c14d9f`.
- No seed rotation.


## Track-4 Task 2c-F (F) — const-expression array sizes FIXED (v106 -> v107 2026-09-16)

Track-4 Task 2c-F closes the array-size const-expression gap pinned by Task 2c-I.
**`sf/src` change** in four files: `sf/src/type_resolver.zig`, `sf/src/diagnostics.zig`,
`sf/src/semantic_analyzer.zig`, `sf/src/front_resolution.zig` (+ the `TypeResolveEnv`
literal-update sites in `main.zig`/`lower.zig`/`symbol_registrator.zig`/`comptime_eval.zig`).
Full report: `.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-2c-report.md`.

**What landed.**
1. **Fold** (`evalConstU32Full`): a `binary` case (`add/sub/mul/div/mod_op`, with the
   `0xFFFFFFFF` unfoldable sentinel and div/mod-by-zero guarded) and a `negate` case
   (`0 - v`). The existing `ident_expr`/`field_access` recursion then folds
   `const C = A * B`, nested `A * B + 2`, and `const C = mid.leaf.HEADER_SIZE * 2`.
2. **Hard-error fallback**: new `ERR_3050_ARRAY_SIZE_NOT_CONSTANT = 3050`
   (`sf/src/diagnostics.zig`); emitted from the `array_type` arm when `arr_resolved`
   is still false, via an optional `diag` handle threaded into `TypeResolveEnv`
   (`[_]T` inferred length is exempt). Emission is deduped per node
   (`DiagnosticCollector.diag_seen` + `diagnosticCollectorMarkNodeOnce`), because
   front_resolution and sema both resolve the same size node.
3. **Variant (e)**: a function-local `const` scope (`LocalConstScope`: name -> decl
   node) is threaded into `TypeResolveEnv` (`local_consts`), populated in source order
   by both `front_resolution.resolveStmtTypesRec` (block-scoped push/pop) and the sema
   var-decl arm, and consulted in `evalConstU32Full`'s `ident_expr` arm before the
   module symbol tables. A function-body `const N = A * B; var x: [N]u8` now folds.

**Build (binding seed model; fixed point MOVES).**
```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t2cF_build
[seed] hop1 binary md5: af9d47d6d0e8cf34dd72178535e3ce07
[seed] hop2 binary md5: 960575b70302c78a19cf6bc0cc129df5
[seed] hop3 binary md5: 960575b70302c78a19cf6bc0cc129df5
[seed] three-hop closure OK (moving point): hop2 == hop3 == 960575b70302c78a19cf6bc0cc129df5
```
BASE fixed point `0da3f1391075e3e77c54b626d5550e3b` → **NEW fixed point
`960575b70302c78a19cf6bc0cc129df5`** (hop2 == hop3; the committed seed predates the
current `sf/src`, so hop1 differs). Compiler under test = `/tmp/t2cF_build/zig1_5_clean`
(the hop1 binary, whose sibling `lib/` carries the 9 std modules).

**Fixtures RED → GREEN** (`-ffast --dump-c89`; gcc `-m32 -std=c89`; link+run):

| fixture | RED (base `0da3f139…`) | GREEN (fix `960575b7…`) |
|---|---|---|
| `const_size_arith_xmod` | dump rc=2, 0 `.c`; `error[20]` ×6 | dump rc=0, 4 `.c`, gcc clean, link+run rc=0, no stdout |
| `const_size_member_xmod` | dump rc=2, 0 `.c`; `error[20]` | dump rc=0, 4 `.c`, gcc clean, link+run rc=0, no stdout |
| `const_size_local_xmod` | dump rc=2, 0 `.c`; `error[20]` | dump rc=0, 4 `.c`, gcc clean, link+run rc=0, no stdout |
| `const_size_unfoldable_xmod` | dump rc=0, 4 `.c`, **stderr empty (SILENT invalid C)**; gcc FAIL | **hard `error[3050]`**, dump rc=2, 0 `.c` |
| `const_size_inline_ctrl_xmod` | OK | OK (no regression) |

Hard-error evidence: `error[3050]: array size is not a constant expression`
(dump rc=2, 0 `.c`). No silent invalid C.

**Corpus `-ffast` dump+gcc classifier (`/tmp/t4bf_classify.sh`), 684 dirs:**

| | base `0da3f139…` | fix `960575b7…` | delta |
|---|---|---|---|
| dirs | 684 | 684 | 0 |
| OK | 632 | 635 | +3 |
| GREEN | 27 | 27 | 0 |
| FAIL | 25 | 22 | −3 |
| ICE | 0 | 0 | 0 |
| CRASH | 0 | 0 | 0 |

**Per-dir movement = exactly the three intended dirs** (`join` diff):
`const_size_arith_xmod` FAIL→OK, `const_size_local_xmod` FAIL→OK,
`const_size_member_xmod` FAIL→OK. All 681 other dirs are class-identical (zero
regression). `const_size_unfoldable_xmod` stays **FAIL** (now a hard frontend
`error[3050]` instead of gcc-side invalid C) — the intended contract.

**Emit-support / self-compile / goldens.**
- `bash scripts/check_emit_support.sh /tmp/t2cF_build/zig1_5_clean` → **5/5** support files byte-identical.
- Self-compile: `zig1_5_clean -ffast --dump-c89 --output-dir … sf/src/main.zig` → rc=0, **48 `.c`**, 0 `error[3000]`, 0 PANIC, 0 errors.
- `bash scripts/closeout/verify_upgraded.sh /tmp/t2cF_build/zig1_5_clean` → **`CLOSEOUT OK`** (A1–A5, B1–B7; lisp `96654b39`, rogue q `3fb6709e`, rogue move `b3c5b0e1`, rogue demo `7361d248`, net `aa40a52e`).
- 4-MD5 runtime byte-identical (`/tmp/t4p_rt.sh`): gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`, lisp `8dc783a3d766430c15993ab08cd0f7ec`, json `8bda3d5a1ec07d14a301bc343df32bf8`, mud_server stdout `66c8f0abb926cca7baf9a0d1692ab318`, mud_server client bytes `93147d0f0bbd983a9d844fea8b7a6fa7`.
- No seed rotation (Task 6 owns rotation).


## Track-4 Task 2c-I (I) — const-expression array sizes pinned (v105 -> v106 2026-09-16)

Track-4 Task 2c-I pins the array-size const-expression gap found by Task 3 (S11).
**No `sf/src` change.** Reference compiler = the Task-2b-F fixed point
`0da3f1391075e3e77c54b626d5550e3b`, rebuilt via the binding seed model
(`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t2c_build`;
gate `=== [seed] Done: /tmp/t2c_build ===`). The committed seed predates the
Task-2b-F `sf/src` work, so the closure is the moving point
**hop2 == hop3 == `0da3f1391075e3e77c54b626d5550e3b`** (hop1
`db278e61385ab79b70619a03e89e387f`). Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-2c-report.md`.

**Root cause (verified, read-only).** `resolveTypeExprFull`'s `array_type` arm
(`sf/src/type_resolver.zig:1109-1173`) resolves the size via `evalConstU32Full`
(`:744`). That evaluator handles `int_literal`, `ident_expr`, and (Task 2b-F)
`field_access` — **no `binary` case**. A module-level `const C = A * B` recurses
from the `ident_expr` arm into its initializer (a `binary` node), returns
`0xFFFFFFFF`, `arr_resolved` stays false, and the arm returns `TYPE_UNDEFINED`
(`:1173`) with no diagnostic. The arm already folds **inline** add/sub/mul/div/mod
directly (`:1123-1139`), so only the const-behind-an-expression case is broken.
Variant (e) (function-local const size) additionally needs the enclosing
function's local-const scope threaded in: `evalConstU32Full`'s `ident_expr` arm
resolves via `symbolLookupAllModules` (`:815`) — module symbol tables only; a
function-local `const` is a local `var_decl` and is never registered there.
`TypeResolveEnv` (`:26-33`) carries no diagnostics handle, so the fallback error
must be emitted in sema/front_resolution (where `diag` exists) or the handle
threaded into `TypeResolveEnv`. Operator ruling (2026-09-16): the fallback is a
**hard error** `ERR_3050_ARRAY_SIZE_NOT_CONSTANT` (explicit numeric 3050 per
`sf/src/diagnostics.zig`), and variant (e) is IN scope for Task 2c-F.

**Five new corpus dirs** (auto-listed by `scripts/corpus/list_corpus_dirs.sh`):

| dir | class | RED today (fixed point 0da3f139…) | expected GREEN (Task 2c-F) |
|---|---|---|---|
| `const_size_arith_xmod` | **FAIL** | dump rc=2, 0 `.c`; `error[20]: identifier '<xc..xh>' is not declared or imported in this module` ×6 (one per `[C]/[D]/[E]/[F]/[G]/[H]` array) | sizes fold (`C`=16, `D`=8, `E`=0, `F`=1, `G`=0, `H`=18); dump rc=0, gcc clean, link+run rc=0, no stdout |
| `const_size_member_xmod` | **FAIL** | dump rc=2, 0 `.c`; `error[20]: identifier 'x' is not declared or imported in this module` (`const C = mid.leaf.HEADER_SIZE * 2; [C]u8`) | `C` folds to 32; dump rc=0, 5 `.c`, gcc clean, link+run rc=0, no stdout |
| `const_size_local_xmod` | **FAIL** | dump rc=2, 0 `.c`; `error[20]: identifier 'x' is not declared or imported in this module` (function-local `const N = A * B; [N]u8`) | `N` folds to 16; dump rc=0, 4 `.c`, gcc clean, link+run rc=0, no stdout |
| `const_size_unfoldable_xmod` | **FAIL** | dump rc=0, 4 `.c`, **stderr empty (SILENT)**; module global degrades to `int zG_..._g;`; gcc then fails `subscripted value is neither array nor pointer nor vector` + `'zT_4' undeclared` | hard `error[3050]` rc=2, 0 `.c` — never silent invalid C |
| `const_size_inline_ctrl_xmod` | **OK** (control) | dump rc=0, 4 `.c`, gcc clean, link+run rc=0 (inline `[A*B]u8`, literal `[16]u8`, direct module ident `[N]u8` already fold) | stays OK (no regression) |

The `const_size_unfoldable_xmod` shape is the exact Task-3 S11 observation: the
size expression does not fold, the array type is `TYPE_UNDEFINED`, the compiler
emits no frontend diagnostic, and only gcc catches the invalid C. The same shape
as a function-local array that is later used instead reports `error[20]` on the
use (a misleading downstream symptom, not the `ERR_3050` contract).

**Corpus `-ffast` dump+gcc classifier (`/tmp/t4bf_classify.sh`, the Task-2b-F
classifier).** Baseline (678 dirs, v105 = `0da3f139…`): **630 OK / 27 GREEN /
21 FAIL / 0 ICE / 0 CRASH**. Current working tree (684 dirs): **632 OK /
27 GREEN / 25 FAIL / 0 ICE / 0 CRASH**. The **678 pre-existing dirs are
class-identical (zero movement)**; the +6 dirs are Task 3's
`async_client_cells_xmod` (OK, added after v105) plus the five Task-2c-I dirs.
Task-2c-I's own contribution: **+1 OK** (`const_size_inline_ctrl_xmod`) and
**+4 FAIL** (`const_size_arith_xmod`, `const_size_member_xmod`,
`const_size_local_xmod`, `const_size_unfoldable_xmod`). No `sf/src` change, so
zero pre-existing movement by construction. **No new diagnostic code is
introduced by Task 2c-I** (fixtures only); Task 2c-F introduces
`ERR_3050_ARRAY_SIZE_NOT_CONSTANT`.

## Track-4 Task 2b-F (F) — residual codegen gaps #9/#5/#1 FIXED (v105 2026-09-16)

Track-4 Task 2b-F closes the three residual gaps pinned by Task 2b-I. **`sf/src`
change** in three files: `sf/src/async_frame_layout.zig` (#9), `sf/src/lower.zig`
(#5), `sf/src/type_resolver.zig` (#1). No seed rotation (`zig0` never invoked).

**Fixed point MOVED** `43d41bfb903d56c153ebf653131aef6d` →
**`0da3f1391075e3e77c54b626d5550e3b`** (three-hop closure hop2 == hop3 from the
committed seed; hop1 `db278e61385ab79b70619a03e89e387f`).

- **#9 — loop-carried local across `@asyncSuspend` now persisted.**
  `async_frame_layout.zig` `hasReadAfter` is now CFG-aware: it keeps the original
  linear scan (strictly additive — no narrowing) and adds a successor worklist
  (`cfgPushSuccessors`, following jump/branch/switch targets and loop back-edges;
  fallthrough when a block is not terminated). A block reached via a back-edge is
  scanned in full, so a local read only on the next loop iteration is marked LIVE
  and added as `ASYNC_FIELD_LIVE`; the existing `saveAllFields`/`reloadAllFields`
  persist it. `async_live_local_across_suspend_xmod` runtime-RED → **run rc=0**
  (`out.a == 8`, `out.b == 800`, no stdout). Emitted evidence: `__Z98Step_coA`
  base saved only `out`@12 / `i`@16; now `n` is saved at frame offset 16 and
  reloaded on resume. (The fixture's compile-only class stays **OK** — its RED was
  runtime-only.)
- **#5 — `&mid.leaf.counter` (address of a module global) now supported.**
  `lowerLValueAddr`'s `field_access` arm detects a module base via
  `resolveModuleBase`, looks up the member `SymbolKind.global`, and emits
  `load_global` + `addr_of` (no new LIR op). `module_value_addr_global_xmod`
  **ICE → OK** (`error[3043]` gone). Emitted: `zT_2 = &zG_9CACDE23_counter;`.
- **#1 — field-access const in array-size position now folded.**
  `type_resolver.zig` `evalConstU32Full` gained a `field_access` arm
  (`evalConstModuleOfExpr` walks the module-alias chain via
  `symbolRegistryQualifiedLookup` and folds the member const initializer); the
  `array_type` arm gained an `else` const-eval fallback. `module_value_arraysize_xmod`
  **FAIL → OK** (`error[20]` gone; `a.len` folds to 16). Q6 variants a
  (`[leaf.HEADER_SIZE]`), b (`[mid.leaf.HEADER_SIZE]`), and d (module-level
  `const N = mid.leaf.HEADER_SIZE`) are GREEN.

**Declared residual (operator-ruled out of Task 2b-F scope, 2026-09-16):**
function-local `const N = <expr>; [N]` used as an ARRAY SIZE still fails
`error[20]`. This is **nesting-independent** and **unreachable from the #1 fix
locus**: the control `const N = 16; var a: [N]u8` (a literal, no module
involvement) fails `error[20]` identically on both the base `43d41bfb` and the
fix `0da3f139`; `TypeResolveEnv` (`sf/src/type_resolver.zig:26`) carries no local
scope and `evalConstU32Full` resolves identifiers via `symbolLookupAllModules`
(module symbol tables only — a function-local `const` is parsed as a local
`var_decl` and never registered there). Fixing it needs **local-const scope
threading into the type resolver**, a separate subsystem. Not to be attempted in
Task 2b-F. The `module_value_arraysize_xmod` fixture header carries the same
note. (Q6 variant e; the plan's #1 is specifically the non-literal / field-access
array-size expression, variants a/b/d.)

**Corpus `-s0` sweep (678 dirs, dump+gcc classifier):** base (43d41bfb) 628 OK /
27 GREEN / 22 FAIL / 1 ICE / 0 CRASH → fix (0da3f139) 630 OK / 27 GREEN / 21 FAIL
/ 0 ICE / 0 CRASH. The ONLY per-dir movement is `module_value_addr_global_xmod`
(ICE→OK) and `module_value_arraysize_xmod` (FAIL→OK); all 676 other dirs are
class-identical (zero regression). `check_emit_support.sh` 5/5; self-compile
closure 48 `.c`, 0 `[3000]`, 0 gcc errors; `verify_upgraded.sh` → `CLOSEOUT OK`;
rogue boot `3fb6709e…` / move `b3c5b0e1…` and mud_server stdout `66c8f0ab…` /
client bytes `93147d0f…` byte-identical.

## Track-4 Task 2b-I (I) — residual codegen gaps #9/#5/#1 pinned (v104 2026-09-16)

Track-4 Task 2b-I pins the three residual codegen gaps declared after Task 2a/Task 2
and presents the fix surface for Task 2b-F. **No `sf/src` change.** Reference compiler =
the Task-2a-F fixed point `43d41bfb903d56c153ebf653131aef6d`, rebuilt via the seed model
(`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t4b_i_build`; gate
`=== [seed] Done ===`). The committed seed (v19) predates Task 2a-F, so hop1
(`zig1_5_clean`) md5 `160bff6f500b8a85762f3f9f45a41092` differs from the closure; the
compiler under test is the closure binary hop2 == hop3 == `43d41bfb…`
(`/tmp/t4b_i_build/hop2/zig1_hop2`). Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-2b-report.md`.

**Two new corpus dirs (auto-listed by `scripts/corpus/list_corpus_dirs.sh`):**

| dir | class | RED today (fixed point 43d41bfb…) | expected GREEN (Task 2b-F) |
|---|---|---|---|
| `async_live_local_across_suspend_xmod` | **OK** (compile-clean) — runtime-RED | dump rc=0, 4 `.c`, gcc clean, link rc=0, **run rc=133** (SIGTRAP) stderr `panic: async_live_local_across_suspend_xmod: coA counter not preserved` | run rc=0, `out.a == 8`, `out.b == 800`, no stdout |
| `module_value_addr_global_xmod` | **ICE** | dump rc=3, 0 `.c`, `warning[3023]: module used as value expression` + `error[3043]: internal: unsupported address-of l-value (node 7)` | dump rc=0, 5 `.c`, gcc clean, link+run rc=0, no stdout |

**#9 (DANGEROUS) — loop-carried local not persisted.**
`async_live_local_across_suspend_xmod` has two interleaved coroutines, each with a
loop-carried accumulator (`n`/`m`) mutated and read across an explicit `@asyncSuspend`
inside a `while`. The accumulator is read only via the loop back-edge, never after the
suspend in LINEAR block order, so P3 `hasReadAfter` (`sf/src/async_frame_layout.zig:373-384`)
does not mark it LIVE; it is absent from the P3 layout (`:481-519`) and
`saveAllFields`/`reloadAllFields` (`sf/src/async_state_machine.zig:253-279`) never persist
it. The emitted step function saves only `out` (offset 12) and the loop counter `i`
(offset 16); on resume `n` is an uninitialized C local. **Failure mode = silent value loss
→ the fixture's own assert panics (rc=133).** NOT a frame mis-size (P2's `scanFrameLocals`
over-reserves every node, so the frame is large enough) and NOT a save/reload emission bug
(the emission faithfully persists every field P3 marks LIVE). The interleave is required:
a SINGLE coroutine alone can pass by stack-slot reuse; the interleaved second coroutine
(same stack slot) makes the lost accumulator deterministic (5/5 runs panic). See report
Q1-Q4.

**#5 — `&mid.leaf.counter` (address of a nested module global).** The l-value ADDRESS path
`lowerLValueAddr` (`sf/src/lower.zig:1360`; field_access arm `:1399-1448`) has no
module-base handling: the base `mid.leaf` is a `module_type`, the struct/union field lookup
misses, and `iceAddrOfLValueUnsupported` (`:1341`) fires. The same ICE fires for a 1-level
DIRECT import `&leaf.counter` (nesting-independent) — the gap is the missing
address-of-a-module-global path. Same-module `&g` already works via `load_global` +
`addr_of`. See report Q5.

**#1 — non-literal / field-access array-size expression (KEPT as the #1 pin).**
`module_value_arraysize_xmod` stays **FAIL**: `var a: [mid.leaf.HEADER_SIZE]u8` is rejected
at type-resolution time with `error[20]: identifier 'a' is not declared or imported in this
module` (dump rc=2, 0 `.c`). NESTING-INDEPENDENT (`[leaf.HEADER_SIZE]` direct-import fails
identically). Root cause: `evalConstU32Full` (`sf/src/type_resolver.zig:695-714`) handles
only `int_literal` / `ident_expr`; the `array_type` arm (`:1042-1097`) has no `field_access`
case, so the size never resolves. A module-level literal const `[N]u8` is GREEN;
`const N = <module member>` is RED (the recursive ident path hits the same missing
`field_access` arm). See report Q6.

**Corpus delta.** Canonical `scripts/corpus/list_corpus_dirs.sh` universe **676 → 678**
(+2). The v103 entry's 675 predates Task 2's addition of `async_frame_lifetime_xmod`
(`a4e2364f`). Class delta vs the 676 pre-existing dirs: **+1 OK** (the #9 fixture is
compile-clean) and **+1 ICE** (the #5 fixture). No `sf/src` change, so the 676 pre-existing
dirs are class-identical (zero movement). `error[3043]` is in the classifier ICE regex; the
#9 fixture's runtime-RED is invisible to the compile-only classifier (recorded here as a
declared runtime-RED expected-fail).

## Track-4 Task 2a-F (F) — nested module value-position gap FIXED (v103 2026-09-16)

Task 2a-F closes the Task 2a-I gap. **`sf/src` change** (`sf/src/lower.zig` only;
no sema/type-resolver change): the field-access value path and the field-store
path now resolve a nested module-alias base (or a module-typed global) to its
owning module and emit the member, via two new helpers
`resolveModuleBase` (`sf/src/lower.zig:2400`) and `lowerModuleMemberValue`
(`:2427`). The existing direct-module ident path is refactored to call the same
member emit; the call-path chain walk (`:3787-3813`) is unchanged. The l-value
store is handled in `lowerFieldStore` (`:1708`) by emitting `store_global`
directly (no address is taken).

**Fixed point MOVED** `286c9011691ccd39403534019baa12c6` →
**`43d41bfb903d56c153ebf653131aef6d`** (three-hop closure hop2 == hop3 from the
committed seed; seed rotation stays at Task 6, `zig0` not invoked).

**Nine pinned ICE dirs RED → OK** (dump rc=0, 5 `.c`, gcc -m32 -std=c89 clean,
link+run rc=0, no stdout):
`module_value_pos_xmod`, `module_value_scalar_xmod`, `module_value_types_xmod`,
`module_value_enum_member_xmod`, `module_value_var_xmod`,
`module_value_varstore_xmod`, `module_value_alias3_xmod`,
`module_value_alias2alias_xmod`, `module_value_positions_xmod`. The three
controls (`module_value_direct1_xmod`, `module_value_fncall_xmod`,
`module_value_local_xmod`) stay OK.

**Residual declared gaps (unchanged):**
- `module_value_arraysize_xmod` stays **FAIL**: a non-literal / field-access
  expression in ARRAY-SIZE position is rejected earlier (`error[20]`), which is
  NESTING-INDEPENDENT (a 1-level direct import fails identically; a module-level
  named const `[N]u8` is GREEN). Out of 2a-F scope; the fixture header documents
  the corrected blocker.
- Address-of a module global through a nested alias (e.g.
  `&mid.leaf.counter`) is not pinned; no `addr_of_global` LIR instruction
  exists, so the store is intercepted before the l-value path. Not exercised by
  any corpus dir.

**Corpus `-s0` sweep (675 dirs, dump classifier):** baseline 621 OK / 27 GREEN /
18 FAIL / 9 ICE / 0 CRASH → 630 OK / 27 GREEN / 18 FAIL / 0 ICE / 0 CRASH. The
ONLY per-dir movement is the nine `module_value_*` ICE→OK flips; all 662
pre-existing dirs are class-identical (zero movement). (`check_emit_support.sh`
5/5; `verify_upgraded.sh` → `CLOSEOUT OK`.)

## Track-4 Task 2a-I (I) — nested module value-position access gap pinned (v101; fix round 1 v102 2026-09-16)

Track-4 Task 2a-I pins the pre-existing `std.async` value-position gap that
blocks Tasks 2/4/5 (which read `std.async.HEADER_SIZE`). **No `sf/src` change.**
Reference compiler = the Task-0q3 fixed point
`286c9011691ccd39403534019baa12c6`; tested binary `/tmp/t4a_ref/zig1_5_clean`
md5 `8c4900dc8980c00c085049970246500d`. The gap is the deferred item **"Amendment 7,
Res 4"** in
`docs/superpowers/specs/2026-09-13-async-prelude-and-feasibility-design.md:474`
(also `2026-09-13-std-async-design.md:407`). Fix is Task 2a-F (fixed point MOVES).

**Shape.** A member read/write whose base is a NESTED module alias
(`std.async.HEADER_SIZE`, `mid.leaf.X`). The lowerer's field-access path lowers
the base as a value; only a DIRECT module ident is recognized as a module
reference (`sf/src/lower.zig:3311-3348`/`:3400-3416`; sema
`sf/src/semantic_analyzer.zig:498-553`/`:659`; type resolver
`sf/src/type_resolver.zig:892`). A nested alias yields `TEMP_NONE` +
`warning[3023]` (`:3124-3128`) then `error[3042]` (`:3352-3359`). The l-value
path (`lowerLValueAddr` `sf/src/lower.zig:1399-1448`) yields `error[3043]`.

**Thirteen new corpus dirs** (each has `main.zig`; the fixture-local ones bundle
`leaf.zig`/`mid.zig`/`mid2.zig`):

| dir | class | diagnostic (current) |
|---|---|---|
| `module_value_pos_xmod` (MINIMAL, `std.async.HEADER_SIZE`) | **ICE** | `error[3042]` + `warning[3023]` |
| `module_value_scalar_xmod` (fixture-local 2-level scalar) | **ICE** | `error[3042]` + `warning[3023]` |
| `module_value_types_xmod` (8 const value types) | **ICE** | `error[3042]`×8 + `warning[3023]`×8 |
| `module_value_enum_member_xmod` | **ICE** | `error[3042]` + `warning[3023]` |
| `module_value_var_xmod` (`pub var` read) | **ICE** | `error[3042]` + `warning[3023]` |
| `module_value_varstore_xmod` (`pub var` store) | **ICE** | `error[3043]` + `warning[3023]` |
| `module_value_alias3_xmod` (3-level alias) | **ICE** | `error[3042]` + `warning[3023]` |
| `module_value_alias2alias_xmod` (`const x = mid.leaf`) | **ICE** | `error[3042]` (no `warning[3023]`) |
| `module_value_positions_xmod` (call-arg/return/arith) | **ICE** | `error[3042]`×3 + `warning[3023]`×3 |
| `module_value_arraysize_xmod` (array-size position) | **FAIL** | `error[20]` (UNRELATED non-literal / field-access array-size expression gap; NESTING-INDEPENDENT — a 1-level direct import fails identically; a module-level named const `[N]u8` is GREEN) |
| `module_value_fncall_xmod` (function via 2-level alias control) | **OK** | — (GREEN today) |
| `module_value_direct1_xmod` (1-level DIRECT import control) | **OK** | — (GREEN today) |
| `module_value_local_xmod` (module-local `pub const` control) | **OK** | — (GREEN today) |

`error[3042]`/`error[3043]` are in the classifier ICE regex
(`error\[(48|3042|9001|3043)\]`, `docs/sf/QUICK_REF.md`), so the nine 3042/3043
dirs bucket as **ICE**, not FAIL; `module_value_arraysize_xmod` is an ordinary
**FAIL** (`error[20]`, not in the ICE regex). The nine ICE dirs are expected
compile-fails that MUST flip to **OK** in Task 2a-F; the arraysize dir additionally
needs the unrelated non-literal / field-access array-size expression gap closed
(NOT a named-const gap — a module-level named const is accepted).

**Corpus `-s0` universe 662 → 675 dirs = 617 OK / 27 GREEN / 22 FAIL / 9 ICE /
0 CRASH.** Delta vs v100 (`662 = 614 OK / 27 GREEN / 21 FAIL / 0 ICE / 0 CRASH`)
is EXACTLY the thirteen new dirs: +3 OK, +1 FAIL, +9 ICE; the 662 baseline dirs
are class-identical (zero movement). Fix round 1 corrected the array-size wording
and added the `module_value_fncall_xmod` control (v101 recorded 674 dirs /
616 OK before that control).

## Task 0q3 (F) — promote enum→int at return/call-argument (v100 2026-09-16)

Track-4 Task 0q3 closes the residual declared by Task 0q (its gap #1, enum half).
enum→integer is now a hard `error[3000]` (rc=2, 0 `.c`) at **return and
call-argument** positions in addition to var-decl/assignment. Two changes:

- **Migrate the compiler's own 7 enum call-arg sites** (all
  `itoa(<enum>.kind, ...)`, target `u32`; `sf/src/util/itoa.zig:1`
  `pub fn itoa(value: u32, buf: []u8) u32`) to
  `@intCast(u32, @enumToInt(<enum>.kind))` — the established idiom
  (`symbol_registrator.zig:343`): `sf/src/lower.zig:3914` (`sm.kind`), `:4007`
  (`callee_cn.kind`), `:5686` (`cond_n.kind`), `:5752` (`cond_node_k.kind`);
  `sf/src/parser.zig:1715` (`cond_n.kind`), `:1722` (`cn1.kind`), `:1725`
  (`cn2.kind`).
- **Drop the `full and` guard** on the enum shape in `isBShapeMismatch`
  (`sf/src/semantic_analyzer.zig`), so the return (`:1430`) and call-argument
  (`:1509`/`:1583`) sites promote enum→int. Those sites still pass
  `full=false`, which now only excludes bare `*T` -> `[*]T`.

**Pins (off-corpus, `repro/mi_matrix/known_excluded/`, excluded from the
corpus universe by `scripts/corpus/list_corpus_dirs.sh`):**
- `w3000_enum_return` — `return E.B;` from a `u32` fn → rc=2, 0 `.c`,
  `error[3000]: type mismatch in return statement` (source: enum / target: u32).
- `w3000_enum_carg` — `g(E.B)` with `g(x: u32)` → rc=2, 0 `.c`,
  `error[3000]: type mismatch in function argument` (source: enum / target: u32).
- `w3000_manyptr_retained` — bare `*u8` -> `[*]u8` at return AND call-argument
  (plus the valid `&arr[0]` array→pointer idiom) → dump rc=0, gcc-clean,
  run rc=0, stdout `4` (proves the retained residual below).

**Gates (seed-built compiler `/tmp/t0q3_build/zig1_5_clean`, closure
`hop2 == hop3 == 286c9011691ccd39403534019baa12c6`):** self-compile 48 `.c`,
rc=0, 0 `error[3000]` / 0 `warning[3000]`; pinned `(a)` census `39 dirs / 0`
(exit 0); the 5 `(b)` corpus dirs still hard-error (rc=2, 0 `.c`, 1
`error[3000]` each); per-dir corpus class map byte-identical to the post-0q
baseline (`662 = 614 OK / 27 GREEN / 21 FAIL / 0 ICE / 0 CRASH`); 4-MD5 runtime
byte-identical (gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`, lisp
`8dc783a3d766430c15993ab08cd0f7ec`, json `8bda3d5a1ec07d14a301bc343df32bf8`,
mud server `66c8f0abb926cca7baf9a0d1692ab318` / client
`93147d0f0bbd983a9d844fea8b7a6fa7`); `CLOSEOUT OK`. Fixed point MOVES
`7c12619c276e0989c29f27cb4c81d748` -> `286c9011691ccd39403534019baa12c6`.
No re-baseline; seed NOT rotated (Task 6).

**Declared residual (NOT marked minor):** bare `*T` -> `[*]T` remains tolerated
at **return/call-argument** (var-decl/assignment still promote it). The
compiler's own source relies on this shape there via the valid `&arr[0]`
array→pointer idiom (`docs/reference/Language_Spec_Z98.md:382`, explicitly
allowed at call-arg/return), so promoting it would break self-hosting; it is
out of Task 0q3 scope (see the Task-0q2/0q3 reports). enum→int is no longer part
of this residual.

## Task 0q (F) — promote the 12 `(b)` invalid-Zig cases to hard `error[3000]` (v99 2026-09-16)

Track-4 Task 0q is the FINAL step of the `warning[3000]` series (0l-0q). The 48
`(a)` valid-Z98 false positives were cleared by Task 0m; Task 0n migrated the 7
self enum->int sites to `@intCast(T, @enumToInt(...))`. This task promotes the
`(b)` invalid-Zig shapes to a hard `error[3000]` (rc=2, 0 `.c`) **scoped to those
shapes only** so no `(a)` case is caught.

**Sites** (`sf/src/semantic_analyzer.zig`):
- var-decl `semanticAnalyzerResolveStmtIter` (the `level` at the `it`/`decl_type` mismatch).
- assignment `semanticAnalyzerResolveAssign` (the `level` at the `eff_src`/`lhs` mismatch).
- return `resolveReturnStmt` (new `(b)`-scoped `error[3000]`).
- call-arg `semanticAnalyzerResolveFnCall` (both the direct-call and fn-pointer paths; new `(b)`-scoped `error[3000]`).
- The shape test is `isBShapeMismatch(self, src, tgt, full)`: bare `*T`->`[]T`, bare
  `*T`->`[*]T`, array element/length mismatch, error-set superset->subset, and
  enum->integer without `@enumToInt`. Callers guard with `!typeRegistryIsAssignable`.
- **Dedupe**: `sf/src/type_registry.zig` had a DUPLICATE `ptr_type -> slice_type`
  assignability block (after the array-pointee block) that still accepted a bare
  `*const u8 -> []const u8`; it is **deleted** (whole block). After deletion the
  remaining array-pointee block is the only ptr->slice acceptance.

**Promoted corpus dirs (5) — now hard `error[3000]`, 0 `.c`:**

| dir | site | exact diagnostic |
|---|---|---|
| `eu_assign_incompat_errorset` | assignment | `main.zig:1:101 error[3000] type mismatch in assignment` — source: error-union / target: error-union (`error{X,Y}` -> `error{X}`) |
| `ptr_scalar_to_manyptr_xmod` | var-decl | `main.zig:18:4 error[3000] type mismatch in variable declaration` — source: pointer / target: many-pointer |
| `typealias_arr_elem_mismatch_xmod` | var-decl | `main.zig:9:4 ... variable declaration` — source: array / target: array (`[3]u8` -> `[3]i32`) |
| `typealias_arr_len_mismatch_xmod` | var-decl | `main.zig:10:4 ... variable declaration` — source: array / target: array (`[2]i32` -> `[3]i32`) |
| `w3000_enum_to_int_xmod` | var-decl | `main.zig:22:4 ... variable declaration` — source: enum / target: u32 (`E.B` without `@enumToInt`) |

**Frontend-reject fixtures (2) — now hard `error[3000]`, 0 `.c`:**
- `nonliteral_ptr_to_slice_xmod` (F-M4): previously gcc-only FAIL; now
  `main.zig:23:4 ... variable declaration` — source: pointer / target: slice.
- `bareptr_to_slice_ctx_xmod` (Task 0i fixture): all six contexts now reject —
  var-decl (`:40`, `:59`, `:64`), assignment (`:46`), return (`:51`),
  call-arg (`:55`), each source: pointer / target: slice.

**Class map (gcc classifier, 662 dirs):** before `619 OK / 20 GREEN / 23 FAIL`;
after `614 OK / 27 GREEN / 21 FAIL`. The ONLY moves are the 5 `(b)` dirs
(OK->GREEN) and the 2 frontend-reject fixtures (`nonliteral_ptr_to_slice_xmod`,
`bareptr_to_slice_ctx_xmod`: FAIL->GREEN). No other dir moves.

**Census / self-compile:** the full-corpus `warning[3000]` census is `5 -> 0`; the
pinned `(a)` census stays `39 dirs / 0` (no `(a)` case caught); the self-compile
dumps 48 `.c`, rc=0, `warning[3000]=0`, `error[3000]=0`. Fixed point MOVES
`3f81ea143da726710ad47b6f08bbb13a` -> `7c12619c276e0989c29f27cb4c81d748`
(hop2==hop3). No re-baseline; seed NOT rotated.

**4-MD5 runtime proof (byte-identical):** gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`,
lisp `8dc783a3d766430c15993ab08cd0f7ec`, json `8bda3d5a1ec07d14a301bc343df32bf8`,
mud server `66c8f0abb926cca7baf9a0d1692ab318` / client
`93147d0f0bbd983a9d844fea8b7a6fa7`. `CLOSEOUT OK`.

**Declared residual (not minor):** the return/call-argument promotion excludes
bare `*T`->`[*]T` and enum->integer. The compiler's OWN source relies on those two
coercions silently in return/argument positions — 34 `*T`->`[*]T` (e.g.
`fopen(&c_path[0], ...)`) + 7 enum->integer (`itoa(node.kind, ...)`) = 41 sites
measured by an all-shapes build — so hard-erroring them there would break
self-hosting. var-decl and assignment promote all five shapes. Report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-0q-report.md`.

## Task 0p (F) — decay the A1 `string_const` pointer-to-array emission (v98 2026-09-16)

Track-4 Task 0p fixes the A1 emission defect classified by Task 0k (its fix #1):
the C emitter rendered the A1 string-literal type `*const [N]u8` as a C
**pointer-to-array** `unsigned char (*)[N]`, while a C string literal decays to
`char*`, producing `+1360 -Wincompatible-pointer-types` corpus-wide. The fix is
**emission-only**: `sf/src/c89_emit.zig` `getCTypeName` (the `ptr_type`/
`many_ptr_type` arm) now renders a **const pointer to a `u8` array** as the plain
element pointer `unsigned char*`. The LIR/sema type stays `*const [N]u8`
(`materializeInto` classifies on it; the slice length is a separate temp). Genuine
`*[N]T` pointers are non-const and unaffected; there is **no** genuine
`*const [N]u8` in `sf/src` or the corpus (grep-verified), so the decay is exactly
the string-literal type. This also fixes the module-level string const
`ast.zig:127 zzz_astnode_sz` (a global emitted with the same `*const [N]u8`
type). **No re-baseline; seed NOT rotated; the fixed point MOVES
`f68e69dbac58d5c8ace9f367e199490c` -> `3f81ea143da726710ad47b6f08bbb13a`**
(hop2 == hop3). Report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-0p-report.md`.

**Warning census (662 dirs, user code, `-Wall -Wextra -fsyntax-only`).** Seed-built
compiler `/tmp/t4p2/zig1_5_clean` (the only sanctioned build path,
`scripts/seed/build_from_seed.sh`).

| category | before 0p (post-0o2) | after 0p | Δ |
|---|---|---|---|
| `-Wincompatible-pointer-types` | 1382 | **16** | **−1366** |
| `-Wint-conversion` | 42 | 42 | 0 |
| `-Wsign-compare` | 17 | 17 | 0 |
| `-Wunused-but-set-variable` | 8 | 8 | 0 |
| `-Wparentheses` | 1 | 1 | 0 |
| `function called through a non-compatible type` | 32 | 32 | 0 |
| `comparison between pointer and integer` | 9 | 9 | 0 |
| `this decimal constant is unsigned only in ISO C90` | 9 | 9 | 0 |
| `integer constant is so large that it is unsigned` | 6 | 6 | 0 |
| **total** | **1506** | **140** | **−1366** |

Every non-pointer category is byte-identical; the entire delta is the A1
`-Wincompatible-pointer-types` set.

**The 16 residual pointer warnings are ALL pre-existing (declared, out of scope).**
They are present in the pre-A1 `97cd5a03` census (pointer = 19) and come from
**non-literal** pointer-to-array sources (`&array`, `@ptrCast`) — not the
`string_const` temp — so the A1 decay correctly leaves them: `lisp_interpreter`,
`lisp_interpreter_adv`, `lisp_interpreter_curr`, `lisp_interpreter_upgraded`
(1 each, `*[4096]u8 -> []u8`); `rogue_mud`, `rogue_mud_upgraded` (1 each,
`BspNode**`/`Task**`); `ptroint_arena_offset` (3, `*[64]u8 -> []u8`);
`safe_bounds_inbounds_xmod`, `safe_bounds_slice_xmod` (1 each, `*[3]i32 -> []i32`);
`typealias_mptr_xmod`, `typealias_pub_mptr_xmod` (1 each, `*[2]u8 -> [*]u8`);
`volatile_add_accept_xmod` (1, `*[2]u32`); `repro/ptrcast_manyptr` (1,
`*[4]u8 -> [*]u8`); plus the Task-0o2 fixture
`strtod_endptr_wrongdecl_nonnull_xmod` (1, the deliberately-pinned wrong extern).
Reconciliation: pre-A1 19 − 4 intended strtod deltas (the three
`json_parser*` examples + `a1_ptrarray_strtod_xmod`, all fixed by 0o/0o2)
+ 1 new 0o2 fixture = **16**. These are pinned by the existing corpus fixtures
above; not marked minor.

**A1 fixtures (seed-built compiler).** `a1_strlit_ptrarray_warn_xmod` 0 pointer
warnings, run `abc`; `a1_ptrarray_cchar_xmod` 0, run `97`;
`a1_ptrarray_strtod_xmod` 0, run `1` (the strtod shape was fixed by 0o).

**Runtime byte-identity (4-MD5 gate, re-verified).** Old (post-0o2) and new (0p)
compilers produce identical streams; the old compiler reproduces the Task-0i
goldens exactly:

| program | stdout md5 | bytes |
|---|---|---|
| `game_of_life` (100 gens) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | 83490 |
| `lisp_interpreter_curr` (feed `(+ 1 2)`/`(cons 1 2)`/`exit`) | `8dc783a3d766430c15993ab08cd0f7ec` | 16 |
| `json_parser` (test.json CWD) | `8bda3d5a1ec07d14a301bc343df32bf8` | 228 |
| `mud_server` stdout (demo `session.sh` canonical feed) | `66c8f0abb926cca7baf9a0d1692ab318` | 75 |
| `mud_server` client bytes | `93147d0f0bbd983a9d844fea8b7a6fa7` | 158 |

**Other gates.** Corpus class map **662 = 619 OK / 20 GREEN / 23 FAIL / 0 ICE /
0 CRASH** — unchanged vs post-0o2. Self-compile closure `hop2 == hop3 ==
3f81ea14…`; self emitted `-Wincompatible-pointer-types` **8409 → 0**;
self `warning[3000]` = 0 (unchanged). `scripts/closeout/verify_upgraded.sh` →
**CLOSEOUT OK** (all 12 verdict rows A1–A5, B1–B7 PASS).

## Task 0o2 (F) — fix the `json_parser` `strtod` declaration + pin the offending syntax (v97 2026-09-16)

Track-4 Task 0o2 fixes the ROOT CAUSE left declared by Task 0o (its gap #1): the
`strtod` extern declaration in the canonical `examples/z98/json_parser*` copies is
type-WRONG for libc. `endptr: ?[*]const c_char` is C `const char *`, but
`<stdlib.h>`'s real `strtod` takes `char **`. Task 0o removed the warning only for
the **statically-null** argument (a null pointer constant is compatible with any
object-pointer parameter); a **non-null** endptr is a genuine mismatch and still
emits non-conforming C. Task 0o2 (a) corrects the example declaration and (b)
pins the offending syntax as an EXPECTED WARNING in the corpus. **No `sf/src`
change; no re-baseline; seed NOT rotated; the fixed point is UNMOVED at
`f68e69dbac58d5c8ace9f367e199490c`** (the seed-rebuild closure `hop2 == hop3 ==
f68e69db…` reproduces Task 0o's point exactly). Report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-0o2-report.md`.

**Correct Z98 type (emission-proven).** `?*[*]c_char` — optional single-item
pointer to a many-item pointer to `c_char` (C `char **`, nullable). Emission test
with the seed-built compiler (scratch probe `strtod(nptr: [*]const c_char,
endptr: ?*[*]c_char)`, called with `null` and with `&out` where `out: [*]c_char`):
dump rc=0, gcc 0 warnings, run rc=0 stdout `1`. Emitted C proves the ABI shape:
the optional materializes as the standard
`typedef struct { char** value; int has_value; }` and ABI-unwraps to a `char**`
temp — `zT_32 = zT_37.has_value ? zT_37.value : NULL;` /
`strtod(..., zT_32);` — while the null argument stays `(void*)(NULL)`. NOT a
struct at the call, NOT a single `char*`. (Candidate confirmed; no `sf/src`
change needed.)

**Example fix (scope ruling B — three canonical copies).** `endptr:
?[*]const c_char` → `endptr: ?*[*]c_char` in `examples/z98/json_parser/file.zig:18`,
`examples/z98/json_parser_upgraded/file.zig:18`, and
`examples/z98/json_parser_workaround/file.zig:19`. Measured with the seed-built
compiler under the binding gcc flag-set
(`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration -I <inc>`):

| example | `passing argument 2 of 'strtod'` | total `-Wall` warns | run | stdout md5 |
|---|---|---|---|---|
| `examples/z98/json_parser` | 0 (was 1) | 59 | rc=0 | `8bda3d5a1ec07d14a301bc343df32bf8` (UNCHANGED) |
| `examples/z98/json_parser_upgraded` | 0 (was 1) | 59 | rc=0 | `8bda3d5a1ec07d14a301bc343df32bf8` |
| `examples/z98/json_parser_workaround` | 0 (was 1) | 62 | rc=0 | `dc22fa473650bd3dcdf4d8a1559a260b` |

The strtod warning is gone for **both** the null argument (all three examples
call `strtod(..., null)`) and a **non-null** endptr (the emission probe above).
`json_parser` runtime stdout is byte-identical to Task 0o (md5 `8bda3d5a…`).
`bash scripts/closeout/verify_upgraded.sh /tmp/t4o2/zig1_5_clean` → **CLOSEOUT
OK**.

**New EXPECTED-WARNING fixture** `repro/mi_matrix/strtod_endptr_wrongdecl_nonnull_xmod`
(auto-listed by `scripts/corpus/list_corpus_dirs.sh`; class OK — gcc exits 0 with
the warning). It carries the OFFENDING SYNTAX: an extern declared with the wrong
`endptr: ?[*]const c_char` (`main.zig:26`) and **CALLED with a NON-NULL
argument** (`main.zig:37`, `endptr` = a pointer into a writable 8-byte slot), so
the emitted C passes a `char*` where `<stdlib.h>` wants `char**`:

```
main_1353F197.c:75:67: warning: passing argument 2 of 'strtod' from incompatible pointer type [-Wincompatible-pointer-types]
   75 |     zT_33 = strtod((char*)((char*)(unsigned char*)(buf + zT_28)), zT_27);
```

**Rationale.** A wrong extern declaration produces illegal (non-conforming) C.
The example is FIXED, so this fixture pins the behaviour deliberately: it is an
EXPECTED WARNING (non-conforming C, gcc rc=0), not a class FAIL and not a
compiler defect. `nptr` is a non-literal local buffer, so the fixture carries
**no** Task-0p `string_const` shape-1/2 warning — the endptr mismatch is its only
warning. It runs memory-safely: run rc=0, stdout `1`.

**`examples/zig0/*` still carry the offending syntax (declared, outside the
canonical corpus).** `examples/zig0/json_parser/file.zig:10` and
`examples/zig0/json_parser_workaround/file.zig:11` keep
`endptr: ?[*]const c_char`; per scope ruling B they are intentionally NOT fixed
(they are outside the `examples/z98/*` canonical corpus). This is a declared
gap, NOT marked minor.

**Measured (seed-built compiler `/tmp/t4o2/zig1_5_clean`; sf/src unchanged).**

- Corpus class map: **662 = 619 OK / 20 GREEN / 23 FAIL / 0 ICE / 0 CRASH**; the
  only delta vs the post-0o 661-dir reference is the new OK fixture.
- Full-corpus gcc warning census (`-Wall -Wextra`, user code):
  **1505 → 1506**, `-Wincompatible-pointer-types` **1381 → 1382**. Per-dir diff
  vs the post-0o census is **exactly the one new dir**
  (`strtod_endptr_wrongdecl_nonnull_xmod  1  -Wincompatible-pointer-types=1`);
  no other category moves; no regression. (The example declaration fix itself
  moves no census row — the examples only call `strtod` with a null endptr, which
  Task 0o already made clean.)
- Self-compile fixed point **UNMOVED** `f68e69dbac58d5c8ace9f367e199490c`
  (hop2 == hop3). No `sf/src` edit.

## Task 0o (F) — fix the pre-existing `strtod` null-optional warning (v96 2026-09-16)

Track-4 Task 0o removes the pre-existing gcc warning
`passing argument 2 of 'strtod' from incompatible pointer type` in
`examples/z98/json_parser` (and its `_upgraded` / `_workaround` copies). It is
**not** A1-caused (Task 0k classified it PRE-EXISTING: 1 warning pre-A1, and 1 of
json_parser's 60 post-A1). No re-baseline; seed NOT rotated; the fixed point
MOVES `c3913a863f0ab6ac843f0bf4672253be` -> `f68e69dbac58d5c8ace9f367e199490c`
(hop2 == hop3). Report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-0o-report.md`.

**Root cause + locus (emitter null-optional ABI path).**
`examples/z98/json_parser/file.zig:18` declares
`extern fn strtod(nptr: [*]const c_char, endptr: ?[*]const c_char) f64;` — the
endptr parameter is the Z98 nullable many-pointer `?[*]const c_char`
(C `const char *`). `<stdlib.h>` declares the real `strtod` endptr as `char **`.
For a **statically-null** argument the lowering ABI-unwrapped the optional into a
payload-typed `char*` temp and passed it:

```c
char* zT_2;
zT_4.has_value = 0;
zT_2 = zT_4.has_value ? zT_4.value : NULL;
strtod(zT_1, zT_2);   /* warning: passing argument 2 of 'strtod' */
```

The value is the null pointer, so the correct C is a null pointer constant, which
is compatible with any object-pointer parameter. **Fix** (`sf/src/lower.zig`,
extern-call arg loop ~`:3686-3713`): when an extern parameter is `optional_type`
whose payload is a pointer (`ptr_type` / `many_ptr_type`) and the argument AST
node is a `null_literal`, emit a `null_const` temp typed as the generic `*void`
(`typeRegistryGetOrCreatePtr(registry, TYPE_VOID, false)`) instead of the
`unwrap_optional_abi` payload temp; the hoisted arg slot is typed `*void` too.
The call now emits `strtod(zT_1, (void*)(NULL))` (or `void* zT_2 = NULL;` when
materialized) — type-correct for the `<stdlib.h>` prototype. Non-null optionals
and non-pointer optional payloads are unchanged (guarded).

**New pin fixture** `repro/mi_matrix/null_opt_manyptr_arg_xmod` (auto-listed;
class OK). It uses `strtod` with a non-literal `nptr` (a local `[8]u8`), so it
carries **no** `string_const` shape-1/2 warning and is independent of Task 0p.
Before 0o (`c3913a86`): exactly **1** `-Wincompatible-pointer-types` warning (the
strtod arg-2). After 0o: **0** warnings; gcc rc=0, link rc=0, run rc=0, stdout `1`.

**Measured** (compiler built from the new `sf/src` via the committed seed;
3-hop closure hop2 == hop3 == `f68e69dbac58d5c8ace9f367e199490c`):

- `json_parser` 60 -> **59** `-Wincompatible-pointer-types` (strtod warning 0);
  `json_parser_upgraded` 60 -> 59; `json_parser_workaround` 63 -> 62 — the
  non-strtod baselines.
- full-corpus gcc warning census (`-Wall -Wextra`, user code): 1510 -> **1505**.
  The ONLY per-dir deltas are the 5 strtod sites: `json_parser` 60->59,
  `json_parser_upgraded` 60->59, `json_parser_workaround` 63->62,
  `a1_ptrarray_strtod_xmod` 3->2 (shape 4 removed; shapes 1/2 remain, Task 0p's),
  and the new fixture 1->0. The strtod warning WAS part of the corpus
  `-Wincompatible-pointer-types` count; no other category moves; no regression.
- corpus class map: **661 = 618 OK / 20 GREEN / 23 FAIL / 0 ICE / 0 CRASH**; the
  only delta vs the post-0n 660-dir reference is the new OK fixture (dir-by-dir
  diff otherwise empty).
- full-corpus `warning[3000]` census: **unchanged at 5** (the 5 `(b)` dirs);
  self-compile `warning[3000]` = 0 (post-0n).
- runtime: `json_parser` stdout byte-identical to the pre-0o compiler
  (md5 `8bda3d5a1ec07d14a301bc343df32bf8`); `json_parser_upgraded` /
  `_workaround` run rc=0; `a1_ptrarray_strtod_xmod` and the new fixture run
  stdout `1`.

**Declared gaps (NOT marked minor).**
1. The example's `strtod` declaration is itself type-wrong for the real C
   function: `endptr: ?[*]const c_char` is `const char *`, but libc's `strtod`
   takes `char **`. Task 0o removes the spurious warning for the **statically
   null** argument only (where `NULL` / `(void*)0` is valid for both types). A
   **non-null** `endptr` argument is still a genuine type mismatch and still
   warns (verified); that is an example-source declaration bug, out of the
   Track-4 warning-classification scope, and is not fixed here.
2. The fix recognizes a **direct `null` literal** argument. A null optional held
   in a variable/expression (e.g. `var p: ?[*]const c_char = null; strtod(s, p)`)
   is not statically recognized and still warns (verified). No corpus program
   does this.

## Task 0m fix round 1 (F) — DECLARE family-B relational-enum over-acceptance (v95 2026-09-15)

Operator ruling (fix round 1): **DECLARE, no behavior change.** The Task-0m
family-B arm (`sf/src/semantic_analyzer.zig:1218-1219`) returns `TYPE_BOOL` for
`lhs == rhs` enum operands in `semanticAnalyzerResolveComparison`, but it is
**not gated on `cmp_eq`/`cmp_ne`**, so relational enum comparisons (`<`, `<=`,
`>`, `>=`) are also accepted. Real Zig rejects relational comparison of enum
operands (only `==`/`!=` are permitted). This over-acceptance is **inherited
verbatim from the Task 0l fix set** (applied by Task 0m) and is a **candidate for
Task 0q / a follow-up** — not fixed here. No `sf/src` change; no re-baseline.

New pin fixture `repro/mi_matrix/relational_enum_overaccept_xmod` (auto-listed by
`scripts/corpus/list_corpus_dirs.sh`; class OK). Measured with the post-0m
compiler (`e19a843aa9505a35aac1ce3e63bb7e68`): **dump rc=0 / 0 `warning[3000]` /
0 errors / gcc-clean / link rc=0 / run rc=0, stdout `12345`**. The emitted C
compares the enum values with raw C relational operators, e.g.
`if ((int)(a < b)) goto z_bb_1;` and
`if ((int)((zT_C00BF080_E)(zT_C00BF080_E_A) < (zT_C00BF080_E)(zT_C00BF080_E_B))) goto z_bb_13;`.

Corpus: **660 dirs = 617 OK / 20 GREEN / 23 FAIL / 0 ICE / 0 CRASH** — the only
class-map delta vs the post-0m 659-dir run is the new OK dir. Pinned `(a)` census
unaffected (39 dirs / 0 `warning[3000]`); full-corpus `warning[3000]` total
unchanged at 5 (the new dir emits none).


## Task 0m (F) — fix the false-positive `warning[3000]` `(a)` families (v94 2026-09-15)

Track-4 Task 0m applies the Task-0l fix set so the **48** `(a)` valid-Z98
`warning[3000]` false positives no longer warn. **The 12 `(b)` invalid-Zig cases
are untouched** (their hard-error promotion is Task 0q, LAST). **No re-baseline;
seed NOT rotated** (the fixed point MOVES; the 4-MD5/seed re-baseline is a later
task per the S25 ruling). Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-0m-report.md`.

Edits: 12 per Task 0l across `sf/src/type_registry.zig` (C, E, F1, H, I + the
`errorSetIsSubset` helper), `sf/src/coercion.zig` (`undefined`/`noreturn` ->
`none`), `sf/src/semantic_analyzer.zig` (A, B, D, F2, G, J, K). One correction to
the 0l plan: the inferred anonymous error set is **not** a real `error_set_type`
— `!T` is parsed with `error_set == 0` (`type_resolver.zig:920-931`) — so the
family-I helper treats `error_set == 0` (either side) as an unknown/inferred set
that is assignable. The `(b)` non-subset `eu_assign_incompat_errorset` keeps real
sets and still warns.

Measured post-0m (compiler built from the new `sf/src` via the committed seed,
3-hop closure `e19a843aa9505a35aac1ce3e63bb7e68`):

- pinned census `w3000_census.sh <zig1> repro/mi_matrix/w3000_fp_pins.list`:
  **39 dirs / 0 `warning[3000]`** (exit 0) — every pinned `(a)` dir cleared.
- full corpus: **659 dirs / 5 `warning[3000]`** — exactly the 5 `(b)` corpus dirs
  (`eu_assign_incompat_errorset`, `ptr_scalar_to_manyptr_xmod`,
  `typealias_arr_elem_mismatch_xmod`, `typealias_arr_len_mismatch_xmod`,
  `w3000_enum_to_int_xmod`). Pre-0m was 55 (50 in the pinned set).
- self-compile `warning[3000]`: **19 -> 7** = the 7 `(b)` enum->int sites
  (`semantic_analyzer.zig:1190,1197`; `lower.zig:3093,3618,3768,3771,3892`).
- corpus class map: **unchanged** — the new compiler's per-dir class list is
  byte-identical to the pre-0m reference (`/tmp/t4i_post/zig1_5_clean`) under the
  same classifier. (The absolute counts read `616 OK / 20 GREEN / 23 FAIL` under
  `/tmp/corpus_classify.sh`, which labels `nc==0 & no error[3000]` as FAIL; the
  0l v93 counts `616/37/6` use the GREEN=any-`nc==0` definition. Both agree the
  6 gcc-fail dirs are unchanged: `array_of_slices_literal_xmod`,
  `bareptr_to_slice_ctx_xmod`, the 3 `callconv_*` emission-inspection dirs,
  `nonliteral_ptr_to_slice_xmod`.)
- runtime: the 39 pinned fixtures were run under both compilers; 34 are
  byte-identical in rc+stdout, 4 are the `callconv_*` emission-inspection dirs
  (same build-fail/no-build under both), and **1 changed** — see below.

### Correction to Task 0l: family D also fixes the `bare_enum_literal_xmod` runtime

Task 0l (concern 4) expected the family-D fix to clear only the `warning[3000]`
and to leave the bare-enum-literal value-position mis-lowering RED. It does not:
the `enum_type` expected-type arm in `semanticAnalyzerResolveEnumLiteral` now
records the member value in `enum_value_table` and resolves the literal to the
expected enum type, so the value-position lowering is correct too.
`repro/mi_matrix/bare_enum_literal_xmod` is now **runtime-GREEN** (run rc=0,
stdout `O`) — previously rc=133 (assert trap). This is a strict improvement (the
fixture was designed to go GREEN when the lowering was fixed); no residual.


## Task 0l (I) — false-positive `warning[3000]` fix set + pin mechanism (v93 2026-09-15)

Track-4 Task 0l investigates the **48** `(a)` valid-Z98 `warning[3000]` false
positives classified by Task 0k (the count is 48, not 49 — see the
`field_store_tagged` correction below) and produces the exact minimal fix set for
Task 0m. **No `sf/src` change; no re-baseline** (reference = post-A1
`958a5e0f8ce3f4121766789322c8da9b`). Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-0l-report.md`.

Corpus universe grows **651 -> 659 dirs** (+8 Task-0l `w3000fp_*` fixtures, all
OK class). Measured class map (post-A1 `958a5e0f`): **659 = 616 OK / 37 GREEN /
6 FAIL** (the 651-dir baseline was 608/37/6; all 8 new fixtures are OK). FAIL set
unchanged.

### Pin mechanism — `scripts/corpus/w3000_census.sh`

The gcc-based classifier keys on the gcc exit code, so a tolerated Z98
`warning[3000]` (the program still compiles and runs) is invisible to it. Task 0l
adds a compiler-stderr census:

```
bash scripts/corpus/w3000_census.sh <zig1> repro/mi_matrix/w3000_fp_pins.list
```

It runs the compiler under test over the pinned dirs, counts `warning[3000]`, and
exits nonzero if any pinned dir warns. `repro/mi_matrix/w3000_fp_pins.list` is the
contract list ("after Task 0m each pinned dir emits ZERO `warning[3000]`").
Full-corpus mode (no pins arg / a missing pins file) prints the total census.

**Measured pre-0m** (`958a5e0f`): full corpus **659 dirs, 55 `warning[3000]`**
(56 before the `field_store_tagged` fixture fix); the 39 pinned `(a)` dirs hold
**50** of them. After Task 0m the pinned set must read 0, leaving the 5 `(b)`
warnings = **5**.

### Fix set (per `(a)` family — details + evidence in the 0l report)

| family | root cause (file:line) | Task 0m change |
|---|---|---|
| A slice `.ptr` -> `[*]T` | `semantic_analyzer.zig:719` builds `*T` | `typeRegistryGetOrCreateManyPtr(..., (base_ty.flags & 1) != 0)` |
| B `bool` from enum cmp / `and`/`or` | `semantic_analyzer.zig:1215-1218` returns `void` for enum==enum | return `bool` for `lhs == rhs` enum kinds |
| C `undefined` -> any | `type_registry.zig:1151-1304` no `undefined` arm | `if (src.kind == undefined_type) return true` |
| D bare enum literal + expected enum | `semantic_analyzer.zig:1706-1737` handles only tagged-union expected types | add `enum_type` expected arm |
| E fn item -> fn ptr | `type_registry.zig:1174` requires `is_extern` equality | drop the `is_extern` equality term |
| F1 `noreturn` init/assign | `type_registry.zig` no `noreturn` arm | `if (src.kind == noreturn_type) return true` (+ `classifyCoercion` -> none) |
| F2 all-`noreturn` switch | `semantic_analyzer.zig:2040` materializes `void` | `if (unified == 0) unified = TYPE_NORETURN` |
| G `if` with expected optional/EU | `semantic_analyzer.zig:1643-1653` honors expected type only for string prongs | accept any `typeRegistryIsAssignable` prong + record coercions |
| H tuple literal -> array | `type_registry.zig` no tuple->array arm | element-count + element-wise assignability |
| I error set -> superset | `type_registry.zig:1193-1199` requires exact set equality | subset check per tag |
| J `@cVaArg` result type | `semantic_analyzer.zig:2359-2360` types it as arg 0 | resolve arg 1 as the result type |
| K `@enumToInt` result type | `semantic_analyzer.zig:2350-2355` gated on explicit backing | return `typeRegistryEnumBackingType` for any enum |

**One fix covers several families:** B alone clears both self sites
(`semantic_analyzer.zig:1639-1640`, `c89_emit.zig:745`); F1 covers every
`src=noreturn` corpus case; G covers all 12 `if` optional/EU cases.

### `repro/field_store_tagged` — Task 0k classification CORRECTED (true positive, fixture fixed)

Task 0k called this `(a)` and read its `source: type` note as "`@intCast` resolves
its result as the `type` value". Task 0l disproves that: `source: type` is the
`typeKindSrcStr`/`typeKindTgtStr` fallback (`diagnostics.zig:540-...`) for the
unmapped `usize_type`; `@intCast(usize, 1)` is correctly typed `usize`, and
`u.tag` is `u32` (`symbol_registrator.zig:148`), so the warning is a REAL
same-width `usize -> u32` mismatch.

**OPERATOR RULING (fix round 1): true positive, remedy (A) — fix the fixture.
NOT moved to `(b)`.** `repro/field_store_tagged/main.zig` now stores
`u.tag = @intCast(u32, 1);` (the print call was also migrated to `std.io` so the
fixture links/runs; the old `__bootstrap_print_int` extern was removed from the
runtime in F4). It is a normal OK fixture (dump/gcc/link/run rc=0) and emits NO
`warning[3000]`. Consequence: the `(a)` set is **48** (not 49), and Task 0q's
`(b)` set is **12** (7 self enum→int sites + 5 corpus dirs; Task 0k said 11 — `w3000_enum_to_int_xmod` was uncounted).

## Task 0k (I) — warning classification: valid Z98 vs invalid Zig (v92 2026-09-15)

Track-4 Task 0k exhaustively classifies every warning emitted by the post-A1
compiler (`958a5e0f8ce3f4121766789322c8da9b`) as **(a) valid Z98 / type-checker
false positive** or **(b) invalid Zig / must become a hard `error[3000]` (0 `.c`)**.
**No `sf/src` change; no fixes; no re-baseline** — the fix set is Task 0l. Full
report: `.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-0k-report.md`.

Corpus universe grows **644 -> 651 dirs** (+7 Task-0k fixtures). Measured class
map (post-A1 `958a5e0f`): **651 = 608 OK / 37 GREEN / 6 FAIL** (the 644-dir
baseline was 601/37/6; all 7 new fixtures are OK). FAIL set unchanged:
`array_of_slices_literal_xmod`, `bareptr_to_slice_ctx_xmod` (GREEN-guard after
0j), the 3 `callconv_*` emission-inspection dirs, `nonliteral_ptr_to_slice_xmod`.

### `-Wincompatible-pointer-types` (A1, +1360) — type model right, emitter wrong

A1's `*const [N]u8` string-literal type is CORRECT (Zig langref: string literals
are `*const [N:0]u8`; `docs/reference/Language_Spec_Z98.md:72`). The defect is the
C emitter (`sf/src/c89_emit.zig:729-761`) rendering that temp as a
pointer-to-array `unsigned char (*)[N]`; a plain element pointer is the correct C
model (the array length is carried separately by `array_to_slice`). Two further
shape pins added (`a1_strlit_ptrarray_warn_xmod`, Task 0i, already pins shapes 1+3):

| fixture | shape | pre-A1 | post-A1 | runtime |
|---|---|---|---|---|
| `a1_ptrarray_cchar_xmod` | 2: `(*)[N]` -> `char*` (`[*]const c_char` materialization) | 0 | 2 ptr warns | `97` |
| `a1_ptrarray_strtod_xmod` | 4: `strtod` arg 2 — **PRE-EXISTING, not A1** | 1 | 3 ptr warns | `1` |

`-Wno-pointer-sign` hides `char*`<->`unsigned char*` but NOT pointer-vs-pointer-to-array,
so the A1 warnings surface under the binding flag-set.

### `warning[3000]` — every case classified (a) valid Z98 vs (b) invalid Zig

Self-compile `sf/src` = **19 warnings** (11 assignment + 8 var-decl); corpus = **41
warnings** in 32 dirs (the brief's "~89 across ~51 dirs" = ALL `[3000]` diagnostics
incl. the 48 already-hard `error[3000]`; the true tolerated-warning count is 60).

- **Self-compile (b) invalid Zig (7):** `semantic_analyzer.zig:1190,1197`,
  `lower.zig:3093,3618,3768,3771,3892` — bare enum->integer (`var x: u32/u8 =
  <enum>.kind`) without `@enumToInt`. Must become hard errors + source rewritten.
- **Self-compile (a) valid Z98 (12):** `main.zig:992` slice `.ptr` -> `[*]`
  (spec:68); `semantic_analyzer.zig:1639,1640` + `c89_emit.zig:745` `bool` from
  `and`/`or` (checker returns `void`); `type_registry.zig:340`, `state_map.zig:65`,
  `module_registry.zig:477-479,482-484` `undefined` -> many-pointer (valid for any
  type). All 12 are type-checker false positives; the self-hosting compiler proves
  the code is correct.
- **Corpus (b) invalid Zig (4):** `eu_assign_incompat_errorset:1` (F!i32 -> E!i32,
  F not-subset E), `ptr_scalar_to_manyptr_xmod:18` (`*T` -> `[*]T`),
  `typealias_arr_elem_mismatch_xmod:9` (`[_]u8` -> `[3]i32`),
  `typealias_arr_len_mismatch_xmod:10` (`[2]i32` -> `[3]i32`). These are genuine
  mismatches currently only warned -> should be hard `error[3000]`.
  **JUDGMENT CALL (operator must confirm):** real Zig DOES permit `*T -> [*]T`, so
  the `ptr_scalar_to_manyptr` verdict rests on the **Z98 spec's enumerated coercion
  table** (`docs/reference/Language_Spec_Z98.md:380-384`: only slice->ptr and
  array->ptr), not real-Zig semantics; the A9F-a GREEN-guard fixture already
  encodes that spec decision. `typealias_arr_elem_mismatch` (`[N]u8` -> `[N]i32`)
  is likewise a structural mismatch that Zig also rejects, but is listed here as a
  spec-based judgment call.
- **Corpus (a) valid Z98 (37):** enum literal with expected enum type, fn item ->
  fn pointer, `noreturn` initializer/assignment, `if (c) A else B` with expected
  optional/error-union type, tuple literal -> array, anonymous/named error set ->
  named error set, `@cVaArg`. All type-checker false positives.
- **Corpus `error[3000]` (48):** already hard errors — `unsupported builtin`
  (20), `cannot declare variable of type void` (12), volatile discard (11), unknown
  type (1), field-on-optional (1), type-mismatch (2: fnptr callconv + EU payload),
  `packed_union_struct_wholemember_xmod` (1: "cannot read a whole packed-struct
  value out of a packed union member" — emitted with **no source location**, so it
  is easy to miss in a location-parsed census). All invalid Zig / unsupported
  features; correct rejects.

### New Task-0k fixtures (corpus 644 -> 651)

| fixture | class | construct | verdict |
|---|---|---|---|
| `a1_ptrarray_cchar_xmod` | OK | pointer shape 2 | A1 C-model; 0 warns after 0j |
| `a1_ptrarray_strtod_xmod` | OK | pointer shape 4 (pre-existing) | separate null-optional codegen |
| `w3000_enum_to_int_xmod` | OK | `var x: u32 = E.B;` | **(b)** invalid -> hard error |
| `w3000_enumtoint_explicit_xmod` | OK | `var x: u32 = @enumToInt(E.B);` | (a) false positive; actual diagnostic `source: enum / target: u32` (checker resolves the result as the ARGUMENT's enum type, not the backing `u32`) |
| `w3000_undefined_manyptr_xmod` | OK | `s.p = undefined;` (many-ptr) | (a) false positive |
| `w3000_sliceptr_manyptr_xmod` | OK | `var p: [*]u8 = s.ptr;` | (a) false positive |
| `w3000_bool_or_xmod` | OK | `var b: bool = <cmp> or <cmp>;` | (a) false positive |

**A1-induced vs pre-existing split:** A1 changed the `[3000]` set by REMOVING 11
`pointer>many-pointer` false-positive warnings (string literal -> `[*]const u8`).
The string literal is a pointer-to-array, so `classifyCoercion` handles it at the
`ptr_type -> many_ptr_type` arm (`sf/src/coercion.zig:169-178`), which returns
`CoercionKind.none` for an array pointee (a no-op decay) — NOT `array_to_many_ptr`
(that kind is for an array SOURCE, `coercion.zig:158-163`); it added 0. C1
deletion (`ed206028`) adds 5 `pointer>slice` warnings (the two
`bareptr_to_slice`/`nonliteral` fixtures). The 48 `error[3000]` and the 19
self-compile warnings are byte-identical across pre-A1 `97cd5a03`, post-A1
`958a5e0f`, post-deletion `ed206028`. The `strtod` arg-2 warning is pre-existing
(1 pre, 1 post).

# mi_matrix corpus — expected-fail manifest (v91 2026-09-15)

## Task 0i (I) residual investigation — fixtures (v91 2026-09-15)

Track-4 Task 0i exhaustively investigates the Task 0h residuals (C1 duplicate block,
frontend rejection, A1 warning regression, M4 reachability, 4-MD5 runtime proof) and
adds THREE corpus fixtures. **No `sf/src` change; no re-baseline** (reference = post-0h
`958a5e0f8ce3f4121766789322c8da9b`; the fix set is Task 0j). Full report:
`.superpowers/sdd/2026-09-13-coroutine-integration-plan/task-0i-report.md`.

Corpus universe grows 641 -> 644 dirs (+3 Task-0i fixtures). Measured classes:
**644 = 601 OK / 37 GREEN / 6 FAIL** (the 641 pre-existing dirs are class-identical —
the three new fixtures are the only additions; `bareptr_to_slice_ctx_xmod` FAIL,
`a1_strlit_ptrarray_warn_xmod` OK, `m4_array_to_slice_len_xmod` OK).

### C1 — the duplicate `ptr_type -> slice_type` block is still live

`sf/src/type_registry.zig:1257-1263` is a SECOND `src.ptr_type && tgt.slice_type`
assignability block (the Task 0h edit at `:1231-1243` removed the bare-pointer returns
from the FIRST block only). Its `:1261` arm still returns true for a bare
`*const u8`/`*const c_char` -> `[]const u8`, so Task 0h's edit is a **no-op**: the
frontend emits NO diagnostic and `lower.zig` inserts no `make_slice`; gcc rejects the
raw-pointer->Slice assignment. **`:1257-1263` CAN be safely deleted** — evidence in the
Task 0i report: no tree reliance; the full corpus class map is identical
(`ed206028` deletion compiler == `958a5e0f` post baseline, 599/37/5, zero per-dir diff);
the full corpus frontend-diagnostic census changes ONLY `nonliteral_ptr_to_slice_xmod`
(+1 `[3000]`); the self-compile diagnostics (19) and emitted C are byte-identical.

### Frontend rejection — `bareptr_to_slice_ctx_xmod` (NEW; class FAIL today, GREEN-guard after Task 0j)

Bare `*const u8` -> `[]const u8` in the var-decl / assignment / return / call-arg /
if-expr / switch-expr contexts. TODAY: dump rc=0 / 5 `.c` / NO frontend diagnostic /
gcc-FAIL (8 `incompatible types` errors). With the duplicate deleted (`ed206028`):
var-decl + assignment emit `warning[3000]` **level=1** and emission continues; `return`
(`resolveReturnStmt`) and call-argument (`:1561 tryRecordCoercion`) emit **no diagnostic
at all**. Task 0j must raise the mismatch to a hard `error[3000]` (level 0, 0 `.c`) at
`:2984-2993` (var-decl) and `:1872-1881` (assignment), and ADD one at `resolveReturnStmt`
and the call-argument site. Declared here: FAIL today, GREEN-guard (frontend reject) after 0j.

### A1 warning regression — `a1_strlit_ptrarray_warn_xmod` (NEW; class OK)

Minimal `var s: []const u8 = "abc";`. Post-0h the string-literal temp is typed
`*const [N]u8` and emitted as `unsigned char (*)[N]`, so gcc emits 2
`[-Wincompatible-pointer-types]` warnings (pre-0h: 0). Corpus-wide user-code warning
census (`gcc -m32 -std=c89 -O0 -Wall -Wextra -fsyntax-only`, 641 dirs): pre 144 -> post
1504; the entire +1360 delta is `-Wincompatible-pointer-types` in 102 dirs (0 improved);
every other category is unchanged. Examples: json_parser 1->60, lisp_interpreter_curr
1->107, mud_server 8->36. Task 0j must restore warning-clean emission (decay the
`string_const` temp OR cast at the use sites). Runtime byte-identical (4-MD5 proof).

### M4 reachability — `m4_array_to_slice_len_xmod` (NEW; class OK)

`lower.zig:6627` `array_to_slice`'s `arr_len = 1` default is **UNREACHABLE** (Task 0i
marker compiler `4089cf7c`: 0 fires across 641 corpus dirs + 0 in a targeted stress probe
+ 0 in the self-compile). This fixture is the positive pin: array -> slice in
var-decl/field/if-expr/call-arg must carry the REAL length (stdout `hello|5`, run rc=0).

### 4-MD5 runtime proof

gol/lisp/json/mud run under pre-0h (`97cd5a03`) and post-0h (`958a5e0f`): stdout
byte-identical (`gol fcbf7e7c…` / `lisp 8dc783a3…` / `json 8bda3d5a…` /
`mud_server 66c8f0ab…` / `mud_client 93147d0f…`), all rc=0. A 4-MD5 re-baseline is
therefore justified (Task 0j Step 4).

# mi_matrix corpus — expected-fail manifest (v90 2026-09-15)

## Latent risks CLOSED (v90 2026-09-15) — Task 0h (F)

Track-4 Task 0h closes the residual latent risks declared by Task 0g. **`sf/src`
change** (`semantic_analyzer.zig` / `lower.zig` / `main.zig` / `std_async.zig`).
Reference compiler = the post-Task-0g fixed point `97cd5a033156119339ebffc15b575c5d`;
NEW fixed point `958a5e0f8ce3f4121766789322c8da9b` (two-hop closure, hop1 == hop2).
Seed NOT rotated (Task 6).

Corpus `-s0` universe **641 dirs** = **599 OK / 37 GREEN / 5 FAIL / 0 ICE / 0 CRASH**.
Per-dir diff vs the pre-fix baseline (`641 = 599 OK / 37 GREEN / 4 FAIL / 1 ICE`) is
EXACTLY two rows — both intended:

| dir | pre | post | why |
|---|---|---|---|
| `taskptr_field_store_xmod` | ICE | **OK** | T0b `error[3043]` fixed — REMOVED from this manifest |
| `nonliteral_ptr_to_slice_xmod` | OK | **FAIL** (gcc) | F-M4 A1 — bare pointer→slice now rejected; DECLARED below |

### F-M4 — A1 root-cause fix (string literals typed `*const [N]u8`)

`sf/src/semantic_analyzer.zig` + `sf/src/lower.zig` now type a string literal as
`*const [N]u8` (the real byte length N is in the type; the emitter supplies the trailing
NUL). Consequences: `"abc"` AND `const p = "abc"; var s: []const u8 = p;` coerce via
`array_to_slice` with the REAL length; the bare `*const u8`/`*const c_char` →
`[]const u8` coercion is removed from `coercion.classifyCoercion` and
`typeRegistryIsAssignable`, so a bare pointer is no longer silently a length-1 slice.
`materializeInto`'s synthesis now applies `array_to_slice` (known-length source) only.

`nonliteral_ptr_to_slice_xmod` (the Task-0g runtime-RED pin) is now a **compile-FAIL**:
the frontend inserts no `make_slice` for the bare `*const u8` params, so the emitted C
assigns a raw pointer to a `Slice` and gcc rejects it with `error: incompatible types
when assigning to type 'zT_..._Slice_zT_..._u' from type 'unsigned char *'` (dump rc=0,
5 `.c`; pre-fix it emitted a hard-coded `len = 1` and ran with the wrong length).
Declared here as a compile-FAIL.

### T0b — `[*]*Task` element field store (FIXED; GREEN, corpus OK)

`sf/src/lower.zig` `lowerFieldStore` now loads the element pointer when the indexed
element is itself a pointer (`s.tasks[i]`), so `s.tasks[i].cancel_requested = true`
resolves to the `Task` struct. The in-tree `sf/src/std_async.zig` `cancelAll`
local-`*Task` workaround is removed. `taskptr_field_store_xmod`: dump rc=0 / 4 `.c` /
gcc-clean / link rc=0 / **run rc=0**. **REMOVED from this manifest.**

### F-M1 guard + T0-M2 (no class movement)

- F-M1: `sf/src/semantic_analyzer.zig` guards the `astStoreNodeAt(prong.child_0)` read
  with `prong.child_0 != 0`.
- T0-M2: `sf/src/main.zig` advances `ctx.lir_slots.len` only by the WRITTEN count, so
  the grouped-slot uninitialized tail is impossible.

### F-M3 fixtures stay GREEN

`unannotated_infer_samelength_xmod` and `unannotated_infer_stmtexpr_xmod`: dump rc=0 /
5 `.c` / gcc-clean / link rc=0 / **run rc=0**, stdout `abc|3` / `xyz|3`. Corpus OK.

### Gates

`check_emit_support.sh` 5/5; `verify_upgraded.sh` → `CLOSEOUT OK` (all goldens
byte-identical); the 4-MD5 emission rows intentionally re-baselined (the string-literal
type change moves every dump; runtime unchanged — `verify_upgraded.sh` byte-identical).


# mi_matrix corpus — expected-fail manifest (v89 2026-09-15)

## Residual latent risks declared (v89 2026-09-15) — Task 0g (I) [SUPERSEDED by v90 for F-M4/T0b]

Track-4 Task 0g declares and pins the residual latent risks the earlier Track-4 reviews
left unpinned. **No `sf/src` change** (any fix is Task 0h); reference compiler = the
post-Task-0f fixed point `97cd5a033156119339ebffc15b575c5d`. Four new corpus dirs; the 637
v88 dirs are class-identical (zero movement). Corpus `-s0` universe **641 dirs** =
**599 OK / 37 GREEN / 4 FAIL / 1 ICE / 0 CRASH**; the delta vs v88 (`637 = 596 OK / 37
GREEN / 4 FAIL / 0 ICE`) is exactly the four new dirs: +3 OK, +1 ICE.

### F-M4 — non-literal `*const u8` → `[]const u8` silently length-1 (runtime-RED; corpus class OK) [FIXED in v90 — now compile-FAIL]

New dir `nonliteral_ptr_to_slice_xmod`. `sf/src/lower.zig` `materializeInto`'s
no-wrap-layer path (`:2029-2035`) and error-union/optional payload path (`:2048-2050`)
synthesize a `string_to_slice` coercion with `.node_idx = src_node` and call
`applyCoercion`, which sets the slice length from the literal ONLY when `node_idx` is an
`AstKind.string_literal` — otherwise `sllen = 1` (`:6633`). `classifyCoercion` returns
`string_to_slice` for ANY `*const u8`/`*const c_char` → `[]const u8` (`coercion.zig:193-200`),
so a NON-literal pointer coerced to a slice on this path silently becomes a length-1 slice.

Reachable construct (verified): `fn pick(p: *const u8, q: *const u8, c: bool) []const u8 {
var s: []const u8 = if (c) p else q; return s; }` called with `"hello"` / `"world!!"`. The
if-expr arms are identifier nodes, so the emitted C hard-codes `len = 1`:
`zT_6 = 1; zT_5.ptr = p; zT_5.len = zT_6;`. RED: dump rc=0 / 5 `.c` / gcc-clean / link rc=0 /
**run rc=133**, stdout `h|1` then `w|1`. GREEN contract: `hello|5` then `world!!|7`, run rc=0.

### T0b — `[*]*Task` element field store (frontend compile-time reject; classifier ICE-buckets `error[3043]`) [FIXED in v90 — now GREEN]

New dir `taskptr_field_store_xmod`. `s.tasks[0].cancel_requested = true` on a `[*]*Task`
field: `lowerFieldStore` (`sf/src/lower.zig:1740-1831`) unwraps exactly ONE pointer level
(`:1744-1748`) leaving `*Task` (not a struct), so the final `else` calls
`iceFieldStoreUnsupported` (`:1827`). Exact diagnostic: `error[3043]: internal:
unsupported field-store base (node 64)`; dump rc=3, ZERO `.c`. The canonical corpus
classifier's ICE regex (`error\[(48|3042|9001|3043)\]`, QUICK_REF.md:151) buckets it as
**ICE**, not FAIL — recorded here as a frontend compile-time reject with the exact
diagnostic. Workaround already in-tree: `sf/src/std_async.zig:222-232` routes the store
through a local `*Task`. Declared, NOT fixed (Task 0h).

### F-M3 — un-annotated same-length switch/if now infer `[]const u8` (characterization; GREEN today)

Two new dirs pin the NEW inference breadth Task 0f gave the un-annotated switch/if
expressions (both were pointer-to-array pre-Task-0f):
- `unannotated_infer_samelength_xmod` — `var s = switch (c) { .A => "abc", .B => "xyz" };`
  (SAME-length literals).
- `unannotated_infer_stmtexpr_xmod` — `var s = if (c) "abc" else "xyz";` (statement-position
  literal if-expr).

Both: dump rc=0 / 5 `.c` / gcc-clean / link rc=0 / **run rc=0**, stdout `abc|3` then
`xyz|3`; the `s.len` direct assertion exercises the slice. Corpus class **OK** (runtime
GREEN), permanent regression guards. No defect.

### Closed / by-design items recorded (no fixture)

- **T0b-M1** — `Scheduler.in_task` is public: **by-design**; Z98 has no private fields.
- **D-M1 / D-M3** — cosmetic / closed (no action).
- **D-M2** — fixed in Task 0f.
- **T0-M2** — latent invariant dependency: module ids are dense, so the `grouped` tail is
  not currently reachable; to be made impossible in Task 0h, **NOT fixed here**.


## Residual string->slice gaps CLOSED (v88 2026-09-15) — Task 0f (F)

Track-4 Task 0f closes the two residual string->slice gaps Task 0e declared (S20
un-annotated inference, S21 error-union/optional payload). **`sf/src` change**:
`sf/src/semantic_analyzer.zig` (S20) + `sf/src/lower.zig` (S21). Reference compiler =
the post-Task-0d fixed point `7297eb442d012f6e07b60617c4f8e4e8`; NEW fixed point
`97cd5a033156119339ebffc15b575c5d` (two-hop closure). The 8 S21 dirs are **REMOVED**
from this manifest (they are GREEN now, not compile-fails). Corpus `-s0` universe
**637 dirs** = **596 OK / 37 GREEN / 4 FAIL / 0 ICE / 0 CRASH**; vs the pre-Task-0f
reference (637 = 587 OK / 37 GREEN / 13 FAIL) the movement is **+9 OK / -9 FAIL** =
exactly the 8 S21 dirs + the new `switch_unannotated_direct_xmod`, with **zero class
movement on the 628 common dirs**.

### S20 — un-annotated switch/if expression inference (FIXED; GREEN, corpus OK)

7 dirs: `switch_unannotated_str_xmod`, `switch_unannotated_diffstr_xmod`,
`if_unannotated_str_xmod`, the three cross-module `..._xmod_xmod` variants (the
expression lives in a NON-last module), and the direct-`s.len` facet
`switch_unannotated_direct_xmod` (added by Task 0f Step 3 — previously declared in prose
only). Each: dump rc=0 / gcc-clean / link rc=0 / **run rc=0** now. GREEN stdout:
`alpha\r\n|7` then `gamma\r\n|7` (equal-length), `beta\r\n|6` (diff-length).

Fix: in `semanticAnalyzerResolveSwitchExpr` / `semanticAnalyzerResolveIfExpr`, when there
is NO expected type a string-literal prong/branch peer-type-resolves the result to
`[]const u8` (`typeRegistryGetOrCreateSlice(TYPE_U8, true)`) and the `string_to_slice`
coercion is recorded on each prong/branch node — not the first prong's `*const [N:0]u8`.
The direct-`s.len` fixture was a gcc compile-FAIL pre-fix (`'zT_..' undeclared`) and now
compiles and prints the full string + length.

### S21 — error-union/optional payload string literals (FIXED; 8 dirs REMOVED)

The 8 dirs (`errunion_payload_str_xmod`, `opt_payload_str_xmod`,
`errunion_payload_callarg_xmod`, `opt_payload_callarg_xmod`,
`errunion_payload_varinit_xmod`, `opt_payload_varinit_xmod`,
`errunion_payload_field_xmod`, `opt_payload_field_xmod`) now dump rc=0 / gcc-clean /
link rc=0 / **run rc=0** (stdout `alpha\r\n`). Root was `materializeInto`'s payload path
(`sf/src/lower.zig`) never applying the inner `string_to_slice` before wrapping; the
payload path now applies it BEFORE the `wrap_error_ok`/`wrap_optional` layer (and also on
the no-wrap-layer direct case, e.g. a `catch`/`orelse` RHS payload). **Removed from this
manifest** (no longer compile-fails).

### Task 0c-reported incidental gaps (still declared; out of Task 0f scope)

| fixture | class | evidence |
|---|---|---|
| `array_of_slices_literal_xmod` | compile-FAIL | dump rc=0 (5 `.c`), gcc FAIL `error: assignment to expression with array type` (array-of-slices literal `[2][]const u8`) |
| `bare_enum_literal_xmod` | **RESOLVED by Task 0m (v94)** — runtime-GREEN | Task 0m family D resolves the bare plain-enum literal to the expected enum type and records its member value, so the value-position lowering is correct: run rc=0, stdout `O` (was run rc=133). The historical v88 text follows: dump rc=0 / gcc-clean / link rc=0 / run rc=133; a bare plain-enum literal in value position is mis-lowered (`var c: C = .A` → wrong `@enumToInt`; a switch over a bare-literal global takes the wrong prong). Distinct from S20/S21; was out of Task 0f scope. |

Reconciliation: post-Task-0f corpus **637 = 596 OK / 37 GREEN / 4 FAIL / 0 ICE / 0
CRASH**. The 4 FAILs = `array_of_slices_literal_xmod` (the Task 0c compile-gap above) +
the 3 documented emission-inspection dirs `callconv_cdecl_fnptr_xmod` /
`callconv_nonpub_stdcall_xmod` / `callconv_stdcall_fnptr_xmod`. The 37 GREEN set is
unchanged. The prior v87 section (Task 0e, `636 = 587 OK / 37 GREEN / 12 FAIL`) is
superseded by this v88 section; the v86 multi-module emission section below is retained
verbatim as the historical record.


## Multi-module `__Z98Step_<f>` emission fix (v86 2026-09-15)

Track-4 Task 0 (S15 emitter fix): synthesized async steps are now emitted in the
`.c`/`.h` of the module that owns them (matched to `LirFunction.module_id`)
instead of only in the last-emitted module's contiguous lowering run. The
per-module (`-o` / `--output-dir`) path stable-groups `lir_slots` by owning
module before emission; `emitModuleFile`/`emitModuleHeaderFile` additionally skip
functions not owned by the file's module. The single-file `--dump-c89` path
already emitted every slot and is unchanged. Self-emission fixed point moved
`027377296b2e38402ff8470f5c429eb8` → **`b844bfb5bedc453c2b385d37af558363`**
(two-hop closure `hop1 == hop2`); seed NOT rotated (Task 6).

Corpus `-s0` universe **613 dirs** = **573 OK / 37 GREEN / 3 FAIL / 0 ICE /
0 CRASH**; `-ffast` == `-fsafe` zero-asymmetric. Vs the same 613-dir universe on
the pre-fix compiler (571 OK / 37 GREEN / 5 FAIL) exactly **two async dirs flip
FAIL→OK**:
- `async_step_nonlast_xmod` (coroutine in a NON-LAST module) — was the v85
  expected-fail (`'zF_4970EAC2___Z98Step_caller' undeclared`); now OK.
- `async_step_midmodule_xmod` (NEW; coroutine in the MIDDLE of three modules) —
  FAIL on the pre-fix compiler, now OK.

The 3 FAILs are the documented `callconv_cdecl_fnptr_xmod` /
`callconv_nonpub_stdcall_xmod` / `callconv_stdcall_fnptr_xmod`
emission-inspection set, byte-identical to v85. All 612 v85 dirs are
class-identical except `async_step_nonlast_xmod` (FAIL→OK); the +1 new dir is
`async_step_midmodule_xmod` (OK). `async_libctx_mix_xmod` (last-module coroutine)
stays OK.

## Async concerns wave (v85 2026-09-15)

Track 2 + Track 3 concerns wave (`d7ea6667`): the compiler await-site child
bump rounds `used` up to 8 before adding `fsz` (mirrors `std.async.contextAlloc`)
and `-fsafe` `@asyncInit` now traps when a compile-time-known `buf.len` is below
`@asyncFrameSize(fn)`. Self-emission fixed point moved
`7b515420f749604c1765c2b1edd0d654` → **`027377296b2e38402ff8470f5c429eb8`**
(two-hop closure `hop1 == hop2`); seed **v18 → v19** (archive md5
`a9ded441846f54f1d02373d3f4da9142` → `23a16154e83736cf6b636685396a124a`).

Corpus `-s0` universe **612 dirs** = **571 OK / 37 GREEN / 4 FAIL / 0 ICE /
0 CRASH**; `-ffast` == `-fsafe` zero-asymmetric. Vs the v84 manifest
(611 = 571 OK / 37 GREEN / 3 FAIL) the **+1 new dir is
`async_step_nonlast_xmod`**, an **expected-fail** (FAIL(gcc)): the coroutine
lives in a NON-LAST module and `@asyncInit` references `__Z98Step_caller`, which
the emitter never emits (synthesized steps are appended after the module loop;
the C emitter consumes only contiguous per-module runs), so `main_*.c` fails gcc
with `'zF_4970EAC2___Z98Step_caller' undeclared`. The emitter fix is **Track 4**;
the fixture is written now so it lands with it. The 611 common dirs are
class-identical (GREEN set + the 3-FAIL emission-inspection set byte-identical).

Changed fixtures (all still OK): `async_pool_xmod` root buffer `64 → 80`
(`level1` frame 80); `async_suspend_store_xmod` root buffer `64 → 80` (`worker`
frame 80); `async_await_xmod` root buffer `128 → 72` + `@asyncFrameSize(caller)`
pin (verified 72); `async_libctx_mix_xmod` comment only (documents the
last-imported-module placement that dodges the emission gap).

## Cross-track async ABI fix — Rule A (v84 2026-09-15)

Track 2 + Track 3 ABI fix (`d2629f9c`): the compiler Context header moved
**12 → 16 bytes** (`CTX_POOL_OFF = 16`, matching `std.async`'s `HEADER_SIZE`),
and **every frame size is padded to a multiple of 8**. This moves the
self-emission fixed point `f5ee84800dd32d7c440bb383c10edb55` →
**`7b515420f749604c1765c2b1edd0d654`** (two-hop closure `hop1 == hop2`) and
rotates the seed **v17 → v18** (archive md5 `0f04224c55a948f47bc72ec47e0374fb` →
`a9ded441846f54f1d02373d3f4da9142`).

Corpus `-s0` universe **611 dirs** = **571 OK / 37 GREEN / 3 FAIL / 0 ICE /
0 CRASH**; `-ffast` == `-fsafe` zero-asymmetric. Vs the v83 manifest
(610 = 570 OK / 37 GREEN / 3 FAIL) the **+1 new dir is `async_libctx_mix_xmod`**
(OK; mixed library + compiler Context path). The 610 common dirs are
class-identical: the GREEN set and the 3-FAIL emission-inspection set are
byte-for-byte the same, and the changed fixtures `async_frame_xmod`
(pin `68 → 72`), `async_await_xmod` (root buffer `64 → 128`; root frame now 72),
and `async_pool_xmod` (comment only) stay **OK**.

## std.async 9-module install (v83 2026-09-15)

Track 3 (`2026-09-13-std-async-plan.md`) landed `sf/src/std_async.zig` and its
`std.zig` re-export, and installed it at every std touchpoint (9-file `lib/`).
No compiler-graph change: the self-emission fixed point is UNMOVED
`f5ee84800dd32d7c440bb383c10edb55` (closeout seed rotation v16 → v17 only adds
the 9th `lib/` module; internal binary unchanged; archive md5
`e04b4063c554c90a51c34f6736fc1346` → `0f04224c55a948f47bc72ec47e0374fb`).
Corpus `-s0` universe **610 dirs** = **570 OK / 37 GREEN / 3 FAIL / 0 ICE /
0 CRASH**; `-ffast` == `-fsafe` zero-asymmetric. Seven new OK dirs:
`stdlib_async_pool_xmod`, `stdlib_async_headerexact_xmod`,
`stdlib_async_f64align_xmod`, `stdlib_async_sched_xmod`,
`stdlib_async_oom_xmod`, `stdlib_async_await_xmod`,
`stdlib_async_cancelall_xmod`.

Reconciliation: v82 was 603 = 563 OK / 37 GREEN / 3 FAIL; +7 new OK fixtures =
**610 = 570 OK / 37 GREEN / 3 FAIL**, the 603 common dirs class-identical. (The
brief/operator target `606 = 567/36/3` predates v82 — it is the stale v80
baseline 599 = 560/36/3 + 7; the actual v82 baseline is 603 = 563/37/3.)

## Fix-wave fixtures + seed v16 closeout (v82 2026-09-15)

Track 2 async compiler core closeout re-run 2, after the final whole-branch review
fix wave F1 `7d81effc` / F2 `3181b6a8` / F3 `7f1a2288` / F4 `06c3e195`.
Measurement compiler = the two-hop closure binary **`f5ee84800dd32d7c440bb383c10edb55`**
(`-ffast`), rebuilt from the committed seed **v15** `eda943dc…` (hop1 == hop2). Seed
rotated **v15 → v16** (archive md5 `e04b4063c554c90a51c34f6736fc1346`, internal
`zig1` md5 `f5ee8480…`, `gen/` 45 `.c` + 46 `.h`).

Corpus `-s0` universe **603 dirs** (`scripts/corpus/list_corpus_dirs.sh`) =
**563 OK / 37 GREEN / 3 emission-inspection (expected standalone gcc-FAIL)**,
`-ffast` == `-fsafe` **zero-asymmetric**. Vs the v81 manifest (602 = 562 OK / 37
GREEN / 3 FAIL) the ONLY change is the new F4 fixture `async_resume_arg_xmod` (OK);
the 602 common dirs are class-identical. Vs the pre-fix-wave compiler (seed v15
`eda943dc`, same 603-dir universe) the only class movements are
`async_frame_temps_xmod` CRASH→OK (F1) and `async_defer_error_xmod` OK→GREEN (F3);
the F2 (`async_state_width_xmod`) and F4 (`async_resume_arg_xmod`) fixtures are
**OK** pre and post (their fixes are runtime-only — the compile classifier cannot
see them). The 3 FAILs remain the documented `callconv_cdecl_fnptr_xmod` /
`callconv_nonpub_stdcall_xmod` / `callconv_stdcall_fnptr_xmod` emission-inspection
rows.

### Fix-wave fixtures (v82 classes, from the actual corpus map)

| fixture | class | fix | note |
|---|---|---|---|
| `async_frame_temps_xmod` | OK | F1 | was CRASH (frame-layout panic); already recorded at v81 |
| `async_state_width_xmod` | OK | F2 | runtime-only fix (u8 state truncation); compile class unchanged |
| `async_defer_error_xmod` | GREEN | F3 | `error[3019]`; already recorded at v81 |
| `async_resume_arg_xmod` | OK | F4 | new dir at v82; runtime-only fix (`@asyncResume` arg) |

Note: the re-run supplement labels `async_state_width_xmod` / `async_resume_arg_xmod`
as "new GREEN fixtures"; the actual corpus map classifies both **OK** (dump rc=0,
4 `.c`, gcc clean), which is also what the required header counts `563 OK / 37
GREEN` mandate. Recorded as OK (derived from the actual map, not guessed).

### 4-MD5 gate rows + fixed point (v82)

All eight 4-MD5 gate rows (default `-fsafe` + `-ffast`) are byte-identical to v81
(re-dumped stdout-only from the repo root with `f5ee8480`):

- `-fsafe`: gol `e6afce418718f4adf2525956e17f6bc9`, lisp
  `a3ba58098357164d644d321015550874`, json `99514d39dcbfddd297ccd12e15a0cb78`,
  mud `07ec234e3f0214e2eb01aabad1676e0a`.
- `-ffast`: gol `e023d3cd0bfb23346ac800725c5192f1`, lisp
  `21747e2acf177947ad499149bb3fdc98`, json `2f08bf260bf2b6813fa4d70ffbc88aa9`,
  mud `ac1579907ce84efa2f9014187070bf94`.

- **Fixed point moved** `09c86411f7edf6b259b0ef1dace49b51` (v81/F3) →
  **`f5ee84800dd32d7c440bb383c10edb55`** (`-ffast`; two-hop closure `hop1 == hop2`
  from the committed seed v15 `eda943dc…`). Seed rotated **v15 → v16** (archive
  `e04b4063…`, internal `f5ee8480…`); post-rotation closure `hop1 == hop2 ==
  f5ee8480…`.

## Async ERR_3018 gated + ERR_3019 defer ban (v81 2026-09-15)

Track 2 async compiler core final whole-branch review finding #3 (operator ruling: fix in code),
Fix F3. Measurement compiler = the two-hop closure binary
**`09c86411f7edf6b259b0ef1dace49b51`** (`-ffast`), rebuilt from the committed seed **v15**
`eda943dc…` (hop1 == hop2). Seed **NOT** rotated; the new fixed point is recorded.

- **`ERR_3018` is a real check** (`sf/src/semantic_analyzer.zig`): the sema `@asyncSuspend` arm
  consults `asyncIsSuspending(suspending_fns, module_id, current_fn_name)` and emits only when
  the enclosing function is not suspending; `async_analysis_ready` is now `true`. It is
  **reachable** (a module-scope `@asyncSuspend` → exactly one `error[3018]`, 0 `.c`) and cannot
  false-positive (Stage 1 self-seeds any function whose body directly contains `@asyncSuspend`).
  All 11 async run fixtures + 4 guards stay green.
- **`ERR_3019` implemented**: a `defer_depth` counter in the sema statement walk;
  `@asyncSuspend`/`@asyncInit`/`@asyncResume` inside a `defer`/`errdefer` body emits exactly one
  `error[3019]` at the builtin's span.

Corpus `-s0` universe **602 dirs** (`scripts/corpus/list_corpus_dirs.sh`) = **562 OK / 37 GREEN /
3 emission-inspection (expected standalone gcc-FAIL)**, `-ffast` == `-fsafe` **zero-asymmetric**.
Vs the pre-F3 compiler (`ae5e2f09`, 601 dirs = 562 OK / 36 GREEN / 3 FAIL) the ONLY movement is
the new fixture `async_defer_error_xmod` GREEN; vs the v80 manifest (599 = 560 OK / 36 GREEN /
3 FAIL) the 599 common dirs are class-identical and the +3 dirs are the F1 `async_frame_temps_xmod`
(OK), F2 `async_state_width_xmod` (OK), and F3 `async_defer_error_xmod` (GREEN).

### New GREEN/reject fixture (v81)

| fixture | class | expected diagnostic |
|---|---|---|
| `async_defer_error_xmod` | GREEN | `error[3019]` (`@asyncSuspend(null)` inside a `defer` body); rc=2, exactly 1×, 0 `.c` |

### 4-MD5 gate rows + fixed point (v81)

All eight 4-MD5 gate rows (default `-fsafe` + `-ffast`) are **byte-identical PRE↔POST** when both
compilers resolve the same `lib/` (the Fix F3 change is sema-only and does not touch emission;
a `defer` body is now resolved by a recursive `semanticAnalyzerResolveStmtIter` call with
identical ordering). Absolute hashes remain path-derived (module basename-hash tokens), so they
are not re-baselined here. `check_emit_support.sh` **5/5** byte-identical.

- **Fixed point moved `eda943dc1f77a48eae039e39ea4bfe04` → `09c86411f7edf6b259b0ef1dace49b51`**
  (the `-ffast` binary; two-hop closure `hop1 == hop2` from the committed seed v15 `eda943dc…`).
  Seed **NOT** rotated (closeout-only).

## Track 2 async compiler core closeout (v80 2026-09-15)

Plan `2026-09-13-async-compiler-core-plan.md` (Track 2, async compiler core) is COMPLETE —
Tasks 1–7 (suspension analysis, frame layout, state-machine lowering, builtins/diagnostics),
the Task-8-regression I/F series Tasks 9/10 (kind-aware AST generic-walk fix), plus the Task-8
closeout. Measurement compiler = the N-hop closure binary
**`eda943dc1f77a48eae039e39ea4bfe04`** (`-ffast`), rebuilt from the committed seed **v14**
`9e6c9faad0536191f28eb60c210a0a25` (hop1 == hop2). The new committed seed is **v15**
(archive md5 `cd09877cbc373ad5c8801b93faccf188`, internal `zig1` md5 `eda943dc…`, `gen/`
45 `.c` + 46 `.h` — the +3 module growth over v14's 42/43 is Track-2's
`async_analysis`/`async_frame_layout`/`async_state_machine` modules).

Corpus `-s0` universe **599 dirs** (`scripts/corpus/list_corpus_dirs.sh`) =
**560 OK / 36 GREEN / 3 emission-inspection (expected standalone gcc-FAIL)**,
`-ffast` == `-fsafe` **zero-asymmetric**. Vs the pre-Task-10 baseline (594 = 555 OK / 35 GREEN /
4 FAIL) the ONLY class movements are the intended ones: `repro/tu_void_prong` FAIL→OK (the
Task-3 `scanFunction` AST-walk OOM regression, fixed by Task 10), the three new
`ast_walk_{capture_prong,error_set,subtree_break}_xmod` FAIL→OK, and
`analyzer_for_body_xmod` OK→GREEN; the 5 new dirs are the Task-10 fixtures (the fourth,
`ast_walk_for_index_xmod`, was already OK pre-fix — its interned index id did not collide —
and stays OK). Zero unexpected movement on the other pre-existing dirs.

### New GREEN/reject fixture (v80)

| fixture | class | expected diagnostic |
|---|---|---|
| `analyzer_for_body_xmod` | GREEN | `error[3035]` double free (the enum member `ERR_2005_DOUBLE_FREE`'s auto-incremented value; the analyzer now descends into the `for` body, Task 10 Part 2) |

### New OK fixtures (v80, Task 10)

`ast_walk_capture_prong_xmod`, `ast_walk_for_index_xmod`, `ast_walk_error_set_xmod`,
`ast_walk_subtree_break_xmod` — all `dump rc=0`, 4 `.c`, gcc `-m32 -std=c89 -O0 -Wall …` clean,
self-contained link, `run rc=0`. (`repro/tu_void_prong` also returns OK.)

### 4-MD5 gate rows + fixed point (v80)

All eight 4-MD5 gate rows (default `-fsafe` + `-ffast`) are **UNCHANGED** from v79 and
deterministic: `-fsafe` gol `e6afce418718f4adf2525956e17f6bc9` / lisp
`a3ba58098357164d644d321015550874` / json `99514d39dcbfddd297ccd12e15a0cb78` / mud
`07ec234e3f0214e2eb01aabad1676e0a`; `-ffast` gol `e023d3cd0bfb23346ac800725c5192f1` / lisp
`21747e2acf177947ad499149bb3fdc98` / json `2f08bf260bf2b6813fa4d70ffbc88aa9` / mud
`ac1579907ce84efa2f9014187070bf94`.

- **Fixed point `eda943dc1f77a48eae039e39ea4bfe04`** (the `-ffast` binary; two-hop closure
  `hop1 == hop2` from the committed seed v14 `9e6c9faa…`). Seed rotated **v14 → v15** via
  `scripts/seed/archive_seed.sh` → archive md5 `cd09877cbc373ad5c8801b93faccf188`, internal
  `zig1` md5 `eda943dc…`, `gen/` 45 `.c` + 46 `.h` (8,337,928 B), `lib/` 8 std `.zig`;
  post-rotation `build_from_seed.sh` closure `hop1 == hop2 == eda943dc…`;
  `check_emit_support.sh` 5/5; self-compile `-ffast` rc=0 / 48 `.c` / 0 `error[` / 0 PANIC;
  strict `gcc -m32 -std=c89 -O3 -Wall -Wextra -fsyntax-only` 0 errors.

### Async fixtures + guards (v80, all GREEN)

9 async run fixtures (`async_await`, `_ret`, `_quick`, `_multi`, `async_suspend_store`,
`async_frame`, `_branch`, `_args`, `async_pool`): dump rc=0 / 4 `.c` / gcc clean / link rc=0 /
run rc=0; off-corpus `known_excluded/async_susp_markers` + `async_susp_xmod` likewise. Guards:
`async_callgraph_xmod` rc=0/5c, `async_builtin_scope_xmod` rc=0/4c,
`async_framesize_invalid_xmod` rc=2/1×`error[3046]`/0c, `async_fnptr_error_xmod`
rc=2/1×`error[3017]`/0c.

## Win9x calling-convention final-review fix (v79 2026-09-14)

Plan `2026-09-13-win9x-calling-convention-plan.md` (Track 1) final whole-branch review **Important**
finding fixed (plan Amendment 7): `sf/src/semantic_analyzer.zig:481/:491/:497` built the fn type for a
**non-pub** cross-module `extern "stdcall"` value with convention 0 (cdecl) while lowering carried
stdcall, so `var s: CbS = lib.cc_std;` (with `CbS = extern "stdcall" fn(i32) i32`) raised a false
`error[3000]` and the same value was silently accepted by the cdecl pointer. All six
`typeRegistryGetOrCreateFn` sites now pass `proto.call_conv`. New regression fixture
`callconv_nonpub_stdcall_xmod` (non-pub stdcall + pub cdecl, each assigned to its matching
fn-pointer type). Measurement compiler = the N-hop closure binary **`b2eda4a50806962db5e0f90625a7da73`**
(`-ffast`, rebuilt from the committed seed v11 `62d8bd40…`; the new committed seed is **v12**).
Corpus `-s0` universe **580 dirs** = **545 OK / 32 GREEN / 3 emission-inspection (expected standalone
gcc-FAIL)**. A per-dir diff against the same classifier run on the pre-fix compiler `cd2259dd…` is
**exactly one row** (the new fixture: GREEN `error[3000]`/0 `.c` → emission-inspection FAIL); the 579
committed dirs are class-identical (**zero unexpected asymmetric movement**). All eight 4-MD5 gate rows
(default `-fsafe` + `-ffast`) are **UNCHANGED** from v78 and deterministic 2×.

### New emission-inspection fixture (v79, EXPECTED standalone gcc-FAIL — not a compiler gap)

Under the Option-B ruling (plan Amendment 4) a convention-bearing extern gets **no** emitted
`Z98_STDCALL` prototype — the C header is the sole declaration source — so a fixture that takes the
**address of a convention extern** emits a reference to a symbol no emitted header declares. This
fixture is emission-inspection only: `dump rc=0`, 5 `.c`, but the emitted `main_*.c` fails `gcc -c`
with `… undeclared`.

| fixture | dump | gcc | reason |
|---|---|---|---|
| `callconv_nonpub_stdcall_xmod` | rc=0, 5 `.c` | FAIL | non-pub stdcall extern-as-value emits `zT_1 = ((zT_6891876A_FS_int_int)cc_std);` (with the `FS_` typedef) and the pub cdecl value emits `zT_3 = zF_C51B80DD_cc_cdecl;`; no C declaration (declaration is the C header's responsibility per the ruling) |

GREEN on the pre-fix compiler (`error[3000]`, 0 `.c`, false positive); it cannot classify OK because
it takes extern addresses and is not linked.

- **Fixed point `b2eda4a50806962db5e0f90625a7da73`** (the `-ffast` binary; two-hop closure
  `hop1 == hop2` from the committed seed v11 `62d8bd40…`). Seed rotated **v11 → v12** via
  `scripts/seed/archive_seed.sh` → archive md5 `b6de9b30646e2d5f6cfa2537121329c0`, internal `zig1` md5
  `b2eda4a5…`, `gen/` 42 `.c` + 43 `.h` (7,842,184 B), `lib/` 8 std `.zig`; post-rotation
  `build_from_seed.sh` closure `hop1 == hop2 == b2eda4a5…`; `check_emit_support.sh` 5/5;
  `-osw net_bind_startup_xmod` mingw `-c` rc=0 (`-I <dump>`).

## Win9x calling-convention prelude GREEN/reject + corpus re-baseline (v78 2026-09-14)

Plan `2026-09-13-win9x-calling-convention-plan.md` (Track 1) is COMPLETE (Tasks 1–4 + closeout).
Measurement compiler = the N-hop closure binary `cd2259dde73d3a8bc22b25280459edc2` (`-ffast`), rebuilt from the
committed seed **v10** `1467d932a876402f40a56316dfcad0e5` (this plan moved the fixed point; the new committed seed is
**v11**), canonical 8-file `lib/` installed alongside the hop2 binary. Corpus `-s0` universe **579 dirs**
(`scripts/corpus/list_corpus_dirs.sh`) = **545 OK / 32 GREEN / 2 emission-inspection (expected standalone gcc-FAIL)**.
Vs the committed v77 baseline (570 = 541 OK / 29 GREEN / 0 FAIL) the **570 common dirs are class-identical — zero
asymmetric movement**; the 9 new `callconv_*` dirs contribute 4 OK + 3 GREEN + 2 emission-inspection FAIL. The
classifier resolves each dir's entry (`<dir>/main.zig`, else `<base>.zig`) and treats a frontend `error[NNNN]` with 0
`.c` as GREEN; "OK" requires every emitted `.c` to `gcc -c` clean.

### New GREEN/reject fixtures (v78)

| fixture | class | expected diagnostic |
|---|---|---|
| `callconv_unknown_green_xmod` | GREEN | `error[3045]` unknown calling convention |
| `callconv_fnptr_mismatch_green_xmod` | GREEN | `error[3000]` cross-convention fn-pointer assignment |
| `callconv_stdcall_variadic_green_xmod` | GREEN | `error[3012]` variadic `stdcall` |

All three classify `dump rc=2`, **0 `.c`**, the expected diagnostic (verified 2026-09-14 on `cd2259dd…`).

### New emission-inspection fixtures (v78, EXPECTED standalone gcc-FAIL — not compiler gaps)

Under the Option-B ruling (plan Amendment 4) a convention-bearing extern gets **no** emitted `Z98_STDCALL` prototype —
the C header is the sole declaration source — so a fixture that takes the **address of a convention extern** emits a
reference to a symbol no emitted header declares. These two fixtures are emission-inspection only (their own comments
say so): `dump rc=0`, 4 `.c` (incl. the self-contained runtime support), but the emitted `main_*.c` fails `gcc -c` with
`… undeclared`. They are EXPECTED to fail the standalone gcc corpus check and are documented here deliberately (the
brief's "7 fixtures → 4 OK / 3 GREEN" expectation predates Task 3R's Option-B revert, which made standalone
non-header-covered convention fixtures emission-inspection only):

| fixture | dump | gcc | reason |
|---|---|---|---|
| `callconv_cdecl_fnptr_xmod` | rc=0, 4 `.c` | FAIL | extern-as-value emitted with the MANGLED name `zF_…_z98_cdecl_probe`; no C declaration (default-cdecl byte-identity regression fixture) |
| `callconv_stdcall_fnptr_xmod` | rc=0, 4 `.c` | FAIL | extern-as-value emitted as `((FS_…)z98_stdcall_probe)`; no C declaration (declaration is the C header's responsibility per the ruling) |

The remaining new `callconv_*` dirs classify OK: `callconv_default_cdecl_xmod`, `callconv_explicit_cdecl_xmod`,
`callconv_stdcall_decl_xmod` (`@isWindows()`-pruned on `-osl`, so the call is eliminated), `callconv_mixed_fnptr_typedef_xmod`.

### Re-baselined 4-MD5 gate rows + fixed point (v78)

ALL FOUR rows moved in BOTH modes (Task 4 migrated all 15 `std_net` Win32 externs to `extern "stdcall"`; every gate
program re-exports `std_net`, so each dump gains the `FS_…` typedefs + use-site casts). Deterministic 2×; runtime
output unchanged (mud verified byte-identical).

| program | default `-fsafe` | `-ffast` byte-anchor |
|---|---|---|
| `examples/z98/game_of_life/main.zig` | `e6afce418718f4adf2525956e17f6bc9` | `e023d3cd0bfb23346ac800725c5192f1` |
| `examples/z98/lisp_interpreter_curr/main.zig` | `a3ba58098357164d644d321015550874` | `21747e2acf177947ad499149bb3fdc98` |
| `examples/z98/json_parser/main.zig` | `99514d39dcbfddd297ccd12e15a0cb78` | `2f08bf260bf2b6813fa4d70ffbc88aa9` |
| `examples/z98/mud_server/main.zig` | `07ec234e3f0214e2eb01aabad1676e0a` | `ac1579907ce84efa2f9014187070bf94` |

- **Fixed point `cd2259dde73d3a8bc22b25280459edc2`** (the `-ffast` binary; two-hop closure from the committed seed v10
  `1467d932…` → hop1==hop2==`cd2259dd…`). Seed rotated **v10 → v11** via `scripts/seed/archive_seed.sh` → archive md5
  `62d8bd40cefd5d604b1c66a80ac0749d`, internal `zig1` md5 `cd2259dd…`, `gen/` 42 `.c` + 43 `.h`; post-rotation
  `build_from_seed.sh` closure hop1==hop2==`cd2259dd…`; `check_emit_support.sh` 5/5; `-osw net_bind_startup_xmod`
  mingw `-c` rc=0 (needs `-I <dump>` for the emitted `net_prelude.h`).


## C89-AHEAD features GREEN/reject + `safe_*` trap contract (v77 2026-09-13)

Plan `2026-09-09-c89-ahead-features-plan.md` is COMPLETE (A1–A13; A12 closeout battery, A13 docs GATE +
seed rotation). Measurement compiler = the N-hop closure binary `1467d932a876402f40a56316dfcad0e5`
(`-ffast`), rebuilt from the committed seed v9 `4da59bb1…` (`hop1 a3e1c410… → hop2==hop3 1467d932…`),
canonical 8-file `lib/`. Corpus `-s0` universe **570 dirs** (`scripts/corpus/list_corpus_dirs.sh`) =
**541 OK / 29 GREEN / 0 FAIL / 0 ICE / 0 CRASH**, `-ffast`==`-fsafe` **zero-asymmetric**. The 29
GREEN/reject fixtures below all classify `dump rc=2`, **0 `.c`**, expected diagnostic (verified
2026-09-13 on `1467d932…`):

| fixture | class | expected diagnostic |
|---|---|---|
| `net_builtin_test` | GREEN | `error[3000]` unsupported builtin (removed `@socket*`) |
| `cleandiag_unknown_builtin_xmod` | GREEN | `error[3000]` unsupported builtin function |
| `cleandiag_unknown_type_xmod` | GREEN | `error[3000]` unknown type in variable declaration |
| `packed_union_struct_wholemember_xmod` | GREEN | `error[3000]` whole-member packed-union move reject |
| `diag_uninit_var_xmod` | GREEN | `error[3014]` uninitialized variable |
| `diag_ignored_error_xmod` | GREEN | `error[3015]` ignored error |
| `diag_missing_return_xmod` | GREEN | `error[3003]` missing return |
| `orelse_requires_optional_xmod` | GREEN | `error[3016]` orelse requires an optional operand |
| `orelse_error_union_xmod` | GREEN | `error[3016]` orelse requires an optional operand (use `catch`) |
| `volatile_drop_ptr_xmod` | GREEN | `error[3000]` cannot implicitly discard `volatile` (use `@volatileCast`) |
| `volatile_drop_manyptr_xmod` | GREEN | `error[3000]` cannot implicitly discard `volatile` |
| `volatile_drop_slice_xmod` | GREEN | `error[3000]` cannot implicitly discard `volatile` |
| `volatile_drop_fnparam_xmod` | GREEN | `error[3000]` cannot implicitly discard `volatile` |
| `volatile_drop_optional_xmod` | GREEN | `error[3000]` cannot implicitly discard `volatile` |
| `volatile_drop_void_xmod` | GREEN | `error[3000]` cannot implicitly discard `volatile` |
| `volatile_drop_array_slice_xmod` | GREEN | `error[3000]` cannot implicitly discard `volatile` (`*volatile [N]T → []T`) |
| `volatile_ptrcast_drop_xmod` | GREEN | `error[3000]` `@ptrCast` cannot discard `volatile` |
| `volatile_cast_wrong_base_xmod` | GREEN | `error[3000]` `@volatileCast` wrong base type |
| `volatile_cast_nonvolatile_xmod` | GREEN | `error[3000]` `@volatileCast` source is not volatile |
| `eu_assign_incompat_payload` | GREEN | `error[3000]` (documented EU green-guard) |
| `euvoid_val_catch` | GREEN | `error[3000]` (documented EU green-guard) |
| `field_access_optional` | GREEN | `error[3000]` (documented optional green-guard) |
| `var_declared_void` | GREEN | `error[3000]` (documented void-decl green-guard) |
| `parsergap_slice_expr_xmod` | GREEN | `error[2000]` + `error[3000]` (documented scalar-base slice reject) |
| `strictzig_brace_if_xmod` | GREEN | `error[2000]` (documented brace-less-if reject) |
| `parsergap_selfblok_xmod` | GREEN | `error[2000]` (documented brace-less-if reject) |
| `parsergap_strict_comma_xmod` | GREEN | `error[2000]` (documented missing-comma reject) |
| `self_embed_optional_cycle` | GREEN | `error[24]` circular type (real Zig rejects `?X` value self-ref) |
| `emission_pal_xmod` | GREEN | `error[20]` (documented compiler-internal import reject) |

29 fixtures total = the 10 documented pre-C89-AHEAD green-guards + 19 C89-AHEAD rejects (9 clean
diagnostics: `net_builtin_test`, `cleandiag_*`×2, `packed_union_struct_wholemember`, `diag_*`×3,
`orelse_*`×2; 10 volatile qualifier rejects).

### `safe_*` / `trap_*` RED→GREEN trap contract

Under pre-C89-AHEAD **`-ffast`** (RED) these programs ran with **no runtime guard** — silent bad output
or raw UB (div/mod-by-zero and `INT_MIN/-1` = SIGFPE **rc=136**). Under C89-AHEAD **default `-fsafe`**
(GREEN) each guard fires: `pal_trap()` → SIGTRAP **rc=133**, no silent miscompile. Control fixtures
(bounds in-range, short-circuit, mixed-sign, intcast control, overflow control, undefined poison,
unwrap guard) stay **rc=0** in both modes; `trap_*` fixtures trap in **both** modes (unconditional
`pal_trap`).

| fixture (representative) | check | pre-C89-AHEAD `-ffast` (RED) | `-fsafe` (GREEN) |
|---|---|---|---|
| `safe_bounds_read_xmod` / `_write` / `_slice` / `_field` | index-OOB | rc=0 (silent) | **rc=133** SIGTRAP |
| `safe_div_zero_xmod` / `safe_div_min_neg1_xmod` / `safe_mod_min_neg1_xmod` | div/mod zero + `INT_MIN/-1` | **rc=136** SIGFPE (raw UB) | **rc=133** SIGTRAP |
| `safe_shift_count_xmod` / `safe_int_lit_shl_{count,runtime,value}_xmod` | shift count / left-shift overflow | rc=0 (silent) | **rc=133** SIGTRAP |
| `safe_cast_overflow_xmod` / `safe_intcast_{subword,widen_sign,u64_i64,i64_u64}_xmod` | checked `@intCast` | rc=0 (silent) | **rc=133** SIGTRAP |
| `safe_int_{add,sub,mul,neg,shl}_overflow{,_u}_xmod` / `safe_ovf_*_xmod` / `safe_compound_*_xmod` | integer overflow (wrap+flag) | rc=0 (silent) | **rc=133** SIGTRAP |
| `trap_unreachable_xmod` / `trap_panic_xmod` / `trap_orelse_unreachable_xmod` / `trap_arena_exhaustion_xmod` | unconditional `pal_trap` | **rc=133** | **rc=133** |
| `safe_bounds_inbounds_xmod` / `safe_divmod_control_xmod` / `safe_int_shortcircuit_xmod` / `safe_int_mixed_sign_xmod` / `safe_intcast_control_xmod` / `safe_ovf_control_xmod` / `safe_ovr_mixsign_boundary_xmod` / `safe_unwrap_guard_xmod` / `safe_undefined_{direct,agg,poison}_xmod` | in-range / guard-prevented controls | rc=0 | rc=0 |

Fixture runtime sweep **180/180** (90 feature dirs × 2 modes) emitted+compiled+linked+ran; `-fsafe`
**42× rc=133** (38 `safe_*` guards + 4 `trap_*`) + **48× rc=0**; `-ffast` **81× rc=0 + 5× rc=136**
(SIGFPE raw div) + **4× rc=133** (`trap_*`). Every `safe≠fast` row is an intended guard fixture.

### C89-AHEAD run-GREEN fixture inventory (all class OK; `-ffast`==`-fsafe` unless noted)

- **`noreturn_*`** (7): `noreturn_{assign_rhs,call_arg,if_init,if_init_block,nested,opt_ctx,switch_init}_xmod` — rc=0 both modes.
- **`trap_*`** (4): `trap_{unreachable,panic,orelse_unreachable,arena_exhaustion}_xmod` — rc=133 both modes.
- **`typealias_*`** (18): `typealias_{prim,agg,arr,chain_arr,mptr,ptr,opt,eu,fn,slice,aint,pub_arr,pub_slice,pub_mptr,pub_aint,forms_control,arr_elem_mismatch,arr_len_mismatch}_xmod` — rc=0 both modes.
- **`arena_oom_green_xmod`**: `std.arena.alloc` OOM → `error.OutOfMemory` via `try`/`catch` — rc=0 both modes.
- **`volatile_*` accept** (4): `volatile_{mmio,fastpaths,cast_accept,add_accept}_xmod` — rc=0 both modes.
- **`diag_*_ok` / `orelse_optional_control_xmod`**: diagnostics controls (no false positives) — rc=0.

### Re-baselined 4-MD5 gate rows + fixed point (v77)

Gate table re-baselined to the **default `-fsafe`** rows with the pre-C89-AHEAD `-ffast` rows kept as
the byte anchor (operator-approved A12 STOP; `docs/sf/QUICK_REF.md` carries the same table):

| program | default `-fsafe` | `-ffast` byte-anchor |
|---|---|---|
| `examples/z98/game_of_life/main.zig` | `1eed772387ae63205e93e207dae6af52` | `a5b49350583ed79edfc7cce9eb4a6e29` |
| `examples/z98/lisp_interpreter_curr/main.zig` | `6f2267711a61a117ad6aa4a92aced4e9` | `8385ab02cb3094c4f8cb48cf010049d9` |
| `examples/z98/json_parser/main.zig` | `ccdcb6ef4b7af5be1193a89f34db5143` | `265fa6a8fc752a62b33fea169b24953e` |
| `examples/z98/mud_server/main.zig` | `5f05df6eb34986a4571e2ae8852887bf` | `c0a2d6773b207e94e1952c2880aa7b0e` |

- **Fixed point `1467d932a876402f40a56316dfcad0e5`** (the `-ffast` binary; N-hop from committed seed v9
  `4da59bb1…` → hop1 `a3e1c410…` → hop2==hop3 `1467d932…`). Seed rotated **v9 → v10** via
  `scripts/seed/archive_seed.sh` → archive md5 `ca18fc9f9af55d58147fcb7ff7a662b6`, internal `zig1` md5
  `1467d932…`, `gen/` 42 `.c` + 43 `.h`; post-rotation `build_from_seed.sh` closure
  hop1==hop2==`1467d932…`; `check_emit_support.sh` 5/5. `archive_seed.sh` now stages the gen dir's
  **emitted, mode-specific** support into `runtime/` so a gcc-only rebuild reproduces the archived
  binary exactly (canonical `-fsafe` runtime previously gave a mismatched `8a87ef6c…`).

## Packed enum(uN) fields GREEN (v76 2026-09-08) — PACK-B3

Plan `2026-09-06-arbitrary-width-enums-plan.md` (PACK-B3) is COMPLETE — `enum(uN)` arbitrary-width
backing + packed-field admission landed (T1 `a8c656ad` backing/introspect, T2-review fix `199e2662`,
T3 `b040caab` packed fields; all packed-ladder L0-L7 GREEN). The L7 fixture
`packed_enum_field_xmod` is RESOLVED and GREEN: compile-clean OK (dump rc=0, 0 `error[`, 0 PANIC,
gcc `-m32` clean) AND run-gate byte-exact 3× deterministic (RUNRC=0, stdout `1 3 1 1`, stdout md5
`69e8e92d…` ×3) — `Pixel = packed struct { on: bool, color: Color }` over `Color = enum(u3)`:
on@0 (1 bit) + green=1@1..3 (3 bits) → byte `0b00000011` = 3; `@sizeOf(Pixel)`=1,
`@enumToInt(Color.blue)`=2, `@sizeOf(Color)`=1. Measured on the reference `/tmp/fx_subfolder/zig1`
md5 **`f5c2f9d2`** (the measurement compiler — rebuilt from the committed seed via the N-hop chain:
seed v3 `e20bfb70` → hop1 `1e96b989` → hop2 `f5c2f9d2` → hop3 `f5c2f9d2` (hop2==hop3 closure, 41 `.c`
+ 42 `.h` per hop), canonical std reinstalled at `/tmp/fx_subfolder/lib`) via the authoritative
fixture_run.sh + classify1.sh recipes (full `-Wall` flag set, fresh dirs, 3 fresh runs per fixture,
stdout md5 identical 3/3). The v75 PACK-AGG-AMENDMENT section below is the historical record —
retained verbatim; the L7 row it references (GREEN-guard, clean `error[3000]` at the packed-field
gate) is the pre-fix state.

| fixture | v75 pre-fix class | v76 GREEN contract (byte-exact 3×) |
|---|---|---|
| `packed_enum_field_xmod` (L7, `enum(u3)` packed field) | GREEN-guard (rc=2, ONE error[3000] `packed struct fields must be bool or an integer type (uN/iN)…`, 0 `.c`, stderr md5 `1779f5dd…` ×3) | compile-clean **OK** + `1 3 1 1` (RUNRC=0 · stdout md5 `69e8e92d…` ×3) |

- **RESOLVED rows (fix commits):** T1 `a8c656ad` (enum(uN) arbitrary-width backing registers as a real
  type + introspect + explicit-backing typing), T2-review fix `199e2662` (@enumToInt general-path
  backing typing + fit-check unsigned normalization, no silent truncation), T3 `b040caab`
  (`semanticAnalyzerPackedFieldTypeAllowed` admits `enum_type` ONLY when it has an explicit UNSIGNED
  backing; the ≤31-bit width cap reads the backing width — `semantic_analyzer.zig` only). Field layout
  + enum ops needed no change (the packed layout and enum value ops derive width from the backing via
  `typeRegistryIntWidthBits`'s enum arm), so L7 bit-packs on@0/green@1..3 → byte 3 with no sub-carrier;
  a plain `enum` (no explicit backing) as a packed field is STILL rejected byte-identical. The fixture
  stays as a permanent regression guard.
- **zig0 retirement (operator ruling, 2026-09-08):** `enum(uN)` is the first syntax zig0's frozen C++
  front end cannot parse — `sf/src` is no longer zig0-compilable; the committed seed is the official
  self-hosted rebuild authority (`scripts/seed/build_from_seed.sh`; the `build_release.sh` zig0 path
  is dead for the current `sf/src`, kept in-tree historical). Seed v4 is the official self-hosted /
  zig0-retirement milestone.
- **Corpus reconciliation (reference `f5c2f9d2`):** full 362-dir mi_matrix `-s0` compile-gate sweep =
  **OK=348 / GREEN=9 / FAIL=5 / GCCFAIL=0 / ICE=0 / CRASH=0** — per-dir IDENTICAL to the Task-4
  stored sweep, and vs the v75 close the ONLY row movement is the intended L7 flip
  `packed_enum_field_xmod` GREEN→OK (v75 GREEN-10 → GREEN-9; the 2 collection-dir artifacts in the
  v75 accounting are not in this classifier's dir-with-`.zig` universe). All packed dirs L0-L7
  classify OK at the compile gate (`packed_union_struct_wholemember_xmod` stays GREEN-guard); their
  RED→GREEN shows at the run gate above. repro top-level 53/53 OK; examples/z98 24/24 OK. Golden 9/9
  PASS; matrix 21/21 PASS. Zero asymmetric movement.
- **4-MD5 gates byte-identical UNCHANGED (v76, NO gate re-baseline):** gol `302df36b…` / lisp
  `3591bad9…` / json `76056b97…` / mud `846106ac…` (repo-root CWD, stdout-only, dump rc=0 each).
- **Self-compile fixed point RE-BASELINED (operator-approved 2026-09-08 at the Task-4 STOP-present):
  `e20bfb7072ea10167476d8f94a9d391d` → `f5c2f9d27d613c6582ab3e79d6fec437`** — N-hop closure at HEAD
  `890302c6`: seed `e20bfb70` → hop1 `1e96b989` → hop2 `f5c2f9d2` → hop3 `f5c2f9d2` (hop2==hop3
  binary byte-identical, `cmp` clean), 41 `.c` + 42 `.h` per hop, rc=0, 0 `error[`, 0 PANIC; hop1 ≠
  hop2 is EXPECTED (seed v3 is pre-PACK-B3-flavored — one generation behind is the documented N-hop
  class). Reference binary md5 `f5c2f9d2…` (N-hop rebuilt from the committed seed at HEAD
  `890302c6`, canonical std reinstalled). Seed rotated to the new fixed point (release/seed seed v4).

## Packed-struct members of packed unions GREEN (v75 2026-09-08) — PACK-AGG AMENDMENT

Plan `2026-09-06-packed-struct-aggregates-plan.md` post-close AMENDMENT (I-1 + F-1, operator-ruled)
is COMPLETE — `packed struct` members of `packed union`s are now admitted (B6 member gate widened
to packed-struct types), union layout sizes them (member width = the inner packed struct's pk total
bits, `bit_offset` 0, `size=ceil(max/8)` min 1, align 1), and leaf access through union members
(`u.member.field`) parses, resolves, and lowers/emits to ONE accumulated `0 + inner_offset`
`load_bitfield`/`store_bitfield` — no sub-container materialization. Whole-member value moves
clean-reject: the direct read/store routes AND the agg-literal `U{.b=inner}` route each fire a
clean `error[3000]` — never silent. The two new guard fixtures `packed_union_struct_member_xmod` /
`packed_union_struct_wholemember_xmod` are GREEN: the leaf fixture is compile-clean OK (dump rc=0,
0 `error[`, 0 PANIC, gcc `-m32` clean) AND run-gate byte-exact 3× deterministic (RUNRC=0, stdout
`1 6 5 7`); the whole-member probe is GREEN-guard class (rc=2, ONE error[3000], 0 `.c`, per the
`field_access_optional`-style green-guard convention). Measured on the reference
`/tmp/fx_subfolder/zig1` md5 `1e7a705b` (rebuilt at HEAD `9bc2c751`, canonical std reinstalled) via
the authoritative fixture_run.sh + classify1.sh recipes (full `-Wall` flag set, fresh dirs, 3 fresh
runs per fixture, stdout/stderr md5 identical 3/3). The v74 PACK-AGG section below is the
historical record — retained verbatim; the fix commits its rows reference are the Tasks 2-4 chain +
this AMENDMENT.

| fixture | v75 class | v75 GREEN contract (byte-exact 3×) |
|---|---|---|
| `packed_union_struct_member_xmod` (leaf access) | compile-clean **OK** (dump rc=0, 0 `error[`, 0 PANIC) | `1 6 5 7` (RUNRC=0 · stdout md5 `8c784da5…` ×3) |
| `packed_union_struct_wholemember_xmod` (whole-member probe) | **GREEN** (guard class) | rc=2 · ONE error[3000] · 0 `.c` (stderr md5 `66e75896…` ×3) |

- **RESOLVED rows (fix commits):** F-1 `03896568` (packed-struct members of packed unions + leaf
  access through union members: B6 member gate admits packed-struct types; union layout sizes a
  packed-struct member at width = its inner pk total bits (`typeRegistryGetPackedTotalBits`), so a
  packed struct member of a packed union is representable; chain-analyze first-packed scan + union
  accumulation dispatch generalized to packed-union containers — leaf `u.member.field` reads/stores
  lower to ONE accumulated-offset `load_bitfield`/`store_bitfield` at `0 + inner_offset`, no
  sub-container materialization) + RULING-A whole-member guards (direct read AND direct store each
  clean-reject with `error[3000]` "cannot read/assign a whole packed-struct value out of/to a
  packed union member (bit-slice … not supported)") + review fix A2 `9bc2c751` (the agg-literal
  whole-member route `U{.b=inner}` — a third whole-member path whose packed-union agg-literal arm
  lacked the member-type guard → silent wrong code — now fires ONE clean `error[3000]` with the
  verbatim direct-store wording; scalar-member agg-literal path unchanged). Run-gate: leaf fixture
  stdout `1 6 5 7`→`8c784da5…` (×3, RUNRC=0); whole-member probe rc=2 / ONE error[3000] / 0 `.c` /
  stderr md5 `66e75896…` (×3). Whole-member value moves now clean-reject on ALL THREE routes —
  direct read, direct store, agg-literal — never silent. Each fixture stays as a permanent
  regression guard.
- **Corpus reconciliation (reference `1e7a705b`):** full 417-dir `-s0` compile-gate sweep =
  **OK=400 / GREEN=10 / FAIL=7 / GCCFAIL=0 / ICE=0 / CRASH=0** — sorted-identical to the F-1
  feature-commit sweep; per-row movement vs the v74 close is EXACTLY the 2 new dirs
  (`packed_union_struct_member_xmod` OK, `packed_union_struct_wholemember_xmod` GREEN), the
  documented FAIL-5 set (`emission_pal_xmod`/`parsergap_selfblok_xmod`/`parsergap_strict_comma_xmod`
  /`self_embed_optional_cycle`/`strictzig_brace_if_xmod`) and the prior GREEN-9 set row-identical
  (FAIL-7 incl the 2 collection-dir artifacts `mi_matrix`/`slice_matrix`, no main.zig; GREEN-10 incl
  `packed_enum_field_xmod` — L7 enum(u3) = PACK-B3 scope — + the whole-member probe). All packed
  dirs (L0-L6 + the new leaf fixture) classify OK at the compile gate; their RED→GREEN shows at the
  run gate above. Golden 9/9 PASS; matrix 21/21 PASS. Zero asymmetric movement.
- **4-MD5 gates byte-identical UNCHANGED (v75, NO gate re-baseline):** gol `302df36b…` / lisp
  `3591bad9…` / json `76056b97…` / mud `846106ac…` (repo-root CWD, stdout-only, dump rc=0 each).
- **Self-compile fixed point RE-BASELINED (operator-approved 2026-09-08):
  `7e23d33d77926c71999daf602e3d96b6` → `e20bfb7072ea10167476d8f94a9d391d`** — two-hop closure at HEAD
  `9bc2c751`, 41 `.c` + 42 `.h`, rc=0, 0 `error[`, 0 PANIC, hop1==hop2 binary byte-identical (`cmp`
  clean); the documented fixed-point-moves-when-compiler-source-grows class (the F-1 + A2 self-source
  edits moved it; the v74 `7e23d33d…` value superseded). Reference binary md5 `1e7a705b…` (rebuilt
  at HEAD `9bc2c751`). Seed rotated to the new fixed point (release/seed seed v3).

## Packed aggregates GREEN (v74 2026-09-08) — PACK-AGG plan Tasks 2-4

Plan `2026-09-06-packed-struct-aggregates-plan.md` Tasks 2-4 are COMPLETE — `packed union` (its own
`packed_union_type` TypeKind), nested `packed struct` leaf fields, and the array/global/by-value +
cross-module surfaces now parse, resolve with true LSB-first bit layout (members/fields at their
bit offsets, no padding, `size=(bits+7)/8`, stride=size), and lower/emit through real bitfield
paths. The four L3-L6 guard fixtures `packed_l3_nested_xmod` / `packed_union_xmod` /
`packed_array_global_xmod` / `packed_byvalue_module_xmod` are GREEN: compile-clean OK (dump rc=0, 0
`error[`, 0 PANIC, gcc `-m32` clean) AND run-gate byte-exact 3× deterministic (RUNRC=0 — the
v62/v63-era GREEN contracts are now all runnable, nothing forced). Measured on the reference
`/tmp/fx_subfolder/zig1` md5 `b99c4806` (rebuilt at HEAD `f1259e65`, canonical std reinstalled) via
the authoritative fixture_run.sh + classify1.sh recipes (full `-Wall` flag set, fresh dirs, 3 fresh
runs per fixture, stdout md5 identical 3/3). The v62 R9 (L3/L4) + v63 R10 (L5/L6) RED rows below
are the historical record — retained verbatim; the fix commits the v62/v63 rows reference are the
Tasks 2-4 chain. L3 was operator-ruled early-GREEN at Task 3 (2026-09-07, Option A); Task 4 (re-
scoped) delivered the genuine emitter rows L4/L5/L6. L0/L1/L2 PACK-CORE stay GREEN unchanged (v73
section below).

| fixture | v62/v63 RED class | v74 GREEN stdout (byte-exact 3×) |
|---|---|---|
| `packed_l3_nested_xmod` | clean parse FAIL error[2000] at the `struct` token (`packed` not a registered keyword; v62 R9) | `2 5 6 3 3` |
| `packed_union_xmod` | clean parse FAIL error[2000] at the `union` token (v62 R9) | `2 8` |
| `packed_array_global_xmod` | clean parse FAIL error[2000] at the `struct` token (v63 R10) | `1 33 3 4` |
| `packed_byvalue_module_xmod` | clean parse FAIL error[2000] at the `struct` token in the imported `types.zig` (v63 R10) | `1 21 186` |

- **RESOLVED rows (Tasks 2-4 fix commits):** packed-union T2 `94734372` (`packed_union_type`
  TypeKind appended at the true enum end + `kw_packed`/`kw_union` parse arms + union-payload packed
  side table (`pk_un_items` lockstep in `unAppend`): every member at bit 0, width = member int width
  (bool→1), total_bits = MAX member width, `size=ceil(max/8)` min 1, align 1 + packed
  `@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf`/`@bitOffsetOf` folds + B6 member gate ≤31 +
  `&packed.field` clean reject); nested-leaf T3 `8589f2c0` (nested packed-struct field bit_width =
  the inner type's pk total bits; leaf-chain reads/stores lower to ONE accumulated-offset
  `load_bitfield`/`store_bitfield`, no sub-container materialization) + review fix `b2b59921`
  (chain-depth≥2 whole-sub clean `error[3000]` reject on BOTH read and store; B6 widening scoped to
  the struct gate — the packed-union member gate still clean-rejects packed-struct members);
  emission T4 `9dfc17ad` (packed-union single-member carrier typedef + member store/read bit-pack +
  struct-init/agg-literal per-field `store_bitfield` arms → L4/L5/L6) + review fix `f1259e65`
  (packed-union AGGREGATE literal resolves via the `semanticAnalyzerResolveStructInit`
  `packed_union_type` arm — bit-packs at offset 0, NEVER silent; plan AMENDMENT `a0e1534b`). Run-gate
  stdout md5s (×3, RUNRC=0): `2 5 6 3 3`→`1b653d0a…`, `2 8`→`3d331b20…`, `1 33 3 4`→`934faea5…`,
  `1 21 186`→`de16190c…`. Each fixture stays as a permanent regression guard.
- **L6 contract note (186 vs 187):** the run-gate GREEN stdout is `1 21 186` (0xBA = hi<<4|lo =
  176+10) — the spec §5 locked contract. The fixture HEADER's own `1 21 187` title line is the stale
  slip (recorded-history, resolved at Task-4 GREEN time); 187 is NOT propagated as GREEN.
- **Corpus reconciliation (Task-5 battery, reference `b99c4806`):** full 428-dir `-s0` compile-gate
  sweep = **OK=414 / GREEN=9 / FAIL=5 / GCCFAIL=0 / ICE=0 / CRASH=0** — per-row movement vs the v73
  PACK-CORE close (OK=410 / GREEN=10 / FAIL=6 / GCCFAIL=2) is EXACTLY the packed-dir flips:
  `packed_union_xmod` FAIL→OK (T2), `packed_l3_nested_xmod` GREEN→OK (T3), `packed_array_global_xmod`
  + `packed_byvalue_module_xmod` GCCFAIL→OK (T4) — all 7 packed dirs (L0-L6) now classify OK at the
  compile gate; their RED→GREEN shows at the run gate above. `packed_enum_field_xmod` stays GREEN
  (L7 enum(u3) field = PACK-B3 scope). Golden 9/9 PASS; matrix 21/21 PASS.
- **4-MD5 gates byte-identical UNCHANGED (v74, NO gate re-baseline):** gol `302df36b…` / lisp
  `3591bad9…` / json `76056b97…` / mud `846106ac…` (repo-root CWD, stdout-only, dump rc=0 each).
- **Self-compile fixed point RE-BASELINED (operator-approved 2026-09-07, Task-5 STOP ruling):
  `fd3e1c0e1787be22e2b2bc09e9916e4c` → `7e23d33d77926c71999daf602e3d96b6`** — two-hop closure at HEAD
  `f1259e65`, 41 `.c` + 42 `.h`, rc=0, 0 `error[`, 0 PANIC, hop1==hop2 binary byte-identical (`cmp`
  clean); the documented fixed-point-moves-when-compiler-source-grows class (the PACK-CORE `fd3e1c0e…`
  value superseded). Reference binary md5 `b99c4806…` (rebuilt at HEAD `f1259e65`). Seed rotated to
  the new fixed point (release/seed seed v2).

## Packed struct core GREEN (v73 2026-09-07) — PACK-CORE plan Tasks 2-5

Plan `2026-09-06-packed-struct-core-plan.md` Tasks 2-5 are COMPLETE — `packed struct` now parses,
resolves with true LSB-first bit layout (no padding, `size=(bits+7)/8`, stride=size), and lowers /
emits through real bitfield paths. The three L0/L1/L2 guard fixtures `packed_l0_flags_xmod` /
`packed_l1_mix_xmod` / `packed_l2_straddle_xmod` are GREEN: compile-clean OK (dump rc=0, 0
`error[`, 0 PANIC, gcc `-m32` clean, 1 `.c` each) AND run-gate byte-exact 3× deterministic
(RUNRC=0 — the v61-era GREEN contracts are now all runnable, nothing forced). Measured on the
reference `/tmp/fx_subfolder/zig1` md5 `801fdc55` (rebuilt at HEAD `c7af022a`, canonical std
reinstalled) via the authoritative fixture_run.sh + classify1.sh recipes (full `-Wall` flag set,
fresh dirs, 3 fresh runs per fixture, stdout md5 identical 3/3). The v61 R8 RED set below (the same
rows) is the historical record — retained verbatim; the fix commits the v61 rows reference are the
Tasks 2-5 chain.

| fixture | v61 RED class | v73 GREEN stdout (byte-exact 3×) |
|---|---|---|
| `packed_l0_flags_xmod` | clean parse FAIL error[2000] at the `struct` token (`packed` not a registered keyword) | `1 5 1` |
| `packed_l1_mix_xmod` | clean parse FAIL error[2000] at the `struct` token | `1 155 1 5 9` |
| `packed_l2_straddle_xmod` | clean parse FAIL error[2000] at the `struct` token | `2 255 31 31 255` |

- **RESOLVED rows (Tasks 2-5 fix commits):** parser `59a59171` (`kw_packed` token + `packed struct`
  parse + `is_packed` bit + B6 field gate) + review fix `79bd5ac0` (module-level B6 gate `main.zig`
  hook + memoized packed-`&field` check); type/layout `d1d8b5a3` (packed bit-layout side table:
  per-field LSB-first bit offsets/widths, `size=(bits+7)/8`, stride=size, packed
  `@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf`/`@bitOffsetOf` folds); LIR `f819a3cd`
  (`load_bitfield`/`store_bitfield` insts + DCE arms, 16/16 inst-switch sites); emitter `efe9d67c`
  (C89 single-member-struct carrier + bitfield store/load accessors) + width-cap `c1d66325` / spec
  `c7af022a` (Imp-2 B1 ruling). Run-gate stdout md5s (×3, RUNRC=0): `1 5 1`→`2b5aa27d…`,
  `1 155 1 5 9`→`db777fc7…`, `2 255 31 31 255`→`d381a891…`. Each fixture stays as a permanent
  regression guard.
- **PACK-AGG scope note (Imp-1 ACCEPTED):** the two ladder-top stub rows `packed_array_global_xmod`
  (L5 array+global) and `packed_byvalue_module_xmod` (L6 by-value + cross-module) are
  **GCCFAIL-on-carrier** — expected PACK-AGG L5/L6 rows (accepted at the Task-5 review; NOT a
  regression); their contracts `1 33 3 4` / `1 21 186` land with PACK-AGG. `packed_l3_nested_xmod` +
  `packed_enum_field_xmod` classify GREEN (PACK-AGG/B3 scope); `packed_union_xmod` remains FAIL
  (packed union is out of PACK-CORE scope).
- **Width cap (Imp-2 B1, spec `c7af022a`):** packed fields must be ≤ 31 bits wide; `u32`/`i64` and
  wider field types are rejected with a clean `error[3000]` (PACK-AGG deferred).
- **Corpus reconciliation (Task-6 battery, reference `801fdc55`):** full 428-dir `-s0` compile-gate
  sweep = **OK=410 / GREEN=10 / FAIL=6 / GCCFAIL=2 / ICE=0 / CRASH=0** — per-row ZERO movement vs
  the Task-5 PACK-CORE baseline (sorted diff identical). The 3 PACK-CORE dirs classify OK at the
  compile gate (their RED→GREEN shows at the run gate above); the 2 PACK-AGG stubs are the GCCFAIL=2;
  `packed_l3_nested_xmod` / `packed_enum_field_xmod` GREEN and `packed_union_xmod` FAIL unchanged.
  Golden 9/9 PASS; matrix 21/21 PASS.
- **4-MD5 gates byte-identical UNCHANGED (v73, NO gate re-baseline):** gol `302df36b…` / lisp
  `3591bad9…` / json `76056b97…` / mud `846106ac…` (repo-root CWD, stdout-only, dump rc=0 each).
- **Self-compile fixed point RE-BASELINED (operator-approved 2026-09-07): `24da89b9…` →
  `fd3e1c0e1787be22e2b2bc09e9916e4c`** — two-hop closure at HEAD `c7af022a`, 41 `.c` + 42 `.h`,
  rc=0, 0 `error[`, 0 PANIC, hop1==hop2 binary byte-identical (`cmp` clean); the documented
  fixed-point-moves-when-compiler-source-grows class (the INTWIDTH/seed-era `24da89b9…` value
  superseded). Reference binary md5 `801fdc55…` (rebuilt at HEAD `c7af022a`). Seed rotated to the
  new fixed point (release/seed seed v1).

## Arbitrary-width ints GREEN (v72 2026-09-07) — INTWIDTH plan Task 5

Plan `2026-09-06-arbitrary-width-ints-plan.md` Tasks 3+4 are COMPLETE — arbitrary-width integer
types `uN`/`iN` now register as real types and emit. The five `intwidth_*` guard fixtures PLUS R7
`int_arbitrary_width_xmod` are GREEN: compile-clean OK (dump rc=0, 0 `error[`, 0 PANIC, gcc `-m32`
clean, 1 `.c` each) AND run-gate byte-exact 3× deterministic (RUNRC=0 — the v71 GREEN-time contracts
are now all runnable, nothing forced). Measured on the reference `/tmp/fx_subfolder/zig1` md5
`3707d33b` (rebuilt at HEAD `6b440d2c`, canonical std reinstalled) via the authoritative classify1.sh
recipe; fixture run-gates fresh under `/tmp/iw_t5/fixtures` (emit `-s0` → gcc `-m32` → link
`zig_runtime.c + zig_pal.c` → run, 3 fresh runs per fixture, stdout md5 identical 3/3). The v71 RED
section below is the historical record of the same rows (kept verbatim); the fix commits the v71 rows
reference are Task-2 fixtures `ca452470`/`3581c172`/`54ef34f5` (doc rulings) + Task-3 type layer
`8967a0b1`/`91912420` + Task-4 emission `cf7169e6`/`6b440d2c`.

| fixture | v71 RED class | v72 GREEN stdout (byte-exact 3×) |
|---|---|---|
| `intwidth_wrap_xmod` | clean error[3000] reject (compile-gate FALSE green) | `0 0` |
| `intwidth_sign_extend_xmod` | clean error[3000] reject (compile-gate FALSE green) | `true -1` |
| `intwidth_cast_xmod` | clean error[3000] reject (compile-gate FALSE green) | ~~`7 0 255`~~ **SUPERSEDED by Task 11S — re-pinned GREEN (clean `error[3000]` reject)** |
| `intwidth_introspect_xmod` | ICE (error[3043] comptime unresolved @sizeOf/@alignOf) | `3 1 2 4 8 1 7` |
| `intwidth_full_xmod` | clean error[3000] reject (compile-gate FALSE green) | `0 -1` |
| `int_arbitrary_width_xmod` (R7, v60 row) | compile-gate FALSE-green family | `7 -3 3000 4` |

- **RESOLVED rows (fix commits):** type layer `8967a0b1` (`width_bits`/`is_signed` on `Type`,
  `typeRegistryIntWidthBits`/`IntIsSigned` helpers, uN/iN primitive registration u1..64/i1..63 with
  clean `error[3000]` for out-of-range widths, `TypeKind` arb_uint/arb_int appended) + review fixes
  `91912420` (comptime fold neutrality for non-int targets); emission `cf7169e6` (carrier map to the
  smallest power-of-2 C carrier, width-keyed mask/sign-extend at the binary/unary/int_cast/int_const
  producers, width-level checked `@intCast`, introspection folds) + sat-op width fix `6b440d2c` (sat
  ops on arbitrary-width clamp at the semantic width bound). The v71 ICE class (introspection) is
  gone — `@sizeOf/@alignOf/@bitSizeOf` on uN fold at comptime; the unknown-type error[3000]
  rejection family (incl. the R7 void-fallback conflation, `cannot declare variable of type void`
  cascade, FALSE-green compile-gate label) is gone — uN/iN annotations resolve to real types. Each
  fixture stays as a permanent regression guard.
- **Corpus v71→v72 reconciliation (Task-5 battery, reference `3707d33b`):** full 433-dir `-s0`
  sweep = **OK=412 / FAIL=13 / GREEN=8 / GCCFAIL=0 / ICE=0 / CRASH=0** (412+13+8=433). vs the
  pre-INTWIDTH netbind S4 baseline (428 dirs, OK=406/FAIL=13/GREEN=9, compiler `c8f1b3d0`): sorted
  per-row `diff` = **EXACTLY ONE row changed — `int_arbitrary_width_xmod` GREEN→OK**; zero delta on
  the other 427. The 5 new intwidth dirs classify OK. FAIL 13 / GREEN common sets row-identical.
- **4-MD5 gates byte-identical UNCHANGED (v72, NO gate re-baseline):** gol `302df36b…` / lisp
  `3591bad9…` / json `76056b97…` / mud `846106ac…` (repo-root CWD, stdout-only, dump rc=0 each).
  Golden 9/9 PASS; matrix 21/21 PASS.
- **Self-compile fixed point RE-BASELINED (operator-approved 2026-09-07): `10f0ca2b…` →
  `24da89b9d6398ff24f4baecfe2e23f77`** — two-hop closure at HEAD `6b440d2c`, 41 `.c`, rc=0, 0
  `error[`, 0 PANIC, hop1==hop2 binary byte-identical (`cmp` clean); the documented
  fixed-point-moves-when-compiler-source-changes class (Task 3's intermediate `4cc150c1…` and
  Task-4's binary md5 `3707d33b…` superseded). Reference binary md5 `3707d33b…` (rebuilt at HEAD
  `6b440d2c`).

## Arbitrary-width ints RED set (v71 2026-09-06) — INTWIDTH plan Task 2

New-corpus RED fixtures (plan `2026-09-06-arbitrary-width-ints-plan.md`, Task 2): the five
`intwidth_*` guard fixtures for arbitrary-width integer types `uN`/`iN` (wrap arithmetic at `u3`/
`u12`, sign-extend through `i7`, truncate/mask casts, introspection `@bitSizeOf/@sizeOf/@alignOf` on
u3/u12/u20/u33/i7, and the 64-bit-carrier boundary `u63`/`i63`). Only the fixed widths register as
primitive type names (`registerPrimitiveName`, `sf/src/type_registry.zig:630-635`), so each `uN`/`iN`
var-decl annotation resolves as an unknown type name — the same R7 void-fallback family
(`error[3000]: unknown type in variable declaration` at the bare-ident annotation, F-CLEANDIAG gate
`932fea8d`, plus the downstream `cannot declare variable of type void` cascade on the untyped-var
results where the analyzer proceeds). Measured on the reference `/tmp/fx_subfolder/zig1` md5
`c8f1b3d0` (rebuilt at HEAD `d4813c70`) via the authoritative classify1.sh recipe
(`.superpowers/sdd/task-LANGWINS-report.md` Step 4, fresh output dir per run). Contracts are
GREEN-time only — NOT runnable today, never forced. Neither CRASH observed; `intwidth_introspect_xmod`
is the exception class (ICE error[3043], R5-precedent — the `@sizeOf/@alignOf` type-arg resolves the
uN annotation to a non-type and comptime-eval halts before the clean 3000s can fire). Corpus +5
(mi_matrix 428→433). No implementation yet at fixture-commit time (Task 3+).

| dir | feature | RED class | expected GREEN stdout |
|---|---|---|---|
| `intwidth_wrap_xmod` | `uN` arithmetic wrap (`u3` 7+1→0; `u12` 4095+1→0) | clean error[3000] rejection (compile-gate label GREEN — FALSE green; `u3`/`u12` annotations unknown → `unknown type in variable declaration`; 0 `.c`; deterministic 3/3) | `0 0` |
| `intwidth_sign_extend_xmod` | `iN` sign-extend (`i7` -1 < 0; `@intCast(i16, i7 -1)` sign-extends) | clean error[3000] rejection (compile-gate label GREEN — FALSE green; `i7` annotation unknown; 0 `.c`; deterministic 3/3) | `true -1` |
| `intwidth_cast_xmod` | `@intCast` narrow/truncate + widen (`u3` 255→7; `u8` 256→0; widen keeps value) | clean error[3000] rejection (compile-gate label GREEN — FALSE green; `u3` annotation unknown; 0 `.c`; deterministic 3/3) | ~~`7 0 255`~~ **SUPERSEDED by Task 11S: out-of-range `@intCast` is now a clean `error[3000]` reject (range-checked, Zig-matching); truncate/mask is covered by `intwidth_wrap_xmod`** |
| `intwidth_introspect_xmod` | introspection on `uN`/`iN` — `@bitSizeOf/@sizeOf/@alignOf` (u3/u12/u20/u33/i7) | ICE (dump rc=3, 0 `.c`; `error[3043]: internal: comptime value unresolved for @sizeOf/@alignOf`; deterministic 3/3) | `3 1 2 4 8 1 7` |
| `intwidth_full_xmod` | 64-bit-carrier boundary — `u63` 2^63-1+1 → 0 wrap; `i63` -1 sign-extends through `@intCast(i64)` | clean error[3000] rejection (compile-gate label GREEN — FALSE green; `u63`/`i63` annotations unknown; 0 `.c`; deterministic 3/3) | `0 -1` |

- **Current RED status — intwidth_wrap_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes. dump.err
  verbatim (repo-relative): `repro/mi_matrix/intwidth_wrap_xmod/main.zig:4:11: error[3000]: unknown
  type in variable declaration` (the `pub fn main() void` annotation line echoed as caret context —
  the R7 display quirk), then `…:5:11` (the `u3` annot at `var a`), then `…:6:4: error[3000]: cannot
  declare variable of type void` (the `var b` result of the untyped-var cascade), repeated for the
  u12 block (`…:9:11`/`…:10:11` unknown-type, `…:11:4` cannot-declare-void). stderr md5
  `13454eb500f2f52ca389ed4c596057e1` byte-identical 3/3.
- **Current RED status — intwidth_sign_extend_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes.
  dump.err the SINGLE `…:4:11: error[3000]: unknown type in variable declaration` (the `i7` annot at
  `var n`; analyzer stops after the first). stderr md5 `bd389d87cc563124951f022a72cda1e2`
  byte-identical 3/3.
- **Current RED status — intwidth_cast_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes. dump.err
  the SINGLE `…:4:11: error[3000]: unknown type in variable declaration` (the `u3` annot at `var t`;
  analyzer stops after the first). stderr md5 `d6138f8850eb7b691a76cea7d8f787e8` byte-identical 3/3.
- **Current RED status — intwidth_introspect_xmod:** dump rc=3, 0 `.c` emitted, stdout 0 bytes.
  dump.err verbatim: `error[3043]: internal: comptime value unresolved for @sizeOf/@alignOf (node 9)`
  — the first `@sizeOf(u3)` type-arg resolves the unknown-width annotation to a non-type and the
  comptime fold halts before any clean 3000 diagnostic fires. No source-echo, no line:col (node-level
  halt). stderr md5 `8d17a8bdf8a7162af6c73ef0d3becdfa` byte-identical 3/3. ICE precedent: R5
  `crossmod_pubvar_xmod` error[3043].
- **Current RED status — intwidth_full_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes. dump.err
  verbatim (repo-relative): `…:4:11: error[3000]: unknown type in variable declaration`, then
  `…:5:11` (the `u63` annot at `var a`), then `…:6:4: error[3000]: cannot declare variable of type
  void` (the `var b` result of the untyped-var cascade), then `…:9:11` unknown-type. stderr md5
  `fd9557a11312ef4142b2323e25a178df` byte-identical 3/3.
- **Rule (GREEN contracts; fixtures turn GREEN in Task 4):** once arbitrary-width int types uN/iN
  register as real types (Task 3 type layer + Task 4 emission carrier math, plan §4), each fixture
  MUST dump rc=0, gcc `-m32` clean, and run rc=0 printing its byte-exact contract: `intwidth_wrap_xmod`
  `0 0` (u3 7+1 wraps 0; u12 4095+1 wraps 0), `intwidth_sign_extend_xmod` `true -1` (i7 -1 < 0 true;
  `@intCast(i16, i7 -1)` = -1 sign-extended → prints -1), `intwidth_cast_xmod` `7 0 255` (@intCast(u3,
  255) masks to 7; @intCast(u8, 256) masks to 0; u3→u8 widen keeps 255), `intwidth_introspect_xmod`
  `3 1 2 4 8 1 7` (@bitSizeOf(u3)=3, @sizeOf(u3)=1 carrier byte, @sizeOf(u12)=2, @sizeOf(u20)=4,
  @sizeOf(u33)=8, @alignOf(u3)=1, @bitSizeOf(i7)=7), `intwidth_full_xmod` `0 -1` (u63
  9223372036854775807 (2^63−1) + 1 → 0 on the 64-bit carrier via mask (1<<63)-1; i63 -1 sign-extends
  through @intCast(i64) → -1). At GREEN time the analyzer must also stop conflating unregistered-width
  names with `void`/unknown (the R7 note), and `@sizeOf/@alignOf` on uN must fold (no error[3043]).
  R7 `int_arbitrary_width_xmod` (v60 row below) is the model row; its current class is the same
  compile-gate FALSE-green family.

## Netbind reconciliation (v70 2026-09-05) — std_net extern OS bindings + target model + socket-builtin removal

Plan `2026-09-05-std-net-extern-target-plan.md` (design `2026-09-05-std-net-extern-target-design.md`
`4e322a71`; commits `bd2666b1` S1 / `93e7d247` S2 / `12a16726` S3-C1 / `838009b0` S3) is COMPLETE:
S1 target model + S2 std_net extern rewrite + S3 builtin removal + S4 combined battery + the
operator-approved re-baselines (2026-09-04). Measured on the reference `/tmp/fx_subfolder/zig1` md5
`c8f1b3d0` (rebuilt at HEAD `838009b0`, canonical std reinstalled). Corpus 428 dirs `-s0` =
**OK=406 / FAIL=13 / GREEN=9 / GCCFAIL=0 / ICE=0 / CRASH=0** — per-row zero delta vs the S3-F sweep;
the ONLY row move is `net_builtin_test` OK→GREEN (the clean-error reclass below). Golden 9/9 PASS;
matrix 21/21 PASS; `scripts/closeout/verify_upgraded.sh` A1–B7 PASS. Three fixture rows reconcile
(the two NEW dirs are valid programs kept as permanent regression guards; `net_builtin_test` is the
C2 negative probe, reclassified in place):

- **GREEN (2026-09-05, S1 `bd2666b1`, NEW regression guard):** `target_is_windows_xmod` — the
  target-model fixture. `@isWindows()` now folds from the per-invocation target (`-osl` default /
  `-osw`; `--target linux|windows` alias), so the `if (@isWindows())` branch is comptime-pruned per
  target: `-osl`/no-flag emission is `x = 222`, `-osw` emission is `x = 111`; run-gate verified 3×
  deterministic both targets (`-osl` gcc -m32 → `222`, `-osw` mingw + wine → `111`), no-flag ==
  `-osl` dump byte-identical. RED pre-S1 (fold hard-false → `222` under BOTH flags; `-osw` was
  silently ignored). It no longer belongs in the expected-fail set; kept as a permanent regression
  guard (a target-fold regression flips it straight back to RED).
- **GREEN (2026-09-05, S2 `93e7d247`, NEW regression guard):** `net_bind_startup_xmod` — the
  std_net init + socket-call shape. `init()` now executes WSAStartup(1,1) on win (was a no-op
  returning 0 → the first socket call failed WSANOTINITIALISED `10093` → `createTcpServer(0)` −1 →
  `@exit(2)`); linux no-op unchanged. Run-gate verified 3× deterministic: linux rc=0 stdout `7`,
  win rc=0 stdout `7` (wine). RED pre-S2 on the WIN target only (rc=2, empty stdout); linux RED was
  never observable (no startup needed). It no longer belongs in the expected-fail set; kept as a
  permanent regression guard (an init regression re-fires the win `10093` path).
- **RECLASSIFIED (2026-09-05, S3 `838009b0`):** `net_builtin_test` **OK → GREEN** (clean-error
  class; the C2 negative probe, AMENDMENT `f1b62a87`). Its main.zig exercises the 11 `@socket*`
  builtins directly; S3 deleted them (std_net is now the sole networking surface — extern wsock32/
  libc bindings), so the fixture is invalid by design post-removal and a direct `@socket*` call now
  fails CLEAN via the F-CLEANDIAG diagnostic: dump rc=2, **0 `.c`**, stderr `error[3000]: unsupported
  builtin function` (19 occurrences; the AMENDMENT-2 `c294fce0`-documented `cannot declare variable
  of type void` CASCADE on the untyped-var results is expected — not a defect). Corpus class moved
  OK→GREEN at S3-F and HOLDS (S4 re-sweep). The historical OK-era records beneath (the fixture
  NOTES.md and the F3/F4/F7-era "all classify OK" rows in the Totals sections) are retained
  verbatim as evidence; the fixture's `main.zig`/NOTES.md are untouched.

**Plan reconciliation note (S1-S3 change record; all operator-ruled or -approved):** (1) target
flags `-osl`/`-osw` + `--target linux|windows` alias, default linux, with target-aware
`@isWindows()` folding (S1 `bd2666b1`); no-flag/`-osl` output byte-identical to pre-change. (2)
std_net full extern rewrite (S2 `93e7d247`): target-selected wsock32/libc `extern "c"` bindings
under `if (@isWindows())` comptime selection, single OS-prototype source = the new
`sf/src/include/net_prelude.h` via `@cInclude("<net_prelude.h>")`, win `init()`/`cleanup()` =
WSAStartup(1,1)/WSACleanup, manual byte-swap helpers `htonsManual`/`htonlManual` (public) alongside
extern `htons`/`htonl`, `-1` INVALID_SOCKET/SOCKET_ERROR mapping preserved. (3) additive public API
(S3-C1 `12a16726`, operator m0926): `createTcpClient(port: u16) i32` client factory; the demo
client `examples/z98/rogue_mud_upgraded/demo/net_demo_client.zig` migrated to the std_net flow
(`init()` → `createTcpClient(4000)` → `send` → `recv` → `close` → `cleanup()`). (4) the 11
`@socket*` builtins removed (S3 `838009b0`) — a direct call now yields the clean `error[3000]:
unsupported builtin function`, and `net_builtin_test` reclassifies OK→GREEN (above). (5)
operator-approved re-baselines (2026-09-04): mud 4-MD5 `53405b3b` → `846106ac` (intermediate
`962a692c` superseded; gol/lisp/json UNCHANGED `302df36b`/`3591bad9`/`76056b97`) and self-compile
fixed point `85733145` → `10f0ca2b` (41 `.c`/0 err/0 PANIC, hop1==hop2 closure). Wine net
verification: mud_server BINDS + serves under `-osw` (banner, zero `10093`), demo client connect
rc 0, select live — 3× deterministic. `cross_net.sh` (legacy win32 pre-test artifact encoding the
pre-fix 10093-gap expectations) intentionally left untouched; `verify_upgraded.sh` is the live gate.

## Closeout note (v69 2026-09-04) — upgraded-examples verification gate

The upgraded-example feature showcases (`examples/z98/lisp_interpreter_upgraded` and
`examples/z98/rogue_mud_upgraded`, each with its `demo/` dir) remain **gate-exempt**
from the mi_matrix corpus — they are example programs, not repro fixtures, and no
expected-fail row applies to them. Their canonical byte-identity + demo goldens are
now committed **gate artifacts** verified by the self-contained closeout gate at
`scripts/closeout/verify_upgraded.sh` (with its repo-authoritative 5-line
`scripts/closeout/flush.c` `_IONBF` LD_PRELOAD shim): A1-A5 = lisp build / canonical
feed (`96654b39…`) / demo feed masked-compare (AMENDMENT 4 `(address)` line) / export
symbol gate (`alloc_value`) / zig0 note; B1-B7 = rogue build / q feed (`3fb6709e…`) /
move feed (`b3c5b0e1…`) / demo feed (`7361d248…`) / export symbol gates
(`saveDungeon`/`loadDungeon`/cross-module `render_calls`) / net variant
(`aa40a52e…`) / zig0 note. Rogue dumps run from the rogue program dir CWD (module
resolution relative; dumping `demo/net_main.zig` from the repo root fails
`error[3048]`). zig0 scope per Global Constraints AMENDMENT 2 = `examples/zig0` ONLY
— no `sf/build/zig0` build is ever attempted against an `examples/z98` entrypoint;
the zig0-incompatibility closeout evidence is documented-only (gate phases A5/B7 echo
the scope line + the C1 tag-`==` construct sites; no build).

## Langwins clean-diag fixtures (v67) — F-CLEANDIAG

- **RESOLVED (2026-09-04, F-CLEANDIAG GATE, `932fea8d`):** the `cleandiag_unknown_builtin_xmod`
  fixture is now **GREEN** — the unsupported-builtin diagnostic gate landed (fixed by commit `932fea8d`
  — the `semanticAnalyzerIsBuiltinSupported` membership helper + the unsupported-builtin arm emitting
  `error[3000]: unsupported builtin function` — preceded by the `test:` fixture commit `1e373449`). Its
  dump contract below now **HOLDS**: dump rc=2, **0 `.c`**, stderr PRIMARY `error[3000]: unsupported
  builtin function` (9:12); a downstream `error[3000]: cannot declare variable of type void` CASCADE on
  the UNTYPED `var r = @totallyBogus(i32, 5)` (9:4) is EXPECTED normal compiler behavior per AMENDMENT 2
  (`c294fce0`) — the binding requirement is the PRIMARY `unsupported builtin function` present with
  rc=2 and 0 `.c`; the cascade is not a defect. It **no longer belongs in the expected-fail set** (kept
  as a permanent regression guard). The historical RED root-cause record beneath this marker is
  retained verbatim as evidence.
- **RESOLVED (2026-09-04, F-CLEANDIAG GATE, `932fea8d`):** the `cleandiag_unknown_type_xmod` fixture
  is now **GREEN** — the unknown-type diagnostic gate landed (fixed by commit `932fea8d` — at the
  var-decl annotation site, when a bare-ident annotation resolves to `TYPE_VOID` a second
  `resolveTypeExprFull` distinguishes a real `void`/alias from a truly unknown name, emitting
  `error[3000]: unknown type in variable declaration` only for the unknown case — preceded by the
  `test:` fixture commit `1e373449`). Its dump contract below now **HOLDS**: dump rc=2, **0 `.c`**,
  stderr the single `error[3000]: unknown type in variable declaration` (10:11) with NO `cannot declare
  variable of type void` (cascade suppressed via `decl_type = TYPE_UNDEFINED` + the existing
  `decl_type = it` init-site recovery). It **no longer belongs in the expected-fail set** (kept as a
  permanent regression guard). The historical RED root-cause record beneath this marker is retained
  verbatim as evidence.

New-corpus CLEAN-DIAG fixtures (plan `2026-09-03-f-cleandiag-clean-diagnostics-plan.md`, Task 1):
two silent/misleading zig1 failure modes get clean `error[3000]` diagnostics — (a) an UNKNOWN /
unsupported builtin name (`@totallyBogus(i32, 5)`), today a silent dump rc=0 emitting valid C whose
result is dropped → prints `0`; (b) an unknown TYPE name in a var annotation
(`var a: bogusfoo = 1;`, the R7 `uN`/void-fallback class), today the misleading
`cannot declare variable of type void`. Measured on the reference `/tmp/fx_subfolder/zig1` md5
`821d77ff` via the authoritative classify1.sh recipe (`.superpowers/sdd/task-LANGWINS-report.md`
Step 4, fresh output dir per run). Corpus +2. Implementation: `sf/src/semantic_analyzer.zig` ONLY
(membership helper `semanticAnalyzerIsBuiltinSupported` + unsupported-builtin arm + unknown-type
check at the var-decl annotation site). No implementation yet at fixture-commit time.

| dir | feature | RED class | expected GREEN stdout |
|---|---|---|---|
| `cleandiag_unknown_builtin_xmod` | unknown `@builtin` name (`@totallyBogus`) parses as `builtin_call`, no sema/lower handler → silent drop | RED today dump rc=0, 0 stderr, compiles + prints `0` (silent mis-emission); after fix clean FAIL rc=2, 0 `.c`, `error[3000]: unsupported builtin function` | (clean-FAIL — no stdout contract) |
| `cleandiag_unknown_type_xmod` | unknown TYPE annotation (`var a: bogusfoo`) → R7 void-fallback | RED today dump rc=2, `error[3000]: cannot declare variable of type void`; after fix `error[3000]: unknown type in variable declaration`, NO `cannot declare variable of type void` | (clean-FAIL — no stdout contract) |

- **Current RED status — cleandiag_unknown_builtin_xmod:** dump rc=0, stderr 0 bytes (empty),
  `fixture_run.sh` run rc=0 printing `0` (the `@totallyBogus` result is silently dropped).
- **Current RED status — cleandiag_unknown_type_xmod:** dump rc=2, 0 `.c`. dump.err verbatim:
  `repro/mi_matrix/cleandiag_unknown_type_xmod/main.zig:10:4: error[3000]: cannot declare variable
  of type void` then `…:10:4: warning[3000]: type mismatch in variable declaration -- initialization
  type may not be compatible with declared type` (text as of Task 18; the Task-6-era observation read `—`) + the source/`note: source: comptime_int` /
  `note: target: void` echo.
- **Rule (GREEN contracts):** once implemented, both dump rc=2 with 0 `.c`; the builtin fixture's
  stderr contains `error[3000]: unsupported builtin function`; the type fixture's stderr contains
  `error[3000]: unknown type in variable declaration` and does NOT contain
  `cannot declare variable of type void` (cascade suppressed). Valid programs byte-identical
  (4-MD5 gates gol `302df36b…`/lisp `3591bad9…`/json `76056b97…`/mud `53405b3b…`).

## Langwins feature-gap fixtures (v63 2026-09-03) — R10 packed ladder top: L5 array+global / L6 by-value+cross-module / L7 enum(u3) field REPRO rows

New-corpus REPRO fixtures (plan `2026-09-03-language-wins-r-i-plan.md`, Task R10): the `packed struct`
ladder top — L5 an ARRAY of packed structs in a storage GLOBAL (whole-element global stores), L6 a
packed struct passed BY VALUE across MODULES (two modules must agree on the packed layout), L7 a
`packed struct` with an `enum(u3)` field. As R8 established, `packed` is NOT a registered keyword
(`sf/src/token.zig` has no `kw_packed`) — the lexer treats `packed` as a PLAIN IDENTIFIER, so the parse
error fires at the FOLLOWING `struct` keyword. Measured on the reference `/tmp/fx_subfolder/zig1` md5
`1a5056b2` via the authoritative classify1.sh recipe (`.superpowers/sdd/task-LANGWINS-report.md`
Step 4, fresh output dir per run). Each is **RED class FAIL** (clean frontend parse rejection,
deterministic 3/3): dump rc=2, **0 `.c` emitted** (no `error[3000]` → clean-FAIL per the Step-4
rules), dump stdout 0 bytes, stderr byte-identical 3/3 per fixture. Neither ICE nor CRASH observed.
Corpus +3 (mi_matrix 348→351). No implementation yet.

| dir | feature | RED class | expected GREEN stdout |
|---|---|---|---|
| `packed_array_global_xmod` | `packed struct` L5: array of packed in a storage GLOBAL `var grid: [4]Cell`; whole-element global stores | clean parse FAIL error[2000] at `struct` (col 20) after `packed` lexed as identifier; 0 `.c`; deterministic 3/3 | `1 33 3 4\n` |
| `packed_byvalue_module_xmod` | `packed struct` L6: by-value + cross-module layout identity (`types.zig` `Pair{lo:u4,hi:u4}` imported + passed by value) | clean parse FAIL error[2000] at `struct` (col 24, in `types.zig:1` — the imported module is parsed first); 0 `.c`; deterministic 3/3 | `1 21 186\n` |
| `packed_enum_field_xmod` | `packed struct` L7: `enum(u3)` field inside a packed struct (exercises B0+B3); the enum(u3) decl PARSES clean — the parse error fires first at the packed decl | clean parse FAIL error[2000] at `struct` (col 21, `main.zig:8`); 0 `.c`; deterministic 3/3 | `1 3 1 1\n` |

- **Current RED status — packed_array_global_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes.
  dump.err verbatim: `repro/mi_matrix/packed_array_global_xmod/main.zig:7:20: error[2000]: expected
  ';' but found token` then `…:7:20: error[2000]: unexpected token`. Line 7 = `const Cell = packed
  struct { x: u4, y: u4 };`; col 20 (0-based) = the `struct` token (`packed` at col 13). No caret
  context echo. stderr md5 `6d8674a0…` byte-identical 3/3.
- **Current RED status — packed_byvalue_module_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes.
  dump.err verbatim: `repro/mi_matrix/packed_byvalue_module_xmod/types.zig:1:24: error[2000]:
  expected ';' but found token` then `…:1:24: error[2000]: unexpected token`, each with the caret
  echo. Line 1 (types.zig) = `pub const Pair = packed struct { lo: u4, hi: u4 };`; col 24 (0-based) =
  the `struct` token (`packed` at col 17). The FAIL fires in the IMPORTED module `types.zig` (parsed
  first), NOT in main.zig. stderr md5 `a4232b9f…` byte-identical 3/3.
- **Current RED status — packed_enum_field_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes.
  dump.err verbatim: `repro/mi_matrix/packed_enum_field_xmod/main.zig:8:21: error[2000]: expected
  ';' but found token` then `…:8:21: error[2000]: unexpected token`, with caret echo. Line 8 =
  `const Pixel = packed struct { on: bool, color: Color };`; col 21 (0-based) = the `struct` token
  (`packed` at col 14). The caret echo displays the PRECEDING line 7 text
  (`const Color = enum(u3) { red, green, blue };`) — the same R7 caret display quirk (line:col
  authoritative). Line 7's `enum(u3)` decl PARSES clean (u3 semantic void-degrade never reached
  because the parse error at the packed decl fires first and stops). stderr md5 `12c9feba…`
  byte-identical 3/3.
- **Rule (L5-L7 contracts; L6 carries the 186-vs-187 resolution note):** once `packed struct` parses
  and lowers as true LSB-first bitfields with NO padding and `size=(bits+7)/8`, stride=size:
  - `packed_array_global_xmod` MUST print `1 33 3 4\n` (rc=0) — size 1 (stride 1, no pad);
    grid[1] byte = x=1,y=2 => 0x21 = 33; grid[3].x=3, .y=4 (whole-element global stores must land).
  - `packed_byvalue_module_xmod` MUST print `1 21 186\n` (rc=0) — size 1; sum(10,11)=21;
    lo=10(1010 bits0-3), hi=11(1011 bits4-7) => hi<<4|lo = 0xBA = 186. **186-vs-187 note:** the
    fixture header's literal first GREEN-contract line says `"1 21 187\n"` (transcribed verbatim) but
    its own inline correction + the plan contract-note establish **186 (0xBA = hi<<4|lo =
    10 + 176 = 186)**; to be confirmed at the I8/G1 gate — do NOT silently change the committed
    main.zig.
  - `packed_enum_field_xmod` MUST print `1 3 1 1\n` (rc=0) — size 1; on=true(bit0),
    color=green(enum 1, bits1-3) => byte 0b00000011 = 3; `@enumToInt(Color.blue)`==2;
    `@sizeOf(Color)`=1 (an enum(u3) whose u3 must register as a real type, per R7).

## Langwins feature-gap fixtures (v62 2026-09-03) — R9 packed struct L3 nested / packed union REPRO rows

New-corpus REPRO fixtures (plan `2026-09-03-language-wins-r-i-plan.md`, Task R9): the `packed struct`
ladder part 2 — L3 a NESTED `packed struct` field (bit-contiguous) and L4 a `packed union` (members
overlap at bit 0). As R8 established, `packed` is NOT a registered keyword (`sf/src/token.zig` has no
`kw_packed`) — the lexer treats `packed` as a PLAIN IDENTIFIER, so the parse error fires at the
FOLLOWING `struct`/`union` keyword. Measured on the reference `/tmp/fx_subfolder/zig1` md5 `1a5056b2`
via the authoritative classify1.sh recipe (`.superpowers/sdd/task-LANGWINS-report.md` Step 4, fresh
output dir per run). Each is **RED class FAIL** (clean frontend parse rejection, deterministic 3/3):
dump rc=2, **0 `.c` emitted** (no `error[3000]` → clean-FAIL per the Step-4 rules), dump stdout 0
bytes, stderr byte-identical 3/3 per fixture. Neither ICE nor CRASH observed.

**L3 FEASIBILITY probe:** the nested fixture is a deliberate feasibility probe — if zig1 must restrict
`packed struct` fields to int/bool/enum only (i.e. a nested packed-struct field is disallowed), this
GREEN contract (`2 5 6 3 3\n`) re-baselines with the operator at the I8 gate rather than staying as
written. Contracts are contract-ONLY, NOT runnable today, never forced GREEN. Corpus +2 (mi_matrix
346→348). No implementation yet.

| dir | feature | RED class | expected GREEN stdout |
|---|---|---|---|
| `packed_l3_nested_xmod` | `packed struct` L3: NESTED packed-struct field `Inner{a:u3,b:u3}` inside `Outer{head:u2,inner,tail:u2}` (bit-contiguous) | clean parse FAIL error[2000] at `struct` (col 21) after `packed` lexed as identifier — BOTH decls (lines 8 & 9) fire; 0 `.c`; deterministic 3/3 | `2 5 6 3 3\n` |
| `packed_union_xmod` | `packed union` L4: `U{a:u4,b:u12}` members overlap at bit 0 | clean parse FAIL error[2000] at `union` (col 17) after `packed` lexed as identifier; 0 `.c`; deterministic 3/3 | `2 8\n` |

- **Current RED status — packed_l3_nested_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes. dump.err
  verbatim (repo-relative entry): `repro/mi_matrix/packed_l3_nested_xmod/main.zig:8:21: error[2000]:
  expected ';' but found token`, `…:8:21: error[2000]: unexpected token`, then the SAME pair at
  `…:9:21` (the parser recovers after the `Inner` decl and reports the `Outer` decl too). Line 8 =
  `const Inner = packed struct { a: u3, b: u3 };`, line 9 = `const Outer = packed struct { head: u2,
  inner: Inner, tail: u2 };`; col 21 (0-based) = the `struct` token (`packed` at col 14). The caret
  context echo appears only under the SECOND (9:21) error group and echoes the PREVIOUS (line 8)
  source text — the same caret display quirk R7 recorded (line:col authoritative). stderr md5
  `01bfa4ab…` byte-identical 3/3.
- **Current RED status — packed_union_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes. dump.err
  verbatim: `repro/mi_matrix/packed_union_xmod/main.zig:6:17: error[2000]: expected ';' but found
  token` then `…:6:17: error[2000]: unexpected token`. Line 6 = `const U = packed union {`; col 17
  (0-based) = the `union` token (`packed` at col 10). stderr md5 `de467b85…` byte-identical 3/3.
- **Rule (L3-L4 contracts, both FEASIBILITY-flagged):** once `packed struct`/`packed union` parse and
  lower as true LSB-first bitfields:
  - `packed_l3_nested_xmod` MUST print `2 5 6 3 3\n` (rc=0) — 2+6+2 = 10 bits => size 2, nested
    packed field bit-contiguous; field reads back. **If the I8 gate restricts packed fields to
    int/bool/enum only (no nesting), re-baseline this contract with the operator.**
  - `packed_union_xmod` MUST print `2 8\n` (rc=0) — members overlap at bit 0; 12 bits => size 2;
    write b=3000, read a = low 4 bits of 3000 = 8.

## Langwins feature-gap fixtures (v61 2026-09-03) — R8 packed struct L0/L1/L2 REPRO rows

New-corpus REPRO fixtures (plan `2026-09-03-language-wins-r-i-plan.md`, Task R8): the `packed struct`
ladder — L0 bool flags / L1 mixed int widths in 1 byte / L2 a straddling field (the C89 padding /
bit-accounting regression net). `packed` is NOT a registered keyword (`sf/src/token.zig` has no
`kw_packed`; grep of `sf/src/` for a parser/lexer `packed` token matches only the unrelated
`flags_packed` fn-flag, packed-range encodings, and the token.zig:129-131 FIXME comment) — so the
lexer treats `packed` as a PLAIN IDENTIFIER and the parse error fires at the FOLLOWING `struct`
keyword, not at `packed` (differs from R4 `export`, a real keyword, which failed at col 0 of
`export`). Measured on the reference `/tmp/fx_subfolder/zig1` md5 `1a5056b2` via the authoritative
classify1.sh recipe (`.superpowers/sdd/task-LANGWINS-report.md` Step 4, fresh output dir per run).
Each is **RED class FAIL** (clean frontend parse rejection, deterministic 3/3): dump rc=2, **0 `.c`
emitted** (no `error[3000]` → clean-FAIL per the Step-4 rules), dump stdout 0 bytes, stderr
byte-identical 3/3 per fixture. Neither ICE nor CRASH observed. These L0-L2 contracts are the
hand-computed C89 padding/bit-accounting regression net — contract-ONLY, NOT runnable today, never
forced GREEN. Corpus +3 (mi_matrix 343→346). No implementation yet.

| dir | feature | RED class | expected GREEN stdout |
|---|---|---|---|
| `packed_l0_flags_xmod` | `packed struct` L0: bool bitflags `{a,b,c: bool}` (LSB-first, 3 bools → 1 byte) | clean parse FAIL error[2000] at `struct` (col 21) after `packed` lexed as identifier; 0 `.c`; deterministic 3/3 | `1 5 1\n` |
| `packed_l1_mix_xmod` | `packed struct` L1: mixed widths `{x:u1, y:u3, z:u4}` in 1 byte (LSB-first bit accounting) | clean parse FAIL error[2000] at `struct` (col 19); 0 `.c`; deterministic 3/3 | `1 155 1 5 9\n` |
| `packed_l2_straddle_xmod` | `packed struct` L2: straddling field `{a:u5, b:u8}` — b spans bytes 0-1 (bits 5..12) | clean parse FAIL error[2000] at `struct` (col 21); 0 `.c`; deterministic 3/3 | `2 255 31 31 255\n` |

- **Current RED status — packed_l0_flags_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes. dump.err
  verbatim: `repro/mi_matrix/packed_l0_flags_xmod/main.zig:8:21: error[2000]: expected ';' but found
  token` then `repro/mi_matrix/packed_l0_flags_xmod/main.zig:8:21: error[2000]: unexpected token`.
  Line 8 = `const Flags = packed struct {`; col 21 (0-based) = the `struct` token — `packed` at col
  14 parses as a bare identifier in the const value expr, then the `struct` keyword terminates the
  expr with no `;`. stderr md5 `1ffc4f38…` byte-identical 3/3.
- **Current RED status — packed_l1_mix_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes. dump.err
  verbatim: `repro/mi_matrix/packed_l1_mix_xmod/main.zig:6:19: error[2000]: expected ';' but found
  token` then `…:6:19: error[2000]: unexpected token`. Line 6 = `const Mix = packed struct {`; col 19
  (0-based) = the `struct` token (`packed` at col 12). stderr md5 `0d31d96d…` byte-identical 3/3.
- **Current RED status — packed_l2_straddle_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes.
  dump.err verbatim: `repro/mi_matrix/packed_l2_straddle_xmod/main.zig:7:21: error[2000]: expected
  ';' but found token` then `…:7:21: error[2000]: unexpected token`. Line 7 =
  `const Strad = packed struct {`; col 21 (0-based) = the `struct` token (`packed` at col 14). stderr
  md5 `4ac74363…` byte-identical 3/3.
- **Rule (L0-L2 = the padding regression net):** once `packed struct` parses and lowers as true
  LSB-first bitfields with NO padding and `size=(bits+7)/8`, stride=size:
  - `packed_l0_flags_xmod` MUST print `1 5 1\n` (rc=0) — 3 bools = 1 byte; a=true(bit0),
    b=false, c=true(bit2) ⇒ byte `0b00000101` = 5; `f.a and !f.b and f.c` ⇒ 1;
  - `packed_l1_mix_xmod` MUST print `1 155 1 5 9\n` (rc=0) — size 1; x=1(bit0), y=5(bits1-3),
    z=9(bits4-7) ⇒ byte `0b10011011` = 155; field reads 1 5 9;
  - `packed_l2_straddle_xmod` MUST print `2 255 31 31 255\n` (rc=0) — size 2; a=31(11111 bits0-4),
    b=255(8 bits @5..12) ⇒ byte0 `0xFF`, byte1 `0x1F`; field reads 31 255.

## Langwins feature-gap fixtures (v60 2026-09-03) — R7 arbitrary-width int REPRO row

New-corpus REPRO fixture (plan `2026-09-03-language-wins-r-i-plan.md`, Task R7): integer types of
ARBITRARY width — `u3`/`i7`/`u12`. Only the fixed widths register as primitive type names
(`registerPrimitiveName`, `sf/src/type_registry.zig:630-635` — i8/u8/u16/u32/u64/i16/i32/i64/f32/...),
so an unregistered width name in a var-decl type annotation does NOT produce the predicted unknown-type
diagnostic — it silently degrades to TYPE_VOID (probe: an arbitrary unknown name `bogusname` degrades
identically, so this is a general unknown-type-name fallback, not uN-specific). Measured on the
reference `/tmp/fx_subfolder/zig1` md5 `1a5056b2` via the authoritative classify1.sh recipe
(`.superpowers/sdd/task-LANGWINS-report.md` Step 4, fresh output dir per run). **RED class: clean
error[3000] rejection (compile-gate label GREEN — a FALSE green, NOT a genuine green-guard)**: dump
rc=2, **0 `.c` emitted**, no ICE/CRASH. Each `uN`/`iN` var-decl fires the GENERIC `cannot declare
variable of type void` (the `var_declared_void` green-guard diagnostic,
`sf/src/semantic_analyzer.zig:2023-2030`) — the unknown width is masked as a void variable, so this
valid `u3` program is currently indistinguishable from a genuine `var x: void` misuse. Deterministic
3/3 (dump.err md5 `2f6985ba…` byte-identical; 4 error/warning pairs = the four var-decls a/b/c/d).
Corpus +1 (mi_matrix 342→343). No implementation yet — this row is a GREEN-contract expectation, NOT
runnable today.

| dir | feature | RED class | expected GREEN stdout |
|---|---|---|---|
| `int_arbitrary_width_xmod` | arbitrary-width integer types `u3`/`i7`/`u12` (N in 1..65535) in var-decl annotations + arithmetic | clean error[3000] rejection (compile-gate label GREEN, FALSE green — NOT a genuine green-guard; unknown width name silently resolves to TYPE_VOID → generic `cannot declare variable of type void`; 0 `.c`; deterministic 3/3) | `7 -3 3000 4\n` |

- **Status update (2026-09-04, F-CLEANDIAG GATE):** class **unchanged GREEN** — this fixture is the
  R7 void-fallback manifestation now covered by F-CLEANDIAG. Its stderr MESSAGE changed with the
  unknown-type gate (`feat` `932fea8d`): the four bare-ident var-decl annotations (u3/u3/i7/u12) now
  report `error[3000]: unknown type in variable declaration` and there are **0** occurrences of
  `cannot declare variable of type void` — the generic void-conflation message is GONE for unknown type
  names. NO fix commit and NO class move (the compile-gate label was already GREEN pre-fix; the RED
  class was a FALSE green, the valid `u3` program still does NOT compile — arbitrary-width uN/iN remain
  unregistered types, F-CLEANDIAG added only the precise diagnostic, not the width feature). Historical
  RED root-cause record beneath retained verbatim.
- **Current RED status — int_arbitrary_width_xmod:** dump rc=2, 0 `.c` emitted, stdout 0 bytes. The
  four typed var-decls each fire an `error[3000]: cannot declare variable of type void` +
  `warning[3000]: type mismatch in variable declaration -- initialization type may not be compatible
  with declared type` (text as of Task 18; the historical observation read `—`) pair (`note: source: comptime_int` / `note: target: void`); the analyzer stops
  after the 4th (var `d: u3`). NO unknown-type diagnostic exists for the unregistered width. Observed
  caret-context quirk: the echoed source line under each diagnostic is the PRECEDING line's text while
  the `line:col` points at the declaration (display off-by-one, line numbers authoritative). stderr md5
  `2f6985bae684274035b47118c935dc7d` byte-identical 3/3. A scratch probe with `var a: bogusname = 5;`
  produces the IDENTICAL diagnostic → unknown type names in var-decl annotations generally fall back to
  void (no `unknown type` error[30xx]), which is why a future corpus sweep would mislabel this row a
  green-guard — it is NOT (the program is valid Zig; the width simply fails to register).
- **Rule:** the fixture MUST print `7 -3 3000 4\n` (rc=0) — u3 5+2=7; i7 -3; u12 3000; u3 7&4=4 —
  once arbitrary-width int types uN/iN register as real types (with arithmetic + `@intCast(i32, …)`
  lowering); at GREEN time the analyzer must also stop conflating unregistered-width names with `void`.

## Langwins feature-gap fixtures (v59 2026-09-03) — R6 switch case-range REPRO row

- **RESOLVED (2026-09-03, COMBINED items-3-6 GATE, F-SWITCHRANGE `bbe47d0e`):** the
  `switch_case_range_xmod` fixture is now **GREEN** — the range prong items `1...5`/`6...9` and
  `'a'...'e'`/`'f'...'z'` now expand to real per-value case dispatch (fixed by commit `bbe47d0e` —
  switch case-range per-value expansion + itoa64 case hardening). Its run-gate contract below now
  **PASSES**: run rc=0 with stdout `130 47`. The RED class was runtime-wrong — the compile gate was OK
  but the range case labels were dropped (all prongs fell to `else`), printing `0 0`. It **no longer
  belongs in the expected-fail set** (kept as a permanent regression guard). The historical RED
  root-cause record beneath this marker is retained verbatim as evidence.

New-corpus REPRO fixture (plan `2026-09-03-language-wins-r-i-plan.md`, Task R6): `switch` prong items
that are RANGES — `1...5` (inclusive int range) and `'a'...'e'` (inclusive char range). Range nodes ARE
parsed (parser.zig:977-981 range_exclusive/inclusive) but switch lowering does not turn them into case
labels. Measured on the reference `/tmp/fx_subfolder/zig1` md5 `1a5056b2` via the authoritative
classify1.sh + fixture_run.sh recipe (`.superpowers/sdd/task-LANGWINS-report.md` Step 4, fresh output
dir per run). **RED class runtime-wrong**: dump rc=0, 4 `.c` emitted, dump stdout+stderr 0 bytes (NO
frontend diagnostic — the ranges are not rejected), gcc `-c` clean (compile gate OK), so the run-gate
applies → `RUNRC=0` with stdout **`0 0`** (contract `130 47`). The emitted switch keeps ONLY
`default: goto z_bb_3;` — the range prongs' bodies are still emitted but unreachable (no case labels),
so every call falls to `else` = 0. Deterministic 3/3 (emitted main md5 `3fb6c7cb…`, prog.out md5
`5928dd99…`). Neither ICE nor CRASH observed. Corpus +1 (mi_matrix 341→342). No implementation yet —
this row is a GREEN-contract expectation, NOT runnable today.

| dir | feature | RED class | expected GREEN stdout |
|---|---|---|---|
| `switch_case_range_xmod` | switch prong ranges `1...5`/`6...9`, `'a'...'e'`/`'f'...'z'` (inclusive) → real dispatch | runtime-wrong (compile gate OK; range case labels dropped → all prongs fall to `else`; deterministic 3/3) | `130 47\n` |

- **Current RED status — switch_case_range_xmod:** dump rc=0, 4 `.c` emitted, stdout+stderr 0 bytes.
  Emitted `zF_78D6088B_inRange` is `switch (n) { default: goto z_bb_3; }` followed by the two range
  prongs' bodies (`zT_2 = 10;` / `zT_3 = 20;`) as DEAD unreachable code, then `z_bb_3: zT_4 = 0;` — the
  `1...5`/`6...9` case labels never lower, so every call jumps straight to `else`. `charClass` identical
  shape. Full chain (fixture_run.sh) 3x → each `RUNRC=0` stdout `0 0` (expected `130 47`) = runtime-wrong.
  Emitted main md5 `3fb6c7cb4f87e8c8f1fb7861b4086c58` (module `main_14A2705C.c`) byte-identical 3/3.
- **Rule:** the fixture MUST print `130 47\n` (rc=0) — int ranges `1..5`=>10, `6..9`=>20 over 1..9 and
  char ranges `'a'..'e'`=>1, `'f'..'z'`=>2 over 'a'..'z' — once switch lowering turns range prong items
  into real case dispatch (the current signature: case labels dropped, prong bodies dead, all falls to
  `else`).

## Langwins feature-gap fixtures (v58 2026-09-03) — R5 cross-module pub var REPRO row

- **RESOLVED (2026-09-03, COMBINED items-3-6 GATE, F-CROSSMOD-STORE `3ad5c12e`):** the
  `crossmod_pubvar_xmod` fixture is now **GREEN** — the importer-side STORE of a cross-module pub var
  now lowers via a real path (fixed by commit `3ad5c12e` — cross-module pub var scalar store, module
  base `store_global` routing). Its run-gate contract below now **PASSES**: run rc=0 with stdout
  `7 7` (importer write visible to the owner's `read()` — ONE storage cell). The RED class was ICE
  `error[3043] internal: unsupported field-store base` rc=3 on the importer-side store. It **no longer
  belongs in the expected-fail set** (kept as a permanent regression guard). The historical RED
  root-cause record beneath this marker is retained verbatim as evidence.

New-corpus REPRO fixture (plan `2026-09-03-language-wins-r-i-plan.md`, Task R5): a module-scope `pub
var` imported AND **directly written** from another module (`other.shared = 7` in `main.zig`, then read
back via `other.read()`, a function in the owning module). This is the **ASYMmetry probe**: importer
writes, owner reads — both must refer to ONE storage cell. Measured on the reference
`/tmp/fx_subfolder/zig1` md5 `1a5056b2` via the authoritative classify1.sh recipe
(`.superpowers/sdd/task-LANGWINS-report.md` Step 4, fresh output dir per run). **RED class ICE
(error[3043])**: dump rc=3, **0 `.c` emitted** — the importer-side STORE of a cross-module pub var hits
a designed internal-error halt `error[3043]: internal: unsupported field-store base` in the lowerer
(`sf/src/lower.zig:1264/1267`, `iceFieldStoreUnsupported` fall-through when the base's resolved type is
neither struct/slice/tagged-union). Deterministic 3/3 (dump.err md5 `ec67ef7f…` byte-identical). NOT
the predicted runtime-wrong class: the store is unimplemented, so the run-gate is never reached. The
**read** side of the same pub var IS green-path (P1-2 fix present): a read-only variant dumps rc=0 and
the owner's emitted header carries the extern decl `extern int zG_A4F844D4_shared;` — but the store to
it is not implemented. ICE flagged per task rules. Corpus +1 (mi_matrix 340→341). No implementation
yet — this row is a GREEN-contract expectation, NOT runnable today.

| dir | feature | RED class | expected GREEN stdout |
|---|---|---|---|
| `crossmod_pubvar_xmod` | module-scope `pub var` — importer writes, owner's fn reads, ONE storage cell | ICE (error[3043] `internal: unsupported field-store base` on the importer-side store; 0 `.c`; deterministic 3/3) | `7 7\n` |

- **Current RED status — crossmod_pubvar_xmod:** dump rc=3, 0 `.c` emitted. dump.err verbatim:
  `warning[3023]: module used as value expression` then
  `error[3043]: internal: unsupported field-store base (node 9)`; stderr md5 `ec67ef7ff2…`
  byte-identical 3/3. Isolated probes (import forms + per-statement): bare `@import("other")` and
  `.zig`-suffixed `@import("other.zig")` resolve identically (same owner module hash `other_BE9F306D`);
  a read-only variant (`var x: i32 = other.shared;`) dumps rc=0 with 2 `.c` and the owner header
  carries `/* Storage globals (extern decls) */ extern int zG_A4F844D4_shared;` (P1-2 fix present);
  a same-module `pub var` store control dumps rc=0 (1 `.c`). Only the importer-side cross-module
  STORE triggers the ICE.
- **Rule:** the fixture MUST print `7 7\n` (rc=0) — importer write visible to the owner's `read()` —
  once the importer-side store of a cross-module pub var gains a real lowering path; the emitted C must
  then hold ONE definition in the owner module (extern header decl in the importer, per the P1-2 shape).

## Langwins feature-gap fixtures (v57 2026-09-03) — R4 export fn/var REPRO rows

- **RESOLVED (2026-09-03, COMBINED items-3-6 GATE, F-EXPORT `9b2fef74`):** the `export_fn_xmod`
  fixture is now **GREEN** — the `export fn square` decl now parses and lowers to a source-named,
  externally-visible C function symbol (fixed by commit `9b2fef74` — export parser bit + registry +
  mangler exemption; the emitted C holds a NON-STATIC `int square(int n) { … }` definition by source
  name, no `zF_…_square` mangled name). Its run-gate contract below now **PASSES**: run rc=0 with
  stdout `81`, with the **symbol gate** holding (emitted C has the non-static `square` defn). The RED
  class was clean parse FAIL `error[2000]` at the `export` keyword (`kw_export` had no parser handler).
  It **no longer belongs in the expected-fail set** (kept as a permanent regression guard). The
  historical RED root-cause record beneath this marker is retained verbatim as evidence.
- **RESOLVED (2026-09-03, COMBINED items-3-6 GATE, F-EXPORT `9b2fef74`):** the `export_var_xmod`
  fixture is now **GREEN** — the `export var counter` decl now parses and lowers to a source-named
  external storage symbol (fixed by commit `9b2fef74` — export parser bit + registry + mangler
  exemption; the emitted C holds a NON-STATIC `int counter;` definition by source name, no
  `zG_…_counter` mangled name). Its run-gate contract below now **PASSES**: run rc=0 with stdout `3`,
  with the **symbol gate** holding (emitted C exposes non-static `counter`). The RED class was clean
  parse FAIL `error[2000]` at the `export` keyword (`kw_export` had no parser handler). It **no longer
  belongs in the expected-fail set** (kept as a permanent regression guard). The historical RED
  root-cause record beneath this marker is retained verbatim as evidence.

New-corpus REPRO fixtures (plan `2026-09-03-language-wins-r-i-plan.md`, Task R4): the `export`
modifier keyword HAS a token (`kw_export`, `sf/src/token.zig:156`) but NO parser handler — `export fn` /
`export var` do not parse. Measured on the reference `/tmp/fx_subfolder/zig1` md5 `1a5056b2` via the
authoritative classify1.sh recipe (`.superpowers/sdd/task-LANGWINS-report.md` Step 4, fresh output dir
per run). Each is **RED class FAIL** (clean frontend rejection, deterministic 3/3): dump rc=2, **0 `.c`
emitted** (no `error[3000]` → clean-FAIL per the Step-4 rules), with the parse diagnostic pointing at
the `export` keyword (col 0). Unlike the R1-R3 silent-dump builtin cases, this is a genuine PARSE-level
clean FAIL — the expected signature for a keyword with no parser handler. Neither ICE nor CRASH observed.
Corpus +2 (mi_matrix 338→340). No implementation yet — these rows are GREEN-contract expectations, NOT
runnable today.

| dir | feature | RED class | expected GREEN stdout |
|---|---|---|---|
| `export_fn_xmod` | `export fn` — source-named, externally-visible C function symbol | FAIL (clean parse diag at `export`; 0 `.c`; deterministic 3/3) | `81\n` (+ symbol gate: emitted C has a non-static `square` defn) |
| `export_var_xmod` | `export var` — source-named external storage symbol | FAIL (clean parse diag at `export`; 0 `.c`; deterministic 3/3) | `3\n` (+ symbol gate: emitted C exposes non-static `counter`) |

- **Current RED status — export_fn_xmod:** `kw_export` has no parser handler → clean parse FAIL at
  `main.zig:8:0` (the `export` keyword, col 0), two `error[2000]` pairs (`expected expression` /
  `unexpected token`) followed by a `:`-recovery pair at `8:18` and a duplicate pair at `10:0`. stderr
  md5 `97924fc3…` byte-identical 3/3; dump rc=2; 0 `.c` emitted.
- **Current RED status — export_var_xmod:** clean parse FAIL at `main.zig:7:0` (the `export` keyword,
  col 0), one `error[2000]` pair (`expected expression` / `unexpected token`). stderr md5 `525d7e69…`
  byte-identical 3/3; dump rc=2; 0 `.c` emitted.
- **Rule:** each fixture MUST print its expected GREEN stdout above (rc=0) AND expose the source-named
  symbol once `export` gains a parser+lowering path. The real `export` contract is the **SYMBOL GATE**:
  the emitted C must contain a NON-STATIC definition named `square` (fn) / `counter` (var) with the
  source name — the runtime-`stdout` contract alone is weak (a non-exported fn can print the same bytes).
  At GREEN time assert the symbol gate by grepping the emitted C for the non-static `square`/`counter`
  definition; the current parse-level FAIL (0 `.c`) cannot reach the gate yet.

## Langwins feature-gap fixtures (v56 2026-09-03) — R3 bitcast-builtin REPRO row

- **RESOLVED (2026-09-03, COMBINED items-3-6 GATE, F-BITCAST `3922a8d7`):** the
  `builtin_bitcast_xmod` fixture is now **GREEN** — the `@bitCast(Dest, src)` call now lowers as a
  same-size integer reinterpretation (fixed by commit `3922a8d7` — @bitCast same-size integer
  reinterpretation). Its run-gate contract below now **PASSES**: run rc=0 with stdout `-1` (u32
  0xFFFFFFFF reinterpreted as i32). The RED class was compile-OK runtime-wrong — the emitted C was
  VALID (gcc `-c` clean) but the silent-drop signature printed `0` (the var's zero-init) instead of
  the contract `-1`. It **no longer belongs in the expected-fail set** (kept as a permanent regression
  guard). The historical RED root-cause record beneath this marker is retained verbatim as evidence.

New-corpus REPRO fixture (plan `2026-09-03-language-wins-r-i-plan.md`, Task R3): the same-size
reinterpretation builtin `@bitCast` is ABSENT from sf/src — grep of sf/src for `bitCast` returns NO
matches. Measured on the reference `/tmp/fx_subfolder/zig1` md5 `1a5056b2` via the authoritative
classify1.sh recipe (`.superpowers/sdd/task-LANGWINS-report.md` Step 4, fresh output dir per run).
RED at the RUN gate: the dump is silent (rc=0, 4 `.c` emitted, 0-byte stderr — the R1/R2 silent-dump
pattern again, NO frontend diagnostic), but unlike R1/R2 the emitted C is VALID — gcc `-c` passes
(compile gate **OK**), so the run-gate applies. The `@bitCast(i32, u)` call is silently DROPPED: the
emitted main computes `zT_2 = (unsigned int)zT_1;` then `(void)zT_2;` and `s` falls back to its
zero-init (`int zT_4 = 0; s = zT_4;`) → full chain prints `0` instead of the contract `-1` →
**class runtime-wrong, deterministic 3/3**. Neither ICE nor CRASH observed. Corpus +1 (mi_matrix
337→338). No implementation yet — this row is a GREEN-contract expectation, NOT runnable today.

| dir | feature | RED class | expected GREEN stdout |
|---|---|---|---|
| `builtin_bitcast_xmod` | `@bitCast(Dest, src)` — same-size reinterpretation | runtime-wrong (compile gate OK; silent drop; deterministic 3/3) | `-1\n` (u32 0xFFFFFFFF reinterpreted as i32) |

- **Current RED status — builtin_bitcast_xmod:** `@bitCast(i32, u)` has no lowering branch — emitted
  `zT_1 = 4294967295u; zT_2 = (unsigned int)zT_1; (void)zT_2;` (result discarded) and the var `s`
  stays at its zero-init (`int zT_4 = 0; s = zT_4; s = zT_4; s = zT_4;`) → run-gate `RUNRC=0`
  stdout `0` (expected `-1`) = runtime-wrong. Emitted main md5 `4b85e4fc…` (module
  `main_0B4CB05F.c`) byte-identical 3/3.
- **Rule:** the fixture MUST print `-1` (rc=0) once `@bitCast` gains a real lowering branch; the
  current silent-drop signature (valid C that discards the result and prints the var's zero-init)
  marks the missing-bitcast gap.

## Langwins feature-gap fixtures (v55 2026-09-03) — R2 pointer-builtin REPRO rows

- **RESOLVED (2026-09-03, F-PTRBUILTIN `c5381d94` + `35468510`):** the `builtin_ptr_roundtrip_xmod`
  fixture is now **GREEN** — the `@intFromPtr(p)`/`@ptrFromInt(a)` calls now lower (fixed by commit
  `35468510` — `@intFromPtr` as an ALIAS branch-extension of the existing `@ptrToInt`, and `@ptrFromInt`
  in its ANNOTATED form reading the target pointer type from the expected-type stack — preceded by the
  `test:` fixture amend `c5381d94` that annotates the `@ptrFromInt` target var `q: *i32` so the
  expected type is resolvable). Its run-gate contract below now **PASSES**: run rc=0 with stdout `42`
  (store 42 through recovered ptr). It **no longer belongs in the expected-fail set** (kept as a
  permanent regression guard). The historical RED root-cause record beneath this marker is retained
  verbatim as evidence.
- **RESOLVED (2026-09-03, F-PTRBUILTIN `c5381d94` + `35468510`):** the `builtin_fieldparentptr_xmod`
  fixture is now **GREEN** — the `@fieldParentPtr(Outer, "inner", &o.inner)` call now recovers the
  container pointer (fixed by commit `35468510` — a struct byte-offset 4-inst chain: resolve the
  `Outer` struct fields, match the `"inner"` field name to its byte offset, `ptr_to_int(&o.inner) −
  offset`, then `int_to_ptr` back to `*Outer`). Its run-gate contract below now **PASSES**: run rc=0
  with stdout `1` (recovered ptr == &o). It **no longer belongs in the expected-fail set** (kept as a
  permanent regression guard). The historical RED root-cause record beneath this marker is retained
  verbatim as evidence.

New-corpus REPRO fixtures (plan `2026-09-03-language-wins-r-i-plan.md`, Task R2): the modern pointer
builtins `@intFromPtr` / `@ptrFromInt` / `@fieldParentPtr` are ABSENT from sf/src — grep of sf/src for
`intFromPtr|ptrFromInt|fieldParentPtr` returns NO matches, while the OLD names `@ptrToInt`/`@intToPtr`
DO exist (sf/src/lower.zig:438-440; semantic_analyzer.zig:93-95). Measured on the reference
`/tmp/fx_subfolder/zig1` md5 `1a5056b2` via the authoritative classify1.sh recipe
(`.superpowers/sdd/task-LANGWINS-report.md` Step 4, fresh output dir per run). Each is **RED class FAIL**
(emission-defect GCCFAIL, deterministic 3/3): dump rc=0 with 4 `.c` emitted and 0-byte stderr (NO
frontend diagnostic — the R1 silent-dump pattern again: the calls lower to dangling temps / a
struct-typed result), then gcc `-c` rejects the emitted `main_*.c`. Neither ICE nor CRASH observed.
Corpus +2 (mi_matrix 335→337). No implementation yet — these rows are GREEN-contract expectations, NOT
runnable today.

| dir | feature | RED class | expected GREEN stdout |
|---|---|---|---|
| `builtin_ptr_roundtrip_xmod` | `@intFromPtr(p)`/`@ptrFromInt(a)` — pointer-int round trip | FAIL (GCCFAIL, deterministic 3/3) | `42\n` (store 42 through recovered ptr) |
| `builtin_fieldparentptr_xmod` | `@fieldParentPtr(Outer, "inner", &o.inner)` — recover container ptr | FAIL (GCCFAIL, deterministic 3/3) | `1\n` (recovered ptr == &o) |

- **Current RED status — builtin_ptr_roundtrip_xmod:** `@intFromPtr(p)` and `@ptrFromInt(a)` have no
  lowering branch — the emitted main body ends `(void)zT_4;` `(void)zT_6;` `q = zT_8;` referencing
  never-declared result temps `zT_6`/`zT_8` → gcc `error: 'zT_6' undeclared (first use in this
  function)` and `'zT_8' undeclared` (`main_083B9CD1.c:19:11` / `:20:9`). Emitted main md5 `6e2eb21f…`
  byte-identical 3/3.
- **Current RED status — builtin_fieldparentptr_xmod:** `@fieldParentPtr(Outer, "inner", &o.inner)`
  mis-types its result as a struct VALUE — emitted C declares `zT_2E7A8214_Outer po;` plus three
  `po = zT_9;` zero-init stores, then compares via `zT_13 = (unsigned int)po;` → gcc `error: aggregate
  value used where an integer was expected` (`main_D9BA0AD5.c:41:5`). Emitted main md5 `90c5cbc9…`
  byte-identical 3/3.
- **Rule:** each fixture MUST print its expected GREEN stdout above (rc=0) once the builtins gain real
  lowering branches; the current silent-dump signatures (never-declared result temps / struct-value
  result where a pointer is required) mark the missing pointer-builtin gap. The old-name aliases
  `@ptrToInt`/`@intToPtr` already work — only the modern spellings and `@fieldParentPtr` are absent.

## Langwins feature-gap fixtures (v54 2026-09-03) — R1 introspection-builtin REPRO rows

- **RESOLVED (2026-09-03, F-INTRO `c8145a8b`):** the `builtin_offsetof_xmod` fixture is now **GREEN** —
  the `@offsetOf(Mixed, "c"/"b"/"d")` calls fold at comptime to the field byte offsets 0/4/8 (fixed by
  commit `c8145a8b` — struct-only `@offsetOf`/`@bitOffsetOf`/`@bitSizeOf` fold branches in
  `sf/src/comptime_eval.zig` + the introspection name-ids in semantic_analyzer/lower). Its run-gate
  contract below now **PASSES**: run rc=0 with stdout `0 4 8` (folded int_consts `zT_N = 0/4/8;` in
  emitted `main_0B772F7A.c`, no struct zero-init). It **no longer belongs in the expected-fail set**
  (kept as a permanent regression guard). The historical RED root-cause record beneath this marker is
  retained verbatim as evidence.
- **RESOLVED (2026-09-03, F-INTRO `c8145a8b`):** the `builtin_bitsizeof_xmod` fixture is now **GREEN** —
  the `@bitSizeOf(bool/u8/u32)` calls fold at comptime to 1/8/32 (fixed by commit `c8145a8b` — the
  `@bitSizeOf` size×8 fold with the bool→1 special case). Its run-gate contract below now **PASSES**:
  run rc=0 with stdout `1 8 32` (folded int_consts `zT_N = 1/8/32;` in emitted `main_481CB325.c`, no
  never-declared temps). It **no longer belongs in the expected-fail set** (kept as a permanent
  regression guard). The historical RED root-cause record beneath this marker is retained verbatim as
  evidence.
- **RESOLVED (2026-09-03, F-INTRO `c8145a8b`):** the `builtin_bitoffsetof_xmod` fixture is now **GREEN** —
  the `@bitOffsetOf(Mixed, "c"/"b"/"d")` calls fold at comptime to the field byte offsets 0/4/8 × 8 =
  0/32/64 (fixed by commit `c8145a8b` — struct-only `@bitOffsetOf` shares the `@offsetOf` fold branch,
  result × 8). Its run-gate contract below now **PASSES**: run rc=0 with stdout `0 32 64` (folded
  int_consts `zT_N = 0/32/64;` in emitted `main_A9A908BB.c`, no struct zero-init). It **no longer
  belongs in the expected-fail set** (kept as a permanent regression guard). The historical RED
  root-cause record beneath this marker is retained verbatim as evidence.

New-corpus REPRO fixtures (plan `2026-09-03-language-wins-r-i-plan.md`, Task R1): the three introspection
builtins `@offsetOf` / `@bitSizeOf` / `@bitOffsetOf` have NO lowering branch in zig1 today. Measured on the
reference `/tmp/fx_subfolder/zig1` md5 `1a5056b2` via the authoritative classify1.sh recipe
(`.superpowers/sdd/task-LANGWINS-report.md` Step 4, fresh output dir per run). Each is **RED class FAIL**
(emission-defect GCCFAIL, deterministic 3/3): dump rc=0 with 4 `.c` emitted and 0-byte stderr (no frontend
diagnostic), then gcc `-c` rejects the emitted `main_*.c`. Corpus +3 (mi_matrix 332→335). No
implementation yet — these rows are GREEN-contract expectations, NOT runnable today.

| dir | feature | RED class | expected GREEN stdout |
|---|---|---|---|
| `builtin_offsetof_xmod` | `@offsetOf(T, "field")` — comptime field byte offset | FAIL (GCCFAIL, deterministic 3/3) | `0 4 8\n` (c:u8@0, b:u32@4, d:u16@8) |
| `builtin_bitsizeof_xmod` | `@bitSizeOf(T)` — comptime bit size | FAIL (GCCFAIL, deterministic 3/3) | `1 8 32\n` (bool=1, u8=8, u32=32) |
| `builtin_bitoffsetof_xmod` | `@bitOffsetOf(T, "field")` — comptime bit offset | FAIL (GCCFAIL, deterministic 3/3) | `0 32 64\n` (byte offsets 0/4/8 × 8) |

- **Current RED status — builtin_offsetof_xmod:** the `@offsetOf(Mixed, "c"/"b"/"d")` calls are
  mis-lowered — emitted C declares `zT_B9A8EF98_Mixed zT_N = {0};` (a zero-init `Mixed` struct) then casts
  the struct to int: `zT_3 = (int)zT_2;` → gcc `error: aggregate value used where an integer was expected`
  (`main_0B772F7A.c:19/25/31`, 3 errors). Emitted main md5 `15d72bd1…` byte-identical 3/3.
- **Current RED status — builtin_bitsizeof_xmod:** the `@bitSizeOf(bool/u8/u32)` results reference
  never-declared temps — emitted `zT_2 = (int)zT_1;` etc. → gcc `error: 'zT_1' undeclared (first use in
  this function)` (`main_481CB325.c:16/22/28`, likewise `'zT_6'`/`'zT_11'`). Emitted main md5 `71077278…`
  byte-identical 3/3.
- **Current RED status — builtin_bitoffsetof_xmod:** identical shape to builtin_offsetof_xmod — emitted
  `zT_B9A8EF98_Mixed zT_N = {0}; zT_3 = (int)zT_2;` → gcc `error: aggregate value used where an integer
  was expected` (`main_A9A908BB.c:19/25/31`). Emitted main md5 `312ad771…` byte-identical 3/3.
- **Rule:** each fixture MUST print its expected GREEN stdout above (rc=0) once the builtin gains a real
  lowering branch; the current emission-defect signatures (int-cast of a struct temp / never-declared
  result temp) mark the missing-introspection-builtin gap.

## RED FIXTURE — global_struct_array_store_xmod (2026-09-03)

- **RESOLVED (2026-09-03, F-STORE-DROP `f014259b`):** the fixture is now **GREEN** — fixed by commit
  `f014259b` (C4-helper/C3-semantics, `sf/src/c89_emit.zig` — the `.assign_index` base of a
  global-array-element store is now read-marked via the `dceBaseEscapes` helper, so the by-name
  `load_global` alias is never dead-classified). Its runtime guard rule below now **PASSES**: run rc=0
  with stdout `1 5 5 10`. It **no longer belongs in the expected-fail set** (kept as a permanent
  regression guard). mud_server movement restored (verified vs the zig0 oracle). The historical
  root-cause record beneath this marker is retained verbatim as evidence.

New corpus fixture `repro/mi_matrix/global_struct_array_store_xmod/main.zig` (plan
`2026-09-02-switch-expr-payload-capture-fix-plan.md` AMENDMENT 2, Task I3-STORE-DROP): zig1 DROPS
a struct-value (indeed ANY whole-element) assignment into a **storage-global array element**.
`fn initRooms()` builds each `Room` in locals then `return;`s — no `zG_...rooms[i] = zT_N;` write
is emitted. Root cause (evidence in `.superpowers/sdd/task-SWEXPR-report.md` `## I3-STORE-DROP`):
the whole-element store is lowered (sf/src/lower.zig:1139-1161) as `.assign_index` whose base is
the by-name load_global alias temp of the global array (c89_emit.zig:5172-5181 `temp_global_map`).
The emitter DCE pass never read-marks an ARRAY-typed assign_index base (c89_emit.zig:7080,
`dceTempIsArray` :7055-7068), so that alias temp has read_count 0 → dead (c89_emit.zig:3380-3381),
and the emission filter skips any inst whose result temp is dead (c89_emit.zig:7384-7387;
assign_index "result" = base, dceResultPos :7202). Every later read of the global creates a fresh
alias temp, so the store is dead-classified in every function that performs it → **unconditionally
dropped**. Original repro: mud_server `examples/z98/mud_server/main.zig:31-48` (`var rooms: [2]Room
= undefined;` + whole-struct stores in initRooms) — world global all-zero at runtime, no movement.

- **Expected GREEN stdout** (10 B, deterministic): `1 5 5 10\n` (rooms[0].north=1,
  rooms[0].desc.len=5 ("first"), rooms[1].north=5, rooms[1].desc.len=10 ("secondroom"); values come
  straight from the source stores, verified via a field-store sibling control — same values through
  the WORKING `rooms[i].field = v` path print byte-identical output on the current compiler).
- **Current RED status:** RUNTIME-gated guard — compile-gate OK (dump rc=0, 4 `.c`, 0 `error[`,
  0 PANIC on all 4 compilers; gcc `-c` rc=0, link rc=0) so the standard corpus compile sweep
  classifies it OK; the guard fires in run/golden-style batteries and the F-STORE-DROP gate.
  Measured on all 4 compilers (ref `/tmp/fx_subfolder/zig1` md5 `29327e2c` + the three `e2028dcf`
  self-host binaries): run rc=0 with stdout `0 0 0 0` (8 B — rooms global stays zero-initialized,
  desc is a null slice → len 0), deterministic 3/3 per compiler, != expected GREEN on all four.
  Emitted `initRooms()` defect region (byte-identical across all four): builds `zT_0`/`zT_10`
  (field-by-field `zT_0.north = zT_4;` …) then `return;` with NO `zG_..._rooms[...] = zT_...;`.
- **Rule:** the fixture MUST print the expected GREEN stdout above (rc=0) after any future change;
  a return of zeros (`0 0 0 0`) marks the global array-element store-drop regression.

## RED FIXTURE — switch_expr_payload_capture_xmod (2026-09-02)

- **RESOLVED (2026-09-03, F-SWEXPR `6d71b917`):** the fixture is now **GREEN** — fixed by commit
  `6d71b917` (`sf/src/lower.zig` — expression-switch payload-capture `load_field`/`decl_local`
  emissions moved into the prong's own block, after `current_bb = prong_bb_id`). Its runtime guard
  rule below now **PASSES**: run rc=0 with stdout `helloA\nhelloA\nhelloB\nhelloB\n` (28 B). It **no
  longer belongs in the expected-fail set** (kept as a permanent regression guard). json_parser_upgraded
  (the program that exposed the bug) now runs rc=0 stdout byte-identical. The historical root-cause
  record beneath this marker is retained verbatim as evidence.

New corpus fixture `repro/mi_matrix/switch_expr_payload_capture_xmod/main.zig` (plan
`2026-09-02-switch-expr-payload-capture-fix-plan.md`, Task I-SWEXPR): a switch used as an
EXPRESSION with a payload-capture prong mis-lowers in zig1 — the payload binding
(`load_field` + `decl_local`) is emitted into the wrong block (dead default fall-through in an
exhaustive no-else switch, or the dispatch block before the case label with an `else` prong)
because at the expression-site (`lowerExprImpl`, sf/src/lower.zig ~4169-4171) the capture
emissions precede `self.current_bb = prong_bb_id;` (~4180). The capture is read UNINITIALIZED.
The statement-switch site (`lowerStmt`, ~5026 before ~5028-5052) is correct. Original repro:
U-JSON json_parser_upgraded rc=139 SIGSEGV; probes `/tmp/ujson/probes/pA.zig` (exhaustive
no-else, rc=139) + `pB.zig` (else-unreachable, garbage).

- **Expected GREEN stdout** (28 B, deterministic, both paths identical): `helloA\nhelloA\n
  helloB\nhelloB\n` (k=0 → payload `helloA`, k=1 → `helloB`; per k an expression-switch
  extraction line then a statement-switch sibling line).
- **Current RED status:** RUNTIME-gated guard — compile-gate OK (dump rc=0, 4 `.c`, 0 `error[`,
  0 PANIC on all 4 compilers; gcc `-c` + link rc=0) so the standard corpus compile sweep
  classifies it OK; the guard fires in run/golden-style batteries and the F-task gate. Measured
  on all 4 compilers (ref `/tmp/fx_subfolder/zig1` + the three `e2028dcf` self-host binaries):
  run rc=0 with stdout `\nhelloA\n\nhelloB\n` (16 B — the two expression-switch lines are EMPTY,
  the captured slice is uninitialized garbage read as empty; emitted `main_*.c` byte-identical,
  md5 `ec77cc10…`, across all four). Sibling shapes crash rc=139 SIGSEGV (pA probe, fixC
  write-loop variant); the committed fixture manifests as deterministic garbage-empty output.
  Emitted defect region (ref): the dispatch `switch (zT_11){case 0: goto z_bb_5; case 1: goto
  z_bb_6; default: goto z_bb_7;}` is followed by `z_bb_5: zT_14 = s;` (reads unassigned capture),
  a stranded `s_1 = kv.payload.A._0;` after the case-0 goto, and `s = kv.payload.A._0;` in the
  dead `z_bb_7` default — while the statement sibling emits `z_bb_1: s = kv.payload.A._0; r = s;`
  correctly inside its case block.
- **Rule:** the fixture MUST print the expected GREEN stdout above (rc=0) after any future change;
  a return of empty expr lines / SIGSEGV / garbage marks the switch-expression payload-capture
  regression.

## GATE — zig1 self-host closure plan, gate-record reconciliation (2026-09-02)

Final gate of the zig1 self-host closure plan (docs/superpowers/plans/2026-09-02-zig1-selfhost-closure-plan.md),
measured on the plan's fixed-point chain (reference `/tmp/fx_subfolder/zig1`, zig0-built md5 `29327e2c`,
vs the 5 byte-identical self-host binaries under `/tmp/zig1_5*`, md5 `e2028dcf`, size 2,930,952 B).
Docs-only task — no `sf/src`, fixture, or script change. Reconciliation notes for the
expected-fail/gate record:

- **4 MD5 gates UNCHANGED (no re-baseline):** gol `302df36b…` / lisp `3591bad9…` / json
  `76056b97…` / mud `4591fef0…` byte-identical on both new hops. Golden 9/9 PASS; matrix 21/21
  PASS (mud/rogue/gol timeout-gated rc=124 = PASS). Corpus 404 dirs at `-s0`: reference
  OK=394 / FAIL=10 (= exactly the 10 green-guards, unchanged set) / ICE=0 / CRASH=0, hop
  identical, **asymmetric = 0**.
- **`_upgraded` example dirs are NEW — exempt from the 4-MD5 gate:** `lisp_interpreter_upgraded`
  (commit `ab318b1e`) and `rogue_mud_upgraded` (commit `93d3ee79`) are new `examples/z98` dirs,
  not corpus/gate members; their emissions differ from the originals by design (source-only
  idiomatic rewrites), stdout byte-identical to the originals on all 4 compilers. The original
  gate dirs (gol/lisp/json/mud) are untouched — no re-baseline.
- **`json_parser_upgraded` DEFERRED (NOT committed) — recorded as a known deferred compiler
  gap:** the planned const-from-switch-expression rewrite (json.zig key extraction) SIGSEGVs
  rc=139 on all 4 compilers from a REAL zig1 emission bug (switch-as-expression with payload
  capture mis-lowers: payload binding emitted after the dispatch `goto` before the case label →
  skipped → uninitialized read). Statement-switch form emits correctly. Follow-up I/F task to
  fix the emission bug to be created by the controller; the untracked dir stays for that fix.

Determinism fixed point **CLOSED** (self-host chain byte-identical, `e2028dcf`); the bootstrap
cycle is closable via the future cInclude-zig1-only migration.

## GATE — spill backend config plan, FULL sweep + reconciliation (2026-09-02)

Final gate battery of the spill backend config plan
(docs/superpowers/plans/2026-09-02-spill-backend-config-plan.md), at HEAD `cc5c37c1`, measured
with `/tmp/fx_subfolder/zig1` (reference rebuilt at HEAD from the F-S self-host generation —
the zig0 bootstrap cannot compile modern `sf/src`; canonical std reinstalled at
`/tmp/fx_subfolder/lib/`) vs self-compiled `/tmp/zig1_5/zig1_5_clean`. Docs-only task — no
`sf/src`, fixture, or script change in this gate. **This is the plan-complete closeout of the
spill backend config: F-SIDE (AST value pools disk-backed) + F-FMT (RES 5 B/node) + F-SBackend
(`SpillStore` Disk/Ram routing) + F-MM (`-mm<N>` default 64 MB ACTIVE) + F-S (`-s<N>` decremental
levels).** The `-s<N>` level is a runtime storage choice — emission is **byte-identical at every
level `-s0`..`-s5`** (same data, different storage medium).

### Pool trajectory (pool= at self-compile, `--markers --track-memory`, self-hosted binary)

| level | pool= (K) | note |
|---|---|---|
| allocator-crux GATE (plan predecessor) | 25,742 | canonical anchor before the spill-config work |
| plan start (I-SIDE baseline) | 15,324 | reference on the pre-change tree |
| `-s0` (all disk, default) | **14,857** | fits the `-mm64` default (no flag needed) |
| `-s1` (+AST → Ram) | 33,290 | fits `-mm64` |
| `-s2` (+LIR → Ram) | 70,922 | **exceeds 64 MB → ICE rc=3 unless paired with `-mm128`** |
| `-s3` (+HASH → Ram) | 70,922 | needs `-mm128` |
| `-s4` (+RES → Ram) | 72,970 | needs `-mm128` |
| `-s5` (all Ram; max level) | **72,970** | Ram-mode resident pool; **no `.zig1_*.tmp` created** |

F-SBackend measured Disk 13,764 K / all-Ram 72,903 K on its intermediate tree; the 13.8–14.9 K
Disk band is the documented free-list segment-reuse noise (F-SBackend note 3), not a real change.
Only `-s0`/`-s1` hold the `-mm64` default on the self-compile workload; `-s2`..`-s5` need `-mm128`
(the documented `-mm`/`-s` pairing tradeoff). Small fixture/gate workloads fit every level
unflagged.

### Step 1 — full gate battery

1. **4 MD5 gates byte-identical at every level `-s0`..`-s5` (repo-root CWD, no re-baseline):** gol
   `302df36be57e9876549d6a8b4031bf95` / lisp `3591bad9726ca0947eae3f8a9a6e7273` / json
   `76056b978f6330c8af0c7f23b3244135` / mud `4591fef0346b42738874ce992c72f4c2` (dump rc=0 each,
   `timeout 120`). Storage-only difference → byte-identity holds at every level.
2. **Golden 9/9 fixtures 9/9 at every level `-s0`..`-s5`** (tco_return_try / tco_defer /
   tco_factorial / fn_ptr_struct_field / func_ptr_return / quicksort / hello /
   emission_assoc_chain_xmod / emission_lower_crash_xmod): runtime stdout + rc byte-identical to
   the F-S golden captures at each level.
3. **21-example matrix 21/21** dump/gcc/link rc=0 (19 RUN_OK + mud_server/rogue_mud
   server-timeout by design; 4 single-file entries func_ptr_return/mandelbrot/quicksort/sort_strings).
4. **Corpus sweep at `-s0` (404 dirs = 330 mi_matrix + 53 top-level repro + 21 z98; `slice_matrix`
   matrix-of-subdirs skipped):** **334 RUN_OK** (incl. `game_of_life` which completed rc=0 with the
   correct glider grid this run — the memory-refactor gate's gol RUN_TIMEOUT was a sweep-timing
   artifact, not a behavior change) + **56 LINK_FAIL** (extern-fn tests; identical
   `undefined reference` class — not a regression) + **10 DUMP_FAIL** (= the 10 green-guards
   exactly: eu_assign_incompat_payload / euvoid_val_catch / field_access_optional / var_declared_void /
   emission_pal_xmod / strictzig_brace_if_xmod / parsergap_selfblok_xmod / parsergap_strict_comma_xmod /
   parsergap_slice_expr_xmod / self_embed_optional_cycle) + **2 RUN_TIMEOUT** (mud_server / rogue_mud,
   servers) + **2 RUN_FAIL** (known symmetric crashes both compilers: `intcast_range_check` rc=134,
   `voiddecl_xmodtype_xmod` rc=139). Garbage dirs `emission_void_temp_enum_xmod` and
   `voiddecl_payload_xmod` classified RUN_OK rc=0 (output unstable by design — NOT a bug). **0
   asymmetric failures, 0 NEW failures** vs the documented baseline (the only delta is gol
   timeout→OK, a timing artifact). Corpus unchanged since the memory-refactor gate (0 new `main.zig`).
5. **Self-compile:** `build_zig1_5.sh` → dump rc=0, **42 `.c`, 0 `error[`, 0 PANIC** (42 = 41 + the
   `spill_store` module — the plan's "41" is stale); rebuilt `zig1_5_clean` runs hello **byte-equal**
   to reference (`Hello, world!\n`). Reference emission vs self-emission: **same 42-file set,
   0 byte-different pairs** (the compiler's own C at HEAD is byte-identical to its self-compile).
6. **`--track-memory` self-compile at `-s0`:** `pool=14857K`; the pool= trajectory is above.

### Step 2 — `-mm` enforcement

- **`-mm64` default is ACTIVE and HOLDS self-compile** at `-s0`/`-s1` (pool 14,857/33,290 K <
  65,536 K).
- **`-s2`..`-s5` at the default ICE rc=3** — `memory limit exceeded: pool limit=65536K pool=70-73M`
  + `ICE: out of memory at allocator.zig:28`; pairing with **`-mm128`** compiles cleanly
  (rc=0, 42 `.c`, 0 err, 0 PANIC) at every level — the documented tradeoff, not a regression.
- **Canary `-mm1` self-compile ICEs rc=3** — `memory limit exceeded: pool limit=1024K pool=6513K`
  + `ICE: out of memory at allocator.zig:28` (budget now live by default; was an inert 16 GiB opt-in).
- Spill-file ladder confirms the prefix deactivation: `-s0` all `.zig1_*.tmp` present,
  `-s1` drops `.zig1_ast.tmp`, `-s2` also `.zig1_lir.tmp`, `-s3` also `.zig1_hash.tmp`,
  `-s4` also `.zig1_res.tmp`, `-s5` none.

### Step 3 — warning-clean confirmation

`gcc -m32 -std=c89 -O3 -Wall -Wextra -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration -I sf/src/include -fsyntax-only` on BOTH
`/tmp/fx_subfolder/*.c` (reference) AND `/tmp/zig1_5/gen/*.c` (self-emitted): **0 warnings,
0 errors** on both, with the 1 pre-authorized `-Wbuiltin-declaration-mismatch` fwrite carve-out
each (`/tmp/fx_subfolder/pal_388A8A1B.c:700` and `/tmp/zig1_5/gen/pal_388A8A1B.c:700` — same
fwrite declaration class, not a defect).

### Milestone statement

The spill backend config plan is **complete**: I-SIDE (AST side-table census) + F-SIDE (AST value
pools `identifiers`/`int_values` disk-backed, −568 K realized) + I-FMT/F-FMT (RES dense record
10→5 B/node, source half → sparse only-on-Set resident map; `.zig1_res.tmp` halves) +
I-SBackend/F-SBackend (`SpillStore` Disk/Ram routing of all five spills, scalar per-spill flags,
uniform `SPILL_SEEK_MAX`; Ram mode = resident, no `.zig1_*.tmp`) + I-MM/F-MM (`-mm<N>` MB hard
budget, default 64 MB ACTIVE) + F-S (`-s<N>` decremental levels, help/README docs). 4 MD5 gates
byte-identical at every level (no re-baseline). Golden 9/9 at every level. Matrix 21/21. Corpus
404 dirs **0 asymmetric**. Self-compile 42 `.c` / 0 err / 0 PANIC, hello byte-equal, reference
emission byte-identical to self-emission. Warning-clean both builds. **pool= at `-s0` = 14,857 K
(same order as the plan-start 15,324 K); the pool rises with `-s` as designed (33,290 → 70,922 →
72,970 K) — a storage tradeoff, not a regression; the `-mm64` default holds `-s0`/`-s1` and the
higher levels need `-mm128` (documented).**

## GATE — zig1 memory-refactor execution plan, FULL battery + reconciliation (2026-08-26)

Final gate battery of the zig1 memory-refactor execution plan
(docs/superpowers/plans/2026-08-26-zig1-memory-refactor-execution-plan.md),
at HEAD `179257dc`, measured with `/tmp/fx_subfolder/zig1` (reference oracle rebuilt at HEAD;
canonical std reinstalled at `/tmp/fx_subfolder/lib/`) vs self-compiled `/tmp/zig1_5/zig1_5_clean`
(built from HEAD by `scripts/self_compile/build_zig1_5.sh`). Docs-only task — no `sf/src`,
fixture, or script change in this gate. **This is the plan-complete closeout of the memory
refactor.** The ≤16,384 K (16 MiB) pool target is **NOT reached**; the S-series outcome is the
DOCUMENTED RESIDUAL (see trajectory below).

### Memory trajectory (pool= at self-compile, `--track-memory --markers`)

| phase | pool= (K) | event |
|---|---|---|
| baseline (pre-S) | 50,501 | canonical anchor (roadmap §1) |
| S-LIR | 42,513 | LIR streaming |
| S-HASH | 44,678 | +2,164 K (input growth + one extra 2 MiB doubling boundary; operator-ruled transient) |
| S-TOKEN | 55,038 | +10,360 K transient (interner-order + lexer window; operator-ruled transient) |
| S-AST | 35,973 | −19,065 K (AST streaming, block-backed 8-slot window) |
| S-RES | 25,738 | −10,235 K (resolved_types dense per-node array) |
| **GATE re-measure** | **25,742** | `track-memory: perm=1661K mod=2047K scr=2047K pool=25742K type_db=246K total=5755K` (Δ4 K = input growth noise vs S-RES) |

**≤16,384 K target NOT reached — documented residual.** Gap = 25,742 − 16,384 = **9,358 K (≈9.14 MiB)**.
Closures/verdicts: **M5** (AST side arrays + token value union slice) closed-unfeasible (S-AST's
block-backed window makes the ~1 MB side-array prize inapplicable); **S-INTERNER** closed-unfeasible
(measured interner text 294,744 B ≈ 0.29 MiB, not the ~4 MB plan estimate — ~3% of the gap at
highest risk, keep-resident); **I-COMPACT** no-go (16-B AstNode is a byte-identical shuffle under a
disk record — record delta 0 or +16,384 B/block worse, +2.2 MiB pool ADD if spans go resident;
migration cost 47 span-read + 45 child_2 sites for ≤0 memory effect). Remaining gap lives in
module-arena live tables / growth-chain levers, out of scope for this plan.

### Step 1 — full gate battery

1. **4 MD5 gates byte-identical (repo-root CWD, no re-baseline):** gol
   `302df36be57e9876549d6a8b4031bf95` / lisp `3591bad9726ca0947eae3f8a9a6e7273` / json
   `76056b978f6330c8af0c7f23b3244135` / mud `4591fef0346b42738874ce992c72f4c2` (dump rc=0 each,
   `timeout 120`). The memory refactor is byte-neutral for the 4 gates.
2. **21-example matrix 21/21** dump/gcc/link rc=0 per program (4 non-`main.zig` entries use their
   own names: `func_ptr_return.zig` / `mandelbrot.zig` / `quicksort.zig` / `sort_strings.zig`).
3. **Corpus sweep (404 dirs = 330 mi_matrix + 53 top-level repro + 21 z98; `slice_matrix`
   matrix-of-subdirs skipped):** **0 ASYMMETRIC diffs** (zig1 == zig1_5 behavior everywhere).
   Distribution: **333 RUN_OK** (rc+output match ref; emitted C byte-identical modulo the
   path-derived std-module hash — the self compiler resolves std from `/tmp/zig1_5/lib`, ref from
   `/tmp/fx_subfolder/lib`, so `std_*.c` names differ but content matches except the
   self-referential `#include` line) + **56 LINK_FAIL** (extern-fn tests; identical
   `undefined reference` for the reference — not a regression) + **10 DUMP_FAIL** (= the 10
   green-guards, both compilers identical) + **2 RUN_FAIL** (known symmetric crashes, both
   compilers: `intcast_range_check` rc=134, `voiddecl_xmodtype_xmod` rc=139) + **3 RUN_TIMEOUT**
   (game_of_life / mud_server / rogue_mud, both compilers; game_of_life glider grid output
   truncated-identical, mud_server boots). **1 garbage OUT_DIFF** = `emission_void_temp_enum_xmod`
   (uninitialized enum temp, output unstable by design — ref `-180421700` vs self `-172545092`,
   both rc=0; NOT a bug; `voiddecl_payload_xmod` the other known garbage dir happened to be EQ
   this run — both non-deterministic). W2-1 fixture `emission_global_alias_xmod` RUN_OK, output
   EQ.
4. **Self-compile:** `build_zig1_5.sh` → dump rc=0, **41 `.c`, 0 `error[`, 0 PANIC**; rebuilt
   `zig1_5_clean` runs hello **byte-equal** to reference (`Hello, world!\n`).
5. **`--track-memory` self-compile:** **`pool=25742K`**, `total=5755K`; residual gap to
   16,384 K = **9,358 K**.

### Step 2 — warning-clean confirmation

`gcc -m32 -std=c89 -O3 -Wall -Wextra -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration -I sf/src/include -fsyntax-only` on BOTH
`/tmp/fx_subfolder/*.c` (reference) AND `/tmp/zig1_5/gen/*.c` (self-emitted): **0 warnings,
0 errors** on both, with the 1 pre-authorized `-Wbuiltin-declaration-mismatch` fwrite carve-out
each (`/tmp/fx_subfolder/pal.c:41` reference; `/tmp/zig1_5/gen/pal_388A8A1B.c:700` self-emitted —
the same fwrite declaration class, not a defect).

### Milestone statement

The zig1 memory-refactor plan is **complete**: Phase 1 (M0/M3/M4) + Phase 2 warnings (W-1..W-4
ref + W2-1..4 gen, both 0-warning) + M1 (AstNode 32→24 B) + M2 (LirInst 32→24 B) + M5
(closed-unfeasible) + M7 (markers) + S-series (S-LIR/S-HASH/S-TOKEN/S-AST/S-RES streaming +
S-INTERNER closed-unfeasible + S-FIX-1..14 correctness) + I-COMPACT no-go. 4 MD5 gates
byte-identical (no re-baseline). Matrix 21/21. Corpus 404 dirs **0 asymmetric**. Self-compile
41 `.c` / 0 err / 0 PANIC, hello byte-equal. Warning-clean both builds. **pool=25,742 K,
target 16,384 K NOT reached — documented residual 9,358 K** (S-series outcome + I-COMPACT verdict).

## GATE — @as + TCO self-emission plan, FINAL sweep + reconciliation (2026-08-26)

Final gate sweep of the @as + TCO self-emission plan
(docs/superpowers/plans/2026-08-26-as-tco-selfcompile-plan.md),
at HEAD `dd83723f`, measured with `/tmp/fx_subfolder/zig1` (rebuilt at HEAD `dd83723f`;
canonical std reinstalled at `/tmp/fx_subfolder/lib/`). Docs-only task — no `sf/src`,
fixture, or script change in this gate. **This is the plan-complete closeout: residual
A+B (the `@as` cast builtin, ONE shared root cause) and residual C (the TCO
self-recursion back-edge) are BOTH CLOSED.**

### Residual A+B CLOSED — `@as` cast builtin unhandled in self-emission (F-AS `50be26f5`)

A (missing fn-ptr typedefs — the 4 `_FN_`/`_FP_` GCC_FAIL dirs) and B (`fn_ptr_struct_field`
compiler SEGV) share ONE root cause: `@as` had no lowering branch. The flag read
`if ((ty.flags & @as(u32, 1)) != @as(u32, 0))` at `sf/src/c89_emit.zig:736` fell through →
uninitialized temp → non-deterministic `'P'`/`'N'` cname char per `getCTypeName` call → the
var-decl references a `_FN_*` name whose `_FP_*` typedef body was emitted under a different
name → gcc `unknown type name 'zT_…_FN_…'` (observed BOTH directions: P-body/N-ref in 5
fixtures, N-body/P-ref in `inferred_errorset_fnptr`); and the `@as(u32, fi)` addend at
`sf/src/type_registry.zig:851-852` produced NO emitted instruction → uninitialized index
into `self.xt_items` → READ SEGV in `typeRegistryIsAssignable` (3/3 rc=139 reproducible).
F-AS `50be26f5` (ONLY `semantic_analyzer.zig` + `lower.zig`, 8 insertions): the `@as`
name_id is interned in both lowerer/sema init, `semanticAnalyzerIsTypeValueCast`
recognizes it, and the lowerer cast branch emits `LirInst.int_cast` (`is_checked=0`) —
mirrors the F-ASSOC `@intToEnum` precedent. All 6 A-fixtures
(`emission_void_call_xmod` / `emission_void_call_control_xmod` / `func_ptr_return_type` /
`inferred_errorset_fnptr` / `quicksort` / `func_ptr_return`) now dump/gcc/link/run rc=0
under self-compiled zig1_5 with run output matching the reference. **This SUPERSEDES the
stale "expected gcc error (class 5, `void value not ignored`)" RED snapshot in
`emission_void_call_xmod/NOTES.md`** — the void fn-ptr statement call now emits `f();`
with no assignment, gcc `-c` rc=0 (historical snapshot retained, not rewritten).
`fn_ptr_struct_field` SEGV → dump rc=0 (no SEGV), run rc=0 (empty output, as reference).
**A+B CLOSED.**

### Residual C CLOSED — TCO self-recursion back-edge (F-C `dd83723f`)

The `tco_return_try` / `tco_defer` / `tco_factorial` self-emitted recursion ran with the
recursive call dropped (no back-edge → wrong counts). Root cause: the tagged-union `.tag`
field READ had no lowering case in `field_access` (`sf/src/lower.zig`) — the result temp
was reserved at `:2676` but never filled for `.tag` reads. F-C `dd83723f` (ONLY
`sf/src/lower.zig`, +8): a `.tag` case in the tagged_union branch (after the variant-name
loop + `.payload` case) interns "tag", looks up the base's name_id, emits
`load_field { field_id = TU_FIELD_TAG (=0), result = tid }`, returns tid — mirrors the
`.payload` sibling and the store-side tag pattern. Self-emitted emissions now contain the
TCO back-edge `goto z_bb_0;` inside the recursive fn. `tco_return_try` rc 139→0
(`count(10)=10\ncount(100000)=100000`, byte-equal ref); `tco_defer` 2 `D` byte-equal ref;
`tco_factorial` unchanged. **C CLOSED.**

### Corpus (329 dirs): `OK=319 / FAIL=0 / ICE=0 / CRASH=0 / green-guards=10` (319+0+0+0+10=329)

Full sweep (per-dir dump + per-file `gcc -c`, measured at HEAD `dd83723f`) classifies
OK=319, FAIL=0, ICE=0, CRASH=0; the 10 green-guards UNCHANGED (`eu_assign_incompat_payload`
/ `euvoid_val_catch` / `field_access_optional` / `var_declared_void` error[3000];
`parsergap_slice_expr_xmod` / `strictzig_brace_if_xmod` / `parsergap_selfblok_xmod` /
`parsergap_strict_comma_xmod` error[2000]; `self_embed_optional_cycle` error[24];
`emission_pal_xmod` error[20]). **No new FAIL/ICE/CRASH vs the 329-dir baseline.**

### 21-example matrix + 4 MD5 gates

21-example matrix **21/21** dump/gcc/link rc=0. 4 MD5 gates byte-identical (repo-root
CWD): gol `eed963e0640a073ed4eebb292f136e05` / lisp `c3c5847798e4553b2e34950e085bb6c6` /
json `089e4f046464ce3882aa2b2c4e585013` / mud `a1d0dd55aada9c3fd904ae33f54de32e` (F-AS
and F-C are byte-neutral for the 4 gates — no re-baseline).

### Runtime sweep (self-compiled zig1_5 vs reference) + self-compile

Full runtime sweep of 403 programs (repro top-level 53 + mi_matrix 329 + z98 21) with
`/tmp/zig1_5/zig1_5_clean` vs `/tmp/fx_subfolder/zig1`: **333 RUN_OK** (rc+output match
ref) + **2 non-deterministic-garbage dirs** (`voiddecl_payload_xmod`,
`emission_void_temp_enum_xmod` — output unstable by design, NOT a bug) + **10 DUMP_FAIL**
(= the 10 green-guards, both compilers identical) + **56 LINK_FAIL** (extern-fn-dependent;
reference fails to link identically — not a regression) + **2 RUN_TIMEOUT** (mud_server +
rogue_mud, both compilers; mud_server boots "MUD server listening on port 4000").
Expected-change fixtures ALL RUN_OK with output matching ref: `emission_void_call_xmod` /
`emission_void_call_control_xmod` / `func_ptr_return_type` (`15`) /
`inferred_errorset_fnptr` / `fn_ptr_struct_field` (was SEGV, rc=0) / `quicksort` (asc/desc
sorted) / `func_ptr_return` (`10+5=15`) / `tco_return_try` rc=0
(`count(100000)=100000`) / `tco_defer` (2 `D`) / `tco_factorial`. Self-compile:
`build_zig1_5.sh` → **40 `.c`, 0 `error[`, 0 PANIC**; rebuilt `zig1_5_clean` runs the
R-A/R-B/C fixtures green — `func_ptr_return_type` (`15`), `fn_ptr_struct_field` (rc=0),
`tco_return_try` (rc=0) — all matching reference.

### Milestone statement

Residual A+B (`@as` cast builtin: fn-ptr `_FP_`/`_FN_` cname mismatch + `typeRegistryIsAssignable`
SEGV) + residual C (TCO back-edge: tagged-union `.tag` field_read lowering) BOTH CLOSED.
4 MD5 gates byte-identical (no re-baseline). 21-example matrix 21/21. Corpus 329 dirs
`OK=319 / FAIL=0 / ICE=0 / CRASH=0 / GREEN=10`. No residual remains from the @as + TCO
self-emission plan.

## GATE — assoc-chain misparse + pending_scope nest-safety plan, FINAL sweep + reconciliation (2026-08-26)

Final gate sweep of the assoc-chain misparse + pending_scope plan
(docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md, AMENDMENT 4),
at HEAD `0b9c8ef6`, measured with `/tmp/fx_subfolder/zig1` (rebuilt at HEAD `0b9c8ef6`;
canonical std reinstalled at `/tmp/fx_subfolder/lib/`). Docs-only task — no `sf/src`,
fixture, or script change in this gate. **This is the plan-complete closeout: residual R-1
(self-emission operator-associativity gap) and residual I-1 (`pending_scope` nest-safety)
are BOTH CLOSED.**

### Residual R-1 CLOSED — self-emission operator-associativity gap (F-ASSOC `9574208d`)

The v48 hypothesis ("likely `OpInfo.right_assoc` mis-read") was **WRONG**. I-ASSOC traced the
reversal to a single self-emission fidelity gap: **`@intToEnum` lowering** (`sf/src/parser.zig:1896-1898`
`precFromInt(v: u8) Prec { return @intToEnum(Prec, v); }` — the only `@intToEnum` in sf/src) fell
through the cast block at `sf/src/lower.zig:3510-3542` (which had branches for `@intCast`/`@intToFloat`/
`@ptrCast`/`@intToPtr` but NO `@inttoEnum`) → emitted `return zT_1;` (declared temp, never assigned) →
`next_min = precFromInt(precToInt(info.prec) + 1)` fed uninitialized garbage into the precedence-climbing
RHS parse → every binary op behaved right-associative for the second operator's RHS. F-ASSOC `9574208d`
(ONLY `sf/src/lower.zig`, 9 insertions): new `inttoenum_name_id` registered in `lowererInit`
(lower.zig:443-444/:518) + new `inttoEnum` branch in the cast block (lower.zig:3542-3546) emitting a
`LirInst.int_cast` (`is_checked=0`, no range-check) → self-emitted `precFromInt` is now
`zT_1 = (zT_2B10107F_Prec)v;`. RED fixture `emission_assoc_chain_xmod` (40485a1d) now GREEN:
self-compiled `/tmp/zig1_5/zig1_5_clean` prints `3 5 0 6 24 55 321` (was `9 2\0 0 6 2\0 5\0 3\0\0`;
reference unchanged `3 5 0 6 24 55 321`). fibonacci `5\0`-class corruption gone. **R-1 CLOSED.**

### Residual I-1 CLOSED — `pending_scope` single-slot non-nest-safety (F-PENDSCOPE `0b9c8ef6`)

I-1 (B3b-review IMPORTANT: a capture inside a for-range END expr, `for (0..if (rt) |x| x else 0) |t|`,
reused + consumed the loop capture's single-slot pending scope, orphaning `t` to a `load_local` fallback)
is fixed by **AMENDMENT 4 option (c) — reorder the for-range lowering**: the capture-add block
(`maybeDisambiguateCapture` + `addLocalDecl` + `decl_local` for `t`) moved from BEFORE the end-expr
lower to AFTER it (`sf/src/lower.zig:4821-4823` → 4818-4823). This eliminates the pending-scope window
entirely (no stack, no fresh/reuse selector, no boundary low-watermark — the operator-ruled design over
the patchy LIFO-stack; see task-PENDSCOPE-report.md). I-1 repro now emits `total + t` DIRECT capture use
(no `zT = t` load_local); the capture-less end-expr shape (`for (0..if (rt) 1 else 0) |t|`) is fixed too.
for-slice captures (`:4891/:4892`) untouched. Byte-neutral for the 4 gates (gol/lisp/mud have no
for-loops; json uses only for-slice) — no re-baseline. **I-1 CLOSED.**

### Corpus (329 dirs): `OK=319 / FAIL=0 / ICE=0 / CRASH=0 / green-guards=10` (319+0+0+0+10=329)

Corpus grew 328→329 (+1: this plan's R fixture `emission_assoc_chain_xmod`, 40485a1d — classifies
**OK**, 4 `.c`, gcc clean). Full sweep (per-dir dump + per-file `gcc -c`) classifies OK=319, FAIL=0,
ICE=0, CRASH=0; the 10 green-guards UNCHANGED (`eu_assign_incompat_payload` / `euvoid_val_catch` /
`field_access_optional` / `var_declared_void` error[3000]; `parsergap_slice_expr_xmod` /
`strictzig_brace_if_xmod` / `parsergap_selfblok_xmod` / `parsergap_strict_comma_xmod` error[2000];
`self_embed_optional_cycle` error[24]; `emission_pal_xmod` error[20]). **No new FAIL/ICE/CRASH vs the
328-dir baseline.**

### 21-example matrix + 4 MD5 gates

21-example matrix **21/21** dump/gcc/link rc=0. 4 MD5 gates byte-identical (repo-root CWD): gol
`eed963e0640a073ed4eebb292f136e05` / lisp `c3c5847798e4553b2e34950e085bb6c6` / json
`089e4f046464ce3882aa2b2c4e585013` / mud `a1d0dd55aada9c3fd904ae33f54de32e`.

### Self-compile re-count + self-compiled binary

`/tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/gf_sc sf/src/main.zig` → **rc=0, 40
`.c`, 0 `error[`, 0 PANIC**. Self-compiled `/tmp/zig1_5/zig1_5_clean` (rebuilt via
`scripts/self_compile/build_zig1_5.sh`): R-ASSOC fixture `emission_assoc_chain_xmod` → dump/gcc/link/run
rc=0 prints **`3 5 0 6 24 55 321`** (matches reference — the self-emission fidelity gap is closed); real
std-importing program `emission_lower_crash_xmod` → dump/link/run rc=0 prints **3**.

### Milestone statement

Residual R-1 (self-emission operator-associativity gap) + residual I-1 (`pending_scope` nest-safety)
BOTH CLOSED. Self-compiled zig1_5 now parses left-assoc chains correctly and runs std-importing programs
rc=0. 4 MD5 gates byte-identical (no re-baseline). 21-example matrix 21/21. Corpus 329 dirs `OK=319 /
FAIL=0 / ICE=0 / CRASH=0 / GREEN=10`. No residual remains from the assoc-chain / pending_scope plan.

## GATE — labeled-block break + self-compiled lowering crash plan, FINAL sweep + reconciliation (2026-08-26)

Final gate sweep of the labeled-break + self-compile crash plan
(docs/superpowers/plans/2026-08-25-labeled-break-and-selfcompile-crash-plan.md, AMENDMENTs 1-3),
at HEAD `a7a207f7`, measured with `/tmp/fx_subfolder/zig1` (rebuilt at the last sf/src code
commit `a7a207f7`; canonical std reinstalled at `/tmp/fx_subfolder/lib/`). Docs-only task — no
`sf/src`, fixture, or script change in this gate. **This is the plan-complete closeout: the
labeled-block break (Phase A) and the self-compiled lowering crash (Phase B) are both CLOSED.**

### Phase A — labeled-block break (A2 F-LABELBREAK `ee092e3b` + docs `e18a424f`)

`break :blk` on a labeled block now resolves to a block-exit jump instead of being silently dropped.
Mechanism (A1a per AMENDMENT 1): `LoopInfo` gains `is_loop: u8`; `labeled_stmt` with a block body
creates an exit BB and pushes a breakable loop_stack entry (`is_loop=0`); `break` resolves the
labeled entry → jump to the block exit; `continue` skips `is_loop==0` entries in both the
unlabeled-innermost and the labeled scans. Fixture `emission_labeled_ctrl_xmod` prints
`3\n6\n10\n1` (the literal shape-A `blk: { var a = 1; break :blk; a = 2; }` now prints `1`).
`emission_orelse_labeled_xmod` + `emission_catch_labeled_xmod` still RUN correctly (prints `0` / `7`);
their emitted bytes gained a dead orphan `z_bb_N` block — the ACCEPTED AMENDMENT-1 dead-code
emission (runtime-identical, re-baseline-default, NOT a gate violation).

### Phase B — self-compiled lowering crash (B3a F2 `ea6882ac` + B3b F1 `a7a207f7`)

The self-compiled zig1_5 SEGV (F2, the crash) and the latent stale-sibling-capture (F1) are CLOSED
(AMENDMENT 2 split, operator-ruled B3a-then-B3b):
- **F2 (crash driver, c89_emit) — B3a F-EMITMAP `ea6882ac`:** the `fl_temps`/`fl_name_ids`
  temp→name map is now growable (was fixed `[128]`), both 128-caps dropped, and the name-dedup
  removed so each `decl_local` registers its OWN temp→name entry (capture shadowing). Self-compiled
  zig1_5 now runs the B1 fixture `emission_lower_crash_xmod` rc=0 (prints 3); reference rc=0.
  **F2 crash CLOSED.**
- **F1 (latent, lower) — B3b F-SCOPERES `a7a207f7`:** architectural lexical scope chain
  (parent-pointer scope nodes); one shared resolver walks the enclosing-scope chain innermost-first,
  replacing BOTH the LDS forward-scan max-scope loop (`lower.zig:2288-2317`) and the `findLocalTemp`
  backward-scan (`:1309-1317`); re-captured names resolve to the lexically-enclosing binding.
  **F1 CLOSED.**

### gol/lisp MD5 re-baseline (AMENDMENT 3, operator ruling A — AUTHORITATIVE)

The pin-mandated fl_temps dedup-removal necessarily changes emitted bytes for any function that
re-declares a name (gol `main` re-declares `var x` in two sibling while-loops; lisp re-uses capture
names). Per operator ruling A, **gol + lisp are RE-BASELINED** (runtime-identical verified: gol
glider grid + lisp REPL outputs diff-clean pristine-vs-candidate, both rc=0). New authoritative
hashes: gol `eed963e0640a073ed4eebb292f136e05` (old `4afb203f…`), lisp
`c3c5847798e4553b2e34950e085bb6c6` (old `5f886646…`). json `089e4f04…` + mud `a1d0dd55…`
UNCHANGED. The MD5 table in docs/sf/QUICK_REF.md carries the re-baseline note.

### Corpus (328 dirs): `OK=318 / FAIL=0 / ICE=0 / CRASH=0 / green-guards=10` (318+0+0+0+10=328)

Corpus grew 323→328 (+5): `emission_enum_switch_xmod` (b9bc3f1d) + `emission_enum_ext_xmod`
(f83912f6) + `emission_tu_switch_xmod` (ba3f0f70) + `emission_labeled_ctrl_xmod` (ac0b7e43) [prior
enum-switch/labeled fidelity-gap plan] + `emission_lower_crash_xmod` (22e0bc6f, this plan's B1).
Full sweep (per-dir dump + per-file `gcc -c`, `/tmp/fx_subfolder/zig1`) classifies **OK=318,
FAIL=0, ICE=0, CRASH=0**; the 10 green-guards unchanged (`eu_assign_incompat_payload` /
`euvoid_val_catch` / `field_access_optional` / `var_declared_void` / `parsergap_slice_expr_xmod`
error[3000]; `strictzig_brace_if_xmod` / `parsergap_selfblok_xmod` / `parsergap_strict_comma_xmod`
error[2000]; `self_embed_optional_cycle` error[24]; `emission_pal_xmod` error[20]). All 5 new dirs
classify OK. **No regression.**

### 21-example matrix + 4 MD5 gates

21-example matrix **21/21** dump/gcc/link rc=0. 4 MD5 gates byte-identical at the AMENDMENT-3
hashes (repo-root CWD): gol `eed963e0640a073ed4eebb292f136e05` / lisp
`c3c5847798e4553b2e34950e085bb6c6` / json `089e4f046464ce3882aa2b2c4e585013` / mud
`a1d0dd55aada9c3fd904ae33f54de32e`.

### Self-compile re-count + self-compiled binary

`bash scripts/self_compile/build_zig1_5.sh` → dump rc=0, 40 `.c`, in-script gcc -c clean;
independent re-count (`cd /tmp/zig1_5/gen && gcc -c *.c`) → **0 `: error:` lines, 40 files**.
Self-compiled `/tmp/zig1_5/zig1_5_clean` runs the B1 fixture `emission_lower_crash_xmod` rc=0
(prints 3, main_3DF5832C.c byte-identical to reference) AND the std-importing real program
`days_in_month` rc=0 with output BYTE-IDENTICAL to reference (all 12 month-day counts). `fibonacci`
runs rc=0 (output differs — see residual R-1).

### Deferred residuals (recorded, NOT fixed — do not regress-gate on these)

1. **Self-emission operator-associativity gap (R-1 — pre-existing, newly observable):** the
   self-compiled zig1_5 mis-parses SAME-PRECEDENCE left-associative operator chains — `a - b - c` →
   `a - (b - c)`, `a - b + c` → `a - (b + c)`, `a / b / c` → `a / (b / c)` — i.e. every binary op
   behaves right-associative for the second operator's RHS (self-emission defect; likely
   `OpInfo.right_assoc` mis-read, mechanism not fully traced — out of scope). Impact: any program
   compiled BY the self-compiled binary that uses a same-precedence chain mis-computes; concretely
   breaks `printInt`'s digit reversal (`std_io.zig:48` `out[pos] = tmp[len - 1 - k]`), so
   self-compiled-emitted binaries print wrong multi-digit integers via `printInt` (fibonacci prints
   `5\0` not `55`, rc=0). **Pre-existing, NOT this plan's regression:** the self-compile emission
   is byte-identical between pre-B3 HEAD `ee092e3b` and current `a7a207f7` (all 40 emitted modules
   diff-clean — A2/B3a/B3b did not change it); the defect was masked until the B3a crash fix let the
   self-compiled binary actually run std-importing programs. Same deferred class as the documented
   self-emission fidelity gap. Programs without same-precedence chains (B1 fixture `1 + 2`,
   `days_in_month` print-`{}` path) run byte-correct. Requires its own R/I/F plan.
2. **`pending_scope` single-slot non-nest-safety (I-1, B3b review IMPORTANT — documented, NOT
   fixed):** `pending_scope` in lower.zig is a single slot, not nest-safe. A capture inside a
   for-range END expr (`for (0..if (rt) |x| x else 0) |t|`) reuses + consumes the loop capture's
   pending scope, orphaning `t` from the scope chain — the resolver falls through to a raw
   `load_local`. Runtime stays CORRECT (emitted `zT = t; total + zT` vs control `total + t`); no
   gate/corpus fixture triggers it. A naive reorder of the pending-scope sites risks MD5
   temp-ordering — recorded for a follow-up F-task, NOT fixed.

### Milestone statement

Phase A (labeled-block break) + Phase B (self-compiled lowering crash) CLOSED. F2 crash CLOSED
(self-compiled zig1_5 runs the B1 fixture rc=0, prints 3). F1 scope-chain CLOSED. gol/lisp MD5
RE-BASELINED per AMENDMENT 3. Self-compile gcc-CLEAN (0 errors); the self-compiled binary RUNS
std-importing programs rc=0. 21-example matrix 21/21. Corpus 328 dirs `OK=318 / FAIL=0 / ICE=0 /
CRASH=0 / GREEN=10`. Residuals: R-1 self-emission associativity gap + I-1 `pending_scope`
nest-safety (both pre-existing / documented, NOT fixed).

## GATE — out-of-scope residual closeout, FINAL sweep + reconciliation (2026-08-25)

Final gate sweep of the out-of-scope residual closeout plan
(docs/superpowers/plans/2026-08-24-out-of-scope-residual-closeout-plan.md, AMENDMENTs 1-6),
at HEAD `ec306847`, measured with `/tmp/fx_subfolder/zig1` (rebuilt at the last sf/src code
commit `a9ea91f0`; canonical std reinstalled at `/tmp/fx_subfolder/lib/`). Docs-only task —
no `sf/src`, fixture, or script change in this gate. **This is the plan-complete closeout:
the entire FAIL=9 residual set is closed (FAIL → OK or → green-guard), FAIL 9→0, CRASH 1→0.**

### Corpus (323 dirs): `OK=313 / FAIL=0 / ICE=0 / CRASH=0 / green-guards=10` (313+0+0+0+10=323)

Corpus grew 322→323 (+1: the R-OPTFPTR fixture `emission_opt_fptr_wrap_xmod`). Full sweep
(per-dir dump + per-file `gcc -c`) classifies OK=313, FAIL=0, ICE=0, CRASH=0; the 10
green-guards = 5 auto-detected error[3000] rejections + 5 manual clean-rejections
(error[2000]/[24]/[20], 0 `.c`, no ICE/crash) reclassified by oracle rulings. **Every
fixture that changed classification this plan:**

| fixture | old | new | mechanism / SHA |
|---|---|---|---|
| `plat_stubs_missing_xmod` | CRASH | **OK** | ASan SEGV gone — F-PLATSTUBS `7d1b512d` (kind-gated recursion, Option B) |
| `emission_orelse_labeled_xmod` | FAIL | **OK** | F-LABELED `2cbf1fd3` (labeled_stmt orelse RHS no first-param leak) |
| `emission_catch_labeled_xmod` | FAIL | **OK** | F-LABELED `2cbf1fd3` (labeled_stmt catch RHS) |
| `emission_opt_fptr_wrap_xmod` | — | **OK** | new fixture (R `70af559c`) — F-OPTFPTR `53b9f1b6` (optional fn-ptr wrap) |
| `parsergap_specifier_xmod` | FAIL | **OK** | F-SPECIFIER `a9ea91f0` ({x} = lowercase hex, no prefix) |
| `field_store_drop` | FAIL | **OK** | fixture corrected `3ef2e8c8` (canonical `pal.zig` import + `std.io.printInt`; temp-0 sentinel superseded — Task 5.5 code fix MOOT) |
| `strictzig_brace_if_xmod` | FAIL | **GREEN** | brace-less `if;else` correct rejection (oracle); green-guard |
| `parsergap_selfblok_xmod` | FAIL | **GREEN** | brace-less `if;else` correct rejection (oracle); green-guard |
| `parsergap_strict_comma_xmod` | FAIL | **GREEN** | missing call-arg comma clean `error[2000]` (oracle); green-guard |
| `parsergap_slice_expr_xmod` | FAIL | **GREEN** | scalar-base slice clean reject `error[2000]`, no `error[3043]` ICE; green-guard |
| `self_embed_optional_cycle` | FAIL | **GREEN** | `error[24]` circular-type is CORRECT per AMENDMENT 6 (real Zig rejects `?X` value self-reference); green-guard |
| `emission_pal_xmod` | GREEN | **GREEN** | unchanged (pal green-guard, `error[20]`) |

Green-guard set (10) = `eu_assign_incompat_payload`, `euvoid_val_catch`,
`field_access_optional`, `var_declared_void` (error[3000]) + `parsergap_slice_expr_xmod`
(error[3000]) + `strictzig_brace_if_xmod`, `parsergap_selfblok_xmod`,
`parsergap_strict_comma_xmod` (error[2000]) + `self_embed_optional_cycle` (error[24]) +
`emission_pal_xmod` (error[20]).

### Oracle rulings (authoritative, recorded this plan)

- **`{x}` format specifier** = lowercase hex, no `0x` prefix (langref `0x{x}`). Z98
  `std.io.print("{x}\n", .{65})` prints **`41`** (F-SPECIFIER `a9ea91f0`; run-verified).
- **Brace-less `if (cond) stmt; else stmt;`** is correctly REJECTED (real-Zig grammar takes
  the `SEMICOLON` first → dangling `else`). The fix was migrating the 3 sf/src sites
  (type_resolver.zig:980-981/:987-990, diagnostics.zig:295-296) to braced form
  (F-BRACEMIG `22006588`); the fixtures are green-guards, not leniency.
- **`?*X` optional-POINTER** is the real-Zig self-reference pattern (pointer-sized, null=0;
  langref linked-list `prev: ?*Node, next: ?*Node`). Optional **VALUE** `?X` embeds by value →
  infinite-size → real Zig rejects. Z98's `error[24]` for `next: ?X` is therefore CORRECT
  (AMENDMENT 6, `ec306847`). Open question (not a blocker): whether Z98 supports `?*X`
  optional-pointer self-reference.

### json gate re-baseline (AMENDMENT 4, authoritative)

`d31e43b1…` → **`089e4f046464ce3882aa2b2c4e585013`** — the NULLWRAP fix (F-NULLWRAP
`a6fe169b`: optional-wrapped extern-call results emit `has_value = result != 0`) changes
json_parser's emitted C (same latent `fopen ?*File` NULL bug repaired). Runtime-identical on
every normal path (fopen succeeds → has_value=1 either way), repairs the NULL path (orelse
now fires). gol/lisp/mud byte-identical. **`089e4f04…` is the json hash for all future gates.**

### Deferred residuals (recorded, NOT fixed — do not regress-gate on these)

1. **Self-emission fidelity gap:** the self-compiled binary RUNS crash-free but misparses
   basic operators (`1 + 1`, `y = 5`, `x.len`, `y == 0`) → mass `error[2000]` self-dumping
   `sf/src/main.zig` (proven independent of NULLWRAP: parser.c/lexer.c/token.c/ast.c
   byte-identical pre/post). Requires its own dedicated R/I/F plan.
2. **`?*X` optional-pointer self-reference support:** open question, not a blocker.

### Milestone statement

Self-compile: **gcc-CLEAN AND LINK-green AND self-compiled binary RUNS crash-free** —
`bash scripts/self_compile/build_zig1_5.sh` → dump rc=0, 40 `.c`, in-script `gcc -c` clean
(0 `: error:` lines), BOTH `zig1_5_clean` + `zig1_5_asan` link rc=0 (c_exit linked via
`aa552f5d`), and the self-compiled binary runs on real input (crash-free rc=2 = the
misparse of the deferred self-emission gap, NOT a regression). `test_analyzer_bin` PASS
(rc=0, "Analyzer tests passed."). 21-example matrix **21/21** dump/gcc/link rc=0.
4 MD5 gates byte-identical: gol `4afb203f…`, lisp `5f886646…` (repo-root CWD), json
`089e4f04…`, mud `a1d0dd55…`.

## GATE — self-compile residual closeout R2/R1, final sweep + reconciliation (2026-08-24)

Final gate sweep of the self-compile closeout plan
(docs/superpowers/plans/2026-08-23-self-compile-closeout-r2r1-plan.md). Docs-only task — no
`sf/src` changes (all fixes landed in the plan's prior F tasks). All gates re-verified with
`/tmp/fx_subfolder/zig1` (rebuilt by F-ACOPY at HEAD `0af060d8`, canonical std reinstalled at
`/tmp/fx_subfolder/lib/`), under the operator ruling **AMENDMENT 5** (`935374d9`) — record
`plat_stubs_missing_xmod` truthfully, no new fix task:

- **4 residual fixes landed (all controller-verified this plan):**
  - **F-R2** (`143766e2`) — array-`.len` emits VOID instead of a bogus `unsigned int` value
    (the R2 `zT_<n> undeclared` ×6 class).
  - **F-ORELSEBLK** (`7a7f5928`) — orelse-block terminator fixed (the R2 orelse-block ×5
    class). Fix A (labeled-stmt orelse/catch RHS → block_terminated guard) did NOT close
    `emission_orelse_labeled_xmod` / `emission_catch_labeled_xmod` — recorded truthfully below.
  - **F-R1** (`a8ec24f7`) — R1 `Opt_10` incompatible-assign closed (×1).
  - **F-ACOPY** (`0af060d8`) — array-copy direct assign emits no bogus `dst = src` (the
    AMENDMENT-1 array-copy live RED; `emission_misc_xmod` residual now GREEN).
- **MAJOR MILESTONE — self-compile gcc-CLEAN (12→0):** `bash scripts/self_compile/build_zig1_5.sh`
  → dump rc=0, 40 `.c` emitted, in-script gcc -c clean (warnings only). Independent re-count:
  `cd /tmp/zig1_5/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
  -Wno-implicit-function-declaration -I /workspace/znineeight/sf/src/include -c *.c
  2>/tmp/emit_errs_final.txt` → gcc rc=0, **0 `: error:` lines, 40 files**. The 12 residuals
  (R2 array-`.len`→VOID ×6, orelse-block terminator ×5, R1 Opt_10 ×1) are all closed. The
  script's final LINK still fails `undefined reference to 'c_exit'` — the documented
  pre-existing out-of-scope issue (build_zig1_5.sh never links `sf/src/c_exit.c`; the gcc -c
  re-count gate is the authority for the milestone).
- **Corpus (322 dirs): `OK=307 / FAIL=9 / CRASH=1 / ICE=0 / green-guards=5`** (307+9+1+5=322).
  Corpus grew 310→322 (+10 A-ADD `emission_*_xmod` dirs + the 2 R-task dirs
  `emission_temp_index_drift_xmod` [F-R2] + `emission_opt10_assign_xmod` [F-R1]). **Documented
  FAIL=7 set unchanged** (byte-identical to the v45 baseline): `field_store_drop` (error[3048]) +
  `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` (error[2000]) +
  `parsergap_slice_expr_xmod` (error[2000]+[3000], clean-reject) + `parsergap_specifier_xmod`
  (error[3013]) + `parsergap_strict_comma_xmod` (error[2000]) + `strictzig_brace_if_xmod`
  (M1 hard-RED fixture, FAIL **by design**).
- **FAIL +2 (A-ADD live-RED labeled shapes — recorded truthfully, out of this plan's fix
  scope):** `emission_orelse_labeled_xmod` + `emission_catch_labeled_xmod` (the po1/pco1
  labeled-stmt classes) remain RED: gcc rc=1 `error: incompatible types when assigning to type
  'int' from type 'zT_…_Slice_zT_…_u'` at `zT_6 = prefix;` / `zT_4 = prefix;`. F-ORELSEBLK's
  Fix A did NOT close them — separate live bugs, documented as out-of-scope.
- **Green-guards = 5** = documented 4 (`eu_assign_incompat_payload` / `euvoid_val_catch` /
  `field_access_optional` / `var_declared_void`, all error[3000], 0 `.c`) + **`emission_pal_xmod`
  (error[20] reject = pal green-guard per AMENDMENT 1)**.
- **CRASH = 1 — `plat_stubs_missing_xmod` (PRE-EXISTING CRASH — mis-recorded previously, now
  corrected):** ASan SEGV in `resolveStmtTypes` (front_resolution.zig:131), 0 `.c`, dump rc=1.
  Bisected NOT caused by this plan (crashes at plan-start HEAD `b9256f2e`; last-known-good ~Aug 18
  `f4_fix_zig1`; suspected window = the silent-drop u32-widening `378c71fa`/`50ebbf82`,
  unverified). Every prior gate sweep (voiddecl/widthbits/residual/GATE-CLOSE) mis-recorded it as
  OK — the sweeps' "identical rc+stderr" comparisons masked a crash present in both reference and
  new compilers. **Operator ruling (AMENDMENT 5, `935374d9`): record truthfully, no new fix task.**
- **21-example matrix: 21/21 dump/gcc/link rc=0** (PASS=21, FAIL=0; 17 via main.zig + 4
  single-file func_ptr_return/mandelbrot/quicksort/sort_strings). Runs: json_parser parses
  test.json rc=0 from its dir; game_of_life renders the glider grid rc=0; rogue_mud boots
  "Welcome to Rogue MUD!" rc=0; mud_server "MUD server listening on port 4000" (timeout-gated
  server).
- **4 MD5 gates byte-identical (no re-baseline):** gol `4afb203f…` + lisp `5f886646…`
  (repo-root CWD) + json `d31e43b1…` + mud `a1d0dd55…` — all 4 match the v45 values.
- **test_analyzer_bin PASS** (build_test.sh battery "5 passed, 4 failed" — unchanged baseline).

## GATE — self-compile 194-error plan closeout, final sweep + reconciliation (2026-08-24)

Final gate sweep of the self-compile 194-error plan
(docs/superpowers/plans/2026-08-22-self-compile-194-closeout-plan.md). Docs-only task — no
`sf/src` changes (all fixes landed in the plan's prior F tasks). Self-compile re-count is
observational only (soft gate) — per-F fixture GREEN (gcc -c rc=0) was the hard gate;
runtime-identity governs:

- **5 fixes landed + AMENDMENTs 4/5 (all controller-verified this plan):**
  - **F-MIGRATE** (`1a06716b` + `df9c3017`) — bare `pal` → `pal_mod` migration (spec-compliant
    module alias) + undeclared-identifier diagnostic instead of silent VOID emission (`pal`
    class ×5 → 0).
  - **F-A** (`6b44d7a3`) — LirInst tag-emission emits the variant's declared tag constant
    (`incompatible types when assigning` class, 48 errors).
  - **F-B** (`6d4892bf` + `56a80136`) — hoisted-local disambiguation by type (name-keyed
    conflation; 108 errors).
  - **F-ORELSE** (`f8e3d914`) — orelse return/continue emits the orelse value, not the first
    param (6 errors).
  - **F-C** (`cb378f17`) — no-member + misc emission classes (8 + 5 errors).
  - AMENDMENTs 4 (`f5ab3bc3`, slice-argv main support) + 5 (`05ea274d`, canonical many-pointer
    main + fixture fix) — docs commits.
- **Self-compile residual state (194-plan FINAL):** NOT buildable. `timeout 120
  /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig` →
  **12 remaining gcc errors** = **R2 `zT_<n>` undeclared ×11 + R1 `Opt_10` assign ×1**
  (11+1=12) — the 194-plan's residual, deferred to the R2/R1 implementation plan →
  **FORWARD: docs/superpowers/plans/2026-08-23-self-compile-closeout-r2r1-plan.md.**
- **Corpus (310 dirs):** 303 → 310 (+7 emission-fixture dirs from this plan's R tasks:
  `emission_assign_xmod`, `emission_zT_undeclared_xmod`, `emission_request_member_xmod`,
  `emission_no_member_xmod`, `emission_pal_xmod`, `emission_misc_xmod`, `emission_orelse_xmod`).
- **4 MD5 gates:** json **`9720478c…` → `d31e43b19f752e40b9fd4b8885b13600` RE-BASELINED**
  (operator-approved during F-ORELSE — runtime-identical; the orelse fix repairs the
  semantically-broken null path); gol `4afb203f…` + lisp `5f886646…` (repo-root CWD) + mud
  `a1d0dd55…` unchanged.

## GATE — self-compile residual closeout, final sweep + reconciliation (2026-08-22)

Final gate sweep of the self-compile residual closeout plan
(docs/superpowers/plans/2026-08-20-self-compile-residual-closeout-plan.md, AMENDMENT 12
re-scope). Docs-only task — no `sf/src` changes (all fixes landed in the plan's prior F
tasks). All gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt at HEAD `b9256f2e`,
canonical std reinstalled at `/tmp/fx_subfolder/lib/`):

- **4 residual fixes landed (all controller-verified this plan):**
  - **F-C3-tighten** (`6534a65b`) — `local_decl_is_capture` flag gates the var-decl rename;
    `json_parser_workaround` stdout BYTE-IDENTICAL to base (md5 `dc22fa473650bd3dcdf4d8a1559a260b`);
    RV 21/21 runtime-identical.
  - **F-A2EXT** (`b019c671`) — Option A `ts_ref_set` owner-module type-storage defs/externs;
    self-compile `zG_` **9→0**.
  - **F-E2DOWN** (`9e00bec7`) — void-payload union-literal store guard (`lower.zig:3757`);
    self-compile `TokenValue has no member 'none'` **62→0**.
  - **F-SWITCH** (`b9256f2e`) — switch-on-plain-enum case values now correct (`case 0/1/2`;
    `enum_value_table` no longer resolves cross-module enum literals against a wrong, larger
    enum's field list). Fixture `emission_type_storage_extern_xmod` prints **3**
    (`case 0/1/2`), `emission_mangler_collision_xmod` prints **4** (NOTES corrected 3→4,
    doc error).
- **Self-compile residual state (AMENDMENT 12 — terminal gate re-scoped):** NOT buildable.
  `timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc
  sf/src/main.zig` → **194 remaining gcc errors** (`incompatible types when assigning` ×86
  enum-temp-typed-as-`unsigned int`, `zT_<n> undeclared` ×68, `request for member` ×22,
  `has no member` ×8, `pal` ×5, misc ×5) = **deferred NEW residual classes** (out of this
  plan's scope, recorded for a future plan). Scoped gates HOLD: `zG_` re-count **0**,
  `TokenValue.none` **0**, `json_parser_workaround` runtime-correct. This plan's success =
  the 4 scoped fixes landed + all gates run + docs reconciled.
- **Corpus (303 dirs): `OK=292 / FAIL=7 / ICE=0 / CRASH=0 / green-guards=4`** (292+7+4=303).
  Corpus grew 287→303 (+16 emission-fixture dirs from this plan's R tasks — all 16 classify
  **OK**; the plan's R fixtures `emission_type_storage_extern_xmod`, `emission_sibling_payload_scale_xmod`,
  `emission_void_temp_scale_xmod` + the AMENDMENT 7/8 variation fixtures + the Task D legacy
  fixtures `emission_mangler_collision_xmod` etc., all RED→OK). **FAIL=7 set unchanged**
  (byte-identical to the v43 baseline): `field_store_drop` (error[3048]) +
  `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` (error[2000]) +
  `parsergap_slice_expr_xmod` (error[2000]+[3000], clean-reject) + `parsergap_specifier_xmod`
  (error[3013]) + `parsergap_strict_comma_xmod` (error[2000]) + `strictzig_brace_if_xmod`
  (M1 hard-RED fixture, FAIL **by design**). Green-guards unchanged
  (`eu_assign_incompat_payload` / `euvoid_val_catch` / `field_access_optional` /
  `var_declared_void`). **No regression.**
- **21-example matrix: 21/21 dump/gcc/link rc=0** (PASS=21, FAIL=0; 17 via main.zig + 4
  single-file func_ptr_return/mandelbrot/quicksort/sort_strings). Runs: json_parser parses
  test.json rc=0 (CWD-sensitive — from its dir); game_of_life + mud_server + rogue_mud
  timeout-gated rc=124 with correct output (boots "Welcome to Rogue MUD!", "MUD server
  listening on port 4000") — counted PASS.
- **4 MD5 gates (2 RE-BASELINED, 2 UNCHANGED — runtime-priority override):**
  - gol **`9cf758d9…` → `4afb203fdde7a880ec6e7aed32543691`** RE-BASELINED — the documented
    baseline predated the F-attempt emission changes (this plan's F tasks); current HEAD
    emits `4afb203f…` (matches the AMENDMENT 12 controller-verified value). Runtime-identity
    justification: gol renders the glider grid rc=0 (md5 `40cfee96…` for 100 gen), corpus
    classification unchanged — per the operator's runtime-priority rule the runtime is the
    gate, not byte-identity.
  - lisp **`88dcb7f9…` → `5f886646b164a70c52bf042eb54bda78`** (repo-root CWD) RE-BASELINED —
    the gate-documented v43 value `88dcb7f9…` predates the F-attempt emission changes (the
    residual plan's Global Constraints carried an intermediate AMENDMENT-5 value `851c9ed3…`,
    now superseded); runtime-identity justification: REPL evaluates `(+ 1 2)`→3 /
    `(define x 10)` / `(+ x 5)`→15 / `(car (quote (5 6)))`→5 rc=0.
  - json `9720478c937409a29fe23ae0199821cf` — **UNCHANGED** (matches).
  - mud `a1d0dd55aada9c3fd904ae33f54de32e` — **UNCHANGED** (matches).
  Historical gol `9cf758d9…` / lisp `88dcb7f9…` refs below carry the `[→ 4afb203f…]` /
  `[→ 5f886646…]` forward-pointer.
- **test_analyzer_bin PASS** (build_test.sh battery "5 passed, 4 failed" — unchanged baseline).

## GATE — voiddecl-family plan closeout, final sweep + reconciliation (2026-08-20)

Final gate sweep of the voiddecl-family plan (docs/superpowers/plans/2026-08-18-voiddecl-family-plan.md,
GATE task lines 351-357, re-amended at :459/:481). Docs-only task — no `sf/src` changes (all fixes
landed in the plan's prior F tasks). All gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt
2026-08-20 at HEAD `df82d010`, canonical std reinstalled at `/tmp/fx_subfolder/lib/`):

- **VOID-decl family FULLY FIXED** — the 9 self-compile `error[3000] cannot-declare-variable-of-type-void`
  sites (main.zig:588, symbol_registrator:258/:357, lower.zig:4410/:5218/:5275/:5319/:5395/:5403):
  - **Root 1 — untyped module-level const/var collapse, FIXED by F1 (`27c71619`):** dedicated
    front-resolution pass (own file, I-FRONTRES design) resolving every module-level `var_decl` init
    type via the semantic-analyzer resolver, writing `sym.type_id` + `nameCachePut`, order-independent
    fixpoint; the leaking `main.zig:448-455` nameCachePut block + `resolveStmtTypes` moved INTO the pass.
  - **Root 2 — tagged-union `.tag` discriminator gap, FIXED by F2 (`660ff8e2`):**
    `resolveFieldAccess` tagged_union_type branch (`semantic_analyzer.zig:473-476`/`:570-591`) now
    returns `tp.tag_type` when `field_name_id == interner("tag")`.
  - Self-compile `error[3000]`: **9 → 0** (this gate: 0 non-9999 error[3000]).
- **F-ICE (`fd56da3b`) — slice_expr ICE `error[3043]` → 0 whole-tree:** 3-loci fix (zero-length array
  `type_resolver.zig:1002`; array-init element resolution `semantic_analyzer.zig:2120-2124`; sentinel
  collision `lower.zig:3907` `TYPE_UNDEFINED`→`TEMP_NONE`) **+ Fix A** (`semantic_analyzer.zig:2115-2141`
  array-init full child resolution) **+ Fix B** (`:841-852` FN3 fn-call arg resolution) — **ratified via
  AMENDMENT 5** (operator ruling 2026-08-19; Fix A/B exceeded the brief's 3 loci to satisfy the
  `error[3043]→0` gate). `parsergap_zeroarr_slice_xmod` RED→GREEN (runs rc=0, prints `0`).
- **F-REJECT (`838935ce`) — scalar-base slice clean reject:** sema `semanticAnalyzerResolveSliceExpr`
  base-is-sliceable check (array/slice/many-ptr allowed; scalar → proper diagnostic). R-ICE fixture
  `parsergap_slice_expr_xmod`: `rc=3 ICE` → `rc=2 error[2000]` (`cannot slice base type: expected array,
  slice, or many-pointer`), 0 `.c`, no `internal:` message.
- **R/I/F-PAYLOAD (`19d919bd`) — tagged-union `.payload` accessor (2-locus, AMENDMENT 6 ruling
  2026-08-20):** Locus 1 sema `semantic_analyzer.zig` tagged_union branch (after the `.tag` block,
  before the fields read — first non-void variant field type, mirroring the `:583-586` array→ptr
  conversion); Locus 2 lower `lower.zig:2450-2461` value path (load_field `TU_FIELD_PAYLOAD`, symmetric
  to the existing store mapping `:1018-1029`). `voiddecl_payload_xmod` RED→OK (compile gate: dump rc=0,
  gcc rc=0, runs rc=0; fixture uses `undefined` so runtime prints are NOT the gate).
- **Corpus (286 dirs): `OK=275 / FAIL=7 / ICE=0 / CRASH=0 / green-guards=4`** (275+7+4=286). Corpus grew
  277→286 (+9 dirs this plan: `parsergap_slice_expr_xmod`, `parsergap_zeroarr_slice_xmod`,
  `voiddecl_ifexpr_xmod` + `voiddecl_ifexpr_ctl_xmod` (R1 two-fixture), `voiddecl_switchexpr_xmod`,
  `voiddecl_u64cast_xmod`, `voiddecl_xmodtype_xmod`, `voiddecl_tagprobe_xmod`, `voiddecl_payload_xmod`).
  FAIL=7 = `field_store_drop` (error[3048]) + `self_embed_optional_cycle` (error[24]) +
  `parsergap_selfblok_xmod` (error[2000]) + `parsergap_specifier_xmod` (error[3013]) +
  `parsergap_strict_comma_xmod` (error[2000]) + `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL
  **by design**) + `parsergap_slice_expr_xmod` (**now clean-reject FAIL** — the F-REJECT ICE→FAIL flip,
  intended). Green-guards unchanged (`eu_assign_incompat_payload` / `euvoid_val_catch` /
  `field_access_optional` / `var_declared_void`). **No regression.**
- **21-example matrix: 21/21 dump/gcc/link rc=0** (PASS=21, FAIL=0; 17 via main.zig + 4 single-file
  func_ptr_return/mandelbrot/quicksort/sort_strings). Runs: json_parser parses test.json rc=0
  (CWD-sensitive — from its dir); game_of_life + mud_server + rogue_mud timeout-gated rc=124 with
  correct output — counted PASS.
- **4 MD5 gates:** gol `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22]
  (repo-root CWD — CWD-sensitive), mud `a1d0dd55aada9c3fd904ae33f54de32e` **byte-identical**; **json
  RE-BASELINED** `fc357296537347a0ef58af49b5a40081` → `9720478c937409a29fe23ae0199821cf` (AMENDMENT 3
  ruling 2026-08-19: the F1 front-resolution pass types json_parser's untyped module
  `var g_arena = std.arena.create(1048576)`, so 5 temp decls in emitted C change `unsigned int` →
  `Arena*`; runtime-identical — rc=0, byte-identical stdout — corpus classification unchanged).
  Historical json `fc357296…` refs carry the `[F1 re-baselined 2026-08-19 → 9720478c…]` forward-pointer.
- **test_analyzer_bin PASS** (build_test.sh battery "5 passed, 4 failed" — unchanged baseline).
- **Next blocker (recorded, NOT fixed):** PANIC `c89_emit.zig:5002` — `width_bits = @intCast(u8, size*8)`
  u8 overflow on a 40-byte tagged-union temp. Self-compile `timeout 120 zig1 --markers --dump-c89
  --output-dir /tmp/sc sf/src/main.zig` → rc=134 (`PANIC: integer cast overflow` at
  `/tmp/fx_subfolder/zig_runtime.h:154`; `STN:width_bits=zT_16/4528/4600` + `P1:t3254T94N5002` markers),
  with **error[3000]==0 AND error[3043]==0** (gate holds). Identical abort point to F-ICE/F-REJECT/
  F-PAYLOAD — the frontier of this plan, NOT fixed.
- **Documented latents (recorded, NOT fixed):** (1) **mixed-type-union `.payload` static-type dialect
  limitation** (AMENDMENT 6): `.payload`'s static type = first non-void variant field type
  (deterministic); on a MIXED-type union (`{a: u32, b: i64}`) the single static type is inherently
  arbitrary — a runtime active variant differing from the first non-void variant emits
  `.payload.<first>._0` reading the wrong width. 0 sites in sf/src. (2) **`.tag` read-load asymmetry**
  (AMENDMENT 6): F2 fixed `.tag` sema-only; bare `.tag` value-reads OUTSIDE a switch still no-load
  (pre-existing, disclosed in I-PAYLOAD §5, accepted by operator).

## GATE — widthbits-overflow plan closeout, final sweep + reconciliation (2026-08-20)

Final gate sweep of the widthbits-overflow plan (docs/superpowers/plans/2026-08-20-widthbits-overflow-plan.md,
STOP ruling 2026-08-20, AMENDMENT 2 `f3b0b916`). Docs-only task — no `sf/src` changes (the F1 fix landed in
the plan's prior task, commit `d5a966f7`). All gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt
2026-08-20 at HEAD `d5a966f7`, canonical std reinstalled at `/tmp/fx_subfolder/lib/`):

- **Width-bits mechanism (F1 `d5a966f7` — the LAST self-compile blocker, now FIXED):** the self-compile PANIC
  `c89_emit.zig:5002` was `width_bits = @intCast(u8, bty.size * @intCast(u32, 8))` — a u8 integer-cast
  overflow when emitting a `.int_const` for a >31-byte tagged-union temp (40 bytes: 40*8 = 320 > 255).
  **3-site class** (every `@intCast(u8, <size>*@intCast(u32, 8))` width computation): `c89_emit.zig:5002`
  (the `.int_const` PANIC locus), `c89_emit.zig:3190` (`emitSatBinary` — int-only operands, size ≤ 8,
  overflow-unreachable), and **`comptime_eval.zig:139` — the second LIVE site** (I-WIDTHBITS blast-radius
  correction; comptime-side `@intCast` fold reachable from a >31-byte non-int target). **Fix (Option B u32
  widening, per the STOP ruling):** `width_bits`/`wb` u8→u32 across the full enumerated surface — c89_emit.zig
  17 edit lines / 6 contiguous regions (`:3160/:3167/:3174/:3181` sat-helper params + their `@intCast(u8,…)`
  comparisons, `:3190/:4992/:5002` compute sites, `:3313/:3428` op-21/22 consumers, `:5020/:5028` `<64`
  guards; `:5024` keeps `sb: u8`), comptime_eval.zig 17 edit lines / 5 contiguous regions (`:16` field,
  `:56` `maxw`, the 8 literal constructions `:119/:128/:160/:173/:175/:177/:178/:196`, `:139` second live
  site, `:141/:144/:146/:183-188` consumers; `:203` pass-through untouched). **STOP-approved `>=`
  shift-guard hardening:** `comptime_eval.zig:141` and `:185` changed `wb == @intCast(u32, 64)` →
  `wb >= @intCast(u32, 64)` (eliminates synthetic-only u64 shift-by->63 UB on >31-byte non-int `@intCast`
  targets; behavior-identical for all int/char/bool targets). Shift-guard invariant preserved: every
  `1 << width_bits` is lexically inside the `is_signed != 0` block (`c89_emit.zig:5018`), tagged unions
  never set `is_signed`, so widths at any shift site stay ≤ 64 — widening introduces zero shift-UB.
  Whole-tree scan: **zero remaining `@intCast(u8, <size>*8)` width computations**; 61 `width_bits` hits
  confined to the 2 files; zero cross-file consumer of `ComptimeVal.width_bits`.
- **R1 fixture (`582bfc4e`, `widthbits_union_intconst_xmod`): RED→GREEN.** Pre-fix: `PANIC: integer cast
  overflow` (rc=134) at `zig_runtime.h:154` on the `.int_const` tag emission for a 40-byte tagged-union
  temp. Post-fix: dump rc=0, gcc rc=0, correct `.tag =` emission. Corpus 286→287 with the fixture counted;
  it now classifies **OK**.
- **Corpus (287 dirs): `OK=276 / FAIL=7 / ICE=0 / CRASH=0 / green-guards=4`** (276+7+4=287). Corpus grew
  286→287 (+1 dir this plan: the R1 fixture `widthbits_union_intconst_xmod`, RED→OK). **FAIL=7 set
  unchanged** (byte-identical to the v42 baseline): `field_store_drop` (error[3048]) +
  `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` (error[2000]) +
  `parsergap_slice_expr_xmod` (error[2000]+[3000], clean-reject) + `parsergap_specifier_xmod` (error[3013]) +
  `parsergap_strict_comma_xmod` (error[2000]) + `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL **by
  design**). Green-guards unchanged (`eu_assign_incompat_payload` / `euvoid_val_catch` /
  `field_access_optional` / `var_declared_void`). **No regression.**
- **21-example matrix: 21/21 dump/gcc rc=0** (PASS=21, FAIL=0; 17 via main.zig + 4 single-file
  func_ptr_return/mandelbrot/quicksort/sort_strings).
- **4 MD5 gates byte-identical** (all MATCH the v42 baselines, no re-baseline this plan): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22] (repo-root CWD —
  CWD-sensitive), json `9720478c937409a29fe23ae0199821cf`, mud `a1d0dd55aada9c3fd904ae33f54de32e`.
  Byte-identity by construction: emitted width-dependent output runs only for int temps ≤ 64 bits; no
  gate/corpus/example uses a >31-byte tagged-union `.int_const`.
- **test_analyzer_bin PASS** (build_test.sh battery "5 passed, 4 failed" — unchanged baseline).
- **MAJOR MILESTONE — self-compile FULLY GREEN:** `timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89
  --output-dir /tmp/sc sf/src/main.zig` → **rc=0, 40 `.c` emitted, zero `error[` non-9999, zero PANIC**. The
  widthbits fix was the **LAST self-compile blocker — next frontier blocker: NONE** (recorded explicitly;
  nothing invented). Informational only, NOT a blocker: the `--markers` emitted .c do not pass strict
  single-file `gcc -c` (`zT_68 undeclared`, `zF_..._main` arg-count mismatch) — a pre-existing `--markers`
  emission quirk unrelated to this widening; no gate requires gcc of self-compile output.

## GATE — self-compile silent-drop plan closeout (R-ladder + I-DROP + F1 u16→u32 sweep) (2026-08-19)

Final gate sweep of the self-compile silent-drop plan
(docs/superpowers/plans/2026-08-18-self-compile-silent-drop-plan.md). Docs-only task — no `sf/src`
changes (the F1 code fix landed in the plan's prior task, commits `378c71fa` + `50ebbf82`). All
gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt 2026-08-19 at HEAD `50ebbf82`, canonical
std reinstalled at `/tmp/fx_subfolder/lib/`):

- **R-ladder fixtures (6, all GREEN):** the plan's scale probes ruled out module-count / chain-depth /
  identifier-volume / tree-shape triggers — nothing below the 65,536-entry boundary trips:
  - `voiddecl_struct_xmod_r1` (`d1ad390b`) — sanity baseline: cross-module struct return at 2
    modules, GREEN.
  - `voiddecl_chain_r2` (`d3405b00`) — import-chain depth probe (N ∈ {5,10,20,40}), GREEN — depth
    alone does NOT trip.
  - `voiddecl_count_r3` (`f35e1835`) — sibling-module-count probe (N up to 39), GREEN — module count
    alone does NOT trip.
  - `voiddecl_volume_r4` (`3badc5cc`) — interned-identifier volume probe (up to 10k ids), GREEN —
    volume alone does NOT trip.
  - `voiddecl_nested_r5` (`44f7d210`) — nested import-tree probe (6 children × 4 grandchildren, 24
    leaf make()s), GREEN — tree shape does NOT trip.
  - `voiddecl_mimic_r6v2` (`7c61c462`) — self-hosting-shape mimic (39 modules), GREEN — shape+scale
    does NOT reconstruct the drop.
- **I-DROP mechanism (isolated — the true trigger, fixed by F1):** u32 span-start overflow in
  `astStoreAddExtraChildren` (`sf/src/ast.zig:424`). The module_root decl span is packed as
  `(start << 16) | count`; when `store.extra_children.len >= 65536` during self-compile, `start << 16`
  wraps to `start & 0xFFFF`, so every module parsed at/after the boundary decodes to the wrong
  (early) extra_children region and **silently registers 0 named types** (m1 = 0 symbols, m2-m4 =
  4/18/10 stray garbage `var_decl`s; `RN:` absent for all of m1-m4). Every cross-module ref to their
  types falls back to TYPE_VOID (`resolveFnSignatures`, type_resolver.zig:1214) → the 213×
  `error[3000]`. The trigger is **aggregate extra_children length**, not module count (sf/src modules
  are large). Isolated by instrumentation (task-I-DROP-report); NOT a registration skip, NOT OOM, NOT
  cyclic re-entrancy (CYE=0/CYF=0).
- **Two boundary repro fixtures (both now GREEN):**
  - `voiddecl_boundary_xmod` (`069b6b35`) — the silent-drop RED form: N=7 × 10k-const modules; the
    bare-`std` module (imported first, parsed last under the LIFO import queue) is silently dropped →
    dump/gcc/run rc=0 but EMPTY stdout (expected `1 7`). Post-F1 GREEN: run prints `1 7`.
  - `voiddecl_boundary_xmod_err` (`b4993838`) — the error[3000] RED form: same shape with m1 imported
    first (parsed last, start wrapped 65539→3) → `rc=2`, `error[3000]: cannot declare variable of type
    void` at `main.zig:10:4`, 0 `.c` emitted. Post-F1 GREEN: run prints `1`.
- **F1 whole-class sweep (the fix):** `AstNode.payload` u32→u64, encoding `(start << 32) | count`
  (decode `>> 32` / `& 0xFFFFFFFF`); every `*_start: u16` index into the two unbounded arrays
  (`ast.extra_children`, `type_registry.xt_items`/`xn_items`) widened to u32 — `*_count` stays u16.
  Commits `378c71fa` (type_registry path) + `50ebbf82` (extra_children path). **Commit order reversed
  from the plan staging** (type_registry landed first) — operator accepted.
- **New self-compile status:** `error[3000]` **213x → 9**; modules 1-4 now register cleanly
  (`RN:m1`/`RN:m2`/`RN:m3`/`RN:m4` markers present, `RN:m5n38` boundary control present). The 9
  residual `error[3000]` are the **same pre-existing VOID-decl family, newly reached** — recorded,
  **NOT fixed** (all `cannot declare variable of type void`). **Next blocker = the VOID-decl family
  (9 sites).**
- **Corpus (277 dirs): `OK=267 / FAIL=6 / ICE=0 / CRASH=0 / green-guards=4`** (267+6+4=277). Corpus
  grew 266→277: +3 signed wrap/sat emission probes (`sat_i64_mul` / `sat_signed_battery` /
  `wrap_signed_battery`, commit `13991817`, landed post-v40-gate) + the 6 R-ladder fixtures + the 2
  boundary repros — all 11 new dirs **OK**. FAIL=6 **unchanged** (byte-identical to the v40
  baseline): `field_store_drop` (error[3048]) + `self_embed_optional_cycle` (error[24]) +
  `parsergap_selfblok_xmod` (error[2000]) + `parsergap_specifier_xmod` (error[3013]) +
  `parsergap_strict_comma_xmod` (error[2000]) + `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL
  **by design**). Green-guards unchanged (`eu_assign_incompat_payload` / `euvoid_val_catch` /
  `field_access_optional` / `var_declared_void`). **No regression.**
- **21-example matrix: 21/21 dump/gcc/link rc=0** (PASS=21, FAIL=0). Runs: json_parser parses
  test.json rc=0 (CWD-sensitive — run from its dir); game_of_life prints the correct glider grid then
  loops on the missing `cls` — timeout-gated rc=124, counted PASS; mud_server rc=124 (timeout-gated
  server); rogue_mud boots + exits on `q` rc=0.
- **4 MD5 gates byte-identical** (all MATCH the v40 baselines, no re-baseline this plan): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22] (repo-root CWD —
  CWD-sensitive), json `fc357296537347a0ef58af49b5a40081` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **test_analyzer_bin PASS** (build_test.sh battery "5 passed, 4 failed" — unchanged baseline).
- **Trigger isolation (recorded, NOT fixed):** the silent module 1-4 drop was the u16 span-start
  overflow (I-DROP mechanism above) — FIXED by F1. The newly-reached 9 `error[3000]` VOID-decl sites
  (main.zig:588, symbol_registrator:258/:357, lower.zig:4410/:5218/:5275/:5319/:5395/:5403) are the
  next genuine blocker — the same pre-existing VOID-decl family as the `var_declared_void`
  green-guard, **recorded, NOT fixed** (see the QUICK_REF baseline line).

## GATE — self-compile-gaps plan closeout (wrap/sat operators + multi-line string + switch-prong) (2026-08-18)

Final gate sweep of the self-compile-gaps plan (docs/superpowers/plans/2026-08-18-self-compile-gaps-plan.md).
Docs-only task — no `sf/src` changes. All gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt
2026-08-18, canonical std reinstalled at `/tmp/fx_subfolder/lib/`):

- **F tasks included in this closeout:**
  - F2 (`fdcf3b54`): multi-line string literal migration to escaped `\n` (c89_emit.zig:1881) —
    self-compile construct passes.
  - F1 (`9cb844b4` + `541092b4` + `10ba14e9`): full wrapping/saturating operator family
    (`+% -% *%` + prefix `-%` + `+%= -%= *%=` then `+| -| *| <<|` + `+|= -|= *|= <<|=`),
    signed+unsigned — `parsergap_wrap_arith_xmod` RED→OK, `hash.zig:18 *%` self-compile passes.
  - F3 (`3079df02`): value-less `return` in switch prongs (return-only per STOP ruling) —
    `parsergap_switch_comma_xmod` RED→OK, `lexer.zig` value-less-return site passes.
- **Corpus (266 dirs): `OK=256 / FAIL=6 / ICE=0 / CRASH=0 / green-guards=4`** (256+6+4=266). The
  FAIL=6 set is **unchanged** (byte-identical to the v39 baseline): `field_store_drop` (error[3048]) +
  `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` (error[2000]) +
  `parsergap_specifier_xmod` (error[3013]) + `parsergap_strict_comma_xmod` (error[2000]) +
  `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL **by design**). Green-guards unchanged
  (`eu_assign_incompat_payload` / `euvoid_val_catch` / `field_access_optional` / `var_declared_void`).
  Corpus grew 264→266 (this plan's R1 `parsergap_wrap_arith_xmod` + R3
  `parsergap_switch_comma_xmod`), **both RED→OK** — OK=254→256, FAIL=6 unmoved (R1/R3 were never
  part of the FAIL=6 baseline set). **No regression.**
- **21-example matrix: 21/21 dump/gcc/link rc=0.** Runs spot-checked: days_in_month rc=0 (all 12
  month-day counts); game_of_life 100 generations rc=0; rogue_mud boots "Welcome to Rogue MUD!" +
  exits on `q` rc=0; json_parser parses test.json rc=0 (CWD-sensitive — run from its dir).
- **4 MD5 gates byte-identical** (all MATCH the v39 baselines, no re-baseline this task): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22] (repo-root CWD —
  CWD-sensitive), json `fc357296537347a0ef58af49b5a40081` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **test_analyzer_bin PASS** (build_test.sh battery "5 passed, 4 failed" — unchanged baseline).
- **Self-compile re-check:** `zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig`
  (timeout 120, rc=2): all 3 plan constructs pass — 0 `util/hash.zig:18` `*%` hits, 0
  `c89_emit.zig:1881` hits, 0 `lexer.zig` value-less-return hits. **Remaining pre-existing blocker:**
  **210 `error[3000] cannot-declare-variable-of-type-void` sema errors** (the VOID-decl family —
  same class as the `var_declared_void` green-guard, but real gap in self-compile sources). The F3
  report's suspicion of a `lexer.zig slice_expr` error[3043] ICE is **NOT reproduced** — the filtered
  self-compile stderr shows 210× error[3000] and ZERO ICE-class errors. Recorded, NOT fixed.

## GATE — parser-gaps followup plan closeout + F6 json historical pointer (2026-08-18)

Final gate sweep of the parser-gaps followup plan (docs/superpowers/plans/2026-08-17-parser-gaps-followup-plan.md).
Docs-only task — no `sf/src` changes. All gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt
2026-08-18, canonical std reinstalled at `/tmp/fx_subfolder/lib/`):

- **F tasks included in this closeout:**
  - F1-followup (`1b3a1b5c`): tuple-literal→array init element-wise lowering (parsergap_many_ptr_xmod
    dependency, operator ruling 2026-08-18).
  - F1 (`84470c61`): many_ptr type-alias registration (parsergap_many_ptr_xmod RED→OK).
  - F2 (`7bb775ad`): restore strict fn-call arg comma/close diagnostics (parsergap_strict_comma_xmod).
  - F3 (`9963858f`): invalid print specifier is a compile error, error[3013] (parsergap_specifier_xmod).
  - F4 (`e8321314`): Site B — innermost-local resolution for shadowed vars (parsergap_shadow_local_xmod).
  - F5: **dropped** — became the strict-zig migration plan (M0-M4 + M8, commits `54e7e8b7`..`29132823`),
    all committed separately.
  - F6 (this task): EXPECTED_FAIL historical json `066c9997…` entries at :169/:186 get the
    `→ fc357296…` forward-pointer (see the two F-CLOSEOUT sections below).
- **Corpus (264 dirs): `OK=254 / FAIL=6 / ICE=0 / CRASH=0 / green-guards=4`** — byte-identical to the
  strict-zig M3 sweep (254+6+4=264). Real FAIL=6 = `field_store_drop` (error[3048]) +
  `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` (error[2000]) +
  `parsergap_specifier_xmod` (error[3013]) + `parsergap_strict_comma_xmod` (error[2000]) +
  `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL **by design**). Green-guards unchanged
  (`eu_assign_incompat_payload` / `euvoid_val_catch` / `field_access_optional` / `var_declared_void`).
  Corpus grew 258→264 (5 followup parsergap dirs + the M1 fixture) at the M3 sweep; no movement this task.
- **21-example matrix: 21/21 dump/gcc/link rc=0.** Runs: 19 exit rc=0 (incl. days_in_month all 12
  month-day counts rc=0, Feb 2024 = 29; json_parser parses test.json rc=0, object fields
  comma-separated, no trailing comma — B-F2 runtime-identity; game_of_life 100 generations rc=0);
  mud_server rc=124 ("MUD server listening on port 4000", timeout-gated server); rogue_mud boots
  "Welcome to Rogue MUD!" + exits on `q` rc=0.
- **4 MD5 gates byte-identical** (all MATCH the current baselines, no re-baseline this task): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22] (repo-root CWD —
  CWD-sensitive), json `fc357296537347a0ef58af49b5a40081` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **test_analyzer_bin PASS** ("Analyzer tests passed.", rc=0).
- **Self-compile re-check:** `zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig`
  (timeout 120) passes the M2 blockers (type_resolver.zig:981/:987-990 — 0 hits) AND the M4-fix 4th
  site (`c89_emit.zig:410-412` — 0 hits). **Remaining pre-existing blockers (ALL recorded, ALL out of
  scope, NOT fixed):** (1) `util/hash.zig:18:21` — `*%` saturating-mul, error[2000]; (2)
  `c89_emit.zig:1881-1882` — unterminated string literal, error[0] (+cascades 1939); (3)
  `lexer.zig:236-239` — error[2000] expected-expression/unexpected-token report sites.

## GATE — M4-fix: 4th ;-before-else site + verification expansion + docs correction (2026-08-18)

M4 final review found the plan's "exactly 3 sites" premise was incomplete: a 4th `;`-before-`else`
site existed at `sf/src/c89_emit.zig:410-412` in the self-compile closure (missed because M2/M3
verification grepped only the first error). Per operator ruling (2026-08-18), this gate fixes that
site, expands the self-compile verification to a tree-wide scan, and corrects the docs' false
"sole next blocker" claim. All gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt 2026-08-18
at HEAD `31d55084` + M4-fix, canonical std reinstalled at `/tmp/fx_subfolder/lib/`):

- **Fix (this gate):** `sf/src/c89_emit.zig:410-412` migrated to braced form (same mechanical
  change as M2) — the `nameManglerMangle` kind-char chain:
  `if (kind == 0) { ... } else if (kind == 1) { ... } else if (kind == 2) { ... }`.
  This is the 4th and last `;`-before-`else` site in the self-compile closure; the fix is
  **byte-identical** (measured, not assumed).
- **Tree-wide scan (verification expansion):** after the fix, the full self-compile
  (`zig1 --markers --dump-c89 --output-dir /tmp/scX sf/src/main.zig`, timeout 120) scans ALL
  non-9999 errors — **ZERO `';' not allowed before 'else'` errors remain anywhere in the closure.**
  Source-tree scan (awk, `;`-ending line followed by `else` on the next line):
  `for f in $(find sf/src -name '*.zig'); do awk 'prev ~ /;[ \t]*$/ && $0 ~ /^[ \t]*else\b/ { print FILENAME ":" FNR ": " prev " ||| " $0 } { prev = $0 }' "$f"; done`
  → **0 hits**. (The only `; else` text left in sf/src is the emitted-C string literal
  `"; else goto z_bb_"` at `c89_emit.zig:3833` — not a Z98 construct.)
- **4 MD5 gates byte-identical** (baselines unchanged): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22] (repo-root CWD), json
  `fc357296537347a0ef58af49b5a40081` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **Corpus spot-check (byte-identical, expect no movement):** `strictzig_brace_if_xmod` FAIL by
  design (M8's diagnostic fires on the fixture's invalid form — the M1 hard-RED fixture),
  `parsergap_selfblok_xmod` FAIL (`error[2000]`), `field_store_drop` FAIL (`error[3048]`) — no
  movement vs v37.
- **Self-compile re-check — TRUE remaining blockers (ALL pre-existing, ALL out of scope, recorded
  only), in order of appearance:**
  1. `sf/src/util/hash.zig:18:21` — `*%` saturating-mul (`hash = hash *% 16777619;`),
     `error[2000]` expected expression / unexpected token.
  2. `sf/src/c89_emit.zig:1881-1882` — unterminated string literal on a line-split string,
     `error[0]` (cascades at 1939).
  3. `sf/src/lexer.zig:236-239` — `error[2000]` expected expression / unexpected token report
     sites.
  The v37 narrative ("next gap = hash.zig:18") implied a sole blocker and was FALSE — the filtered
  stderr also showed c89_emit.zig:411-412 (now fixed), c89_emit.zig:1881-1882, and lexer.zig:236-239.
  Corrected here and in QUICK_REF.

## GATE — strict-zig-if migration plan closeout, gate sweep + reconciliation (2026-08-18)

Final gate sweep of the strict-zig-if migration plan (M1 fixture + M2 migration). All gates
re-verified with `/tmp/fx_subfolder/zig1` (rebuilt 2026-08-18 at HEAD `1585adf2`, canonical std
reinstalled at `/tmp/fx_subfolder/lib/`):

- **M2 fixes landed (this plan):** the 3 invalid `;`-before-`else` if/else sites migrated to
  braced form (`sf/src/type_resolver.zig:980-981` + `:987-990`, `sf/src/diagnostics.zig:295-296`)
  — commit `1585adf2`. No `sf/src` changes in this gate task (docs-only).
- **Corpus (264 dirs): `OK=254 / FAIL=6 / ICE=0 / CRASH=0 / green-guards=4`.** 254+6+4=264.
  Real FAIL=6 = `field_store_drop` (bare `@import("pal")`, `error[3048]`),
  `self_embed_optional_cycle` (C89 fundamental, `error[24]` circular type),
  `parsergap_selfblok_xmod` (`error[2000]`), `parsergap_specifier_xmod` (`error[3013]`),
  `parsergap_strict_comma_xmod` (`error[2000]`) — the plan's expected FAIL=5, UNCHANGED — plus
  `strictzig_brace_if_xmod` (the M1 hard-RED fixture, `error[2000]`, FAIL **by design** — it ships
  the invalid `;`-before-`else` form). Green-guards unchanged (`eu_assign_incompat_payload` /
  `euvoid_val_catch` / `field_access_optional` / `var_declared_void`, all `error[3000]`, 0 `.c`).
  Delta vs plan expectation (263 dirs, FAIL=5): actual = 264 dirs — the +1 is the M1 fixture
  `strictzig_brace_if_xmod` landing in the corpus, counted as FAIL per its gate role (264 =
  258 at the parser-gaps closeout + 5 followup parsergap dirs [many_ptr / selfblok / shadow_local
  / specifier / strict_comma] + 1 M1 fixture). OK=254 unchanged (no fixture flipped; migration
  is byte-identical). ICE=0, CRASH=0.
- **21-example matrix: 21/21 dump/gcc/link rc=0.** Runs: 19 exit rc=0 (incl. json_parser +
  json_parser_workaround rc=0 from their dirs with test.json present, game_of_life 100 generations
  rc=0); mud_server rc=124 ("MUD server listening on port 4000", timeout-gated server); rogue_mud
  boots "Welcome to Rogue MUD!" + exits on `q` rc=0.
- **4 MD5 gates byte-identical** (all MATCH the plan/M2 baselines, measured with the rebuilt
  compiler): gol `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22]
  (repo-root CWD — CWD-sensitive), json `fc357296537347a0ef58af49b5a40081` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud
  `a1d0dd55aada9c3fd904ae33f54de32e`. Byte-identity proof: the migration emits byte-identical C.
- **test_analyzer_bin PASS** ("Analyzer tests passed.", rc=0).
- **Self-compile re-check:** `zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig`
  (timeout 120) now passes the M2 blocker — **0 hits for `type_resolver.zig:98x`** in filtered
  stderr (the braced migration at :981/:987-990 compiles). It proceeds into type resolution and
  hits the next pre-existing gap at `sf/src/util/hash.zig:18:21` (`error[2000]` expected expression /
  unexpected token — the `*%` saturating-mul construct `hash = hash *% 16777619;`). **Recorded,
  out of scope — not fixed** (next self-compile blocker; see QUICK_REF).

## GATE — parser-gaps plan closeout, final gate sweep + reconciliation (2026-08-17)

Final gate sweep of the parser-gaps plan (Workstream A + B). All gates re-verified with
`/tmp/fx_subfolder/zig1` (HEAD `830c5691` + A-F1..A-F3 + B-F1..B-F2), canonical std installed at
`/tmp/fx_subfolder/lib/`:

- **Fixes landed (this plan):** A-F1 (`7209f5b4`, discard capture `|_|` in if-stmt/if-expr),
  A-F2 (`891f06fc`, bare array type as const value), A-F3 (`ef425586`, trailing comma in fn-call
  args), B-F1 (`4f1200de`, specifier-driven print dispatch `{}`/`{d}`/`{c}`), B-F2 (`830c5691`,
  for-index capture disambiguation).
- **Corpus (258 dirs): `OK=252 / FAIL=2 / ICE=0 / CRASH=0 / green-guards=4`.** FAIL=2 =
  `field_store_drop` (bare `@import("pal")`, `error[3048]`) + `self_embed_optional_cycle` (C89
  fundamental, `error[24]` circular type); green-guards = `eu_assign_incompat_payload` /
  `euvoid_val_catch` / `field_access_optional` / `var_declared_void`. Corpus grew 252→258 since the
  F-CLOSEOUT baseline (the 3 parsergap fixtures + `parsergap_value_if_xmod` +
  `parsergap_value_if_xmod_cross` + `pathnorm_dup_xmod`), all 6 new dirs OK. The 3 parsergap repros
  (`parsergap_discard_if_xmod` / `parsergap_array_type_xmod` / `parsergap_trailing_comma_xmod`) —
  previously deferred FAIL — are now **OK** (A-F1/A-F2/A-F3). Measured: **OK=252 / FAIL=2 / ICE=0 /
  CRASH=0 / green-guards=4 over 258 dirs** (252+2+4=258). (Note: the plan's expected corpus size was
  255 dirs; the actual corpus is 258 — the +3 is `parsergap_value_if_xmod`,
  `parsergap_value_if_xmod_cross`, `pathnorm_dup_xmod` landing after the plan was written. Real
  numbers recorded here.)
- **21-example matrix: 21/21 dump/gcc/link rc=0.** mud_server run rc=124 ("MUD server listening on
  port 4000", timeout-gated); rogue_mud run rc=0 (boots "Welcome to Rogue MUD!", exits on `q`).
- **4 MD5 gates byte-identical:** gol `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp
  `524d2872daefb2677c8ddc1ac8f34cf5`, json `fc357296537347a0ef58af49b5a40081` (B-F2 re-baseline)
  [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **test_analyzer_bin PASS** (build_test.sh "5 passed, 4 failed" — unchanged baseline).
- **Self-compile re-check:** `zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig`
  (timeout 120) now progresses PAST the three pre-fix blockers (cinclude.zig:23 / lower.zig:2283 /
  main.zig:759 — all 0 `error[` hits at those sites) into type resolution (type_resolver markers
  `RN:`/`CLS:`/`T01` stream), where a NEW pre-existing gap blocks at `type_resolver.zig:981`
  (`error[2000]` expected expression / unexpected token in the const-array-size evaluator
  `evalConstU32Full` sub/div/mod arms, plus lexer.zig:236-239 report sites). Out of scope for this
  plan — recorded, not fixed.
- **days_in_month + json_parser runtime correct per B fixes:** days_in_month prints all 12 month-day
  counts (Feb 2024 = 29, leap year) rc=0; json_parser parses `test.json` rc=0 with object fields
  comma-separated and no trailing comma (B-F2 runtime-identity).

## B-F2 — for-index capture disambiguation, json MD5 re-baseline (2026-08-17)

Compiler fix task of the parser-gaps plan (Workstream B). All gates re-verified with
`/tmp/fx_subfolder/zig1` (HEAD `4f1200de` + B-F2 Site A fix), canonical std installed at
`/tmp/fx_subfolder/lib/`:

- **Fix:** for-loop INDEX capture is now name-disambiguated like the element capture
  (`sf/src/lower.zig` — index capture runs through `maybeDisambiguateCapture`, TYPE_USIZE). The
  `.Object` loop's `i` in json_parser resolves to its own counter (disambiguated `i_2`), not the
  stale `.Array` counter. Site A only; Site B (LDS innermost-scan) NOT implemented.
- **json MD5 RE-BASELINED:** `066c99974f6052317636854dc4c2a2d5` → `fc357296537347a0ef58af49b5a40081`
  [→ `9720478c…` F1 re-baselined 2026-08-19, see the v42 GATE entry].
  Runtime-identity proof (AMENDMENT B): fixed binary parses `test.json` rc=0, object fields
  comma-separated (`"status": "alpha",` / `"bugs": null`), NO trailing comma after last field —
  pre-fix had no object-field commas + trailing `,` after `"meta"`. Array elements unchanged.
- **gol/lisp/mud byte-identical** (no for-index collisions): gol `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22],
  lisp `524d2872daefb2677c8ddc1ac8f34cf5`, mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **21-example matrix: 21/21 dump/gcc rc=0** (re-verified 2026-08-17 with the fixed compiler —
  17 via main.zig + 4 single-file entries: func_ptr_return/mandelbrot/quicksort/sort_strings).
  No repro dirs touched; fix is lowerer-internal — json_parser is the only example with
  `for ... |item, i|` index captures.

## F-CLOSEOUT — std-lib fallback demotion (2026-08-14)

Final gate sweep of the std-lib fallback-demotion plan (Task F fallback demotion, Option A root-cause
fix). All gates re-verified with `/tmp/fx_subfolder/zig1` (HEAD `5c1e17e4`), canonical std installed
at `/tmp/fx_subfolder/lib/`:

- **Root-cause fix (4 sites):** the bare name-cache key (`name_id`) collides with module-0's scoped
  key (`(0<<32)|name_id == name_id`), so any un-scoped `nameCacheGet` silently resolved module-0-first.
  Fixed across **4 sites** — `type_resolver.zig` (`resolveTypeExprFull` `ident_expr` arm reordered
  current-module-first), `symbol_registrator.zig` (`registerDecl` ident_expr alias branch scoped to
  the declaring module), `const_alias_prepass.zig` (Phase-2 seed scoped to the alias declaring
  module), and `semantic_analyzer.zig` (`semanticAnalyzerResolveFnCall` return-type fallback now
  routes through `resolveTypeExprFull`; dead manual scan removed). The bare-key fallback is now
  **primitive + module-0 named type** (module-0 named types share the bare key — that IS the
  collision).
- **4 `r_fallback_*` repros added** (Task R): `r_fallback_fnret` (fn-return-type bare `Foo` in mod_b
  vs module-0's `Foo`, RED→GREEN), `r_fallback_constalias` (`pub const Bar = Foo` ident_expr alias,
  RED→GREEN), `r_fallback_constalias_prepass` (const-alias via prepass, RED→GREEN), and
  `r_fallback_fnret_ctl` (control — no module-0 collision, stays GREEN). All 4 classify OK.
- **Corpus (252 dirs): `OK=246 / FAIL=2 / ICE=0 / CRASH=0 / green-guards=4`.** FAIL=2 =
  `field_store_drop` (bare `@import("pal")`, `error[3048]`) + `self_embed_optional_cycle` (C89
  fundamental, `error[24]` circular type); green-guards = `eu_assign_incompat_payload` /
  `euvoid_val_catch` / `field_access_optional` / `var_declared_void`. Corpus grew 248→252 (the 4
  `r_fallback_*` repros).
- **21-example matrix: 21/21 dump/gcc/link rc=0.** mud_server run rc=124 ("MUD server listening on
  port 4000", timeout-gated); rogue_mud run rc=0 (boots "Welcome to Rogue MUD!", exits on `q`).
- **4 MD5 gates byte-identical** (unchanged from the F3 AMENDMENT B baseline): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `524d2872daefb2677c8ddc1ac8f34cf5`, json
  `066c99974f6052317636854dc4c2a2d5` → `fc357296537347a0ef58af49b5a40081` [B-F2 re-baselined
  2026-08-17, see gate table; → `9720478c…` F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **test_analyzer_bin PASS** (build_test.sh "5 passed, 4 failed" — unchanged baseline).

## F-CLOSEOUT — std-lib closeout (2026-08-14)

Final gate sweep of the std-lib closeout plan (F1+F2+F3 fixes). All gates re-verified with
`/tmp/fx_subfolder/zig1` (HEAD `c5856928`), canonical std installed at `/tmp/fx_subfolder/lib/`:

- **4 fixes landed:** **D2** (module-instance ≥1 incomplete type — FIXED in
  `sf/src/type_resolver.zig`, module-scoped bare-ident resolution; `arena_multi_inst_xmod`
  RED→OK), **host_is_windows** config const (`sf/src/config.zig`), **printInt INT_MIN**
  (i64-widened negation in `sf/src/std_io.zig`), **emitSocketSelect #ifdef** guard +
  spec-catalog sig corrections (`sf/src/c89_emit.zig` + the std-lib migration spec).
- **21-example matrix: 21/21 dump/gcc/link rc=0.** mud_server run rc=124 ("MUD server listening
  on port 4000", timeout-gated); rogue_mud run rc=0 (boots "Welcome to Rogue MUD!", exits on `q`).
- **4 MD5 gates byte-identical** (F3 re-baseline, AMENDMENT B): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `524d2872daefb2677c8ddc1ac8f34cf5`, json
  `066c99974f6052317636854dc4c2a2d5` → `fc357296537347a0ef58af49b5a40081` [B-F2 re-baselined
  2026-08-17, see gate table; → `9720478c…` F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **Corpus (248 dirs): `OK=242 / FAIL=2 / ICE=0 / CRASH=0 / green-guards=4`.** FAIL=2 =
  `field_store_drop` (bare `@import("pal")`, `error[3048]`) + `self_embed_optional_cycle` (C89
  fundamental, `error[24]` circular type); green-guards = `eu_assign_incompat_payload` /
  `euvoid_val_catch` / `field_access_optional` / `var_declared_void`. `arena_multi_inst_xmod` is
  the 248th dir (new RED→OK repro — the D2 fix).
- **test_analyzer_bin PASS** (build_test.sh "5 passed, 4 failed" — unchanged baseline).

**Tracking entries (stay LATENT, documented — NOT fixed):**

- **Win32 WSAStartup** — `std_net.init()` is a no-op on Windows (returns 0, no `WSAStartup`/
  `WSACleanup`); a Windows build must add WinSock startup/cleanup before `createTcpServer`/`select`
  work. `std_net.cleanup()` is likewise empty.
- **Win-arm / OpenWatcom `#ifdef` arms untested** — the socket builtin bodies are emitted with a
  `#ifdef _WIN32 / #else` guard (mirroring `net_runtime.c`), but only the Linux `#else` arm is
  exercised here; the Win-arm / OpenWatcom arms remain untested.

## F-GATE — search-path gate sweep + reconciliation (2026-08-14)

Final gate sweep of the std-lib search-path plan (Task F + F-MIGRATE). All gates re-verified with
`/tmp/fx_subfolder/zig1` (HEAD `51fa4342`), canonical std installed at `/tmp/fx_subfolder/lib/`:

- **21-example matrix: 21/21 dump/gcc/link rc=0.** mud_server run rc=124 ("MUD server listening on
  port 4000", timeout-gated); rogue_mud run rc=0 (boots "Welcome to Rogue MUD!", exits on `q`).
- **4 MD5 gates byte-identical** (post-migration re-baseline): gol `4074946027f8f72a325fafaa459bc8ec`,
  lisp `b71a0e0c3d3ad78349e219a9e72c8b35`, json `b47f9498c56a3f6995f803600968dd3b`, mud
  `447c491b4877e65b2ca2b87089a3021b`. Runtime-identical proof (AMENDMENT B): gol renders grid (100
  generations, 0 literal `{}`/`{c}` specifiers); lisp REPL evaluates `(+ 1 2)`→3 / `(define x 10)`
  / `(+ x 5)`→15 / `(car (quote (5 6)))`→5; json parses test.json rc=0; mud rc=124.
- **Corpus (247 dirs): `OK=241 / FAIL=2 / ICE=0 / CRASH=0 / green-guards=4`.** FAIL=2 =
  `field_store_drop` + `self_embed_optional_cycle`; green-guards =
  `eu_assign_incompat_payload` / `euvoid_val_catch` / `field_access_optional` / `var_declared_void`.
- **test_analyzer_bin PASS** (build_test.sh "5 passed, 4 failed" — unchanged baseline).

**Search-path record.** The **D1 defect** (bare `@import("std")` unresolved) is **resolved**: Task F
wired the search path (tiers: importer dir → `-I`/`--lib-dir` dirs in CLI order → default install
path `<exe_dir>/lib` → CWD), F-MIGRATE migrated all 34 example + 57 repro sources to bare
`@import("std")` / `@import("std_net")` / `@import("std_arena")` and deleted all **181** local
`std*.zig` copies (kept `std_import_bare_xmod/local/` as the `--lib-dir` GREEN fixture).
Reclassifications: `test_stub_0` + `std_import_bare_xmod` **FAIL→OK**. `std_import_bare_xmod` is a
**two-state gate**: RED (bare `@import("std")` unresolved without the search path — pre-Task-F) vs
GREEN (resolves either via `--lib-dir local/` OR the default install path `<exe_dir>/lib`).

## F-MIGRATE — std-lib search-path migration closeout (2026-08-14)

All `examples/z98/*/` + `repro/mi_matrix/*/` sources migrated from local `@import("std.zig")` /
`@import("std_net.zig")` / `@import("std_arena.zig")` (and rogue_mud's `../mud_server/std.zig`
cross-refs) to bare `@import("std")` / `@import("std_net")` / `@import("std_arena")`, resolved via
the Task F search path to the canonical `sf/src/std*.zig` installed at `<exe_dir>/lib`
(`/tmp/fx_subfolder/lib`). All **181** local `std*.zig` copies deleted (kept:
`std_import_bare_xmod/local/{std,std_io}.zig` — the Task R `--lib-dir` GREEN fixture). The 14
`std.debug.print`/`printInt` sites (10 example dirs incl. `hello`, plus rogue_mud's 3 test files)
rewritten to `std.io.print`/`printInt`, with `sf/src/std_io.zig` `print` made variadic
(`print(s: [*]const c_char, ...)`) so the compiler's enhanced print lowering (fn name `print` +
≥2 args) still fires — format specifiers stay interpolated.

**Reclassifications (bare `@import("std")` now resolves via the default install path):**
- `test_stub_0` — **FAIL → OK** (was `error[3048]` std-lib-deferred; now resolves + emits).
- `std_import_bare_xmod` — **FAIL → OK** (bare `@import("std")` resolves via `<exe_dir>/lib`; its
  `--lib-dir local/` GREEN path unchanged).

**Corpus (247 dirs, std installed): `OK=241 / FAIL=2 / ICE=0 / CRASH=0 / green-guards=4`.**
FAIL=2 = `field_store_drop` (bare `@import("pal")`, `error[3048]`) + `self_embed_optional_cycle`
(C89 fundamental). No new FAIL; OK improved 239→241. **21-example matrix 21/21** dump/gcc/link OK
(mud_server + rogue_mud link+run with the canonical `std.zig` io+arena re-export — the F4-D2
arena-instance emission bug no longer triggers).

## Totals (246 dirs / 236 manifest repros)

- **CURRENT (2026-08-13 F3 closeout — lisp_interpreter lowerer-defects plan): raw sweep of all
  246 dirs (gcc-exit classifier, `/tmp/fx_subfolder/zig1`, fresh F6-source build, HEAD
  `31de6800`): OK=239 / FAIL=3 / ICE=0 / CRASH=0 / green-guards=4** (239+3+4=246). FAIL=3
  unchanged: 2 std-lib-deferred (`field_store_drop` + `test_stub_0`, both `error[3048]`) +
  `self_embed_optional_cycle` (C89 fundamental). Green-guards unchanged:
  `eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
  **No new corpus FAIL introduced by the lisp-defects plan (F1-F6).** The 6 plan repro dirs
  (`union_literal_nested_xmod`, `global_null_init_xmod`, `nested_field_store_xmod`,
  `nested_field_store_xmod2`, `sizeof_struct_union_xmod`, `union_emission_layout_xmod`) all
  classify **OK** (246 = 236 manifest + 10 separately-tracked). **21-example matrix: 21/21
  end-to-end working** — the sole
  gcc-FAIL `lisp_interpreter` (pre-existing builtins.zig `zT_N` lowerer defect) is now
  dump/gcc/link/run rc=0 AND functionally correct (evaluates `nil`/`true`/`+`/`(quote 5)`/
  `cons`; Defects A-E fixed). `json_parser_workaround` run rc=0 (its F4-exposed SEGFAULT
  resolved by the Defect D+E fixes) — parses test.json, prints the full tree. mud_server boots
  (server, timeout-gated). 4 MD5 gates byte-identical: gol `ff47d18d…`, lisp `c1cb748b…`, json
  `376fd681…`, mud `fd0fdaa4…`. test_analyzer_bin PASS (build_test.sh 5/4 unchanged). See the
  F3 closeout section below. Corpus dirs = 236 manifest repros (230 at F7 + the 6 plan repros)
  + 10 separately-tracked dirs (`opt_slice_null_return`, `ptr_to_int_void_xmod`,
  `mod_silent_drop_xmod`, `zT_missing_fwd_xmod`, `plat_stubs_missing_xmod`,
  `tagged_union_cmp_xmod`, `extern_runtime_symbol_xmod`, `io_builtin_test`,
  `console_builtin_test`, `net_builtin_test`).
- Prior: OK=233 / FAIL=3 / ICE=0 / CRASH=0 / green-guards=4 over 240 dirs (2026-08-13 F7 —
  std-lib plan CLOSEOUT; measured with `/tmp/fx_subfolder/zig1`, fresh F6-source build).
  FAIL=3 unchanged: 2 std-lib-deferred
  (`field_store_drop` + `test_stub_0`, both `error[3048]`) + `self_embed_optional_cycle` (C89
  fundamental). Green-guards unchanged: `eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`. **No new corpus FAIL introduced by the std-lib plan
  (F1-F6).** The 3 std-lib-plan repro dirs (`io_builtin_test`, `console_builtin_test`,
  `net_builtin_test`) all classify **OK**. The D2 (`arena_alloc_default` → `std_arena.zig`, F3)
  and D4 (`plat_*` console stubs → builtins, F5) deferred gaps are **CLOSED**; `json_parser`,
  `json_parser_workaround`, `rogue_mud`, `extern_runtime_symbol_xmod`, `plat_stubs_missing_xmod`
  all link+run on the standard sf runtime (no legacy object, no `net_runtime.c`). **21-example
  matrix: 20/21 end-to-end working** (lisp_interpreter gcc-FAIL is the pre-existing
  builtins.zig `zT_N` lowerer defect; mud_server boots — server, timeout-gated). 4 MD5 gates:
  gol `b246a2fe…`, lisp `141994cc…`, json `f50ce1e6…` byte-identical; mud `fd0fdaa4…` (F6
  migration + F6-review null-coalesce re-baseline; mud is NOT an MD5 gate per the operator).
  test_analyzer_bin PASS (build_test.sh 5/4 unchanged). See the F7 closeout section below.
  Corpus dirs = 230 manifest repros + 10 separately-tracked dirs (`opt_slice_null_return`,
  `ptr_to_int_void_xmod`, `mod_silent_drop_xmod`, `zT_missing_fwd_xmod`,
  `plat_stubs_missing_xmod`, `tagged_union_cmp_xmod`, `extern_runtime_symbol_xmod`,
  `io_builtin_test`, `console_builtin_test`, `net_builtin_test`).
- Prior: OK=223 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 230 (2026-08-07 F4 gate sweep — char_literal switch + opt_slice null fixes CLOSEOUT). Measured with
  FAIL=3 / green-guards=4 / ICE=0 / CRASH=0** over **230 repros** (223 + 3 + 4 = 230; raw
  classifier FAIL = 7 — the 4 green-guards are a sub-bucket of the raw count). Measured with
  `sf/build/out_release/zig1` at HEAD (compiler source = F1 `e0a4d6d6` char_literal switch +
  F2 `5c515a7d` opt_slice null, commits 7dc119a6..7a732cb3; battery commits are repro-only).
  Corpus = 231 dirs (230 manifest repros + `opt_slice_null_return`, OK-by-gate/type-incorrect,
  tracked separately). The 15 battery repros ALL classify **OK** under the gcc-exit gate and are
  now **fully OK** — the F1/F2 fixes landed: the **12 Battery A char_literal switch-case repros
  no longer runtime-gap-tracked** (F1 emits real `case 'a':` labels at lower.zig:3202 expr /
  :3941 stmt; all 12 now print their expected post-fix output — `120`, `1120`, `19`, `1`, `109`,
  etc., verified by run), and the **3 Battery B opt_slice null-payload repros are no longer
  latent** (F2 Option B drops the dead `int zT_N; zT_N = NULL;` payload temp — 0 `-Wint-conversion`
  warnings, 0 `= NULL;` sites, still print `1`, verified by run). The 3 FAILs unchanged: 2
  std-lib-deferred (`field_store_drop` + `test_stub_0`, both `error[3048]`) +
  `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). The 4 green-guards unchanged:
  `eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
  No other repro flipped. Note: `opt_slice_null_return` remains OK-by-gate (type-incorrect,
  tracked separately, see the F5 section). 4 MD5 gates: gol byte-identical; mud/lisp/json
  RE-BASELINED by F2 (mud `6c0a83f1…`, gol `0d8f0092…`, lisp `fad41183…`, json
  `c403f079…` — full hashes in QUICK_REF). [F2 2026-08-08: `extern_runtime_symbol_xmod` added
  as a 232nd dir — OK-by-gate/latent, std-lib-deferred, tracked separately like
  `opt_slice_null_return`; manifest count and all totals UNCHANGED. See the F2 section below.]
  [F4 2026-08-08: `plat_stubs_missing_xmod` documented as OK-by-gate/latent,
  std-lib-deferred (the D4 platform-stub gap — 5 console/platform-detect stubs,
  `plat_is_windows` + `plat_console_*`, all rogue_mud-only); tracked separately
  like `opt_slice_null_return` / `extern_runtime_symbol_xmod`; manifest count
  and all totals UNCHANGED. See the F4 section below.]
  [F5 2026-08-13: the D4 plat-stub gap is CLOSED via the F2 console builtins —
  `rogue_mud/ui.zig`'s 5 `plat_*` console externs → `@isWindows`/
  `@consoleClear`/`@consoleGotoxy`/`@consoleSetColor`/`@putChar`; main.zig's
  `ui_mod.plat_is_windows()` → comptime `@isWindows()`; `plat_stubs_missing_xmod`
  migrated to the builtins → **FULLY OK** (link rc=0, run rc=0), its
  OK-by-gate/latent deferral CLEARED; rogue_mud links (rc=0, both recipes) +
  runs (rc=0, ANSI console verified). Manifest counts UNCHANGED (223/3/4/0/0,
  raw FAIL 7). See the F5 section below.]
- Prior: OK=208 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 215 (2026-08-07 F5 gate sweep — rogue_mud emission-defects plan closeout; Verified with `/tmp/zf5/zig1` — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors). `switch_mixed_case_argtype`
  **FAIL→OK** (added 2026-08-07 by the rogue_mud I-task): the sema mid-switch abort in
  `resolveSwitchExpr` — the MIX else-branch at semantic_analyzer.zig:1167 `return
  type_mod.TYPE_VOID;` aborted the whole switch when two prong bodies had non-coercible types
  (assignment→i32 vs empty-block→void), skipping all later prongs — so the call prong was never
  sema'd and `call_arg_types` was never populated, making the lowerer fallback type arg slots as
  raw lowered types (`unsigned int` for `&arena`, `char*` for the string literal). Now the
  MIX else-branch `continue`s (keeps resolving remaining prongs) while keeping the
  `resolvedTypeTableSet(..., TYPE_VOID)` (Option A, operator ruling; I4-validated). dump rc=0,
  gcc-clean, link rc=0, run rc=0; emitted arg temps correctly typed `Sand*` / `Slice_u8`. The 3
  remaining FAILs: 2 std-lib-deferred (`field_store_drop` + `test_stub_0`, both
  `error[3048]`) + `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). The 4
  green-guards unchanged: `eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`. No other repro flipped. Note: `opt_slice_null_return`
  is OK-by-gate (type-incorrect, tracked separately). Known adjacent bug (out of scope, tracked
  as follow-up): char-literal switch `case` labels dropped at lower.zig:3858-3860/:3121-3123 (refs superseded — actual sites lower.zig:3183 expr / :3920 stmt), so
  this repro's switch still takes `default` at runtime (see the F4 section below).
- Prior: OK=207 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 214 (2026-08-07 F3: cross-module pub const resolves)
- Prior: OK=206 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 213 (2026-08-07 F2: undefined struct-array field init emits valid C)
- Prior: OK=205 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 212 (2026-08-07 F1: duplicate-typed struct fields emit correctly)
- Prior: OK=203 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 210 (2026-08-07 F1: labeled statement support in parser, sema, lowerer)
- Prior: OK=202 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 210 (2026-08-07 I-task: rogue_mud build attempt — labeled_stmt_unhandled added as FAIL)
- Prior: OK=202 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 209 (2026-08-06 Task F7 gate sweep, 4-item plan closeout)
- Prior: OK=200 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 208 (2026-08-06 F2 u64-safe int_literal marker)
- Prior: OK=199 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 207 (2026-08-06 F1 @intCast range-check)
- Prior: OK=198 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 206 (2026-08-06 F9 gate sweep)
- Prior: OK=197 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 205 (2026-08-06 F7: comptime_u64_fold_overflow)
- Prior: OK=196 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 204 (2026-08-06 P0 fix wave 1)
- **2026-08-01 ADD: `comptime_neg_int`** — RUNTIME GAP, not counted in the compile-only totals above. `const N = @intCast(i32, -5);` dumps rc=0, gcc clean, but emitted C never assigns `N` (comptime-folded negative dropped) → run prints garbage not `-5`. Tracks via runtime gate; the gcc-exit classifier reports it OK. Reproduces "comptime int cannot be negative". **FIXED post-F-1..F-8 (2026-08-04): prints `-5` correctly.**
- Prior: OK=162 / FAIL=4 / ICE=0 / CRASH=0 (2026-07-16: extern-fn ABI-wrap — c89_emit .call_direct wrapping for extern fn optional/EU returns; 5/5 extern-fn repros fixed; opt_extern_ptr_file FIXED; json_parser HARD gate 0 errors; EU representation (3) now FIXED by error-set pipeline)
- Prior: OK=148 / FAIL=14 / ICE=0 / CRASH=0 (2026-07-16: folded 13 ungated RED repros from top-level `repro/` tree into gated corpus)
- Prior: OK=148 / FAIL=1 / ICE=0 / CRASH=0 (2026-07-16: error-set crash fix chain — F-SEMA Gap A/B sema arms + shared helper `typeRegistryErrorSetMemberIndex`; F-C5C7 Fix A+B valid module/type_alias temps + Fix C symreg `populateTypePayload` error_set_decl case + Fix E/F lowerer member lookups + module-base field_access branch; F-LISP module-qualified fn refs via func_ref machinery; F-C6 c89_emit `emitErrorSetType` typedef + per-member `#define` constants; F-TEMPNONE dedicated temp-index sentinel `TEMP_NONE=0xFFFFFFFF`; F-REMOVE unconditional 3042 tripwire + module-as-value warning[3023] + observability repro)
- Prior: OK=147 / FAIL=1 / ICE=0 / CRASH=0 (2026-07-15: error-set pipeline fix — T1 symbol_reg, T2 sema, T3 lowerer, T4 c89_emit)
- Prior: OK=144 / FAIL=2 / ICE=2 / CRASH=0 (2026-07-14: Phase D repros — actual state; earlier manifest erroneously claimed 147/1/0/0)
- Prior: OK=136 / FAIL=5 / ICE=1 / CRASH=0 (2026-07-14: sema-diagnostics v2)
- Prior: OK=122 / FAIL=15 / ICE=1 / CRASH=0 (2026-07-13: xmod_field_store_index fixed)
- Prior (132 repros): OK=117 / FAIL=14 / ICE=1 / CRASH=0 (v4 idiomatic baseline)

---

## ICE (7 — all from syntax coverage category A-E, 2026-07-30)

7 new ICE repros added for categories A-E. All hand-rolled tagged union patterns (A1-A3) trigger `error[3043]: internal: unsupported field-store base`. Inferred error set patterns (B1-B2) trigger `error[3011]: error literal not found in error set`.

### Error[3043] — hand-rolled tagged unions (3)
- `tu_field_store_ptr` — union field-store through @ptrCast pointer
- `tu_uninit_data_void` — uninitialized union data for void-variant tag
- `tu_ptrcast_copy` — hand-rolled tagged union copy through @ptrCast

### Error[3011] — bare `!` error sets (2)
- `inferred_errorset_fnptr` — @ptrCast to fn(!T) through *void
- `inferred_errorset_xmod` — cross-module bare ! error inference

### Error[2000] — parser (2, defined in category F)
- `define_mutate_closure` — `fn (i32) i32` type syntax not parseable
- `define_mutate_closure_green` — same parse failure

**Prior:** All error-set SEGV/ICE crashes eliminated. **Accidental-revert history:** commit `a4bb08c4` ("use structural hash for optional C typedef naming") accidentally reverted 4 earlier error-set commits — `9f2236e2` (c89_emit error_set typedef + member emission), `c0803328` (symreg error_set payload population), `d0104d33` (sema error_set member handlers), `b4d78651` (lowerer module-base field_access branch) — which is why an earlier manifest claimed 147/1/0/0 when actual was 144/2/2/0. This plan's upstream fix chain correctly restored all 4 layers.

- `lzw_cross_module_error_set` (C5) — **FIXED** — was ICE (SEGV at hoisted_temps[18] OOB). Fixed by: sema member resolution via shared helper, symreg payload, lowerer valid module temp + module-base field_access branch + member lookup via helper, c89_emit cross-module typedef emission.
- `lzw_error_set_member_comparison` (C6) — **FIXED** — was ICE → partial F2 error[3042] → now compilable C. Fixed by: sema Gap A/B arms, c89_emit `emitErrorSetType` typedef + per-member `#define` ordinals.
- `lzw_eu_return_mismatch` (C7) — **FIXED** — was ICE (SEGV same class as C5). Fixed by: sema member resolution, symreg payload, lowerer valid type_alias temp + member lookup via helper, `.is_error=1` wrap_error_err EU-wrap coercion path.

---

## FIXED (2026-07-16 — optional-wrap coercion family: 6/7)

### Orelse unwrap (F-REPROFIX + F-SEMA-ORELSE)
- `orelse_void` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (orelse void coercion). Fixed by: repro rewritten to valid z98 syntax + sema :806 coercion recording.
- `optstar_void_orelse` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (*void orelse coercion). Fixed by: repro rewritten to valid z98 syntax + sema :806 coercion recording.
- `file_const_single` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (file-level const optional). Fixed by: repro rewritten to valid z98 syntax + sema :806 coercion recording.

### Catch EU unwrap (F-SEMA-CATCH + F-CATCHRETURN)
- `eu_optional_value` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (error union optional value). Fixed by: sema :1187 coercion recording + lower.zig `lowerExprOrBlock` stmt routing.
- `mi_eu_opt_val` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (module-import variant of eu_optional_value). Fixed by: sema :1187 coercion recording + lower.zig `lowerExprOrBlock` stmt routing.

### Var_decl type pollution (F-LOWERIDENT2)
- `opt_value_decl` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (optional payload in decl init). Previously fixed by band-aid `3c8c1e92`, now fixed at ROOT via sema :1559 guard against resolvedTypeTable pollution.

---

### FIXED by extern-fn ABI-wrap (1)
- `opt_extern_ptr_file` — **FIXED (F-ABI)** — was deferred `??*T FILE* gateway`. extern-fn ABI-wrap (`c89_emit .call_direct` wrapping for extern fn optional/EU returns) now wraps raw `FILE*` into `Opt_*` type. gcc 0 errors. No longer deferred.
---

## FAIL (6) — [2 remain FAIL post-F-1..F-8; see F-1..F-8 section above]

### VOID decl-skip / undeclared-temp (2) — out-of-scope
- `var_declared_void` — gcc `'x' undeclared` (VOID-typed variable skipped in C decl emission). **Still FAIL post-F-1..F-8** (sema doesn't reject void vars).
- `field_store_drop` — **STILL FAIL post-F-1..F-8** — now via `error[3048]: could not resolve imported file 'pal'` (its `const pal = @import("pal")` can't be resolved — pre-existing import-resolver gap; F-5 AMENDMENT C).

### Aggregate / anon-init (2) — out-of-scope
- `anon_init_orelse_rhs` — gcc `incompatible types` (anonymous init on orelse RHS). **FIXED post-F-1..F-8 (F-6+F-8)** → OK.
- `array_tagged_union_read` — gcc `incompatible types` (tagged union indexing on array). **Still FAIL post-F-1..F-8** (union payload assigned from `unsigned int`).

### Syntax coverage new FAILs (2) — 2026-07-30
- `tu_uninit_data_void` — gcc `void tag/data declared` (hand-rolled tagged union with uninitialized data variant). **FIXED post-F-1..F-8 (F-3)** → OK.
- `module_var_mutable` — gcc `'x' undeclared` (global mutable var, C emission misses global declaration). **FIXED post-F-1..F-8 (F-7)** → OK.

Note: FAIL=4 count reflects 2 remaining out-of-scope families (VOID decl-skip, aggregate/anon-init) = 4 repros total (2+2). EU representation (3 repros: eu_err_ret, eu_value_ret, mi_eu_err) now FIXED by error-set pipeline (F-C5C7 Fix A/B) — gcc 0 errors.

---

## Folded 13 RED repros (2026-07-16)

Gated 13 ungated top-level repros into `repro/mi_matrix/` corpus. **As of 2026-07-16, 9/13 FIXED (see FIXED sections above).** Remaining 4 still classify as FAIL (gcc errors):

- **EU representation** (3): `eu_err_ret`, `eu_value_ret`, `mi_eu_err` — **FIXED by error-set pipeline (F-C5C7 Fix A/B)** — gcc 0 errors. Was previously FAIL (incompatible types in error-union payload/return coercion).
- **VOID decl-skip / undeclared-temp** (2): `var_declared_void` — `'x' undeclared` (VOID-typed variable skipped in C declaration). `field_store_drop` — `'zT_23'/'zT_32' undeclared` (undeclared temps from field-store lowering; same root cause as var_declared_void VOID-decl-skip path). Fix owned by future plan.
- **Aggregate / anon-init** (2): `anon_init_orelse_rhs` — anon init on orelse RHS. `array_tagged_union_read` — tagged union indexing on array.

---

## Repro added 2026-07-16

- `module_as_value` — **OK (warning[3023] non-fatal)**. Bare module ident in value position (`_ = h;`) emits `warning[3023]: module used as value expression`. VOID temp prevents C-decl pollution (TYPE_VOID=1 skipped by c89_emit decl loop). zig0 oracle: accepts silently (rc=0). C compiles cleanly (gcc 0 errors). Class: OK.
  - **REGRESSION + F-9 FIX (2026-08-04):** post-F-1..F-8 this was FAIL — emitted `main_6D0C3706.c` had
    `(void)zT_0;` with `zT_0` undeclared (module-ident branch returned a VOID temp). **Fixed F-9** (module
    branch now returns `TEMP_NONE`) — classified **OK** again.

---


## FIXED (2026-07-16 — extern-fn ABI-wrap: 5/5)
- `opt_extern_ptr_file` — **FIXED (F-ABI)** — was deferred `??*T FILE* gateway`. extern-fn ABI-wrap (`c89_emit .call_direct` wrapping for extern fn optional/EU returns) now wraps raw `FILE*` into `Opt_*` type. gcc 0 errors. No longer deferred.
- `extern_fn_opt_return` — **OK (F-ABI)** — optional return from extern fn; ABI-wrap emits wrapper that calls extern, builds `Opt_*` struct from raw return. gcc 0 errors.
- `extern_fn_opt_return_cross` — **OK (F-ABI)** — cross-module variant of extern_fn_opt_return. gcc 0 errors.
- `extern_fn_eu_return` — **OK (F-ABI)** — error-union return from extern fn; ABI-wrap emits caller-side wrapper. gcc 0 errors.
- `error_set_unknown_member` — **OK (F-ABI)** — error-set member resolution across modules; was expected FAIL per original plan but passes gcc 0 errors after extern-fn ABI fixes. Class: OK (not fail).

---

## FIXED (2026-07-15 — lowerer-errors-deep-dive)

- `euvoid_val_catch` — **FIXED (F1)** — `lowerExprImpl` now handles `AstKind.block` in expression context. `return {}` coerced to `E!void` no longer ICEs.
- `lzw_local_var_undeclared` — **FIXED (F3)** — sema caches non-ident type annotations (`[256]u8`, `*T`, `?T`) in `resolvedTypeTable`. Lowerer emits `decl_local` — `buf` declared in C.

## Repro added 2026-07-14

- `field_access_optional` — **FIXED (ERR_3000)** — `?S.x` now produces `error[3000]: cannot access field on optional type` instead of lowerer ICE. Matches zig0 oracle (rejects `.` on optional). Green guard — no C emitted. → reclassified **green-guard (P3-1)**; see Green-guards section.
- `lzw_error_set_typedef` — **GREEN at HEAD** — simple error-union case passes.

## Previously FIXED (2026-07-14)

- `eu_assign_incompat_payload` — **FIXED** — `E!i64 → E!i32` now emits `error[3000]` at sema (EU payload mismatch severity check). → reclassified **green-guard (P3-1)**; see Green-guards section.
- `euoptptr_val_orelse` — **FIXED** — optional C typedef naming uses `getCTypeName` instead of `name_id=0`.
- `optptr_val_orelse` — **FIXED** — same c89_emit fix.
- `optptr_null_orelse` — **FIXED** — same c89_emit fix.
- `eu_assign_incompat_errorset` — **WARNING** — different error sets produce warning[3000] but same C struct compiles.
- `typeres_unhandled_node` — **FIXED (2026-07-14)** — range handler + lowerer demote.

## Previously FIXED (2026-07-13)

- `xmod_field_store_index` — EX1 fix (broad name-cache prepass)
- `array_value_copy` — EX3 fix (indexed elem type + emitter)
- `array_manyptr_type` — EX4 fix (c89_emit * sanitize)
- `func_ptr_return_type` — EX5 fix (FN_/FP_ prefix + ident_expr)

---

## Syntax Coverage Repro — 2026-07-30 (13 repros, categories A-F)

Repros discovered from broken examples (lisp_interpreter, json_parser_workaround, rogue_mud, lisp_adv). All hand-rolled tagged union patterns trigger error[3043]. Inferred error set patterns trigger error[3011]. GREEN regression guards pass where applicable.

| Category | Repro | GREEN | RED | Pattern |
|----------|-------|-------|-----|---------|
| A1 | `tu_field_store_ptr` | OK | **OK (F-3)** | union field-store through @ptrCast ptr |
| A2 | `tu_uninit_data_void` | — | **OK (F-3)** | uninitialized union data for void tag |
| A3 | `tu_ptrcast_copy` | — | **OK (F-3)** | hand-rolled tagged union copy |
| B1 | `inferred_errorset_fnptr` | OK | **OK (F-1)** | @ptrCast to fn(!T) through *void |
| B2 | `inferred_errorset_xmod` | OK | **OK (F-1)** | cross-module bare ! error set |
| C1 | `catch_block_implicit_expr` | OK | OK(no RED) | catch block expression works |
| D | `ptroint_arena_offset` | OK | FAIL | @intToPtr/@ptrToInt arena arithmetic |
| E | `module_var_mutable` | OK | **OK (F-7)** | global mutable var missing C decl |
| F | `define_mutate_closure` | ICE(2000) | ICE(2000) | fn ptr type not parseable by zig1 |

**Total (A-F): 13 new (10 unique + 3 GREEN guards), 2 new FAILs, 7 ICEs, 4 OK (all GREEN + C1 RED that unexpectedly passes)**

---

## Syntax Coverage G — 2026-07-30 (3 repros, cross-module struct literal)

Cross-module struct literal pattern discovered from json_parser_workaround. Creating a struct literal with an imported struct type causes the variable declaration to be missing from C output. Adding a field-store after the literal escalates to ICE(3043).

| Category | Repro | GREEN | RED | Pattern |
|----------|-------|-------|-----|---------|
| G1 | `ptrcast_slice_field_void` | OK | **OK (F-4)** | xmod struct + slice field + field-store |
| G2 | `ptrcast_slice_field_xmod` | OK | **OK (F-4)** | xmod struct + scalar fields + field-store |
| G3 | `ptrcast_slice_field_type` | OK | **OK (F-4)** | xmod struct literal only (no field-store, undeclared var) |

**Note:** Category F (define_mutate_closure) removed from corpus — `fn (i32) i32` syntax not parseable by zig1.

---

## Syntax Coverage H — 2026-07-30 (1 repro, cross-module &extern_var + union field-store)

Full json_parser_workaround chain: `&zig_default_arena` (address-of extern var) → `arena_alloc_default` → `@ptrCast` to struct with union data → field-store to union member → ICE(3043).

| Category | Repro | GREEN | RED | Pattern |
|----------|-------|-------|-----|---------|
| H1 | `xmod_amp_arena_union_store` | OK | **OK (F-3)** | &extern_var + extern alloc + @ptrCast + union field-store |

## Std-Lib Phase 1 — 2026-08-03 (6 repros, std-lib migration syntax-gap candidates)

Defensive repros for the std-lib migration design spec — each probes a Z98 syntax feature with ZERO prior corpus coverage. Classified per QUICK_REF (dump + per-file gcc -c). Full evidence in each dir's `NOTES.md`.

| Pattern | Repro | Result | Note |
|---------|-------|--------|------|
| struct fn-ptr field (vtable) | `fn_ptr_struct_field` | OK | **FIXED (F-2)** — was FAIL (`'write_fn' declared void`); struct FieldEntries back-patch + void-field guard |
| pub module var (scalar) | `module_pub_var_int` | OK | **runtime gap FIXED (F-7)** — `= 42` init now emitted; prints `43` |
| pub module var (struct) | `module_pub_var_struct` | OK | **runtime gap FIXED (F-7)** — prints `7` |
| module const fn-call init | `module_const_fn_call` | OK | **runtime gap FIXED (F-7)** — `getInit()` now called; prints `42` |
| local fn-ptr (bare, no errset) | `fn_ptr_local_bare` | OK | gcc-clean, runs correctly (prints 3); sema warning[3000] non-fatal |
| cross-module `extern "c"` | `import_extern_c` | OK | 2 .c emitted, gcc-clean, runs correctly (prints hello) |

**Total active repros in v16: 192. Classification: OK=173, FAIL=8, ICE=11, CRASH=0.** *(pre-F-1..F-8 snapshot — see F-1..F-9 section for post-fix OK=184 / FAIL=8 / ICE=0)*

---

## F-1..F-9 corpus-RED fixes — 2026-08-04 (measured with /tmp/zb/zig1)

Post-fix state: **OK=184 / FAIL=8 / ICE=0 / CRASH=0** over 192 repros.

Post-P1+guard state (this file, 197 repros): **OK=188 / FAIL=9 / ICE=0 / CRASH=0** — see
"Defensive repros (Plan 1, 2026-08-04)" below. The +1 FAIL is `self_embed_optional_cycle`
(its own documented F-8 residual); the other 4 new repros classify OK.

All 6 pre-fix `error[3043]` ICEs eliminated (moved to OK):
- `tu_field_store_ptr`, `tu_ptrcast_copy`, `xmod_amp_arena_union_store`, `struct_field_store_subscript`
  (F-3), `ptrcast_slice_field_void`, `ptrcast_slice_field_xmod` (F-4).

Former FAIL/ICE repros now OK (verified per-file gcc clean):
- `inferred_errorset_fnptr`, `inferred_errorset_xmod`, `bare_error_union_return` (F-1 error[3011] fixed)
- `fn_ptr_struct_field` (F-2)
- `tu_uninit_data_void`, `tu_field_store_ptr`, `tu_ptrcast_copy`, `xmod_amp_arena_union_store`,
  `struct_field_store_subscript` (F-3)
- `ptrcast_slice_field_type`, `ptrcast_slice_field_void`, `ptrcast_slice_field_xmod` (F-4)
- `anon_init_orelse_rhs` (F-6+F-8)
- `module_var_mutable` (F-7)
- `opteu_err_if_expr`, `opteu_err_switch`, `module_as_value` (F-9)
- Runtime gaps now FIXED (run-verified): `comptime_neg_int` → `-5`, `module_pub_var_int` → `43`,
  `module_pub_var_struct` → `7`, `module_const_fn_call` → `42`.

Remaining 8 FAIL (0 ICE) — as measured with /tmp/zb/zig1 pre-P2; see the P2-3 green-guard
section below for the var_declared_void/euvoid_val_catch reclassification:
- **Emission defects (dump rc=0, gcc rejects):** `array_tagged_union_read` (**FIXED by P2-2**,
  2026-08-04), `ptroint_arena_offset` (**FIXED by P2-4**, 2026-08-05), `var_declared_void` (**now a
  green-guard, P2-3**).
  - NOTE: `module_as_value`, `opteu_err_if_expr`, `opteu_err_switch` were FAIL in the F-1..F-8
    baseline (undeclared `zT_0` temp / incompatible int→`Opt_` assign) but are now **OK — fixed F-9
    2026-08-04** (Option B optional-of-EU unwrap in the error-literal sema handler + module branch
    `TEMP_NONE`). Verified per-file gcc clean; see "Former FAIL/ICE repros now OK" above.
- **Frontend gaps (5, 0 `.c` emitted; 2 now green-guards P3-1):** `catch_block_value_producing`
  (error[2000]), `eu_assign_incompat_payload` (error[3000] — **now a green-guard, P3-1**),
  `field_access_optional` (error[3000] — **now a green-guard, P3-1**), `field_store_drop`
  (error[3048], pal-import — see QUICK_REF known-issues), `test_stub_0`
  (error[3048], imports nonexistent `"std"`).

---

## Defensive repros (Plan 1, 2026-08-04) — +4 repros (192 → 196)

Four defensive repros guarding deferred items from the F-1..F-9 review (cross-module global
field-access, F-8 optional self-embed residual, F-7 array `load_global` copy-loop, anonymous
error-set comparison). Classified with `/tmp/zb/zig1` per the QUICK_REF corpus classifier
(dump rc + emitted `.c` count + per-file `gcc -c`; runtime verified for the runnable ones).

| Repro | RED | GREEN | Classification (measured) | Guards |
|-------|-----|-------|---------------------------|--------|
| `xmod_global_field_access` | runtime gap | OK (prints 2) | **FIXED (P1-2)** — dump rc=0, gcc-clean, prints `2` (two bumps → counter=2) | F-7 review I-1: cross-module global field-access — FIXED by Plan 1 Task P1-2 (lower.zig SymbolKind.global branch + header extern decls) |
| `self_embed_optional_cycle` | FAIL | — | **FAIL** — dump rc=0, 1 `.c`, gcc `unknown type name 'zT_DD0C1E27_X'` (incomplete-type) | F-8 residual: `struct X { next: ?X }` → infinite-size C type; guards, not fixes |
| `load_global_array_copy` | OK | — | **OK** — dump rc=0, 1 `.c`, gcc clean, runs: prints `3` and `15` (concatenated `315`, print_int adds no newline) | F-7 array `load_global` copy-loop correctness (dead copy-temps, correct but wasteful) |
| `anon_errset_comparison` | OK (prints 1) | OK (prints 1) | **OK (semantically verified, P3-3)** — dump rc=0, 1 `.c`, gcc clean, RED prints `1`, GREEN prints `1`; RED==GREEN==1 on zig1 AND zig0 oracle (matches oracle) | bare-`!` error-set member comparison (`err == error.Bad`) — **semantically correct (P3-3)**: anon error literal carries the raw name_id (unique-per-name, program-stable interner code), so same name ⟹ same code, distinct names never collide |

**Updated totals: OK=187 / FAIL=9 / ICE=0 / CRASH=0 over 196 repros.** The +1 FAIL is exactly
`self_embed_optional_cycle`'s own documented status (F-8 residual). The other 3 new repros
classify OK, so the FAIL increase does not exceed the new repros' own documented status; no
regressions in the existing 192.

**Notes:**
- `xmod_global_field_access` was a RUNTIME GAP (counted OK in the compile-only gate) and is now **FIXED by Plan 1 Task P1-2** — prints `2` (was 1).
- `self_embed_optional_cycle` FAIL is the documented F-8 residual. Naive C emission would produce
  `struct X { struct X next; int has_value; }`; today the struct typedef is dropped entirely
  (`unknown type name`), so the residual is guarded, not fixed.
- `anon_errset_comparison`: RED and GREEN both print `1` — the bare-`!` set comparison is
  **semantically correct (P3-3, Option A)**. name_id is a unique-per-name, program-stable
  interner code; same name ⟹ same code, distinct names can never collide within one program.
  Verified RED==GREEN==1 on zig1 and the zig0 oracle. Investigation resolved — see the P3-3
  section below.

---

## Task P1-4 guard repro — 2026-08-04 (+1 repro, 196 → 197)

Guards the analyzer `analyzeExpr` builtin_call crash that crashed `examples/z98/lzw` at HEAD
(regression `532420cb`, last-good `7bc6e4d1`). Single-file repro of `main.zig:17`:
`@intCast` inside an `if` condition. `builtin_call.child_0` is the builtin's **name_id**, not a
node index (parser.zig:611); `analyzeExpr`'s generic child fallback recursed into it and formed a
cycle when the name_id collided with the enclosing `if_stmt`'s node index → infinite recursion →
stack overflow. Full analysis: `.superpowers/sdd/I-lzw-regression-report.md`.

| Repro | RED | Classification (measured) | Guards |
|-------|-----|---------------------------|--------|
| `lzw_builtin_call_crash` | CRASH pre-fix | **CRASH pre-fix** (dump rc=139 SIGSEGV, 0 `.c`; bypassed by `--no-null-check --no-lifetime-check --no-leak-check`); **OK post-fix** (dump rc=0, gcc-clean, links, runs → prints `invalid` on stdin EOF) | P1-4 analyzer `builtin_call` arg-walk fix (analyzer.zig:495-502) |

**Updated totals post-fix: OK=188 / FAIL=9 / ICE=0 / CRASH=0 over 197 repros.** The +1 total is
the new repro, which counts OK post-fix. FAIL count unchanged (9) vs the P1-3 baseline; no existing
repro flipped OK→FAIL; the lzw example itself now dumps, compiles, links, and runs.

---

## Green-guards (correct rejection, not a defect) — P2-3 (2026-08-04)

Reclassified per operator ruling (AMENDMENT P2-3). A green-guard is a valid-Z98 program that is
CORRECTLY rejected by the frontend with a diagnostic — it guards the rejection, it is not a compiler
gap. Green-guards are counted SEPARATELY from FAIL; a green-guard moving to OK/FAIL is a regression.
Classifier rule: dump emits 0 `.c` with the documented `error[NNNN]` diagnostic.

| Repro | Classification | Correct rejection (measured; P2 rows /tmp/p2v/zig1, P3-1 rows /tmp/p3/zig1) |
|-------|----------------|--------------------------------------------------|
| `var_declared_void` | **green-guard (was emission-defect FAIL)** | dump rc=2, `error[3000]: cannot declare variable of type void`, 0 `.c` emitted. `var x = noop();` (void init) — sema now rejects VOID-typed var decls (semantic_analyzer.zig:1674-1677) |
| `euvoid_val_catch` | **green-guard (was OK)** | dump rc=2, `error[3000]: cannot declare variable of type void`, 0 `.c` emitted. `var r = h() catch {};` (void-typed init) — latent void-var acceptance bug; Zig forbids void variables |
| `eu_assign_incompat_payload` | **green-guard (was frontend-gap FAIL)** | dump rc=2, `error[3000]: type mismatch in assignment -- internal type representations differ` (Task 18: ASCII `--`; the historical text read `—`), 0 `.c` emitted. `E!i64 → E!i32` payload mismatch at sema; zig0 oracle rejects identically (`error: type mismatch`) |
| `field_access_optional` | **green-guard (was frontend-gap FAIL)** | dump rc=2, `error[3000]: cannot access field on optional type; use .? to unwrap first`, 0 `.c` emitted. `.` on `?S`; zig0 oracle rejects identically (`error: type mismatch`) |

Post-P2-3 accounting: **OK=188 / FAIL=7 / green-guards=2 / ICE=0 / CRASH=0 over 197 repros.**
(var_declared_void: FAIL→green-guard; euvoid_val_catch: OK→green-guard; FAIL 9→7 counting
green-guards separately; array_tagged_union_read moved FAIL→OK in P2-2.) No other repro flipped.

**Post-P3-1 accounting (2026-08-05): OK=189 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 197
repros** (189 + 4 + 4 = 197). `eu_assign_incompat_payload` and `field_access_optional` reclassified
FAIL→green-guard (verified correct rejections matching the zig0 oracle — see table). No other repro
flipped.

**Updated totals (raw classifier, 197 repros): OK=189 / FAIL=8 / ICE=0 / CRASH=0.** Of the 8
classifier-FAILs, 4 are green-guards (this section): `eu_assign_incompat_payload`,
`field_access_optional`, `var_declared_void`, `euvoid_val_catch` (green-guards are a sub-bucket of
the raw 8, counted separately from FAIL).

---

## P2-4 — ptroint_arena_offset FIXED (2026-08-05)

`ptroint_arena_offset` moves emission-defect **FAIL → OK** via **Option A + SCOPED Option B**:

- **Option A (root cause, semantic_analyzer.zig:495,498):** `semanticAnalyzerResolveArithmetic`
  now treats `TYPE_INT_LIT` as a valid pointer-arithmetic offset (`&buf + 64` → pointer type
  instead of TYPE_VOID), covering `ptr ± lit` and `lit + ptr`.
- **SCOPED Option B (emission hardening, c89_emit.zig:2729,2732):** the `written_type` override in
  `emitHoistedDecls` now applies only when the hoisted temp's `type_id ∈ {TYPE_VOID, TYPE_UNDEFINED}`
  AND the derived `written_type` is valid (`!= 0xFFFFFFFF`) and `!= TYPE_VOID`. Zero-blast-radius
  (verified in `.superpowers/sdd/P2-optB-report.md`); the unscoped variant regressed the corpus.
- **Gates:** self-host build 0 gcc errors; repro dump rc=0, gcc-clean, links, runs rc=0
  (`zT_8` declared as `Arr_unsigned_char_6*`); full corpus **OK=189 / FAIL=8 / ICE=0 / CRASH=0**
  (raw classifier; FAIL −1 exactly, `ptroint_arena_offset` removed, no other flips); 4 MD5 gates
  byte-identical (mud `4644ad13…`, gol `d0d3051d…`, lisp `f84c8748…`, json `3492a935…`).

**Post-P2-4 accounting: OK=189 / FAIL=6 / green-guards=2 / ICE=0 / CRASH=0 over 197 repros**
(189 + 6 + 2 = 197). FAIL 9→8 raw; the 2 green-guards (`var_declared_void`, `euvoid_val_catch`)
count separately. Remaining 6 FAIL: 5 frontend gaps (`catch_block_value_producing`,
`eu_assign_incompat_payload`, `field_access_optional`, `field_store_drop`, `test_stub_0`) and
1 gcc-visible emission defect `self_embed_optional_cycle` (F-8 residual) — all documented above.

---

## P3-1 — reclassify 2 correct rejections as green-guards (2026-08-05)

`eu_assign_incompat_payload` and `field_access_optional` are **CORRECT rejections** matching the
zig0 oracle — green-guards, not defects (both documented as FIXED above; now formally reclassified
out of the FAIL count into the "Green-guards" section). Verified with /tmp/p3/zig1:

| Repro | zig1 (dump rc, error) | 0 `.c` | zig0 oracle |
|-------|------------------------|--------|-------------|
| `eu_assign_incompat_payload` | rc=2, `error[3000]: type mismatch in assignment -- internal type representations differ` (Task 18: ASCII `--`) | yes | rejects: `error: type mismatch` (rc=1) |
| `field_access_optional` | rc=2, `error[3000]: cannot access field on optional type; use .? to unwrap first` | yes | rejects: `error: type mismatch` (rc=1) |

**Post-P3-1 accounting: OK=189 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 197 repros**
(189 + 4 + 4 = 197). Raw classifier FAIL stays **8** (green-guards are a sub-bucket of the raw 8).
The 4 green-guards: `eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`,
`euvoid_val_catch`. The 4 real FAILs: 2 import-gap (`field_store_drop`, `test_stub_0`, both
`error[3048]`) + `catch_block_value_producing` (`error[2000]`) + `self_embed_optional_cycle`
(F-8 residual, gcc incomplete-type). No other repro flipped.

---

## P3-2 — defer 2 import-gap repros to the std-lib milestone (2026-08-05)

`field_store_drop` and `test_stub_0` remain classified **FAIL** but are now tracked as
**std-lib-deferred** — NOT compiler defects. Both fail via `error[3048]` because user programs
cannot import compiler-internal modules; no std lib exists yet. **Will pass when zig1 gains a real
std lib.** (Both already documented in QUICK_REF.md "3 frontend-gap repros" / known-issues.)

| Repro | Class | Cause | Will pass |
|-------|-------|-------|-----------|
| `field_store_drop` | FAIL (std-lib-deferred) | `const pal = @import("pal")` → `error[3048]: could not resolve imported file 'pal'` — pre-existing import-resolver gap; a user program cannot import compiler-internal modules | when zig1 gains a real std lib |
| `test_stub_0` | FAIL (std-lib-deferred) | imports nonexistent `"std"` → `error[3048]` | when zig1 gains a real std lib |

**Deferral changes no counts.** Accounting stays **OK=189 / FAIL=4 / green-guards=4 / ICE=0 /
CRASH=0 over 197 repros** (189 + 4 + 4 = 197; raw classifier FAIL stays **8**). The 4 real FAILs:
2 std-lib-deferred import-gap (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`catch_block_value_producing` (`error[2000]`) + `self_embed_optional_cycle` (F-8 residual, gcc
incomplete-type). No other repro flipped.

---

## P3-3 — anon_errset_comparison OK (semantically verified) + adjacent defects (2026-08-05)

Per the P3-3 operator ruling (**Option A**, docs-only closeout): the bare-`!`
`err == error.Bad` comparison is **semantically correct**. An anonymous error literal stores the
raw **name_id** as its C error code (`lower.zig:1191-1206`, `semantic_analyzer.zig:1182`), and
name_id is a **unique-per-name, program-stable interner code** — `string_interner.zig:88-122`
dedups by exact content (`mem_eql` at `:101`), one interner per program (`main.zig:146`), so same
name always yields the same name_id and distinct names can never collide within one program.
Measured **RED==GREEN==1** on zig1 AND the zig0 oracle (matches oracle); all pure-anonymous probes
(`==`/`!=`, cross-fn, distinct-name) match the oracle (`.superpowers/sdd/P3-anonerr-report.md`).

`anon_errset_comparison` upgraded from `**OK**` to **OK (semantically verified)** — it was already
OK since Plan 1 P1-1; this records the semantic justification. **Counts unchanged: OK=189 /
FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 197 repros** (189+4+4=197; raw classifier FAIL
stays 8). No other repro flipped.

**2 adjacent defects found by P3-3 — tracked as follow-ups, NOT fixed (out of scope):**

1. **Switch-on-error exhaustiveness → P3-5.** Switch-case collection in `lower.zig:2919-2934`
   handles only `int_literal`/`enum_literal` case nodes; an `error_literal` case falls to
   `continue` → zero SwitchCase entries → `switch (err) { default: ... }` always takes `default`.
   Affects named AND anonymous error sets; the oracle emits proper `case ERROR_Bad:`. No corpus
   repro or MD5 gate exercises it today. Clean upstream fix (mirror the enum_literal branch).
2. **Error-code representation unification → I3-5 / P3-6.** zig1 accepts inferred→named error-set
   coercions that real Zig also accepts (subset→superset is legal; zig0/z98 is stricter), but then
   MISCOMPARES: anonymous-set errors carry the raw name_id, named-set errors carry the ordinal.
   Only reachable through programs the zig0 oracle rejects, so it is not a corpus classification
   issue. Investigate (I3-5), then implement per ruling (P3-6).

---

## P3-4 + P3-7 — catch_block_value_producing FAIL → OK (2026-08-05)

`catch_block_value_producing` is now **OK** — the last of the 5 frontend-gap repros. Two tasks
flipped it:

- **P3-4 (commit a50e2910, value-producing blocks):** the catch block's trailing bare `99` (no `;`)
  no longer errors `error[2000]: expected ';' but found '}'` — the trailing `;` is now optional
  before `}` in `parserParseExprStmt` (parser.zig:1256-1260) — and `lowerExprOrBlock`
  (lower.zig:3223-3238) now returns the last child's temp, so the catch fallback materializes the
  real `99` instead of an uninitialized local (was garbage `-366458289`).
- **P3-7 (this commit, inline error-set types in type positions):** `helper.zig:1`
  `pub fn try_compute() error{Bad}!i32` — an INLINE error-set declaration in a type position — is
  now fully supported:
  - **Parser (parser.zig:902-930):** the `kw_error` branch of `parserParseType` now checks for a
    trailing postfix `!` after `parserParseErrorSetDecl` and, when present, parses the payload type
    and builds an `error_union_type` node (mirroring the base+`!` path at :914-921). Before: the
    `!` fell out of the type parser → `error[2000]: expected '{' but found token`.
  - **Type-resolver (type_resolver.zig:738-755):** `resolveTypeExprFull` now has an
    `error_set_decl` case — it appends the member name_ids to the registry `xn_items` table and
    registers an anonymous `error_set_type` via `typeRegistryGetOrCreateErrorSet` (content-deduped
    through the registry `es_cache`, mirroring `symbol_registrator.zig:195-210`/`:357-372` named-set
    population). Before: `error{Bad}` (no `!`) fell through to `TYPE_UNDEFINED` (:901-903) and the
    fn return type resolved void → ICE `error[3043]: internal: invalid temp index 0`.
  - **C89 emission (c89_emit.zig):** the anonymous (`name_id==0`) `error_set_type` is now included
    in the synthetic-type emission whitelists (`computeSharedSet`, `emitSharedHeader` sub-passes
    2a/2b, `emitSpecialTypes` sub-passes 2a/2b), so its `typedef int <cname>;` + per-member
    `#define <cname>_<member> <ordinal>` macros are emitted. Before: the whitelist excluded
    `error_set_type`, so the error-code temp's type name was undefined → gcc error.

**Measured (this build):** dump rc=0, 2 `.c` emitted (main + helper), gcc-clean, links, runs
printing **`99`** rc=0. `error{Bad}!i32` parses; bare `error{Bad}` (no `!`) no longer ICEs (dumps
clean, gcc-clean, prints `0`). 4 MD5 gates byte-identical (mud `4644ad13…`, gol `d0d3051d…`,
lisp `f84c8748…`, json `3492a935…`).

**Post-P3-7 accounting: OK=190 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 197 repros**
(190 + 3 + 4 = 197). Raw classifier FAIL **8 → 7** (green-guards remain a sub-bucket of the raw
count). `catch_block_value_producing` moved FAIL→OK. The remaining 3 real FAILs:
2 std-lib-deferred import-gap (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). The 4 green-guards unchanged:
`eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
No other repro flipped.

---

## P3-5 — switch-on-error exhaustiveness FIXED (2026-08-05) — +2 repros (197 → 199)

`switch (err)` over a caught error value (named OR anonymous error set) now emits real
`case <value>:` entries instead of an empty `switch (err) { default: ... }`.

- **Root cause (P3-3 investigation finding #3):** switch-case collection in `lower.zig:2919-2934`
  (and its statement-site twin `lower.zig:3644-3658`) handled only `int_literal` and `enum_literal`
  case nodes; an `error_literal` case node fell to `continue` → zero SwitchCase entries → the
  emitted C `switch (err) { default: ... }` always took `default`.
- **Fix (lower.zig):** added an `error_literal` branch to both switch-case collection sites,
  mirroring the `enum_literal` branch — value resolves via `enum_value_table` (ordinal) when an
  entry is present, else falls back to the raw `node.payload` name_id (anonymous-set case,
  matching the error_literal lowering at `lower.zig:1191-1206`).
- **Companion fix (semantic_analyzer.zig, `semanticAnalyzerResolveSwitchExpr`):** when the switch
  cond type is an `error_set_type` (or `error_union_type`), resolve `error_literal` case nodes
  against the cond error set (pushExpectedType + resolveExpr) so `enum_value_table` gets the
  ordinal — mirroring how `enum_literal` case nodes are resolved for tagged-union switches. Without
  this, a NAMED-set case value would fall back to the raw name_id and never match the produced
  ordinal-coded error.

| Repro | RED (pre-fix) | GREEN (post-fix) | Notes |
|-------|---------------|------------------|-------|
| `switch_on_error_named` | prints `0` (default taken; emitted `switch (err) { default: }`, 0 case entries) | prints `1` (emitted `case 0:`/`case 1:`) | `const E = error{ Bad, Other }`; `E!i32` returns `error.Bad`; catch switch |
| `switch_on_error_anon` | prints `0` (default taken) | prints `1` (emitted `case 23:`/`case 28:` = raw name_ids) | bare `!i32` returns `error.Bad`; catch switch |

Both classify **OK** per the QUICK_REF gate (dump rc=0, 1 `.c`, gcc-clean) in BOTH states — the
defect is runtime-wrong, not a compile failure — so these are new OK repros with a runtime-gap-now-
fixed annotation, NOT FAIL→OK moves. The zig0 oracle emits `case ERROR_Bad:` / `case ERROR_Other:`
and prints `1`; zig1 now matches that runtime behavior.

**Post-P3-5 accounting: OK=192 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 199 repros**
(192 + 3 + 4 = 199; corpus total grows 197 → 199 by 2 new OK repros). Raw classifier FAIL stays
**7** (green-guards remain a sub-bucket of the raw count). The 3 real FAILs unchanged:
2 std-lib-deferred import-gap (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). The 4 green-guards unchanged:
`eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
4 MD5 gates byte-identical (mud `4644ad13…`, gol `d0d3051d…`, lisp `f84c8748…`, json
`3492a935…`). No other repro flipped.

---

## P3-6 — error-code representation unification: per-name registry + `ERROR_<name>` prologue (2026-08-05) — +1 repro (199 → 200)

Operator ruling 2026-08-05: **Option B (zig0-style)**, per `.superpowers/sdd/I3-5-errorcodes-report.md`.
All error codes are now dense per-program **per-name** registry codes (name_id → small int,
1-based, first-use order) instead of per-set ordinals / raw name_id. Fixes the cross-set `e1 == e2`
miscompare for real-Zig-legal subset→superset coercions (both I3-5 probes now print `1`).

- **Registry:** `error_code_registry: U32ToU32Map` (name_id → code) on `CompilerContext`
  (main.zig, next to `enum_value_table`); `hash_mod.u32ToU32MapGetOrAddDense` (look up; miss ⇒
  `count+1`, store). Sema/lower/emitter all route through it.
- **Producers repointed** (ordinal / raw name_id → registry code):
  - sema `semanticAnalyzerResolveExpr` error_literal-under-expected-set (membership check kept).
  - sema `var x = error.Bad` set-scan inference (kept).
  - sema switch-case companion (P3-5) stores the registry code via the error_literal path.
  - lower `error_literal` fallback → `getOrAdd(name_id)` (bare-`!` anon path; same code as named).
  - lower `E.Bad` field-access (type-site + value-site) → `enum_const` with registry code.
  - lower switch-case error_literal fallbacks → `getOrAdd(name_id)`.
  - c89_emit `emitErrorSetType` member `#define`s revalued to registry codes.
- **Prologue macros:** program-global `#define ERROR_<name> <code>` emitted once into
  `zig_special_types.h` (multi-module shared header — every module .h includes it) and inline in
  the single-stream path; skipped when the registry is empty (keeps mud/gol byte-identical).
  Assignment order = sema/lower traversal order (deterministic), finalized by registering all
  error-set members in type order before emission.

| Repro | RED (pre-P3-6) | GREEN (post-P3-6) | Notes |
|-------|----------------|-------------------|-------|
| `errset_cross_set_compare` (NEW) | prints `00` | prints `11` | anon→named + named→named subset→superset `err == error.Bad`; classifies **OK** |

**Post-P3-6 accounting: OK=193 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 200 repros**
(193 + 3 + 4 = 200; corpus total grows 199 → 200 by 1 new OK repro). Raw classifier FAIL stays
**7**; the 3 real FAILs and 4 green-guards unchanged. 4 MD5 gates: **mud + gol byte-identical**
(mud `4644ad13…`, gol `d0d3051d…`); **lisp + json RE-BASELINED** per F-5 AMENDMENT B precedent
("runtime behavior is the gate, not byte-identity"): lisp `dd56cd23…`, json `900cb401…` — both
compile, link, and run correctly (lisp `(+ 1 2)` → `3`, `(foo-bar-baz)` → `Eval error:
UnboundSymbol`; json parses `test.json` identically). No other repro flipped. `@enumToInt(err)`
values change to registry codes (accepted; re-verified at runtime — `error_literal_return` still
prints `1`, all ~30 error repros unchanged).

---

## Task P0 — 3 defensive repros for comptime arithmetic folding gaps (2026-08-06) — +3 repros (200 → 203)

Three defensive repros proving the three comptime-arithmetic-folding pipeline gaps
(plan `.superpowers/plans/2026-08-06-comptime-arithmetic-folding-plan.md`, AMENDMENT P0-A/P0-B):
Gap 1 = `phase_ComptimeEvaluation` (main.zig:339-352) visits only `builtin_call` nodes; Gap 2 =
lowerer binary/unary handlers (`lower.zig:1218-1306`, `:1426-1439`) emit `BIN_*`/`UN_*` LIR
unconditionally while `builtin_call` (`:2456`) checks `comptime_values`; Gap 3 = type_resolver
array-size handler (type_resolver.zig:869-911) misses `mul`/`div`/`mod_op`. Classified with
`/tmp/z1/zig1` per the QUICK_REF corpus classifier.

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `comptime_binop_not_folded` | emission gap | **OK (gap RESOLVED by F1+F2+F4)** — dump rc=0, 1 `.c`, gcc-clean, links, runs printing `40 20 300 3 0 -30 10 30 20 120 7 -31`; `__module_init`-scoped `grep -c '[\*\/\%]'` = **0** (all 12 consts emit `int_const`: 40/20/300/3/0/-30/10/30/20/120/7/-31 — see NOTES.md) | Gap 1: bare binary/unary nodes never reached `comptimeEvalEvaluate` — FIXED by F1 (bitwise/shift comptime ops) + F2 (var_decl binop/unary inits folded in phase_ComptimeEvaluation) + F4 (lowerer guard consumes the fold) |
| `comptime_lower_ignores_fold` | emission gap | **OK (gap RESOLVED by F4+F5)** — identical measured state to repro 1 (same source; isolates Gap 2); `__module_init`-scoped `grep -c '[\*\/\%]'` = **0** | Gap 2: lowerer binary/unary handlers never consulted `comptime_values` — FIXED by F4 (comptime_values guards on 10 binary op handlers, INT_LIT→I32 remap) + F5 (negate/bit_not guards) |
| `comptime_array_size_gap` | semantic gap | **OK (runtime gap RESOLVED by F6)** — dump rc=0, 1 `.c`; the arrays now resolve `u8[4000]`/`u8[40]`/`u8[2]` (emitted `typedef unsigned char …[4000];`/`[40];`/`[2];`), gcc-clean (rc=0) — no longer a silent type-drop (pre-fix the consts degraded to uninitialized `int` globals; counted OK+runtime-gap per ruling P0-E) | Gap 3: type_resolver array-size handler missed `mul`/`div`/`mod_op` → `arr_len`=0 → `TYPE_UNDEFINED` — FIXED by F6 (mul/div/mod arms, type_resolver.zig:888-896) |

**Post-P0 accounting: OK=195 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 203 repros**
(195 + 4 + 4 = 203; corpus total grows 200 → 203 by 3 new repros). OK 193→195 (+2 = repros 1+2,
emission-gap annotations); FAIL 3→4 (+1 = `comptime_array_size_gap`). Raw classifier FAIL **7 → 8**
(green-guards remain a sub-bucket of the raw count). **UPDATED by "Fix wave 1" (operator rulings
P0-D/P0-E) below: `comptime_array_size_gap` reclassified OK+runtime-gap (FAIL 4→3) and
`fn_varargs_unsupported` added as FAIL (3→4) → final OK=196 / FAIL=4 / green-guards=4 @204 (raw
FAIL=8).** No other repro flipped.

**Source-note (deviation from the plan's verbatim draft source, see
`.superpowers/sdd/task-P0-report.md`):** the plan's draft main.zig for repros 1+2 does not compile
on the current compiler — (1) the parser requires `;` after `@cInclude(...)`; (2) varargs `...`
in `extern fn` params is not parseable (`error[2000]`); (3) `const A`/`const B` referenced ONLY
from other const initializers never receive C storage-global decls (`zG_..._A` undeclared in
`__module_init` → gcc error). Corrections applied: `;` after `@cInclude`, fixed-arity `printf`,
literal operands inlined. The tested gap is unchanged (12 bare binary/unary module-scope const
ops that must fold to `int_const`).

**Discrepancy note (repro 3, evidence over prediction — RESOLVED by ruling P0-E):** the
brief/ruling predicted `error: ISO C forbids zero-size array` for `comptime_array_size_gap`; the
measured pre-fix state is instead a **silent semantic miscompile** (arrays dropped, consts →
uninitialized `int` globals, gcc-clean). It was initially counted **FAIL** per AMENDMENT P0-B
(real gap, `int`-drop is wrong output), NOT because gcc rejects it — flagged for operator
re-adjudication under the classifier convention (gcc rc==0 ⇒ OK, per the
`comptime_neg_int`/`load_global_array_copy` runtime-gap precedent). **Operator ruling P0-E
(2026-08-06): classify it OK with runtime-gap annotation.** See "Fix wave 1" below.

---

## Fix wave 1 — operator rulings P0-D/P0-E (2026-08-06) — +1 repro (203 → 204)

- **P0-E (reclassify):** `comptime_array_size_gap` **FAIL → OK with runtime-gap annotation**. Under
  the QUICK_REF gcc-exit classifier the emission is gcc-clean (rc=0), so it is **OK**, not FAIL.
  The gap is a **silent semantic miscompile**: array types resolve `TYPE_UNDEFINED`
  (type_resolver.zig:869-911 misses `mul`/`div`/`mod_op` → `arr_len`=0), so
  `CELLS`/`HALF`/`REM` degrade to uninitialized `int` globals (no `u8[N]`, no `[0]`, gcc-clean).
  Counted OK following the `comptime_neg_int`/`load_global_array_copy` runtime-gap precedent; the
  miscompile is tracked as a runtime gap until F3 fixes it (re-verified 2026-08-06: dump rc=0, 1
  `.c`, gcc rc=0, emitted `int zG_..._CELLS;` / `int zG_..._HALF;` / `int zG_..._REM;`).
- **P0-D (new tracking repro):** the plan's original `extern fn printf(fmt: [*]const u8, ...) i32;`
  does not compile — parser.zig has NO varargs (`...`) support → `error[2000]: expected identifier
  but found token`. Recorded as a standalone tracking repro:

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `fn_varargs_unsupported` | parse gap | **FAIL** — dump rc=2, `error[2000]: expected identifier but found token` at the `...`, 0 `.c` emitted (frontend parse gap) | parser.zig has no varargs support; out of comptime-arithmetic scope — tracked as a known gap |

**Post-P0-fix-wave-1 accounting: OK=196 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 204
repros** (196 + 4 + 4 = 204; corpus total grows 200 → 204 by 3 comptime-arithmetic repros + 1
varargs tracking repro). OK 193→196 (repros 1+2 with emission-gap annotations + repro 3
reclassified OK+runtime-gap per P0-E); FAIL 3→4 (+1 = `fn_varargs_unsupported`, P0-D). Raw
classifier FAIL stays **8** (green-guards remain a sub-bucket of the raw count). The 4 real FAILs:
2 std-lib-deferred (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`self_embed_optional_cycle` (F-8 residual, gcc incomplete-type) + `fn_varargs_unsupported`
(parser varargs gap, `error[2000]`). The 4 green-guards unchanged: `eu_assign_incompat_payload`,
`field_access_optional`, `var_declared_void`, `euvoid_val_catch`. No other repro flipped.

## Task F7 — `comptime_u64_fold_overflow` (u64 const fold >2^32 masking) (2026-08-06) — +1 repro (204 → 205)

Operator ruling I1-A (serious bug): a u64-annotated const whose folded value exceeds 2^32
(`const X: u64 = 3000000000 * 2;` = 6000000000) gets typed I32 by the F4/F5 guard (bare binop
resolves TYPE_INT_LIT → remapped I32) and the `int_const` emitter masks the value to 32 bits →
wrong value (1705032704 / 0). Reproduced + FIXED in `main.zig` (commit `fix(F7): …`):

- **Root cause (2 defects, both in `main.zig` phase_SemanticAnalysis):**
  1. The declared type is stored on the var_decl node (`resolved_types[var_decl]`, set at
     main.zig:397), but is then **clobbered** to the init type (INT_LIT) by the unconditional
     `resolvedTypeTableSet(decls[di], init_type)` at main.zig:428-430 → the storage global
     (main.zig:639 reads `resolved_types[var_decl]`) is emitted `int` → truncates at the store.
  2. The F4/F5 fold guard types the temp from `resolved_types[binop]` (INT_LIT → I32); the
     declared u64 type is never threaded onto the init node for module-scope decls (fn-scope
     var_decls already get this at sema:1705-1708).
- **Fix (Option B, "B-lite"):** (a) gate the `resolved_types[var_decl] = init_type` write on
  `existing == null` so a known declared type is never clobbered (storage globals now type
  correctly); (b) mirror the fn-scope behavior — after resolving the module-scope init, set
  `resolved_types[child_1] = declared type` when the decl is annotated. The F4/F5 guard then
  reads the declared type (u64) with **no lower.zig change**. Verified: `1:1705032704
  3000000000 1:0` (was `0:1705032704 3000000000 0:0`).

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `comptime_u64_fold_overflow` | runtime-gap | **OK with runtime-gap annotation (pre-fix) → OK post-fix** — dump rc=0, 1 `.c`, gcc-clean, runs printing `0:1705032704 3000000000 0:0` (X=6000000000 and Z=4294967296 masked to 32 bits; Y=3000000000 control correct); post-fix prints `1:1705032704 3000000000 1:0`. Note: on -m32 `%lu` is 32-bit and `%llu` reads adjacent varargs slots pre-fix, so the repro prints each u64 as two i32 halves (`hi = @intCast(u64,X)>>32`, `lo = @intCast(u64,X) & @intCast(u64,4294967295)`) — see NOTES.md | F4/F5 guard types folded temps/storage globals from the binop's INT_LIT instead of the declared u64 |

**Post-F7 accounting: OK=197 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 205 repros**
(197 + 4 + 4 = 205; corpus grows 204 → 205 by `comptime_u64_fold_overflow`, counted OK).
Raw classifier FAIL stays **8** (4 green-guards + `field_store_drop`, `test_stub_0`
(std-lib-deferred), `self_embed_optional_cycle`, `fn_varargs_unsupported`). No other repro
flipped; 4 MD5 gates byte-identical; test_analyzer_bin PASS; build_test.sh 5/4 (baseline-identical).

## Task F8 — `comptime_const_chain` (ident_expr const-chain folding) (2026-08-06) — +1 repro (205 → 206)

Operator ruling I1-B ("include now"): `comptimeEvalEvaluate` must resolve `ident_expr` operands by
following const chains, so `const B: i32 = A + 5;` (where `const A: i32 = 30;`) folds to 35 and
`const C: i32 = B * 2;` folds to 70. Implemented in `comptime_eval.zig` as a depth-guarded
`ident_expr` branch (mirrors the array-size const-chain path `evalConstU32Full`,
type_resolver.zig:579-598: `symbolRegistryQualifiedLookup` across all module tables → const check
`(flags & 0x01) == 0` → recurse into `decl.child_1`), with a depth-16 cap so const cycles
(`const A = B + 1; const B = A + 1;`) cannot infinitely recurse.

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `comptime_const_chain` | **FAIL** (gcc error, NOT merely a fold gap) | **OK post-fix** — dump rc=0, 1 `.c`, gcc-clean, runs printing `3570`; emitted `__module_init` stores `zT_0 = 35;` / `zT_1 = 70;` (int_const, no runtime `+`/`*`) | Pre-F8 the lowerer emits `load_global` for `A` in `A + 5`, but `A` (a non-storage const, literal init) gets **no C storage-global decl** → `zG_..._A` undeclared → **gcc FAIL**. F8 folds the ident away so the load is eliminated. Also guards: const-chain through two hops (`B * 2` from `A + 5`) |

**Post-F8 accounting: OK=198 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 206 repros**
(198 + 4 + 4 = 206; corpus grows 205 → 206 by `comptime_const_chain`, counted OK; pre-F8 it
classified **FAIL**, so this is a genuine FAIL→OK flip). Raw classifier FAIL stays **8** (4
green-guards + `field_store_drop`, `test_stub_0` (std-lib-deferred), `self_embed_optional_cycle`,
`fn_varargs_unsupported`). No other repro flipped. **MD5 gate: gol RE-BASELINED** — the emitted C
for `examples/z98/game_of_life` changes because `@intCast(i32, WIDTH)` / `@intCast(i32, HEIGHT)`
(WIDTH/HEIGHT are `const usize`) now fold at comptime (previously a runtime `(int)` load+cast);
runtime output is byte-identical (verified by run diff), so per the F-5 AMENDMENT B precedent
("runtime behavior is the gate, not byte-identity") the gol baseline is updated from
`d0d3051d…` to `e2f4c625…`. mud/lisp/json gates unchanged and byte-identical.

---

## F9 — gate sweep + comptime gap annotations cleared (2026-08-06)

Final task of the comptime arithmetic folding plan. All 5 comptime-arithmetic repros are now fully
OK with their emission/runtime-gap annotations **cleared** — the gaps were resolved by F1-F8.
The full gate battery was re-run at HEAD with a fresh /tmp bootstrap (`/tmp/f9b/zig1`, zig0 rc=0,
gcc rc=0, 0 errors); evidence in `.superpowers/sdd/task-F9-report.md`.

**Fix commits (comptime arithmetic folding, all 2026-08-06):**

| Commit | Task | Change |
|--------|------|--------|
| `7dc119a6` | F1 | comptime_eval.zig: add `bit_and`/`bit_or`/`bit_xor`/`shl`/`shr` to `comptimeEvalBinOp` (with shift-amount >=64 → null guard) |
| `dacf8cf6` | F2 | comptime_eval.zig: add `bit_not` and route the 12 binary/unary ops to comptime binop evaluation (`comptimeEvalEvaluate` binop arm) |
| `94853c65` | F3 | main.zig `phase_ComptimeEvaluation`: fold `const var_decl` binop/unary **inits** (not just `builtin_call`) into `comptime_values` |
| `ec71f9ad` | F4 | lower.zig: `comptime_values` guards on the 10 binary op handlers (add/sub/mul/div/mod/bit_and/bit_or/bit_xor/shl/shr) with INT_LIT→I32 remap — emit `int_const` when folded |
| `5ed90251` | F5 | lower.zig: `comptime_values` guards on `negate` + `bit_not` unary handlers (same INT_LIT→I32 remap) |
| `6dd614e7` | F6 | type_resolver.zig array-size handler: add `mul`/`div`/`mod_op` arms to `evalConstU32Full` size eval (closes the `comptime_array_size_gap` silent type-drop) |
| `827e0221` | F7 | main.zig `phase_SemanticAnalysis`: (a) gate the `resolved_types[var_decl] = init_type` write on `existing == null` so declared types aren't clobbered; (b) thread the declared type onto the init node for annotated module-scope consts — folded u64 consts >2^32 keep their declared width (fixes `comptime_u64_fold_overflow`) |
| `bf5d3636` | F8 | comptime_eval.zig: `ident_expr` const-chain branch in `comptimeEvalEvaluateDepth` (depth-16 guarded), mirroring the array-size `evalConstU32Full` chain — folds `const B: i32 = A + 5` from `const A` (fixes `comptime_const_chain` gcc FAIL) |

**Gate-sweep results (measured, /tmp/f9b/zig1):**

- **Repros 1+2** (`comptime_binop_not_folded`, `comptime_lower_ignores_fold`): dump rc=0, gcc rc=0,
  run rc=0, prints `40 20 300 3 0 -30 10 30 20 120 7 -31`; `__module_init`-scoped
  `grep -c '[\*\/\%]'` = **0** (all 12 consts emit `int_const` — emission gap closed).
- **Repro 3** (`comptime_array_size_gap`): dump rc=0, gcc rc=0; emitted `typedef unsigned char
  …[4000];` / `…[40];` / `…[2];` — arrays resolve `u8[4000]`/`u8[40]`/`u8[2]` (runtime gap closed).
- **Repro u64** (`comptime_u64_fold_overflow`): dump rc=0, gcc rc=0, run prints
  `1:1705032704 3000000000 1:0` (X=6000000000, Z=4294967296 correct via hi:lo halves).
- **Repro** `comptime_const_chain`: dump rc=0, gcc rc=0, run prints `3570`; `__module_init` stores
  `zT_0 = 35;` / `zT_1 = 70;` (int_const, no runtime `+`/`*`).
- **Varargs** (`fn_varargs_unsupported`): stays **FAIL** — dump rc=2, `error[2000]: expected
  identifier but found token` at `...`, 0 `.c` emitted (out of comptime scope).
- **Full corpus**: **206 repros, OK=198 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0**
  (198 + 4 + 4 = 206; raw classifier FAIL = 8 — the 4 green-guards are a sub-bucket).
  FAIL count unchanged vs the F8 baseline; no repro flipped; the 4 real FAILs are the 2
  std-lib-deferred import gaps (`field_store_drop`, `test_stub_0` — `error[3048]`),
  `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type), and `fn_varargs_unsupported`
  (varargs parse gap).
- **4 MD5 gates byte-identical** to the current baselines: mud `4644ad1349c55af80fa1a18fe0e17989`,
  gol `e2f4c62515b4ab5e5c5b1202f7c2e12e`, lisp `dd56cd23984d2533eebd244ffe593791`,
  json `900cb401779aab11bcf22ce35100323c`.
- **test_analyzer_bin PASS** (43/43 tests ok, run rc=0).

This is the final accounting for the plan: **206 repros, OK=198 / FAIL=4 / green-guards=4** —
the comptime arithmetic folding feature is complete and gated.

---

## Task F1 — `@intCast` range-check (Option B + scope b) (2026-08-06) — +1 repro (206 → 207)

Per I1 (`/workspace/znineeight/.superpowers/sdd/I-intcast-range-report.md`) + operator ruling
(binding): the lowerer's explicit `@intCast` handler always set `is_checked=0`, so zig1 lowered
`@intCast(i32, i64_expr)` to a raw C `(int)` cast — silently wrapping on overflow (lisp `(fact 13)`
printed garbage `1932053504` instead of panicking). Fix site = **Option B** (c89_emit wraps via the
existing `int_cast.is_checked` field + source-aware per-pair `__bootstrap_<DST>_from_<SRC>` naming);
scope = **(b) full oracle rule** (check iff narrowing OR same-width reinterpret).

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `intcast_range_check` | runtime-gap: dump rc=0, gcc clean, prints `-2147483648` (wrapped), rc=0 — **NO panic**; emitted `zT_6 = (int)i;` | **OK post-fix** — dump rc=0, 1 `.c`, gcc-clean; emitted `zT_6 = __bootstrap_i32_from_i64(i);`; run PANICS with `panic: integer cast overflow in @intCast`, nonzero exit (rc=134) — the intended fix, matching the zig0 oracle | guards: the in-range path must still pass (i32-from-i64 of a small value prints correctly); comptime-folded `@intCast` literals skip the runtime cast; pure widening stays a raw cast |

**Implementation:** lower.zig computes src type via `getTempType` and sets `is_checked=1` when
`src_bits > dst_bits` OR (`src_bits == dst_bits` AND signedness differs); c89_emit's `.int_cast`
checked arm builds `__bootstrap_<DST>_from_<SRC>` from `c.target` + `getTempTypeByIndex`; the 19
oracle helpers were added to `sf/src/include/zig_runtime.c` (definitions) + `sf/src/include/
zig_runtime.h` (C89 `static` definitions, per-TU self-sufficient — the oracle's own header pattern
is `ZIG_INLINE ZIG_UNUSED`), message standardized to `"integer cast overflow in @intCast"`.
`std_checked_cast_*` (upper-bound-only, false-panics on negatives) is NOT used.

**Post-F1 accounting: OK=199 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 207 repros**
(199 + 4 + 4 = 207; corpus grows 206 → 207 by `intcast_range_check`, counted OK — no FAIL
increase). Raw classifier FAIL stays **8**. No other repro flipped.

**MD5 gate — ALL 4 RE-BASELINED (scope b):** mud, gol, lisp, json each contain explicit runtime
`@intCast` sites that are now checked. New values: mud `0064a08149b07aa591033210ffce68f5`,
gol `51d6d078bdecad022318bded23182f72`, lisp `e54be381967cab4a3f0886e106166771`,
json `6528f26f396092976b46938482a4f0d4`. Runtime-verified identical except lisp `(fact 13)` now
PANICS (the intended fix); per the F-5 AMENDMENT B precedent ("runtime behavior is the gate, not
byte-identity"). Per-gate helper counts: mud `i32_from_usize` x4 + `usize_from_i32` x1; gol
`i32_from_usize` x2 + `usize_from_i32` x2; lisp `i32_from_i64`, `i32_from_u32`, `i32_from_usize`,
`u32_from_i32`, `u8_from_i32`, `usize_from_i32`, `c_char_from_u8`; json `usize_from_i32` x1.
(json's legacy-runtime link — `src/runtime/zig_runtime.c` — lacks the new helpers, so the header
`static` definitions are what make the multi-module json gate link; mud/gol/lisp additionally link
the extern defs in `sf/src/include/zig_runtime.c`.)

## Task F2 — `ice_literal_overflow` (u64-safe int_literal marker) (2026-08-06) — +1 repro (207 → 208)

The `int_literal` lowering marker (`ILR:i … v<value>`) called
`itoa_mod.itoa(@intCast(u32, val), …)` with `val` the u64 literal value. Since
F1's `@intCast` range-check, that cast lowers to the checked
`__bootstrap_u32_from_u64`, so any program that runtime-lowers a literal >= 2^32
aborted the compiler itself (`PANIC: integer overflow in @intCast`), dump rc=134.
The lowering pipeline is correct — only the marker was broken. Fixed by adding
`pal.markerWriteInt64` (itoa64, `[24]u8` buffer) and using it for the value marker.

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `ice_literal_overflow` | **ICE** (dump rc=134, SIGABRT) | **OK post-fix** — dump rc=0, 1 `.c`, gcc-clean, runs printing `1:705032704 1:0` (correct hi/lo halves of X=5000000000 and Y=4294967296) | guards: any literal >= 2^32 that reaches runtime lowering must not crash the compiler; the `--markers` ILR trace renders the full u64 value (`ILR:i39v5000000000`) |

**Note on repro form:** the brief's exact const-only source (`pub const X: u64 =
5000000000;` + `print_u64(X)`) does NOT reproduce the ICE on the current tree —
F8's ident_expr const-chain fold resolves `X` at comptime, so the literal never
reaches the `int_literal` runtime-lowering marker. The repro keeps the brief's
consts (the program still contains literals >= 2^32) AND adds a runtime-lowered
literal (`var sink: u64 = 5000000000;`) that exercises the marker path. Pre-fix
the repro dumps rc=134; post-fix rc=0. See `ice_literal_overflow/NOTES.md`.

**Post-F2 accounting: OK=200 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over
208 repros** (200 + 4 + 4 = 208; corpus grows 207 → 208 by `ice_literal_overflow`,
counted OK — the pre-fix ICE becomes a clean post-fix OK, so no FAIL increase).
Raw classifier FAIL stays **8**. The 4 real FAILs unchanged:
`field_store_drop` + `test_stub_0` (std-lib-deferred, `error[3048]`),
`self_embed_optional_cycle` (F-8 residual), `fn_varargs_unsupported` (varargs
parse gap). **4 MD5 gates byte-identical** (markers → stderr only; emitted C
unchanged): mud `0064a08149b07aa591033210ffce68f5`, gol
`51d6d078bdecad022318bded23182f72`, lisp `e54be381967cab4a3f0886e106166771`,
json `6528f26f396092976b46938482a4f0d4`. test_analyzer_bin PASS.

---

## Task F5 — varargs end-to-end (`@cVaStart`/`@cVaArg`/`@cVaEnd` + `...` emission + extern prototypes) (2026-08-06) — +1 repro (208 → 209)

4-item compiler-gaps plan Task F5 (`.superpowers/sdd/task-F5-brief.md`). Full
varargs support: Z98 variadic fn bodies read their `...` args via `va_list` +
`@cVaStart`/`@cVaArg`/`@cVaEnd`; `...` is emitted in C fn prototypes; variadic
externs get C prototypes (Option B); `stdarg.h` is emitted gated on actual
`va_*` usage.

| Repro | RED (pre-fix) | Classification (measured, /tmp/zigf5b/zig1) | Guards |
|-------|---------------|---------------------------|--------|
| `fn_varargs_unsupported` | parse gap → F3 OK but no prototype emission | **OK post-F5** — dump rc=0; emitted header carries the Option B extern prototype `int printf(unsigned char*, ...);` (name-passthrough); no `stdarg.h` (no `va_*` use); gcc-clean, links + runs rc=0 | variadic extern must get a C prototype; no `@cInclude`'d header may conflict with it |
| `fn_varargs_body` (NEW) | n/a (new repro) | **OK** — dump rc=0; emitted `#include <stdarg.h>`, `int zF_..._sum(unsigned int count, ...) {`, `va_start(zL_vl, zL_count);`, `zT_11 = va_arg(zL_vl, int);`, `va_end(zL_vl);`, `int printf(unsigned char*, ...);`; gcc-clean; runs printing `sum=60` (the KEY proof `sum(3, 10, 20, 30)` = 60 via `@cVaArg`), rc=0 | a Z98 variadic body must read args; no `@cInclude("<stdio.h>")` with a variadic printf (type conflict `unsigned char*` vs `const char*`) |

**Implementation summary:**
- lower.zig: `@cVaStart`/`@cVaArg`/`@cVaEnd` name_ids in `lowererInit`;
  builtin dispatch inserted after `@ptrToInt`, before the `ec.len>=2` cast
  block; `lowerFn` reads `FnPayload.flags_packed` (bit0) → `func_ptr.is_variadic`
  (the `child_0==0` anytype-marker branch is **kept as a defensive OR**, NOT
  removed — see deviations below).
- c89_emit.zig: 3 emitting `.va_start`/`.va_arg`/`.va_end` arms; `stdarg.h`
  gated on any `va_*` LirInst in the TU at 3 sites (emitModuleHeader,
  emitModuleHeaderFile, emitModuleFile); `emitFunctionForwardDecl`
  name-passthrough for externs; the two extern-prototype guards
  (`:1962`/`:2108`-era) now `is_extern==0 OR is_variadic!=0`.

**Deviations from the brief's literal text (both REQUIRED to keep the 4 MD5
gates byte-identical — see Task F5 report):**
1. **`lower.zig:4680` child_0==0 branch is kept as a defensive no-op-instead-of
   removal.** The brief premised "no gate has a variadic fn"; in fact **mud and
   gol both define `print(fmt, *const c_char, args: anytype)`** (anytype →
   `child_0==0` param) whose C signature relies on the marker branch emitting
   `...` (`void zF_..._print(char*, ...);` is in both baselines). Making it a
   pure no-op deletes `...` from those signatures → mud/gol MD5 drift + gcc
   break. Kept as an OR with the flags_packed read (true `...` still works).
2. **`stdarg.h` gating is on actual `va_*` LIR insts, not on `is_variadic`.**
   The brief's premise "no gate has a variadic fn" is also wrong for mud/gol
   (their anytype-print has `is_variadic=1` but never uses `va_*`); gating on
   `is_variadic` would inject `#include <stdarg.h>` into mud/gol → MD5 drift.
   Gating on `va_*` insts keeps mud/gol/lisp/json byte-identical AND still
   emits `stdarg.h` for real varargs bodies.

> **F5b RESOLUTION (Task F5b, AMENDMENT 5, 2026-08-06, commit `ef529f42`):**
> deviation 1 is now MOOT. F5b migrated mud/gol `print(fmt, args: anytype)` to a
> true trailing `...` (`print(fmt, ...)`) and **deactivated** the `child_0==0`
> anytype-marker branch (its `else { is_variadic = 1 }` was removed from
> `lowerFn`) — `is_variadic` now comes solely from the F3 flag-bit path
> (`FnPayload.flags_packed` bit0, set by parser flag 0x01 via
> type_resolver.zig:1126-1127). mud/gol re-baselined to `50beb1bf…` /
> `0d8f0092…` (runtime byte-identical, AMENDMENT B precedent); lisp/json
> unchanged. Deviation 2 (stdarg.h gating on actual `va_*` insts) remains in
> force. A variadic fn with ZERO fixed params (`fn f(...)`) is now rejected
> `error[3012]` (final-review fix, 2026-08-06).

**Post-F5 accounting: OK=202 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over
209 repros** (202 + 4 + 3 = 209; corpus grows 208 → 209 by `fn_varargs_body`;
`fn_varargs_unsupported` FAIL→OK). Raw classifier FAIL stays **7** (4
green-guards sub-bucket). The 3 real FAILs: `field_store_drop` + `test_stub_0`
(std-lib-deferred, `error[3048]`) + `self_embed_optional_cycle` (F-8 residual).
**4 MD5 gates byte-identical**: mud `e306b1874e51e06a23b708bcd79fec6d`, gol
`51d6d078bdecad022318bded23182f72`, lisp `55044a1f64011bc644cddbcf73b5de93`,
json `b5f56ebd51d2f0fcd379a1e083594462`. test_analyzer_bin PASS.

---

## Task F7 — gate sweep + docs + final review prep (2026-08-06) — 4-item plan CLOSEOUT

Final task of the 4-item compiler-gaps plan (brief `.superpowers/sdd/task-F7-brief.md`). Full
corpus + MD5 gate sweep at HEAD with a fresh /tmp bootstrap (`/tmp/f7build/zig1`, zig0 rc=0, gcc
rc=0, 0 errors); evidence in `.superpowers/sdd/task-F7-report.md`. **Docs-only — no sf/src
changes.**

**Final accounting (measured): 209 repros, OK=202 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
(202 + 4 + 3 = 209; raw classifier FAIL = 7). Identical to the v20 totals — **no repro flipped**
during the final sweep. The plan's Step-1 prediction ("210 repros, OK=200/FAIL=3/gg=4") was
**STALE**: it double-counted `fn_varargs_unsupported`, which was already in the 208 baseline
(209 = 208 baseline + `fn_varargs_body`). The corrected accounting is recorded in the Totals
section at the top of this file.

**4-item fixes — all complete (fix refs):**

| # | Item | Fix | Key commit(s) | Gate evidence |
|---|------|-----|---------------|---------------|
| 1 | `@intCast` narrowing + reinterpret range-check | c89_emit emits `__bootstrap_<DST>_from_<SRC>` (checked) — see Task F1 section | `14f31511` | `intcast_range_check` OK; run PANICS (`integer cast overflow in @intCast`) rc=134, matching oracle |
| 2 | ICE on literals ≥ 2^32 | u64-safe `int_literal` marker via `pal.markerWriteInt64` — see Task F2 section | `5d280a6d` | `ice_literal_overflow` OK; prints `1:705032704 1:0` rc=0 |
| 3 | Full varargs (`@cVaStart`/`@cVaArg`/`@cVaEnd` + `va_list` + `...` emission + extern variadic prototypes) — see Task F5 section | `4448d187` (parser bit0 flag), `b8deb732` (va_list TYPE_VA_LIST=21 + LIR), `c420a277` (emission), `ef529f42` (F5b) | `fn_varargs_unsupported` FAIL→OK (runs `printf`); `fn_varargs_body` OK — **`sum=60`** rc=0 |
| 4 | Lisp closures capture current env | `eval.zig:124` `env_to_value(env.*,…)` → `curr_env.*` — see `examples/z98/lisp_interpreter_curr/NOTES.md` | `0cb7891c` | `((make-adder 5) 3)`→8, `((add 10) 1)`→11, `((make-func 42))`→42 (were `UnboundSymbol`) |

**MD5 gates (byte-identical to the current baselines — no re-baseline needed):**
mud `50beb1bf5edc4cbb638f84aa027ffade`, gol `0d8f0092c22c04375482a198691a3957`,
lisp `605b597e8b7cff60de0ce84a0593e743`, json `b5f56ebd51d2f0fcd379a1e083594462`.

**Runtime spot-checks (this sweep):** `fn_varargs_body` → `sum=60` rc=0; `intcast_range_check` →
rc=134 `panic: integer cast overflow in @intCast` (the intended fix); `ice_literal_overflow` →
`1:705032704 1:0` rc=0; lisp closures `8`/`11`/`42`; `((twice square) 3)` → SEGFAULT (rc=139);
`(fact 13)` → rc=134 (F1 range-check, intended).

**Known lisp limitations (documented in lisp NOTES.md — NOT compiler defects, operator-accepted):**
`((twice square) 3)` / `((compose square square) 3)` SEGFAULT (env-capture cycle in lisp source,
exposed by the F6 fix — was `UnboundSymbol`); `(countdown 3000)` OOM (~3000 threshold); post-OOM
REPL dead (no `sand_reset` on the error path); `(fact 13)` PANICS (correct — F1 range check).

No other repro flipped; `fn_varargs_unsupported` stays OK; 4 MD5 gates byte-identical;
`test_analyzer_bin` PASS (from prior F-tasks). This is the **final accounting for the plan**.

---

## I-task: rogue_mud build attempt — labeled_stmt frontend gap (2026-08-07) — +1 repro (209 → 210)

Investigation task: attempt to build `examples/z98/rogue_mud/` with the current zig1
(`/tmp/zigaps/zig1`, fresh HEAD bootstrap 2026-08-07, zig0 rc=0, gcc rc=0, 0 errors). The
pre-analysis predicted SUCCESS (all patterns well-tested + the catch-block-expression fix P3-4/P3-7);
the actual dump FAILS at type resolution.

| Repro | RED (measured) | Classification | Guards |
|-------|----------------|----------------|--------|
| `labeled_stmt_unhandled` | dump rc=2, `error[3020]: internal error: unhandled node kind in type resolution`, 0 `.c` emitted | **FAIL** (real frontend gap; rc=2 + `error[3020]` is outside the ICE regex — not an ICE, not a green-guard) → **OK post-F1 (2026-08-07)** — dump rc=0, 1 `.c`, gcc-clean, links, runs rc=0 and TERMINATES (the labeled `break :game_loop` now matches the loop via `current_label` propagation; pre-fix it was a no-op and `while(true)` HUNG) | `semanticAnalyzerResolveStmtIter` (semantic_analyzer.zig:1599-1778) has no `labeled_stmt` (AstKind 82) case → generic `else` (:1773) forwards to `resolveExpr` → unhandled-else (:1424-1429) emits error[3020]. Correct behavior: unwrap the label and push the wrapped child onto the stmt work stack — now implemented (parser.zig + semantic_analyzer.zig + lower.zig; see Task F1 section below) |

**Dump diagnostics (rogue_mud):** 2× `error[3020]`, one per labeled statement in the program —
`main.zig:92` `game_loop: while (true)`, `lib/scenario.zig:59` `bsp_loop: while (stack.len > 0)`.
Both are the SAME distinct failure (kind 82). The reported locations (`main.zig:32:2`,
`scenario.zig:159:8`) are BOGUS — the 3020 diagnostic passes `node_idx` as both span ends
(semantic_analyzer.zig:1428), so the reported file:line never matches the labeled statement.
Note: other latent rogue_mud gaps may hide behind this blocker (unverifiable without a fix); the
labeled_stmt gap is the only DISTINCT failure actually observed.

**Oracle verification:** `./sf/build/zig0 -o out.c repro` accepts the labeled loop (rc=0, emits C)
— labeled statements are valid Z98, so this is a genuine compiler gap, not a correct rejection.
zig1 dump for the repro: rc=2, `error[3020]`, 0 `.c` (markers `ST:N<node> ST:K82`).

**Post-repro accounting: OK=202 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 210 repros**
(202 + 4 + 4 = 210; corpus grows 209 → 210 by `labeled_stmt_unhandled`, counted FAIL). Raw
classifier FAIL **7 → 8** (green-guards remain a sub-bucket of the raw count). The 4 real FAILs:
2 std-lib-deferred (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`self_embed_optional_cycle` (F-8 residual, gcc incomplete-type) + `labeled_stmt_unhandled`
(error[3020], sema labeled_stmt gap). The 4 green-guards unchanged:
`eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
No existing repro flipped. Investigation complete — no compiler fixes made.

---

## Task F1 — labeled statement support in parser, sema, lowerer (2026-08-07) — FAIL→OK

The `labeled_stmt_unhandled` repro (added 2026-08-07 by the rogue_mud I-task) is now **OK**:
`game_loop: while (true) { break :game_loop; }` dumps, compiles, links, and **runs rc=0 and
TERMINATES** (pre-fix the labeled `break :game_loop` matched no loop and was a no-op, so the
`while(true)` HUNG at runtime). 5 edits in 3 files (plan `labeled statement support implementation
plan` `37e1892a`, AMENDMENT 1 `50723411`):

1. **Parser (parser.zig:1285 + :1299):** `parserParseLabeledStmt` + `parserParseLabeledBlockExpr`
   now store `label_tok.value.string_id` in the `labeled_stmt` node payload (was hardcoded `0`),
   so `break :label` / `continue :label` can match it.
2. **Sema stmt dispatcher (semantic_analyzer.zig:1767):** `labeled_stmt` case added to
   `semanticAnalyzerResolveStmtIter` before `defer_stmt` — transparent unwrap: pushes
   `node.child_0` onto the stmt work queue (mirrors the defer_stmt unwrapper); one case covers
   while/for/block/if/switch inner kinds.
3. **Sema expr redirect (semantic_analyzer.zig:1341):** `labeled_stmt` added to the
   var_decl/defer/errdefer branch → delegates back to `semanticAnalyzerResolveStmtIter`
   (defensive; prevents the `error[3020]` unhandled-else crash if a labeled_stmt ever reaches
   resolveExpr).
4. **Lowerer unwrap (lower.zig:3516):** `labeled_stmt` case in `lowerStmt` recurses into
   `node.child_0`, saving/setting/restoring `self.current_label = node.payload` around the
   recurse.
5. **Edit 4b — label propagation (AMENDMENT 1, required):** `LirLowerer` gains `current_label:
   u32` (init 0); all 3 loop-push sites (while :3627, for-range :3726, for-slice :3780) now use
   `.label_id = self.current_label` instead of hardcoded `0`. The original 4-edit version was
   verified unsatisfiable (labeled break matched no `LoopInfo` → runtime no-op → hang); the
   operator ruling amended the plan to add edit 4b, which the F1 implementer prototyped + verified,
   then reverted pending ruling. Re-applied here.

**Gate evidence (measured, /tmp/zlbl/zig1):**

- Repro `labeled_stmt_unhandled`: dump rc=0, 1 `.c` emitted, gcc rc=0, link rc=0, **run rc=0 and
  TERMINATES** (the hang was the bug).
- Nested-labels probe `outer: while (true) { inner: while (true) { i += 1; if (i < 3) { continue
  :inner; } break :outer; } }` + `if (i != 3) @panic("FAIL")`: dump rc=0, gcc rc=0, link rc=0,
  run rc=0 (assertion passes — `continue :inner` re-loops, `break :outer` exits the outer loop).
- 4 MD5 gates **byte-identical**: mud `50beb1bf5edc4cbb638f84aa027ffade`, gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462`.
- test_analyzer_bin **PASS** (`Analyzer tests passed`); build_test.sh 5/4 (baseline-identical).
- Corpus: 210 repros, **OK=203 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0** (203+3+4=210; raw
  classifier FAIL **8 → 7**). Only flip: `labeled_stmt_unhandled` FAIL→OK. The 3 remaining FAILs:
  2 std-lib-deferred (`field_store_drop`, `test_stub_0`, `error[3048]`) +
  `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). 4 green-guards unchanged.

**Documented scope limit (accepted, not fixed):** `break :label` out of a labeled NON-LOOP block
(`lbl: { break :lbl; }`) remains unsupported — the break/continue handlers (`lower.zig:4005-4044`)
search only `loop_stack`, and a labeled block never pushes a `LoopInfo`. Loop labels
(`label: while` / `label: for`) are fully supported; out of this repro's scope (loop case only).

**Accounting: OK=203 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 210 repros** — see the
Totals section at the top.

---

## Task F1 — duplicate-typed struct fields emit correctly (dup field topo-sort) (2026-08-07) — +2 repros (210 → 212)

The `dup_optptr_field_emit` + `dup_val_field_emit` repros (added 2026-08-07 by the rogue_mud
I-task, per `.superpowers/sdd/I-rogue-dupfld-report.md`) are now **OK**. Both previously failed
gcc with `unknown type name 'zT_...'`: the `tstTopologicalSort` Kahn algorithm dropped the struct
from the `sorted` array, so its forward-decl and body were never emitted while the lowerer still
referenced the type by name.

- **Root cause:** `tstEdgesCount` (`sf/src/c89_emit.zig:799-839`) counted **one edge per field
  occurrence**, so a struct with two same-typed edge-forming fields (`a: Point, b: Point`;
  `left: ?*Node, right: ?*Node`) got `indegree = 2`. The Kahn dequeue loop (`:960-968`)
  decremented **once per dependent type** (`tstIsDep` boolean, `:961`), leaving indegree 1 → the
  struct was never dequeued → dropped from `sorted` → no fwd-decl/body → gcc `unknown type name`.
- **Fix (Option B, operator ruling):** `tstEdgesCount` now counts each distinct dependent type
  **once** — deduped same-typed field edges in the struct/tagged_union/union branches, including
  dedupe of `tag_type` vs fields in the tagged_union branch. New helper `tstSeenInRange`
  (c89_emit.zig:799-805) scans the field range for an already-counted type id. Mirrored in
  `tstEdgesFill` (dead code, 0 callers — zero runtime effect) for consistency. Indegree now equals
  "number of distinct dep types" == the count of `tstIsDep`-true decrements, so count and dequeue
  can never drift; Kahn drains fully, which also eliminates the uninitialized-`sorted`-tail hazard
  (`sandAlloc` does not zero) for this pattern.
- **Files:** `sf/src/c89_emit.zig` (commit `fix: duplicate-typed struct fields emit correctly
  (dup field topo-sort)`).

**Gate evidence (measured, /tmp/zf1/zig1 — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors):**

- `dup_val_field_emit`: dump rc=0, 1 `.c`, gcc-clean, link rc=0, run rc=0;
  `zig_special_types.h` now carries the `zT_9808F547_Line` fwd-decl + body (`zT_EAA8EF31_Point a;`
  / `b;`).
- `dup_optptr_field_emit`: dump rc=0, 1 `.c`, gcc-clean, link rc=0, run rc=0;
  `zT_3468032D_Node` fwd-decl + body now emitted.
- 4 MD5 gates **byte-identical**: mud `50beb1bf5edc4cbb638f84aa027ffade`, gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462` (no gate program has duplicate edge-forming field types).
- Full corpus sweep (216 dirs, /tmp/zf1/zig1): **OK=206 / FAIL=10 (raw) / ICE=0 / CRASH=0**. Of the
  raw FAIL=10: 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`) + 3 real baseline FAILs (`field_store_drop`,
  `test_stub_0`, `self_embed_optional_cycle`) + 3 I-task repros for the other gaps
  (`undef_arr_struct_literal`, `xmod_pub_const_global`, `switch_mixed_case_argtype` — stay FAIL
  until F2/F3/F4).
- **F1 accounting: 210 → 212 repros, OK=205 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
  (205 + 3 + 4 = 212; raw classifier FAIL stays **7**). Only flip:
  `dup_optptr_field_emit` + `dup_val_field_emit` FAIL→OK. The 3 remaining FAILs: 2
  std-lib-deferred (`field_store_drop`, `test_stub_0`, `error[3048]`) +
  `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). 4 green-guards unchanged. No
  existing repro flipped. See the Totals section at the top.

---

## Task F2 — undefined struct-array field init emits valid C (undef_arr_struct_literal) (2026-08-07) — +1 (212 → 213)

The `undef_arr_struct_literal` repro (added 2026-08-07 by the rogue_mud I-task, per
`.superpowers/sdd/I-rogue-undefarr-report.md`) is now **OK**. It previously failed gcc with
`incompatible types when assigning to type 'zT_..._Client' from type 'int'`: the emitted C
expanded the `undefined` initializer of the `[5]Client` field into a zero-fill loop
`clients[_j] = 0;` — ill-typed for struct elements.

- **Root cause:** `emitFieldAssign` (`sf/src/c89_emit.zig:276-287`) hardcodes
  `base.fld[_j] = 0;` for ALL array-valued fields, never checking the element type or the `src`
  temp — only valid for scalar elements. The zig0 oracle emits NOTHING for `undefined` array
  fields (struct and primitive elements, verified).
- **Fix (Option A, operator ruling):** in the LOWERER (upstream, matches the oracle exactly),
  `sf/src/lower.zig` now skips the `assign_field` for a struct-literal field entirely when the
  field value is `undefined_literal` AND the field's declared type is `array_type`. A pre-scan at
  `lower.zig:2988-3027` sets `is_undef_arr_field` (struct + tagged-union kinds); the tagged-union
  payload branch (`:3063-3068`) and the struct branch (`:3072-3081`) both skip the
  `emitInst(assign_field)`. Skipping the field value's `lowerExpr` also drops the dead
  `undefined_const` temp (`zT_4 = 0;`). Emitter untouched.
- **Gate consequence (operator-approved re-baseline, F-5 AMENDMENT B precedent):** **mud
  RE-BASELINED** — `examples/z98/mud_server/main.zig:159` `.buffer = undefined` (`[256]u8`
  primitive array) drops its dead zero-fill (was `/tmp/mud_gate.c:800-802`). Runtime verified
  IDENTICAL: new mud prints "MUD server listening on port 4000" and exits rc=124 (timeout),
  matching the pristine build. New mud MD5 `906fa59c8676bb1054d3fcc13704fce5` (was
  `50beb1bf...`). gol/lisp/json byte-identical (no struct-literal `undefined` array fields).
- **Files:** `sf/src/lower.zig` (commit `fix: undefined struct-array field init emits valid C
  (undef_arr_struct_literal)`).

**Gate evidence (measured, /tmp/zf2/zig1 — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors):**

- `undef_arr_struct_literal`: dump rc=0, 1 `.c`, gcc-clean, link rc=0, run rc=0. Emitted C is
  just `zT_1.listen_socket = zT_3;` — no `clients[_j] = 0` zero-fill, no dead `undefined_const`
  temp.
- 4 MD5 gates: mud `906fa59c8676bb1054d3fcc13704fce5` (RE-BASELINED, runtime-verified
  identical — "MUD server listening on port 4000", rc=124), gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462` — the latter three byte-identical.
- Full corpus sweep (216 dirs, /tmp/zf2/zig1): **OK=207 / FAIL=9 (raw) / ICE=0 / CRASH=0**. Of
  the raw FAIL=9: 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`) + 3 real baseline FAILs (`field_store_drop`,
  `test_stub_0`, `self_embed_optional_cycle`) + 2 I-task repros for the other gaps
  (`xmod_pub_const_global`, `switch_mixed_case_argtype` — stay FAIL until F3/F4).
- **F2 accounting: 212 → 213 repros, OK=206 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
  (206 + 3 + 4 = 213; raw classifier FAIL stays **7**). Only flip:
  `undef_arr_struct_literal` FAIL→OK. The 3 remaining FAILs: 2 std-lib-deferred
  (`field_store_drop`, `test_stub_0`, `error[3048]`) + `self_embed_optional_cycle` (F-8
  residual, gcc incomplete-type). 4 green-guards unchanged. No existing repro flipped. See the
  Totals section at the top.

---

## Task F3 — cross-module pub const resolves (xmod_pub_const_global) (2026-08-07) — +1 (213 → 214)

The `xmod_pub_const_global` repro (added 2026-08-07 by the rogue_mud I-task, per
`.superpowers/sdd/I-rogue-xmodconst-report.md`) is now **OK**. It previously failed gcc with
`'zG_..._COLOR_WHITE' undeclared`: the cross-module `pub const` literal-init
(`pub const COLOR_WHITE: u8 = 7`) registers as `SymbolKind.global` but gets NO F-7 storage slot
(main.zig:616-660 skips literal-init consts, bit0=mutable only), so there is no definition in the
owner `.c` and no extern in the module header, and the consumer's `load_global` read referenced an
undeclared `zG_` name.

- **Root cause:** lower.zig:2005-2011 (the cross-module `SymbolKind.global` module-field-access
  branch) unconditionally lowered every module-qualified global reference to `load_global`,
  never consulting the const bit or the decl init.
- **Fix (Option C, operator ruling):** `sf/src/lower.zig` — the cross-module
  `SymbolKind.global` branch now, when `(ts.flags & 0x01) == 0` (const) and the target's
  `decl_node.child_1` init is an int/float/char literal, emits the corresponding
  `int_const`/`float_const` typed at the DECLARED type (`gbl_tid` from
  `resolvedTypeTableGet(resolved_types, ts.decl_node)`, i.e. `u8` not `TYPE_U32` — avoids the F-7
  u64-width regression class), mirroring the same-module literal fold at lower.zig:1681-1710. The
  `load_global` fallback is retained for non-literal consts (already storage-classified via
  main.zig:627). No bare `zG_` definition emitted (zero-init trap avoided).
- **Gate consequence:** none — **4 MD5 gates byte-identical** (mud `906fa59c…`, gol `0d8f0092…`,
  lisp `605b597e…`, json `b5f56ebd…`; no gate program has a cross-module scalar `pub const`).
- **Files:** `sf/src/lower.zig` (commit `fix: cross-module pub const resolves (xmod_pub_const_global)`).

**Gate evidence (measured, /tmp/zf3/zig1 — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors):**

- `xmod_pub_const_global`: dump rc=0, 2 `.c`, per-file gcc-clean, link rc=0, run rc=0. Emitted C
  folds both refs: `zT_3 = 7;` (`fg`), `zT_5 = 7;` (`cell.fg`), `zT_4 = 0;` (`bg`), typed
  `unsigned char`; colors.c stays `/* EOF */`.
- 4 MD5 gates: mud `906fa59c8676bb1054d3fcc13704fce5`, gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462` — all four byte-identical, no re-baseline.
- Full corpus sweep (216 dirs, /tmp/zf3/zig1): **OK=208 / FAIL=8 (raw) / ICE=0 / CRASH=0**. Of
  the raw FAIL=8: 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`) + 3 real baseline FAILs (`field_store_drop`,
  `test_stub_0`, `self_embed_optional_cycle`) + 1 I-task repro (`switch_mixed_case_argtype` —
  stays FAIL until F4).
- **F3 accounting: 213 → 214 repros, OK=207 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
  (207 + 3 + 4 = 214; raw classifier FAIL stays **7**). Only flip:
  `xmod_pub_const_global` FAIL→OK. The 3 remaining FAILs: 2 std-lib-deferred
  (`field_store_drop`, `test_stub_0`, `error[3048]`) + `self_embed_optional_cycle` (F-8
  residual, gcc incomplete-type). 4 green-guards unchanged. No existing repro flipped. See the
  Totals section at the top.

---

## Task F4 — switch mixed-case call-arg typing (switch_mixed_case_argtype) (2026-08-07) — +1 (214 → 215)

The `switch_mixed_case_argtype` repro (added 2026-08-07 by the rogue_mud I-task, per
`.superpowers/sdd/I-rogue-switcharg-report.md`) is now **OK**. It previously failed gcc with
`error: incompatible type for argument 1/3 of 'zF_..._saveDungeon'`: the `&arena` arg temp was
`unsigned int` and the string-literal temp `char*` instead of `Sand*` / `Slice_u8`.

- **Root cause (I4, confirmed):** NOT `call_arg_types` corruption — a **sema mid-switch abort**.
  The MIX else-branch at `semantic_analyzer.zig:1167` did `return type_mod.TYPE_VOID;` when two
  prong bodies had non-coercible types (assignment `dx = 0` → i32 vs empty block `{}` → void),
  aborting `semanticAnalyzerResolveSwitchExpr` and skipping all prongs *after* the conflict. The
  call prong (`'v','V'`) was therefore never sema'd, so the fixed-param loop at
  `semantic_analyzer.zig:775` never populated `call_arg_types`, and the lowerer fallback
  (`lower.zig:2388`) typed the arg slots as raw lowered types (`unsigned int` for `&arena`,
  `char*` for the string literal).
- **Fix (Option A, operator ruling):** `semantic_analyzer.zig:1167` — replaced `return
  type_mod.TYPE_VOID;` with `continue;` (skip this prong's contribution to the switch's `unified`
  type but keep resolving the remaining prongs, so the call prong IS sema'd and `call_arg_types`
  is populated normally). Kept the `resolvedTypeTableSet(..., TYPE_VOID)` on the same line
  (stmt-switch resolved type is unused). Lowerer untouched (the 4 call-arg paths were NOT the bug).
- **Gate evidence (measured, /tmp/zf4/zig1 — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors):**
  - `switch_mixed_case_argtype`: dump rc=0, 2 `.c` emitted, per-file gcc-clean, link rc=0, run
    rc=0. Emitted arg temps now correctly typed: `zT_3E40CD83_Sand* zT_24;`,
    `zT_8F083A69_Slice_zT_0B42B2F8_u zT_26;`, string literal built into a `Slice`.
  - 4 MD5 gates **byte-identical**: mud `906fa59c8676bb1054d3fcc13704fce5`, gol
    `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
    `b5f56ebd51d2f0fcd379a1e083594462` (I4 measured the same; gol/lisp MIX aborts are
    pre-existing and emit no coercion-needing skipped call).
  - Full corpus sweep (216 dirs, /tmp/zf4/zig1): **OK=209 / FAIL=7 (raw) / ICE=0 / CRASH=0**. Of
    the raw FAIL=7: 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`,
    `var_declared_void`, `euvoid_val_catch`) + 3 real baseline FAILs (`field_store_drop`,
    `test_stub_0`, `self_embed_optional_cycle`). Only flip: `switch_mixed_case_argtype` FAIL→OK.
  - test_analyzer_bin **PASS** (`Analyzer tests passed`, run rc=0).
- **F4 accounting: 214 → 215 repros, OK=208 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
  (208 + 3 + 4 = 215; raw classifier FAIL stays **7**). Only flip:
  `switch_mixed_case_argtype` FAIL→OK. The 3 remaining FAILs: 2 std-lib-deferred
  (`field_store_drop`, `test_stub_0`, `error[3048]`) + `self_embed_optional_cycle` (F-8
  residual, gcc incomplete-type). 4 green-guards unchanged. No existing repro flipped. See the
  Totals section at the top.
- **Files:** `sf/src/semantic_analyzer.zig` (commit `fix: switch mixed-case call-arg typing
  (switch_mixed_case_argtype)`).
- **Known adjacent bug (out of scope, documented follow-up):** char-literal switch `case` labels
  are still dropped at `lower.zig:3858-3860` (stmt switch) / `:3121-3123` (expr switch; refs superseded — actual sites lower.zig:3183 expr / :3920 stmt), so this
  repro's emitted `switch (c)` has no `case` labels and its body is **unreachable at runtime**
  (always takes `default`). The F4 runtime gate passes only because the repro prints nothing and
  `c != -1` is false. This affects `rogue_mud`'s input switch too (`examples/z98/rogue_mud/
  main.zig:236-256`); a follow-up `switch_char_case_labels` repro + F-task is recommended. NOT
  fixed here.

## Task F5 — gate sweep + tech docs, rogue_mud emission-defects plan closeout (2026-08-07)

Docs-only + verification task (no compiler code changed — the 4 F-fixes F1 a5ac4598, F2
ba89a6e0, F3 317f3a82, F4 b1b3f7e9 are all on the branch). Compiler under test: `/tmp/zf5/zig1`
(fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors).

- **Full corpus sweep (216 dirs, QUICK_REF classifier): `OK=209 / FAIL=3 / ICE=0 / CRASH=0 /
  GREEN=4 / TOTAL=216`.** Reconciliation vs the 215-repro manifest total: 216 dirs = 215 manifest
  repros + `opt_slice_null_return` (OK-by-gate, type-incorrect, tracked separately — its OK is
  the 209th, so effective OK=208). Raw classifier FAIL = 7 = 4 green-guards (sub-bucket) + 3 real
  FAILs (`field_store_drop`, `self_embed_optional_cycle`, `test_stub_0`). The 5 gap repros all
  OK: `dup_optptr_field_emit`, `dup_val_field_emit`, `undef_arr_struct_literal`,
  `xmod_pub_const_global`, `switch_mixed_case_argtype` — each runtime-verified (dump rc=0, gcc
  rc=0, run rc=0). No repro flipped vs F4; no regressions.
- **4 MD5 gates verified byte-identical** (no re-baseline this task; the mud re-baseline was
  recorded in F2): mud `906fa59c8676bb1054d3fcc13704fce5`, gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462`.
- **5 gap rows cleared → OK** in this manifest; the 3 remaining FAILs stay enumerated (2
  std-lib-deferred `error[3048]` + `self_embed_optional_cycle` gcc incomplete-type).
- **`opt_slice_null_return` latent guard** — OK-by-gate (gcc rc=0), but type-incorrect (emits an
  `undefined_const` for a slice return); tracked separately, NOT a gate failure.
- **Out-of-scope follow-up (unchanged from F4):** char_literal switch `case` labels dropped at
  `lower.zig:3858-3860` (stmt switch) / `:3121-3123` (expr switch; refs superseded — actual sites lower.zig:3183 expr / :3920 stmt) — `rogue_mud`'s input switch
  (`examples/z98/rogue_mud/main.zig:236-256`) would be runtime-dead. A `switch_char_case_labels`
  repro + F-task is recommended.
- **Tech docs updated (AGENTS §1.1.1, `[updated: 2026-08-07]`):**
  - `08_c89_emission.md` — F1: `tstEdgesCount`/`tstEdgesFill` dedupe same-typed field edges
    (distinct dep type counted once) via new `tstSeenInRange` (c89_emit.zig:799); fixed stale
    line refs (`tstTopologicalSort` :959, `tstEdgesCount` :807, `tstEdgesFill` :857, `tstIsDep`
    :922, sub-pass 2a/2b :1256/:1297, fwd-decls :1233-1255, Q1 refs).
  - `07_lir_lowering.md` — F2: lowerer skips `assign_field` for `undefined` array-typed fields
    (oracle parity); F3: cross-module `pub const` literal fold at the ref site.
  - `05_semantic_analysis.md` — F4: switch MIX branch `continue` (resolves remaining prongs
    instead of aborting; `call_arg_types` populated for later prongs); fixed stale :1018-1129
    function range → :1046-1179 and the abort-behavior doc.
  - `02_symbol_registration.md` — F3: `pub const` literal-init has no storage slot (bit0=mutable);
    cross-module refs fold literals at the ref site.
  - `03_type_resolution.md` — NOT updated (F1/F3 touch c89_emit/lower, not the type-resolution
    path; verified by `git show --stat`).
- **Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, `sf/docs/tech_docs/`
  (08, 07, 05, 02, INDEX.md), `examples/z98/rogue_mud/NOTES.md`. Commit
  `docs: gate sweep + tech docs for rogue_mud emission defects plan`.

---

## char_literal switch-case repro battery (Battery A, 2026-08-07) — 12 repros, ALL OK (F1-fixed, runtime-gap cleared)

Repros from the repro battery plan (`95b3c828` spec, `f0077d50` plan; commits `0dc4f594`,
`1e592430`, `c2864086`). They probe the **char_literal switch `case`-label drop**: both
switch-case-collection loops in `lower.zig` handle `int_literal`/`enum_literal`/`error_literal`
case nodes then `else { continue; }`, so a `char_literal` (kind 13) case node is silently dropped
from the case table — the emitted C `switch (c)` has NO `case` labels, only `default:`, and every
input takes the `else` body.

- **Defect sites (both, FIXED by F1 `e0a4d6d6`):**
  - `sf/src/lower.zig:3170-3184` — **expr-switch** case collection, `else { continue; }` at
    `:3183`. **F1** adds an `AstKind.char_literal` branch reading `store.int_values` (like
    `int_literal` does) — actual expr-site fix at lower.zig:3202.
  - `sf/src/lower.zig:3907-3921` — **stmt-switch** case collection, `else { continue; }` at
    `:3920`. **F1** adds the same `char_literal` branch — actual stmt-site fix at lower.zig:3941.
- **Fix (F1, commit `e0a4d6d6`, 2026-08-07):** both switch-case-collection loops gained an
  `AstKind.char_literal` branch (mirroring `int_literal`: value from `store.int_values`), so char
  cases emit real `case 'a':` labels. All 12 repros flip to their expected post-fix output
  (verified by run below).

**Classification under the corpus gate (POST-FIX):** every repro dumps rc=0, is gcc-clean
(per-file `gcc -c` rc=0), links, and runs rc=0 — gcc-exit classifier reports **OK**. **F1 makes
them fully OK at runtime too** — the char cases are no longer dead; each repro prints its expected
post-fix output. **No longer runtime-gap-tracked** (pre-fix they compiled clean but miscompiled at
runtime; the F1 fix resolved the runtime gap).

**Measured POST-FIX (sf/build/out_release/zig1, F4 gate sweep 2026-08-07):** all 12 dump rc=0,
gcc rc=0, run rc=0, output matches the expected post-fix column:

| Repro | defect site | pre-fix run output | **post-fix run output** |
|-------|-------------|--------------------|--------------------------|
| `switch_char_single` | stmt `:3920` (→ fixed :3941) | `000` | **`120`** |
| `switch_char_multi` | stmt `:3920` (→ fixed :3941) | `0000` | **`1120`** |
| `switch_char_nodefault` | stmt `:3920` (→ fixed :3941) | `99` | **`19`** |
| `switch_char_mixed_kinds` | stmt `:3920` (→ fixed :3941) | `020` | **`120`** (INT case 98 + char case both fire now) |
| `switch_char_expr` | expr `:3183` (→ fixed :3202) | `000` | **`120`** |
| `switch_char_while` | stmt `:3920` (→ fixed :3941) | `0` | **`1`** |
| `switch_char_labeled` | stmt `:3920` (→ fixed :3941) | `0` | **`1`** |
| `switch_char_nested` | stmt `:3920` (→ fixed :3941) | `999` | **`109`** |
| `switch_char_xmod` | stmt `:3920` (→ fixed :3941) (cross-module) | `000` | **`120`** |
| `switch_char_xmod_expr` | expr `:3183` (→ fixed :3202) (cross-module) | `000` | **`120`** |
| `switch_char_xmod_while` | stmt `:3920` (→ fixed :3941) (cross-module, in loop) | `0` | **`1`** |
| `switch_char_xmod_nodefault` | stmt `:3920` (→ fixed :3941) (cross-module, no else) | `99` | **`19`** |

Each dir's `NOTES.md` documents the defect, oracle (zig0) verification, measured pre-fix output,
and expected post-fix output (F3 7a732cb3 updated the classifications to "FIXED post-F1").
`switch_char_mixed_kinds` is the key discriminator — its INT case prong (`98`) fired while the char
prong (`'a'`) was dropped, proving the bug was char-specific, not a general switch miscompile; now
both prongs fire.

**Accounting:** 12 repros, all **fully OK** (F1-fixed). FAIL=3 and green-guards=4 **UNCHANGED**.

---

## opt_slice null-payload repro battery (Battery B, 2026-08-07) — 3 repros, ALL OK / FIXED by F2 (Option B)

Repros from the same repro battery plan (commit `965a830b`). They probe the **opt_slice
null-payload temp typing**: `catch return null` (and `return null`) in a function returning an
OPTIONAL SLICE (`?[]T`) emitted the null payload as a scalar `int` temp assigned `NULL`
(`int zT_3; zT_3 = NULL; zT_4.has_value = 0;`) even though the optional struct's payload field is
really a slice `typedef struct { zT_..._Slice... value; int has_value; } Opt;`. For an optional
POINTER (`?*T`) the payload IS a pointer and `int`/`NULL` is acceptable; for an optional slice the
temp type was wrong.

- **Defect (pre-fix):** the null-construction path picked a scalar `int` temp for the payload
  regardless of the payload's real type (the optional's payload type was not threaded onto the null
  temp). Latent, not a gate failure: the emitted C compiled (gcc rc=0, `-Wint-conversion` warning
  only) and the payload is never READ when `has_value=0`.
- **Fix (F2, commit `5c515a7d`, 2026-08-07, Option B):** the `null_literal` branch in
  `lowerExprImpl` (lower.zig:1183-1214) now consults the coercion table: when the coercion routes
  to `wrap_optional_null` / `wrap_optional` / `wrap_error_success` AND the target chain contains an
  optional layer, it emits `set_optional_null` directly on a temp typed as that optional layer —
  the dead `int zT_N; zT_N = NULL;` store (typed `null_type` → `int`, gcc `-Wint-conversion`) is
  gone. No payload temp is emitted at all; `materializeInto` short-circuits on `src_ty == expected`
  (lower.zig:911) or wraps the `?T` temp into outer EU layers (lower.zig:945). Emitted C is now
  `Opt_... zT; zT.has_value = 0;`. Warning count on the payload temp: 2/2/3 → **0/0/0**; `grep
  '= NULL;'` on emitted C: **0 hits**. All 3 still print `1` (verified by run, F4 sweep).

**Measured POST-FIX (sf/build/out_release/zig1, F4 gate sweep 2026-08-07):** all 3 repros dump
rc=0, gcc-clean (**0 `-Wint-conversion`**, 0 `= NULL;`), link, run rc=0 printing `1`:

| Repro | path | post-fix emitted-C symptom |
|-------|------|--------------------|
| `opt_slice_null` (B1) | same-module `?[]Point` | `Opt_... zT; zT.has_value = 0;` (no `int zT_3;` payload temp, no `= NULL;`) |
| `opt_slice_null_xmod` (B2) | cross-module `?[]Path` (lib.zig) | same post-fix shape in `lib_*.c` |
| `opt_slice_null_multi` (B3) | 3 null sites (2× `catch return null` + final `return null`) | `Opt_... zT; zT.has_value = 0;` at each site (no `int zT_6; = NULL;`) |

`opt_slice_null_return` (from the rogue_mud F5 I-task, 2026-08-07) is a DIFFERENT latent issue
(it emits an `undefined_const` for a slice return, not the null-payload `int` temp — unaffected by
F2's null_literal change) and remains **OK-by-gate, tracked separately** (see the F5 section).
Each dir's `NOTES.md` documents the pre-fix gap and the post-fix analysis.

**Accounting:** 3 repros, all **OK / FIXED by F2**. FAIL=3 and green-guards=4 **UNCHANGED**.

---

## F1/F2 fix records — char_literal switch + opt_slice null (2026-08-07)

The 15 battery repros above (12 Battery A + 3 Battery B) gate the two post-plan fixes; both are
now landed and the battery annotations are cleared:

| Fix | Commit | What changed | Battery impact |
|-----|--------|--------------|----------------|
| F1 — char_literal switch `case` labels | `e0a4d6d6` | Both switch-case-collection loops (`lower.zig` expr-switch site ~:3202, stmt-switch site ~:3941) gained an `AstKind.char_literal` branch (value from `store.int_values`, mirroring `int_literal`) — char cases now emit real `case 'a':` labels instead of being dropped (`else { continue; }`). | 12 Battery A repros **runtime-gap cleared** — all print expected post-fix output (`120`, `1120`, `19`, `1`, `109`, …). Fully OK. |
| F2 — opt_slice null-payload temp | `5c515a7d` | `null_literal` branch (lower.zig:1183-1214, Option B) consults the coercion table; null_src coercions with an optional layer emit `set_optional_null` directly on an `Opt_`-typed temp — the dead `int zT_N; zT_N = NULL;` payload temp (gcc `-Wint-conversion`) is gone. | 3 Battery B repros **latent cleared** — 0 `-Wint-conversion` warnings (was 2/2/3), 0 `= NULL;` sites, all still print `1`. Fully OK. |

**Gate sweep (F4, 2026-08-07, `sf/build/out_release/zig1` at HEAD):** full corpus 231 dirs
classify **OK=224 / FAIL=3 / ICE=0 / CRASH=0 / green-guards=4** (224 OK dirs = 223 effective
manifest OK + `opt_slice_null_return` tracked separately; raw classifier FAIL = 7 = 4 green-guards
sub-bucket + 3 real FAILs). FAIL=3 and green-guards=4 UNCHANGED. 4 MD5 gates: gol byte-identical;
mud/lisp/json re-baselined by F2 (full hashes in QUICK_REF). test_analyzer_bin PASS.

---

## F2 — D2 deferred to std-lib + `extern_runtime_symbol_xmod` repro (2026-08-08, docs + repro only)

Per the I2 report (`.superpowers/sdd/I-orphan-module-report.md`) and the operator ruling,
the D2 "json_parser orphan module" investigation found **NO compiler defect**: `arena.zig`
is never `@import`ed (orphan file), all modules emit, and the link failure is
`undefined reference to arena_alloc_default` — an extern (declared
`sf/src/include/zig_runtime.h:21-22`) defined ONLY in the legacy
`src/runtime/zig_runtime.c:31/:154-156`, **absent from `sf/src/include/zig_runtime.c`**.
Class **(b) runtime-library gap**; a documented runtime API
(`docs/reference/runtime_api.md:38-48`). **Deferred to the std-zig1 library — NOT fixed
here** (no `sf/src/*.zig` changes, no runtime-file changes).

**json_parser + json_parser_workaround — officially documented as std-lib-deferred** (their
NOTES.md gained a "Deferred to std-lib" section): both call `arena_alloc_default`; the
standard sf-runtime recipe fails on 5 undefined refs; linking the legacy
`src/runtime/zig_runtime.c` object makes json_parser link+run. `json_parser_workaround`
remains ADDITIONALLY blocked by the I3 6× zT_xx forward-decl COMPILE gap (unaffected by
any runtime fix). These are **example-level link gaps, not corpus repros** — they do not
change the corpus counts.

**New repro `extern_runtime_symbol_xmod` (class-(b) extern-link spec for the std-lib plan):**

| Repro | RED (measured) | Classification (measured, sf/build/out_release/zig1) | Guards |
|-------|----------------|---------------------------|--------|
| `extern_runtime_symbol_xmod` | pre-F3: standard-recipe link rc=1: `undefined reference to 'arena_alloc_default'` (lib_*.c) | **F3: FULLY OK (green regression guard)** — migrated off the `arena_alloc_default` extern to the `std_arena.zig` module (lib.zig imports a local std_arena copy, wraps `std.alloc` in `pub fn alloc`); dump rc=0, all modules emit (lib + main + std_arena), per-file gcc -c rc=0, **standard sf-runtime link rc=0 (no legacy object)**, run rc=0 (prints `0`; the 16-byte alloc succeeds → non-null ptr → `@ptrToInt(p)==0` false). The F2 OK-by-gate/latent std-lib-deferred classification is CLEARED (see the F3 section) | `mod_silent_drop_xmod` stays as the general emission guard; this repro now guards cross-module `std.arena` use (module emission + alloc + multi-module link + run) |

**zig0 oracle verification:** dump rc=0, emits lib.c/main.c (same module set). Honest
nuance vs the brief's "SAME link failure": zig0 re-emits the extern as `extern unsigned
char* arena_alloc_default(unsigned int n);` (from the `[*]u8` return), which CONFLICTS
with `zig_runtime.h:21` `void*` → the oracle's standard-recipe output fails at **compile**
(conflicting types), whereas zig1 (header-decl-only, no re-emitted extern) fails at
**link**. Both confirm the same runtime gap. zig0 also emits
`__bootstrap_i32_from_bool(...)` for `@intCast(i32, bool)` — a checked-cast helper in NO
runtime (legacy zig0 emission; zig1 post-F1 emits a raw `(int)` cast for the widening).

**Source corrections vs the brief's verbatim blocks (both documented in the repro
NOTES.md):** (1) the in-body `extern fn __bootstrap_print_int` was moved to module scope —
BOTH zig1 (`error[3020]`) and the zig0 oracle (syntax error) reject in-function `extern fn`
decls (pre-existing Z98 subset limitation, not a zig1 defect; corpus pattern is top-level);
(2) the `@ptrToInt(p) == @intCast(usize, 0)` line **works post-F1** as predicted
(`@ptrToInt` → `usize` for single-arg calls, commit `51bfdb3c`) — no error.

**Accounting:** **UNCHANGED — OK=223 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 230
manifest repros** (raw classifier FAIL stays 7). `extern_runtime_symbol_xmod` is tracked
separately as OK-by-gate/latent (mirrors the `opt_slice_null_return` precedent), NOT added
to FAIL; the two examples are example-level link gaps, not corpus repros. No repro
flipped; no compiler changes; 4 MD5 gates untouched (compiler unchanged). test_analyzer_bin
PASS. Full evidence: `.superpowers/sdd/task-F2-rogue-report.md`.

## F3 — `std_arena.zig` + json_parser migration (2026-08-08) — D2 arena gap CLOSED

The D2/F2 `arena_alloc_default` deferral is resolved with a **Zig-side arena module** (not a
runtime C symbol). New `sf/src/std_arena.zig` — a pure Z98 bump allocator
(`pub const Arena = struct { data: [*]u8, capacity: usize, used: usize };` +
`pub fn create(initial_capacity: usize) Arena`, `pub fn alloc(self: *Arena, size: usize)
?[*]u8`, `pub fn reset(self: *Arena) void`) over a static 1 MB `g_storage` + `g_used`
counter. `json_parser` + `json_parser_workaround` (`arena.zig`/`file.zig`/`json.zig`)
replaced `extern fn arena_alloc_default` with `const std = @import("std_arena.zig");` +
`std.create/alloc` (local copies of the module in each example dir so the import resolves);
`extern_runtime_symbol_xmod` migrated the same way.

**Verified (sf/build/out_release/zig1, multi-module recipe, STANDARD sf runtime, NO legacy
object):** json_parser — dump rc=0 (main/json/file/std_arena emit), per-file gcc `-c` rc=0,
link rc=0, run rc=0 (parses test.json). json_parser_workaround — dump rc=0, gcc `-c` rc=0
(both the F3 cross-module-enum fix AND the std_arena migration), link rc=0, run rc=0 (prints
`{}`; the hand-rolled tagged-union print path is a known example-source quirk). Both
previously failed standard-recipe link with **5× `undefined reference to arena_alloc_default`**
(4 json + 1 file). **`extern_runtime_symbol_xmod` flipped to FULLY OK (green regression
guard)** — dump rc=0, all modules emit (lib + main + std_arena), gcc rc=0, **standard-recipe
link rc=0**, run rc=0 (prints `0`); its F2 OK-by-gate/latent std-lib-deferred classification
is CLEARED. Corpus counts UNCHANGED (examples + the tracked-separately repro are not
manifest repros): effective **OK=223 / FAIL=3 / green-guards=4** over 230; the 3 FAILs
(`field_store_drop`, `test_stub_0`, `self_embed_optional_cycle`) and 4 green-guards
unchanged. **4 MD5 gates: mud `6c0a83f1…`, gol `0d8f0092…`, lisp `a12f2fce…` byte-identical;
json RE-BASELINED to `ff9b880c…`** (its source changed → emitted C changes; runtime output
byte-identical to pre-fix — old legacy-linked binary vs new standard-linked binary `diff`
empty — per the F-5 AMENDMENT B precedent). test_analyzer_bin PASS.

## F4 — D4 plat-stub gap deferred to std-lib (2026-08-08, docs only)

Per the I4 report (`.superpowers/sdd/I-platstub-gap-report.md`) and the operator ruling,
the D4 "platform-stub gap" investigation found **NO compiler defect**: 12 `plat_*` symbols
exist in `sf/src/include/net_runtime.c` (all socket-family), but the **5
console/platform-detect stubs** requested by `rogue_mud`
(`examples/z98/rogue_mud/ui.zig:11-15`) are **MISSING from ALL runtime files**
(`zig_runtime.c` / `zig_pal.c` / `net_runtime.c`): `plat_is_windows`,
`plat_console_gotoxy`, `plat_console_setcolor`, `plat_console_putchar`,
`plat_console_clear`. Class **(b) runtime-library gap**; `sf/build/zig0` fails
IDENTICALLY (same undefined-reference link rc=1) → NOT a compiler bug. **Deferred to the
std-zig1 library — NOT fixed here** (no compiler changes, no runtime-file changes).

`plat_stubs_missing_xmod` is the existing guard repro (dump rc=0, all modules emit, gcc
`-c` rc=0, link rc=1 on the missing stubs):

| Repro | RED (measured) | Classification (measured, sf/build/out_release/zig1) | Guards |
|-------|----------------|---------------------------|--------|
| `plat_stubs_missing_xmod` | link rc=1: `undefined reference to plat_is_windows` / `plat_console_putchar` (console_*.c) | **OK-by-gate / LATENT, std-lib-deferred** — dump rc=0, all modules emit, per-file gcc -c rc=0, standard-recipe link rc=1 on the missing console/platform-detect stubs (all 5 rogue_mud-only) | guards the rogue_mud link gap; flips to PASS when the std-lib runtime adds the 5 stubs (a console/platform-detect layer, e.g. `console_runtime.c` mirroring `net_runtime.c`) |

**Accounting:** **UNCHANGED — OK=223 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 230
manifest repros** (raw classifier FAIL stays 7). `plat_stubs_missing_xmod` is tracked
separately as OK-by-gate/latent (mirrors the `opt_slice_null_return` /
`extern_runtime_symbol_xmod` precedents), NOT added to FAIL. `rogue_mud` (20 modules) is
BROKEN at link ONLY on these 5 stubs (both single- and multi-module recipes: all modules
emit, gcc compile rc=0). No repro flipped; no compiler changes; 4 MD5 gates untouched.
Full evidence: `.superpowers/sdd/task-F4-rogue-report.md`.

## F5 — D4 plat-stub gap CLOSED via console builtins (2026-08-13) — `plat_stubs_missing_xmod` FULLY OK

F5 (std-zig1 lib plan, console builtins migration) closed the D4 platform-stub gap the F2
way — via the **compiler console builtins**, NOT runtime stubs:

- **`examples/z98/rogue_mud/ui.zig`**: the 5 `plat_*` console externs
  (`plat_is_windows`, `plat_console_gotoxy`, `plat_console_setcolor`,
  `plat_console_putchar`, `plat_console_clear`) replaced with the F2 builtins
  (`@isWindows()` / `@consoleClear()` / `@consoleGotoxy(x,y)` /
  `@consoleSetColor(fg,bg)` / `@putChar(ch)`). The `plat_send` socket extern stays
  (provided by `net_runtime.c`).
- **`examples/z98/rogue_mud/main.zig`**: the 4 `ui_mod.plat_is_windows()` call sites →
  comptime `@isWindows()` (folds to 0 on the POSIX host → `!@isWindows()` true).
- **`repro/mi_matrix/plat_stubs_missing_xmod/console.zig`**: migrated off the 2 externs to
  `@isWindows()` + `@putChar('X')`.

| Repro | RED (pre-F5) | GREEN (measured, sf/build/out_release/zig1) | Guards |
|-------|----------------|---------------------------|--------|
| `plat_stubs_missing_xmod` | link rc=1: `undefined reference to plat_is_windows` / `plat_console_putchar` (console_*.c) | **FULLY OK** — dump rc=0, all modules emit, gcc -c rc=0, **standard-recipe link rc=0**, run rc=0; the D4 OK-by-gate/latent std-lib-deferred classification is CLEARED | guards the rogue_mud console migration (module emission + builtin wiring + multi-module link + run) |

**rogue_mud (22 modules):** dump rc=0, gcc -c rc=0, **link rc=0** (BOTH single-module and
multi-module recipes — was rc=1 on the 5 stubs), **run rc=0** — boots, renders the dungeon
via ANSI escapes (`@consoleGotoxy`/`@consoleSetColor`/`@putChar` emit `\x1b[<y+1>;<x+1>H` +
`\x1b[<fg>;<bg>m` + char on POSIX), accepts WASD/Q input, exits cleanly on `q`. The 5
undefined `plat_*` refs are gone from the emitted C (0 matches across all 22 modules).

**Accounting:** UNCHANGED — effective **OK=223 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0
over 230 manifest repros** (raw classifier FAIL stays 7). `plat_stubs_missing_xmod` moves
from the separately-tracked OK-by-gate/latent bucket to **FULLY OK** (like
`extern_runtime_symbol_xmod` at F3). No repro flipped; **no compiler changes**; 4 MD5 gates
untouched. See `.superpowers/sdd/task-F5-rogue-report.md`.

---

## F1 — @ptrToInt resolves to usize for single-arg calls (2026-08-08) — `ptr_to_int_void_xmod`

**Commit `51bfdb3c`** (semantic_analyzer.zig, 03_type_resolution.md). Hoisted the
`ptrtoint_name_id` check above the `ec.len` dispatch in `semanticAnalyzerResolveExpr`
(semantic_analyzer.zig:1298-1301), mirroring lower.zig:2653-2657; dead nested
`@ptrToInt → TYPE_USIZE` branch (was under `ec.len >= 2`) removed. Single-arg
`@ptrToInt(x)` now resolves to `TYPE_USIZE` instead of `void`.

| Repro | RED (pre-fix) | GREEN (post-fix, measured) |
|-------|---------------|----------------------------|
| `ptr_to_int_void_xmod` | dump rc=2, `error[3000] cannot declare variable of type void`, 0 `.c` | dump rc=0; emitted `unsigned int current_pos; current_pos = (unsigned int)ptr;`; gcc -c rc=0; link rc=0; **run rc=0, prints `1`**. Classifies **OK**. |

**Gates:** lisp_interpreter (the headline consumer) unblocked from the sema frontend block —
dump rc=0 (was error[3000]) — but its emitted C now surfaces a **separate pre-existing
lowerer defect** in `builtins.zig`: gcc FAIL, 6 errors (5× `zT_N` undeclared in token_*.c +
1× `zG_..._global_symbol_list = zT_0` Opt_45-null-payload mismatch in parser_*.c). This is
NOT a new regression from F1 (builtins.zig has no `@ptrToInt`; the defect was previously
masked by the sema block); tracked as a follow-up (see below). **lisp MD5 RE-BASELINED**
`fad41183…` → `a12f2fcebc30f2d8c2a148facb9d1174` (addr/start/end consts now `unsigned int`;
runtime output byte-identical to pre-fix, both run rc=0, output md5 `1c1f0a417d5e943433755a8ce593542f`
— verified by stash-revert rebuild, F1 report §Gates). test_analyzer_bin PASS.

## F3 — cross-module plain-enum member access resolves (2026-08-08) — `zT_missing_fwd_xmod`

**Commit `021ffcfd`** (semantic_analyzer.zig, lower.zig, 08_c89_emission.md). `x ==
mod.Type.Member` cross-module plain-enum access resolved to `TYPE_VOID` in sema + lowering
→ emitted C omitted the enum-literal temp → gcc `'zT_XX' undeclared`. Fix: sema
(semantic_analyzer.zig:459) + lower (lower.zig:2207) generic base-type dispatch gained an
`enum_type` case mirroring the same-module ident_expr path (`:260-271` / `:1981-1999`).

| Repro | RED (pre-fix) | GREEN (post-fix, measured) |
|-------|---------------|----------------------------|
| `zT_missing_fwd_xmod` | dump rc=0; gcc `-c` main_A05BD8BB.c rc=1 (`'zT_2' undeclared` at `zT_3 = tag == zT_2;`) | dump rc=0; gcc -c rc=0; link rc=0; **run rc=0** (emits `zT_3 = zT_..._Tag_Null; zT_4 = tag == zT_3;`). Classifies **OK**. |

**json_parser_workaround — gcc-clean (was 6× zT_xx COMPILE FAIL):** all 6 missing temps
resolved (`zT_11 = zT_6BE94440_JsonValueTag_Null;` … `zT_97 = zT_6BE94440_JsonValueTag_Object;`),
0 compile errors (only the pre-existing strtod `-Wincompatible-pointer-types` warning).
Link/run STILL blocked by the std-lib-deferred `arena_alloc_default` extern (F2). **4 MD5
gates byte-identical** (lisp already at post-F1 `a12f2fce…`). test_analyzer_bin PASS.

## F5 — arena resize for self-compile (2026-08-08) — PARTIAL

**Commit `462ddee4`** (allocator.zig:74-79, main.zig:848, 00_shared_infra.md). perm 1 MB→4 MB,
mod 1.5 MB→8 MB, scratch 1.5 MB→2 MB; `DEV_MAX_MEM` 8 MB→16 MB (== `RELEASE_MAX_MEM`).
Resize landed (plan-mandated 4/8/2, 16 MB budget). **Self-compile import-phase gate NOT
met:** `zig1 --dump-c89 --output-dir /tmp/z5 sf/src/main.zig` → `dump rc=3`,
`OOM: used=1899216 new=3472080 total=2097152` — the **scratch** arena (2 MB) OOMs during
import lexing of a 5k-line module (the lexer token array, 24 B/Token, doubling 32K→64K,
never freed within a module, needs ≥3.5 MB). **Documented as future investigation (operator
ruling m0442), NOT a corpus regression** — the resize fixes phase-1 module/perm OOMs and no
repro regressed. Scratch-arena optimization listed as a follow-up (see below). **4 MD5 gates
byte-identical** (arena size does not change codegen). test_analyzer_bin PASS.

## F6 — cross-module tagged-union member access no longer SEGVs (2026-08-08) — `tagged_union_cmp_xmod`

**Commit `efbf4807`** (lower.zig:2174-2206, 08_c89_emission.md). Option (a) ONLY per operator
ruling m0406: the generic base-type field-access branch previously called
`typeRegistryGetStructFields` for `tagged_union_type` (WRONG → SEGV at lower.zig:2180). Added
a dedicated `tagged_union_type` case mirroring the same-module member path (lower.zig:1966-1979):
look up the member in `tu_items[ty.payload_idx]`, on match return
`emitTaggedUnionInit(...)` — a TU-typed `int_const` emitting `.tag = <ordinal>;`. Option (b)
(reject-in-sema) NOT implemented.

| Repro | RED (pre-fix) | GREEN (post-fix, measured) |
|-------|---------------|----------------------------|
| `tagged_union_cmp_xmod` | dump rc=1, 0 `.c`; stderr `AddressSanitizer:DEADLYSIGNAL` → `SEGV on unknown address 0x00000000`, frame 0 = `typeRegistryGetStructFields` ← `lowerExprImpl` ← `phase_LIRLowering` | dump rc=0 (SEGV **gone**, CRASH→0); isolated `var x = lib_mod.Shape.Circle;` gcc-clean, link rc=0, **run rc=0**. The `==` form still emits gcc-invalid C (`error: invalid operands to binary ==` — the known separate latent union-`==` emission issue; NOT fixed, see follow-ups). Classifies gcc-FAIL → sweep FAIL 7→8, ICE 1→0. |

**F3 repros no-regression:** `zT_missing_fwd_xmod` run rc=0; json_parser_workaround gcc-clean.
**4 MD5 gates byte-identical. test_analyzer_bin PASS.**

## F7 gate sweep + full example matrix reconciliation (2026-08-08)

**Corpus sweep (all 237 dirs, gcc-exit classifier, `sf/build/out_release/zig1`):**
`OK=229 / FAIL=8 / ICE=0 / CRASH=0`. FAIL=8 = the 4 green-guards (`eu_assign_incompat_payload`,
`euvoid_val_catch`, `field_access_optional`, `var_declared_void`) + 2 std-lib-deferred
(`field_store_drop`, `test_stub_0`) + `self_embed_optional_cycle` (C89 fundamental) +
`tagged_union_cmp_xmod` (latent union-`==` emission). **No manifest OK repro regressed; the
only count moves vs the F3 sweep (OK=229/FAIL=7/ICE=1) are tagged_union_cmp_xmod ICE→FAIL
(F6 SEGV fix).** Convention reconciliation vs the plan's 230/231 figures is documented in
the Totals block above.

**Full 21-example matrix (MEM4 recipe, multi-module `--dump-c89 --output-dir`; measured):**

| # | Example | dump | gcc | link | run | Post-fix status vs MEM4 |
|---|---------|------|-----|------|-----|--------------------------|
| 1 | hello | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 2 | fibonacci | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 3 | prime | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 4 | heapsort | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 5 | quicksort | 0 | 0 | 0 | 0 | unchanged WARN OK (10w) |
| 6 | mandelbrot | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 7 | game_of_life | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 8 | lzw | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 9 | func_ptr_return | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 10 | sort_strings | 0 | 0 | 0 | 0 | unchanged WARN OK (8w) |
| 11 | days_in_month | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 12 | tco_factorial | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 13 | tco_defer | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 14 | tco_return_try | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 15 | json_parser | 0 | 0 (1w) | **0 (was 1)** | **0** | **LINK FAIL CLEARED (F3, std_arena migration)** — standard-recipe link rc=0 (no legacy object), run rc=0 parses test.json; was 5× `arena_alloc_default` undefined ref |
| 16 | json_parser_workaround | 0 | 0 (1w) | **0 (was 1)** | **0** | **LINK FAIL CLEARED (F3, std_arena migration)** — standard-recipe link rc=0, run rc=0 (prints `{}`); both the F3 cross-module-enum compile fix AND the arena link gap resolved |
| 17 | lisp_interpreter | **0 (was error[3000] DUMP FAIL → now dumps, F1)** | **1** | — | — | **frontend block CLEARED (F1)**; GCC FAIL 6 errors = 5× `zT_N` undeclared + 1 Opt_45 null-payload (pre-existing builtins.zig lowerer defect, follow-up) |
| 18 | lisp_interpreter_adv | 0 | 0 | 0 | 0 | unchanged WARN OK (1w) |
| 19 | lisp_interpreter_curr | 0 | 0 | 0 | 0 | unchanged WARN OK (1w; MEM4 recorded 9w — gcc-version/toolchain diff, benign) |
| 20 | mud_server | 0 | 0 | 0 | 124 | unchanged CANNOT RUN — server, "MUD server listening on port 4000" (timeout) |
| 21 | rogue_mud | 0 (20 modules) | 0 (5w) | **1** | — | **LINK FAIL at this sweep** — 5 `plat_*` stubs (std-lib-deferred, F4); **[F5 2026-08-13 CLEARED: the 5 stubs → console builtins, link rc=0 + run rc=0 — see the F5 section]** |

**End-to-end working binaries: 16/21** (12 FULL OK + 4 WARN OK), same as MEM4 — but two
compiler-defect classes were CLEARED (json_parser_workaround's 6× zT_xx compile gap via F3;
lisp_interpreter's @ptrToInt frontend block via F1, exposing a separate pre-existing lowerer
defect). No NEW regression vs MEM4. **[F3 2026-08-08: `json_parser` + `json_parser_workaround`
now link+run rc=0 → end-to-end working binaries 18/21** (the 3 non-working: lisp_interpreter
gcc FAIL, mud_server server-timeout, rogue_mud plat_* link FAIL). See the F3 section.]**
**[F5 2026-08-13: rogue_mud console migration closes the D4 gap → link rc=0 + run rc=0 →
working set 19/21 end-to-end** (lisp_interpreter gcc FAIL + mud_server server-timeout are the
only non-run). See the F5 section.] **[F6 2026-08-13: networking builtins + std_net migration;
mud_server re-verified boots on the standard runtime (no net_runtime.c); the working set is
unchanged. See the F6 section / QUICK_REF MD5 table.]**

**[F4 2026-08-08 — std.io migration (see task-F4-stdlib-report.md):]** all 21 examples
migrated off `__bootstrap_*` (zero refs in example sources); all 21 dump rc=0; the working set
is **unchanged at 18/21 end-to-end** (same set as F3 — no example regressed). The 6
example-facing `__bootstrap_*` I/O wrappers were removed from `zig_runtime.c`/`.h`; the 19
`@intCast` cast helpers now panic via `std_panic` directly (m0564). The F1/F2 feature-guard
repros **`io_builtin_test` + `console_builtin_test` were migrated to `std.io`** (local
`std.zig`/`std_io.zig`/`std_arena.zig` copies in each dir; the F2 console builtins' emitted
`__bootstrap_write` calls were repointed to `std_print_len` in c89_emit.zig — the console
builtins' stdout-write helper) — both still compile+link+run. Corpus at F4: **239 dirs measured,
OK=232 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0** (the 3 FAILs + 4 green-guards are exactly
the documented set — no new corpus FAIL).

## F4 repro migration — corpus repros off `__bootstrap_*` → std.io (2026-08-13)

F4 removed the 6 example-facing `__bootstrap_*` I/O wrappers (`__bootstrap_print`,
`__bootstrap_print_int`, `__bootstrap_print_char`, `__bootstrap_panic`, `__bootstrap_write`,
`__bootstrap_sleep_ms`) from `zig_runtime.c`/`.h`. Corpus repros still declaring
`extern fn __bootstrap_print*` therefore no longer LINK (`undefined reference to
__bootstrap_print*`). **47 repro .zig files migrated** (44 `main.zig` + 2 `main_green.zig`
+ 1 `io.zig`; `field_store_drop` left unmigrated — compile-only FAIL, `error[3048]` on
`@import("pal")`, std-lib-deferred) off the extern to `std.io`
(`std.io.print` / `std.io.printInt` / `std.io.write`), each with **byte-identical local
`std.zig` + `std_io.zig` copies** (the F3 std_arena per-example-copy precedent, D1). The local
`std.zig` is the reduced `io`-only root package (omits the `arena`/`debug` re-exports — see the
D2 tracking entry below). Verified with the QUICK_REF single-file recipe
(`zig1 --dump-c89` + `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include
/tmp/x.c zig_runtime.c zig_pal.c`):

| Repro | Result |
|-------|--------|
| `intcast_range_check` | dump rc=0, gcc rc=0 (LINKS), run rc=134 — PANICS `integer cast overflow in @intCast` (F1 pass criterion, link restored) |
| `enum_literal_assign` | dump rc=0, gcc rc=0, run rc=0, prints `1` (expected_out.txt) |
| `error_literal_return` | dump rc=0, gcc rc=0, run rc=0, prints `1` (expected_out.txt) |
| `switch_char_expr` | dump rc=0, gcc rc=0, run rc=0, prints `120` (char switch post-F1-fix, migration is a pure I/O swap) |
| `opt_extern_ptr_file` | dump rc=0, gcc rc=0, run rc=0, prints `1` — pre-existing optional-wrap emission RED (has_value hardcoded 1), unchanged by migration; the `printInt` path itself works |
| `import_extern_c` | dump rc=0, gcc rc=0, run rc=0, prints `hello` (io.zig migrated `extern "c" fn __bootstrap_print` → `std.io.print`) |

**`field_store_drop` disposition:** NOT migrated — it is a compile-only FAIL
(`error[3048]: could not resolve imported file 'pal'` from its `@import("pal")`, std-lib-
deferred). The `__bootstrap_print_int` extern is unreachable behind the frontend gate; leaving
it does not break the gate (verified: still error[3048], 0 `.c` emitted).

## D2 tracking — std_arena module-instance ≥1 emission bug (FILE the entry, out of F4 scope)

**Pre-existing compiler bug (verified in the F4 stdlib review):** importing `std_arena.zig` as
**module instance ≥ 1** emits invalid C — the `_N` instance suffix is applied to the struct
typedef + locals (`zT_F22A6288_Arena_1`) but NOT to the function-signature type refs
(`zT_F22A6288_Arena` return) → `error: return type is an incomplete type` / `conflicting types`
in the emitted `std_arena_*.c`. Trigger: `rogue_mud` (multi-module build) pulling the canonical
`std.zig` root package (which re-exports `arena`); json_parser builds std_arena at instance 0
and is unaffected. **Out of F4 scope** (compiler change; F4 is a repro/example migration).
Workaround today: local `std.zig` root packages omit the `arena` re-export where std_arena
would land at instance ≥ 1 (mud_server, and the 48 migrated corpus repros). **Documented
follow-up** — a future compiler task must fix the instance-suffix application for
function-signature type refs (or defer std_arena to instance 0). See the F4 stdlib report
concern 2 / DEVIATION D2 (`.superpowers/sdd/task-F4-stdlib-report.md`).

## printInt INT_MIN overflow tracking (Minor, out of F4 scope)

**Pre-existing minor defect (verified in the F4 stdlib review):** `std_io.zig`'s `printInt`
uses `v = @intCast(u32, 0 - n)` for negatives. This is correct for all i32 values EXCEPT
`INT_MIN` (`0 - INT_MIN` overflows i32 → panic rc=134). The suggested `0 - @intCast(u32, n)`
was rejected in testing: this compiler's `@intCast(u32, negative)` panics, breaking the working
`-5` case (`comptime_neg_int`). **No example or repro prints INT_MIN.** File as a documented
follow-up: fix requires i64-widened negation (`@intCast(u32, 0 - @intCast(i64, n))`) or a
division-based magnitude loop — deferred, not an F4 defect.


## Follow-ups (multi-module fixes plan) — NOT fixed here

1. **Union `==` emission** — `tagged_union_cmp_xmod` and same-module union `==` emit
   `lhs == rhs` as `binary ==` on the C struct union (`error: invalid operands to binary ==`).
   Needs either a union-equality emission path (compare `.tag` + payload) or the reject-in-sema
   diagnostic (F6 Option b, ruled out of scope by m0406). The repro's run gate cannot pass
   until then.
2. **TU payload-read lowering** — same-module TU VALUE payload access `s.Circle` now lowers to
   the tag value (`.tag = 0;`), not the payload read (`s.data.Circle`). Semantically-incorrect-
   but-crash-free after F6; a payload-read emission path is a follow-up.
3. **lisp_interpreter builtins.zig `zT_N`** — post-F1, lisp_interpreter dumps but gcc FAILs on
   5× `zT_N` undeclared (union/optional `==` comparison temp-drop class; P3-5 adjacent) + 1×
   Opt_45 null-payload global assign. Pre-existing lowerer defect, previously masked by the
   @ptrToInt sema block. F1 report concern-2. **RESOLVED (F3 closeout, 2026-08-13):** the
   lisp_defects plan's Defects A-E fixes (bare-union literals F1, module-scope null globals F2,
   nested field-store write-back F4, struct-with-union layout F5, bare-union C emission F6)
   cleared lisp_interpreter's compile AND runtime failures — it now dumps/gccs/links/runs rc=0
   and evaluates `nil`/`true`/`+`/`(quote 5)`/`cons` correctly. See the F3 closeout section.
4. **Scratch-arena optimization** — self-compile import-phase scratch OOM (F5; token array
   doubling 32K→64K in the 2 MB scratch). Candidate options (all require operator ruling,
   plan mandates 4/8/2): scratch 2→4 MB; reset scratch per-file after the parser consumes the
   token array; or move the token array to the module arena.
5. **Cross-module enum-literal switch-case dropping** — observed in F6's isolated-form switch
   test; separate pre-existing switch-path gap.
6. **json_parser / json_parser_workaround / extern_runtime_symbol_xmod** — **RESOLVED (F3,
   std_arena migration, 2026-08-08)**: the `arena_alloc_default` deferral was closed with the
   `std_arena.zig` module, not a runtime symbol — all three now link+run rc=0 on the standard
   sf runtime (see the F3 section). **`rogue_mud` / `plat_stubs_missing_xmod` — RESOLVED (F5,
   console builtins, 2026-08-13)**: the 5 `plat_*` stubs were replaced with the F2 console
   builtins (`@isWindows` + `@consoleClear`/`@consoleGotoxy`/`@consoleSetColor`/`@putChar`),
   not runtime symbols — both now link+run rc=0 on the standard sf runtime (see the F5
   section). No std-lib-deferred runtime gaps remain.

---

## F7 — std-lib plan CLOSEOUT: 21-example matrix + gate sweep + fix records (2026-08-13)

Closes the std-lib builtins plan (F1-F6, commits `cc63eb02`..`25fb7ce1`). Measured with
`/tmp/fx_subfolder/zig1` (fresh F6-source build; `sf/build/out_release/` wedged — all builds
in `/tmp`). **Full 21-example matrix (multi-module `--dump-c89 --output-dir`, standard sf
runtime `zig_runtime.c` + `zig_pal.c`, NO `net_runtime.c`):**

| # | Example | dump | gcc | link | run | Status |
|---|---------|------|-----|------|-----|--------|
| 1 | hello | 0 | 0 | 0 | 0 | FULL OK — "Hello, world!" |
| 2 | fibonacci | 0 | 0 | 0 | 0 | FULL OK — `55` |
| 3 | prime | 0 | 0 | 0 | 0 | FULL OK — `2357` |
| 4 | heapsort | 0 | 0 | 0 | 0 | FULL OK — sorted output |
| 5 | quicksort | 0 | 0 | 0 | 0 | FULL OK — asc/desc sorted |
| 6 | mandelbrot | 0 | 0 | 0 | 0 | FULL OK |
| 7 | game_of_life | 0 | 0 | 0 | 0 (40s) | FULL OK — 100 gens glider, rc=0 |
| 8 | lzw | 0 | 0 | 0 | 0 | FULL OK |
| 9 | func_ptr_return | 0 | 0 | 0 | 0 | FULL OK — `10 + 5 = 15` |
| 10 | sort_strings | 0 | 0 | 0 | 0 | FULL OK |
| 11 | days_in_month | 0 | 0 | 0 | 0 | FULL OK |
| 12 | tco_factorial | 0 | 0 | 0 | 0 | FULL OK — `fact(10)=3628800`, deep ok |
| 13 | tco_defer | 0 | 0 | 0 | 0 | FULL OK — defer fires once |
| 14 | tco_return_try | 0 | 0 | 0 | 0 | FULL OK — `count(100000)=100000` |
| 15 | json_parser | 0 | 0 | 0 | 0 | FULL OK — parses test.json (CLEARED F3) |
| 16 | json_parser_workaround | 0 | 0 | 0 | 0 | FULL OK — prints `{}` (CLEARED F3); **[2026-08-13 F3 closeout: full tree output rc=0 — SEGFAULT resolved]** |
| 17 | lisp_interpreter | 0 | 1 | 1 | — | **gcc FAIL** — pre-existing builtins.zig `zT_N` lowerer defect (5× `zT_N` undeclared + 1 Opt_45 null-payload); follow-up #3 **[2026-08-13 F3 closeout: CLEARED — dump/gcc/link/run rc=0, functionally correct]** |
| 18 | lisp_interpreter_adv | 0 | 0 | 0 | 0 | FULL OK — REPL (EOF rc=0) |
| 19 | lisp_interpreter_curr | 0 | 0 | 0 | 0 | FULL OK — `(+ 1 2)` → `3` |
| 20 | mud_server | 0 | 0 | 0 | 124 | **CANNOT RUN** — server, boots "MUD server listening on port 4000" (timeout-gated; NOT an MD5 gate) |
| 21 | rogue_mud | 0 (24 mods) | 0 | 0 | 0 | FULL OK — boots, WASD/Q, exits rc=0 on `q` (CLEARED F5) |

**End-to-end: 20/21 working** — 19 run rc=0 + mud_server boots (server, timeout-gated). The
sole gcc-FAIL is `lisp_interpreter` (pre-existing builtins.zig `zT_N` lowerer defect, NOT a
std-lib regression; previously masked by the @ptrToInt sema block — see the multi-module-fixes
plan F1 section). json_parser / json_parser_workaround (F3) and rogue_mud (F5) rows are
**deferred→fixed** and now run on the standard runtime with NO legacy object and NO
`net_runtime.c`. game_of_life needs ~10s (100 gens × 100ms sleep) — the prior 8s timeout
showed rc=124; a 40s timeout gives rc=0. **[2026-08-13 F3 closeout: this is now 21/21 — see
the F3 closeout section below.]**

### Fix records (std-lib plan F1-F6)

| Task | Commits | What landed |
|------|---------|-------------|
| F1 core I/O builtins | `cc63eb02` | `@putChar`/`@stdoutWrite`/`@stderrWrite`/`@getChar`/`@exit`/`@sleepMs` in sema/lower/emit; `repro/mi_matrix/io_builtin_test` OK |
| F2 console builtins | `b91bf296` | `@isWindows` (comptime) + `@consoleClear`/`@consoleGotoxy`/`@consoleSetColor`; `repro/mi_matrix/console_builtin_test` OK |
| F3 std.arena | `3b1e06bf` | `std_arena.zig` bump allocator; json_parser + json_parser_workaround + extern_runtime_symbol_xmod link+run — D2 gap CLOSED |
| F4 std.io migration | `737e1966`,`f3077477`,`ad0c71e7`,`05124d9c`,`54a7f2c9`,`b2d03bd3` | std.zig/std_io.zig; all 21 examples + 47 repros off `__bootstrap_*`; wrappers removed; cast helpers → `std_panic` |
| F5 rogue_mud console | `1be697e8` | rogue_mud + plat_stubs_missing_xmod on the console builtins — D4 gap CLOSED |
| F6 networking builtins | `50da2447`,`25fb7ce1` | 11 `@socket*` builtins port net_runtime.c into the emitter; std_net.zig; mud_server + rogue_mud migrate off `net_runtime.c`; F6-review null-coalesce fix |

### Gates (all PASS)

- **Corpus sweep (240 dirs): OK=233 / FAIL=3 / ICE=0 / CRASH=0 / green-guards=4** (233+3+4=240).
  FAIL=3 exactly the documented set: `field_store_drop` + `test_stub_0` (std-lib-deferred,
  `error[3048]`) + `self_embed_optional_cycle` (C89 fundamental). No new FAIL. The 3 std-lib
  repro dirs (`io_builtin_test`, `console_builtin_test`, `net_builtin_test`) all OK.
- **4 MD5 gates:** gol `b246a2fecc0b5ff4402912c49970cdae`, lisp `141994cc81ab4bbb89722b7d30af419d`,
  json `f50ce1e6800d9e1365c019e46ac61292` — **byte-identical** through F6. mud
  `fd0fdaa42a419b0e72cfdb3226a54c4a` (F6 std_net migration + F6-review null-coalesce
  re-baseline; mud NOT an MD5 gate per the operator).
- **test_analyzer_bin: PASS** — `bash sf/scripts/build_test.sh` → `5 passed, 4 failed`
  (unchanged documented baseline; the 4 fails are the pre-existing set, zero
  `sf/src/tests/*` changes in the plan range).
- QUICK_REF.md corpus baseline + MD5 table (mud `fd0fdaa4…`) + gcc recipe notes updated.
  Tech docs 00/05/07/08 line-refs verified; 05 + 07 gained the F6 socket builtins
  (was F1/F2-only).

### Deferred-gap clearance summary

All std-lib-deferred runtime gaps from the std-lib plan are CLOSED — no example or repro
needs a legacy runtime object or `net_runtime.c` anymore. The only remaining FAIL items are
the two `error[3048]` import-gap repros (`field_store_drop`, `test_stub_0` — a user program
cannot import compiler-internal modules; pass when zig1 gains a real std lib) and
`self_embed_optional_cycle` (C89 fundamental).

---

## F3 — lisp_interpreter lowerer-defects plan CLOSEOUT: 21-example matrix 21/21 + gate sweep (2026-08-13)

Closes the lisp_defects plan (Defects A-E, F1-F6, commits `535010d4`..`31de6800`). Measured
with `/tmp/fx_subfolder/zig1` (fresh F6-source build, HEAD `31de6800`; `sf/build/out_release/`
wedged — all builds in `/tmp`). **Full 21-example matrix (multi-module `--dump-c89
--output-dir`, standard sf runtime `zig_runtime.c` + `zig_pal.c`, NO `net_runtime.c`; runs
timeout-gated, cwd = example dir for json_parser*):**

| # | Example | dump | gcc | link | run | Status |
|---|---------|------|-----|------|-----|--------|
| 1 | hello | 0 | 0 | 0 | 0 | FULL OK — "Hello, world!" |
| 2 | fibonacci | 0 | 0 | 0 | 0 | FULL OK — `55` |
| 3 | prime | 0 | 0 | 0 | 0 | FULL OK — `2357` |
| 4 | heapsort | 0 | 0 | 0 | 0 | FULL OK — sorted output |
| 5 | quicksort | 0 | 0 | 0 | 0 | FULL OK — asc/desc sorted |
| 6 | mandelbrot | 0 | 0 | 0 | 0 | FULL OK |
| 7 | game_of_life | 0 | 0 | 0 | 0 | FULL OK — 100 gens glider rc=0, stdout md5 `fcbf7e7c…` (documented) |
| 8 | lzw | 0 | 0 | 0 | 0 | FULL OK |
| 9 | func_ptr_return | 0 | 0 | 0 | 0 | FULL OK — `10 + 5 = 15` |
| 10 | sort_strings | 0 | 0 | 0 | 0 | FULL OK |
| 11 | days_in_month | 0 | 0 | 0 | 0 | FULL OK |
| 12 | tco_factorial | 0 | 0 | 0 | 0 | FULL OK — `fact(10)=3628800`, deep ok |
| 13 | tco_defer | 0 | 0 | 0 | 0 | FULL OK — defer fires once |
| 14 | tco_return_try | 0 | 0 | 0 | 0 | FULL OK — `count(100000)=100000` |
| 15 | json_parser | 0 | 0 | 0 | 0 | FULL OK — parses test.json |
| 16 | json_parser_workaround | 0 | 0 | 0 | 0 | **FULL OK — no SEGFAULT**; parses test.json, prints full tree (F4-exposed SEGFAULT resolved by Defect D+E) |
| 17 | lisp_interpreter | 0 | 0 | 0 | 0 | **FULL OK — CLEARED**; dump/gcc/link/run rc=0 AND functionally correct (see below) |
| 18 | lisp_interpreter_adv | 0 | 0 | 0 | 0 | FULL OK — REPL (EOF rc=0) |
| 19 | lisp_interpreter_curr | 0 | 0 | 0 | 0 | FULL OK — `(+ 1 2)` → `3` |
| 20 | mud_server | 0 | 0 | 0 | 124 | server — boots "MUD server listening on port 4000"; client interaction verified (welcome + look + north responses) |
| 21 | rogue_mud | 0 | 0 | 0 | 0 | FULL OK — boots, exits rc=0 on `q` |

**End-to-end: 21/21 working.** `lisp_interpreter` is now dump/gcc/link/run rc=0 AND
**functionally correct** — REPL session: `(+ 1 2)` → `3`, `(quote 5)` → `5`,
`(cons 1 2)` → `(1 . 2)`, `nil` → `nil`, `true` → `true`, `(define x 10)` → `10`,
`(* x 2)` → `20`. No silent eval failure, no SEGFAULT. The pre-existing builtins.zig `zT_N`
lowerer defect (follow-up #3) is **RESOLVED** — the Defects A-E fixes (bare-union literals F1
`535010d4`, module-scope null globals F2 `5a3b2adc`, nested field-store write-back F4
`73e21c81`, struct-with-union layout F5 `8a9df9a2`, bare-union C emission F6 `31de6800`)
collectively cleared its compile AND runtime failures.

### Defects fixed by this plan (all 5, +F1/F2/F4 repros green)

| Defect | Fix task | Commit | Repro | Output |
|--------|----------|--------|-------|--------|
| A — bare-union literal in struct literal → 5× `zT_N` | F1 | `535010d4` | `union_literal_nested_xmod` | `42` |
| B — module-scope `?T = null` global typed `int` | F2 | `5a3b2adc` | `global_null_init_xmod` | `1` |
| C — nested field-access store drops write-back | F4 | `73e21c81` | `nested_field_store_xmod` / `nested_field_store_xmod2` | `4243` / `78` |
| D — `@sizeOf`/`@alignOf` struct-with-union layout ordering | F5 | `8a9df9a2` | `sizeof_struct_union_xmod` | `24` (oracle `24`) |
| E — bare union emitted as stacked C struct (arena overflow → SEGFAULT) | F6 | `31de6800` | `union_emission_layout_xmod` | `7816` |

All 6 repro dirs classify **OK** under the gcc-exit gate (dump/gcc/link/run rc=0, outputs
above verified by run). 4 MD5 gates **byte-identical** to the F2 post-Defect-A-D re-baseline
(gol `ff47d18d…`, lisp `c1cb748b…`, json `376fd681…`, mud `fd0fdaa4…`) — no re-baseline needed.
test_analyzer_bin PASS.

### Gates (all PASS)

- **Corpus sweep (246 dirs): OK=239 / FAIL=3 / ICE=0 / CRASH=0 / green-guards=4** (239+3+4=246).
  FAIL=3 exactly the documented set: `field_store_drop` + `test_stub_0` (std-lib-deferred,
  `error[3048]`) + `self_embed_optional_cycle` (C89 fundamental). Green-guards=4 unchanged
  (`eu_assign_incompat_payload`, `euvoid_val_catch`, `field_access_optional`,
  `var_declared_void`). **No new FAIL, no new ICE/CRASH, no green-guard moved.**
- **4 MD5 gates:** gol `ff47d18dc8ef00e9b8f92f5e0a14c34a`, lisp
  `c1cb748b423eef191b9c9ce7023ae2a0`, json `376fd6812ef751913bdad00de676ceb6` —
  **byte-identical**; mud `fd0fdaa42a419b0e72cfdb3226a54c4a` (mud NOT an MD5 gate per the
  operator; F6 std_net migration + null-coalesce re-baseline retained).
- **test_analyzer_bin: PASS** — `bash sf/scripts/build_test.sh` → `5 passed, 4 failed`
  (unchanged documented baseline; zero `sf/src/tests/*` changes in the plan range).
- QUICK_REF.md corpus baseline (246 dirs, 21/21) + MD5 table (post-F2 re-baseline values)
  updated to match. Tech docs 05/07/08 line-refs verified against current source.

