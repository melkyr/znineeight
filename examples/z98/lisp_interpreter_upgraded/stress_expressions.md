# Lisp Stress Tests & Limits

This document records the performance and recursion limits of the `lisp_interpreter_curr` on 32-bit hardware (simulated via `gcc -m32`).

## Test Results Summary

| Expression | Complexity | Result | Notes |
|------------|------------|--------|-------|
| `(countdown 5)` | Simple | **Success: 0** | Baseline check. |
| `(countdown 5000)` | Tail-Recursive | **Success: 0** | Verifies TCO. |
| `(countdown 10000)`| Tail-Recursive | **Failure: OutOfMemory** | Limits of the 1MB temporary arena. |
| `(fact 5)` | Recursive | **Success: 120** | Non-tail recursion check. |
| `(fact 12)` | Recursive | **Success: 479001600** | Largest factorial within `i32` range. |
| `(fact 13)` | Recursive | **Panic: Integer Overflow** | Exceeds checked 64-bit limits at the runtime level. |
| `(fib 7)` | Tree-Recursive | **Success: 13** | Standard tree recursion. |
| `(even? 4)` | Mutual Recursion| **Success: true** | Requires `odd?` to be defined. |
| `(even? 1000)` | Mutual Recursion| **Success: true** | TCO handles mutual tail calls. |

## Detailed Observations

### 1. Tail-Call Optimization (TCO)
The implementation of TCO allows the interpreter to handle deep recursion for tail-recursive functions.
- **Countdown**: `(define countdown (lambda (n) (if (= n 0) 0 (countdown (- n 1)))))`
- At `n=5000`, the interpreter succeeds, which was previously impossible without TCO as it would exhaust the Zig-to-C stack.
- The limit is currently determined by the 1MB `temp_sand` arena, which must store the environment for the current call.

### 2. Recursion Depth (Non-TCO)
Standard recursive calls (like the naive `fact` or `fib`) still consume C stack space and arena memory.
- `(fact 5)` works perfectly.
- `(fib 7)` works perfectly.
- Higher depths are primarily constrained by the temporary arena during the evaluation of arguments and intermediate results.

### 3. Mutual Recursion
Mutual recursion works as expected. The interpreter handles cross-references between closures correctly.
```lisp
(define odd? nil)
(define even? (lambda (n) (if (= n 0) true (odd? (- n 1)))))
(define odd? (lambda (n) (if (= n 0) false (even? (- n 1)))))
(even? 1000) ; Success: true
```

### 4. Memory Exhaustion
When the 1MB temporary arena is exhausted, the interpreter returns `Eval error: OutOfMemory`. This prevents segfaults and allows the REPL to continue after resetting the arena.

### 5. Runtime Limits
Z98 enforces safety checks on integer casts. Factorial calculations above 12 result in a `PANIC: integer cast overflow` because the resulting value exceeds the limits of the internal Z98 runtime types used for printing or intermediate storage.
