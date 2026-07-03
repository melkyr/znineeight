# Z98 External C Dependency Design

## History / Background

### Bootstrap Phase (zig0 / C++98)

zig0 compiles Z98 to C89. Runtime helpers are declared as bare `extern fn`.
C prototypes come from `src/include/zig_runtime.h`, included separately at
build time. The compiler generates no forward declarations for these externs.

### Self-Hosted Phase (zig1 / Z98)

Multi-file examples need C prototypes. The first attempt had the compiler
generate forward declarations from each `extern fn`. Problems: type mismatches
(`[*]const u8` vs `const char*`), and duplicate declarations. Dedup was added,
but the fundamental issue remained — the compiler was guessing C types.

### The Fix: @cInclude

The developer explicitly declares C dependencies. C prototypes come from the
headers, not the compiler. The Zig `extern fn` becomes a pure ABI annotation.

## Syntax

const _ = @cInclude("stdio.h");       // → #include <stdio.h>
const _ = @cInclude("net_runtime.h"); // → #include "net_runtime.h"

## Bootstrap Strategy

sf/src/extern_c.zig       — zig0 compatible (bare extern fn)
sf/src/extern_c_z98.zig   — zig1 (uses @cInclude, placeholder)

examples/zig0/             — oracle (zig0 compile)
examples/z98/              — zig1 target (uses @cInclude)

When zig0 is dropped, delete extern_c.zig, rename extern_c_z98.zig → extern_c.zig.

## Future

@lispInclude, @cppInclude — same pattern, language-appropriate linkage directives.
Developer declares every external dependency. Compiler never guesses.
