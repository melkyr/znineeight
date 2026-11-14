# parsergap_many_ptr_xmod — RED: `const P = [*]u8;` spurious `error[3000]` at use

## What it tests
A bare `many_ptr` type used as a **const type alias**:

```zig
const P = [*]u8;
```

`var q: P = @ptrCast(P, &arr);` then resolves `P` to `void` and dies with
`error[3000]: cannot declare variable of type void` — the many_ptr analogue of the
array/slice aliases fixed by A-F2. A-F2 registered `array_type|slice_type` →
`type_alias` in `symbol_registrator.zig:284` but NOT `many_ptr_type`, so the alias
never registers and the use resolves to a void type. This RED baseline is the gate
for F1 (extend the `symbol_registrator.zig:284` branch to include
`AstKind.many_ptr_type`).

## Measured baseline — RED (2026-08-17, `/tmp/fx_subfolder/zig1` at HEAD `a3c639ef`)

Run from the repro dir (CWD = repro dir; bare `@import("std")` resolves via the
installed lib at `/tmp/fx_subfolder/lib`):

```
cd repro/mi_matrix/parsergap_many_ptr_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```

- **rc=2** (frontend error; no crash)
- **`error[3000]` ×1** at the `P` use (main.zig:5, the `var q: P` line), exact diagnostic:

```
main.zig:4:4: warning[3000]: type mismatch in variable declaration — initialization type may not be compatible with declared type
pub fn main() void {
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
note: source: tuple
note: target: array
main.zig:5:4: error[3000]: cannot declare variable of type void
    var arr: [4]u8 = .{ 1, 2, 3, 4 };
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
main.zig:5:4: warning[3000]: type mismatch in variable declaration — initialization type may not be compatible with declared type
    var arr: [4]u8 = .{ 1, 2, 3, 4 };
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
note: source: many-pointer
note: target: void
```

(The tuple/array warning on the `arr` line is a benign cascade; the fatal diagnostic
is `error[3000]: cannot declare variable of type void` with note `source:
many-pointer` / `target: void` — the `P` alias resolved to void.)

- **0-byte `/tmp/x.c`** (no `.c` emitted) → frontend gap, classified FAIL (never "OK").

## Controls (must stay GREEN — the A-F2 fix)
The array_type and slice_type alias equivalents must NOT show the error:

- `const A = [10]u8;` (array_type alias) used as annotation:
  ```zig
  var b: A = undefined;
  b[0] = @intCast(u8, 3);
  std.io.printInt(@intCast(i32, b[0]));
  ```
  → **dump rc=0**, `.c` emitted (10653 B), gcc rc=0, run rc=0, prints `3`.

- `const S = []const u8;` (slice_type alias) used as annotation:
  ```zig
  var s: S = "abc";
  std.io.printInt(@intCast(i32, s[0]));
  ```
  → **dump rc=0**, `.c` emitted (10483 B), gcc rc=0, run rc=0, prints `97`.

Both run with the full recipe from the repo root:
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x`.

⇒ Only the many_ptr alias is RED; its array/slice siblings are GREEN.

## Isolated trigger
- `const P = [*]u8; var q: P = @ptrCast(P, &arr);` (many_ptr alias + annotated use):
  **dump rc=2, RED** (`error[3000] cannot declare variable of type void`).
- `const A = [10]u8; var b: A = undefined;` (array alias): **dump rc=0, GREEN**.
- `const S = []const u8; var s: S = "abc";` (slice alias): **dump rc=0, GREEN**.

## Locus (for F1)
`sf/src/symbol_registrator.zig:284` — the registerDecl init-kind switch registers
`array_type|slice_type` → `type_alias` but has no `many_ptr_type` arm. Downstream
already handles many_ptr (type_resolver.zig:922, semantic_analyzer.zig:1561,
varDeclInitNeedsNameCache returns true; ast.zig:87 `many_ptr_type = 85`), so the
F1 fix is a one-line extension of that branch.
