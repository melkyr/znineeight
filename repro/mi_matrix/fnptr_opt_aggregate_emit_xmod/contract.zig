// contract.zig — D1 emit-ordering shape's shared type contract (T0 fixture).
// Reproducer B of examples/torrent_example_defects.md "D1": a struct that
// merely DEFINES a fn-pointer field returning `?Key` (never assembled) forces
// the fn-pointer typedef whose return is the optional composite. See main.zig.
pub const Key = union(enum) { char: u8, sigint, up, down, left, right, enter, esc };
pub const Console = struct {
    clear_fn: fn (*void) void,
    setCursor_fn: fn (*void, u16, u16) void,
    writeStr_fn: fn (*void, []const u8) void,
    readKey_fn: fn (*void) ?Key,
    enterRaw_fn: fn (*void) void,
    leaveRaw_fn: fn (*void) void,
    width_fn: fn (*void) u16,
    height_fn: fn (*void) u16,
    cursorShow_fn: fn (*void, bool) void,
    state: *void,
};
