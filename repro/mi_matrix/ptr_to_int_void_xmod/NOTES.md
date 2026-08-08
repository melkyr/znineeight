# ptr_to_int_void_xmod — FAIL (frontend gap, @ptrToInt result resolves to void)  [R1a, 2026-08-08]

## What it tests
A cross-module function `lib.zig` `getPtrAddr` that aligns a `[*]u8` pointer
address: `const current_pos = @ptrToInt(ptr);` then
`const aligned_pos = (current_pos + mask) & ~mask;`. `main.zig` imports
`lib.zig` and prints 1/0 based on whether the returned (aligned) address is
nonzero. Minimal reproduction of `lisp_interpreter/sand.zig:17-18`
(`const current_pos = @ptrToInt(sand.pos);` /
`const aligned_pos = (current_pos + mask) & ~mask;` — the MEM4 DUMP FAIL
example, error[3000]).

## The compiler gap
The `@ptrToInt` intrinsic's result type resolves to `void` instead of
`usize`. An untyped `const` that captures a `@ptrToInt` result
(`const current_pos = @ptrToInt(ptr);`) is rejected by sema with
`error[3000]: cannot declare variable of type void`. Should resolve to
`usize`.

NOTE (measured 2026-08-08): the task-brief's original R1a source
(`return @ptrToInt(ptr);` in a `pub fn getPtrAddr(ptr: [*]u8) usize`) does
NOT trigger the defect — the explicit `usize` return-type annotation forces
a coercion that masks the void result, and the emitted C is correct
(`zT_1 = (unsigned int)ptr; return zT_1;`; dump rc=0, prints 1). The defect
only fires when the `@ptrToInt` result is captured in an UNTYPED `const`
and then used in integer arithmetic (the `& ~mask` bitwise chain, exactly
the MEM4 lisp_interpreter trigger). This repro therefore uses that faithful
trigger form.

## Measured result (2026-08-08, sf/build/out_release/zig1)
- `zig1 --dump-c89 --output-dir DIR` → dump rc=2, 0 `.c` emitted.
- stderr: `error[3000]: cannot declare variable of type void` at
  `lib.zig:4` (`const current_pos = @ptrToInt(ptr);`).
- Expected pre-fix behavior confirmed: frontend rejection, NOT an emission
  defect.

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy compiles clean (rc=0, emits lib.c/main.c)
— an untyped `const current_pos = @ptrToInt(ptr)` + `& ~mask` chain is
valid Z98, genuine compiler gap. (Also confirmed the brief's original
`return @ptrToInt(ptr)` form is oracle-clean rc=0.)

## Expected classification
FAIL (frontend gap) until `@ptrToInt` resolves to `usize` (then the repro
compiles + runs and prints `1`).
