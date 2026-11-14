# Std-Lib Search Path (`@import("std")`) Design Spec

**Date:** 2026-08-14
**Status:** Approved by operator (m0983, m0985). Ready for plan.

## 1. Goal

Make `@import("std")` (and other bare module names) resolve through a **search path**, following standard-compiler practice: a CLI include-dir flag (`-I`/`--lib-dir`) plus a **default install path relative to the compiler binary**. Eliminates the ~19 duplicated `std.zig`/`std_io.zig`/`std_arena.zig`/`std_net.zig` copies across `examples/` and `repro/`. **Win9x (MSVC6/OpenWatcom) is the primary target; Linux is a side effect.**

## 2. Problem Statement

Post-std-lib-builtins, every example and repro carries a local `std.zig` (io-only or io+arena+net) + `std_io.zig` copy because bare `@import("std")` fails to resolve — the module resolver only handles relative paths / registered module names. This is ~19 byte-identical duplicated trees (std-lib final review Min-5, tracked as D1). The maintenance burden is real: each future std change must be replicated across all copies.

Standard compilers resolve their std lib against a **search path**: user `-I` dirs first, then a compiler-binary-relative install path (gcc: `GCC_EXEC_PREFIX`/sysroot include dirs; Zig: lib dir relative to the executable). The operator's decision (m0983): CLI flag **plus** a default baked-in path, resolved relative to the compiler's own location — the right practice for a compiler that ships its std lib on the install path. **Win9x is primary:** the default-path resolution must work without POSIX-only APIs (argv[0] / executable-dir derivation, backslash+forward-slash tolerant).

## 3. Architecture

- **Search-path list** in the module resolver: user-supplied `-I` dirs (in CLI order) followed by the compiler-default install path.
- **`--lib-dir <dir>` / `-I <dir>`** CLI flag(s), repeatable.
- **Default path:** resolved at startup relative to the compiler binary (argv[0]-based), e.g. `<bindir>/../lib/std/` — pointing at `sf/src/std.zig`'s siblings (a canonical `std/` lib directory). Win9x-tolerant.
- **Resolution:** bare `@import("std")` → search the list for `std.zig`; `@import("std.io")`-style dotted names → `std/io.zig` (namespace→subdir mapping) if used.
- **Migration:** after the resolver works, migrate all 21 examples + ~47 repros off local copies to `@import("std")`, and delete the ~19 duplicated trees.

## 4. Tasks

### 4.1 R — Repro: bare `@import("std")` fails

Create `repro/mi_matrix/std_import_bare_xmod/`: a module does `const std = @import("std");` and calls `std.io.printInt`. Pre-fix: dump fails (unresolved import / error[2000]-class). Post-fix: resolves via search path. NOTES.md documents the search-path mechanism.

### 4.2 I — Investigation: resolver + install-path practice

- Read `sf/src/module_registry.zig` (`moduleResolverResolve` :144, `joinPath` :109) + `import_resolver.zig` + how `main.zig` registers the entry module.
- Determine how zig0 resolves `@import` (its std-relative behavior) — cross-check the `examples/zig0/*` and `src/runtime` references.
- Research the **right install-path practice** for a Win9x-primary compiler (argv[0]/executable-dir derivation portable to MSVC6/Watcom; `GetModuleFileName`-style where available; forward/backslash handling).
- Tech doc update + report.

### 4.3 F — Search path + CLI flag + default path + migration

- Add `search_paths: []module path` to the resolver; `-I`/`--lib-dir` parsing in `main.zig` CLI; default install-path resolution at init.
- Bare-name resolution: `@import("std")` → `std.zig` in each search dir.
- Migrate 21 examples + ~47 repros to `@import("std")`; delete ~19 local `std*.zig` copies.
- Gate sweep.

## 5. Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — ⭐ SUBAGENT CHEAT-SHEET (lines 1-60). Copy exact commands.
- **Compiler under test:** `/tmp/fx_subfolder/zig1` (out_release WEDGED — use timeouts).
- **Win9x-primary:** default-path resolution MUST be portable (no POSIX-only APIs); Linux is a side effect. Flag any non-portable assumption for operator review.
- **4 MD5 gates byte-identical** UNLESS operator-approved re-baseline with runtime proof (AMENDMENT B): gol `ff47d18dc8ef00e9b8f92f5e0a14c34a`, lisp `c1cb748b423eef191b9c9ce7023ae2a0`, json `376fd6812ef751913bdad00de676ceb6`, mud `fd0fdaa42a419b0e72cfdb3226a54c4a` (mud NOT a gate). Migration changes emitted-C module hashes (import path IDs) but the migration is runtime-gated; re-baseline is EXPECTED and operator-approved if runtime-identical.
- **Corpus:** 246 dirs, OK=239/FAIL=3/GG=4. FAIL must not increase.
- **RUNTIME gates mandatory** (AGENTS §2.5.3).
- **Tech-doc maintenance:** every I-task and source-changing F-task updates the covering tech doc — `[updated: 2026-08-14]`.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read before each edit; bottom-to-top). NO sed/python/bulk transforms.
- **The plan is the ONLY authority.** STOP on any issue.
- **I-tasks report then STOP for combined operator ruling.**

## 6. Out of Scope

- Any std-lib content changes (the `std*.zig` content is fixed; only its *location/resolution* changes)
- Renaming std modules or restructuring the std lib
- Windows-target codegen (only the path-resolution portability is in scope)
- The other std-lib closeout items (D2, printInt, config const — separate closeout plan)
