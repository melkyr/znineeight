// async_export_fn_xmod — FEATURE-GAP RED fixture (suspending `export fn`, value).
//
// Feature: a suspending `export fn` must keep a synthesized synchronous entry
// under its SOURCE name, exactly like root `pub fn main` (Task 8-F). Today only
// root `main` is a driver target (`sf/src/async_state_machine.zig:597`
// `isRootMain` requires module 0 + `is_pub` + `"main"`).
//
// Shape: `bump(n: i32) i32` suspends via `@asyncSuspend` then returns `n+1`;
// `pub fn main` calls it and prints the result. Because `bump` is suspending,
// main's direct call is an implicit await, so main is transformed too and gets
// its own synthesized driver.
//
// RED today: the async transform replaces `bump`'s LIR with `__Z98Step_bump`
// and never streams the original (`sf/src/main.zig:770-779`), so the emitted C
// has NO external symbol named `bump` — only the temp-mangled step. There is no
// synchronous entry an external caller could invoke, so there is no
// value-returning path across the export boundary. Evidence:
//   nm prog | grep bump  ->  T zF_<hash>___Z98Step_bump   (only the step)
//   grep -E '\bbump\b' main_*.c  ->  no match
// The awaited value still round-trips *within* main (its implicit await points
// the child's hidden result field at main's parent-result slot), so the runtime
// already prints "6\n"; the RED is the absent source-named external symbol.
//
// GREEN (contract): the emitted C contains a non-static definition named `bump`
// (source name, not temp-mangled) that drives the step to completion and
// returns n+1; main still prints "6\n". Expected stdout: "6\n".
const std = @import("std");

export fn bump(n: i32) i32 {
    @asyncSuspend(null);
    return n + 1;
}

pub fn main() void {
    std.io.printInt(bump(5));
    std.io.writeByte('\n');
}
