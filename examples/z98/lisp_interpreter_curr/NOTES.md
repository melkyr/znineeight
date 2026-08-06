# lisp_interpreter_curr — Z98 Example

**Status:** OK (runtime verification 2026-08-06 — see "Runtime status" below)

**Entry file:** `main.zig`

**Working commit:** `bf5d3636`

**MD5 (`--dump-c89`):** `dd56cd23984d2533eebd244ffe593791` [updated: 2026-08-06]

> MD5 history: re-baselined 2026-08-03 (TCO/AMENDMENT 9-11), 2026-08-04 (F-5/F-7 stores+globals),
> and 2026-08-05 (P3-6 error-code registry) per the F-5 AMENDMENT B precedent ("runtime behavior is
> the gate, not byte-identity"). Previous baseline `0ad02040…` is stale.

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
recursion + TCO, single-level closures.

## Runtime status (operator verification 2026-08-06) — corrections to earlier claims

The report `.superpowers/sdd/lisp-curr-runtime-test.md` verified the gated build at runtime.
Three documented claims were found to be **false / stale**:

1. **First-class closures are BROKEN** (NOT "closures work"). A closure returned as a value that
   captures **caller parameters** fails: `((make-adder 5) 3)` → `Eval error: UnboundSymbol`
   (same for `((add 10) 1)`, `((make-func 42))`, `((twice square) 3)`, `((compose square square) 3)`).
   Interpreter-source bug: `eval.zig:124` captures the `lambda`'s parameter `env.*` instead of the
   reassigned tail-call environment `curr_env.*` — call-site parameters are lost. **Oracle-identical**
   (the zig0 oracle build reproduces every failure), so this is faithful compilation of buggy
   interpreter logic, NOT a zig1 miscompile. Closures capturing **globals** and single-level
   function application DO work (`(square 5)` → 25, `((lambda (x) (* x x)) 7)` → 49, `(getz)` → 100).
2. **Countdown OOM threshold is ~3000, not 5000.** `(countdown 2000)` OK, `(countdown 3000)` →
   `Eval error: OutOfMemory`. `stress_expressions.md` says 5000-OK / 10000-OOM — stale. The
   tail-recursive eval loop never resets the 1 MB `temp_sand` until the REPL line completes.
3. **The REPL does NOT recover after OOM** (stress_expressions.md says it does). After
   `OutOfMemory`, every subsequent line → `Parse error` (parse allocates in `temp_sand`, which stays
   full). Cause: `main.zig`'s eval-error catch (`main.zig:146-161`) `continue`s **without**
   `sand_mod.sand_reset(&temp_sand)`; `sand_reset` only runs on the success path (`main.zig:167`).
   Oracle-identical. Also: `(fact 13)` does NOT panic (docs say it does) — the zig1 build silently
   wraps to `1932053504` (a zig1 `@intCast` range-check lowering gap; the oracle does panic).

**Compiler gate status:** the md5 gate (`dd56cd23…`) pins byte-identical emission; the gate is
satisfied. The runtime defects above are interpreter-source bugs (items 1, 3) or docs staleness
(items 2, 3), with item-4's fact-13 panic being a separate zig1 `@intCast` gap tracked outside the
lisp example.

## Notes
Multi-file: 10 modules — sand, value, token, parser, env, eval, builtins, util, deep_copy.
