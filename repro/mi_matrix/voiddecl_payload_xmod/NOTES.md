# voiddecl_payload_xmod — `.payload` accessor probe (AMENDMENT 5, R-PAYLOAD)

**Status: DONE** (2026-08-20, R-PAYLOAD). RED repro fixture for the tagged-union
`.payload` accessor gap — AMENDMENT 5 of the voiddecl-family plan
(docs/superpowers/plans/2026-08-18-voiddecl-family-plan.md). Same-class gap as the
F2 `.tag` fix (`semantic_analyzer.zig:475-481`): `x.payload` on a tagged union
resolves to `TYPE_VOID` (`TU_FIELD_PAYLOAD` type_registry.zig:38, currently 0 sites
in sf/src).

## Purpose

`.payload` accessor gap probe. F2 fixed the tagged-union `.tag` discriminator
accessor (commit `660ff8e2`); AMENDMENT 5 adds a latent R/I/F cluster for the
sibling `.payload` member access: `x.payload` on a `union(enum)` resolves to
`TYPE_VOID` instead of the active-variant field type. This fixture pins the RED
baseline for that gap (single-file, inline tagged union, typed `Item` var), mirroring
the F2 tagprobe fixture's shape. Trigger controller-verified before commit.

## Fixture sources

`main.zig` (verbatim, committed):

```zig
const std = @import("std");

const Item = union(enum) {
    a: u32,
    b: void,
};

pub fn main() void {
    var x: Item = undefined;
    var p = x.payload;
    std.io.printInt(p);
}
```

`.tag` GREEN control (inline variant, /tmp only — `main2_payload_control.zig`,
NOT committed):

```zig
const std = @import("std");

const Item = union(enum) {
    a: u32,
    b: void,
};

pub fn main() void {
    var x: Item = undefined;
    var t = @enumToInt(x.tag);
    std.io.printInt(t);
}
```

## RED baseline

Command (run from fixture dir, existing binary `/tmp/fx_subfolder/zig1`, no rebuild):

```
timeout 60 /tmp/fx_subfolder/zig1 --dump-c89 main.zig
```

Result — rc=2, `error[3000]: cannot declare variable of type void`, no `.c` emitted
(0-byte .c, compile aborts):

```
main.zig:10:4: error[3000]: cannot declare variable of type void
    var x: Item = undefined;
    ^^^^^^^^^^^^^^^^^^
```

- Reported line 10 is `var p = x.payload;` (the span's line); the caret prints line
  above (`var x: Item = undefined;`) — known off-by-one caret display, as in the F2
  tagprobe and R1-R4 records. The `.payload` read resolves to `TYPE_VOID`; the
  consuming `var p` hard-errors.

## GREEN control

`.tag` variant (same `Item`, `var t = @enumToInt(x.tag);`), /tmp only:

```
timeout 60 /tmp/fx_subfolder/zig1 --dump-c89 /tmp/main2_payload_control.zig
```

Result — rc=0, `.c` emitted to stdout (struct shows `unsigned int tag;` + the
variant `payload` union). The `.tag` discriminator path is GREEN; only the `.payload`
member path is under test.

## Post-fix expectation

After F-PAYLOAD: fixture compiles (dump/gcc/link rc=0); `x.payload` resolves to the
active-variant field type (u32 for `a`, void for `b`); `var p = x.payload` on a
currently-active `a: u32` prints the value. Like the tagprobe fixture, the compile
gate is the primary post-fix signal — this fixture uses `undefined`, so runtime
prints are not the gate.

## Post-fix (F-PAYLOAD, 2026-08-20)

`var p = x.payload;` now compiles GREEN: dump rc=0 + gcc rc=0, `.c` emits a REAL load
`zT_3 = x.payload.a._0;` (result-temp type = first non-void variant field type u32).
Run rc=0 (prints a garbage value — `x` is `undefined`, runtime prints are not the
gate). The 2-locus fix: sema `semantic_analyzer.zig` tagged-union branch maps
`.payload` → first non-void variant field type (array→ptr mirrored), lower
`lower.zig` emits `load_field { field_id = TU_FIELD_PAYLOAD }`.

## Commit hash + date

Base HEAD `838935ce` (pre-fixture, branch `zig1_start`), 2026-08-20. Fixture's own
commit SHA recorded in the task report (self-referencing a commit from its own tree
is not possible, so NOTES.md pins the base HEAD as in the tagprobe fixture).
