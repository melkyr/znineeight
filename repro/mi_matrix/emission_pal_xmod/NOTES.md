# emission_pal_xmod — RED fixture for the 194-closeout `pal`-undeclared class (R5, 5 errors)

Task R5 (2026-08-22). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`
(current; R tasks have not rebuilt it). Build recipe identical to the other emission_*_xmod
fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

## Purpose

Full-graph (4-module: main/mod_a/mod_b/pal + std) reproducer of the self-compile
residual class **`'pal' undeclared (first use in this function)`** (5 errors —
semantic_analyzer 3, symbol_registrator 1, type_registry 2).

## Self-compile lines reproduced (source of truth: `/tmp/emit_errs_e2down.txt`)

```
semantic_analyzer_4DBE89E5.c:1748:14: error: 'pal' undeclared (first use in this function)
semantic_analyzer_4DBE89E5.c:8613:14: error: 'pal' undeclared (first use in this function)
symbol_registrator_757C4BC5.c:3269:14: error: 'pal' undeclared (first use in this function)
type_registry_8EE489B8.c:2846:13: error: 'pal' undeclared (first use in this function)
type_registry_8EE489B8.c:4325:13: error: 'pal' undeclared (first use in this function)
```

The fixture's emitted C reproduces the byte-identical message text
(`'pal' undeclared (first use in this function)`); the column number differs
(12 vs 13/14) only because the fixture's `zT = pal;` sits at a different column.

## Fixture (verbatim)

`pal.zig` (the special builtin module under test — a minimal `pal`-like platform
module exporting the marker helpers, mirroring `sf/src/pal.zig:130,136`):
```zig
pub fn markerWrite(msg: []const u8) void {
    var i: usize = 0;
    while (i < msg.len) : (i += 1) {
        _ = msg[i];
    }
}

pub fn markerWriteInt(prefix: []const u8, value: u32) void {
    _ = prefix;
    _ = value;
}
```

`mod_a.zig` (graph filler — provides a cross-module function so the chain is 3+):
```zig
pub fn addOne(x: u32) u32 {
    return x + 1;
}
```

`mod_b.zig` (THE emission site — mirrors the self-compile's defect exactly: it
imports the pal module under a DIFFERENT alias and then references it BARE):
```zig
const mod_a = @import("mod_a.zig");
const pal_mod = @import("pal.zig");

pub fn resolveType(name_id: u32) u32 {
    var rdt_sv: []const u8 = "SVO\n";
    pal.markerWrite(rdt_sv);
    return mod_a.addOne(name_id);
}

pub fn lookupType(sym_type: u32) u32 {
    var u2n_m: []const u8 = "U2N:e";
    pal.markerWrite(u2n_m);
    return sym_type + mod_a.addOne(1);
}
```

`main.zig`:
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var t = mod_b.resolveType(5);
    t = mod_b.lookupType(t);
    std.io.printInt(@intCast(i32, t));
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`, `mod_b → pal`. 4 fixture
modules + std. `zig1` accepts the program with **rc=0 and no diagnostics** —
identical to how it accepted the self-compile's sf/src files with the same defect
(`sf/src/semantic_analyzer.zig:17` imports `pal_mod`, lines 290/293/844 call bare
`pal.markerWrite(...)`; `sf/src/symbol_registrator.zig:12` + 409-413;
`sf/src/type_registry.zig:6` + 388-393/405-410/524-542).

## Why it triggers the class (mirror of the self-compile defect)

The module `mod_b` registers a symbol for **`pal_mod`** (its import alias) but no
symbol named **`pal`**. A statement calls `pal.markerWrite(rdt_sv)` — the bare
`pal` is not declared anywhere in the module. `zig1` (same as on the self-compile)
does NOT reject this: `semanticAnalyzerResolveIdent` (`sf/src/semantic_analyzer.zig:262`)
finds no local, no symbol, no name-cache entry and falls through to `return TYPE_VOID`
(`:322`). The field access resolves the VOID base to VOID
(`semanticAnalyzerResolveFieldAccess:452-455`), the call takes the non-fn path
(`semanticAnalyzerResolveFnCall:884-895`), and the whole call resolves VOID.
Result: rc=0, no diagnostics, and the ident `pal` is left as a bare
`load_local` in the LIR.

## RED evidence (measured 2026-08-22, /tmp/fx_subfolder/zig1)

```
$ mkdir -p /tmp/r5_194
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r5_194 \
    repro/mi_matrix/emission_pal_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd /tmp/r5_194 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```

Exact gcc errors (class `'pal' undeclared`, 2 hits — one per call site):
```
mod_b_A0ED05C9.c:21:12: error: 'pal' undeclared (first use in this function)
mod_b_A0ED05C9.c:51:12: error: 'pal' undeclared (first use in this function)
```

Emitting C — the bare `pal` load, byte-identical shape to the self-compile's
`zT_127 = pal;` (`semantic_analyzer_4DBE89E5.c:1748`):
```
zT_5 = pal;      // mod_b_A0ED05C9.c:21 — bare (unmangled) 'pal' from load_local
...
zT_5 = pal;      // mod_b_A0ED05C9.c:51
```
`pal` appears nowhere else: no declaration, no mangled form.

NOTE (co-occurring secondary symptom): the SAME `zT_5 = pal;` line also triggers
`mod_b_A0ED05C9.c:21:5: error: 'zT_5' undeclared ... did you mean 'zT_9'?` — the
load's temp is VOID-typed (the ident resolved to VOID), so its C declaration is
skipped by the same hoisted-decl skip guard as the R2 zT class. In the self-compile
the analogous temp happened to carry a declared slice type (resolved-type-table
state from the full 40+-module compilation), so only `'pal'` was flagged there.
The `'pal' undeclared` error is independent of the zT temp and stays RED even if
the R2 temp-declaration fix lands.

## Probable mechanism (HYPOTHESIS — I may overturn this)

1. **Semantic resolution** (`semantic_analyzer.zig:262-323`): a bare ident with no
   local, no symbol and no name-cache entry resolves to `TYPE_VOID` with **no
   diagnostic** (`:322`). The field-access/call wrapping it also resolves VOID, so
   `zig1` accepts the module (rc=0). This is exactly what the self-compile's sf/src
   files do — the defect is a *known* bare `pal` in modules that only imported
   `pal_mod`.
2. **Lowering** (`lower.zig:2292-2399`): the field-access base ident `pal` has no
   symbol (`symbolRegistryQualifiedLookup` null), so the module-member fast path is
   skipped and `base_temp = lowerExpr(ident pal)` runs (`lower.zig:2400`). The ident
   branch (`lower.zig:2164-2288`) finds no local temp and a VOID resolved type, and
   emits `LirInst{ .load_local = .{ .name_id = interner("pal"), ... } }` (`:2286-2288`).
   The self-compile emits the identical `zT_N = pal;` IR shape.
3. **Emission** (`c89_emit.zig:4392-4440`): `.load_local` calls
   `mangleLocalName` (`c89_emit.zig:1876`), which for a name never declared as a
   local returns the **raw** identifier — `pal` (only keywords are prefixed `z_`).
   Hence `zT_5 = pal;` with `pal` unmangled.
4. **gcc**: `'pal' undeclared (first use in this function)` — byte-identical to the
   self-compile lines.

Root-cause framing for the 5-error class: `zig1` neither rejects an undeclared
identifier used as a call base (it silently resolves it to VOID) nor emits it in a
referenced-but-never-defined form. The unmangled `load_local` reference leaks the
Zig source name into C with no C declaration. Fix candidates (untested): make the
semantic analyzer emit a hard "undeclared identifier" diagnostic for a bare ident
used as a value/call base (spec-correct behavior), or have lowering drop/skip the
VOID `load_local` instead of emitting it, or have the emitter mangle/declare
non-local `load_local` targets. A source-level fix is also valid: change the
self-compile's bare `pal.` to `pal_mod.` (the V-audit files have `pal_mod` imported).

## Expected post-fix result

After the fix, `zT_5 = pal;` either disappears (clean diagnostic / dropped load) or
`pal` is emitted as a declared, mangled symbol. `gcc -c` rc=0 and the binary prints
`7`.
