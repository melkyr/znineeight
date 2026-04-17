# COMPLEMENT.md — Mitigations, Gap Analysis & Implementation Safeguards

**Version:** 1.0  
**Component:** Cross‑cutting concerns, risk mitigation strategies, missing specifications, bootstrap safeguards  
**Parent Documents:** All Z98 design specifications (`DESIGN.md v3.0`, `AST_PARSER.md`, `TYPE_SYSTEM.md`, `AST_LIR_Lowering.md`, `LIR_C89_Emission.md`, `STATIC_ANALYZERS.md`, `Error Handling & Diagnostic Strategy`)

---

## 0. Purpose

This document complements the existing design specifications by explicitly addressing:

- **High‑risk areas** identified in the senior design review, with concrete mitigation strategies.
- **Missing specifications** that are essential for a complete, robust toolchain.
- **Implementation safeguards** to prevent schedule derailment and ensure bootstrap success.

It serves as a **risk register and implementation companion** for the development team (human or AI). Each section provides actionable steps that can be converted into tasks or checklists.

---

## 1. Risk Mitigation Strategies

### 1.1 Risk 1: Type System Resolution (Kahn's Algorithm)

**Risk Statement:** The type dependency graph must correctly capture all value‑type dependencies while allowing pointers/slices to break cycles. A single missed edge results in incorrect layout or infinite loops.

**Mitigation Strategy:**

| Action | Owner | Timing | Success Criteria |
|---|---|---|---|
| **1.1.1** Implement exhaustive unit tests for `isValueDependency()` covering all `TypeKind` variants. | Dev | Milestone 4 | 100% branch coverage; test cases for primitives, pointers, slices, arrays, structs, unions, optionals, error unions. |
| **1.1.2** Add a dependency graph dumper (`--dump-type-deps`) that outputs GraphViz DOT format. Visually inspect cycles and missing edges. | Dev | Milestone 4 | Manual inspection of `eval.zig` type graph shows correct edges. |
| **1.1.3** Differential testing against `zig0`: For every reference program, compare the computed size and alignment of every resolved type. | QA | Milestone 4 | Zero mismatches in size/alignment for all types in reference programs. |
| **1.1.4** Fuzz testing of type expressions: Generate random valid type expressions (including nested pointers, arrays, optionals) and verify that Kahn's algorithm terminates with consistent layouts. | Dev | Milestone 4 | 10,000 random type expressions processed without panic or cycle. |
| **1.1.5** Cycle detection hardening: Explicitly test circular value dependencies (`struct A { b: B }`, `struct B { a: A }`) and verify that `ERR_CIRCULAR_TYPE_DEPENDENCY` is emitted and the types are poisoned. | Dev | Milestone 4 | Diagnostic emitted, compilation continues. |

---

### 1.2 Risk 2: Parser Error Recovery

**Risk Statement:** The parser must produce an `AstKind.err` node and synchronize without cascading failures. Poor recovery leads to unusable ASTs and spurious diagnostics.

**Mitigation Strategy:**

| Action | Owner | Timing | Success Criteria |
|---|---|---|---|
| **1.2.1** Formalize the synchronization token set in `PARSER_RECOVERY.md` (or inline in `AST_PARSER.md`). The set: `semicolon`, `rbrace`, `kw_fn`, `kw_const`, `kw_var`, `kw_pub`, `kw_test`, `eof`. | Dev | Milestone 2 | Documented and code‑reviewed. |
| **1.2.2** Create a corpus of malformed Z98 programs (missing semicolons, unmatched braces, invalid expressions) and add to test suite. | QA | Milestone 2 | At least 50 malformed test cases. |
| **1.2.3** Implement `--dump-ast-after-recovery` to inspect the AST produced after errors. Ensure that `AstKind.err` nodes are inserted and that subsequent valid statements are still parsed. | Dev | Milestone 2 | Manual inspection of AST dumps shows recovery. |
| **1.2.4** Stress‑test error recovery with deeply nested invalid constructs (e.g., 100 unmatched `(`). Verify that the parser does not exceed recursion limits or memory budget. | Dev | Milestone 2 | No stack overflow; memory stays within bounds. |
| **1.2.5** Differential diagnostic comparison: For malformed programs, compare the error messages (span and code) produced by `zig0` and `zig1`. Aim for parity. | QA | Milestone 2 | 90%+ match in error locations. |

---

### 1.3 Risk 3: LIR Lowering of Control Flow (Especially `switch` and `defer`)

**Risk Statement:** Tagged union switches with payload captures, nested `defer`/`errdefer`, and the TCO pattern (`while(true)` + `continue`) are non‑trivial. Incorrect lowering produces broken C code that is hard to debug.

**Mitigation Strategy:**

| Action | Owner | Timing | Success Criteria |
|---|---|---|---|
| **1.3.1** Create a dedicated LIR visualizer (`--dump-lir-graph`) that outputs basic blocks and control‑flow edges in a human‑readable format. | Dev | Milestone 7 | Inspectable LIR for all reference programs. |
| **1.3.2** Unit test every control‑flow lowering pattern in isolation: `if` without else, `if` with else, `while`, `for` (range/slice), `switch` on enum, `switch` on tagged union, `break`/`continue`, `defer` in loops, `errdefer`, `try`/`catch`. | Dev | Milestone 7 | At least 30 focused lowering tests. |
| **1.3.3** Golden‑file testing for LIR: For reference programs (`eval.zig`, `mud.zig`), capture the LIR output and store as a golden file. Changes to lowering must be reviewed against golden diff. | QA | Milestone 7 | Golden files checked into repository. |
| **1.3.4** TCO pattern validation: Write a specific test that ensures `continue` inside `while(true)` does not expand outer defers. Use `eval.zig`'s `eval` function as the canonical test. | Dev | Milestone 7 | Test passes; manual inspection of generated C shows correct defer placement. |
| **1.3.5** Runtime validation: Compile the generated C for `eval.zig` and run the Lisp test suite. Any control‑flow bug will manifest as incorrect evaluation results. | QA | Milestone 9 | All Lisp tests pass. |

---

### 1.4 Risk 4: C89 Emission Edge Cases

**Risk Statement:** C89 lacks compound literals, `bool`, `inline`, mixed declarations, and has identifier length limits. The emitter must work around all of these without introducing bugs.

**Mitigation Strategy:**

| Action | Owner | Timing | Success Criteria |
|---|---|---|---|
| **1.4.1** Establish a C89 conformance test suite consisting of small Z98 programs that exercise each C89‑sensitive feature: empty structs, 64‑bit integers, `bool` usage, 31‑char identifiers, void pointer arithmetic, etc. | QA | Milestone 8 | At least 20 conformance tests. |
| **1.4.2** Continuous integration with multiple C89 compilers: `gcc -std=c89 -pedantic -Wall -Werror`, `cl /Za /W3` (via Wine or real Windows), `wcc386 -za` (OpenWatcom). | DevOps | Milestone 8 | All CI jobs pass. |
| **1.4.3** Implement a C89 linter pass in the emitter that scans the generated C code for common C89 violations (e.g., `//` comments, trailing commas, mixed declarations) and emits internal errors if found. | Dev | Milestone 8 | Linter runs during emission, catches regressions. |
| **1.4.4** Identifier truncation collision detection: The name mangler should detect when truncation to 31 characters causes a collision and append a counter. Add unit tests for collision scenarios. | Dev | Milestone 8 | Tests pass; no silent collisions. |
| **1.4.5** Runtime helper audit: Ensure all `__bootstrap_*` functions are strictly C89 compliant and do not rely on C99 features. | Dev | Milestone 8 | Manual review of `zig_runtime.c`. |

---

### 1.5 Risk 5: `zig0` Limitations During Bootstrap

**Risk Statement:** `zig1` is written in Z98 and compiled by `zig0`. If `zig0` has bugs or missing features, `zig1` may be impossible to bootstrap.

**Mitigation Strategy:**

| Action | Owner | Timing | Success Criteria |
|---|---|---|---|
| **1.5.1** Maintain a `ZIG0_KNOWN_ISSUES.md` document listing all observed bugs or limitations in `zig0` and the workarounds employed in `zig1`. | Dev | Ongoing | Document exists and is updated. |
| **1.5.2** Implement a `--bootstrap-safe` mode in `zig1` that avoids using any language features known to trigger `zig0` bugs. This mode is used only when compiling with `zig0`. | Dev | Milestone 0 | `zig1` compiled with `zig0` passes all tests. |
| **1.5.3** Create a minimal bootstrap smoke test: a tiny Z98 program that exercises all language features used by `zig1`. Compile with `zig0` and verify it runs correctly. | Dev | Milestone 0 | Smoke test passes before major `zig1` development. |
| **1.5.4** Keep a fallback C++ implementation of any critical component that `zig0` cannot compile. This is a last resort. | Arch | — | Not needed unless bootstrap blocked. |
| **1.5.5** Engage with `zig0` maintainers (if applicable) to report and fix bugs that block bootstrap. | PM | Ongoing | Bugs fixed upstream or workarounds documented. |

---

### 1.6 Risk 6: Memory Budget Overruns

**Risk Statement:** The 16 MB limit is tight. A single unbounded allocation could blow the budget.

**Mitigation Strategy:**

| Action | Owner | Timing | Success Criteria |
|---|---|---|---|
| **1.6.1** Implement a `TrackingAllocator` that logs every allocation with size, file, and line. At the end of compilation, print peak memory usage. | Dev | Milestone 0 | Peak memory reported accurately. |
| **1.6.2** Set a development‑time memory limit of **8 MB**. This forces early detection of bloat. The limit can be raised to 16 MB for release. | Dev | Milestone 0 | CI enforces 8 MB limit; developer machines also check. |
| **1.6.3** Add `ensureCapacity()` calls before all `ArrayList` appends in hot paths to avoid reallocation cascades. | Dev | All milestones | No reallocations in steady state. |
| **1.6.4** Profile memory usage of each pipeline phase using the reference programs. Identify and optimize any phase exceeding its budget. | Dev | Milestone 9 | All phases within budget; peak < 8 MB for reference programs. |
| **1.6.5** Implement arena reset discipline: Every pass must reset its `scratch` arena before returning. Add debug assertions to detect leaks. | Dev | All milestones | Assertions enabled in debug builds. |

---

## 2. Missing Specifications & Gap Filling

### 2.1 Missing Piece 1: `zig_runtime.c` Full Specification

**Current State:** Mentioned but not fully specified.

**Required Additions:**

| Component | Specification | Priority |
|---|---|---|
| **Arena Allocator** | `typedef struct Arena { unsigned char* memory; unsigned int capacity; unsigned int used; } Arena;`<br>`Arena* arena_init(unsigned int size);`<br>`void* arena_alloc(Arena* a, unsigned int size, unsigned int align);`<br>`void arena_reset(Arena* a);`<br>`void arena_destroy(Arena* a);` | P0 |
| **Panic Handler** | `void __bootstrap_panic(const char* msg) __attribute__((noreturn));` – prints to stderr and calls `exit(3)`. | P0 |
| **Checked Conversions** | `i32 __bootstrap_checked_cast_i32(zu64 val);` – panics if out of range.<br>`u32 __bootstrap_checked_cast_u32(zu64 val);`<br>Similar for other target types. | P0 |
| **Print Helpers** | `void __bootstrap_print(const char* s);`<br>`void __bootstrap_print_int(i32 v);`<br>`void __bootstrap_print_int64(z64 v);`<br>`void __bootstrap_print_hex(u32 v);`<br>`void __bootstrap_print_str(const char* ptr, unsigned int len);`<br>`void __bootstrap_print_bool(int v);`<br>`void __bootstrap_print_char(char c);` | P0 |
| **String Comparison** | `int __bootstrap_str_eql(const char* a, const char* b);` – used for `mem_eql` in runtime. | P1 |
| **itoa / utoa** | `void __bootstrap_itoa(i32 val, char* buf, int* len);` – used by panic handler. | P1 |

**Action:** Create `zig_runtime.h` and `zig_runtime.c` as part of **Milestone 0** infrastructure. These files are compiled once and linked with every generated C program.

---

### 2.2 Missing Piece 2: Linkage and `extern` Variable Initialization

**Problem:** The emitter must produce exactly one definition per global variable across multiple modules.

**Strategy:**

| Action | Owner | Timing |
|---|---|---|
| **2.2.1** Ownership tracking: During symbol registration, designate one module as the owner of each `export` or `pub` global variable. For `extern var`, no module owns it. | Dev | Milestone 3 |
| **2.2.2** Emission rules:<br>- **Owner module:** Emit definition (`int zG_foo = 42;`) in `.c` file.<br>- **Importing module:** Emit `extern int zG_foo;` in `.h` file and include it.<br>- **`extern var`:** Emit `extern int zG_foo;` in both `.h` and `.c` (no definition). | Dev | Milestone 8 |
| **2.2.3** Linkage validation: Add a post‑emission check that every referenced global has exactly one definition. This can be done by scanning all emitted `.c` files for definitions and cross‑checking with imports. | Dev | Milestone 9 |

---

### 2.3 Missing Piece 3: `@import` of C Headers (`@cImport`)

**Current State:** Post‑self‑hosting feature. Not required for `zig1` bootstrap.

**Placeholder Strategy:**

| Action | Owner | Timing |
|---|---|---|
| **2.3.1** Document that `@cImport` is not supported in `zig1`. Emit a clear error if encountered. | Dev | Milestone 2 |
| **2.3.2** Design the extension point: The `import_expr` node already has a payload for the path. For `@cImport`, we would parse the C header using an external tool (or a built‑in C parser) and generate Z98 declarations. This is deferred to post‑self‑hosting. | Arch | Post‑Milestone 9 |

---

### 2.4 Missing Piece 4: Build System Integration

**Problem:** `zig1` emits `.c`, `.h`, and build scripts, but a full toolchain requires orchestration.

**Strategy:**

| Action | Owner | Timing |
|---|---|---|
| **2.4.1** Emit a `build.ninja` or `Makefile` alongside the C files. The build script should compile all `.c` files with the detected C89 compiler and link them with `zig_runtime.c`. | Dev | Milestone 8 |
| **2.4.2** Provide a driver script (e.g., `zig1-driver`) that invokes `zig1` to generate C, then invokes the C compiler and linker. This script is not part of the compiler binary but distributed with it. | DevOps | Milestone 9 |
| **2.4.3** Support incremental builds: The driver should only re‑emit C for changed `.zig` files and re‑compile changed `.c` files. | Future | Post‑Milestone 9 |

---

### 2.5 Missing Piece 5: Debug Information (`#line` Directives)

**Problem:** Without source mapping, debugging generated C is a nightmare.

**Strategy:**

| Action | Owner | Timing |
|---|---|---|
| **2.5.1** Emit `#line` directives in the generated C code. Before emitting any statement, emit `#line <line> "<filename>"` corresponding to the source span of the AST node being lowered. | Dev | Milestone 8 |
| **2.5.2** Ensure `#line` works with C89: The `#line` directive is part of C89 (section 3.8.4). It is supported by all target compilers. | — | — |
| **2.5.3** Add a flag `--no-line-directives` to suppress them for differential testing (to avoid spurious diffs). | Dev | Milestone 8 |

---

## 3. Implementation Safeguards & Process

### 3.1 Development Process

| Safeguard | Description |
|---|---|
| **Test‑Driven Development (TDD)** | For each component, write unit tests before implementation. Use the `test_runner.zig` framework. |
| **Differential Testing from Day One** | As soon as a pass produces output comparable to `zig0`, add it to the differential test suite. |
| **Continuous Memory Profiling** | Run all tests with `--track-memory` and fail if peak exceeds 8 MB. |
| **Code Review Checklist** | Every PR must verify: (1) No unbounded recursion, (2) Arena reset after use, (3) `@intCast` used for all `usize ↔ u32` conversions, (4) No Z98 features known to break `zig0`. |

### 3.2 Bootstrap Validation Pipeline

```text
[zig0] compiles [zig1] → zig1_zig0.exe
[zig1_zig0.exe] compiles [zig1 source] → zig1_stage1.exe
[zig1_stage1.exe] compiles [zig1 source] → zig1_stage2.exe
fc /b zig1_stage1.exe zig1_stage2.exe  → must be identical
```
