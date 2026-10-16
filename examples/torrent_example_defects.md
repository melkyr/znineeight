# z9play / examples — compiler defects found

Tracks compiler defects found while building the example programs. **Reset 2026-10-16:**
the earlier entries D1–D8 were all FIXED at root cause by the zig1 emitter-sanitization
milestone (2026-10-12 … 2026-10-16); their full history, and the milestone's tracked
residuals, live in git (fix commits `4056b26f`, `e526859b`, `c2772f6a`, `b7cba183`,
`649fe398`/`c4838a29`, `dcd0c9db`, `1029221f`/`40a8a36e`) and in that milestone's SDD
reports/ledger. This file now tracks only open defects; numbering restarts at D1.

_(Add new entries as D2, the next free slot, as they are found while building the
examples; entries are doc-only unless a compiler fix is separately authorized.)_

---

## D1 — A function pointer whose return type is an optional of an aggregate cannot be emitted

**Status:** OPEN (found 2026-10-16 building z9play M5b; example-only workaround documented below; compiler fix not yet authorized).

**Symptom.** A function-pointer type — or a struct field / variable of such a type —
whose return type is `?T`, where `T` is an aggregate (`struct`, `enum`, `union(enum)`;
observed with `?Key`, `?struct`, `?enum`), is not representable in seed v98:

1. **Frontend coercion rejected.** Assigning a free function whose return type is `?Key`
   to a function-pointer field fails with
   `error[3000]: type mismatch in field initialization … note: source: function / note: target: pointer`.
   The same shapes with `?u8` (optional scalar), a direct aggregate return
   (`fn (*void) Key`), or an error-union return (`fn (*void) E!T` — the D8 shape) all
   work. **Only optional-of-aggregate is broken.**
2. **Emitted C89 invalid.** Even when a shared named alias for the optional makes the
   frontend accept the coercion, the build fails at gcc:
   `zig_special_types.h:663:29: error: expected declaration specifiers or '...' before '*' token`
   / `unknown type name 'zT_…_FP_zT_…_Opt_'`. The function-pointer typedef (whose return
   type is the optional) is emitted **before** the optional typedef it references — a
   **D8-class ordering gap for `optional_type`** (the D8 fix added the edge for error
   unions; optionals are uncovered). Merely *defining* a struct with such a field (never
   assembling a literal) triggers it.

**Minimal reproducer A — frontend coercion (`probe/a.zig`):**

```zig
pub const Key = union(enum) { char: u8, sigint };
pub const Console = struct { readKey_fn: fn (*void) ?Key, state: *void };
pub fn readKey(state: *void) ?Key { _ = state; return Key{ .sigint = {} }; }
var st: u8 = 0;
pub fn main() void {
    var c: Console = Console{ .readKey_fn = readKey, .state = @ptrCast(*void, &st) };
    if (c.readKey_fn(c.state)) |k| { switch (k) { .char => |x| { _ = x; }, else => {} } }
}
```

```sh
timeout 120 /tmp/z9play_seed_v98/zig1_5_clean -fsafe -o /tmp/probe /tmp/probe/a.zig
# error[3000]: type mismatch in field initialization (source: function, target: pointer)
```

**Minimal reproducer B — emit ordering (contract defined, never assembled):**

```zig
// contract.zig
pub const Key = union(enum) { char: u8, sigint, up, down, left, right, enter, esc };
pub const Console = struct {
    clear_fn: fn (*void) void, setCursor_fn: fn (*void, u16, u16) void,
    writeStr_fn: fn (*void, []const u8) void, readKey_fn: fn (*void) ?Key,
    enterRaw_fn: fn (*void) void, leaveRaw_fn: fn (*void) void,
    width_fn: fn (*void) u16, height_fn: fn (*void) u16,
    cursorShow_fn: fn (*void, bool) void, state: *void,
};
// main.zig
const con = @import("contract.zig");
var g_c: *con.Console = undefined;
pub fn main() void { _ = g_c; }
```

```sh
zig -fsafe -o out main.zig            # rc 0
sh out/build_target.sh linux out/prog
# zig_special_types.h:663:29: error: expected declaration specifiers or '...' before '*' token
```

**Boundary probes:** `?u8` field assignment → OK; `fn (*void) Key` → OK;
`fn (*void) E!i32` → OK; `?struct`, `?enum`, `?union(enum)` → **fail**;
`var x: ?Key = f();` → only `warning[3000]` (rc 0), i.e. the optional identity mismatch
is systemic and is a hard error only on the function-pointer coercion path. A
`*const fn (*void) ?Key` cast is accepted by the frontend but emits an undefined
`zT_…_FP_…_Opt_` type name (still invalid C89).

**Root cause (hypothesis).** `typeRegistryGetOrCreateOptional`
(`sf/src/type_registry.zig:814`) caches an optional only when the payload's `state == 2`
(layout resolved), so a field's `?Key` and a function's `?Key` can be two distinct
synthetic optional ids; `typeRegistryIsAssignable`
(`sf/src/type_registry.zig:1830-1849`) compares the two `fn_type`s' `return_type` ids
directly ⇒ rejection. The emitter additionally mis-orders the fn-pointer typedef vs the
optional-return typedef (the D8-class gap).

**Example-only workaround (used by z9play M5b).** Avoid an optional-of-aggregate
fn-pointer return: return the aggregate **directly** and add an in-band sentinel.
`Key = union(enum){ none, char: u8, sigint, up, down, left, right, enter, esc }` with
`readKey_fn: fn (*void) Key` ("no key ready" = `.none`). No compiler change required.

**Compiler fix (not authorized).** Add the `fn_type`→`optional_type` return-type edge to
the C89 type-dependency relation, and intern/canonicalize optional-of-aggregate so the
fn-pointer coercion unifies. A compiler change (outside an example-only milestone);
author under a future compiler plan.
