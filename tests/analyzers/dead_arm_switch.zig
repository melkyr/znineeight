// dead_arm_switch.zig — T9a DED-2 switch-prong gating fixture.
//
// The selector is comptime-known (`switch (1)` / `switch (0)`), so exactly one
// prong exists for analysis. The dead `0 =>` prong in `dead_switch` must not
// emit the double free; the live `0 =>` prong in `live_switch` still must.
const Sand = struct { dummy: u32 };

fn sandAlloc(s: *Sand, n: usize, a: usize) *u8 {
    _ = s;
    _ = n;
    _ = a;
    return @intToPtr(*u8, 8);
}

fn sandFree(s: *Sand, p: *u8) void {
    _ = s;
    _ = p;
}

fn dead_switch(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    switch (1) {
        0 => {
            sandFree(s, p);
            sandFree(s, p);
        },
        else => {
            sandFree(s, p);
        },
    }
}

fn live_switch(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    switch (0) {
        0 => {
            sandFree(s, p);
            sandFree(s, p);
        },
        else => {
            sandFree(s, p);
        },
    }
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    dead_switch(&s);
    live_switch(&s);
}
