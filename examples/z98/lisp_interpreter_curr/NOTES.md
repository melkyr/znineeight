# lisp_interpreter_curr — Z98 Example

**Status:** OK (runtime verification 2026-08-06 — see "Runtime status" below)

**Entry file:** `main.zig`

**Working commit:** `0cb7891c` (F6 lisp closures)

**MD5 (`--dump-c89`):** `141994cc81ab4bbb89722b7d30af419d` [updated: 2026-08-08]
(Re-baselined 2026-08-08 — F4 `std.io` migration replaces `__bootstrap_print*` externs with
`std.io.print`/`std.io.printInt` (local `std.zig`/`std_io.zig` copies); runtime output
byte-identical to pre-F4, per F-5 AMENDMENT B. Previous `a12f2fce…` stale.)

> MD5 history: re-baselined 2026-08-03 (TCO/AMENDMENT 9-11), 2026-08-04 (F-5/F-7 stores+globals),
> 2026-08-05 (P3-6 error-code registry), 2026-08-06 (F1 @intCast range-check scope b, F6 closures)
> per the F-5 AMENDMENT B precedent ("runtime behavior is the gate, not byte-identity"). Previous
> baselines `0ad02040…` / `dd56cd23…` / `e54be381…` are stale. **F7 gate sweep (2026-08-06):
> byte-identical, no further re-baseline.**

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/lisp_interpreter_curr/main.zig -o build/lisp_interpreter_curr
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/lisp_interpreter_curr/main.zig
# produces: /tmp/out/*.c + /tmp/out/*.h + /tmp/out/zig_special_types.h
```

### GCC compile + link + run
```bash
cd /tmp/out
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog
/tmp/out/prog
```

## Expected Output
```
>  (REPL prompt, reads stdin until EOF)
```
Core language works: all arithmetic, define, recursion, conditionals, list ops, mutual
recursion + TCO, and first-class closures (F6 fix — closures now capture the current env).

## Runtime status (operator verification 2026-08-06 — updated post-F6)

The report `.superpowers/sdd/lisp-curr-runtime-test.md` documented the pre-F6 state. **F6
(commit `0cb7891c`) FIXED first-class closures** — `eval.zig:124` now captures the current
tail-call env (`curr_env.*`) instead of the stale param env (`env.*`). Runtime-verified at F7:

- **Closures now WORK:** `((make-adder 5) 3)` → `8`, `((add 10) 1)` → `11`, `((make-func 42))` →
  `42` (all were `Eval error: UnboundSymbol` pre-F6). `(square 5)` → `25` unchanged.
- **New limitation (F6-exposed, lisp-source, NOT a compiler defect):** composition of a closure
  passed as an argument — `((twice square) 3)`, `((compose square square) 3)` — now **SEGFAULTS**
  (rc=139; was `UnboundSymbol`). Root cause is a latent env-capture cycle in the interpreter
  source: `env_to_value` stores live `define`-slot pointers that are back-patched after capture.
  Tracked for a follow-up lisp-source fix; operator-accepted as "the lisp interpreter is just an
  example that's a limitation".
- **`(fact 13)` now PANICS** (`panic: integer cast overflow in @intCast`, rc=134) — the **intended**
  F1 `@intCast` range-check fix. Pre-F1 it silently wrapped to garbage `1932053504`; the zig0
  oracle panics too. This is correct behavior, not a regression.
- **Countdown OOM threshold ~3000** (unchanged): `(countdown 2000)` OK, `(countdown 3000)` →
  `Eval error: OutOfMemory`. The tail-recursive eval loop never resets the 1 MB `temp_sand` until
  the REPL line completes.
- **The REPL does NOT recover after OOM** (unchanged): after `OutOfMemory`, every subsequent line
  → `Parse error` (parse allocates in `temp_sand`, which stays full). `sand_reset` only runs on the
  success path (`main.zig:167`). Oracle-identical.

**Compiler gate status:** the md5 gate (`605b597e…`) pins byte-identical emission at HEAD; the F7
gate sweep re-verified it byte-identical. The runtime limitations above are interpreter-source
behaviors (composition SEGFAULT, OOM / no-recovery) or intended fix behavior (`(fact 13)` panic),
not zig1 miscompiles.

## Notes
Multi-file: 10 modules — sand, value, token, parser, env, eval, builtins, util, deep_copy.
[F4 2026-08-08: `__bootstrap_print*` externs → `std.io.print`/`std.io.printInt` (via local `std.zig`/`std_io.zig`/`std_arena.zig` copies). Runtime output byte-identical to pre-F4.]
