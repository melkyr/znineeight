// surface_types.zig — T5 SignatureAnalyzer current-surface fixture.
//
// Contract (analyzer tests/analyzers runner): 0 errors, 0 warnings. Covers
// arbitrary-width ints (`i7`/`u48`/`i3` — the parseArbIntWidth family),
// packed-union types, and tagged-union `.tag` member access in live code.
const PU = packed union { a: u8, b: i8 };
const TU = union(enum) { char: u8, sigint };

fn f1(x: i7, y: u48) i3 {
    _ = x;
    _ = y;
    return 1;
}

fn f2() u33 {
    return 2;
}

fn fpu(u: PU) PU {
    return u;
}

fn ftu(u: TU) u8 {
    var n: u8 = 0;
    switch (u.tag) {
        .char => {
            n = 1;
        },
        .sigint => {
            n = 2;
        },
    }
    return n;
}

pub fn main() void {
    _ = f1(1, 2);
    _ = f2();
    var u: PU = PU{ .a = 3 };
    _ = fpu(u);
    var t: TU = TU{ .sigint = {} };
    _ = ftu(t);
}
