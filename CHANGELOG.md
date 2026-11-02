# Changelog

All notable changes to this project will be documented in this file.

## [0.21.0] - "Terephthalic Acid"

### Added
- **Mutable `for` capture**: `|*item|`, `|*item, index|`, `|*_|` bind a pointer into the iterable; writes through `item.*` / `item.field` mutate in place (`d893379c`, `c45a7514`).
- **Sema-only `--check`**: runs import resolution, sema, static analyzers, and const-init; prints all diagnostics; rc 0/2 (`d893379c`, `0673563e`).
- **New diagnostics**: `error[3077]` for semantic-analysis depth (limit 130) and `error[3078]` for unsupported mutable captures (`56350635`, `d893379c`).
- **Debugger**: `-d`/`--debug` sidecar map emission plus `z9dbg` with Linux ptrace/DWARF and Win98 COFF/DWARF-in-PE backends (`4df9a753`, `566f65ce`, `7cd7e26f`).
- **GUI layer**: `std_gfx` / `std_gfx_pal` windowed DirectDraw7 cell layer, `gfx_demo`, and a 16-color GDI fallback (`b83df7e9`, `571445b9`).
- **Editor**: `z9edit` single-file editor with gap buffer, syntax/declared-identifier colors, bracket matching, undo, clipboard, and CRLF/LF preservation (`0065371b`, `629dc9b1`).
- **Themes**: `std_gfx.Theme` white/solarized/dark; `z9edit.ini`/`z9edit.cfg` config and F2 cycling (`be8d4f96`, `21dbc320`).
- **Networking/crypto std**: `std_net` extensions, `std_tcpip`, `std_crypto`, `std_cipher`, `std_ecc`, `std_asn1`, `std_x509`, `std_tls`, `std_wireguard`, `std_http` (`349b3de3`, `6e14ce78`, `2a2dc138`, `fe2c74d2`, `8af805dc`, `4858de78`, `3b98ebb3`, `ed1fcd7b`, `00ef28ea`, `7cc9f072`).
- **Algorithm std**: `std_noise`, `std_lz4`, `std_zstd`, `std_num`, `std_pathfind`, `std_physics`, `std_hpa`, `std_fold` (`10fd69c0`, `e48278ef`, `c9af1fa8`, `0231ddc9`, `abbc7ce2`, `453efcc0`, `e89acce2`, `a3abb204`).
- **Async**: `std.async` scheduler fixes, multi-module `__Z98Step_<f>`, suspending `export fn` drivers, and async/coroutine documentation (spec §4/§4.1, builtins, README, `sf/docs/tech_docs/12_async_coroutines.md`) (`b8ffe1bb`, `af2d7080`, `66446667`, `aaf6374b`, `d3bace14`, `5967496d`, `84b73b12`).
- **Examples**: `z9play`, `z9torr`, `z9dbg`, `gfx_demo`, `z9edit`, `wireguard_demo`, and TLS/HTTPS demos (`07d92393`, `37484cb6`, `566f65ce`, `b83df7e9`, `629dc9b1`, `65c20b1c`, `b9fb17bd`).
- **Seed**: committed rotating bootstrap seed; **v129** fixed point `c1bb4c0e7cbb3d9f4a808491f1a5772d` with 50-file `lib/`; Win9x companion seed zip (`53eb190d`, `a886be61`, `4a0f34ea`, `0b9e0a89`, `cdec5098`, `1e7b303a`, `b5580232`).

### Changed
- **String literals** are typed `*const [N]u8` and decay warning-cleanly in C89 output (`5b9208c7`, `821c932f`).
- **Implicit enum→int** is now rejected; use `@enumToInt` (`40fd672c`, `c153f31c`).
- **Invalid Zig coercions** now fail with `error[3000]` (`40fd672c`).
- **`zig0` is retired**; rebuild from the committed seed via `scripts/seed/build_from_seed.sh` (`fbe40e9f`).
- **Windows emission** is strict-C89, CRLF, warning-clean, and no longer passes `/Za` `/WX` `/za` `/we`; MinGW fallback scripts are generated (`6941244f`, `1339eb4a`).
- **Lowering** uses an explicit continuation stack, fixing deep-expression C-stack failures (`dd5d8a2e`, `1891be6f`, `09ed4ae5`, `c0c23ea8`, `395ccdfd`).
- **`-d`/`--debug`** requires `--output-dir` (`4df9a753`).

### Removed
- **`zig0` from the release/build path**; no zig0 binaries or archives ship in 0.21.0 (`fbe40e9f`; design §2/§5).

### Fixed
- **Coroutine emission**: `__Z98Step_<f>` is emitted in the owning module; `std.async` stores task handles by pointer and traps non-suspending `awaitTask` (`b8ffe1bb`, `af2d7080`).
- **String slicing**: switch/if string-literal prongs recover the real length; un-annotated expressions infer `[]const u8`; error-union/optional payloads coerce (`b6ec2da5`, `5fa8a3d5`).
- **False positives**: 48 spurious `warning[3000]` removed; bare enum literals lower correctly (`466fd2cc`).
- **`[*]*T` field stores** no longer ICE with `error[3043]` (`5b9208c7`).
- **`strtod`**: direct `null` optional arguments emit `(void*)NULL`; examples declare `endptr` correctly (`ee6345b2`, `1a10ebd2`).
- **Windows spill**: update-stream `fseek` elision fixed; Windows-hosted compiler matches Linux corpus classes (`4805a742`, `908fd08b`).
- **Debugger maps**: lazy sections, optional C names, COFF line RVAs, dump/step semantics (`99b2c1cf`, `9519eece`).
- **Editor**: save failure/replace/backup, wheel, clipboard, Delete, minimize/live pump (`4fcd08f2`, `1baa0199`, `4b04c597`, `fee47e86`, `6b4abb36`).
- **Theme**: black color-atlas background fixed for light themes (`b0e7fc44`).
- **Win9x**: D11 declaration ordering, CRLF, flag cleanup, warning-clean emission, MinGW fallback (`6941244f`, `1339eb4a`).
- **Win9x truth hotfix**: source identifiers reserved by MSVC 6 / OpenWatcom (`cdecl`, `near`, `far`, `stdcall`, …) plus the emitted `Z98_*`/`zig_*`/`pal_*`/`zT_*`/`zF_*`/`zG_*` namespaces are escaped in the raw-mint path while convention tokens stay raw; emitted `.bat` files are `command.com`-safe (no `set OUT`/`set CFLAGS`, no `%ERRORLEVEL%`/`&&`/`||`/`setlocal`), stop on `if errorlevel 1 goto z98_fail`, never print `Built:` after a failure, and link gcc via `@z98_link.rsp` (`cdec5098`; seed v129).

## [Unreleased]

## [0.20.0] - "Oxalic Acid"

### Added
- **Self-Hosted Compiler (zig1)**: Z98 now compiles itself — `zig1`, written in Z98, builds Z98 source deterministically to a byte-identical fixed point.
- **Deterministic Fixed Point**: `-s0` self-compiles emit byte-identical C89 at every hop; the recorded fixed-point binary md5 `10f0ca2b` is reproduced byte-for-byte.
- **Language Builtins**: `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf`, `@intFromPtr`, `@ptrFromInt`, `@fieldParentPtr`, `@bitCast`.
- **Export Support**: `export fn` / `export var`, keeping source-level symbol names in the emitted C.
- **Cross-Module `pub var` Stores**: stores to `pub var` across modules compile and link.
- **Switch Case Ranges**: inclusive (`...`) and exclusive (`..`) case ranges in switch prongs.
- **Clean Diagnostics**: stable, non-cascading error diagnostics for malformed input.
- **Target Model**: `-osl` (linux) / `-osw` (windows) and the `--target linux|windows` alias select the compile target; `@isWindows()` is target-aware.
- **std_net Extern Bindings**: target-selected `wsock32` / libc extern bindings with `WSAStartup` init, `createTcpClient`, `htonsManual`, `htonlManual`, and the `net_prelude.h` prelude header.
- **Spill Management**: `-s<N>` and `-mm<N>` spill-to-disk controls (all-spill `-s0` self-compile: ≈14.5 MB pool, ~13 MB peak RSS).
- **Upgraded Showcase Examples**: `lisp_interpreter_upgraded` (demo builtins) and `rogue_mud_upgraded` (local `i` demo + network variant) with committed canonical + demo goldens, plus the `verify_upgraded.sh` closeout harness (A1–B7).

### Changed
- **std_net Rewritten**: compiler socket builtins replaced by std_net target-selected extern bindings; the net demo client migrated from `@socket*` builtins to `std_net` (`createTcpClient`).
- **Networking Programs**: mud_server, rogue_mud (+upgraded) and the net demos now link the extern net path (linux libc; windows `wsock32` with WSAStartup init).
- **Windows std-lib Discovery**: win32 `zig1` needs an explicit std-lib dir (`-I`) — `fopen` cannot open a directory handle on Windows, so the exe-relative `lib/` auto-discovery does not fire there.

### Removed
- **`@socket*` Builtins**: 11 socket builtins removed from the compiler (semantic analyzer, lowerer, C89 emitter, LIR); direct use now produces a clean `error[3000]` (net_builtin_test).
- **Bootstrap (`zig0`) from the current build path**: the C++98 compiler is retained only as the bootstrap-era tool and release binary; current development is fully self-hosted.

### Fixed
- **WSAStartup Init**: std_net now calls `WSAStartup`, removing win32 `10093` (WSANOTINITIALISED) failures — mud_server binds and serves, and the client connects, under wine.
- **Connect Loopback**: `createTcpClient` connects to `htonl(0x7F000001)` (127.0.0.1) with `htons(port)` — no double byte-swap.

## [0.13.0] - "2-Propanol"

### Added
- **Hardened Cross-Module Type Alias Resolution**: Resolved "Transitive Alias Blockades" by enhancing `isTypeExpression` to correctly identify `NODE_MEMBER_ACCESS` originating from types or modules.
- **Systemic Symbol Table Stability**: Hardened `Scope::insert` to prevent overwriting valid symbol metadata with uninitialized `NULL` values during module-level updates.
- **Forced Local Type Resolution**: Implemented a mandatory second-pass resolution for local variables with inferred types (`TYPE_UNDEFINED`) at the end of block visitation.
- **Static Analyzer Robustness**: Decoupled `LifetimeAnalyzer` and `NullPointerAnalyzer` from scope-based lookups during post-check phases; they now utilize the `getRootSymbol` helper for provenance tracking.
- **Memory Safety**: Added proactive NULL guards in `TypeChecker::visitMemberAccess` and static analyzers to prevent crashes during analysis of incomplete or erroneous modules.
- **Developer Experience**: Added permanent trace logging for symbol resolution and type-checking phases to assist in diagnosing complex cross-module visibility issues.
- **Canonical Module Identity**: Modules now use interned absolute paths for identity, resolving type visibility issues in large multi-module projects.
- **Fixed-Point Placeholder Resolution**: Phase 0.5 now iterates until convergence (up to 10,000 passes) to handle deep transitive alias chains.
- **Deep Alias Unwrapping**: Type constants are now deeply unwrapped during placeholder resolution to find concrete underlying types immediately.
- **Aggregate Initializer Lifting**: Automatically decomposes struct/union/tuple literals in expression contexts into field assignments for C89 compatibility.
- **Enhanced Tagged Union Coercion**: Support for returning naked tag literals from control-flow branches.

## [0.12.0] - "Isophthalic acid"

### Added
- **OpenWatcom Compatibility**: The bootstrap compiler and generated C89 code are now fully compatible with the OpenWatcom 1.9 compiler suite, including optimized build scripts and standardized PAL headers.
- **Tuple Support**: Implemented Tuple types (`struct { T1, T2 }`), literals (`.{ a, b }`), and member access (`t.0`). C89 lowering uses structs with indexed fields (`field0`, `field1`, etc.).
- **Networking Support**: Added a minimal socket API to the Platform Abstraction Layer (PAL), supporting TCP server creation, `select()`, `recv()`, and `send()` on both Windows (Winsock 1.1) and POSIX.
- **MUD Server Example**: Added a minimal telnet Multi-User Dungeon (MUD) server example in `examples/mud_server/` to demonstrate networked application development in Z98.
- **Unified Logging System**: Implemented a global `Logger` architecture intercepted at the platform layer, ensuring robust debugging across 32-bit targets.
- **Documentation**: Added comprehensive test suite documentation in `tdocs/` and a detailed Lexer Design Specification.

### Fixed
- **Lifetime Analysis**: Upgraded `LifetimeAnalyzer` to detect dangling pointers in complex expressions involving field access, array indexing, and slices via recursive provenance tracking.
- **Double-Free Detection**: Major upgrade to `DoubleFreeAnalyzer` (Phases 5-8). Added multi-level aggregate tracking (nested members, arrays, tuples), transfer history diagnostics showing original owner/transfer site, path-aware `errdefer` semantics, and arena leak suppression via the `-Warena-leak` flag.
- **Aggregate Lifting**: Resolved issues where `TYPE_ANYTYPE` placeholders reached the emitter. Implemented two-layer defense for error unions and preserved direct assignments for literals.
- **C89 Global Visibility**: Fixed `CBackend::generateHeaderFile` to correctly emit `extern` declarations for public global variables while skipping type aliases and imports.
- **TypeChecker Robustness**: Improved handling of error unions in control-flow conditions (`if`, `while`) and refined lookahead disambiguation for anonymous literals (named initializers vs. tuples vs. naked tags).
- **Array Initialization**: Ensured valid C89 static initialization for global arrays of aggregates by forcing decomposition of initializers in `C89Emitter`.
- **Lexer Stability**: Resolved an infinite loop bug in the lexer when encountering tuple member access (e.g., `.0`) and stabilized numeric literal parsing.

### Changed
- **Lexer**: Standardized floating-point literal rules (must have a leading digit; `.5` is invalid) and removed `TOKEN_MEMBER_NUMBER` in favor of generic numeric member access.
- **C89 Emitter**: Optimized `emitArrayInitializer` to use positional C89 compound literals to ensure compatibility and valid static initialization.
- **PAL**: Standardized `plat_write_file` to return `long` (bytes written) and simplified `plat_accept` signature for cross-platform ease.
- **Project Status**: Marked as the final feature release for the bootstrap compiler (`zig0`). Future development transitions to the self-hosted phase.

## [0.11.0] - "para-Cresol"

### Added
- **Switch Ranges**: Support for inclusive (`...`) and exclusive (`..`) ranges in switch prongs for integers, enums, and character literals.
- **Braceless Control Flow**: Full support for braceless `if`, `while`, `for`, and `defer` statements.
- **Payload Captures**: Support for `while (optional) |capture|` and `switch (union) |capture|`.
- **Print Lowering**: `std.debug.print` is now lowered by the compiler into multiple runtime calls, allowing for safe and efficient printing on legacy systems.
- **Built-ins**: Added `@intToPtr` and optimized `@sizeOf`/`@alignOf` for all types.
- **Documentation**: Comprehensive Z98 Language Specification and updated Lisp interpreter documentation.
- **Mandelbrot Example**: Added a Mandelbrot set renderer example to demonstrate floating-point and fixed-point arithmetic capabilities.
- **C89 Compatibility Macros**: Introduced `ZIG_UNUSED` and `ZIG_INLINE` in `zig_compat.h` to ensure portability across OpenWatcom and MSVC 6.0.

### Fixed
- **Recursion**: Fully resolved recursion in Z98 applications (like the Lisp interpreter) via a "mutable slot" strategy in `eval.zig`.
- **Tagged Unions**: Fixed a critical bug where nested anonymous struct payloads in `union(enum)` initializers caused `TYPE_UNDEFINED` propagation. Introduced `TYPE_ANONYMOUS_INIT` for robust resolution.
- **C89 Compliance**: `C89Emitter` now ensures all compiler-generated temporaries (`opt_tmp`, `for_idx`) are declared at the top of their respective blocks, maintaining strict C89 definition-before-statement rules.
- **String Literals**: Resolved `-Wpointer-sign` warnings by specializing `__make_slice_u8` to accept `const char*` with internal casts.
- **Local Const Aggregates**: Fixed an issue where local `const` aggregate declarations were treated as type aliases; they now generate correct C89 initializers.
- **Switch Captures**: Fixed state corruption in loops using switch captures; captures are now correctly scoped and initialized within the loop block.
- **Visibility**: Improved cross-module symbol visibility and resolution for tagged union tags and type aliases.
- **Runtime IO**: Standardized `__bootstrap_print`, `__bootstrap_write`, and `__bootstrap_panic` to use `const char*` signatures for better platform compatibility.

### Changed
- **Toolchain**: Reverted primary build recommendation to MinGW due to ongoing incompatibilities with OpenWatcom and MSVC 6.0 for the bootstrap compiler itself.
- **Codegen**: Refactored `C89Emitter` to use centralized keyword constants and standardized statement terminators.

## [0.10.0] - "Xylene"

### Optimized
- Reduced memory usage by resetting token arena after parsing all modules and dependencies.
- Implemented a transient arena reset between file emissions in the C backend, reclaiming per-file overhead (~2.8MB saved).
- Tuned `ArenaAllocator` default chunk size to 256KB to reduce internal fragmentation.

### Fixed
- Fixed switch statement prong bodies containing expressions (e.g., function calls) by making `C89Emitter::emitStatement` handle expression nodes correctly.
- Ensured `zig_special_types.h` is included in all generated `.c` and `.h` files, resolving "unknown type name 'Slice_u8'" errors.
- Fixed placeholder finalization to preserve the original type name and generate proper C identifiers, resolving issues with recursive types and cross-module imports.
- Allowed comparison of optional types with `null` literal (`==`, `!=`).
- Improved `@ptrCast` error messages when source is an optional, suggesting `.value`.
- Fixed a potential segfault in `TypeChecker::visitFnBody` when analyzing functions returning complex union literals. Added robust null checks and forced signature resolution.
- Added `loc` field to `ASTFnDeclNode` to support precise error reporting in function bodies.

### Added
- Added common narrowing conversion helpers (`__bootstrap_u8_from_i32`, etc.) to `zig_runtime.h` to resolve implicit declaration warnings during narrowing casts.
- Supported read-only member access for optional types via `.value` and `.has_value`.
- Regression test for function return segfault in Batch 62.
- Implemented "Union Naked Tags" (Milestone 9 Phase 1 extension). Support for writing `Null` instead of `Null: void` in tagged unions.
- Improved Windows 98 compatibility: defensive console output (`WriteConsoleA`), large memory allocations (`VirtualAlloc`), and optimized build scripts.
