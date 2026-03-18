const value_mod = @import("value.zig");
const token_mod = @import("token.zig");
const util = @import("util.zig");

pub const SymbolNode = struct {
    name: []const u8,
    value: *value_mod.Value,
    next: ?*SymbolNode,
};

var global_symbol_list: ?*SymbolNode = null;

pub fn intern_symbol(name: []const u8, arena: *value_mod.arena_mod.Arena) !*value_mod.Value {
    var cur = global_symbol_list;
    while (cur != null) {
        const node = @ptrCast(*SymbolNode, cur);
        if (util.mem_eql(node.name, name)) {
            return node.value;
        }
        cur = node.next;
    }

    // Allocate name in perm_arena
    const name_mem = try value_mod.arena_mod.arena_alloc(arena, name.len, 1);
    var i: usize = 0;
    while (i < name.len) {
        name_mem[i] = name[i];
        i += 1;
    }
    const name_slice = name_mem[0..name.len];

    // Allocate Value in perm_arena
    const val = try value_mod.alloc_symbol(name_slice, arena);

    // Allocate SymbolNode in perm_arena
    const node_mem = try value_mod.arena_mod.arena_alloc(arena, @sizeOf(SymbolNode), @alignOf(SymbolNode));
    const node = @ptrCast(*SymbolNode, node_mem);
    node.name = name_slice;
    node.value = val;
    node.next = global_symbol_list;
    global_symbol_list = node;

    return val;
}

pub fn parse_expr(tokenizer: *token_mod.Tokenizer, perm_arena: *value_mod.arena_mod.Arena, temp_arena: *value_mod.arena_mod.Arena) !*value_mod.Value {
    const tok = try tokenizer.next_token();
    if (tok.tag == token_mod.TokenTag.Eof) return error.UnexpectedEof;
    if (tok.tag == token_mod.TokenTag.RParen) return error.UnexpectedRParen;
    if (tok.tag == token_mod.TokenTag.LParen) return try parse_list(tokenizer, perm_arena, temp_arena);
    if (tok.tag == token_mod.TokenTag.Int) return try value_mod.alloc_int(tok.data.Int, temp_arena);
    if (tok.tag == token_mod.TokenTag.Symbol) return try intern_symbol(tok.data.Symbol, perm_arena);
    return error.UnexpectedToken;
}

fn parse_list(tokenizer: *token_mod.Tokenizer, perm_arena: *value_mod.arena_mod.Arena, temp_arena: *value_mod.Arena) !*value_mod.Value {
    const peeked = try tokenizer.peek_token();
    if (peeked.tag == token_mod.TokenTag.RParen) {
        _ = try tokenizer.next_token();
        return try intern_symbol("nil", perm_arena);
    }

    const car = try parse_expr(tokenizer, perm_arena, temp_arena);
    const cdr = try parse_list_tail(tokenizer, perm_arena, temp_arena);
    return try value_mod.alloc_cons(car, cdr, temp_arena);
}

fn parse_list_tail(tokenizer: *token_mod.Tokenizer, perm_arena: *value_mod.arena_mod.Arena, temp_arena: *value_mod.arena_mod.Arena) !*value_mod.Value {
    const peeked = try tokenizer.peek_token();
    if (peeked.tag == token_mod.TokenTag.RParen) {
        _ = try tokenizer.next_token();
        return try intern_symbol("nil", perm_arena);
    }

    // Check for dotted pair
    if (peeked.tag == token_mod.TokenTag.Symbol and util.mem_eql(peeked.data.Symbol, ".")) {
        _ = try tokenizer.next_token(); // consume "."
        const res = try parse_expr(tokenizer, perm_arena, temp_arena);
        const next_peek = try tokenizer.peek_token();
        if (next_peek.tag != token_mod.TokenTag.RParen) return error.ExpectedRParen;
        _ = try tokenizer.next_token(); // consume ")"
        return res;
    }

    const car = try parse_expr(tokenizer, perm_arena, temp_arena);
    const cdr = try parse_list_tail(tokenizer, perm_arena, temp_arena);
    return try value_mod.alloc_cons(car, cdr, temp_arena);
}
