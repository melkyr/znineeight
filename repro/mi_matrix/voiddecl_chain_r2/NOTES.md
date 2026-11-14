# voiddecl_chain_r2 — import-chain depth probe  [R2, 2026-08-18]

## Purpose
Second rung of the self-compile silent-drop plan
(docs/superpowers/plans/2026-08-18-self-compile-silent-drop-plan.md).
R1 (2 modules, cross-module struct return) was GREEN. This rung escalates the
LINEAR import-chain depth to N ∈ {5, 10, 20, 40} to ask: does chain depth alone
trip the "modules silently dropped" bug (213x error[3000] during self-compile)?

## Fixture (committed state = N=40, the largest GREEN N tested)
Linear chain `main → a1 → a2 → … → a40`. Terminal `a40.zig`:

```zig
pub const T = struct { v: u32 };
pub fn make() T {
    var f = T{ .v = 42 };
    return f;
}
```

Each `aK` (1 ≤ K < N) re-exports the next module and forwards `make()`:

```zig
pub const a_next = @import("a{K+1}.zig");
pub fn make() T {
    return a_next.make();
}
```

`main.zig`:
```zig
const std = @import("std");
const a1 = @import("a1.zig");
pub fn main() void {
    var x = a1.make();
    std.io.printInt(x.v);
}
```

## Dialect adaptation (documented per brief)
The brief's forwarding form is `pub fn make() T` with a bare `T`. In the Z98
dialect this bare `T` IS accepted (it resolves through the `a_next` re-export),
so NO adaptation was needed for the committed fixture. **However**, probing
discovered a significant artifact: if the forwarding return type is written as
an explicit cross-module reference — `a_next.T`, `a2.T`, or via a local alias
`pub const T = a_next.T` — the compiler emits
`error[3000]: cannot declare variable of type void` at `main.zig`'s
`var x = a1.make()` even at chain depth N=3 (dump rc=2). The same N=3 chain with
bare `T` is GREEN. Same N=3 with re-export only (`main` calls `a1.a_next.make()`,
no forwarding fn) is also GREEN. So the tripping trigger is an explicit
cross-module type reference appearing as a function return type — not chain
depth. This is the closest R-rung hit to the self-compile signature observed so
far and is flagged for the I-DROP mechanism investigation, but it does NOT
discriminate on depth.

## Measured results (2026-08-18, /tmp/fx_subfolder/zig1, run FROM fixture dir)
Recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig` → gcc → run.

| N | dump rc | error[3000] count | gcc rc | run output | run rc | verdict |
|---|---------|-------------------|--------|------------|--------|---------|
| 5  | 0 | 0 | 0 | 42 | 0 | GREEN |
| 10 | 0 | 0 | 0 | 42 | 0 | GREEN |
| 20 | 0 | 0 | 0 | 42 | 0 | GREEN |
| 40 | 0 | 0 | 0 | 42 | 0 | GREEN |

- Largest N that stays GREEN: **40** (committed chain). No N tripped the drop.
- No first-error site applicable (no RED at any tested N).

## Ruling
**GREEN at all N. Chain depth alone does NOT trip the silent-drop bug; proceed
to R3** (the ladder's discard-the-easy-resolution step). The explicit
cross-module return-type reference artifact documented above (trips at N=3
regardless of depth) is the strongest lead so far for the real mechanism and
should be handed to R3/I-DROP as a candidate trigger dimension.
