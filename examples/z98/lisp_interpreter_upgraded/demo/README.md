# lisp_interpreter_upgraded — demo feeds

This directory holds two REPL feeds for the upgraded interpreter:

- `canonical_feed.txt` / `canonical_expected.txt` — the original interpreter's
  arithmetic/cons/compare surface (Task 1 baseline). Output is fully
  deterministic: `canonical_expected.txt` must stay byte-identical
  (md5 `96654b39…`).
- `demo_feed.txt` / `demo_expected.txt` — the observable demo surface added by
  Task 3: 8 new builtins registered in `main.zig` and implemented in
  `builtins.zig` (`layout`/`address`/`eq?`/`ptr-check`/`container-of`/`bitcast`/
  `allocs`/`classify`), plus the existing `=` (kept as-is) and `nil?` etc.

## The 8 new builtins

| REPL name | Builtin fn | Arity | Behavior |
|---|---|---|---|
| `layout` | `builtin_layout` | 0 | Prints `@offsetOf(EnvNode,"value")` `@bitSizeOf(bool)` `@bitSizeOf(i64)` (e.g. `8 1 64`), returns `nil` |
| `address` | `builtin_address` | 1 | Returns `@intFromPtr(arg)` — the runtime address of the arg's perm-arena `Value` as an int |
| `eq?` | `builtin_phys_eq` | 2 | Atom-aware equality: equal `Int`/`Bool`/`Symbol` content or both `Nil` → `true`; otherwise pointer identity |
| `ptr-check` | `builtin_ptr_check` | 1 | `@intFromPtr` + `@ptrFromInt` round-trip; returns whether the rebuilt pointer equals the original |
| `container-of` | `builtin_container_of` | 0 | `@fieldParentPtr` over a module-level `DemoOuter{tag:u8,payload:u32}` local; prints whether the recovered parent equals `&o` (`true`) |
| `bitcast` | `builtin_bitcast` | 0 | `@bitCast` of `0xFFFFFFFFFFFFFFFF` (u64) to i64 → prints `-1` |
| `allocs` | `builtin_allocs` | 0 | Returns the running `value_mod.alloc_count` (deterministic count for a given feed) |
| `classify` | `builtin_classify` | 1 | Symbol argument: counts lowercase/uppercase/digit chars and prints `lower upper digit`, returns `nil` |

`demo_feed.txt` exercises only this new surface. Every feed line is
value-producing (no `Parse error`/`Eval error`).

## Determinism note (AMENDMENT 4, operator-directed)

The demo output is NOT byte-deterministic end-to-end. `(address ...)` prints the
runtime address of a perm-arena `Value`, and because the build links as PIE by
default while the kernel applies ASLR, that printed integer varies on every run:
gcc's default `-pie`/ET_DYN plus `kernel.randomize_va_space = 2` relocates the
static arena base per process. Do NOT add `-no-pie` or any other determinism
flag to make the whole file byte-stable.

The committed `demo_expected.txt` is therefore a reference capture whose
`(address)` line is a per-run sample. Behavior must be verified as follows, not
by md5 of the whole file:

- the other ten deterministic lines byte-match their hand contracts —
  `eq?` atoms `true/false/true/false`, `layout` `8 1 64` (+`nil`),
  `bitcast` `-1`, `container-of` `true`, `allocs` a stable count, `classify` `2 2 2`
  (+`nil`), `eq? l1 l1` `true`, `eq?` of two distinct `(quote (1 2))` lists `false`;
- `(address ...)` prints a positive integer (the VA sample);
- `(ptr-check ...)` returns `true`, proving the `@ptrFromInt` round-trip.

The `(address)` value is implementation-coupled to the perm-arena allocation
order and layout; regenerate `demo_expected.txt` (re-capture run 1 of
`demo_feed.txt`) if that ever changes.
