# Z98 Self-Hosted Compiler (`zig1`) – AI Agent Guidelines

**Version:** 2.0  
**Phase:** Self‑Hosted Implementation  
**Context:** `zig1` is written in Z98, rebuilt from the committed seed `release/seed/zig1-seed.tgz` with `gcc` (zig0 is retired), and emits C89 code for 1998‑era targets.
**Current Milestone in progress:**
---

## 0. Overview

This document defines the roles, responsibilities, methodology, and constraints for AI agents working on the **self‑hosted Z98 compiler** (`zig1`). It supersedes the previous `Agents.md` that governed the C++98 bootstrap (`zig0`) phase. Our working directory will be /sf so we can distinguish ourselves from the zig0 that is under the root so everything is kept normal,

The agent's mission: **implement `zig1` according to the design specifications in `docs/sf/`**, in a folder /sf following a 300+ task plan that culminates in a byte‑identical self‑compilation.

### 0.1 Project Context

| Aspect | Details |
|--------|---------|
| **Compiler Source Language** | Z98 (a strict subset of Zig targeting C89) |
| **Bootstrap Compiler** | Rebuilt from the committed seed `release/seed/zig1-seed.tgz` using `gcc`; zig0 is retired |
| **Target Output** | C89 source code (`.c` / `.h` files) |
| **Runtime Environment** | 32‑bit Windows 9x / NT, 16 MB peak RAM |
| **Development Host** | Linux (with cross‑compilation capability) |
| **PAL** | Platform Abstraction Layer for file I/O and memory |

### 0.2 Key Documents

| Document | Purpose |
|----------|---------|
| `docs/reference/Language_Spec_Z98.md` | Binding Z98 language reference |
| `docs/sf/QUICK_REF.md` | Current build, seed, gate, and debugging commands |
| `sf/docs/tech_docs/INDEX.md` | As-built pipeline/function cross-reference |
| `docs/superpowers/specs/` | Approved designs for current work |
| `docs/superpowers/plans/` | Active tracked implementation plans |

Older `Design_p2.md` / `*_p2.md` material is historical; use the tech-docs index
for the current code layout.


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
- **Compiler under test**: built from the committed seed
  `release/seed/zig1-seed.tgz` via
  `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>`.
  zig0 is retired and is not a current build path.
- **Version Control**: Git
- **Testing**: seed/fixed-point closure, corpus classification, goldens,
  stdlib fixtures/crosscheck, and targeted fixtures.

### 1.3 Z98 Language Constraints (for `zig1` Source Code)

`zig1` is written in Z98. The binding language reference is
`docs/reference/Language_Spec_Z98.md`; consult it rather than the retired zig0
documentation.

| Constraint | Requirement |
|------------|-------------|
| No generics / `anytype` / `@Type` | Use concrete hash maps and concrete functions. |
| No `@cImport` | Use `extern` declarations. `@cInclude` **is** supported for C headers. |
| No `comptime` parameters | Ordinary constant folding, `@sizeOf`/`@alignOf`, and the documented builtins are supported; see spec §4/§7.2. |
| Strict `i32` ↔ `usize` coercion | Use `@intCast`. |
| No pointer captures (`if (opt) \|*p\|`) | Use `if (opt != null) { var p = &opt.value; }`. |
| `switch` requires `else` | Always include `else`; `else => unreachable` is a live trap in both modes. |
| No method syntax | Use free functions (`fn foo(self: *T, ...)`). |
| `std.debug.print` requires a tuple | Use `.{}` for arguments. |
| Runtime global initialization | Use `pub var` + an explicit `init()` for non-constant initialization; value-shaped file-scope `const` aggregates are supported as C89 `static const` rodata. |

### 1.4 Memory Budget Enforcement

`zig1` targets **16 MB peak RAM**. Use the arena hierarchy (`permanent`,
`module`, `scratch`), pre-size hot arrays, and measure with
`--markers --track-memory` (implemented; prints pool/perm/mod/scratch totals).


---

## 2. Development Methodology & Workflow

### 2.1 Task-Driven Implementation

The active plan under `docs/superpowers/plans/` (or the operator’s task brief) is
the source of truth. Work sequentially and mark a task complete only after:

1. The code compiles from the current committed seed.
2. Targeted fixtures and required runtime tests pass.
3. The plan’s gates pass (corpus/goldens/stdlib/tiers as applicable).
4. Memory validation for the affected workload passes.


### 2.2 Build & Test Cycle (Linux)

The current cycle is the committed seed; zig0 is retired. Use a fresh output
directory.

```bash
# 1. Build the current compiler from the seed
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>

# 2. Emit a program (output dir must exist)
mkdir -p <dump_dir>
<out_dir>/zig1_5_clean -fsafe -o <dump_dir> <entry.zig>

# 3. Build the emitted C
cd <dump_dir> && sh build_target.sh linux prog

# 4. Run the stdlib gate
bash scripts/stdlib/verify_stdlib.sh <out_dir>/zig1_5_clean
```

The dump MUST run from the repo root with the relative `sf/src/main.zig` path
(module basename-hash tokens are path-derived). The script’s closure line is the
gate; on a std-only rotation use `hop1 == hop2`, on a compiler-changing rotation
use `hop2 == hop3`. Full model: §9.4.

### 2.3 Testing Oracles

There is no current zig0 differential oracle. Validate against, in order:

1. Seed/fixed-point closure and the recorded fixed point.
2. Frozen corpus classification (`scripts/corpus/classify`) and the pinned
   goldens.
3. `scripts/stdlib/verify_stdlib.sh` + `run_crosscheck.sh` for std changes.
4. Targeted fixtures and 3× determinism.
5. Example tiers / `-osw` import gates where applicable.

If a result differs, isolate the pass with markers and generated-C inspection;
do not compare emitted C against legacy zig0 output.


### 2.4 Code Review & Quality Standards

- **Comments**: Use `//` for single line, `/* */` for multi‑line. Document non‑obvious logic.
- **Error Handling**: All fallible functions return `!T`. Use `try` and `catch` appropriately. For unrecoverable errors (ICE), use `@panic` — it writes `panic: <msg>` to stderr and then traps (it does not return).
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
## 3. Historical Milestone Notes

These sections describe the original implementation sequence; current work
follows the active plan under `docs/superpowers/plans/`.

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
- Validate with targeted fixtures, `--dump-c89`, and `--markers`; `--dump-lir`
  is a dead flag constant and is not a supported CLI mode.

### 3.7 Milestone 8: C89 Emission

- Implement `C89Emitter` per `LIR_C89_Emission.md`.
- C89 identifiers are produced by the mangler (keyword escape + collision
  handling); keep the historical MSVC 6 31-character concern in mind.
- Do **not** emit `#line` directives. Generated-C debugging uses the symbol/line
  sidecar design, not `#line`.
- Test generated C with the canonical `gcc -m32 -std=c89` flag set from
  `docs/sf/QUICK_REF.md` (including `-Wno-long-long`), not a stricter dialect.


### 3.8 Milestone 9: Integration & Self‑Hosting (historical)

- Wire all passes in `main.zig`.
- Compile `zig1` with `zig0` to produce `zig1.exe` (via cross‑compilation).
- Compile `zig1` with `zig1.exe` to produce `zig2.exe`.
- Verify byte‑identical `zig1.exe` and `zig2.exe`.

---

## 4. Communication Protocol for Human Developers

When assigning a task to the AI agent, provide a structured prompt:

```text
Task: [Task number/title from docs/superpowers/plans/<active-plan>.md]
Description: [Brief summary of the deliverable]
Relevant Docs: [Spec/plan/tech-doc paths]
Constraints: [Z98 subset, memory, seed/gate requirements]
Deliverables: [Exact files, fixtures, docs, commits]
```

**Example:**
```
Task: M1 Task 1 (compiler debug map)
Description: Emit the opt-in --debug sidecar map.
Relevant Docs: docs/superpowers/specs/2026-10-24-phase2-z98-debugger-design.md;
  docs/superpowers/plans/2026-10-24-phase2-z98-debugger-plan.md
Constraints: Z98 subset; LirInst stays 32 B; map off by default.
Deliverables: sf/src/debug_map.zig, lower/lir/c89_emit/main edits, fixture, report.
```



---

## 5. Debugging & Troubleshooting

When `zig1` misbehaves, use the current debugging ladder:

1. Unit tests and the targeted fixture for the affected pass.
2. Corpus classification, goldens, and fixed-point/seed closure.
3. `--dump-c89` inspection and `--markers` / `pal.markerWriteInt` tracing.
4. GDB on generated C (there are **no `#line` directives**; use `zF_*`/`zT_*`
   symbols and the debugger sidecar once available).
5. `-fsafe` runtime checks (default) vs `-ffast`.
6. Isolate the pass with markers before considering a compiler change.


Agents should **never** silently guess at a fix. Use the debugging tools to isolate the issue.

---

## 6. Testing Requirements

All code submissions must include:

- **Targeted tests/fixtures** for new functionality (`repro/mi_matrix/*` and/or
  `sf/src/tests/`).
- **Integration test** (if applicable) using a current `examples/z98/` program.
- **Memory validation** for any change that could affect allocation.
- **Plan gates** (corpus/goldens/stdlib/tiers) required by the active plan.


### 6.1 Reference Programs

Current examples live under `examples/z98/`; `examples/zig0/` is legacy oracle
material only.

| Program | Tests |
|---------|-------|
| `examples/z98/mandelbrot/mandelbrot.zig` | Floats, extern functions |
| `examples/z98/game_of_life/main.zig` | Tagged unions, switch |
| `examples/z98/mud_server/main.zig` | Slices, struct init, null |
| `examples/z98/lisp_interpreter_curr/*.zig` | Deep switches, TCO, error unions |
| `examples/z98/lzw/*.zig` | Compression, file I/O |


---

## 7. Appendix: Key Differences from Bootstrap Phase (historical)

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

Use the `mnemoria` CLI; the old `memory_recall`/`memory_remember` plugin API is
retired.

### 8.1 Session Start

```bash
mnemoria --path .opencode/memory timeline --limit 20
mnemoria --path .opencode/memory search "keyword" --limit 40
```

### 8.2 Session End

Store one logical fact per entry, single-line, with file references:

| Type | Use for |
|------|---------|
| `decision` | Architecture/design choices |
| `discovery` | Codebase facts and constraints |
| `intent` | Active plan/goal |
| `problem` | Known blockers |
| `pattern` | Recurring implementation patterns |
| `success` | Completed milestones |

### 8.3 Memory Store Path (IMPORTANT)

The populated database is **`.opencode/memory`**. Always pass
`--path .opencode/memory`; without it `mnemoria` reads/creates a different
near-empty store.

```bash
mnemoria --path .opencode/memory stats
mnemoria --path .opencode/memory search "keyword" --limit 40
mnemoria --path .opencode/memory ask "question"
```

### 8.4 Plan Writing & Plan-Mode Write Permissions (DURABLE — do not re-litigate)

The superpowers **`writing-plans` skill** produces bite-sized, TDD, task-by-task
implementation plans. Load it via the `skill` tool before touching code on a
multi-step task.

- **Current plans are saved under `docs/superpowers/plans/` and are tracked.**
  Write them in build mode, not while plan mode is active.
- `.opencode/plans/` is a legacy/untracked scratch area. It is not the current
  plan location.
- **Plan mode is READ-ONLY for tracked project/code state.** Per the durable
  operator decision (mnemoria, 2026-06-26 "m1213"), memory writes via
  `mnemoria add` and `compress` are permitted in plan mode; editing tracked
  files, committing, or other project/system mutations is not.
- Do not re-litigate this: if unsure, search
  `mnemoria --path .opencode/memory search "plan mode memory-tool allowed"`.


---

## 9. Build System

### 9.1 Output Directory Isolation (CRITICAL)

Compiler and emitted-C builds each need an isolated output directory. Never
reuse a directory across compiler states: stale `.c`/`.h` files cause C89
type/name errors. `build_from_seed.sh` creates a fresh `<out_dir>`; emitted
`--dump-c89` requires an existing `--output-dir`.

### 9.1.1 Seed-build error diagnosis

zig0 is retired and no longer builds current `sf/src`. When a seed build
fails, inspect the current source first: missing `@import`, wrong module
alias, or a stale `<out_dir>/lib/` module copy. Do not work around a failure
by reverting to the old zig0 cycle.

### 9.2 Build Scripts

| Script | Purpose |
|--------|---------|
| `scripts/seed/build_from_seed.sh` | Rebuild the current `sf/src` with the committed seed; writes `<out_dir>/zig1_5_clean` + `<out_dir>/lib/` |
| `scripts/seed/archive_seed.sh` | Assemble/rotate `release/seed/zig1-seed.tgz`; closeout-only |

```bash
# Current compiler (use a fresh directory)
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>

# Seed rotation (plan closeout only)
bash scripts/seed/archive_seed.sh <zig1_binary> <gen_dir> release/seed/zig1-seed.tgz --update-changelog
```

### 9.3 Manual Build Commands

There is no manual zig0 build path. Use the seed recipe above; the resulting
`<out_dir>/zig1_5_clean` is the compiler under test. `--dump-c89` requires a
pre-created output directory.

### 9.4 Seed Model + Bootstrap-Staging Constraint (SEEDMIG)

`zig1` is rebuildable **zig0-independently** from the committed rotating seed
`release/seed/zig1-seed.tgz` (tracked; provenance in
`release/seed/CHANGELOG.md`). Current seed is **v119**:

- archive md5 `e7ac8cd2ed7e790a4b9225a82acaf4a5`
- `gen/` 47 `.c` + 48 `.h`
- `lib/` 47 std `.zig` + `lib/manifest.md5` (manifest md5 `e731a3d2a7aef913f5bbcfd8670e5a2e`)
- archived binary = fixed point `45158dcede81125a39a2c2c58478e21e`
- `runtime/` contains `zig_compat.h`, `zig_runtime.h`, `zig_special_types.h`,
  `zig_runtime.c`, `zig_pal.c`, `zig_nocrt.c`; no `net_prelude.h`

The archived binary and self-emission fixed point are the same compiler state.

**Bootstrap-staging constraint** — a seed can only compile `sf/src` written in
the subset it already understands:

1. **Every plan begins from the committed seed.** Run
   `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>`
   from the repo root with the relative `sf/src/main.zig` path. Gate on the
   script's closure line; the result is `<out_dir>/zig1_5_clean` + `lib/`.
   For a std-only rotation (like v119) `hop1 == hop2`; a compiler-changing
   rotation uses `hop2 == hop3`.
2. **New compiler code must use constructs the current seed understands** —
   the seed (or its gcc-of-C reconstruction) compiles the next hop.
3. **`sf/src` may adopt new syntax only after a new fixed point exists.**
4. **Rotate the seed at plan closeout** via `scripts/seed/archive_seed.sh`
   when the fixed point moved **or** the archive's `lib/` payload changed.
   The script gcc-rebuilds the archive C and prepends provenance to
   `release/seed/CHANGELOG.md`.
5. **The seed lives at `release/seed/` (tracked), never `/tmp`.**

**Plan-convention line:** every plan should carry the standard line:
"Reference compiler rebuilt per the seed model (`release/seed/`); rotate the
seed at closeout via `scripts/seed/archive_seed.sh`."

**Flag-set rule (binding):** every `gcc -c` MUST be
`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`
— fixed point `45158dce…` reproduces only with `-Wall`. Link set for
self-emission C89: `zig_runtime.c` + `zig_pal.c` + `c_exit.c` (plus
`zig_nocrt.c` when `ZIG_NO_CRT` is used). `-Wextra -O3 -fsyntax-only` is a
separate verification gate, never the build command. Exact recipes are in
`release/seed/SEED_README.txt`.


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

### X.5 String Literals

String literals are typed `*const [N]u8` and coerce to `[]const u8`,
`[*]const u8`, or `*const u8` (Language Spec §1.4/Type Coercions). Direct calls
such as `pal.stderr_write("hello");` are valid. A mutable `[]u8` target still
requires a mutable buffer, not a string literal.


<context_management_directive>
### X.6 QUICK_REF.md — Operational Commands & Memory Search

Before any build/debug/troubleshooting session, consult
**`docs/sf/QUICK_REF.md`** for:

- seed build (`scripts/seed/build_from_seed.sh`)
- `zig1` → C89 emission + `build_target.sh`
- building and running current `examples/z98/` programs
- stdlib fixture/crosscheck gates
- GDB on the seed-built compiler

**Memory search:** use `mnemoria --path .opencode/memory` (see §8). Do not use
the retired `memory_recall` plugin API.

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
