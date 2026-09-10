// catch_ret_err_lzw_shape — the real `examples/z98/lzw/compress.zig`
// `compress()` shape: a dictionary `add()` returning an error union, called
// in a loop inside a statement-context block catch that IGNORES `Full` and
// re-propagates every other error.
//
// Pattern (compress.zig:29-36):
//     dict.add(&d, i) catch |err| {
//         if (err == E.Full) {
//             // dictionary full: stop adding, keep compressing
//         } else {
//             return err;
//         }
//     };
//
// zig0 oracle GREEN contract (RUNRC=0, byte-exact):
//   01234
extern fn putchar(c: i32) i32;

const E = error{ Full, Fail };

const Dict = struct {
    count: i32,
};

fn printDigit(n: i32) void {
    _ = putchar(48 + n);
}

fn add(self: *Dict, n: i32) E!void {
    if (n == 90) return E.Full;
    if (n == 91) return E.Fail;
    self.count += 1;
}

fn run() E!void {
    var d: Dict = Dict{ .count = 0 };
    var i: i32 = 0;
    while (i < 5) {
        add(&d, i) catch |err| {
            if (err == E.Full) {
            } else {
                return err;
            }
        };
        printDigit(i);
        i += 1;
    }
}

pub fn main() void {
    run() catch {};
    _ = putchar(10);
}
