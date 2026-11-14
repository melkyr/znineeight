# d14_original_http2_eu — D14 exact original two-level imported shape

Phase 3.5 Task 0.2 repro (test-only; no fix here).

Reconstructed from `git show 022a59f2:sf/src/std_http2.zig` (parent `bba72a1c`)
plus the `try http2Wait` call documented in the Phase 3.3 Task 7 report. The
022a59f2 tree itself was submit-only; this fixture restores the wait:

```zig
fn submitUrl(c, id) h2.Http2Error!u32 { try h2.http2Wait(c, id); return id; }
fn http2Get(c, id) h2.Http2Error!u32 { return submitUrl(c, id); }
```

`main.zig` is exactly that two-level shape (inner non-tail, outer tail).
`submitUrl` is private in `std_http2`, so the shape is reproduced locally with
the public `h2.Http2Error` and `h2.http2Wait`; `std_http2` is not edited.
Compile-only: a real suspension needs a live HTTP/2 peer.

Sibling shapes (same imported `h2.Http2Error`/`h2.http2Wait`):

- `sibling_outer_nontail.zig` — outer `var x = try submitUrl(...); return x;`.
- `sibling_tail_tail.zig` — value wait tail-returned through two levels.
- `sibling_two_value_ab.zig` / `sibling_two_value_ba.zig` — two value waits in
  both source orders.
- `sibling_mixed_void_value.zig` / `sibling_mixed_value_void.zig` — mixed void
  and value waits in both orders.
- `sibling_wrapper_catch.zig` — `catch |e| return e;` binding.
- `sibling_wrapper_if.zig` — await inside an `if` arm.

Result (`-ffast` and `-fsafe`): **no `error[3043]` on any shape**; every
non-tail bound form emits a GCC-clean C tree and builds/runs. The two tail
shapes (`main.zig`, `sibling_tail_tail.zig`) are the RED: GCC rejects the
emitted step ABI (`EU` assigned from `int` / `EU` returned where `Opt`
expected). Evidence is in
`docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md` §9.
