extern fn __bootstrap_print_int(x: i32) void;

const E = error{ Boom };

const Tok = union(enum) {
    LParen: void,
    Int: i64,
    Sym: []const u8,
    Eof: void,
};

const Scan = struct {
    input: []const u8,
    pos: usize,
};

fn scan_sym(self: *Scan) E!Tok {
    const start = self.pos;
    while (self.pos < self.input.len and self.input[self.pos] != ' ') {
        self.pos += 1;
    }
    const s = self.input[start..self.pos];
    return Tok{ .Sym = s };
}

pub fn main() void {
    var src: []const u8 = "hello world";
    var sc: Scan = Scan{ .input = src, .pos = @intCast(usize, 0) };
    const t = scan_sym(&sc) catch {
        __bootstrap_print_int(@intCast(i32, -1));
        return;
    };
    switch (t) {
        .Sym => |name| __bootstrap_print_int(@intCast(i32, name.len)),
        .LParen => __bootstrap_print_int(@intCast(i32, 0)),
        .Int => |v| __bootstrap_print_int(@intCast(i32, v)),
        .Eof => __bootstrap_print_int(@intCast(i32, 0)),
    }
}
