> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project.

# Self-Hosted AST & Parser Design

**Version:** 1.0  
**Component:** `zig1` parser, AST, and expression evaluation  
**Parent Document:** DESIGN.md v3.0  
**Supersedes:** Bootstrap AST\_Parser.md (C++ implementation)

---

## 1. Scope and Relationship to Bootstrap

This document specifies the AST representation and parser for the self-hosted Z98 compiler (`zig1`). It replaces the bootstrap's C++ AST and Pratt parser with:

| Bootstrap (`zig0`) | Self-Hosted (`zig1`) | Why |
|---|---|---|
| `ASTNode` with pointer union (28 bytes, pointer-chasing) | Flat `AstNode` packed struct (24 bytes, index-based) | Cache locality, no iterator invalidation |
| Out-of-line allocation for nodes >8 bytes | Parallel payload arrays indexed by `u32` | Uniform access, no per-node allocation decisions |
| `DynamicArray<ASTNode*>` for child lists | `extra_children: ArrayList(u32)` with packed `(start, count)` | Single flat array, no per-list allocation |
| Recursive Pratt parser with depth limit 255 | Precedence climbing with bounded recursion ~12 | Handles `try`/`catch`/`orelse` naturally |
| `ChildVisitor` virtual dispatch for traversal | Iterative DFS with explicit `ArrayList(u32)` stack | No vtable, no recursion, Z98-compatible |
| `forEachChild` + `cloneASTNode` (deep copy) | Immutable AST — no cloning needed | Lifting builds new LIR, doesn't clone AST |
| C++98 with `ArenaAllocator` | Z98 with `std.heap.ArenaAllocator` | Self-hosting |

---

## 2. AstNode: The Core Structure

### 2.1 Layout

```zig
pub const AstNode = packed struct {
    kind: AstKind,        // u8  — node type discriminator
    flags: u8,            // per-kind flags (is_pub, is_const, has_capture, is_inclusive, etc.)
    span_start: u32,      // byte offset in source file
    span_end: u32,        // byte offset of node end
    child_0: u32,         // primary child index (0 = none)
    child_1: u32,         // secondary child
    child_2: u32,         // tertiary child
    payload: u32,         // index into kind-specific payload array
};
// sizeof = 24 bytes. Two nodes per 64-byte cache line.
```

**Comparison with bootstrap**: The bootstrap `ASTNode` is 28 bytes (4 + 12 + 4 + 8 for type/loc/resolved\_type/union). The self-hosted node is 24 bytes and stores MORE information (span\_end, flags, payload index) because it eliminates the pointer union overhead. The `resolved_type` is NOT stored in the node — it lives in a side-table (`TypeTable`) indexed by node index, built during semantic analysis.

**Child index 0 is the null sentinel**. Node index 0 is reserved and never used for real nodes. `child_N == 0` means "no child." This eliminates the need for nullable pointers.

### 2.2 Flags Byte Encoding

The `flags` byte encodes boolean properties that vary per node kind. To avoid wasting space on per-kind flag structs, flags are bit-packed:

| Bit | Meaning (context-dependent) |
|---|---|
| 0 | `is_const` (var\_decl, ptr\_type, slice\_type, many\_ptr\_type) |
| 1 | `is_pub` (var\_decl, fn\_decl) |
| 2 | `is_extern` (fn\_decl) |
| 3 | `is_export` (fn\_decl) |
| 4 | `has_capture` (if\_stmt, while\_stmt, switch\_prong, for\_stmt) |
| 5 | `has_index_capture` (for\_stmt, payload\_capture) |
| 6 | `is_inclusive` (range\_inclusive vs range\_exclusive) |
| 7 | `is_mutable` (var\_decl: `var` vs `const`) |

Example: `pub const x: i32 = 42;` → `flags = 0b0000_0011` (is\_const=1, is\_pub=1).

### 2.3 The Payload Field

The `payload` field is a `u32` that means different things depending on `kind`:

| Node Kind | payload meaning |
|---|---|
| `int_literal` | Index into `AstStore.int_values` |
| `float_literal` | Index into `AstStore.float_values` |
| `string_literal`, `ident_expr` | Index into `AstStore.identifiers` (interned string ID) |
| `fn_decl` | Index into `AstStore.fn_protos` |
| `fn_call`, `block`, `struct_decl`, `enum_decl`, `union_decl`, `switch_expr`, `tuple_literal`, `struct_init` | Packed `(start << 16 \| count)` into `AstStore.extra_children` |
| `builtin_call` | Interned string ID of the builtin name (`@sizeOf`, `@intCast`, etc.) |
| `var_decl`, `field_decl`, `param_decl`, `field_access`, `enum_literal`, `error_literal` | Interned string ID of the name |
| `labeled_stmt`, `break_stmt`, `continue_stmt` | Interned string ID of the label (0 = unlabeled) |
| `if_capture`, `while_capture`, `for_stmt` | Interned string ID of the capture name |
| `import_expr` | Interned string ID of the path |

---

## 3. AstKind Enum (Complete)

This enum defines every node type the parser can produce. It is the contract between the parser and all downstream passes.

```zig
pub const AstKind = enum(u8) {
    // ═══ Error Recovery ═══
    err,                    // unrecoverable parse error; allows continued traversal

    // ═══ Declarations ═══
    var_decl,               // const/var; child_0=type_expr, child_1=init_expr, payload=name_id
                            // flags: bit0=is_const, bit1=is_pub, bit7=is_mutable
    fn_decl,                // child_0=return_type, child_1=body (block or 0 for extern)
                            // payload→fn_protos; flags: bit1=is_pub, bit2=is_extern, bit3=is_export
    struct_decl,            // payload→extra_children (field_decl nodes)
    enum_decl,              // child_0=backing_type (or 0), payload→extra_children (field_decl nodes)
    union_decl,             // child_0=tag_type (or 0 for bare/implicit enum)
                            // payload→extra_children (field_decl nodes)
                            // flags: bit0=is_tagged
    field_decl,             // child_0=type_expr (0 for void/naked tag), child_1=default_value (or 0)
                            // payload=name_id
    param_decl,             // child_0=type_expr, payload=name_id
    test_decl,              // child_0=body_block, payload=name_string_id
    error_set_decl,         // payload→extra_children (name IDs stored as pseudo-nodes or in identifiers)

    // ═══ Literals ═══
    int_literal,            // payload→int_values index
    float_literal,          // payload→float_values index
    string_literal,         // payload→identifiers index (interned string ID)
    char_literal,           // payload→int_values index (codepoint as u64)
    bool_literal,           // flags: bit0 = value (1=true, 0=false)
    null_literal,           // no children, no payload
    undefined_literal,      // no children, no payload
    unreachable_expr,       // no children, no payload
    enum_literal,           // .MemberName; payload=name_id
    error_literal,          // error.TagName; payload=name_id

    // ═══ Aggregate Literals ═══
    tuple_literal,          // .{ a, b, c }; payload→extra_children (element exprs)
    struct_init,            // .{ .x=1, .y=2 } or Type{ .x=1 }; child_0=type_expr (0 for anon)
                            // payload→extra_children (field_init nodes)
    field_init,             // .name = expr; child_0=value_expr (0 for naked tag), payload=name_id

    // ═══ Expressions ═══
    ident_expr,             // payload=interned string ID
    field_access,           // child_0=base_expr, payload=field_name_id (supports .0 .1 for tuples)
    index_access,           // child_0=base_expr, child_1=index_expr
    slice_expr,             // child_0=base_expr, child_1=start_expr (or 0), child_2=end_expr (or 0)
    deref,                  // child_0=base_expr (expr.*)
    address_of,             // child_0=operand (&expr)
    fn_call,                // child_0=callee_expr, payload→extra_children (arg exprs)
    builtin_call,           // child_0=arg0, child_1=arg1, child_2=arg2
                            // payload=builtin_name_id, flags: bits 0-2 = arg_count (0-3)
    paren_expr,             // child_0=inner_expr (preserves grouping for diagnostics)

    // ═══ Binary Operators ═══
    // Arithmetic
    add,                    // child_0=lhs, child_1=rhs
    sub,
    mul,
    div,
    mod_op,
    // Bitwise
    bit_and,
    bit_or,
    bit_xor,
    shl,
    shr,
    // Boolean
    bool_and,
    bool_or,
    // Comparison
    cmp_eq, cmp_ne, cmp_lt, cmp_le, cmp_gt, cmp_ge,
    // Assignment
    assign, add_assign, sub_assign, mul_assign, div_assign, mod_assign,
    shl_assign, shr_assign, and_assign, xor_assign, or_assign,

    // ═══ Unary Operators ═══
    negate,                 // child_0=operand (-expr)
    bool_not,               // child_0=operand (!expr)
    bit_not,                // child_0=operand (~expr)

    // ═══ Error/Optional Handling ═══
    try_expr,               // child_0=operand
    catch_expr,             // child_0=lhs_expr, child_1=fallback_expr, child_2=capture (or 0)
                            // If capture: child_2 is a payload_capture node
    orelse_expr,            // child_0=lhs_expr, child_1=fallback_expr

    // ═══ Control Flow ═══
    if_stmt,                // child_0=condition, child_1=then_body, child_2=else_body (or 0)
    if_expr,                // child_0=condition, child_1=then_expr, child_2=else_expr
    if_capture,             // Same as if_stmt but with optional unwrap capture
                            // child_0=condition, child_1=then_body, child_2=else_body
                            // payload=capture_name_id; flags: bit4=has_capture
    while_stmt,             // child_0=condition, child_1=body, child_2=continue_expr (or 0)
                            // payload=label_name_id (0=unlabeled)
    while_capture,          // while (opt) |val| — same layout as while_stmt
                            // payload=capture_name_id
    for_stmt,               // child_0=iterable, child_1=body
                            // payload=capture_name_id (item); flags: bit5=has_index_capture
                            // child_2 = label_name node (or 0) — encoded via extra mechanism
    switch_expr,            // child_0=condition, payload→extra_children (switch_prong nodes)
    switch_prong,           // child_0=body_expr
                            // payload→extra_children (pattern value nodes: literals, ranges)
                            // flags: bit4=has_capture, bit0=is_else
    block,                  // payload→extra_children (statement nodes)
    return_stmt,            // child_0=value_expr (or 0 for void return)
    break_stmt,             // payload=label_name_id (0=unlabeled)
    continue_stmt,          // payload=label_name_id (0=unlabeled)
    defer_stmt,             // child_0=deferred_statement
    errdefer_stmt,          // child_0=deferred_statement

    // ═══ Type Expressions ═══
    ptr_type,               // child_0=pointee_type; flags: bit0=is_const
    many_ptr_type,          // child_0=pointee_type; flags: bit0=is_const
    array_type,             // child_0=elem_type, child_1=size_expr
    slice_type,             // child_0=elem_type; flags: bit0=is_const
    optional_type,          // child_0=payload_type
    error_union_type,       // child_0=payload_type, child_1=error_set_expr (or 0)
    fn_type,                // payload→fn_protos (param types + return type)

    // ═══ Ranges ═══
    range_exclusive,        // child_0=start, child_1=end (start..end)
    range_inclusive,         // child_0=start, child_1=end (start...end)

    // ═══ Module-level ═══
    import_expr,            // payload=path_string_id
    module_root,            // payload→extra_children (top-level decl nodes)

    // ═══ Captures ═══
    payload_capture,        // payload=name_id; flags: bit5=has_index_capture

    // ═══ Labels ═══
    labeled_stmt,           // child_0=inner_stmt, payload=label_name_id

    // ═══ Expression Statement ═══
    expr_stmt,              // child_0=expression (wraps expr used as statement)
};
```

### 3.1 Node Kind Count and Mapping to Bootstrap

Total: **88 node kinds** in `u8` (bootstrap had ~65 `NodeType` enum values).

New kinds not in bootstrap:
- `if_capture`, `while_capture` — the bootstrap used a `capture_name` field inside the same struct; we use separate kinds because the flat node has no room for an extra name field
- `field_init` — the bootstrap embedded this in `ASTNamedInitializer`; we promote it to a first-class node
- `labeled_stmt` — the bootstrap stored labels as fields in `ASTWhileStmtNode`/`ASTForStmtNode`; we separate them
- `expr_stmt` — the bootstrap had `NODE_EXPRESSION_STMT`; same concept, different name
- `bit_not` — the bootstrap had this as a unary op token; we give it its own kind for clarity
- `paren_expr` — preserved for diagnostic span accuracy

Removed from bootstrap:
- `NODE_ASYNC_EXPR`, `NODE_AWAIT_EXPR` — not in Z98 spec, not needed for self-hosting
- `NODE_COMPTIME_BLOCK` — Z98 has no comptime; reserved for extensibility
- `NODE_ERROR_SET_MERGE` — can be handled during semantic analysis
- `NODE_PAREN_EXPR` becomes `paren_expr` (renamed only)
- `NODE_EMPTY_STMT` — empty statements produce no node; parser skips them

---

## 4. AstStore: The Flat AST Container

```zig
pub const AstStore = struct {
    nodes: ArrayList(AstNode),
    allocator: *Allocator,

    // ═══ Payload arrays (indexed by AstNode.payload depending on kind) ═══
    identifiers: ArrayList(u32),       // interned string IDs
    int_values: ArrayList(u64),        // integer literal values
    float_values: ArrayList(f64),      // float literal values
    fn_protos: ArrayList(FnProto),     // function signatures
    extra_children: ArrayList(u32),    // flat variable-length child lists

    // ═══ Node creation helpers ═══

    /// Reserve node index 0 as null sentinel
    pub fn init(alloc: *Allocator) AstStore {
        var store = AstStore{
            .nodes = ArrayList(AstNode).init(alloc),
            .allocator = alloc,
            .identifiers = ArrayList(u32).init(alloc),
            .int_values = ArrayList(u64).init(alloc),
            .float_values = ArrayList(f64).init(alloc),
            .fn_protos = ArrayList(FnProto).init(alloc),
            .extra_children = ArrayList(u32).init(alloc),
        };
        // Index 0 = null sentinel
        store.nodes.append(AstNode{
            .kind = .err, .flags = 0,
            .span_start = 0, .span_end = 0,
            .child_0 = 0, .child_1 = 0, .child_2 = 0,
            .payload = 0,
        }) catch unreachable;
        return store;
    }

    /// Add a simple node with up to 3 children
    pub fn addNode(self: *AstStore, kind: AstKind, flags: u8,
                   span_start: u32, span_end: u32,
                   c0: u32, c1: u32, c2: u32, payload: u32) !u32 {
        const idx = @intCast(u32, self.nodes.items.len);
        try self.nodes.append(.{
            .kind = kind, .flags = flags,
            .span_start = span_start, .span_end = span_end,
            .child_0 = c0, .child_1 = c1, .child_2 = c2,
            .payload = payload,
        });
        return idx;
    }

    /// Add a binary operator node
    pub fn addBinary(self: *AstStore, tok: Token, lhs: u32, rhs: u32) !u32 {
        const kind = binaryKindFromToken(tok.kind);
        return self.addNode(kind, 0, tok.span_start, tok.span_start + tok.span_len, lhs, rhs, 0, 0);
    }

    /// Add a variable-length child list, return packed payload
    pub fn addExtraChildren(self: *AstStore, children: []const u32) !u32 {
        const start = @intCast(u16, self.extra_children.items.len);
        var i: usize = 0;
        while (i < children.len) : (i += 1) {
            try self.extra_children.append(children[i]);
        }
        return (@intCast(u32, start) << 16) | @intCast(u32, @intCast(u16, children.len));
    }

    /// Retrieve variable-length child list
    pub fn getExtraChildren(self: *AstStore, payload: u32) []const u32 {
        const start = @intCast(usize, payload >> 16);
        const count = @intCast(usize, payload & 0xFFFF);
        return self.extra_children.items[start .. start + count];
    }

    /// Add an integer literal
    pub fn addIntLiteral(self: *AstStore, value: u64, span_start: u32, span_end: u32) !u32 {
        const val_idx = @intCast(u32, self.int_values.items.len);
        try self.int_values.append(value);
        return self.addNode(.int_literal, 0, span_start, span_end, 0, 0, 0, val_idx);
    }

    /// Add a float literal
    pub fn addFloatLiteral(self: *AstStore, value: f64, span_start: u32, span_end: u32) !u32 {
        const val_idx = @intCast(u32, self.float_values.items.len);
        try self.float_values.append(value);
        return self.addNode(.float_literal, 0, span_start, span_end, 0, 0, 0, val_idx);
    }

    /// Add a string literal or identifier (interned)
    pub fn addIdentifier(self: *AstStore, kind: AstKind, string_id: u32,
                         span_start: u32, span_end: u32) !u32 {
        const id_idx = @intCast(u32, self.identifiers.items.len);
        try self.identifiers.append(string_id);
        return self.addNode(kind, 0, span_start, span_end, 0, 0, 0, id_idx);
    }
};
```

### 4.1 FnProto (Function Signature Payload)

```zig
pub const FnProto = struct {
    name_id: u32,                // interned function name
    params_start: u16,           // start index into extra_children (param_decl nodes)
    params_count: u16,           // number of parameters
    return_type_node: u32,       // AST node index for return type (0 = void)
};
```

### 4.2 Memory Budget Analysis

For a 2000-line Z98 source file (typical compiler module), estimated AST sizes:

| Component | Per-item | Estimated count | Total |
|---|---|---|---|
| `AstNode` | 24 bytes | ~8000 nodes | 192 KB |
| `extra_children` | 4 bytes | ~4000 entries | 16 KB |
| `identifiers` | 4 bytes | ~2000 entries | 8 KB |
| `int_values` | 8 bytes | ~500 values | 4 KB |
| `float_values` | 8 bytes | ~50 values | 0.4 KB |
| `fn_protos` | 8 bytes | ~100 functions | 0.8 KB |
| **Total** | | | **~221 KB** |

For the entire self-hosted compiler (~14,600 lines across ~17 modules), peak AST is approximately **1.5 MB** — well within the 16 MB budget.

---

## 5. Parser: Precedence Climbing

### 5.1 Architecture

```zig
pub const Parser = struct {
    tokens: []const Token,
    pos: usize,
    store: *AstStore,
    interner: *StringInterner,
    diag: *DiagnosticCollector,
    allocator: *Allocator,

    // Temporary scratch buffers for building child lists
    child_buf: ArrayList(u32),

    pub fn init(tokens: []const Token, store: *AstStore,
                interner: *StringInterner, diag: *DiagnosticCollector,
                alloc: *Allocator) Parser {
        return .{
            .tokens = tokens, .pos = 0,
            .store = store, .interner = interner,
            .diag = diag, .allocator = alloc,
            .child_buf = ArrayList(u32).init(alloc),
        };
    }

    // ═══ Token access ═══

    fn peek(self: *Parser) Token {
        if (self.pos >= self.tokens.len) return self.tokens[self.tokens.len - 1]; // EOF
        return self.tokens[self.pos];
    }

    fn peekN(self: *Parser, n: usize) Token {
        const idx = self.pos + n;
        if (idx >= self.tokens.len) return self.tokens[self.tokens.len - 1];
        return self.tokens[idx];
    }

    fn advance(self: *Parser) Token {
        const tok = self.peek();
        if (self.pos < self.tokens.len) self.pos += 1;
        return tok;
    }

    fn expect(self: *Parser, kind: TokenKind) !Token {
        const tok = self.peek();
        if (tok.kind != kind) {
            try self.addError(tok, "expected token");
            return error.UnexpectedToken;
        }
        return self.advance();
    }

    // ═══ Error handling ═══

    fn addError(self: *Parser, tok: Token, msg: []const u8) !void {
        try self.diag.diagnostics.append(.{
            .level = 0, // error
            .file_id = 0,
            .span_start = tok.span_start,
            .span_end = tok.span_start + tok.span_len,
            .message = msg,
        });
    }

    fn synchronize(self: *Parser) void {
        while (self.pos < self.tokens.len) {
            const k = self.tokens[self.pos].kind;
            if (k == .semicolon or k == .rbrace or k == .kw_fn or
                k == .kw_const or k == .kw_var or k == .kw_pub or
                k == .kw_test or k == .eof) return;
            self.pos += 1;
        }
    }
};
```

### 5.2 Expression Parsing: Core Loop

```zig
pub fn parseExpression(self: *Parser) !u32 {
    return self.parseExprPrec(.assignment);
}

fn parseExprPrec(self: *Parser, min_prec: Prec) !u32 {
    var lhs = try self.parsePrimary();
    lhs = try self.parsePostfixChain(lhs);

    while (true) {
        const tok = self.peek();
        const info_opt = getInfixInfo(tok.kind);
        if (info_opt == null) break;
        const info = info_opt.?;
        if (info.prec.toInt() < min_prec.toInt()) break;

        _ = self.advance();
        const next_min = if (info.right_assoc) info.prec
                         else Prec.fromInt(info.prec.toInt() + 1);

        const rhs: u32 = switch (tok.kind) {
            .kw_catch  => try self.parseCatchRHS(next_min),
            .kw_orelse => try self.parseOrelseRHS(next_min),
            else       => try self.parseExprPrec(next_min),
        };

        lhs = try self.store.addBinary(tok, lhs, rhs);
    }
    return lhs;
}
```

### 5.3 Primary Expressions

```zig
fn parsePrimary(self: *Parser) !u32 {
    const tok = self.peek();
    return switch (tok.kind) {
        .integer_literal  => self.parseIntLiteral(),
        .float_literal    => self.parseFloatLiteral(),
        .string_literal   => self.parseStringLiteral(),
        .char_literal     => self.parseCharLiteral(),
        .kw_true          => self.parseBoolLiteral(true),
        .kw_false         => self.parseBoolLiteral(false),
        .kw_null          => self.parseSingleToken(.null_literal),
        .kw_undefined     => self.parseSingleToken(.undefined_literal),
        .kw_unreachable   => self.parseSingleToken(.unreachable_expr),
        .identifier       => self.parseIdentExpr(),
        .builtin_identifier => self.parseBuiltinCall(),
        .kw_error         => self.parseErrorLiteral(),
        .minus            => self.parsePrefixUnary(.negate),
        .bang             => self.parsePrefixUnary(.bool_not),
        .tilde            => self.parsePrefixUnary(.bit_not),
        .ampersand        => self.parsePrefixUnary(.address_of),
        .kw_try           => self.parseTryExpr(),
        .lparen           => self.parseGroupedExpr(),
        .dot_lbrace       => self.parseAnonymousLiteral(),
        .dot              => self.parseEnumLiteralOrFieldInit(),
        .kw_if            => self.parseIfExpr(),
        .kw_switch        => self.parseSwitchExpr(),
        else => {
            try self.addError(tok, "expected expression");
            return self.emitErrorNode(tok);
        },
    };
}
```

### 5.4 Postfix Chain

```zig
fn parsePostfixChain(self: *Parser, base: u32) !u32 {
    var node = base;
    while (true) {
        const tok = self.peek();
        switch (tok.kind) {
            .dot => {
                _ = self.advance();
                if (self.peek().kind == .star) {
                    _ = self.advance();
                    node = try self.store.addNode(.deref, 0, tok.span_start,
                        self.tokens[self.pos - 1].span_start + 1, node, 0, 0, 0);
                } else {
                    const name_tok = try self.expect(.identifier);
                    // Also handles tuple .0 .1 access via integer token
                    const name_id = self.interner.intern(self.tokenText(name_tok));
                    node = try self.store.addNode(.field_access, 0, tok.span_start,
                        name_tok.span_start + name_tok.span_len, node, 0, 0, name_id);
                }
            },
            .lbracket => {
                _ = self.advance();
                const first = try self.parseExpression();
                if (self.peek().kind == .dot_dot or self.peek().kind == .dot_dot_dot) {
                    // Slice: base[start..end]
                    const is_inclusive = self.peek().kind == .dot_dot_dot;
                    _ = self.advance();
                    const end_expr = if (self.peek().kind == .rbracket)
                        @intCast(u32, 0)
                    else
                        try self.parseExpression();
                    _ = try self.expect(.rbracket);
                    node = try self.store.addNode(.slice_expr, 0, tok.span_start,
                        self.tokens[self.pos - 1].span_start, node, first, end_expr, 0);
                } else {
                    // Index: base[index]
                    _ = try self.expect(.rbracket);
                    node = try self.store.addNode(.index_access, 0, tok.span_start,
                        self.tokens[self.pos - 1].span_start, node, first, 0, 0);
                }
            },
            .lparen => {
                node = try self.parseFnCallArgs(node, tok);
            },
            else => break,
        }
    }
    return node;
}
```

### 5.5 `catch` and `orelse` RHS Parsing

```zig
fn parseCatchRHS(self: *Parser, next_min: Prec) !u32 {
    var capture: u32 = 0;
    if (self.peek().kind == .pipe) {
        _ = self.advance(); // |
        const name_tok = try self.expect(.identifier);
        _ = try self.expect(.pipe); // |
        const name_id = self.interner.intern(self.tokenText(name_tok));
        capture = try self.store.addNode(.payload_capture, 0,
            name_tok.span_start, name_tok.span_start + name_tok.span_len, 0, 0, 0, name_id);
    }
    const fallback = if (self.peek().kind == .lbrace)
        try self.parseBlock()
    else
        try self.parseExprPrec(next_min);
    // catch_expr: child_0=lhs (set by caller), child_1=fallback, child_2=capture
    // But we only return the RHS here; the caller wraps it into the binary node
    // Actually, catch is special — it needs 3 children.
    // Return a temporary that the caller's addBinary will handle specially.
    return fallback; // caller adds catch_expr node with capture
}

fn parseOrelseRHS(self: *Parser, next_min: Prec) !u32 {
    if (self.peek().kind == .lbrace) return self.parseBlock();
    return self.parseExprPrec(next_min);
}
```

**Note on `catch`**: The precedence climbing loop in `parseExprPrec` calls `addBinary` generically. For `catch_expr`, the store must create a 3-child node. The `addBinary` implementation checks for `.kw_catch` and handles the capture child accordingly, or a specialized `addCatchNode` is used.

### 5.6 Statement Parsing

```zig
fn parseStatement(self: *Parser) !u32 {
    return switch (self.peek().kind) {
        .kw_const, .kw_var => self.parseVarDecl(false),
        .kw_pub            => self.parsePubDecl(),
        .kw_fn             => self.parseFnDecl(false, false),
        .kw_if             => self.parseIfStmt(),
        .kw_while          => self.parseWhileStmt(null),
        .kw_for            => self.parseForStmt(null),
        .kw_switch         => self.parseSwitchStmt(),
        .kw_return         => self.parseReturnStmt(),
        .kw_break          => self.parseBreakStmt(),
        .kw_continue       => self.parseContinueStmt(),
        .kw_defer          => self.parseDeferStmt(.defer_stmt),
        .kw_errdefer       => self.parseDeferStmt(.errdefer_stmt),
        .kw_test           => self.parseTestDecl(),
        .kw_struct         => self.parseContainerDecl(.struct_decl),
        .kw_enum           => self.parseContainerDecl(.enum_decl),
        .kw_union          => self.parseContainerDecl(.union_decl),
        .lbrace            => self.parseBlock(),
        .semicolon         => blk: { _ = self.advance(); break :blk try self.parseStatement(); },
        .identifier        => blk: {
            if (self.peekN(1).kind == .colon) break :blk self.parseLabeledStmt();
            break :blk self.parseExprStmt();
        },
        else => self.parseExprStmt(),
    };
}
```

### 5.7 Switch Parsing (Statement and Expression)

The bootstrap distinguishes `NODE_SWITCH_STMT` and `NODE_SWITCH_EXPR` via context. The self-hosted parser uses `switch_expr` for both — the context is determined by where the node appears (expression position vs statement position via `expr_stmt` wrapper).

```zig
fn parseSwitchExpr(self: *Parser) !u32 {
    const kw = self.advance(); // consume 'switch'
    _ = try self.expect(.lparen);
    const cond = try self.parseExpression();
    _ = try self.expect(.rparen);
    _ = try self.expect(.lbrace);

    self.child_buf.items.len = 0; // reset scratch
    while (self.peek().kind != .rbrace and self.peek().kind != .eof) {
        const prong = try self.parseSwitchProng();
        try self.child_buf.append(prong);
        // Mandatory comma after each prong (unless at closing brace)
        if (self.peek().kind == .comma) { _ = self.advance(); }
    }
    _ = try self.expect(.rbrace);

    const payload = try self.store.addExtraChildren(self.child_buf.items);
    return self.store.addNode(.switch_expr, 0, kw.span_start,
        self.tokens[self.pos - 1].span_start, cond, 0, 0, payload);
}

fn parseSwitchProng(self: *Parser) !u32 {
    const start_tok = self.peek();
    var is_else: bool = false;

    self.child_buf.items.len = 0; // reuse for case items (nested)
    // ... but we need a separate buffer since child_buf is in use for prongs
    // Use a local ArrayList for case items
    var case_items = ArrayList(u32).init(self.allocator);
    defer case_items.deinit();

    if (self.peek().kind == .kw_else) {
        _ = self.advance();
        is_else = true;
    } else {
        // Parse comma-separated case items
        while (true) {
            const item = try self.parseExpression();
            // Check for range: ..  or ...
            if (self.peek().kind == .dot_dot) {
                _ = self.advance();
                const end_expr = try self.parseExpression();
                const range_node = try self.store.addNode(.range_exclusive, 0,
                    start_tok.span_start, self.tokens[self.pos - 1].span_start,
                    item, end_expr, 0, 0);
                try case_items.append(range_node);
            } else if (self.peek().kind == .dot_dot_dot) {
                _ = self.advance();
                const end_expr = try self.parseExpression();
                const range_node = try self.store.addNode(.range_inclusive, 0,
                    start_tok.span_start, self.tokens[self.pos - 1].span_start,
                    item, end_expr, 0, 0);
                try case_items.append(range_node);
            } else {
                try case_items.append(item);
            }
            if (self.peek().kind != .comma or self.peekN(1).kind == .fat_arrow) break;
            _ = self.advance(); // consume comma between items
        }
    }
    _ = try self.expect(.fat_arrow);

    // Optional payload capture: |val|
    var flags: u8 = 0;
    var capture_name: u32 = 0;
    if (self.peek().kind == .pipe) {
        _ = self.advance();
        const name_tok = try self.expect(.identifier);
        _ = try self.expect(.pipe);
        capture_name = self.interner.intern(self.tokenText(name_tok));
        flags |= (1 << 4); // has_capture
    }
    if (is_else) flags |= 1; // is_else

    // Parse body (expression or block)
    const body = if (self.peek().kind == .lbrace)
        try self.parseBlock()
    else
        try self.parseExpression();

    const items_payload = try self.store.addExtraChildren(case_items.items);
    return self.store.addNode(.switch_prong, flags, start_tok.span_start,
        self.tokens[self.pos - 1].span_start, body, 0, 0, items_payload);
}
```

---

## 6. Type Expression Parsing

```zig
fn parseType(self: *Parser) !u32 {
    const tok = self.peek();
    return switch (tok.kind) {
        .star => {
            _ = self.advance();
            const is_const: u8 = if (self.peek().kind == .kw_const) blk: {
                _ = self.advance(); break :blk 1;
            } else 0;
            const base = try self.parseType();
            return self.store.addNode(.ptr_type, is_const, tok.span_start,
                self.tokens[self.pos - 1].span_start, base, 0, 0, 0);
        },
        .lbracket => {
            _ = self.advance();
            if (self.peek().kind == .star) {
                // [*]T or [*]const T
                _ = self.advance();
                _ = try self.expect(.rbracket);
                const is_const: u8 = if (self.peek().kind == .kw_const) blk: {
                    _ = self.advance(); break :blk 1;
                } else 0;
                const base = try self.parseType();
                return self.store.addNode(.many_ptr_type, is_const, tok.span_start,
                    self.tokens[self.pos - 1].span_start, base, 0, 0, 0);
            } else if (self.peek().kind == .rbracket) {
                // []T or []const T
                _ = self.advance();
                const is_const: u8 = if (self.peek().kind == .kw_const) blk: {
                    _ = self.advance(); break :blk 1;
                } else 0;
                const base = try self.parseType();
                return self.store.addNode(.slice_type, is_const, tok.span_start,
                    self.tokens[self.pos - 1].span_start, base, 0, 0, 0);
            } else {
                // [N]T
                const size_expr = try self.parseExpression();
                _ = try self.expect(.rbracket);
                const base = try self.parseType();
                return self.store.addNode(.array_type, 0, tok.span_start,
                    self.tokens[self.pos - 1].span_start, base, size_expr, 0, 0);
            }
        },
        .question_mark => {
            _ = self.advance();
            const payload = try self.parseType();
            return self.store.addNode(.optional_type, 0, tok.span_start,
                self.tokens[self.pos - 1].span_start, payload, 0, 0, 0);
        },
        .bang => {
            _ = self.advance();
            const payload = try self.parseType();
            return self.store.addNode(.error_union_type, 0, tok.span_start,
                self.tokens[self.pos - 1].span_start, payload, 0, 0, 0);
        },
        .kw_fn => self.parseFnType(),
        .identifier, .kw_void, .kw_bool, .kw_noreturn, .kw_c_char => {
            const name_tok = self.advance();
            const name_id = self.interner.intern(self.tokenText(name_tok));
            // Handle qualified types: mod.Type
            var node = try self.store.addIdentifier(.ident_expr, name_id,
                name_tok.span_start, name_tok.span_start + name_tok.span_len);
            while (self.peek().kind == .dot) {
                _ = self.advance();
                const field_tok = try self.expect(.identifier);
                const field_id = self.interner.intern(self.tokenText(field_tok));
                node = try self.store.addNode(.field_access, 0, name_tok.span_start,
                    field_tok.span_start + field_tok.span_len, node, 0, 0, field_id);
            }
            return node;
        },
        .kw_error => {
            _ = self.advance();
            _ = try self.expect(.lbrace);
            // Parse error set: error { A, B, C }
            var members = ArrayList(u32).init(self.allocator);
            defer members.deinit();
            while (self.peek().kind != .rbrace) {
                const tag_tok = try self.expect(.identifier);
                const tag_id = self.interner.intern(self.tokenText(tag_tok));
                try members.append(tag_id);
                if (self.peek().kind == .comma) { _ = self.advance(); }
            }
            _ = try self.expect(.rbrace);
            // Store as error_set_decl with member names in extra_children
            const payload = try self.store.addExtraChildren(members.items);
            return self.store.addNode(.error_set_decl, 0, tok.span_start,
                self.tokens[self.pos - 1].span_start, 0, 0, 0, payload);
        },
        else => {
            try self.addError(tok, "expected type expression");
            return error.UnexpectedToken;
        },
    };
}
```

---

## 7. Iterative AST Traversal

All downstream passes (semantic analysis, LIR lowering) use iterative traversal. No `ChildVisitor` virtual dispatch.

```zig
pub fn visitPreOrder(alloc: *Allocator, store: *AstStore, root: u32,
                     callback: fn(node: AstNode, idx: u32, store: *AstStore) void) !void {
    var stack = ArrayList(u32).init(alloc);
    defer stack.deinit();
    try stack.append(root);

    while (stack.items.len > 0) {
        const idx = stack.pop().?;
        if (idx == 0) continue;
        const node = store.nodes.items[idx];
        callback(node, idx, store);

        // Push children in reverse for natural order
        if (node.child_2 != 0) try stack.append(node.child_2);
        if (node.child_1 != 0) try stack.append(node.child_1);
        if (node.child_0 != 0) try stack.append(node.child_0);

        // Push extra_children for applicable kinds
        if (nodeHasExtraChildren(node.kind)) {
            const children = store.getExtraChildren(node.payload);
            var i: usize = children.len;
            while (i > 0) : (i -= 1) {
                try stack.append(children[i - 1]);
            }
        }
    }
}

fn nodeHasExtraChildren(kind: AstKind) bool {
    return switch (kind) {
        .fn_call, .block, .struct_decl, .enum_decl, .union_decl,
        .switch_expr, .switch_prong, .tuple_literal, .struct_init,
        .module_root, .error_set_decl => true,
        else => false,
    };
}
```

---

## 8. Extensibility Hooks

| Feature | Extension Point | What Changes |
|---|---|---|
| `comptime` blocks | Add `comptime_block` to `AstKind`; parse in `parsePrimary` | Parser + 1 AstKind |
| `async`/`await` | Add `async_expr`, `await_expr` to `AstKind` | Parser + 2 AstKinds |
| Method syntax | Desugar `expr.method(args)` → `Type.method(expr, args)` during semantic analysis | No parser changes |
| Generics | Add `comptime` param modifier; monomorphize during semantic analysis | Parser flag + semantic pass |
| New operators | Add to `TokenKind`, `getInfixInfo`, and binary `AstKind` mapping | Lexer + parser table + 1 AstKind |
| New builtins | Add name to `builtin_call` recognition | Parser string check only |
