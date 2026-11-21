# d14_two_level_matrix — D14 local 15-name `E!u32` matrix

Phase 3.5 Task 0.2 repro (test-only; no fix here).

Local equivalent of the exact two-level shape using the 15-member
`std_http2.Http2Error` error set and `@asyncSuspend` leaves. `main.zig` is the
runnable canonical form:

```zig
fn submitUrl(c, id) Http2Error!u32 { try wait(c); return id; }
fn http2Get(c, id) Http2Error!u32 { return submitUrl(c, id); }
```

Runtime harness: `c = 0` prints `42 0`; `c = 1` takes the error path and prints
`0 1`. Post-fix contract in `expected.txt`/`expected.rc`.

Sibling shapes:

- `local_outer_nontail.zig` — outer `var x = try submitUrl(...); return x;`.
- `local_tail_tail.zig` — value wait tail-returned through two levels.
- `local_two_value_ab.zig` / `local_two_value_ba.zig` — two value waits in
  both source orders (outputs `42043 0` / `43042 0`).
- `local_mixed_void_value.zig` / `local_mixed_value_void.zig` — mixed void and
  value waits in both orders.
- `local_wrapper_try.zig` — `const x = try valueWait(...); return x;`.
- `local_wrapper_catch.zig` — `const x = valueWait(...) catch |e| return e;`.
- `local_wrapper_if.zig` — await inside an `if` arm.

Result (`-ffast` and `-fsafe`): **no `error[3043]` on any shape**. Every
non-tail, two-value, mixed, try, catch and if shape emits GCC-clean C, builds
and runs with the expected stdout. Only the two tail shapes (`main.zig`,
`local_tail_tail.zig`) are RED at GCC (`EU` from `int`, `EU` returned where
`Opt` expected). Evidence is in
`docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md` §9.
