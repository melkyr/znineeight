// P3-M3 entry-stop honesty fixture: module init faults before main. z9dbg
// must report a pre-entry signal stop, not a normal entry stop.
var bad: u32 = boom();

fn boom() u32 {
    var p: *u32 = @intToPtr(*u32, 0);
    return p.*;
}

pub fn main() void {}
