
## Review Summary

### ✅ What's Already Excellent

| Aspect | Assessment |
|--------|------------|
| **Unified Collector** | The side‑table, arena‑backed, interning‑based collector is perfect for Z98. |
| **Phase Isolation** | Clear recovery strategies and poison type (`TYPE_VOID`) prevent cascade failures. |
| **Determinism** | Sorting by `file_id → span_start → level → code` guarantees reproducible output. |
| **Memory Caps** | `max_diagnostics=256` and pre‑sized ArrayLists keep peak RAM predictable. |
| **CLI Integration** | `--error-format`, `--warnings-as-errors`, exit codes are all present. |
| **Z98 Workarounds** | Explicit handling of `catch unreachable`, `@intCast`, and C89 string limits. |

### 🔧 Areas for Enrichment (Spaceship‑Grade Robustness)

1. **Explicit Recovery Pseudocode** – Adding concrete algorithms for lexer/parser synchronization will eliminate ambiguity during implementation.
2. **OOM and ICE Handling** – Define exactly how out‑of‑memory and internal compiler errors are reported (including a minimal panic handler that works on Win9x).
3. **Arena Lifetime Integration** – Clarify when diagnostics are flushed and how they survive across module boundaries (important for cross‑module errors).
4. **Note Attachment & Span Chaining** – Add support for multi‑span notes (e.g., "declared here") without dynamic allocation.
5. **Diagnostic Code Exhaustiveness** – Provide a complete table of all error/warning codes for Z98 (ensures no gaps).
6. **Testing Strategy Expansion** – Include concrete unit tests for recovery paths and golden‑file validation.
7. **Z98‑Specific Error Propagation** – Show how to handle errors in functions that cannot return error unions (common in `zig0`‑compiled `zig1`).

I've incorporated all of these into the enriched document below.

---

# Error Handling & Diagnostic Strategy Design Specification

**Version:** 1.1 (Enriched)  
**Component:** Unified diagnostic collection, phase‑resilient error recovery, reporting, and determinism guarantees  
**Parent Document:** `DESIGN.md v3.0` (Sections 1–2, 7–8, 11–12), `TYPE_SYSTEM.md` (Section 7), `LEXER.md` (Section 8), `AST_LIR_Lowering.md`, `LIR_C89_Emission.md`  
**Supersedes:** Bootstrap ad‑hoc `printf`/`abort` error paths

---

## 0. Scope & Philosophy

This document specifies the **error handling and diagnostic strategy** for the self‑hosted Z98 compiler (`zig1`). It replaces the bootstrap's two‑tier `abort()` vs `recover` model with a unified, non‑panicking, side‑table‑driven architecture that guarantees:

- **Zero unhandled panics** in library code (only OOM or Internal Compiler Errors trigger a hard abort)
- **Maximum error collection** per compilation run
- **Deterministic, reproducible output** across platforms and runs
- **Strict phase isolation** with graceful degradation
- **<16 MB peak memory** enforcement

**Core Principles:**

1. **Explicit Collection:** Diagnostics are never printed directly. All passes receive a `*DiagnosticCollector` and append structured records.
2. **Recovery Over Crash:** On recoverable errors, the compiler emits a placeholder/poison value, synchronizes to a safe state, and continues.
3. **Cascade Prevention:** Invalid types/expressions propagate as `TYPE_VOID` (poison) to suppress secondary false positives.
4. **Deterministic Ordering:** Diagnostics are sorted by `file_id → span_start → level → code` before emission. No hash‑iteration or pointer‑address leakage.
5. **Clean Abort Boundary:** If `hasErrors()` is true after semantic analysis, code generation is skipped. Partial C89 output is never emitted.
6. **OOM/ICE as Hard Aborts:** Only out‑of‑memory or internal compiler errors terminate the process. They are reported via a minimal panic handler that writes to `stderr` and exits with code `3`.

---

## 1. Core Data Structures

Diagnostics are stored as flat, arena‑backed records with explicit source spans and machine‑readable codes.

```zig
pub const DiagnosticLevel = enum(u8) {
    error   = 0,
    warning = 1,
    info    = 2,
    note    = 3,   // attached only to other diagnostics
};

pub const ErrorCode = enum(u16) {
    // Lexer
    ERR_1000_UNTERMINATED_STRING,
    ERR_1001_UNTERMINATED_BLOCK_COMMENT,
    ERR_1002_INVALID_CHAR_LITERAL,
    ERR_1003_INVALID_ESCAPE,
    WARN_1010_UNRECOGNIZED_ESCAPE,
    WARN_1011_INTEGER_OVERFLOW,

    // Parser
    ERR_2000_UNEXPECTED_TOKEN,
    ERR_2001_MISSING_SEMICOLON,
    ERR_2002_UNCLOSED_BRACE,
    ERR_2003_EXPECTED_EXPRESSION,
    ERR_2004_EXPECTED_TYPE,
    WARN_2010_DEPRECATED_SYNTAX,

    // Semantic
    ERR_3000_TYPE_MISMATCH,
    ERR_3001_UNDEFINED_SYMBOL,
    ERR_3002_INVALID_ASSIGNMENT,
    ERR_3003_MISSING_RETURN,
    ERR_3004_SWITCH_NOT_EXHAUSTIVE,
    ERR_3005_CIRCULAR_TYPE_DEPENDENCY,
    ERR_3006_INVALID_COERCION,
    WARN_3010_UNUSED_VARIABLE,
    WARN_3011_UNREACHABLE_CODE,

    // LIR / Lowering
    ERR_4000_INVALID_CONTROL_FLOW,
    ERR_4001_UNRESOLVED_TYPE_IN_LOWER,
    ERR_4002_DEFER_IN_INVALID_SCOPE,

    // Emitter / Backend
    ERR_5000_C89_UNSUPPORTED_FEATURE,
    ERR_5001_MANGLE_OVERFLOW,
    ERR_5002_EMPTY_AGGREGATE,

    // System
    ERR_9000_OOM,
    ERR_9001_ICE,
    ERR_9999_TOO_MANY_ERRORS,
};

pub const Span = struct {
    file_id: u32,
    byte_start: u32,
    byte_end: u32,
};

pub const Diagnostic = struct {
    level: DiagnosticLevel,
    code: ErrorCode,
    span: Span,
    message_id: u32,           // interned string index for main message
    note_count: u8,            // attached contextual notes (max 3)
    note_ids: [3]u32,          // interned string indices for notes
    // For multi‑span notes (e.g., "declared here"), we store an index into a separate side‑table
    related_span_idx: u16,     // 0 = none, otherwise index into related_spans ArrayList
};

pub const RelatedSpan = struct {
    span: Span,
    message_id: u32,           // e.g., "declared here"
};

pub const DiagnosticCollector = struct {
    diagnostics: ArrayList(Diagnostic),
    related_spans: ArrayList(RelatedSpan),  // shared across all diagnostics
    interner: *StringInterner,
    allocator: *Allocator,
    error_count: u32,
    warning_count: u32,
    max_diagnostics: u32 = 256,
};
```

**Key Design Decisions:**

- Messages are **interned**, not copied. Reduces memory fragmentation and enables fast equality checks.
- `note_count`/`note_ids` allow attaching up to three contextual hints without dynamic allocation.
- `related_spans` provides a shared pool for cross‑reference notes (e.g., "declared here" pointing to another file). Each diagnostic can reference one related span via `related_span_idx`.
- `max_diagnostics` prevents infinite diagnostic generation in malformed inputs. Exceeding it emits a single `ERR_9999_TOO_MANY_ERRORS` and halts collection.

---

## 2. Collection Architecture & Lifetime

The `DiagnosticCollector` is instantiated once per compilation session, injected into every phase, and flushed to stdout/file at the end of the pipeline.

```zig
pub const CompilerContext = struct {
    diag: *DiagnosticCollector,
    alloc: *CompilerAlloc,
    interner: *StringInterner,
    source_mgr: *SourceManager,
    // ... other phase contexts
};

pub fn initDiagnosticCollector(alloc: *Allocator, interner: *StringInterner) !*DiagnosticCollector {
    var collector = try alloc.create(DiagnosticCollector);
    collector.* = .{
        .diagnostics = ArrayList(Diagnostic).init(alloc),
        .related_spans = ArrayList(RelatedSpan).init(alloc),
        .interner = interner,
        .allocator = alloc,
        .error_count = 0,
        .warning_count = 0,
    };
    try collector.diagnostics.ensureCapacity(64);
    try collector.related_spans.ensureCapacity(32);
    return collector;
}
```

**Collection API:**

```zig
/// Add a diagnostic. Returns the index of the new diagnostic (for attaching notes).
pub fn add(self: *DiagnosticCollector, level: DiagnosticLevel, code: ErrorCode,
           span: Span, message: []const u8) !u32 {
    if (self.diagnostics.items.len >= self.max_diagnostics) {
        if (self.diagnostics.items.len == self.max_diagnostics) {
            _ = self.add(.error, .ERR_9999_TOO_MANY_ERRORS, span,
                         "too many errors; further diagnostics suppressed");
        }
        return self.diagnostics.items.len - 1; // return index of cap warning
    }
    const msg_id = self.interner.intern(message);
    const idx = @intCast(u32, self.diagnostics.items.len);
    try self.diagnostics.append(.{
        .level = level,
        .code = code,
        .span = span,
        .message_id = msg_id,
        .note_count = 0,
        .note_ids = [3]u32{ 0, 0, 0 },
        .related_span_idx = 0,
    });
    if (level == .error) self.error_count += 1
    else if (level == .warning) self.warning_count += 1;
    return idx;
}

pub fn addNote(self: *DiagnosticCollector, diag_idx: u32, note: []const u8) !void {
    if (diag_idx >= self.diagnostics.items.len) return;
    var d = &self.diagnostics.items[diag_idx];
    if (d.note_count < 3) {
        d.note_ids[d.note_count] = self.interner.intern(note);
        d.note_count += 1;
    }
}

/// Attach a related span (e.g., "declared here") to the diagnostic.
pub fn addRelatedSpan(self: *DiagnosticCollector, diag_idx: u32, span: Span, msg: []const u8) !void {
    if (diag_idx >= self.diagnostics.items.len) return;
    const rs_idx = @intCast(u16, self.related_spans.items.len);
    try self.related_spans.append(.{ .span = span, .message_id = self.interner.intern(msg) });
    self.diagnostics.items[diag_idx].related_span_idx = rs_idx;
}
```

**Lifetime:**

- `permanent` arena: `interner`, `SourceManager` spans, `DiagnosticCollector` itself.
- `module` arena: `DiagnosticCollector.diagnostics` and `related_spans` ArrayLists. **These are reset after each module's C89 emission**, because cross‑module diagnostics (e.g., type mismatches from imported modules) must survive until all modules are processed.
- `scratch` arena: Temporary buffers for formatting messages before interning.

---

## 3. Phase‑Specific Error Recovery

Each compiler phase implements deterministic recovery to maintain pipeline continuity without propagating invalid state.

### 3.1 Lexer Recovery

```zig
fn nextToken(lex: *Lexer) Token {
    // ...
    if (unrecognized_char) {
        const start = lex.pos;
        _ = lex.advance(); // consume bad char
        const tok = lex.makeErrorToken(start);
        lex.diag.add(.error, .ERR_1000_UNRECOGNIZED_CHAR, tok.span, "unrecognized character");
        return tok;
    }
    if (unterminated_string) {
        // Close at EOF, emit diagnostic, return string token with whatever we have
        lex.diag.add(.error, .ERR_1000_UNTERMINATED_STRING, span, "unterminated string literal");
        return makeToken(.string_literal, span_start, .{ .string_id = interned });
    }
    // ...
}
```

### 3.2 Parser Recovery

Synchronization tokens: `semicolon`, `rbrace`, `kw_fn`, `kw_const`, `kw_var`, `kw_pub`, `kw_test`, `eof`.

```zig
fn synchronize(p: *Parser) void {
    while (p.pos < p.tokens.len) {
        const k = p.tokens[p.pos].kind;
        if (k == .semicolon or k == .rbrace or k == .kw_fn or
            k == .kw_const or k == .kw_var or k == .kw_pub or
            k == .kw_test or k == .eof) {
            return;
        }
        p.pos += 1;
    }
}
```

On unexpected token:
1. Emit `ERR_2000_UNEXPECTED_TOKEN`.
2. Create `AstKind.err` node.
3. Call `synchronize()`.
4. Return the error node and continue parsing.

### 3.3 Type Resolution Recovery

- **Cycle detection:** After Kahn's algorithm, any type with `in_degree > 0` is part of a cycle. Mark it as `TYPE_VOID` and emit `ERR_3005_CIRCULAR_TYPE_DEPENDENCY`.
- **Unresolved names:** Emit `ERR_3001_UNDEFINED_SYMBOL` and replace with `TYPE_VOID`.

### 3.4 Semantic Analysis Recovery

- **Poison propagation:** Any expression whose type is `TYPE_VOID` or that references an undefined symbol yields `TYPE_VOID`.
- **Constraint checking:** Skips nodes involving poison types.
- **Function bodies with errors:** Lowering still produces a valid (but empty) `LirFunction` so the pipeline can continue for other functions.

### 3.5 LIR Lowering Recovery

- **Function‑level bailout:** If the function's return type is poison or contains unresolved types, skip lowering entirely and emit a stub `LirFunction` that returns `undefined`.
- **Invalid control flow:** Emit `ERR_4000_INVALID_CONTROL_FLOW` and insert a `nop` to preserve block structure.

### 3.6 C89 Emission Skip

```zig
if (ctx.diag.hasErrors()) {
    // Do not emit any C89 output
    return;
}
```

This prevents confusing downstream C compiler errors caused by incomplete or invalid LIR.

---

## 4. Out‑of‑Memory and Internal Compiler Error Handling

These are **hard aborts**—they cannot be recovered. However, we must report them cleanly before exiting.

```zig
pub fn panicHandler(msg: []const u8, file: []const u8, line: u32) noreturn {
    // Minimal write to stderr (PAL call, no allocation)
    pal.stderr_write("ICE: ");
    pal.stderr_write(msg);
    pal.stderr_write(" at ");
    pal.stderr_write(file);
    pal.stderr_write(":");
    // Write line number (simple itoa)
    var buf: [16]u8 = undefined;
    const len = itoa(line, &buf);
    pal.stderr_write(buf[0..len]);
    pal.stderr_write("\n");
    pal.exit(3);
}
```

For OOM, the allocator wrapper calls this handler with `"out of memory"`.

**Z98 Constraint:** The panic handler must **not** allocate, must **not** use `std.debug.print`, and must work on Win9x (calls `WriteFile` to `GetStdHandle(STD_ERROR_HANDLE)` via PAL).

---

## 5. Memory, Performance & Determinism Constraints

| Constraint | Enforcement Mechanism |
|---|---|
| **<16 MB Peak RAM** | `DiagnosticCollector` capped at 256 entries. Interned messages reused. Scratch arena reset per phase. |
| **Deterministic Order** | Final sort: `file_id` (stable), `span_start` (stable), `level` (error→warning→info), `code`. |
| **O(1) Append** | ArrayList amortized growth. `ensureCapacity()` called at startup. |
| **No Global State** | Collector injected explicitly via `CompilerContext`. |
| **ASCII/Latin‑1 Only** | Unicode escapes rejected in lexer; non‑ASCII replaced with `?` in diagnostic messages. |

**Sorting Algorithm (Insertion Sort, Deterministic):**

```zig
fn sortDiagnostics(self: *DiagnosticCollector) void {
    var i: usize = 1;
    while (i < self.diagnostics.items.len) : (i += 1) {
        const key = self.diagnostics.items[i];
        var j: usize = i;
        while (j > 0) : (j -= 1) {
            const prev = self.diagnostics.items[j - 1];
            if (compareDiag(prev, key) <= 0) break;
            self.diagnostics.items[j] = self.diagnostics.items[j - 1];
        }
        self.diagnostics.items[j] = key;
    }
}

fn compareDiag(a: Diagnostic, b: Diagnostic) i32 {
    if (a.span.file_id != b.span.file_id) return @intCast(i32, a.span.file_id) - @intCast(i32, b.span.file_id);
    if (a.span.byte_start != b.span.byte_start) return @intCast(i32, a.span.byte_start) - @intCast(i32, b.span.byte_start);
    if (a.level != b.level) return @intCast(i32, @enumToInt(a.level)) - @intCast(i32, @enumToInt(b.level));
    return @intCast(i32, @enumToInt(a.code)) - @intCast(i32, @enumToInt(b.code));
}
```

---

## 6. CLI Integration & Output Formatting

The compiler CLI consumes the sorted `DiagnosticCollector` and formats output based on terminal capabilities and flags.

**Standard Format:**

```
src/eval.zig:42:10: error[E3000]: type mismatch: expected 'i32', found '[]const u8'
    const x: i32 = "hello";
             ^~~~
note: help: use @intCast or change variable type
```

**Configuration Flags:**

| Flag | Behavior |
|---|---|
| `--color=auto\|always\|never` | ANSI escapes for levels |
| `--max-errors=N` | Stop after N errors (default: 256) |
| `--warnings-as-errors` | Treat `warning` as `error` for exit code |
| `--error-format=human\|json\|sarif` | Machine‑readable output |
| `--quiet` | Suppress warnings/info |

**JSON Output Schema:**

```json
{
  "diagnostics": [
    {
      "level": "error",
      "code": "E3000",
      "file": "src/eval.zig",
      "line": 42,
      "column": 10,
      "message": "type mismatch: expected 'i32', found '[]const u8'",
      "notes": ["help: use @intCast or change variable type"]
    }
  ],
  "summary": { "errors": 1, "warnings": 0 }
}
```

**Exit Codes:**

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Warnings only (or `--warnings-as-errors` triggered) |
| `2` | Errors detected |
| `3` | ICE / OOM (hard abort) |

---

## 7. Z98 Constraints & Workarounds

| Limitation | Workaround |
|---|---|
| No `try` in non‑error functions | Use `catch unreachable` for ICEs. For recoverable errors: explicit `if (err) { self.diag.add(...); return; }` |
| No global aggregate constants | `DiagnosticCollector` allocated at startup, passed via `CompilerContext` |
| Strict `i32` ↔ `usize` coercion | All span/offset arithmetic uses `@intCast(u32, ...)` with explicit checks |
| C89 string literal limits (2048 chars) | Diagnostic messages truncated to 256 chars in collector; full text kept in arena if needed |
| Win9x console width (80 chars) | Context lines wrapped at 78 chars; caret aligned to source column |
| `zig0` lacks `@enumToInt` | Use manual `switch` or direct cast (Z98 subset allows cast for enums with explicit backing type) |

**Error Handling Pattern for `zig0`‑Compiled `zig1`:**

```zig
// Functions that can't return error unions use this pattern:
fn parseSomething(p: *Parser) !u32 {
    const tok = p.nextToken();
    if (tok.kind == .err_token) {
        try p.diag.add(.error, .ERR_2000_UNEXPECTED_TOKEN, tok.span, "unexpected token");
        return error.UnexpectedToken;
    }
    // ...
}
```

The caller handles `error.UnexpectedToken` and continues recovery.

---

## 8. Testing & Validation Strategy

| Test Layer | Input | Verified Property |
|---|---|---|
| **Unit: Lexer Recovery** | `0xFF "unterminated` | `.err_token` emitted, diagnostic appended, lexer continues |
| **Unit: Parser Sync** | `fn foo() { if (x) return; bar` | `AstKind.err` inserted, syncs to next `;`/`eof`, no crash |
| **Unit: Poison Propagation** | `const x = undefined + 1; const y = x + 2;` | Single error on line 1, line 2 silently skipped |
| **Integration: Diagnostic Count** | `bad_program.zig` | Exact error/warning count matches golden file |
| **Determinism: Order Stability** | Compile same source 10x | Byte‑identical `--dump-diagnostics` output |
| **Memory Gate** | Pathological 50k‑line malformed input | `DiagnosticCollector` caps at 256, peak < 16 MB |
| **CLI: JSON Format** | `--error-format=json` | Valid JSON, matches schema, parseable by `jq` |
| **Differential vs `zig0`** | Reference programs with errors | Error spans/codes match (allowing improved messages) |
| **ICE Simulation** | Trigger `@panic("test")` in compiler code | Exit code 3, stderr contains "ICE" and location |

---

## 9. Extensibility Hooks

The architecture is designed for incremental post‑self‑hosting upgrades:

| Feature | Extension Point |
|---|---|
| **Custom Formatters** | Replace `formatHuman()` with `formatJson()`, `formatSarif()`, `formatJUnit()` |
| **Severity Overrides** | `--ignore=W3010`, `--warn-as-error=E3003` via CLI parser mapping to `ErrorCode` |
| **IDE/LSP Integration** | `--error-format=json` + `--watch` mode for incremental recompilation |
| **Plugin Diagnostics** | Post‑self‑hosting: `DiagnosticCollector` becomes an interface; plugins append via callback |
| **Cross‑Reference Errors** | Already supported via `related_spans` |
| **Localization** | `message_id` maps to translation table; CLI selects locale at startup |

---

## Appendix A: Complete Diagnostic Codes & Levels

| Code | Level | Category | Message Template |
|---|---|---|---|
| `E1000` | error | Lexer | "unterminated string literal" |
| `E1001` | error | Lexer | "unterminated block comment" |
| `E1002` | error | Lexer | "invalid character literal" |
| `E1003` | error | Lexer | "invalid escape sequence" |
| `W1010` | warning | Lexer | "unrecognized escape sequence, treated as literal" |
| `W1011` | warning | Lexer | "integer literal overflow, saturated to max value" |
| `E2000` | error | Parser | "unexpected token '{tok}', expected '{expected}'" |
| `E2001` | error | Parser | "missing semicolon" |
| `E2002` | error | Parser | "unclosed brace" |
| `E2003` | error | Parser | "expected expression" |
| `E2004` | error | Parser | "expected type expression" |
| `W2010` | warning | Parser | "deprecated syntax, use '{new}' instead" |
| `E3000` | error | Semantic | "type mismatch: expected '{expected}', found '{found}'" |
| `E3001` | error | Semantic | "undefined symbol '{name}'" |
| `E3002` | error | Semantic | "cannot assign to immutable variable" |
| `E3003` | error | Semantic | "missing return statement" |
| `E3004` | error | Semantic | "switch must handle all cases" |
| `E3005` | error | Semantic | "circular type dependency" |
| `E3006` | error | Semantic | "invalid coercion from '{from}' to '{to}'" |
| `W3010` | warning | Semantic | "unused variable '{name}'" |
| `W3011` | warning | Semantic | "unreachable code" |
| `E4000` | error | Lowering | "invalid control flow (break/continue outside loop)" |
| `E4001` | error | Lowering | "unresolved type in lowering" |
| `E4002` | error | Lowering | "defer in invalid scope" |
| `E5000` | error | Emitter | "C89 does not support this feature" |
| `E5001` | error | Emitter | "mangled name exceeds 31 characters" |
| `E5002` | error | Emitter | "empty struct/union requires dummy field" |
| `E9000` | error | System | "out of memory" |
| `E9001` | error | System | "internal compiler error" |
| `E9999` | error | System | "too many errors, stopping" |

---

## Appendix B: Synchronization Points Table

| Context | Sync Tokens | Recovery Action |
|---|---|---|
| Statement list | `;`, `}`, `kw_fn`, `kw_const`, `kw_var`, `kw_pub`, `eof` | Skip to next token, emit `AstKind.err`, continue parsing |
| Expression | `)`, `]`, `}`, `,`, `;`, `eof` | Return `AstKind.err` node, unwind to `parseExprPrec` |
| Switch prong | `=>`, `,`, `}`, `else`, `eof` | Skip to `=>` or `}`, mark prong as `err` |
| Function body | `}`, `eof` | Close block early, emit implicit `return` if non‑void |
| Module root | `kw_fn`, `kw_const`, `kw_var`, `kw_test`, `eof` | Skip malformed top‑level, continue import resolution |

---

## Appendix C: Core Compilation Loop with Error Gates

```zig
pub fn runCompiler(ctx: *CompilerContext) !void {
    // Phase 1: Lexing & Parsing (per module, on-demand)
    try phase_ImportResolution(ctx);
    if (ctx.diag.hasErrors()) {
        try ctx.diag.flushAndExit(2);
        return;
    }
    
    // Phase 2: Symbol Registration
    try phase_SymbolRegistration(ctx);
    // (errors can be collected but we continue to type resolution for more errors)
    
    // Phase 3: Type Resolution (Kahn)
    try phase_TypeResolution(ctx);
    if (ctx.diag.hasErrors()) {
        try ctx.diag.flushAndExit(2);
        return;
    }
    
    // Phase 4: Semantic Analysis
    try phase_SemanticAnalysis(ctx);
    if (ctx.diag.hasErrors()) {
        try ctx.diag.flushAndExit(2);
        return;
    }
    
    // Phase 5: LIR Lowering
    try phase_LIRLowering(ctx);
    // Errors here are fatal for the affected function, but we continue lowering others
    
    // Phase 6: C89 Emission (skipped if any errors exist)
    if (ctx.diag.hasErrors()) {
        try ctx.diag.flushAndExit(2);
        return;
    }
    try phase_C89Emission(ctx);
    
    // Flush any remaining warnings/info
    if (ctx.diag.warning_count > 0) {
        ctx.diag.flush();
        if (ctx.cli.warn_as_errors) {
            pal.exit(1);
        }
    }
}
```

---

This enriched document provides a **spaceship‑grade** error handling foundation. It is fully aligned with Z98 constraints, integrates seamlessly with all other compiler phases, and guarantees deterministic, memory‑bounded, and recoverable diagnostics—exactly what is needed for a robust self‑hosting compiler on 1998‑era hardware.
