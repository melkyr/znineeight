# Z98 `print` formatting — Design

> **Status:** **Implemented** — whole program complete at the Task-7 closeout
> (2026-09-25); every correction paragraph in §4/§6 records what actually
> shipped. Approved 2026-09-22 (operator rulings m1162, m1172). Program-level
> spec. The plan `docs/superpowers/plans/2026-09-22-z98-print-formatting-plan.md`
> argues from this document.

**Goal:** Move the `print` formatting layer out of the compiler's ad-hoc C
runtime into a standard-library module (`std.fmt`), and bring `print` to full
parity with official Zig 0.15.2 across the whole type/format surface.

## §1 The gap this closes

`print` is a **compiler special case**. A call whose callee is named `print`
(e.g. `std.io.print`) is intercepted in lowering: `lowerPrintFmt`
(`sf/src/lower.zig:988`, from the `fn_call` arm at `:3838-3862`) parses the
format string and emits `LirInst{ .print_val = .{ .value, .type_id, .fmt } }`
(and `.print_str`) per argument. The emitter's `.print_val` arm
(`sf/src/c89_emit.zig:7889`) calls `getPrintFnName` (`sf/src/c89_emit.zig:5474-5502`),
which returns a **C runtime symbol** (`std_print_i32`, `std_print_u32`,
`std_print_i64`, `std_print_u64`, `std_print_f64`, `std_print_bool`,
`std_print_char`, `std_print_hex_*`, `std_print_str`) defined in
`sf/src/include/zig_runtime.c` (canonical copy emitted from
`sf/src/emit_support.zig`). The shipped wrapper
`std.io.print(s: [*]const c_char, ...) void` (`sf/src/std_io.zig:15`) is a stub
whose body is never reached. `sf/src/print_decomposition.zig` is dead code, and
`semantic_analyzer.zig` has no `print` handling.

This puts a **library concern in the compiler** and leaves a long tail of
divergences from official Zig (see `task-7G-report.md` for the full table):

- **Mis-routes** (fall through to `std_print_i32`): `usize` > 2^31-1,
  arbitrary-width ints of size 8 (`u40`/`i40`), wide-backed enums; array /
  pointer / function-value arguments silently print garbage (gcc warning);
  aggregates / optional / error-union produce a gcc hard error.
- **Format divergences:** `{x}` on negative signed ints prints two's-complement
  (`fffffffb`) instead of Zig's `-5`; `{x}` on small/unsigned ints is ignored;
  integer-valued floats print `7.0` instead of Zig's `7`; float `{x}` is not a
  hex-float.
- **Wrong representations:** enum `{}` prints the ordinal, not Zig's `.member`;
  `error_set` `{}` prints a global ordinal, not Zig's `error.A`.
- **Unenforced spec/type mismatches:** `{c}` on a non-`u8`, `{s}` on a
  non-string, `{x}`/`{d}` on `bool`, `{}` on a slice — all silently accepted.

## §2 Authority and operator decisions

- **Oracle:** official **Zig 0.15.2** (`/tmp/zig-x86_64-linux-0.15.2/zig`).
  Never zig0. Every Z98-vs-Zig claim is verified against this binary.
- **Option B (m1162):** implement the missing features for **full parity** —
  do not clean-reject what Zig accepts merely because Z98 lacks a printer.
- **Mangled `std.fmt.*` (m1172):** the compiler emits calls to **mangled Z98
  `std.fmt` functions**; the C-ABI `std_print_*` symbols are an internal detail
  and disappear from the emitted call sites. The abstraction is hidden behind
  `std.fmt`.
- **Auto-import (m1172):** the compiler **auto-imports `std_fmt`** whenever a
  `print` is lowered, so user code needs no new import. The detection is
  name-based and over-approximates (the Task-1 alias fix matches any
  `ident_expr`/`field_access` named `print`). **Task 10 (B8, 2026-09-25):** the
  auto-import is skipped silently when `std_fmt.zig` is absent from the search
  dirs, and the missing module is reported (`error[3048]`) only when a print
  VALUE was actually lowered — an unrelated identifier named `print` no longer
  fails a lib dir without `std_fmt.zig`, while the alias auto-import is
  preserved. When `std_fmt.zig` IS present the over-approximation only adds it
  to the module graph (an unreferenced module is pruned at emission).
- **Keep the entry (m1172):** `std.io.print` stays the user-facing entry point;
  the compiler still special-cases a callee named `print`.
- **Reject `{}` on `[]const u8` (m1170/m1172):** match Zig — a slice needs
  `{s}` (or `std.io.write`). Verified: no shipped program uses `{}` on a slice.
- **Defaults (no objection):** the low-level float→string conversion stays in
  the PAL (`pal_f64_to_str`); hex-float is hand-rolled in `std_fmt`; aggregate
  printers are compiler-generated per type; one plan.

## §3 Target architecture — the `std.fmt` seam

```
   user:  std.io.print("...{}...", .{a, b})      (unchanged entry)
              |
   lower: lowerPrintFmt  ->  per-arg static-type dispatch + format validation
              |                         (stays in the compiler)
   emit:  mangled call  ->  std_fmt.<printer>(arg)   (a normal Z98 call)
              |
   lib:   sf/src/std_fmt.zig  ->  the formatting primitives, in Z98
              |
   low:   @stdoutWrite / pal_*   (PAL builtins)
```

- **`sf/src/std_fmt.zig`** (new std module) owns the formatting layer, written
  in Z98. It is re-exported as `std.fmt` from `sf/src/std.zig`.
- The **compiler keeps** format-string parsing, per-argument static-type
  dispatch, and validation (`lowerPrintFmt` + `getPrintFnName`). It does **not**
  contain the formatting bodies.
- The compiler emits **mangled `std.fmt` calls** (cross-module), exactly like
  any other cross-module call; the `std_print_*` C-ABI names are retired.
- The compiler **auto-imports `std_fmt`** so the module (and its PAL backing)
  is present whenever a `print` is lowered.

## §4 The `std.fmt` printer API

Integer/format primitives (names indicative; final names fixed in the plan):

- `printI32(v: i32)`, `printU32(v: u32)`, `printI64(v: i64)`, `printU64(v: u64)`
- `printHexI32(v: i32)`, `printHexU32(v: u32)`, `printHexI64(v: i64)`, `printHexU64(v: u64)`
  — signed variants print **`-` followed by the hex magnitude when `v < 0`**
  (Zig `{x}` on a negative signed value: `-10` → `-a`,
  `-549755813888` → `-8000000000`), hex otherwise. **Task-2 correction
  (2026-09-25):** the original wording here and in the frozen table said
  "signed decimal"; the Zig 0.15.2 oracle prints `-` + hex magnitude, and the
  table's own recorded evidence (`p_ints ix=-8000000000`) is that form.
- `printF64(v: f64)` — **bounded-residual decimal; omits `.`+fraction when the
  value is integral** (`7.0` → `7`, `100.0` → `100`, `0.0` → `0`), matching Zig.
  **Operator ruling Q2 (2026-09-24) documented residuals** — the non-integral
  path is the PAL's 6-digit truncating printer, so `1.0/3.0` → `0.333333`
  (Zig `0.3333333333333333`); `1e20` hits the `(i64)` cast UB and prints
  `-9223372036854775808…` (Zig `100000000000000000000`); `-0.0` prints `0`
  (Zig `-0`). Full shortest-form decimal is NOT implemented by this program.
- `printBool(v: bool)`, `printChar(c: u8)`, `printStr(ptr: [*]const u8, len: usize)`
- `printEnumName(table: [*]const u8, name_off: u32, name_len: u32)` — prints the
  member name from a compiler-emitted table. **Superseded — see the Task-5
  correction below:** realized as generated per-type static helpers
  (`z98_printEnum_<tid>`) over compiler-emitted static tables, calling the
  existing `std.fmt.printStr`; no `printEnumName` function exists.
- `printErrorName(table, …)` — prints `error.<Name>`. **Superseded — see the
  Task-5 correction below:** realized as `z98_printErrorSet_<tid>` + the same
  tables + `std.fmt.printStr`.
- `printPtr(addr: usize)` — prints `T@<lowercase-hex>` with **no `0x` prefix**
  (R3 correction, 2026-09-25: the original `T@0x…` wording was a stale guess;
  Zig 0.15.2 emits `i32@7fff8668af48`). The compiler-side route uses the
  pointee's compile-time `@typeName` spelling plus the existing
  `std.fmt.printHexU64` for the runtime address (see the Task-6 correction).
- `printFloatHex(v: f64)` — hand-rolled C89 hex-float (`0x1.8p0`).

Aggregate / tuple printers are **compiler-generated per type** (Z98 has no
generics): for each aggregate type printed, the compiler emits a
`std_fmt`-style function `printStruct_<TypeId>(v)` that walks the fields and
calls the field printers, producing Zig's `. { .a = 1, .b = 2 }` / `.{ 1, 2, 3 }`
form. It is emitted into the program alongside the module.

**Task-5 correction (2026-09-25):** `printEnumName`/`printErrorName` are
realized as compiler-generated per-type `static` C helpers
(`z98_printEnum_<tid>` / `z98_printErrorSet_<tid>`) over compiler-emitted static
name tables (`z98_etab_` blob + `z98_eoff_`/`z98_elen_` offsets/lengths +
`z98_eval_` member values / `z98_escode_` global codes) that call the existing
`std.fmt.printStr`; no function was added to `std_fmt.zig`, because the
`--dump-c89` output carries the reachable std_fmt module C in full and any
addition moves the four pinned 4-MD5 gate dumps (the STOP rule forbids a
re-baseline). A `print_val.implicit` bit distinguishes a bare `{}` (name route)
from an explicit enum `{d}`/`{x}` (numeric route). Bounded residuals: packed
enum/error-set aggregate fields still reject `error[3063]`; an enum member
literal above u32 max truncates at the literal in sema (`enum_value_table` is a
`U32ToU32Map`), while the runtime value and the name lookup are exact (e.g. via
`@intToEnum`).

**Task-4 correction (2026-09-25):** implemented as one `static` C printer per
type (`z98_printStruct_<tid>` etc., an explicit depth parameter carrying
`std.fmt.default_max_depth = 3`; untagged auto unions always print `.{ ... }`),
with tuple types gaining a `typedef struct { _0, _1, ... }` C model emitted only
for tuples that hold a runtime value. **Bounded residual:**
`printFmtAggFieldsOk`/`printFmtAggFieldKindOk` accept only fields with a final
route today (integer-like minus `enum`, `bool`, `f32`/`f64`, nested aggregates;
packed fields ≤32 bits). An aggregate whose printer would read an `enum` /
`error_set` (Task 5), pointer (Task 6), array / slice / optional / error-union /
`void` field rejects the ARGUMENT with `error[3063]` (Zig accepts and prints it;
the same operator-principle class as the Q3 list in §6).

**Task-6 correction (2026-09-25):** pointer / fn-pointer `{}` follows Zig
0.15.2's ACTUAL output (**no `0x`;** row G1/G5 evidence `i32@7fff8668af48`,
`fn () void@113e860`), so the `printPtr` row above is corrected per operator
ruling R3. The route is emitted directly at the call site, not as a new
`std.fmt` function: `std_print("<@typeName(child)>@")` followed by the existing
`std.fmt.printHexU64((unsigned long long)(unsigned int)(value))`. Compile-time
delegation matches `Writer.zig:1337-1352` (`*struct`/`*union`/`*tagged`/`*tuple`
→ the pointee printer, `*enum` → the Task-5 name printer, everything else the
`T@hex` form) and is a **ONE-pointer** rule: Zig's `.many, .c` arm calls
`printAddress`, whose `@typeName(child)` is container-qualified for a named
aggregate (`main.S@addr`), so a many-pointer uses the structural name route only
— `[*]i32` prints `i32@addr`, while `[*]S`/`[*]E`/`[*]TU`/`[*]U`/`[*]PS`
aggregate FIELDS reject `error[3063]` (fix round 1, review Critical 1; same
container-qualification residual as `*?S`). The child name is rendered for the
exact Z98-expressible space
(ints/floats/bool/void/c_char/arb/pointers/many/slices/arrays/optionals/error
unions/error sets/fn), while a name containing a NAMED enum/struct/union
rejects `error[3063]` (Zig container-qualifies those, e.g. `main.S`; bounded
residual). Task 6 also extends the aggregate field closure for pointer and
fn-pointer fields (`{any}` field semantics) and adds type-dependency emission
for pointer members whose C type is the pointee typedef (fn-pointer, enum,
error set, optional, slice, array, packed aggregate). Float `{x}` is
`printFloatHex` realized as a compiler-generated `static` C89 helper
(`z98_printFloatHex32/64`, bit-for-bit `Writer.zig:1572-1720`), not a
`std_fmt.zig` function (same 4-MD5 STOP reason as Tasks 4/5).

## §5 Compiler changes (summary; exact sites in the plan)

1. **`getPrintFnName`** (`sf/src/c89_emit.zig:5474-5502`) → a width/signedness
   dispatcher over the `std.fmt` function names, keyed on
   `typeRegistryIntWidthBits` / `typeRegistryIntIsSigned`; integer-like =
   ints + arbitrary-width ints + `c_char` + `enum` + `integer_literal`.
2. **Emitted call sites** become mangled `std.fmt` calls; the runtime C
   `std_print_*` definitions retire from `zig_runtime.c` / `emit_support.zig`.
3. **Auto-import** `std_fmt` in the print-lowering path.
4. **Generated printers** for aggregates/tuples; **name tables** for enum and
   error-set (the compiler has the names). Task 5 landed this as generated
   per-type name printers + tables **outside** `std_fmt.zig` (4-MD5 constraint;
   see the Task-5 correction in §4).
5. **Format validation** in `lowerPrintFmt` (see §6).

## §6 Diagnostics and rejects

> **Correction (2026-09-25, Task 3):** the original text named the new
> no-printer code `error[3058]`; operator ruling Q1 (2026-09-24) fixes it at
> **`error[3063]`** `ERR_3063_PRINT_TYPE_NOT_SUPPORTED`, because 3058 is live
> as `ERR_3058_CONDITION_NOT_BOOL`. Task 3 also freezes the exact decision
> boundaries below from the reviewed per-case table
> (`.superpowers/sdd/2026-09-22-z98-print-formatting-plan/task-0-report.md`).

> **Correction (final whole-branch review fix wave, 2026-09-25):** two
> post-closeout findings. **(1)** An untyped `integer_literal` print argument is
> no longer forced down the 32-bit signed route: `lowerPrintArgExact`
> (`sf/src/lower.zig`) materialises the argument's exact value into its
> value-chosen carrier (`comptimeIntUntypedType`: `i32` when it fits, else
> `u32`/`i64`/`u64`, with literal-only arithmetic folded exactly like the
> unannotated-local slot type), so `3000000000` / `b2d05e00` / `-3000000000` /
> `18446744073709551615` each match the Zig 0.15.2 twin; values that fit `i32`
> keep the pre-fix temp and emit byte-identical C (fixture
> `repro/mi_matrix/stdlib_print_untyped_lit_xmod`). **(2) R11 (operator
> ruling):** a recursive aggregate (`struct Node { v: i32, next: *Node }`) or a
> mutually recursive pair (`A { b: *B }` / `B { a: *A }`) stays a documented
> bounded residual rejecting `error[3063]` where Zig 0.15.2 prints the nested
> `.{ .next = .{ ... } }` form; no recursive-printer machinery is implemented.
> The latent emitter risk is recorded with the residual: `emitAggPrinterRec`
> emits printers in post-order with no forward declarations, so relaxing the
> validator would first need forward declarations plus a recursion strategy (a
> self-cycle would not terminate; a mutual `A -> B -> A` cycle has no valid
> post-order). Fixture `repro/mi_matrix/print_recursive_aggregate_reject_xmod`.

- `error[3013]` `ERR_3013_INVALID_PRINT_SPECIFIER` — a specifier that is
  invalid **for the argument type** (Zig rejects): `{c}` on a non-`u8`
  (all non-u8 integer kinds incl. `c_char`/arbitrary-width and
  `integer_literal`); `{s}` on a non-string (non-u8 ints, bool, float, enum,
  `integer_literal`, non-`u8` slices); `{x}`/`{d}` on `bool`; float `{c}`/`{s}`;
  enum `{c}`/`{s}`; `u8 {s}`; `{}`/`{c}`/`{d}` on a `[]const u8`;
  all known specifiers on a non-`u8` slice; explicit `{d}`/`{x}`/`{c}`/`{s}` on
  aggregates and error sets (their `{}` is routed by Tasks 4/5); `{}`/`{d}` on a
  one-pointer to an array; `{}`/`{s}`/`{x}`/`{d}` on many-pointers; non-byte
  one-pointer `{s}`/`{x}`; fn-pointer `{d}`/`{x}`/`{s}`/`{c}`. The existing
  unknown-specifier check (`{q}`, multi-char `{any}`) keeps its `error[3013]`
  and is never doubled with a type diagnostic.
- **New** `error[3063]` `ERR_3063_PRINT_TYPE_NOT_SUPPORTED` — a `print`
  argument whose type Z98 has no printer for **after** option B. Four uses
  (each explicit; never a default arm): (i) Zig-rejected no-printer kinds —
  `[N]T` (`{}`/`{d}`/`{c}`/`{s}`/`{x}`), `?T {}`, `E!T {}`, function-body
  values, `undefined`, and the exotic/unreachable kinds; (ii) the operator-ruled
  Q3 bounded residuals (`{}` on `void`/`null`/`type`; `[]u8`/`[]const u8 {x}`;
  `[N]u8 {s}`/`{x}`; `*const [N]u8 {s}`/`{x}` — where Zig accepts; `[*c]u8
  {s}`/`{x}` is a Zig-side-only entry: Z98 cannot parse a C-pointer type, so
  the site parse-rejects `error[2000]` before the validator runs); (iii)
  Zig-rejected forms with no Z98 printer (the `undefined`
  row); (iv) **operator ruling R10 (2026-09-25):** a bare `error.X` print
  argument with no expected type (a bare error literal has no inference site in
  Z98 sema and resolves to `void`) — a **documented divergence**, because
  official Zig 0.15.2 accepts it and prints `error.X`
  (`std.debug.print("e={}\n", .{error.A})` -> `e=error.A`, rc 0). Recorded in
  the fixture header, `EXPECTED_FAIL.md` and QUICK_REF; kept as a bounded
  residual. The R5 boundary is `error[3013]` for `{c}` on an `integer_literal`
  (Zig accepts an in-range literal — documented residual). `(ii)` plus the
  `void` rows require the `TEMP_NONE`/temp-range guard at the `.print_val`
  argument deref, without which `print("{}", .{f()})` (`f() void`) SIGSEGVs
  the compiler.
- Both are level 0 at the **argument node's** span → rc=2 / 0 `.c`. A bare
  `{}` is tracked separately from an explicit `{d}` (aggregates and error sets
  accept the former and reject the latter); diagnostics are deduped per node.

## §7 Blast radius, gates, seed

- The compiler's own emitted C changes → **fixed point MOVES**; the seed is
  rotated **at the Task-7 closeout** (v84 → **v85**; archive md5
  `c544e251b044aef37083ca846d65be05`, archived binary md5 = fixed point
  `96c723914ec8b48fddc2a1d039e49141`).
- The **4-MD5 emitted-C gates re-baseline**: the program dump now carries
  `std_fmt`'s C (previously the helpers lived in the un-dumped runtime).
- Corpus `-s0` class movement = the new fixtures only.
- `scripts/check_emit_support.sh` must stay 7/7 (any PAL/runtime edit is made in
  lockstep in both copies).
- Full QUICK_REF gate battery per task: self-compile closure, 24/24 example
  matrix, 4-MD5, std-lib runtime gate, corpus join-diff, `check_emit_support`,
  `verify_upgraded`.

## §8 Conventions

- `sf/src` changes are documented per AGENTS §1.1.1 (the `c89_emit.zig` doc, the
  runtime/PAL docs, `docs/reference/Language_Spec_Z98.md` §4's per-type
  specifier table, `docs/sf/QUICK_REF.md`).
- Each I/F task leaves a `repro/mi_matrix/` fixture (goldens from the FIXED
  compiler) + a standalone `repro/` program, and updates
  `repro/mi_matrix/EXPECTED_FAIL.md` and `scripts/stdlib/expected_dirs.txt`.
- Semantics are validated against official Zig 0.15.2, never zig0.

## §9 Plan index

- Plan: `docs/superpowers/plans/2026-09-22-z98-print-formatting-plan.md`
- Investigation of record: `.superpowers/sdd/2026-09-22-z98-manual-volume-I-plan/task-7G-report.md`
- Parent program: `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md`
