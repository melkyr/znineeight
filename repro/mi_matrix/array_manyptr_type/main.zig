extern fn __bootstrap_print(s: [*]const u8) void;

pub fn main() void {
    var a: [*]const u8 = "aa";
    var b: [*]const u8 = "bb";
    var c: [*]const u8 = "cc";
    var d: [*]const u8 = "dd";
    var words = [4][*]const u8{ a, b, c, d };
    __bootstrap_print(words[0]); // expect "aa" once fixed
}
