# pathnorm_dup_xmod — RED: AST duplication from un-normalized import paths (defect F-PATHNORM)

## What it tests
A 3-file mutual import cycle through a `..` segment, mirroring the self-compile pattern
(`sf/src/lexer.zig` ↔ `sf/src/tests/lexer_tests.zig`) at reduced scale:

- `main.zig` → `@import("mod.zig")`
- `mod.zig` → `@import("sub/mod2.zig")`
- `sub/mod2.zig` → `@import("../mod.zig")`

`joinPath` (`sf/src/module_registry.zig:109-119`) concatenates dir + `/` + target WITHOUT
normalizing `.`/`..`, so every cycle layer yields a NEW un-normalized path string
(`sub/mod2.zig`, `sub/../mod.zig`, `sub/../sub/mod2.zig`, …), each interning to a NEW module
entry that is re-lexed + re-parsed and appends a full AST copy to the shared store. The chain
only terminates when the path string exceeds `pal.zig:23-27/52-56`'s 511-char buffer cap, at
which point the `.`-fallback resolve (`module_registry.zig:179-181`) returns the short canonical
path `./sub/mod2.zig` which dedups to an existing module (this requires the compiler to run with
CWD = the repro dir; from the repo root the terminal import instead errors `error[3048]`).

Each file carries a small unique `pub const`/`pub fn` (`mod_tag`, `mod2_tag`, `modValue`,
`mod2Value`) so module identity is observable per emitted C unit. `main` prints a value
(`modValue() = 10 + mod2Value() = 10 + 2 = 12`) via `std.io.printInt` so the repro runs.
The import chain is std-free; `@import("std")` appears only in `main` and resolves via the
installed canonical lib at `/tmp/fx_subfolder/lib/`.

## Mechanism (the defect)
3 physical fixture files but each `..` layer adds a `sub/../` prefix to the module path, so the
resolver registers the same physical file under many distinct path strings. Every distinct string
= a new `ModuleEntry` (`moduleRegistryGetOrCreateModule`, `module_registry.zig:266-272`) = a full
re-parse appending its AST to the shared store (`import_resolver.zig:100-121`). Nothing collapses
the strings because path identity is exact-string (`path_to_id` on interned path).

## Measured baseline — RED (2026-08-15, `/tmp/fx_subfolder/zig1`, branch `zig1_start`)
Run from the repro dir (CWD = `repro/mi_matrix/pathnorm_dup_xmod/`; required so the terminal
`.`-fallback resolve terminates cleanly instead of `error[3048]`):

```
/tmp/fx_subfolder/zig1 --markers --track-memory --dump-c89 --output-dir DIR main.zig
```

- **dump rc=0**
- **Parse markers `IRP:m` (module parses, `import_resolver.zig:111`): 146**
  (3 physical fixture files ⇒ post-fix expectation 3 parses + std std_io = 5)
- **Module entries `IRV:m` (`import_resolver.zig:144`): 147**
- **Emitted per-module C units: 147 `.c`** (basename breakdown: `main` 1, `mod` **72**,
  `mod2` **71**, `std` 1, `std_io` 1, `std_arena` 1) — duplicated entries appear as
  extra `_N`-suffixed units, one per module entry.
- **AST store nodes `IRN:n`: 2174** (vs ~60-100 expected for 6 physical modules)
- **`--track-memory` module arena: `mod=246K`** (full line:
  `track-memory: perm=121K mod=246K scr=255K pool=2144K type_db=15K total=622K`)
- **gcc -c of all 147 emitted units: rc=0** (0 errors)
- **link (all 147 `.o` + zig_runtime.c + zig_pal.c): rc=0**
- **run: prints `12`, rc=0**

Note: from the repo root (no `.`-fallback hit) the terminal deep import fails with
`error[3048]: could not resolve imported file 'sub/mod2.zig'` → dump rc=2. That is ALSO a direct
symptom of the same defect (the un-normalized chain overflows the 511-char file buffer), but the
CWD=repro-dir form is used so the repro both duplicates AND runs.

## Expected post-fix behavior (path normalization)
Normalize `.`/`..` in `joinPath` so each physical file has exactly one canonical path string.
Then the cycle collapses: every `@import("../mod.zig")` from any depth resolves to the same
canonical `mod.zig` entry, and the mutual import is dedup'd by module id.

- **Fixture module entries: 3** (`main.zig`, `mod.zig`, `sub/mod2.zig`) + `std`/`std_io`/`std_arena`
  = **6 total** (vs 147 RED)
- **Parse markers: 6** (vs 146 RED)
- **Emitted C units: 6** (vs 147 RED)
- **AST store nodes: ~tens** (vs 2174 RED)
- **module arena: small** (vs 246K RED)
- run still prints `12`, rc=0

## Classification
RED (duplication confirmed: 147 module entries / 146 parses ≫ 3 physical files; 72 mod.zig +
71 mod2.zig module instances from 1 physical file each). Post-fix gate: the above numbers collapse
to the 3+3 module entries while output stays `12`.
