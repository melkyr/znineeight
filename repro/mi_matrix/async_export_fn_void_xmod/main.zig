// async_export_fn_void_xmod — FEATURE-GAP RED fixture (suspending `export fn`, void).
//
// Void CONTROL for `async_export_fn_xmod`: same missing-synchronous-entry gap,
// but the `export fn` returns void. This pins the driver's `ret_void` tail
// (Task 8-F: the value-returning driver `ret`s from a local result buffer; a
// void driver `ret_void`s as root `main` does today).
//
// Shape: `notify(n: i32) void` suspends via `@asyncSuspend` then prints `n`;
// `pub fn main` calls it. main's direct call is an implicit await, so main is
// transformed and gets its own synthesized driver.
//
// RED today: the transform replaces `notify`'s LIR with `__Z98Step_notify` and
// never streams the original, so the emitted C has NO external symbol named
// `notify`. Evidence:
//   nm prog | grep notify  ->  T zF_<hash>___Z98Step_notify  (only the step)
//   grep -E '\bnotify\b' main_*.c  ->  no match
// The awaited call still runs to completion within main, so the runtime already
// prints "5\n"; the RED is the absent source-named external symbol.
//
// GREEN (contract): the emitted C contains a non-static void definition named
// `notify` that drives the step to completion; main still prints "5\n".
// Expected stdout: "5\n".
const std = @import("std");

export fn notify(n: i32) void {
    @asyncSuspend(null);
    std.io.printInt(n);
    std.io.writeByte('\n');
}

pub fn main() void {
    notify(5);
}
