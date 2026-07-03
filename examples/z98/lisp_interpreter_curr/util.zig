pub const LispError = error {
    OutOfMemory,
    UnexpectedRParen,
    UnexpectedEof,
    UnexpectedToken,
    InvalidQuote,
    InvalidIf,
    InvalidDefine,
    InvalidLambda,
    InvalidExpr,
    NotCallable,
    InvalidClosure,
    InvalidEnv,
    UnboundSymbol,
    WrongArity,
    NotACons,
    NotAnInt,
    DivisionByZero,
    InvalidParams,
    Unreachable,
    InvalidDigit,
};

pub fn mem_eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) {
        if (a[i] != b[i]) return false;
        i += 1;
    }
    return true;
}

pub fn parse_int(s: []const u8) LispError!i64 {
    var res: i64 = 0;
    var neg = false;
    var i: usize = 0;
    if (s.len > 0 and s[0] == '-') {
        neg = true;
        i = 1;
    }
    while (i < s.len) {
        if (s[i] < '0' or s[i] > '9') return error.InvalidDigit;
        res = res * 10 + @intCast(i64, s[i] - '0');
        i += 1;
    }
    if (neg) return -res;
    return res;
}

pub fn points_to_arena(ptr: *const void, sand_start: [*]u8, sand_pos: usize) bool {
    const addr = @ptrToInt(ptr);
    const start = @ptrToInt(sand_start);
    const end = start + sand_pos;
    return addr >= start and addr < end;
}
