
# Z98 Self-Hosted Compiler (`zig1`) – AI Agent Guidelines

**Version:** 2.0  
**Phase:** Self‑Hosting Development (Milestones 0–9)  
**Language:** Z98 (compiled by `zig0`)  
**Target:** C89 / Windows 9x / 16 MB peak memory

---

## 0. Project Context & Mission

We are building `zig1`, a self‑hosted compiler for the Z98 language (a Zig subset targeting 1998‑era hardware). `zig1` is written in Z98 and compiled by the existing C++98 bootstrap compiler `zig0`. The ultimate goal is for `zig1` to compile itself, producing a byte‑identical `zig2.exe`.

This document is the **single source of truth** for AI agents implementing `zig1`. It defines the development methodology, constraints, documentation references, and task execution protocol.

---

## 1. Core Constraints (Non‑Negotiable)

| Constraint | Enforcement |
|------------|-------------|
| **Language:** Z98 subset | Must compile with `zig0`. No features outside the Z98 spec (see `DESIGN.md v3.0`). |
| **Memory:** < 16 MB peak | `TrackingAllocator` enforced. Development limit: **8 MB**. |
| **Target Output:** Strict C89 | Generated C must compile with `gcc -std=c89 -pedantic -Wall -Werror` and `cl /Za /W3`. |
| **Dependencies:** `kernel32.dll` only | No C runtime beyond `kernel32`. All I/O via PAL. |
| **Determinism:** Reproducible builds | FNV‑1a with fixed seed, stable sorts, no pointer leakage. |
| **No Panics:** Unified diagnostics | Use `DiagnosticCollector`. Only ICE/OOM abort. |

---

## 2. Documentation Map (Read Before Any Task)

All design documents reside in `docs/sf/`. **You MUST consult the relevant documents before implementing any task.**

| Document | Content | When to Read |
|----------|---------|--------------|
| `DESIGN.md` | Overall pipeline, invariants, memory strategy | All tasks |
| `DEBUGGING.md` | How to debug `zig1` during development | **Keep open always** |
| `COMPLEMENT.md` | Risk mitigations, missing specs, safeguards | Project launch |
| `LEXER.md` | Token definitions, scanning rules | Milestone 1 |
| `AST_PARSER.md` | AST node layout, parser algorithm, precedence climbing | Milestone 2 |
| `IMPORT_RESOLUTION_AND_SYMBOL_REGISTRATION.md` | Module graph, Kahn's sort, symbol tables | Milestone 3 |
| `TYPE_SYSTEM.md` | Type representation, Kahn's resolution, coercions | Milestones 4–5 |
| `AST_LIR_Lowering.md` | LIR instructions, control‑flow lifting, defer expansion | Milestone 7 |
| `LIR_C89_Emission.md` | C89 code generation, name mangling, type emission | Milestone 8 |
| `STATIC_ANALYZERS.md` | NullPointer, Lifetime, DoubleFree analyzers | Milestone 6 |
| `Error_Handling_And_Diagnostic_Strategy.md` | Diagnostic collection, error recovery | All tasks |
| `AI_Agent_Tasks.md` | The 300+ task breakdown | Daily work reference |

---

## 3. Development Methodology

### 3.1 Task Execution Protocol

For each task assigned from `AI_Agent_Tasks.md`:

1. **Read** the referenced design document section.
2. **Write unit tests first** (in `tests/` using `test_runner.zig`).
3. **Implement** the functionality in Z98.
4. **Run differential test** against `zig0` if applicable (e.g., `--dump-ast`).
5. **Verify memory** with `--track-memory` (peak < 8 MB).
6. **Update documentation** if the implementation clarifies or corrects the design.
7. **Commit** with message referencing task number.

### 3.2 Test‑Driven Development (TDD)

Every component **MUST** have unit tests before implementation is considered complete. Use the `test_runner.zig` framework (Task 21–25).

```zig
test "lexer: decimal integer" {
    const source = "42";
    const tokens = lex(source);
    assert(tokens.len == 2); // integer, eof
    assert(tokens[0].kind == .integer_literal);
    assert(tokens[0].value.int_val == 42);
}
```

### 3.3 Differential Testing

For any pass that has a `zig0` equivalent, add a differential test to `scripts/diff_test.sh`. This ensures `zig1`'s output matches `zig0`'s for all reference programs (`eval.zig`, `mud.zig`, etc.).

### 3.4 Memory Discipline

- **Development limit: 8 MB.** The CI enforces this. Exceeding it is a build failure.
- Use `ensureCapacity()` before `ArrayList` appends in hot paths.
- Reset `scratch` arena at the end of every pass.
- Use `TrackingAllocator` (Task 3) to profile peak usage.

---

## 4. Z98 Coding Standards & `zig0` Workarounds

### 4.1 Language Subset Compliance

`zig1` must compile under `zig0`. Avoid known `zig0` bugs (documented in `ZIG0_KNOWN_ISSUES.md`).

| Z98 Feature | Status in `zig0` | Workaround |
|-------------|------------------|------------|
| `@enumToInt` / `@intToEnum` | May not work | Use manual `switch` or direct cast. |
| Global aggregate constants | Not supported | Use `pub var` and initialize in `init()` function. |
| Pointer captures (`if (opt) \|*p\|`) | Buggy | Unwrap with `if (opt != null) { var p = &opt.value; }` |
| `try` in non‑error‑returning functions | Not allowed | Use `catch unreachable` for ICEs, or explicit `if` for recoverable errors. |
| Switch expressions require `else` | Required | Always add `else => unreachable`. |
| `std.debug.print` | Works reliably | Use for instrumentation. |

### 4.2 Code Style

- **Allocator passing:** Every function that allocates receives an `Allocator` parameter. No global allocator.
- **Error handling:** Functions return `!T`. Use `try` where possible; fall back to explicit checks for `zig0` compatibility.
- **Comments:** Doxygen‑style `///` for public functions. Explain *why*, not *what*.

### 4.3 Debugging Instrumentation

Add `--dump-*` flags for every pipeline stage (see `DEBUGGING.md`). Use `std.debug.print` liberally during development—it works.

---

## 5. Build & Validation Workflow

### 5.1 Clean Build Sequence (Every Task Completion)

```bash
# 1. Clean environment (removes all artifacts)
./scripts/setup_clean_env.sh   # or .bat

# 2. Compile zig1 with zig0
zig0 build.zig -o zig1.exe

# 3. Run test suite
./test_runner.exe

# 4. Run differential tests
./scripts/diff_test.sh

# 5. Measure peak memory (must be < 8 MB)
./zig1.exe --track-memory --max-mem=8M test_programs/mandelbrot.zig

# 6. Clean binaries (preserve only zig1.exe for next step)
./scripts/clean_binaries.sh
```

### 5.2 Continuous Integration Gates

The CI pipeline (GitHub Actions or similar) runs on every commit:
- **Z98 unit tests** (compiled with `zig0`).
- **Differential tests** against `zig0`.
- **Memory gate** (peak < 8 MB).
- **C89 compilation gate** (`gcc -std=c89 -pedantic -Wall -Werror` on generated C).

---

## 6. Phase‑Specific Guidance

### 6.1 Milestone 0–2 (Infrastructure, Lexer, Parser)

- **Focus:** Correctness and determinism.
- **Primary Docs:** `LEXER.md`, `AST_PARSER.md`.
- **Key Deliverables:** `--dump-tokens`, `--dump-ast` flags that match `zig0` output exactly.

### 6.2 Milestone 3–4 (Imports, Symbols, Type System)

- **Focus:** Module graph, Kahn's algorithm, type layout.
- **Primary Docs:** `IMPORT_RESOLUTION_...md`, `TYPE_SYSTEM.md`.
- **Key Deliverables:** `--dump-types` flag, cycle detection.

### 6.3 Milestone 5 (Semantic Analysis)

- **Focus:** Type checking, coercions, comptime folding.
- **Primary Docs:** `TYPE_SYSTEM.md` (Sections 5–7), `Error_Handling_...md`.
- **Key Deliverables:** `ResolvedTypeTable`, `CoercionTable`.

### 6.4 Milestone 6 (Static Analyzers)

- **Focus:** Flow‑sensitive safety checks.
- **Primary Docs:** `STATIC_ANALYZERS.md`.
- **Key Deliverables:** Warnings for null derefs, leaks, dangling pointers.

### 6.5 Milestone 7 (LIR Lowering)

- **Focus:** Control‑flow lifting, defer expansion.
- **Primary Docs:** `AST_LIR_Lowering.md`.
- **Key Deliverables:** `--dump-lir` flag, golden LIR files.

### 6.6 Milestone 8 (C89 Emission)

- **Focus:** Strict C89 output, name mangling.
- **Primary Docs:** `LIR_C89_Emission.md`.
- **Key Deliverables:** Compilable `.c`/`.h` files, `--dump-c89` flag.

### 6.7 Milestone 9 (Self‑Hosting)

- **Focus:** Byte‑identical bootstrap.
- **Primary Docs:** All.
- **Key Deliverables:** `fc /b zig1.exe zig2.exe` returns no differences.

---

## 7. Communication Protocol for Human Developers

When assigning a task, provide:
- **Task ID** (from `AI_Agent_Tasks.md`).
- **Specific deliverable** (code files, tests, docs update).
- **Any deviations** from the standard constraints.

Example:
> "Implement Task 46: `scanInteger()`. Reference `LEXER.md` Section 5.2. Deliver `lexer.zig` with the function and `test_lexer_integer.zig` with unit tests. Verify with `--dump-tokens` against `zig0`."

The agent will respond with:
- **Summary of changes.**
- **Test results.**
- **Memory peak.**
- **Any questions or ambiguities encountered.**

---

## 8. Critical Files & Directories

```
zig1/
├── docs/
│   └── sf/                     # All design documents
├── src/                        # zig1 source code (Z98)
│   ├── main.zig
│   ├── lexer.zig
│   ├── parser.zig
│   ├── ast.zig
│   ├── type_registry.zig
│   ├── ...
│   └── runtime/                # zig_runtime.c (C89)
├── tests/                      # Unit tests (Z98)
│   ├── test_runner.zig
│   ├── lexer/
│   ├── parser/
│   └── regression/
├── scripts/
│   ├── setup_clean_env.sh
│   ├── clean_binaries.sh
│   ├── diff_test.sh
│   └── memory_profile.sh
├── reference_programs/         # eval.zig, mud.zig, etc.
├── AI_Agent_Tasks.md           # The 300+ task list
├── ZIG0_KNOWN_ISSUES.md        # Bootstrap bugs & workarounds
└── DEBUGGING.md                # Tactical survival guide
```
