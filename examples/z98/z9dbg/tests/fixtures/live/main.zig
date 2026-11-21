// P3-M3 live-session fixture: no stdout, deterministic control flow.
// The debuggee writes a completion marker to argv[1] (when supplied) so the
// tier can prove a detached/continued process ran to completion.
const std = @import("std");
const os = @import("std_os");
const file_mod = @import("std_file");

var counter: u32 = 0;

fn addTwo(n: u32) u32 {
    const a = n + 1;
    const b = a + 1;
    return b;
}

fn middle(n: u32) u32 {
    const r = addTwo(n);
    return r;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    var x = middle(5);
    x = addTwo(x);
    counter = x;
    os.initArgs(argc, argv);
    if (os.argc() > 1) {
        file_mod.writeAll(os.argv(1), "done\n") catch {};
    }
}
