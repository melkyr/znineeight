const std = @import("std");

const Inst = union(enum) {
    int_const: struct { value: u64, result: u32 },
    int_cast: struct { value: u32, target: u32, result: u32, is_checked: u8 },
    float_const: struct { value: f64, result: u32 },
    float_cast: struct { value: f64, target: u32, result: u32 },
};

fn getResult(inst: Inst) u32 {
    var acc: u32 = 0;
    var a0: u32 = 0; var a1: u32 = 0; var a2: u32 = 0; var a3: u32 = 0;
    var a4: u32 = 0; var a5: u32 = 0; var a6: u32 = 0; var a7: u32 = 0;
    var a8: u32 = 0; var a9: u32 = 0; var a10: u32 = 0; var a11: u32 = 0;
    var a12: u32 = 0; var a13: u32 = 0; var a14: u32 = 0; var a15: u32 = 0;
    var a16: u32 = 0; var a17: u32 = 0; var a18: u32 = 0; var a19: u32 = 0;
    var a20: u32 = 0; var a21: u32 = 0; var a22: u32 = 0; var a23: u32 = 0;
    var a24: u32 = 0; var a25: u32 = 0; var a26: u32 = 0; var a27: u32 = 0;
    var a28: u32 = 0; var a29: u32 = 0; var a30: u32 = 0; var a31: u32 = 0;
    var a32: u32 = 0; var a33: u32 = 0; var a34: u32 = 0; var a35: u32 = 0;
    var a36: u32 = 0; var a37: u32 = 0; var a38: u32 = 0; var a39: u32 = 0;
    var a40: u32 = 0; var a41: u32 = 0; var a42: u32 = 0; var a43: u32 = 0;
    var a44: u32 = 0; var a45: u32 = 0; var a46: u32 = 0; var a47: u32 = 0;
    var a48: u32 = 0; var a49: u32 = 0; var a50: u32 = 0; var a51: u32 = 0;
    var a52: u32 = 0; var a53: u32 = 0; var a54: u32 = 0; var a55: u32 = 0;
    var a56: u32 = 0; var a57: u32 = 0; var a58: u32 = 0; var a59: u32 = 0;
    var a60: u32 = 0; var a61: u32 = 0; var a62: u32 = 0; var a63: u32 = 0;
    var a64: u32 = 0; var a65: u32 = 0; var a66: u32 = 0; var a67: u32 = 0;
    var a68: u32 = 0; var a69: u32 = 0;
    switch (inst) {
        .int_const => |ic| acc = ic.result,
        .int_cast => |ic| acc = ic.result,
        .float_const => |fc| acc = fc.result,
        .float_cast => |fc| acc = fc.result,
    }
    return acc + a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10 + a11 + a12 + a13 + a14 + a15 + a16 + a17 + a18 + a19 + a20 + a21 + a22 + a23 + a24 + a25 + a26 + a27 + a28 + a29 + a30 + a31 + a32 + a33 + a34 + a35 + a36 + a37 + a38 + a39 + a40 + a41 + a42 + a43 + a44 + a45 + a46 + a47 + a48 + a49 + a50 + a51 + a52 + a53 + a54 + a55 + a56 + a57 + a58 + a59 + a60 + a61 + a62 + a63 + a64 + a65 + a66 + a67 + a68 + a69;
}

pub fn main() void {
    var inst: Inst = .{ .int_const = .{ .value = 7, .result = 3 } };
    std.io.printInt(@intCast(i32, getResult(inst)));
}
