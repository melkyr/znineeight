# intcast_range_check — RED -> OK (F1, @intCast range-check)

**Task:** F1 — implement `@intCast` range-check (Option B + scope b). See
`.superpowers/sdd/task-F1-brief.md` + `.superpowers/sdd/I-intcast-range-report.md`.

**The bug (pre-fix, 2026-08-06):** a runtime `i64` value that overflows `i32` range narrows via
`@intCast(i32, i)` to a raw C cast — silently wrapping instead of panicking.

- Dump rc=0, gcc-clean (0 errors).
- Emitted C (`/tmp/x.c` line 30): `zT_6 = (int)i;` — raw C cast, no range check.
- Run: prints `-2147483648` (wrapped), rc=0 — **NO panic**.
- `grep -c "__bootstrap_i32_from_i64" /tmp/x.c` → 0 (no helper call emitted).

**The fix (F1):** lowerer marks the explicit `@intCast` checked when narrowing or
same-width reinterpret (scope b); c89_emit emits the source-aware
`__bootstrap_<DST>_from_<SRC>` helper; the 19 oracle helpers were added to the sf runtime
(`sf/src/include/zig_runtime.c` + `.h`).

**Post-fix:** emitted C contains `__bootstrap_i32_from_i64(i)`; run PANICS with
`integer cast overflow in @intCast` (nonzero exit) — the intended fix.

## Runtime check

```bash
zig1 --dump-c89 repro/mi_matrix/intcast_range_check/main.zig > /tmp/x.c
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x
/tmp/x   # post-fix: panic (integer cast overflow in @intCast), nonzero exit
```

Panic message (stderr): `panic: integer cast overflow in @intCast`, exit code nonzero
(`pal_abort`). Classification is gcc-rc based; post-fix dump rc=0 + gcc rc=0 → **OK**.
The runtime-panic on the overflowing value is the intended semantic (matches the zig0
oracle, which panics on `(fact 13)`).
