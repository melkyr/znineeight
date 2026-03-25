const value_mod = @import("value.zig");
const token_mod = @import("token.zig");
const sand_mod = @import("sand.zig");
const util = @import("util.zig");

pub fn parse_expr(tokens: *token_mod.Tokenizer, perm_sand: *sand_mod.Sand, temp_sand: *sand_mod.Sand) util.LispError!*value_mod.Value {
    const tok = try token_mod.next_token(tokens);
    if (tok.tag == token_mod.TokenTag.LParen) {
        return try parse_list(tokens, perm_sand, temp_sand);
    } else if (tok.tag == token_mod.TokenTag.Int) {
        return try value_mod.alloc_int(tok.data.Int, temp_sand);
    } else if (tok.tag == token_mod.TokenTag.Symbol) {
        return try value_mod.alloc_symbol(tok.data.Symbol, perm_sand);
    } else if (tok.tag == token_mod.TokenTag.RParen) {
        return error.UnexpectedRParen;
    } else if (tok.tag == token_mod.TokenTag.Eof) {
        return error.UnexpectedEof;
    } else {
        return error.UnexpectedToken;
    }
}

pub fn parse_list(tokens: *token_mod.Tokenizer, perm_sand: *sand_mod.Sand, temp_sand: *sand_mod.Sand) util.LispError!*value_mod.Value {
    const next = try token_mod.peek_token(tokens);
    if (next.tag == token_mod.TokenTag.RParen) {
        _ = try token_mod.next_token(tokens); // consume ')'
        return try value_mod.alloc_symbol("nil", perm_sand);
    } else {
        const car = try parse_expr(tokens, perm_sand, temp_sand);
        const cdr = try parse_list(tokens, perm_sand, temp_sand);
        return try value_mod.alloc_cons(car, cdr, temp_sand);
    }
}
