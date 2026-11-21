// D2 cross-module enum: the enum type lives in colors.zig; the range switches
// stay in main.zig. The prong labels are still dropped.
pub const Color = enum { Red, Green, Blue };
