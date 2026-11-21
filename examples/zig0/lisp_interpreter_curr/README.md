# Z98 Lisp Interpreter (`lisp_interpreter_curr`)

This is a stable Lisp interpreter built using the Z98 Milestone 11 compiler. It targets 32-bit C89 and demonstrates the compiler's ability to handle complex tagged unions, recursion, and arena allocation.

## Current Status: Milestone 11 Verified

The interpreter is fully functional in 32-bit mode. Recent updates have improved its stability and performance.

### Key Features
- **Tail-Call Optimization (TCO)**: The core `eval` loop has been refactored to support TCO. This allows deep tail recursion (e.g., `countdown` or `factorial-iter`) without exhausting the C stack.
- **Arena Memory Management**: Uses a dual-arena system (Permanent and Temporary) to manage Lisp values efficiently within a < 16MB memory footprint.
- **Milestone 11 Support**: Leverages advanced Z98 features like braceless control flow and improved tagged union codegen.

## Limitations & Known Issues

- **One Expression Per Line**: The REPL currently only parses and evaluates the first Lisp expression found on each input line. Multiple expressions like `(define a 1) (define b 2)` must be entered on separate lines.
- **Integer Overflow**: Uses 64-bit integers (`i64`), but the Z98 runtime currently enforces safety checks. Operations that exceed `i64` limits (like `(fact 13)`) will trigger a runtime panic.
- **Memory Exhaustion**: The temporary arena is fixed at 1MB. Extremely deep recursion or massive list processing that allocates many temporary objects without returning to the REPL loop may hit `OutOfMemory`.
- **64-bit Compatibility**: This interpreter is optimized for 32-bit targets. Building in 64-bit mode may lead to memory alignment issues or segfaults.

## Quick Start

1. **Build the Interpreter**:
   ```bash
   ./build_target.sh
   ```

2. **Run the REPL**:
   ```bash
   ./app
   ```

3. **Try an Expression**:
   ```lisp
   > (define fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1))))))
   <closure>
   > (fact 5)
   120
   ```

4. **Exit**:
   Type `exit` or use `Ctrl+C`.
