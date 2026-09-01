# C2: lzw_error_set_typedef

## Repro Description
Named error set `LzwError` used as error union return type `LzwError!void`.
Minimal single-file repro isolating the typedef omission pattern from `examples/z98/lzw/`.

## zig1 Behavior (HEAD)
**PASSES** — 0 gcc errors at current HEAD.
The simple error-union case (`fn encode() LzwError!void`) generates correct C typedef:
`typedef struct { int err; int is_error; } zT_08A61393_EU_1;`

## zig0 Oracle Behavior
0 gcc errors — zig0 also handles this case correctly.

## NOTE: Bug manifests in lzw example
The full `examples/z98/lzw/main.zig` (multi-module) still triggers:
```
error: unknown type name 'zT_7F0A2DCA_LzwError'
```
The named error set typedef is emitted for error unions but NOT for raw
error set variables (e.g., catch |err| captures where err type is named
error set, not error union). The minimal repro may need multi-module
imports or a pattern where the raw named error set type appears as a
variable type.

## Root Cause
c89_emit does not emit a C typedef for named error set types when the
error set is used by name (not anonymously as part of an error union).
The anonymous error union typedef `zT_08A61393_EU_1` is emitted, but the
named error set `zT_7F0A2DCA_LzwError` is not. Cross-module catch
variables referencing named error sets trigger the missing typedef.

## Link
See: examples/z98/lzw/main.zig, examples/z98/lzw/dict.zig
