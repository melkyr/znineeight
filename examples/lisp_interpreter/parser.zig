const value_mod = @import("value.zig");
const token_mod = @import("token.zig");
const util = @import("util.zig");

pub const SymbolNode = struct {
    name: []const u8,
    value: *value_mod.Value,
    next: ?*SymbolNode,
};

var global_symbol_list: ?*SymbolNode = null;

pub fn intern_symbol(name: []const u8, arena: *value_mod.arena_mod.LispArena) !*value_mod.Value {
    var cur = global_symbol_list;
    while (cur) |node| {
        if (util.mem_eql(node.name, name)) {
            return node.value;
        }
        cur = @ptrCast(?*SymbolNode, node.next);
    }

    // Allocate name in perm_arena
    const name_mem = try value_mod.arena_mod.lisp_alloc(arena, name.len, 1);
    var i: usize = 0;
    while (i < name.len) {
        name_mem[i] = name[i];
        i += 1;
    }
    const name_slice = name_mem[0..name.len];

    // Allocate Value in perm_arena
    const val = try value_mod.alloc_symbol(name_slice, arena);

    // Allocate SymbolNode in perm_arena
    const node_mem = try value_mod.arena_mod.lisp_alloc(arena, @sizeOf(SymbolNode), @alignOf(SymbolNode));
    const node = @ptrCast(*SymbolNode, node_mem);
    node.name = name_slice;
    node.value = val;
    node.next = global_symbol_list;
    global_symbol_list = node;

    return val;
}

pub fn parse_expr(tokenizer: *token_mod.Tokenizer, perm_arena: *value_mod.arena_mod.LispArena, temp_arena: *value_mod.arena_mod.LispArena) !*value_mod.Value {
    const tok = try token_mod.next_token(tokenizer);
    if (tok.tag == token_mod.TokenTag.Eof) return error.UnexpectedEof;
    if (tok.tag == token_mod.TokenTag.RParen) return error.UnexpectedRParen;
    if (tok.tag == token_mod.TokenTag.LParen) return try parse_list(tokenizer, perm_arena, temp_arena);
    if (tok.tag == token_mod.TokenTag.Int) return try value_mod.alloc_int(tok.data.Int, temp_arena);
    if (tok.tag == token_mod.TokenTag.Symbol) return try intern_symbol(tok.data.Symbol, perm_arena);
    return error.UnexpectedToken;
}

fn parse_list(tokenizer: *token_mod.Tokenizer, perm_arena: *value_mod.arena_mod.LispArena, temp_arena: *value_mod.arena_mod.LispArena) !*value_mod.Value {
    const peeked = try token_mod.peek_token(tokenizer);
    if (peeked.tag == token_mod.TokenTag.RParen) {
        _ = try token_mod.next_token(tokenizer);
        return try intern_symbol("nil", perm_arena);
    }

    const car = try parse_expr(tokenizer, perm_arena, temp_arena);
    const cdr = try parse_list_tail(tokenizer, perm_arena, temp_arena);
    return try value_mod.alloc_cons(car, cdr, temp_arena);
}

fn parse_list_tail(tokenizer: *token_mod.Tokenizer, perm_arena: *value_mod.arena_mod.LispArena, temp_arena: *value_mod.arena_mod.LispArena) !*value_mod.Value {
    const peeked = try token_mod.peek_token(tokenizer);
    if (peeked.tag == token_mod.TokenTag.RParen) {
        _ = try token_mod.next_token(tokenizer);
        return try intern_symbol("nil", perm_arena);
    }

    // Check for dotted pair
    if (peeked.tag == token_mod.TokenTag.Symbol and util.mem_eql(peeked.data.Symbol, ".")) {
        _ = try token_mod.next_token(tokenizer); // consume "."
        const res = try parse_expr(tokenizer, perm_arena, temp_arena);
        const next_peek = try token_mod.peek_token(tokenizer);
        if (next_peek.tag != token_mod.TokenTag.RParen) return error.ExpectedRParen;
        _ = try token_mod.next_token(tokenizer); // consume ")"
        return res;
    }

    const car = try parse_expr(tokenizer, perm_arena, temp_arena);
    const cdr = try parse_list_tail(tokenizer, perm_arena, temp_arena);
    return try value_mod.alloc_cons(car, cdr, temp_arena);
}
