# C3: lzw_local_var_undeclared

## Repro Description
Local array variable `buf` declared inside an `else {}` block is not emitted
as a C declaration. The generated C code references `buf` in an array copy
loop but never declares it. Isolates the `'buf' undeclared` error from
`examples/z98/lzw/io.zig` function `writeCode()`.

## zig1 Behavior (HEAD)
**FAILS** — 1 gcc error:
```
error: 'buf' undeclared (first use in this function)
```
dump rc=0 (no ICE).

## zig0 Oracle Behavior
**0 gcc errors** — zig0 correctly emits the `buf` declaration.

## Root Cause
When a local array variable (`var buf: [N]u8 = undefined`) is declared
inside a conditional branch (if/else), the c89 emitter fails to emit the
C variable declaration. Subsequent code that copies or accesses the array
references the undeclared identifier.

In the generated C, the codegen inserts an array copy loop:
```c
{
    unsigned int _i = 0;
    while (_i < 10) {
        zT_18[_i] = buf[_i];
        _i++;
    }
}
```
But `buf` was never declared. The `zT_18` temp is declared (as
`zT_5A26C2ED_Arr_unsigned_char_1 zT_18;`) but the user variable `buf`
is missing.

The bug only manifests when the variable declaration is inside a block
scope (if/else/while body). Top-level function scope declarations work
correctly.

## Link
See: examples/z98/lzw/io.zig function writeCode() (lines 18-36)
