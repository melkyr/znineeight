# parsergap_specifier_xmod — RED: invalid print specifier `{x}` SILENTLY degrades to decimal (B-F1)

## What it tests
A print-format specifier that is not `{}`/`{d}`/`{c}` is **silently accepted and
degraded to decimal** — the caller never gets an error. With a `u8` value of `65`:

```zig
std.io.print("{x}\n", .{v});   // v: u8 = 65
```

prints `65` (decimal) at runtime instead of a hex form (`0x41`/`41`) or a compile
error. B-F1: `lower.zig:549-556` captures **any** char between `{` and `}` into
`spec_fmt` with no validation, and the emitter only special-cases `'c'`. This RED
baseline is the gate for F3 (invalid specifier → compile error per operator ruling).

## Measured baseline — RED (2026-08-17, `/tmp/fx_subfolder/zig1`, repo HEAD `fd2a215f`)

Run from the repro dir (CWD = repro dir; bare `@import("std")` resolves via the
installed lib at `/tmp/fx_subfolder/lib`):

```
cd repro/mi_matrix/parsergap_specifier_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```

- **rc=0** (SILENT — no diagnostic, no crash)
- **`/tmp/x.err` is 0 bytes** (empty stderr)
- **`/tmp/x.c` = 10203 bytes** (`.c` emitted — the invalid specifier fully compiles)
- **gcc on the emitted C: rc=0** (links clean)
- **run: rc=0, prints `65`** — the degrade: `{x}` prints DECIMAL, not hex.

```
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x   # gcc rc=0
timeout 30 /tmp/x                                                                                                                          # prints: 65  run rc=0
```

- **Emitted C proof of the degrade**: the `main` body contains
  `std_print_u32(v);` — a decimal print. The emitted `.c` for `{x}` is
  **byte-identical** to the `{d}` and `{}` control outputs (`cmp` clean) — the
  invalid specifier is literally indistinguishable from a decimal print.

⇒ Full silent regression: invalid `{x}` not only passes the frontend, it compiles
AND runs and prints decimal `65`. Classified **FAIL-by-silence** (a valid-looking
frontend gap — must be classified FAIL, never OK).

## Second specifier case: the space `"{} {}"` — also silent today
Variant source (kept at `/tmp/space.zig`, not committed; dir contains exactly
`main.zig` + `NOTES.md`):

```zig
const std = @import("std");
pub fn main() void {
    var v: u8 = 65;
    std.io.print("{} {}\n", .{v, v});
}
```

Run (same command shape): `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 /tmp/space.zig > /tmp/s.c 2>/tmp/s.err; echo rc=$?`

- **rc=0** (SILENT), **`/tmp/s.err` = 0 bytes**
- **`/tmp/s.c` = 10245 bytes**, gcc rc=0
- **run: rc=0, prints `65 65`** — the space char between the two `{}` slots is
  preserved as literal text and each slot degrades (valid `{}`) to decimal.

Bonus data point — **space INSIDE the braces** `{ }` (`/tmp/spacein.zig`,
`std.io.print("{ }\n", .{v});`): **rc=0**, SILENT, `/tmp/si.c` = 10203 bytes
(byte-identical to the `{x}` output), run prints `65`. The space is captured into
`spec_fmt` (`lower.zig:553-554`), and since only `'c'` is special, it too silently
degrades to decimal. ⇒ any non-`c` char (and any char at all) inside `{}` is
silent today.

## Controls (must stay GREEN — the F3 fix must not break them)
All run with `v: u8 = 65`, same dump + gcc + run recipe.

- **`{d}`** → dump rc=0, `/tmp/ctrld.c` = **10203 B**, gcc rc=0, run rc=0, prints `65` (decimal) — **GREEN**.
- **`{c}`** → dump rc=0, `/tmp/ctrlc.c` = **10204 B**, gcc rc=0, run rc=0, prints `A` (char, 65 = 'A') — **GREEN**.
- **`{}`** → dump rc=0, `/tmp/ctrlempty.c` = **10203 B**, gcc rc=0, run rc=0, prints `65` (decimal) — **GREEN**.

All three emit `std_print_*` directly: `{d}`/`{}` → `std_print_u32(v)`, `{c}` →
`std_print_char(v)` (verified in the emitted `.c`). All GREEN and must remain GREEN.

## Expected post-fix behavior (per operator ruling — F3)
- `{x}` (and any invalid specifier, e.g. `{ }`) → **compile error** (frontend
  diagnostic, e.g. `error[NNNN] invalid format specifier`, nonzero rc, 0 `.c`
  emitted) — the silent degrade is the bug.
- `{d}` / `{c}` / `{}` → **rc=0**, stay GREEN (decimal / char / decimal as today).

## Locus (for F3)
- `sf/src/lower.zig:549-556` — specifier capture: `spec_fmt` defaults to `'d'`; any
  char between `{` and `}` that is not `'}'` is blindly stored as `spec_fmt`
  (`lower.zig:553-554`), no validation, no error. F3 must validate the specifier
  here (or in the print-decomposition pass) and emit a compile error for anything
  other than `d`/`c`/empty.
- `sf/src/c89_emit.zig:3180-3193` (`getPrintFnName`) — the emission split: for a u8
  type only `fmt == 'c'` routes to `std_print_char` (`c89_emit.zig:3187-3190`);
  every other `fmt` (including `'x'`, `' '`) routes to `std_print_u32` (decimal).
- `sf/src/c89_emit.zig:5114-5132` — `.print_val` LIR inst emission calls
  `getPrintFnName`; the bad specifier surfaces here as a wrong printer call.
