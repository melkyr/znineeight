# RED repro: array-of-many-pointer type-name emission — Symptom B2

**Status:** RED. zig1 emits malformed C typedef for `[4][*]const u8`; gcc rejects on `Arr_unsigned_char*_` with stray `*`.

## What it does

Declares `var words = [4][*]const u8{ a, b, c, d }` (array of 4 many-pointers to u8 literals),
then prints `words[0]`. Expected output once fixed: `aa`.

## zig1 symptom (RED)

- **dump:** `sf/build/out_release/zig1 --dump-c89 ...` → rc=0 (no crash)
- **malformed typedef line:** `typedef unsigned char* zT_2DAE4148_Arr_unsigned_char*_[4];`
  — the `*` between the mangled name `Arr_unsigned_char` and the array marker `_[4]` is illegal C.
- **gcc -c:** FAIL (`error: expected '=', ',', ';', 'asm' or '__attribute__' before '*' token` on line 5;
  cascading `unknown type name 'zT_2DAE4148_Arr_unsigned_char'`)

## zig0 oracle cross-check

- **dump:** `./sf/build/zig0 --header-priority-include -o /tmp/B2or/o.c ...` → rc=0
- **gcc -c (main.c alone):** 0 errors — zig0 produces valid C89 → proves zig1 bug.

## Layer

`c89_emit` — type-name mangling for array-of-many-pointer. The emitted typedef inserts a
stray `*` inside the mangled identifier before the array suffix `_[4]`, producing
`Arr_unsigned_char*_[4]` instead of a valid C typedef.

## Expected post-fix output

Program prints `aa`.
