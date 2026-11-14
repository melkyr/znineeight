// fnptr_opt_aggregate.zig — T5 SignatureAnalyzer surface fixture (D1 shapes).
//
// Contract (analyzer tests/analyzers runner): 0 errors, 0 warnings. A fn-ptr
// whose return is `?Aggregate` / `E!Aggregate` is accepted post-T1/T2; the
// signature rules reach the aggregate bases through the wrappers.
const Key = struct { a: u32 };
const E = error{Bad};
const Console = struct {
    read: fn (*void) ?Key,
    readE: fn (*void) E!Key,
};

fn r1(s: *void) ?Key {
    _ = s;
    return Key{ .a = 1 };
}

fn r2(s: *void) E!Key {
    _ = s;
    return Key{ .a = 2 };
}

fn take(h: fn (*void) ?Key, s: *void) ?Key {
    return h(s);
}

fn takeE(h: fn (*void) E!Key, s: *void) E!Key {
    return h(s);
}

pub fn main() void {
    var st: u8 = 0;
    var c: Console = Console{ .read = r1, .readE = r2 };
    _ = take(c.read, @ptrCast(*void, &st));
    _ = takeE(c.readE, @ptrCast(*void, &st));
}
