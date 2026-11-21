const value_mod = @import("value.zig");
const token_mod = @import("token.zig");
const sand_mod = @import("sand.zig");
const util = @import("util.zig");

pub fn parse_expr(tokens: *token_mod.Tokenizer, perm_sand: *sand_mod.Sand, temp_sand: *sand_mod.Sand) util.LispError!*value_mod.Value {
    const tok = try token_mod.next_token(tokens);
    switch (tok) {
        .LParen => return try parse_list(tokens, perm_sand, temp_sand),
        .Int => |val| return try value_mod.alloc_int(val, temp_sand),
        .Symbol => |name| {
            // Intern symbols in perm_sand
            // For now, we'll just allocate them. Real interning would use a hash table.
            return try value_mod.alloc_symbol(name, perm_sand);
        },
        .RParen => return error.UnexpectedRParen,
        .Eof => return error.UnexpectedEof,
        else => return error.UnexpectedToken,
    }
}

pub fn parse_list(tokens: *token_mod.Tokenizer, perm_sand: *sand_mod.Sand, temp_sand: *sand_mod.Sand) util.LispError!*value_mod.Value {
    const next = try token_mod.peek_token(tokens);
    switch (next) {
        .RParen => {
            _ = try token_mod.next_token(tokens); // consume ')'
            return try value_mod.alloc_symbol("nil", perm_sand);
        },
        else => {
            const car = try parse_expr(tokens, perm_sand, temp_sand);
            const cdr = try parse_list(tokens, perm_sand, temp_sand);
            return try value_mod.alloc_cons(car, cdr, temp_sand);
        },
    }
}
