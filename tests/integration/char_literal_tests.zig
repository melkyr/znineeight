fn isDigit(c: u8) bool {
    return switch (c) {
        '0'...'9' => true,
        else => false,
    };
}

export fn test_entry() void {
    if (!isDigit('5')) unreachable;
    if (isDigit('a')) unreachable;
}
