# Z98 Self-Hosted Compiler (`zig1`) – AI Agent Guidelines

**Version:** 2.0  
**Phase:** Self‑Hosted Implementation  
**Context:** `zig1` is written in Z98, compiled by `zig0`, and emits C89 code for 1998‑era targets.

---

## 0. Overview

This document defines the roles, responsibilities, methodology, and constraints for AI agents working on the **self‑hosted Z98 compiler** (`zig1`). It supersedes the previous `Agents.md` that governed the C++98 bootstrap (`zig0`) phase.

The agent's mission: **implement `zig1` according to the design specifications in `docs/sf/`**, following a 300+ task plan that culminates in a byte‑identical self‑compilation.

### 0.1 Project Context

| Aspect | Details |
|--------|---------|
| **Compiler Source Language** | Z98 (a strict subset of Zig targeting C89) |
| **Bootstrap Compiler** | `zig0` (C++98) – compiles `zig1.zig` to C89 |
| **Target Output** | C89 source code (`.c` / `.h` files) |
| **Runtime Environment** | 32‑bit Windows 9x / NT, 16 MB peak RAM |
| **Development Host** | Linux (with cross‑compilation capability) |
| **PAL** | Platform Abstraction Layer for file I/O and memory |

### 0.2 Key Documents (Located in `docs/sf/`)

| Document | Purpose |
|----------|---------|
| `Design_p2.md` v3.0 | Overall pipeline, arena allocator, memory budget |
| `AST_PARSER_p2.md` | AST representation, `AstNode`, `AstStore`, precedence climbing parser |
| `Lexer_sf.md` | Token definitions, string interning, keyword table |
| `TYPE_SYSTEM_p2.md` | `TypeRegistry`, Kahn's algorithm, coercion rules |
| `AST_LIR_Lowering_p2.md` | LIR data structures, control‑flow lifting, defer expansion |
| `LIR_C89_Emission_p2.md` | C89 code generation, name mangling, type emission |
| `STATIC_ANALYZERS_p2.md` | Signature, NullPointer, Lifetime, DoubleFree analyzers |
| `ERROR_HANDLING_p2.md` | Diagnostic collector, error recovery, phase isolation |
| `Import_Symbol_reg.md` | Module graph, symbol tables, type stubs |
| `COMPLEMENT.md` | Risk mitigation, missing specs, implementation safeguards |
| `DEBUGGING.md` | Tactical debugging guide for `zig1` development |

---

## 1. AI Agent Role: Z98 Compiler Implementer

The agent acts as a specialized implementer of the `zig1` compiler, translating the detailed design documents into working Z98 code.

### 1.1 Core Responsibilities

1. **Task Interpretation**: Read and understand tasks from `AI_tasks.md` (Milestones 0–9).
2. **Document Consultation**: Reference the relevant `docs/sf/*.md` documents **before** writing any code.
3. **Constraint Adherence**: Respect all Z98 limitations, memory budget (<16 MB), and C89 emission requirements.
4. **Implementation**: Produce clean, well‑commented Z98 code that follows the design.
5. **Test Compliance**: Ensure code passes unit tests, differential tests, and memory gates.
6. **Documentation Updates**: Update `docs/sf/` if implementation details necessitate changes (e.g., clarifications, edge cases).
7. **Clarification Requests**: When encountering ambiguity, ask explicitly rather than assuming.

### 1.2 Development Environment

- **Host OS**: Linux (Ubuntu 20.04+ or equivalent)
- **Bootstrap Compiler**: `zig0` (built from the C++98 codebase, located at `./zig0`)
- **Build Tool**: `make` (using `Makefile.legacy` adapted for `zig0` invocation)
- **Version Control**: Git
- **Testing**: Differential testing against `zig0` output, unit tests via `test_runner.zig`

### 1.3 Z98 Language Constraints (for `zig1` Source Code)

`zig1` is written in Z98, which is a subset of Zig with specific limitations. Agents **must** adhere to these when writing `zig1` code:

| Limitation | Workaround / Requirement |
|------------|--------------------------|
| No generics (`anytype`, `@Type`) | Use concrete hash maps (`U32ToU32Map`, `U64ToU32Map`) manually implemented. |
| No `@cImport` | Manual `extern` declarations for PAL functions. |
| No `comptime` beyond basic folding | Use `@sizeOf`/`@alignOf` only; avoid complex comptime logic. |
| Strict `i32` ↔ `usize` coercion | Always use `@intCast`. |
| No pointer captures (`if (opt) \|*p\|`) | Use `if (opt != null) { var p = &opt.value; }` pattern. |
| Switch requires `else` | Always include `else => unreachable`. |
| No method syntax | Use free functions (`fn foo(self: *T, ...)`) . |
| `std.debug.print` requires tuple | Always use `.{}` syntax for arguments. |
| Global aggregate constants | Use `pub var` and initialize in a dedicated `init()` function. |

### 1.4 Memory Budget Enforcement

`zig1` must operate within **16 MB peak RAM** when compiled for the target. During development on Linux, we enforce the same limit using a `TrackingAllocator`.

- **Arena Hierarchy**: `permanent`, `module`, `scratch` (see `DESIGN.md` 2.1).
- **Peak Tracking**: Use `--track-memory` flag (to be implemented in Milestone 0).
- **Pre‑allocation**: Call `ensureCapacity()` on `ArrayList` before hot loops.

---

## 2. Development Methodology & Workflow

### 2.1 Task-Driven Implementation

The master task list (`AI_tasks.md`) is the single source of truth. Agents work on tasks sequentially, marking them complete only after:

1. Code is written and compiles under `zig0`.
2. Unit tests (if applicable) pass.
3. Differential tests against `zig0` for relevant pipeline stages pass.
4. Memory validation (peak <16 MB) passes.

### 2.2 Build & Test Cycle (Linux)

The development cycle uses `zig0` to compile `zig1` and then runs tests on the resulting executable.

```bash
# 1. Clean environment (optional but recommended for memory tests)
make clean

# 2. Compile zig1 using zig0
zig0 src/main.zig -o build/zig1

# 3. Run unit tests
./build/zig1 --test

# 4. Run differential test suite
./scripts/differential_test.sh

# 5. Memory profiling
./scripts/memory_profile.sh ./build/zig1 test_programs/eval.zig
```

### 2.3 Differential Testing as the Primary Oracle

Since `zig0` is the reference implementation, every pipeline stage must produce output byte‑identical (or semantically equivalent) to `zig0`.

**Workflow:**
1. Run `zig0 --dump-ast test.z > expected.txt`
2. Run `build/zig1 --dump-ast test.z > actual.txt`
3. `diff expected.txt actual.txt`

If differences exist, the agent must debug `zig1` using the strategies in `DEBUGGING.md`.

### 2.4 Code Review & Quality Standards

- **Comments**: Use `//` for single line, `/* */` for multi‑line. Document non‑obvious logic.
- **Error Handling**: All fallible functions return `!T`. Use `try` and `catch` appropriately. For unrecoverable errors (ICE), use `@panic`.
- **Naming Conventions**: Follow Zig style: `snake_case` for functions/variables, `PascalCase` for types.
- **No Dead Code**: Remove debugging prints before committing unless guarded by a `const DEBUG = false;` flag.

---

## 3. Phase‑Specific Implementation Guidelines

### 3.1 Milestone 0: Infrastructure (`src/`)

- Implement `ArenaAllocator`, `TrackingAllocator`.
- Implement `StringInterner` with FNV‑1a.
- Implement `DiagnosticCollector`.
- Create `src/main.zig` with CLI parsing.

**Reference:** `DESIGN.md` 2.1, `Error Handling` 1.

### 3.2 Milestone 1–2: Lexer & Parser

- Follow `LEXER.md` exactly for token kinds and scanning logic.
- Follow `AST_PARSER.md` for `AstNode` layout and precedence climbing.
- **Critical**: Implement `--dump-tokens` and `--dump-ast` early for differential testing.

### 3.3 Milestone 3–4: Import Resolution & Type System

- Implement Kahn's algorithm for module sorting (`IMPORT_RESOLUTION_SYMBOL_REGISTRATION.md` 3).
- Implement `TypeRegistry` and dependency graph (`TYPE_SYSTEM.md` 2, 3).
- **Risk Area**: Cycle detection and layout computation. Write exhaustive unit tests.

### 3.4 Milestone 5: Semantic Analysis

- Implement `ResolvedTypeTable` and `CoercionTable` (`TYPE_SYSTEM.md` 4, 5).
- Implement `ComptimeEval` for `@sizeOf` and constant folding (`TYPE_SYSTEM.md` 8).
- Validate against `eval.zig` and `mud.zig`.

### 3.5 Milestone 6: Static Analyzers

- Implement the four analyzers per `STATIC_ANALYZERS.md`.
- Use `StateMap` with delta‑linked parents for flow‑sensitive analysis.
- **Memory**: Reset `scratch` arena between functions.

### 3.6 Milestone 7: LIR Lowering

- Implement `LirLowerer` per `AST_LIR_Lowering.md`.
- Handle defer/errdefer, TCO pattern, and tagged union switches carefully.
- Use `--dump-lir` and golden files for validation.

### 3.7 Milestone 8: C89 Emission

- Implement `C89Emitter` per `LIR_C89_Emission.md`.
- Ensure name mangling respects 31‑char C89 limit.
- Emit `#line` directives for debugging.
- Test generated C with `gcc -std=c89 -pedantic -Wall -Werror`.

### 3.8 Milestone 9: Integration & Self‑Hosting

- Wire all passes in `main.zig`.
- Compile `zig1` with `zig0` to produce `zig1.exe` (via cross‑compilation).
- Compile `zig1` with `zig1.exe` to produce `zig2.exe`.
- Verify byte‑identical `zig1.exe` and `zig2.exe`.

---

## 4. Communication Protocol for Human Developers

When assigning a task to the AI agent, provide a structured prompt:

```text
Task: [Task Number and Title from AI_tasks.md]
Description: [Brief summary of what needs to be done]
Relevant Docs: [List of docs/sf/*.md files to consult]
Constraints: [Any specific Z98 or memory constraints to emphasize]
Deliverables: [Expected code files, tests, and documentation updates]
```

**Example:**
```
Task: 146-150 (TypeRegistry Foundation)
Description: Implement TypeKind enum, Type struct, and TypeRegistry with primitive well-known IDs.
Relevant Docs: docs/sf/TYPE_SYSTEM.md Sections 1.1-1.4
Constraints: Use concrete U32ToU32Map; no generics. Pre-register primitives at indices 1-19.
Deliverables: src/type_registry.zig, tests/type_registry.zig, updated TYPE_SYSTEM.md if needed.
```

---

## 5. Debugging & Troubleshooting

When `zig1` misbehaves, agents **must** consult `DEBUGGING.md`. The debugging pyramid is:

1. Unit tests
2. Differential `--dump-*` outputs
3. `std.debug.print` / `@panic` instrumentation
4. GDB on generated C code (with `#line` directives)
5. `--bootstrap-safe` mode (or equivalent)
6. C++ fallback component (last resort)

Agents should **never** silently guess at a fix. Use the debugging tools to isolate the issue.

---

## 6. Testing Requirements

All code submissions must include:

- **Unit tests** for new functionality (in `tests/` directory).
- **Integration test** (if applicable) using one of the reference programs.
- **Memory validation** (peak <16 MB) for any change that could impact allocation.
- **Differential test** against `zig0` for relevant pipeline stages.

### 6.1 Reference Programs

| Program | Tests |
|---------|-------|
| `mandelbrot.zig` | Floats, extern functions |
| `game_of_life.zig` | Tagged unions, switch |
| `mud.zig` | Slices, struct init, null |
| `eval.zig` | Deep switches, TCO, error unions |

---

## 7. Appendix: Key Differences from Bootstrap Phase

| Aspect | Bootstrap (`zig0` in C++98) | Self‑Hosted (`zig1` in Z98) |
|--------|-----------------------------|------------------------------|
| **Language** | C++98 | Z98 (Zig subset) |
| **AST** | `ASTNode` with pointer union | Flat `AstNode` (24 bytes) with index children |
| **Type System** | Mutable `TYPE_PLACEHOLDER` | Immutable types + Kahn's algorithm |
| **Parser** | Recursive Pratt parser | Precedence climbing (bounded recursion) |
| **IR** | Ad‑hoc lifting during codegen | Explicit LIR lowering pass |
| **Error Handling** | Mixed `abort()` and recovery | Unified `DiagnosticCollector` |
| **Memory** | Arena per `CompilationUnit` | Three‑arena hierarchy (`permanent`, `module`, `scratch`) |
| **Build** | `Makefile.legacy` with C++ compiler | `zig0` compiling `zig1.zig` |

---

**End of Guidelines.** Agents are expected to internalize this document and the entire `docs/sf/` corpus before beginning implementation.
```
