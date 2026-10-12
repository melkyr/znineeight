const colors = @import("colors.zig");

const Cell = struct { ch: u8, fg: u8, bg: u8 };

pub fn main() void {
    var cell = Cell{ .ch = ' ', .fg = colors.COLOR_WHITE, .bg = colors.COLOR_BLACK };
    cell.fg = colors.COLOR_WHITE;
    _ = cell;
}
