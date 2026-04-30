# Bug Report: zig0 cross-module import resolves type names incorrectly

## Symptom

When `main.zig` imports `lexer.zig` (either at top level or via `@import` inside a function body), zig0 reports "use of undeclared type" for the `Lexer` type at `lexer.zig:12` — even though `Lexer` is defined as `pub const Lexer = struct { ... }` at `lexer.zig:1` in the same file.

Standalone `./zig0 sf/src/lexer.zig` compiles cleanly. The error only occurs when lexer.zig is imported by another module (main.zig).

## Exact Reproduce Steps (from CURRENT codebase state on branch `zig1_start`)

```
cd /workspace/znineeight
git checkout zig1_start
./zig0 -o out/zig1.c sf/src/main.zig
```

### Expected: zig0 compiles all modules, emitting C89 to out/.
### Actual: "error: use of undeclared type" at sf/src/lexer.zig:12.

## Files

- `sf/src/lexer.zig:1` — `pub const Lexer = struct { ... }` (struct definition)
- `sf/src/lexer.zig:12` — `pub fn lexerInit(...) Lexer {` (uses `Lexer` return type — "undeclared")
- `sf/src/main.zig:59` — `const lexer_mod = @import("lexer.zig");` (triggers the bug)
- `sf/src/dump.zig` — imports lexer.zig (via function-level `@import`)

## Code State Triggering the Bug

In `sf/src/main.zig`, the lexer is imported once at function scope:

```zig
pub fn main(argc: i32, argv: [*]*const u8) void {
    pal.initArgs(argc, argv);
    var cli = parseArgs();
    const lexer_mod = @import("lexer.zig");  // <-- triggers bug
    ...
}
```

This single import replaces what was previously three separate `@import("lexer.zig")` inside each `if` block (sanity_test, test_mode, dump_tokens). The consolidated import is what fails.

## Key Finding

The bug is NOT caused by duplicate imports. Even a **single** `@import("lexer.zig")` inside `main()` fails. The original code worked because the imports were inside separate function-local scopes (inside `if (cli.test_mode) { ... }` blocks), and zig0 may process those differently.

Lexer.zig is the only module with this issue. Other modules (allocator.zig, diagnostics.zig, token.zig, etc.) import without problems. The distinguishing factor: `Lexer` struct references `Sand` (from allocator.zig) in its fields, and functions use `Lexer` as a return type while the module also has bottom-of-file `const pal = @import("pal.zig")` and `const interner_mod = @import("string_interner.zig")`.

## Minimal Repro

```zig
// a.zig
pub const Foo = struct { x: i32 };
pub fn bar() Foo { return Foo{ .x = 42 }; }
```

```zig
// b.zig
const a = @import("a.zig");
pub fn baz() void { _ = a.bar(); }
```

```zig
// c.zig (entry)
const b = @import("b.zig");
pub fn main() void { b.baz(); }
```

Run: `./zig0 c.zig` — likely produces "use of undeclared type" for `Foo` at `a.zig:2`.

## Zig0 Version

C++98 bootstrap compiler at `src/bootstrap/`. Built from commit at `/workspace/znineeight/src/`.

## Expected Behavior

A type declared as `pub const` in the same file should be visible to all subsequent declarations in that file, regardless of which module triggered the file's compilation.

## Actual Behavior

"use of undeclared type" error on a type that is defined 11 lines earlier in the same file, only when the file is imported transitively through another module.

## Zig0 compiler flags tested

```
./zig0 -o out/zig1.c sf/src/main.zig
```

Also tested with: `./zig0 -o out/zig1.c --test-mode sf/src/main.zig` (same result).

## Workarounds Tried and Failed

1. **Import inside function body** (original): `const lexer_mod = @import("lexer.zig")` inside `if (cli.test_mode)` blocks works for test_mode/sanity_test, but adding a 3rd block for `dump_tokens` triggers the bug.
2. **Single top-of-function import**: `const lexer_mod = @import("lexer.zig")` at start of `main()`. Fails.
3. **Top-of-module import**: `const lexer_mod = @import("lexer.zig")` at file scope (before `pub fn main`). Fails.
4. **Bottom-of-module import**: `const _loader = @import("lexer.zig")` after all other declarations. Fails.
5. **Wrapper module**: `lexer_wrapper.zig` re-exports `pub const Lexer = @import("lexer.zig").Lexer;`. Fails with same error.

## Workaround That Works (but prevents dump_tokens)

Keep `@import("lexer.zig")` ONLY inside the `if (cli.sanity_test_mode)` and `if (cli.test_mode)` blocks. Do NOT add a 3rd import anywhere. This keeps test_mode working but prevents adding `--dump-tokens` support.

Root cause suspected: zig0 has a module-level type resolution cache that gets corrupted when the same type export is referenced from multiple import sites, or when a module with internal cross-references (Lexer struct → Lexer as return type) is imported alongside other modules.

## Status

Unresolved. Blocking Task 57 (`--dump-tokens` flag). Needs zig0 fix in the C++ bootstrap compiler.
