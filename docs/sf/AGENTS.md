# Z98 Self-Hosted Compiler (`zig1`) – AI Agent Guidelines

**Version:** 2.0  
**Phase:** Self‑Hosted Implementation  
**Context:** `zig1` is written in Z98, compiled by `zig0`, and emits C89 code for 1998‑era targets.
**Current Milestone in progress:**
---

## 0. Overview

This document defines the roles, responsibilities, methodology, and constraints for AI agents working on the **self‑hosted Z98 compiler** (`zig1`). It supersedes the previous `Agents.md` that governed the C++98 bootstrap (`zig0`) phase. Our working directory will be /sf so we can distinguish ourselves from the zig0 that is under the root so everything is kept normal,

The agent's mission: **implement `zig1` according to the design specifications in `docs/sf/`**, in a folder /sf following a 300+ task plan that culminates in a byte‑identical self‑compilation.

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

1. **Task Interpretation**: Read and understand tasks from `docs/sf/AI_tasks_sf.md` (Current Milestone defined in progress, in prompt usually).
2. **Document Consultation**: Reference the relevant `docs/sf/*.md` documents **before** writing any code.
3. **Constraint Adherence**: Respect all Z98 limitations, memory budget (<16 MB), and C89 emission requirements.
4. **Implementation**: Produce clean, well‑commented Z98 code that follows the design.
5. **Test Compliance**: Ensure code passes unit tests, differential tests, and memory gates.
6. **Documentation Updates**: Update `docs/sf/` if implementation details necessitate changes (e.g., clarifications, edge cases).
7. **Clarification Requests**: When encountering ambiguity, ask explicitly rather than assuming.
8. **No Scope Creep**: Execute only the task requested. Do not batch-implement adjacent tasks without approval. "Plan the next 3 tasks" is plan-only — execution requires explicit user confirmation per task.

### 1.1.1 Technical Documentation Maintenance

When modifying any compiler pipeline code (lexer, parser, type system,
semantic analysis, static analyzers, LIR lowering, C89 emission, or
pipeline orchestration), the agent MUST update the corresponding document
in sf/docs/tech_docs/:

- Check INDEX.md Table A to find which doc covers the modified file
- Update function signatures, descriptions, data flow, and markers
- Add `[updated: date]` annotation at top of changed section

### 1.2 Development Environment

- **Host OS**: Linux (Ubuntu 20.04+ or equivalent)
- **Bootstrap Compiler**: `zig0` (built from the C++98 codebase, has to be compiled `./zig0`)
- **Build Tool**: g++ (g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o zig0)
- **Version Control**: Git
- **Testing**: Differential testing against `zig0` output, unit tests via `test_runner.zig`

### 1.3 Z98 Language Constraints (for `zig1` Source Code)

`zig1` is written in Z98, which is a subset of Zig with specific limitations. Agents **must** adhere to these when writing `zig1` code (If in doubt check docs/Language_Spec_Z98.md that is the documentation for zig0):

| Limitation | Workaround / Requirement |
|------------|--------------------------|
| No generics (`anytype`, `@Type`) | Use concrete hash maps (`U32ToU32Map`, `U64ToU32Map`) manually implemented. |
| No `@cImport` | Manual `extern` declarations for PAL functions. |
| No `@cInclude` in zig0 mode | Use bare `extern fn` in `extern_c.zig`; `@cInclude` only in z98 examples |
| No `comptime` beyond basic folding | Use `@sizeOf`/`@alignOf` only; avoid complex comptime logic. |
| Strict `i32` ↔ `usize` coercion | Always use `@intCast`. |
| No pointer captures (`if (opt) \|*p\|`) | Use `if (opt != null) { var p = &opt.value; }` pattern. |
| Switch requires `else` | Always include `else => unreachable`. |
| No method syntax | Use free functions (`fn foo(self: *T, ...)`) . |
| `std.debug.print` requires tuple | Always use `.{}` syntax for arguments. |
| Global aggregate constants | Use `pub var` and initialize in a dedicated `init()` function. |
| Slice bounds with inline cast+math | Pre-compute into local `var` vars; zig0 cannot resolve `@intCast` + `+` inside `[a..b]`. |
| `continue` inside `while : (expr)` with fn return values in condition | Replace `continue` with `if-else {}` chain; zig0 C89 goto miscompiles when combined with function return values used in same block. Use empty `{}` blocks as no-ops instead of `continue`. |

### 1.4 Memory Budget Enforcement

`zig1` must operate within **16 MB peak RAM** when compiled for the target. During development on Linux, we enforce the same limit using a `TrackingAllocator`.

- **Arena Hierarchy**: `permanent`, `module`, `scratch` (see `DESIGN.md` 2.1).
- **Peak Tracking**: Use `--track-memory` flag (to be implemented in Milestone 0).
- **Pre‑allocation**: Call `ensureCapacity()` on `ArrayList` before hot loops.

---

## 2. Development Methodology & Workflow

### 2.1 Task-Driven Implementation

The master task list (`docs/sf/AI_tasks_sf.md`) is the single source of truth. Agents work on tasks sequentially, marking them complete only after:

1. Code is written and compiles under `zig0` (Under /docs there are folders regarding zig0 documentation except for /sf folder, ONLY consult the zig0 documentation if in doubt of featureset on zig0).
2. Unit tests (if applicable) pass.
3. Differential tests against `zig0` for relevant pipeline stages pass.
4. Memory validation (peak <16 MB) passes.

### 2.2 Build & Test Cycle (Linux)

The development cycle uses `zig0` to compile `zig1` and then runs tests on the resulting executable.

```bash
# 0. Build zig0
g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o zig0

# 1. Clean environment (optional but recommended for memory tests)
make clean

# 2. Compile zig1 using zig0
./sf/build/zig0 --header-priority-include -o build/out_release/zig1.c sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration \
    -Iinclude build/out_release/*.c sf/src/include/zig_pal.c -o build/out_release/zig1

# 3. Run unit tests
./sf/build/zig1 --test

# 4. Run differential test suite
./sf/scripts/differential_test.sh

# 5. Memory profiling
./sf/scripts/memory_profile.sh ./build/zig1 test_programs/eval.zig
```

### 2.3 Differential Testing as the Primary Oracle

Since `zig0` is the reference implementation, every pipeline stage must produce semantically equivalent to `zig0`.

**Workflow:**
1. Compile something with zig0 (If you need flags check the zig0 docs in /docs/*)
2. Run `build/zig1 --dump-ast test.z > actual.txt`
3. `diff expected.txt actual.txt`

If differences exist, the agent must debug `zig1` using the strategies in `DEBUGGING.md`.

### 2.4 Code Review & Quality Standards

- **Comments**: Use `//` for single line, `/* */` for multi‑line. Document non‑obvious logic.
- **Error Handling**: All fallible functions return `!T`. Use `try` and `catch` appropriately. For unrecoverable errors (ICE), use `@panic`.
- **Naming Conventions**: Follow Zig style: `snake_case` for functions/variables, `PascalCase` for types.
- **No Dead Code**: Remove debugging prints before committing unless guarded by a `const DEBUG = false;` flag.

---
### 2.5 Review Hardening (MANDATORY — post-incident policy, 2026-07-17)

> **Origin:** `.opencode/plans/2026-07-16-literal-ordinal-resolution-amended.md` "PROCESS-FAILURE RECORD". These rules are binding for all subagent dispatches and contract execution.

1. **Skip/severance/deviation = BLOCKED.** Any subagent that skips a contracted phase, exercises a severability clause, or deviates from contract text MUST report status `BLOCKED` (never `DONE`) and halt. The controller MUST STOP and present to the operator BEFORE any commit containing a deviation. Deviations discovered post-hoc are sanctionable.

2. **Reviewer independence.** Reviewer prompts MUST NOT contain "do not flag" instructions, pre-judged severities, or framing that shields specific categories of findings. Reviewers flag everything; the controller adjudicates in the loop, and the operator rules on plan-conflicts.

3. **Runtime gates mandatory.** Every fix-task gate battery MUST include RUNTIME execution of affected programs (and oracle/parent comparison where available). Compile-only gates are FORBIDDEN — the 2026-07-16 incident proved a compile-clean binary can regress at runtime (partial name_id→ordinal migration broke `err == error.X` consistency).

4. **Important/Critical findings loop.** Every Important or Critical review finding MUST be followed by a fix subagent + re-review, OR an explicit operator ruling. The controller may not self-adjudicate severity downgrades.

5. **Verification claims must be evidenced.** A subagent claiming "X was verified" must include the evidence (file:line, command output). Unevidenced verification claims are treated as false — per the 2026-07-16 incident where a phase was skipped on a wrong verification claim.

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

- **Unit tests** for new functionality (in `zig1/tests/` directory).
- **Integration test** (if applicable) using one of the reference programs.
- **Memory validation** (peak <16 MB) for any change that could impact allocation.
- **Differential test** against `zig0` for relevant pipeline stages.

### 6.1 Reference Programs

| Program | Tests |
|---------|-------|
| `examples/zig0/mandelbrot/mandelbrot.zig` | Floats, extern functions |
| `examples/zig0/game_of_life/main.zig` | Tagged unions, switch |
| `examples/zig0/mud_server/main.zig` | Slices, struct init, null |
| `examples/zig0/lisp_interpreter_curr/*.zig` | Deep switches, TCO, error unions |
| `examples/zig0/lzw/*.zig` | Have also relevant syntax |

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

---

## 8. Session Memory Persistence

Every session **must** persist key learnings using the memory plugin (`@knikolov/opencode-plugin-simple-memory`) at session start and end.

### 8.1 Session Start

`memory_recall()` — load all prior context before answering any question.

### 8.2 Session End

Before closing, run `memory_remember` for:

| Type | Scope | What to store |
|------|-------|---------------|
| `decision` | `project` | Architecture/design choices (with file refs) |
| `learning` | `project` | Codebase discoveries, Z98 constraint workarounds |
| `preference` | `project` | User preferences or patterns learned |
| `blocker` | `project` | Known issues or unfinished work |
| `context` | `project` | Current task status, what was done, what's next |
| `pattern` | `project` | Recurring implementation patterns |

**Rule**: Store one memory per logical fact. Keep content single-line, detailed, with file references.

### 8.3 Memory Update

If new info contradicts existing memory, use `memory_update` (not `memory_forget` + `memory_remember`).

### 8.4 Memory List

`memory_list()` to discover all stored scopes and types in use.

### 8.5 Memory Store Path (IMPORTANT)

The real, populated `mnemoria` database lives at **`.opencode/memory`** (~2,100+
entries). ALWAYS query it with `--path .opencode/memory` (or `-p .opencode/memory`):

```bash
mnemoria --path .opencode/memory stats           # ~2,121 entries
mnemoria --path .opencode/memory search "keyword" --limit 40
mnemoria --path .opencode/memory ask "question"
mnemoria --path .opencode/memory timeline --limit 20
```

**Pitfall:** running `mnemoria` from the repo root WITHOUT `--path` reads/creates a
DIFFERENT, near-empty store at `./mnemoria/` (a stray build-mode artifact with only a
handful of entries). That is NOT the project memory. If a search returns very few
results, you are on the wrong store — re-run with `--path .opencode/memory`, raise
`--limit` (default 10 is low), and vary phrasings before concluding a memory is absent.

### 8.6 Plan Writing & Plan-Mode Write Permissions (DURABLE — do not re-litigate)

The superpowers **`writing-plans` skill** produces bite-sized, TDD, task-by-task
implementation plans. Load it via the `skill` tool before touching code on any
multi-step task.

- **Where plans are saved:** `.opencode/plans/YYYY-MM-DD-<feature-name>.md` (overrides
  the skill default `docs/superpowers/plans/`). This directory is **git-ignored /
  untracked** — writing a plan there mutates nothing tracked; it is a scratch/handoff
  artifact.
- **Plan mode's READ-ONLY constraint targets CODE/PROJECT/SYSTEM writes only.** Per the
  durable operator decision (mnemoria, 2026-06-26 "m1213", tags
  `plan-mode,memory-tool,compress,allowed,no-relitigate`), the following ARE permitted
  in plan mode on the operator's request, and MUST NOT be refused/looped:
  - Writing/updating **plan `.md` files** under `.opencode/plans/` (untracked, benign).
  - Storing memories via **`mnemoria add`** (benign collaboration side-channel).
  - Running **`compress`** (context-management meta-op).
- **Still forbidden in plan mode:** source/code edits (`edit`/`fastedit`/`write` on
  tracked project files), shell file-manipulation, `git commit`, `git checkout`, config
  changes — any real project/code/system mutation.
- **If unsure**, search mnemoria (`--path .opencode/memory search "plan mode
  memory-tool allowed"`) and follow the operator's standing authorization rather than
  attempting to convince the operator or looping. The operator is the authority and the
  sole liable party for this environment.

---

## 9. Build System

### 9.1 Output Directory Isolation (CRITICAL)

zig0 generates `.c` and `.h` files in the output directory. **Different build targets MUST use separate output directories.** Mixing stale `.c`/`.h` files from different builds causes C89 type mismatch errors (e.g., `unknown type name 'Slice_*'`). Always delete `.c`/`.h` before each zig0 invocation.

### 9.1.1 zig0 Error Diagnosis — DO NOT Blame zig0 First (CRITICAL)

When zig0 produces a compilation error (`use of undeclared identifier`, `unable to infer type`, etc.), the correct diagnostic order is:

1. **Check the identifier declaration** — `grep` for the identifier name in the file and its imports. Is it declared? Is the import alias correct?
2. **Check the module import name** — different files use different aliases for the same module (e.g., `lower.zig` imports `pal`, while `semantic_analyzer.zig` imports `pal_mod`). Use `grep "const pal\|import.*pal" <file>` to verify.
3. **Check for missing imports** — `grep "const X = @import" <file>` to see what's imported vs what's used. A file may be a never-imported stub with pre-existing bugs.
4. **THEN consider zig0 limitations** — only after ruling out (1)-(3). zig0 C89 issues are RARE; user-level bugs are COMMON.

**This is non-negotiable.** Two sessions produced false zig0-blaming: (a) `pal_mod` vs `pal` module name mismatch in `lower.zig`, blamed on "C89 variable budget"; (b) missing `ast_mod` import in `comptime_eval.zig`, blamed on "type inference failure". Both were simple import errors. See memory [97cffe29](mnemoria).

### 9.2 Build Scripts

Two pre-made scripts isolate output per target:

| Script | Target | Output |
|--------|--------|--------|
| `sf/scripts/build_release.sh` | `sf/src/main.zig` → zig1 binary | `sf/build/out_release/` |
| `sf/scripts/build_test.sh` | Test binaries (`test_*_bin.zig`) | `sf/build/out_test_<name>/` (one per test) |

**Note:** `build_test.sh` links `sf/src/include/zig_pal.c` into each test binary. This is required since `pal.zig` gained the `pal_file_open`/`pal_file_write`/`pal_file_close` externs — without it every test binary fails to link.

**Usage:**
```bash
# Release
bash sf/scripts/build_release.sh

# All tests (semantic, module_reg, sym_reg)
bash sf/scripts/build_test.sh
```

### 9.3 Manual Build Commands

When building manually, NEVER reuse the same output directory:
```bash
# Release (isolated)
OUT=sf/build/out_release
rm -rf $OUT && mkdir -p $OUT
./sf/build/zig0 --header-priority-include -o $OUT/zig1.c sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -Iinclude $OUT/*.c sf/src/include/zig_pal.c -o $OUT/zig1

# Test (isolated per binary)
OUT=sf/build/out_test_foo
rm -rf $OUT && mkdir -p $OUT
./sf/build/zig0 --header-priority-include -o $OUT/foo.c sf/src/tests/test_foo_bin.zig
gcc -m32 ... $OUT/*.c -o $OUT/foo
$OUT/foo
```

---

---

## X. Debugging Protocol for zig1

### X.1 PAL Diagnostic First

Before investigating ANY pipeline issue, verify that `pal.stderr_write`
works from the target module. Add a single marker at program start:

```zig
var dbg: []const u8 = "START\n";
pal.stderr_write(dbg);
```

Build + run. If `"START"` does not appear in stderr, resolve the PAL
issue before any other debugging. Never proceed to instrumentation
without a working diagnostic channel.

### X.2 Letter-Code Markers

For pipeline tracing, use single-letter markers (no `itoa` needed):

| Marker | Meaning |
|--------|---------|
| `"I"` | phase_ImportResolution |
| `"S"` | phase_SymbolRegistration |
| `"T"` | phase_TypeResolution |
| `"A"` | phase_StaticAnalyzers |
| `"L"` | phase_LIRLowering |
| `"C"` | phase_C89Emission |
| `"M"` | Module found (in per-module loop) |
| `"R"` | Root is AstKind.module_root |
| `"F"` | fn_decl found |
| `"."` | Non-fn_decl found |
| `"E"` | Error / unexpected state |

This shows pipeline flow and module contents without numeric formatting.

### X.3 FORBIDDEN: Python Scripts for Code Editing

Python-based code modification (using `str.replace`, `split('\n')`,
regex over Z98 source, `sed` with regex) is PROHIBITED. These scripts:

- Corrupt newline sequences (LF vs CRLF)
- Break string literal line endings (`\n` vs `\\n`)
- Crush multi-line structures into single lines
- Cannot be undone without `git checkout` which
  reverts ALL uncommitted fixes alongside the attempted changes

**Use only the `edit` tool (exact `oldString`/`newString`) or the `fastedit` tool (line ranges — see X.7)** for code edits.
One edit at a time. No bulk transforms. No exceptions.

### X.4 FORBIDDEN: git checkout to Erase Diagnostic Code

Using `git checkout -- sf/src/file.zig` to "clean up" diagnostics
ERASES actual bug fixes applied in the same file. Never use
`git checkout` to undo work. If a diagnostic is wrong, fix it with
another `edit` — do not revert to an earlier state that has neither
the fix nor the diagnostic.

### X.5 Z98 String Literal Pattern (Slice_u8)

Raw string literals in Z98 are fixed-size arrays, not slices.
Always use the Slice_u8 workaround:

```zig
var msg: []const u8 = "hello";
pal.stderr_write(msg);
// CORRECT: above
// WRONG:   pal.stderr_write("hello");
```

This applies to ALL `pal.stderr_write`, `pal.stdout_write`, and
`bufferedWriterWrite` calls.

<context_management_directive>
### X.6 QUICK_REF.md — Operational Commands & Memory Search

Before any build/debug/troubleshooting session, consult
**`docs/sf/QUICK_REF.md`** for:

- zig0 → zig1 bootstrap build command
- zig1 → C89 compilation command
- GCC C89 compilation + linking (with zig_runtime.c + zig_pal.c)
- Building and running Mandelbrot, Game of Life, mud_server
- Running test binaries (sf/src/tests/)

**Memory search fallback (Section 8 directive):**

When `memory_recall()` with keyword queries returns older/irrelevant
entries only, use the direct file read approach:

1. Memory files are stored at **`/workspace/znineeight/.opencode/memory/`**
   as `YYYY-MM-DD.logfmt` (one entry per line, logfmt format)
2. Read specific date files directly with the Read tool:
   `filePath="/workspace/znineeight/.opencode/memory/2026-06-10.logfmt"`
3. For broad search across all dates, use:
   `grep -r "keyword" /workspace/znineeight/.opencode/memory/`
4. Each line format: `ts=ISO-time type=<kind> scope=<label> content="<text>"`
   The `content` field is double-quoted with escaped inner quotes (`\"`)

This bypasses the memory_recall tool's score-based ranking which may
bury recent entries under older high-score matches.
</context_management_directive>

### X.7 Editing with `fastedit` (line-based, sanctioned)

`fastedit` is an additional approved manual-edit tool (alongside `edit`):
it replaces/deletes an inclusive 1-indexed line range
(`start_line`..`end_line`) with `new_code`, and prints a diff + surrounding
context + warnings (duplicate function/class names, missing
blank-line-before-function). It is NOT a bulk / replace-all / python
transform — it is one controlled, diff-previewed edit, so it satisfies the
X.3 manual-edit discipline.

Rules and gotchas (learned 2026-06-26, Stage I traversal unify):

- **Re-read the target region with `read` immediately before every
  `fastedit`.** Line numbers are absolute and shift after each edit; a
  stale number silently edits the wrong lines.
- **Edit bottom-to-top** when making several edits in one file, so each
  edit only shifts lines *below* it and the pending (higher) line numbers
  stay valid.
- **Insert-before is NOT supported via `end_line = start_line - 1`** (it
  errors `start_line must be <= end_line`, despite the tool's own help
  text). To INSERT, replace the anchor line with `[new content + the
  original anchor line]` — i.e. include the original line verbatim at the
  end of `new_code`.
- **Source indentation is cosmetic for the byte-identical gate** — zig0
  parses regardless of whitespace and `--dump-c89` output is unaffected;
  still match sibling indentation for readability.
- The **duplicate-function-name warning** is useful right after inserting
  a verbatim-extracted helper (e.g. the M1/M2 header helpers): it flags an
  accidental second definition.

Same gates apply: self-host build 0 errors + man/gol/mud/lisp `--dump-c89`
byte-identical (or oracle-correct) + per-stage verification STOP.

**End of Guidelines.** Agents are expected to internalize this document and the entire `docs/sf/` corpus before beginning implementation. Memory persistence (Section 8) is mandatory every session.
```

## 9. Mnemoria Memory Store

Memories are stored using `mnemoria` CLI. Store at `.opencode/memory/`.

### Agent Conventions

| agent_name | Purpose |
|---|---|
| `legacy-zni` | Pre-migration memories from old logfmt system |
| `legacy-deleted` | Previously deleted memories, retained for reference |

### Type Mapping

| memory type | mnemonia entry_type |
|---|---|
| learning | discovery |
| decision | decision |
| plan | intent |
| blocker | problem |
| pattern | pattern |
| context | discovery |
| preference | discovery |

### Usage

```bash
# Search legacy memories
mnemoria --path .opencode/memory search --agent legacy-zni "keyword"

# Ask about legacy memories (RAG)
mnemoria --path .opencode/memory ask "What patterns exist?"

# View recent timeline
mnemoria --path .opencode/memory timeline --limit 10

# Add new memory
mnemoria --path .opencode/memory add \
  --agent my-agent \
  --type discovery \
  --summary "Brief description" \
  "Detailed content here"

# Get stats
mnemoria --path .opencode/memory stats
```
