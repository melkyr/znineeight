# anon_init_var_decl — GREEN GUARD (not a RED)

## Form
Anonymous tagged-union init in a **typed var-decl**:
```zig
var c: Command = .{ .Go = @intCast(i32, 7) };
```
where `Command = union(enum) { Quit: void, Go: i32 }`, then read back `.Go` via switch.

## Expected
`7`.

## Empirical result on HEAD `0abe2efa` (Task 4 Step 1b, 2026-07-08)
**ALREADY WORKS — prints `7`.** dump rc=0, gcc 0 errors, run rc=0.

Emitted C shows the payload IS written on the typed var-decl anon-init path:
```c
zT_2 = 7;
zT_1.tag = zT_3;
zT_1.payload.Go._0 = zT_2;   /* payload stored */
c = zT_1;
...
d = c.payload.Go._0;         /* read back */
```

## Why this is kept
The site-map (`.superpowers/sdd/anon-init-sitemap-report.md`) classified typed var-decl as class-B
("expected type available but NOT threaded"). That classification is EMPIRICALLY WRONG for the
tagged-union case: the typed var-decl path already threads the declared type to the anon-init, so it
already works.

This repro is therefore a **GREEN GUARD / regression test**: after Task 4 wires the `expected_type_stack`
across all 12 sites, this must STILL print `7` (the wiring must not break the already-correct typed
var-decl path, and must not perturb its byte-identical output).

## Cross-links
- Task 4 (`.opencode/plans/2026-07-08-tagged-union-payload-store.md`): expected_type_stack root fix.
- Contrast: `repro/tagged_union_anon_return` (return anon-init) and `repro/anon_init_if_arm` (if-arm
  anon-init) are genuinely RED.
