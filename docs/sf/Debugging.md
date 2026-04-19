# DEBUGGING.md – The `zig1` Developer's Tactical Survival Guide

**Version:** 1.0  
**Audience:** Developers working on `zig1` itself (not end users)  
**Context:** `zig1` is compiled by `zig0` and runs on a target with limited debugging tools.  
**Placement:** Read this **before** writing any `zig1` code. Keep it open during development.

---

## 0. The Fundamental Problem – Why This Document Exists

You are building a compiler with a compiler that you cannot easily debug. The stack looks like this:

```
[Your Z98 Source: zig1.zig]
          ↓ (compiled by)
[zig0.exe (C++98 bootstrap)]  ← Black box. May have bugs.
          ↓ (produces)
[Generated C89: zig1.c]       ← Verbose, low-level, hard to map back.
          ↓ (compiled by)
[zig1.exe]                    ← Crashes or miscompiles.
```

When something goes wrong, you have **no interactive source-level debugger** for Z98. You cannot set a breakpoint in `zig1.zig` and step through it. You are effectively blind.

This document provides **explicit, tactical workflows** for isolating bugs across these layers. It is your flashlight in the dark.

---

## 1. The Debugging Pyramid – Use This Order

Always start at the top and work down. Do not jump to GDB immediately.

```
          /\
         /  \   HIGH LEVEL (Fast, easy)
        / 5. \  Use C++ Fallback Component
       /------\
      / 4. C   \ Debug Generated C with GDB/WinDbg
     /  Debugger \
    /-------------\
   / 3. Instrument \ Add @panic / std.debug.print
  /   with Prints   \
 /-------------------\
/ 2. Differential     \ Compare --dump-* against zig0
/    Testing           \
/-----------------------\
/ 1. Unit Tests         \ Run the test suite
/-------------------------\
```

- **Level 1:** Catches most regressions early.
- **Level 2:** Pinpoints which compiler phase is broken.
- **Level 3:** Narrows down within a phase.
- **Level 4:** Last resort for crashes.
- **Level 5:** Nuclear option when all else fails.

---

## 2. Level 1: The Test Suite – Your First Line of Defense

Before you even run `zig1` on a real program, run the unit tests.

```bash
# Build the test runner (using zig0)
zig0 build_test_runner.zig -o test_runner.exe

# Run all unit tests
./test_runner.exe
```

**If a test fails:**
1. The test name tells you which component is broken (e.g., `test_lexer_hex_literal`).
2. Look at the test source in `tests/`. It's a small, focused Z98 program.
3. Go to **Level 2** to compare `zig1`'s output for that test against `zig0`.

---

## 3. Level 2: Differential Testing with `--dump-*` Flags

Every pipeline stage has a dump flag. Use them to compare `zig1`'s output against `zig0`'s output for the **same input file**.

### 3.1 Available Dump Flags in `zig1`

| Flag | Outputs | Compares Against |
|---|---|---|
| `--dump-tokens` | Token stream (one per line: `KIND start len value`) | `zig0 --dump-tokens` |
| `--dump-ast` | S-expression AST | `zig0 --dump-ast` |
| `--dump-types` | Resolved types, sizes, alignments | `zig0 --dump-types` (if available) |
| `--dump-lir` | LIR basic blocks and instructions | *No zig0 equivalent; manual inspection or golden files* |
| `--dump-c89` | Generated C code | `zig0 --emit-c89` (or saved golden files) |

### 3.2 Workflow for Isolating a Phase Bug

**Scenario:** `zig1` compiles `test.z` but the resulting executable produces wrong output, while `zig0`'s version works.

```bash
# Step 1: Dump tokens
./zig1 --dump-tokens test.z > zig1_tokens.txt
./zig0 --dump-tokens test.z > zig0_tokens.txt
diff zig0_tokens.txt zig1_tokens.txt

# If diff shows differences → Lexer bug. Fix lexer.
# If no difference, continue.

# Step 2: Dump AST
./zig1 --dump-ast test.z > zig1_ast.txt
./zig0 --dump-ast test.z > zig0_ast.txt
diff zig0_ast.txt zig1_ast.txt

# If diff shows differences → Parser bug. Fix parser.
# If no difference, continue.

# Step 3: Dump Types
./zig1 --dump-types test.z > zig1_types.txt
# (zig0 may not have this; compare against expected layout)

# Step 4: Dump LIR
./zig1 --dump-lir test.z > zig1_lir.txt
# Compare against a golden LIR file (if you've saved one) or manually inspect.

# Step 5: Dump C89
./zig1 --dump-c89 test.z > zig1.c
./zig0 --emit-c89 test.z > zig0.c
diff zig0.c zig1.c
```

**Important:** The first stage where the outputs diverge is where the bug lives. Focus your debugging there.

### 3.3 Creating Minimal Reproducers

When a large program (like `zig1` itself) fails, create the smallest possible Z98 file that triggers the bug.

**Technique:**
1. Copy the failing module to `bug.zig`.
2. Delete half the code. Recompile. If bug persists, delete more. If bug disappears, restore the last deletion and delete other parts.
3. Repeat until you have a <50-line test case.
4. Add this test case to `tests/regression/` so it never comes back.

---

## 4. Level 3: Instrumentation with `@panic` and `std.debug.print`

When you've isolated the bug to a specific function but need to see *what's happening inside*, use print statements.

### 4.1 Adding Print Statements

```zig
// In the suspect function (e.g., type_resolver.zig)
fn resolveTypeLayout(reg: *TypeRegistry, tid: TypeId) !void {
    std.debug.print("DEBUG: resolveTypeLayout tid={}\n", .{tid});
    // ... rest of function
}
```

**Recompile `zig1` with `zig0`** and run it on your minimal reproducer. You will see the debug output on the console.

### 4.2 Bisecting with `@panic`

If `zig1` crashes (e.g., segfault or `zig0`-generated abort), add `@panic` to narrow down the crash location.

```zig
fn someFunction() void {
    @panic("reached point A");   // Add this, recompile, run.
    // ... code ...
    @panic("reached point B");
    // ... more code ...
}
```

If "reached point A" prints but "reached point B" does not, the crash is between A and B. Move the panics closer together.

### 4.3 Conditional Instrumentation

To avoid spamming output, use a global flag or environment variable:

```zig
const DEBUG_TYPE_RESOLVER = true;  // Set to false before committing

fn resolveTypeLayout(...) !void {
    if (DEBUG_TYPE_RESOLVER) {
        std.debug.print("DEBUG: tid={}\n", .{tid});
    }
    // ...
}
```

---

## 5. Level 4: Debugging the Generated C Code with GDB/WinDbg

When `zig1` crashes at runtime (segfault, assertion failure in `__bootstrap_*`), you can debug the **generated C executable** with a C debugger.

### 5.1 Compile `zig1` with Debug Symbols

First, get the generated C code from `zig1` (compiled by `zig0`):

```bash
# Compile zig1.zig with zig0, but ask it to emit C instead of an executable
# (This assumes zig0 has an --emit-c flag; if not, you'll need to modify zig0 or capture the intermediate C files)
zig0 --emit-c zig1.zig -o zig1.c
```

Then compile the C code manually with a C compiler that includes debug info:

```bash
# Using GCC (on Linux/mingw)
gcc -g -std=c89 -pedantic -o zig1_debug.exe zig1.c zig_runtime.c

# Using MSVC 6.0 (on Windows 98)
cl /Zi /Za /Fezig1_debug.exe zig1.c zig_runtime.c
```

### 5.2 Run Under GDB

```bash
gdb ./zig1_debug.exe
(gdb) run test.z          # Run zig1 on a test file
# ... zig1 crashes ...
(gdb) bt                  # Backtrace
(gdb) frame 0             # Inspect the crash frame
(gdb) list                # Show source code (should show Z98 source if #line directives are working)
```

**If `#line` directives are working**, GDB will show you the original `zig1.zig` source lines. If not, you'll see the generated C code. You can still debug, but it's more painful.

### 5.3 Common C-Level Crashes and What They Mean

| Crash Signature | Likely Cause in `zig1` |
|---|---|
| `Segmentation fault` at `__bootstrap_checked_cast_*` | A `@intCast` failed bounds check. The value was out of range. |
| `Assertion failed: ptr != NULL` | A `null` dereference in generated code. The `NullPointerAnalyzer` may have missed something, or you bypassed safety. |
| `Stack overflow` | Infinite recursion or large stack allocation. Check for recursive functions without base case. |
| `__bootstrap_panic("out of memory")` | Arena allocation exceeded budget. Check for memory leaks or oversized allocations. |

---

## 6. Level 5: The `--bootstrap-safe` Escape Hatch

Some bugs only appear when `zig1` is compiled with optimizations or uses complex Z98 features that `zig0` mishandles.

**Add a flag `--bootstrap-safe` to `zig1`** (early in development) that:

- Disables any LIR optimizations.
- Lowers complex control flow (`switch`, `try`) to simpler, more verbose patterns.
- Avoids using Z98 features known to trigger `zig0` bugs (e.g., deeply nested `switch` expressions).

When a bug is elusive:

```bash
# Rebuild zig1 with bootstrap-safe mode enabled
zig0 zig1.zig -o zig1_safe.exe -- -Dbootstrap_safe=true

# Run the test that was failing
./zig1_safe.exe test.z
```

If the bug disappears, the problem is either:
- In an optimization pass.
- In `zig0`'s handling of a complex language feature.

You can then selectively disable parts of `zig1` to pinpoint the exact trigger.

---

## 7. The Nuclear Option: Rewriting a Component in C++

If a specific component of `zig1` (e.g., the type resolver) is hopelessly buggy and you **cannot debug it from within Z98**, temporarily rewrite that component in C++ and link it as an `extern "C"` library.

### 7.1 How to Do It

1. Create a C++ file (e.g., `type_resolver_fallback.cpp`) that implements the same interface as the Z98 component.
2. Compile it with a modern C++ compiler to a static library or object file.
3. In `zig1.zig`, declare the functions as `extern "c"`.
4. Link the C++ object file when building `zig1` with `zig0`.

```zig
// In zig1.zig
extern "c" fn fallback_resolve_types(reg: *TypeRegistry) bool;
```

This is a valid bootstrapping technique. Once the rest of `zig1` is stable, you can rewrite the C++ component in Z98 with confidence.

---

## 8. Debugging `zig0` Itself (When All Else Fails)

If you suspect `zig0` is miscompiling `zig1`, you can debug `zig0` as a C++ program.

1. Recompile `zig0` with debug symbols (`-g` for GCC, `/Zi` for MSVC).
2. Run `zig0` under a C++ debugger (GDB or Visual Studio).
3. Set breakpoints in the `zig0` source code that correspond to the Z98 feature you're using.
4. Step through `zig0`'s compilation of `zig1.zig` and watch its internal state.

This is time-consuming but can be necessary. You've already done this during the initial bootstrap phase.

---

## 9. Phase-Specific Debugging Tips

### 9.1 Lexer
- Use `--dump-tokens` and `diff` against `zig0`.
- If `zig0` doesn't have `--dump-tokens`, write a small Z98 program that prints tokens and compare output.
- Print the token kind and lexeme for each token in a loop.

### 9.2 Parser
- Use `--dump-ast` and `diff` against `zig0`.
- If the AST is huge, use `--dump-ast` on a minimal test case.
- Add `@panic` in the parser when an unexpected token is encountered.

### 9.3 Type System
- Use `--dump-types` to see resolved sizes/alignments.
- Add `std.debug.print` in `TypeRegistry.getOrCreate*` to see what types are being created.
- Watch for infinite loops in Kahn's algorithm: add a loop counter and panic if it exceeds `types.len * 2`.

### 9.4 LIR Lowering
- Use `--dump-lir` and visually inspect the basic blocks.
- Add a `--dump-lir-graph` option that outputs DOT format. Render with GraphViz to see control flow.
- Panic if a basic block is not terminated.

### 9.5 C89 Emission
- Use `--dump-c89` and compile the output with `gcc -std=c89 -pedantic -Wall -Werror`. Fix all warnings/errors.
- Add a `--no-line-directives` flag to get clean diffs.
- Test the emitted C on multiple C89 compilers (GCC, MSVC, OpenWatcom) early.

---

## 10. Debugging Checklist – When You're Stuck

Print this and tape it to your monitor.

- [ ] Have I run the unit test suite? (`./test_runner.exe`)
- [ ] Have I created a **minimal reproducer** (<50 lines)?
- [ ] Have I dumped and diffed **every pipeline stage**?
- [ ] Have I added `std.debug.print` to the suspect function?
- [ ] Have I bisected with `@panic`?
- [ ] Have I tried `--bootstrap-safe` mode?
- [ ] Have I stepped through the generated C in **GDB**?
- [ ] Have I asked a **rubber duck** to explain the code line by line?
- [ ] Have I checked `ZIG0_KNOWN_ISSUES.md` for relevant bugs?
- [ ] Have I considered rewriting the component in **C++ as a fallback**?

---

## 11. Appendix: Useful `zig0` Commands for Debugging

Since `zig0` is your bootstrap, here are some commands that may help you debug `zig1`:

```bash
# Dump tokens for a file
zig0 --dump-tokens test.z

# Dump AST (if supported)
zig0 --dump-ast test.z

# Emit C code instead of compiling
zig0 --emit-c test.z -o test.c

# Compile with debug symbols (if zig0 passes -g to C compiler)
zig0 -g test.z -o test_debug.exe

# Increase memory limit for zig0 itself (if it crashes)
zig0 --max-mem=32M zig1.zig -o zig1.exe
```

---

**Remember:** You are not alone in the dark. This document is your map. The `--dump-*` flags are your eyes. `@panic` is your voice. And `diff` is your compass.
