# RED repro: array-value local copy `const temp = a[i]` — Symptom B1

**Status:** RED (known-failing corpus repro). zig1 emits direct array-type assignments; gcc rejects with `assignment to expression with array type`.

## What it does

`swap(a: *[10]i32, i, j)` copies an array element by value into a `const temp`, then
writes elements back. The emitted C declares `temp` as an array type (`zT_*_Arr_int_10`)
and uses direct assignment (`temp = zT_5;` / `a[i] = zT_7;` / `a[j] = temp;`), which is
illegal C89 — arrays are not assignable. A per-element copy loop is required instead.

## zig1 symptom (RED)

- **dump:** `sf/build/out_release/zig1 --dump-c89 ...` → rc=0 (no crash)
- **gcc -c:** FAIL (`error: assignment to expression with array type`) on 5 lines:
  - `/tmp/B1.c:25:10: error: assignment to expression with array type`
  - `/tmp/B1.c:26:10: error: assignment to expression with array type`
  - `/tmp/B1.c:44:10: error: assignment to expression with array type`
  - `/tmp/B1.c:47:10: error: assignment to expression with array type`
  - `/tmp/B1.c:50:10: error: assignment to expression with array type`

## zig0 oracle cross-check

- **dump:** `./sf/build/zig0 --header-priority-include -o /tmp/B1or/o.c ...` → rc=0
- **gcc -c:** 0 errors — zig0 produces valid C89 with element-copy loops → proves zig1 bug.

## Layer

`c89_emit` — array l-value assignment must emit an element-copy loop. `temp` is declared
as an array type (`zT_*_Arr_int_10`) and then assigned directly instead of via the
array-copy marker pattern.

## Expected post-fix output

Program prints `11` (= `arr[0]` after swapping indices 0 and 1 in `{12, 11, 13, ...}`).
