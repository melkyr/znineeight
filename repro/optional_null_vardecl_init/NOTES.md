# Optional null var-decl init — RED reproduction

**Compiler:** zig1 @ HEAD 452f433c (branch zig1_start)
**Date:** 2026-07-10

## Expected
Program prints `11` (both optionals correctly detect `null` after `var x: ?T = null;`).

## Actual
- `zig1 --dump-c89` rc=0
- Self-assigns present: `p = p;` (line 34), `q = q;` (line 48 + 50) — `has_value = 0` targets `zT_0`/`zT_8` temps, not `p`/`q`
- `gcc -m32 -std=c89` rc=1 — fails to compile: `invalid operands to binary == (have 'zT_733AFA29_Opt_zT_811C9DC5_' and 'int')` at `p == NULL` comparison; same for `q == NULL`
- Program never reaches runtime

## Root cause
`lower.zig:3579-3591` fast-path: `dl_temp` used as both `set_optional_null` target and `assign` source. Since emitter's `resolveTempName` resolves `dl_temp` → local name `p`, the assign becomes `p = p;`. The `has_value = 0` targets a separate temp (`zT_N`), not the local.

## Cross-references
- `sf/src/lower.zig:3579-3591` — fast-path
- `sf/src/c89_emit.zig:2956-2962` — `set_optional_null` emission
- `examples/z98/lisp_interpreter_curr/main.zig:113` — `var global_env: ?*env_mod.EnvNode = null;`
- `eval.zig:10` — `var global_env: ?*env_mod.EnvNode = null;`
- `.superpowers/sdd/optnull-arch-task-1-report.md` — full investigation
