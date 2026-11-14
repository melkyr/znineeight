# load_global_array_copy — RED  [Defensive repros — Plan 1, 2026-08-04]

## What it tests
Reading a module-global array (`buf[3]`, `buf[15]`) after filling it in a loop. Guards
correctness of F-7's array `load_global` copy-loop (temp_global_map redirection).

## Expected classification
OK — values 3 and 15 print correctly when linked and run.

## Deferred item
Optimization note: F-7's `load_global` emits a dead copy-loop (temp_global_map
redirection) that is correct but wasteful for large arrays (see lisp's 1MB buffers).
This repro GUARDS correctness; the optimization is a separate future task.
