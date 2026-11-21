const value_mod = @import("value.zig");
const token_mod = @import("token.zig");
const util = @import("util.zig");
const sand_mod = @import("sand.zig");

pub const SymbolNode = struct {
    name: []const u8,
    value: *value_mod.Value,
    next: ?*SymbolNode,
};

var global_symbol_list: ?*SymbolNode = null;

pub fn intern_symbol(name: []const u8, sand: *sand_mod.LispSand) !*value_mod.Value {
    var cur: ?*SymbolNode = global_symbol_list;
    while (cur) |node| {
        if (util.mem_eql(node.name, name)) {
            return node.value;
        }
        cur = node.next;
    }

    // Allocate name in perm_sand
    const name_mem = try sand_mod.lisp_sand_alloc(sand, name.len, 1);
    var i: usize = 0;
    while (i < name.len) {
        name_mem[i] = name[i];
        i += 1;
    }
    const name_slice = name_mem[0..name.len];

    // Allocate Value in perm_sand
    const val = try value_mod.alloc_symbol(name_slice, sand);

    // Allocate SymbolNode in perm_sand
    const node_mem = try sand_mod.lisp_sand_alloc(sand, @sizeOf(SymbolNode), @alignOf(SymbolNode));
    const node = @ptrCast(*SymbolNode, node_mem);
    node.name = name_slice;
    node.value = val;
    node.next = global_symbol_list;
    global_symbol_list = node;

    return val;
}

pub fn parse_expr(tokenizer: *token_mod.Tokenizer, perm_sand: *sand_mod.LispSand, temp_sand: *sand_mod.LispSand) !*value_mod.Value {
    const tok = try token_mod.next_token(tokenizer);
    if (tok.tag == token_mod.TokenTag.Eof) return error.UnexpectedEof;
    if (tok.tag == token_mod.TokenTag.RParen) return error.UnexpectedRParen;
    if (tok.tag == token_mod.TokenTag.LParen) return try parse_list(tokenizer, perm_sand, temp_sand);
    if (tok.tag == token_mod.TokenTag.Int) return try value_mod.alloc_int(tok.data.Int, temp_sand);
    if (tok.tag == token_mod.TokenTag.Symbol) return try intern_symbol(tok.data.Symbol, perm_sand);
    return error.UnexpectedToken;
}

fn parse_list(tokenizer: *token_mod.Tokenizer, perm_sand: *sand_mod.LispSand, temp_sand: *sand_mod.LispSand) !*value_mod.Value {
    const peeked = try token_mod.peek_token(tokenizer);
    if (peeked.tag == token_mod.TokenTag.RParen) {
        _ = try token_mod.next_token(tokenizer);
        return try intern_symbol("nil", perm_sand);
    }

    const car = try parse_expr(tokenizer, perm_sand, temp_sand);
    const cdr = try parse_list_tail(tokenizer, perm_sand, temp_sand);
    return try value_mod.alloc_cons(car, cdr, temp_sand);
}

fn parse_list_tail(tokenizer: *token_mod.Tokenizer, perm_sand: *sand_mod.LispSand, temp_sand: *sand_mod.LispSand) !*value_mod.Value {
    const peeked = try token_mod.peek_token(tokenizer);
    if (peeked.tag == token_mod.TokenTag.RParen) {
        _ = try token_mod.next_token(tokenizer);
        return try intern_symbol("nil", perm_sand);
    }

    // Check for dotted pair
    if (peeked.tag == token_mod.TokenTag.Symbol and util.mem_eql(peeked.data.Symbol, ".")) {
        _ = try token_mod.next_token(tokenizer); // consume "."
        const res = try parse_expr(tokenizer, perm_sand, temp_sand);
        const next_peek = try token_mod.peek_token(tokenizer);
        if (next_peek.tag != token_mod.TokenTag.RParen) return error.ExpectedRParen;
        _ = try token_mod.next_token(tokenizer); // consume ")"
        return res;
    }

    const car = try parse_expr(tokenizer, perm_sand, temp_sand);
    const cdr = try parse_list_tail(tokenizer, perm_sand, temp_sand);
    return try value_mod.alloc_cons(car, cdr, temp_sand);
}
