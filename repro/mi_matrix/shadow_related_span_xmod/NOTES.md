# shadow_related_span_xmod — Task 18 related-span pin

**Contract:** dump rc=2, 0 emitted `.c`, five `error[3057]`, and after every error
excerpt a related-span line `main.zig:<line>: note: ...` pointing at the earlier
declaration. Container-level shadows use `note: declared here`; local/param/
capture shadows use `note: previous declaration here`.

**Zig 0.15.2 oracle:** `zig build-exe -fno-emit-bin main.zig` rejects the same
shapes and prints the same note locations (`14→13`, `23→21`, `35→34`, `42→10`).
Zig additionally suppresses a later same-function shadow error once one has been
reported in that function (`const twice` at line 28 is not reported by Zig),
while Z98 reports every site; this is a pre-existing Task 7D divergence in the
count of diagnostics, not in the related-span rendering.

## Pinned stderr (seed-built `zig1_5_clean`, 2026-09-24)

```
main.zig:14:8: error[3057]: local declaration shadows an earlier declaration in an enclosing scope
    var x: i32 = 5;
        ^
main.zig:13: note: previous declaration here
main.zig:23:14: error[3057]: local declaration shadows an earlier declaration in an enclosing scope
        const outer = 2;
              ^^^^^
main.zig:21: note: previous declaration here
main.zig:28:10: error[3057]: local declaration shadows an earlier declaration in an enclosing scope
    const twice = 2;
          ^^^^^
main.zig:26: note: previous declaration here
main.zig:35:14: error[3057]: local declaration shadows an earlier declaration in an enclosing scope
    if (opt) |cap| {
              ^^^
main.zig:34: note: previous declaration here
main.zig:42:10: error[3057]: local declaration shadows an outer-scope declaration
    const g = 9;
          ^
main.zig:10: note: declared here
```

Matching Zig oracle notes: `main.zig:13:14: note: previous declaration here`
(param), `main.zig:21:9: note: previous declaration here` (outer local),
`main.zig:34:9: note: previous declaration here` (capture),
`main.zig:10:1: note: declared here` (container-level `const g`).
