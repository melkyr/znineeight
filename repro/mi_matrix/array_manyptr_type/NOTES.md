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

## Root Cause Investigation (2026-07-12)

### Root cause

**`sf/src/c89_emit.zig:1119`** — in `emitArrayType()`, the function builds a mangled C89 typedef identifier by calling `getCTypeName()` for the array's element type and copying each character into the identifier buffer. Only spaces are replaced with underscores; the `*` character from pointer type names passes through unfiltered.

For `[4][*]const u8`:
- `getCTypeName()` is called for the element type `[*]const u8` (a many-pointer to `u8`)
- `getCTypeName()` at line 516 returns `"unsigned char*"` (C type name with trailing `*`)
- The character copy loop at line 1119 only checks `if (c == 32) { c = '_'; }` — it does **not** filter `*`
- Result: the mangled identifier becomes `Arr_unsigned_char*_[4]` — the `*` between `char` and `_[4]` is illegal in a C identifier

The same copy-paste bug exists at **`sf/src/c89_emit.zig:501`** in `getCTypeName()`'s array-type branch — same `if (ac == 32)` check with no `*` filtering. This would trigger for multi-dimensional arrays like `[3][4][*]const u8`.

Full trace for `typedef unsigned char* zT_2DAE4148_Arr_unsigned_char*_[4];`:
1. `emitTypeDefinition(tid_array)` → `emitArrayType(tid_array)` (line 1157)
2. `getCTypeName(reg, mangler, tid_manyptr_u8)` → `"unsigned char*"` (line 516, special-cased `u8` many-pointer)
3. Mangled name built (lines 1116-1122): `"Arr_" + "unsigned_char*_[4]"` → identifier `Arr_unsigned_char*_[4]`
4. `typedef unsigned char* zT_..._Arr_unsigned_char*_[4];` emitted (lines 1126-1135)
5. gcc rejects the `*` inside the C identifier token

### Oracle contrast

zig0 does **not** emit any typedef for the `[4][*]const u8` array type. Instead it inlines the declaration:
```c
unsigned char const* words[4];
```
No typedef needed — valid C89, 0 gcc errors.

If zig0 were to emit a typedef, any correct C emitter must ensure the mangled identifier contains only `[A-Za-z0-9_]`, never `*`.

### Proposed fix approach (NOT applied)

In `emitArrayType()` (line 1119) and `getCTypeName()` array branch (line 501), the character-copying loop must additionally filter `*` characters when building the mangled identifier. Replace `*` with a safe token such as `'p'` (for "pointer") or skip it:
- Line 1119: Change `if (c == 32) { c = '_'; }` to also handle `c == '*'` (e.g. `if (c == 32) { c = '_'; } else if (c == '*') { c = 'p'; }`)
- Line 501: Same change (identical copy-paste code)

This fix is **NOT** applied — investigation only.
