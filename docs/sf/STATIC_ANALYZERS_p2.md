> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project.

# Z98 Self-Hosted Static Analyzers

**Version:** 1.0  
**Component:** Semantic analysis passes 6–9 in the `zig1` pipeline  
**Parent Document:** DESIGN.md v3.0 (Section 7.1, passes 4–6)  
**Supersedes:** Bootstrap `SignatureAnalyzer`, `LifetimeAnalyzer`, `NullPointerAnalyzer`, `DoubleFreeAnalyzer`

---

## 1. Scope and Design Principles

### 1.1 What This Document Covers

The self-hosted compiler (`zig1`) runs a sequence of static analysis passes after type resolution and constraint checking. These passes detect memory safety issues, C89 incompatibilities, and correctness problems — producing warnings and errors without modifying the AST.

The bootstrap had four analyzers implemented as C++ visitor classes using virtual dispatch over pointer-based AST nodes. The self-hosted versions must:

| Requirement | Bootstrap Approach | Self-Hosted Approach |
|---|---|---|
| AST traversal | `ChildVisitor` virtual dispatch | Iterative DFS with `ArrayList(u32)` stack |
| State storage | Per-analyzer hash maps with `std::string` keys | Concrete `U32ToU32Map` keyed by symbol name\_id |
| Branch forking | Deep-copy state map on each branch | Delta-linked state maps (O(1) fork) |
| Memory | Unbounded `DynamicArray` growth | Pre-allocated from `scratch` arena, reset between functions |
| Error reporting | Mixed `abort()` + `ErrorHandler` | Unified `DiagnosticCollector` — never aborts |

### 1.2 Memory Budget

Static analysis runs on the `scratch` arena, which is reset between each analyzed function. The budget for all analyzers combined must stay under **512 KB per function** (to leave headroom within the 16 MB total).

Estimated per-function overhead:

| Component | Per-variable | Typical function (30 vars) | Worst case (200 vars) |
|---|---|---|---|
| State map entries | 16 bytes | 480 B | 3.2 KB |
| Delta chain nodes | 12 bytes/delta | ~1 KB (10 branches) | ~12 KB (100 branches) |
| Traversal stack | 4 bytes/node | ~2 KB | ~8 KB |
| Diagnostic messages | ~64 bytes each | ~320 B (5 warnings) | ~3.2 KB (50 warnings) |
| **Total per analyzer** | | **~4 KB** | **~26 KB** |
| **All 4 analyzers** | | **~16 KB** | **~104 KB** |

Well within the 512 KB budget even for the eval.zig `eval` function (which has ~50 local variables and deep nesting).

### 1.3 Performance Expectations

On 1998-era hardware (Pentium II 300 MHz), each analyzer pass over a function takes:
- Small function (20 nodes): < 0.1 ms
- Medium function (200 nodes): < 1 ms
- eval.zig `eval` (~800 nodes, 7-level nesting): < 5 ms

**Total analysis time for the entire compiler (~14,600 lines)**: estimated < 200 ms. If this exceeds the budget on target hardware, individual analyzers can be disabled via CLI flags (`--no-null-check`, `--no-lifetime-check`, `--no-leak-check`).

---

## 2. Shared Infrastructure

All analyzers share a common state tracking and traversal infrastructure.

### 2.1 Flow-Sensitive State Map

The core data structure for all flow-sensitive analyses is a **delta-linked state map**. This avoids deep-copying the entire state at every branch point.

```zig
pub const StateMap = struct {
    /// Each entry maps a symbol name_id to a state value (u8)
    entries: ArrayList(StateEntry),
    /// Parent map — lookups chain through parents if not found locally
    parent: ?*StateMap,
    allocator: *Allocator,

    pub const StateEntry = struct {
        name_id: u32,
        state: u8,
    };

    /// Fork: create a child map that inherits this map's state.
    /// O(1) — just sets parent pointer.
    pub fn fork(self: *StateMap, alloc: *Allocator) !*StateMap {
        var child = try alloc.create(StateMap);
        child.* = .{
            .entries = ArrayList(StateEntry).init(alloc),
            .parent = self,
            .allocator = alloc,
        };
        return child;
    }

    /// Get the state of a variable. Walks the parent chain.
    pub fn get(self: *StateMap, name_id: u32) ?u8 {
        // Check local entries first
        var i: usize = self.entries.items.len;
        while (i > 0) : (i -= 1) {
            if (self.entries.items[i - 1].name_id == name_id) {
                return self.entries.items[i - 1].state;
            }
        }
        // Check parent
        if (self.parent) |p| return p.get(name_id);
        return null;
    }

    /// Set (or override) the state of a variable. Local only.
    pub fn set(self: *StateMap, name_id: u32, state: u8) !void {
        // Check if already in local entries
        var i: usize = 0;
        while (i < self.entries.items.len) : (i += 1) {
            if (self.entries.items[i].name_id == name_id) {
                self.entries.items[i].state = state;
                return;
            }
        }
        try self.entries.append(.{ .name_id = name_id, .state = state });
    }
};
```

### 2.2 Conservative Merge

At branch join points (`if`/`else`, `switch` prongs, `catch`/`orelse`), divergent states are merged conservatively:

```zig
/// Merge two branch state maps back into the parent.
/// For any variable that differs between branches, set it to the "unknown" state.
fn mergeStates(
    parent: *StateMap,
    branch_a: *StateMap,
    branch_b: *StateMap,
    unknown_state: u8,
) !void {
    // Collect all variables modified in either branch
    var i: usize = 0;
    while (i < branch_a.entries.items.len) : (i += 1) {
        const entry = branch_a.entries.items[i];
        const other = branch_b.get(entry.name_id);
        if (other) |other_state| {
            if (other_state != entry.state) {
                try parent.set(entry.name_id, unknown_state);
            } else {
                try parent.set(entry.name_id, entry.state);
            }
        } else {
            // Modified in A only — compare with parent's original state
            const orig = parent.get(entry.name_id);
            if (orig) |orig_state| {
                if (orig_state != entry.state) {
                    try parent.set(entry.name_id, unknown_state);
                }
            }
        }
    }
    // Handle variables only modified in B
    i = 0;
    while (i < branch_b.entries.items.len) : (i += 1) {
        const entry = branch_b.entries.items[i];
        // Skip if already handled above
        if (branch_a.get(entry.name_id) != null) continue;
        const orig = parent.get(entry.name_id);
        if (orig) |orig_state| {
            if (orig_state != entry.state) {
                try parent.set(entry.name_id, unknown_state);
            } else {
                try parent.set(entry.name_id, entry.state);
            }
        }
    }
}
```

### 2.3 Iterative Function Visitor

Each analyzer implements a function-level visitor that walks the AST iteratively. The visitor dispatches on node kind and processes statements in order.

```zig
pub const AnalyzerContext = struct {
    store: *AstStore,
    symbols: *SymbolTable,
    types: *TypeRegistry,
    interner: *StringInterner,
    diag: *DiagnosticCollector,
    source_mgr: *SourceManager,
    allocator: *Allocator,       // scratch arena — reset between functions
    current_fn_name: u32,        // interned name of function being analyzed
};

/// Walk a function body's statements in order.
/// Unlike the generic pre-order visitor, this walks SEQUENTIALLY
/// through blocks (respecting control flow order) and handles
/// branches by forking/merging state.
fn walkBlock(ctx: *AnalyzerContext, state: *StateMap, block_idx: u32, handler: *Handler) !void {
    if (block_idx == 0) return;
    const node = ctx.store.nodes.items[block_idx];
    if (node.kind != .block) {
        // Single statement (braceless body) — process directly
        try handler.visitStatement(ctx, state, block_idx);
        return;
    }
    const children = ctx.store.getExtraChildren(node.payload);
    var i: usize = 0;
    while (i < children.len) : (i += 1) {
        try handler.visitStatement(ctx, state, children[i]);
    }
}
```

### 2.4 Diagnostic Severity Levels

| Code Range | Level | Category |
|---|---|---|
| 2000–2099 | Error | Definite bugs (guaranteed null deref, definite double free) |
| 6000–6099 | Warning | Potential bugs (maybe-null deref, potential leak, dangling pointer) |
| 7000–7099 | Info | Informational (C89 concern, performance note, ownership transfer) |

---

## 3. SignatureAnalyzer

### 3.1 Purpose

Validates that all function signatures are compatible with C89 code generation. Runs once per function declaration (not per call site).

### 3.2 Checks

| Check | Condition | Diagnostic |
|---|---|---|
| Void parameter | Parameter type resolves to `void` | ERR 2010: `void` not allowed as parameter type |
| Incomplete struct | Parameter/return type is an unresolved struct | ERR 2011: incomplete type in signature |
| Incomplete union | Same for unions | ERR 2011 |
| Anytype parameter | `anytype` keyword detected | ERR 2012: `anytype` not supported in Z98 |
| Large return value | Return type `sizeof > 64` | WARN 7010: large return may cause MSVC 6.0 issues |
| Opaque type | Parameter/return is opaque | ERR 2013: opaque types not supported |

### 3.3 Implementation

```zig
pub fn analyzeSignature(ctx: *AnalyzerContext, fn_node_idx: u32) !void {
    const node = ctx.store.nodes.items[fn_node_idx];
    if (node.kind != .fn_decl) return;

    const proto_idx = node.payload;
    const proto = ctx.store.fn_protos.items[proto_idx];

    // Check parameters
    const params = ctx.store.getExtraChildren(
        (@intCast(u32, proto.params_start) << 16) | @intCast(u32, proto.params_count)
    );
    var i: usize = 0;
    while (i < params.len) : (i += 1) {
        const param_node = ctx.store.nodes.items[params[i]];
        const type_node_idx = param_node.child_0;
        if (type_node_idx == 0) continue;
        try validateSignatureType(ctx, type_node_idx, "parameter");
    }

    // Check return type
    if (proto.return_type_node != 0) {
        try validateSignatureType(ctx, proto.return_type_node, "return");

        // Large return check
        const ret_type = resolveTypeFromNode(ctx, proto.return_type_node);
        if (ret_type) |tid| {
            const ty = ctx.types.types.items[tid];
            if (ty.size > 64) {
                try ctx.diag.diagnostics.append(.{
                    .level = 1, // warning
                    .file_id = 0,
                    .span_start = node.span_start,
                    .span_end = node.span_end,
                    .message = "return type exceeds 64 bytes; may cause issues on MSVC 6.0",
                });
            }
        }
    }
}
```

### 3.4 Extensibility

After self-hosting, this analyzer can be extended to validate ABI compatibility for cross-module calls, check alignment requirements for specific platforms, or enforce calling convention constraints.

---

## 4. NullPointerAnalyzer

### 4.1 Purpose

Detects definite and potential null pointer dereferences before they become runtime crashes. This is the most valuable safety analyzer for Z98 programs, especially given the heavy use of optional types and error union captures.

### 4.2 Pointer States

```zig
pub const PtrState = enum(u8) {
    uninit = 0,     // Declared but never assigned (PS_UNINIT)
    is_null = 1,    // Definitely null (assigned null or 0)
    safe = 2,       // Definitely non-null (from &x, after null check, from capture)
    maybe = 3,      // Unknown — could be null or non-null
};
```

### 4.3 State Transitions

| Event | State Before | State After | Example |
|---|---|---|---|
| `var p: *T = undefined;` | — | `uninit` | Declaration without init |
| `var p: ?*T = null;` | — | `is_null` | Init with null |
| `p = null;` | any | `is_null` | Assignment to null |
| `p = &x;` | any | `safe` | Address-of local |
| `p = alloc();` | any | `maybe` | Function call result |
| `p = try alloc();` | any | `safe` | `try` unwraps error; success = non-null |
| `if (p != null)` enter then | `maybe` | `safe` (in then block) | Null guard |
| `if (p != null)` enter else | `maybe` | `is_null` (in else block) | Inverted |
| `if (p == null)` enter then | `maybe` | `is_null` (in then block) | Null check |
| `if (opt) \|val\|` capture | — | `safe` (for `val`) | Optional unwrap capture |
| `while (opt) \|val\|` capture | — | `safe` (for `val` in body) | Loop capture |
| `x orelse y` | — | `safe` (for result) | Orelse provides fallback |
| `x catch y` | — | `safe` (for result) | Catch provides fallback |
| Branch merge (differ) | `safe`+`is_null` | `maybe` | Conservative join |
| Loop exit | modified in body | `maybe` | Loop uncertainty |
| `p.*` (deref) | `is_null` | **ERROR 2004** | Definite null deref |
| `p.*` (deref) | `uninit` | **WARN 6001** | Uninit pointer deref |
| `p.*` (deref) | `maybe` | **WARN 6002** | Potential null deref |
| `p.*` (deref) | `safe` | OK | Proven non-null |

### 4.4 Implementation Sketch

```zig
pub const NullAnalyzer = struct {
    ctx: *AnalyzerContext,
    state: *StateMap,

    pub fn analyzeFunction(self: *NullAnalyzer, fn_body: u32) !void {
        self.state = try StateMap.init(self.ctx.allocator);
        try walkBlock(self.ctx, self.state, fn_body, &self.handler);
    }

    fn visitStatement(ctx: *AnalyzerContext, state: *StateMap, stmt_idx: u32) !void {
        const node = ctx.store.nodes.items[stmt_idx];
        switch (node.kind) {
            .var_decl => try handleVarDecl(ctx, state, node, stmt_idx),
            .assign, .add_assign, .sub_assign => try handleAssign(ctx, state, node),
            .if_stmt, .if_capture => try handleIf(ctx, state, node),
            .while_stmt, .while_capture => try handleWhile(ctx, state, node),
            .for_stmt => try handleFor(ctx, state, node),
            .switch_expr => try handleSwitch(ctx, state, node),
            .return_stmt => try handleReturn(ctx, state, node),
            .defer_stmt, .errdefer_stmt => {}, // defers analyzed at scope exit
            .block => try walkBlock(ctx, state, stmt_idx, &handler),
            .expr_stmt => try analyzeExpr(ctx, state, node.child_0),
            else => {},
        }
    }

    fn handleVarDecl(ctx: *AnalyzerContext, state: *StateMap, node: AstNode, idx: u32) !void {
        const name_id = node.payload; // interned name
        const init_idx = node.child_1;

        if (init_idx == 0) {
            // No initializer — uninit
            try state.set(name_id, @enumToInt(PtrState.uninit));
            return;
        }

        // Determine initial state from initializer expression
        const init_state = try classifyExpr(ctx, state, init_idx);
        try state.set(name_id, init_state);
    }

    fn handleIf(ctx: *AnalyzerContext, state: *StateMap, node: AstNode) !void {
        const cond = node.child_0;
        const then_body = node.child_1;
        const else_body = node.child_2;

        // Analyze condition expression for side effects
        try analyzeExpr(ctx, state, cond);

        // Check for null guard pattern: if (ptr != null) or if (ptr == null)
        const guard = detectNullGuard(ctx, cond);

        // Fork state for branches
        var then_state = try state.fork(ctx.allocator);
        var else_state = try state.fork(ctx.allocator);

        // Apply guard refinement
        if (guard) |g| {
            if (g.is_not_null) {
                try then_state.set(g.name_id, @enumToInt(PtrState.safe));
                try else_state.set(g.name_id, @enumToInt(PtrState.is_null));
            } else {
                try then_state.set(g.name_id, @enumToInt(PtrState.is_null));
                try else_state.set(g.name_id, @enumToInt(PtrState.safe));
            }
        }

        // Handle optional capture: if (opt) |val|
        if (node.kind == .if_capture) {
            const capture_name_id = node.payload;
            try then_state.set(capture_name_id, @enumToInt(PtrState.safe));
        }

        // Walk branches
        try walkBlock(ctx, then_state, then_body, &handler);
        if (else_body != 0) {
            try walkBlock(ctx, else_state, else_body, &handler);
        }

        // Merge
        try mergeStates(state, then_state, else_state, @enumToInt(PtrState.maybe));
    }

    /// Classify an expression's "nullability" for state tracking
    fn classifyExpr(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) !u8 {
        if (expr_idx == 0) return @enumToInt(PtrState.uninit);
        const node = ctx.store.nodes.items[expr_idx];
        return switch (node.kind) {
            .null_literal => @enumToInt(PtrState.is_null),
            .address_of => @enumToInt(PtrState.safe),
            .try_expr => @enumToInt(PtrState.safe),  // try unwraps error → non-null
            .fn_call => @enumToInt(PtrState.maybe),   // unknown function result
            .ident_expr => state.get(node.payload) orelse @enumToInt(PtrState.maybe),
            .orelse_expr => @enumToInt(PtrState.safe), // orelse provides guaranteed fallback
            .catch_expr => @enumToInt(PtrState.safe),  // catch provides guaranteed fallback
            .int_literal => blk: {
                const val = ctx.store.int_values.items[node.payload];
                break :blk if (val == 0) @enumToInt(PtrState.is_null) else @enumToInt(PtrState.safe);
            },
            else => @enumToInt(PtrState.maybe),
        };
    }

    /// Check dereferences within an expression tree
    fn analyzeExpr(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) !void {
        if (expr_idx == 0) return;
        const node = ctx.store.nodes.items[expr_idx];

        switch (node.kind) {
            .deref => {
                // This is the critical check: expr.*
                const base_idx = node.child_0;
                const base_state = try classifyExpr(ctx, state, base_idx);
                switch (@intToEnum(PtrState, base_state)) {
                    .is_null => {
                        try ctx.diag.diagnostics.append(.{
                            .level = 0,
                            .file_id = 0,
                            .span_start = node.span_start,
                            .span_end = node.span_end,
                            .message = "definite null pointer dereference",
                        });
                    },
                    .uninit => {
                        try ctx.diag.diagnostics.append(.{
                            .level = 1,
                            .file_id = 0,
                            .span_start = node.span_start,
                            .span_end = node.span_end,
                            .message = "dereference of uninitialized pointer",
                        });
                    },
                    .maybe => {
                        try ctx.diag.diagnostics.append(.{
                            .level = 1,
                            .file_id = 0,
                            .span_start = node.span_start,
                            .span_end = node.span_end,
                            .message = "potential null pointer dereference",
                        });
                    },
                    .safe => {}, // OK
                }
            },
            .index_access => {
                // arr[i] — check that arr is non-null if it's a pointer/slice
                try analyzeExpr(ctx, state, node.child_0);
                try analyzeExpr(ctx, state, node.child_1);
            },
            .field_access => try analyzeExpr(ctx, state, node.child_0),
            .fn_call => {
                // Analyze all arguments
                const args = ctx.store.getExtraChildren(node.payload);
                var i: usize = 0;
                while (i < args.len) : (i += 1) {
                    try analyzeExpr(ctx, state, args[i]);
                }
            },
            .assign => {
                try analyzeExpr(ctx, state, node.child_1); // RHS
                // Update state of LHS if it's an identifier
                const lhs = ctx.store.nodes.items[node.child_0];
                if (lhs.kind == .ident_expr) {
                    const new_state = try classifyExpr(ctx, state, node.child_1);
                    try state.set(lhs.payload, new_state);
                }
            },
            else => {
                // Recurse into children
                if (node.child_0 != 0) try analyzeExpr(ctx, state, node.child_0);
                if (node.child_1 != 0) try analyzeExpr(ctx, state, node.child_1);
                if (node.child_2 != 0) try analyzeExpr(ctx, state, node.child_2);
            },
        }
    }
};
```

### 4.5 Null Guard Detection

The analyzer recognizes these patterns as null guards:

| Pattern | Then-branch state | Else-branch state |
|---|---|---|
| `if (p != null)` | `safe` | `is_null` |
| `if (p == null)` | `is_null` | `safe` |
| `if (p)` (where p is `?*T`) | `safe` | `is_null` |
| `if (!p)` | `is_null` | `safe` |
| `while (p != null)` | `safe` in body | `is_null` after loop |
| `while (opt) \|val\|` | `val` is `safe` | — |

```zig
const NullGuard = struct {
    name_id: u32,
    is_not_null: bool,
};

fn detectNullGuard(ctx: *AnalyzerContext, cond_idx: u32) ?NullGuard {
    const node = ctx.store.nodes.items[cond_idx];
    switch (node.kind) {
        .cmp_ne => {
            // ptr != null
            if (isNullExpr(ctx, node.child_1)) {
                if (isIdentExpr(ctx, node.child_0)) |name_id| {
                    return .{ .name_id = name_id, .is_not_null = true };
                }
            }
            if (isNullExpr(ctx, node.child_0)) {
                if (isIdentExpr(ctx, node.child_1)) |name_id| {
                    return .{ .name_id = name_id, .is_not_null = true };
                }
            }
        },
        .cmp_eq => {
            // ptr == null
            if (isNullExpr(ctx, node.child_1)) {
                if (isIdentExpr(ctx, node.child_0)) |name_id| {
                    return .{ .name_id = name_id, .is_not_null = false };
                }
            }
            if (isNullExpr(ctx, node.child_0)) {
                if (isIdentExpr(ctx, node.child_1)) |name_id| {
                    return .{ .name_id = name_id, .is_not_null = false };
                }
            }
        },
        .ident_expr => {
            // if (optional_ptr) — truthy means non-null
            return .{ .name_id = node.payload, .is_not_null = true };
        },
        .bool_not => {
            // if (!ptr) — inverted
            const inner = detectNullGuard(ctx, node.child_0);
            if (inner) |g| return .{ .name_id = g.name_id, .is_not_null = !g.is_not_null };
        },
        else => {},
    }
    return null;
}
```

---

## 5. LifetimeAnalyzer

### 5.1 Purpose

Detects dangling pointers: returning or storing the address of a stack-local variable that will be destroyed when the function returns.

### 5.2 Provenance Tracking

Each pointer variable is tracked with a **provenance** — what it points to:

```zig
pub const Provenance = enum(u8) {
    unknown = 0,      // Function call result, extern, etc. — safe to return
    local = 1,        // Points to a local variable — DANGER if returned
    param = 2,        // Points to a parameter — safe to return (value)
    param_addr = 3,   // Points to the ADDRESS of a parameter — DANGER
    global = 4,       // Points to a global — safe to return
    heap = 5,         // Arena-allocated — safe to return (within arena lifetime)
};
```

### 5.3 Analysis Rules

| Pattern | Provenance | Return OK? | Diagnostic |
|---|---|---|---|
| `return &local_var;` | `local` | NO | ERR 2020: returning address of local variable |
| `return &param;` | `param_addr` | NO | ERR 2021: returning address of parameter |
| `var p = &local; return p;` | `local` (tracked) | NO | WARN 6010: returning pointer to local via variable |
| `return param_ptr;` | `param` | YES | — (caller manages lifetime) |
| `return &global;` | `global` | YES | — |
| `return arena_alloc(...)` | `heap` | YES | — |
| `return &s.field;` | `local` (field of local) | NO | ERR 2020 |
| `return &arr[i];` | `local` (element of local) | NO | ERR 2020 |
| `return local_arr[0..5];` | `local` (slice of local) | NO | WARN 6011: returning slice of local array |

### 5.4 Origin Resolution

The analyzer resolves the "origin" of an address expression by walking through field access and indexing:

```zig
fn resolveOrigin(ctx: *AnalyzerContext, expr_idx: u32) ?u32 {
    // Returns the name_id of the base local variable, or null if not resolvable
    if (expr_idx == 0) return null;
    const node = ctx.store.nodes.items[expr_idx];
    return switch (node.kind) {
        .ident_expr => node.payload,
        .field_access => resolveOrigin(ctx, node.child_0),   // s.field → s
        .index_access => resolveOrigin(ctx, node.child_0),   // arr[i] → arr
        .deref => null,    // ptr.* — we lose provenance through dereference
        .slice_expr => resolveOrigin(ctx, node.child_0),      // arr[0..5] → arr
        else => null,
    };
}
```

### 5.5 Implementation

```zig
pub const LifetimeAnalyzer = struct {
    ctx: *AnalyzerContext,
    provenance: *StateMap,   // name_id → Provenance (as u8)

    pub fn analyzeFunction(self: *LifetimeAnalyzer, fn_node: AstNode, fn_body: u32) !void {
        self.provenance = try StateMap.init(self.ctx.allocator);

        // Register parameters as param provenance
        const proto = self.ctx.store.fn_protos.items[fn_node.payload];
        const params = self.ctx.store.getExtraChildren(
            (@intCast(u32, proto.params_start) << 16) | @intCast(u32, proto.params_count)
        );
        var i: usize = 0;
        while (i < params.len) : (i += 1) {
            const param = self.ctx.store.nodes.items[params[i]];
            try self.provenance.set(param.payload, @enumToInt(Provenance.param));
        }

        try walkBlock(self.ctx, self.provenance, fn_body, &self.handler);
    }

    fn visitStatement(ctx: *AnalyzerContext, state: *StateMap, stmt_idx: u32) !void {
        const node = ctx.store.nodes.items[stmt_idx];
        switch (node.kind) {
            .var_decl => {
                const name_id = node.payload;
                const init_idx = node.child_1;
                if (init_idx == 0) {
                    try state.set(name_id, @enumToInt(Provenance.unknown));
                    return;
                }
                const prov = classifyProvenance(ctx, state, init_idx);
                try state.set(name_id, prov);
            },
            .assign => {
                const lhs = ctx.store.nodes.items[node.child_0];
                if (lhs.kind == .ident_expr) {
                    const prov = classifyProvenance(ctx, state, node.child_1);
                    try state.set(lhs.payload, prov);
                }
            },
            .return_stmt => {
                if (node.child_0 == 0) return; // void return
                try checkReturnProvenance(ctx, state, node.child_0, node);
            },
            else => {},
        }
    }

    fn classifyProvenance(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32) u8 {
        const node = ctx.store.nodes.items[expr_idx];
        return switch (node.kind) {
            .address_of => blk: {
                const origin = resolveOrigin(ctx, node.child_0);
                if (origin) |name_id| {
                    // Check if this is a local or parameter
                    const sym = ctx.symbols.lookup(name_id);
                    if (sym) |s| {
                        if (s.kind == 0) break :blk @enumToInt(Provenance.local);   // local
                        if (s.kind == 1) break :blk @enumToInt(Provenance.param_addr); // param
                        if (s.kind == 2) break :blk @enumToInt(Provenance.global);
                    }
                }
                break :blk @enumToInt(Provenance.unknown);
            },
            .fn_call => @enumToInt(Provenance.heap), // conservative: assume heap-allocated
            .ident_expr => state.get(node.payload) orelse @enumToInt(Provenance.unknown),
            else => @enumToInt(Provenance.unknown),
        };
    }

    fn checkReturnProvenance(ctx: *AnalyzerContext, state: *StateMap, expr_idx: u32, ret_node: AstNode) !void {
        const prov = classifyProvenance(ctx, state, expr_idx);
        switch (@intToEnum(Provenance, prov)) {
            .local => {
                try ctx.diag.diagnostics.append(.{
                    .level = 0,
                    .file_id = 0,
                    .span_start = ret_node.span_start,
                    .span_end = ret_node.span_end,
                    .message = "returning pointer to local variable",
                });
            },
            .param_addr => {
                try ctx.diag.diagnostics.append(.{
                    .level = 0,
                    .file_id = 0,
                    .span_start = ret_node.span_start,
                    .span_end = ret_node.span_end,
                    .message = "returning address of function parameter",
                });
            },
            else => {},
        }
    }
};
```

### 5.6 Known Limitations (Documented for Users)

- **No alias tracking through pointer dereferences**: `*ptr = &local; return *ptr;` is not caught.
- **No field-level assignment tracking**: `s.ptr = &local;` is not tracked (would require per-field provenance maps).
- **No inter-procedural analysis**: If `store_ref(&local)` stores the reference, the leak is not caught.
- **Conservative for function results**: All function return values are assumed `heap` provenance. This avoids false positives but misses cases where a function returns a stack reference.

---

## 6. DoubleFreeAnalyzer

### 6.1 Purpose

Detects double `arena_free` calls, memory leaks (allocated but never freed), and use-after-free patterns when using the arena allocator API.

### 6.2 Allocation States

```zig
pub const AllocState = enum(u8) {
    untracked = 0,      // Not an arena allocation — skip
    allocated = 1,      // arena_alloc'd, not yet freed
    freed = 2,          // arena_free'd once
    returned_val = 3,   // Returned from function — not a leak
    transferred = 4,    // Passed to a function — ownership uncertain
    unknown = 5,        // Divergent state after branch merge
};
```

### 6.3 Analysis Rules

| Event | State Before | State After | Diagnostic |
|---|---|---|---|
| `var p = arena_alloc(a, N);` | — | `allocated` | Track allocation site |
| `var p = try arena_alloc(a, N);` | — | `allocated` | Track through `try` |
| `arena_free(a, p);` | `allocated` | `freed` | OK |
| `arena_free(a, p);` | `freed` | — | **ERR 2005**: double free |
| `arena_free(a, p);` | `untracked` | — | **WARN 6006**: free of untracked pointer |
| `p = new_alloc;` | `allocated` | `allocated` (new) | **WARN 6005**: leak (old alloc not freed) |
| `p = null;` | `allocated` | — | **WARN 6005**: leak |
| `return p;` | `allocated` | `returned_val` | OK — caller is responsible |
| `some_func(p);` | `allocated` | `transferred` | **INFO 7001**: ownership transferred |
| Scope exit | `allocated` | — | **WARN 6005**: leak at scope exit |
| Branch merge | `freed`+`allocated` | `unknown` | Conservative |
| Loop body modify | `allocated` | `unknown` | Conservative |

### 6.4 Allocation Detection

The analyzer recognizes these patterns as arena allocations:

```zig
fn isArenaAlloc(ctx: *AnalyzerContext, expr_idx: u32) bool {
    const node = ctx.store.nodes.items[expr_idx];
    switch (node.kind) {
        .fn_call => {
            const callee = ctx.store.nodes.items[node.child_0];
            if (callee.kind == .ident_expr) {
                const name = ctx.interner.get(callee.payload);
                return mem_eql(name, "arena_alloc") or
                       mem_eql(name, "arena_alloc_aligned");
            }
        },
        .try_expr => return isArenaAlloc(ctx, node.child_0),
        else => {},
    }
    return false;
}

fn isArenaFree(ctx: *AnalyzerContext, expr_idx: u32) ?u32 {
    // Returns the name_id of the pointer being freed, or null
    const node = ctx.store.nodes.items[expr_idx];
    if (node.kind != .fn_call) return null;
    const callee = ctx.store.nodes.items[node.child_0];
    if (callee.kind != .ident_expr) return null;
    const name = ctx.interner.get(callee.payload);
    if (!mem_eql(name, "arena_free")) return null;

    // Second argument is the pointer being freed
    const args = ctx.store.getExtraChildren(node.payload);
    if (args.len < 2) return null;
    const ptr_arg = ctx.store.nodes.items[args[1]];
    if (ptr_arg.kind == .ident_expr) return ptr_arg.payload;
    return null;
}
```

### 6.5 Defer Handling

The analyzer maintains a LIFO queue of deferred actions. At scope exit:

1. Execute deferred actions in reverse order.
2. For each `defer arena_free(a, p)`: transition `p` from `allocated` → `freed`.
3. For each `errdefer arena_free(a, p)`: transition ONLY if exit is via error path.

```zig
pub const DeferEntry = struct {
    kind: u8,        // 0=defer, 1=errdefer
    stmt_idx: u32,   // AST node of the deferred statement
    scope_depth: u32,
};

fn executeDeferQueue(
    ctx: *AnalyzerContext,
    state: *StateMap,
    queue: *ArrayList(DeferEntry),
    target_depth: u32,
    is_error_exit: bool,
) !void {
    var i: usize = queue.items.len;
    while (i > 0) : (i -= 1) {
        const entry = queue.items[i - 1];
        if (entry.scope_depth < target_depth) break;

        if (entry.kind == 0) {
            // Normal defer — always execute
            try processFreesInStatement(ctx, state, entry.stmt_idx);
        } else if (entry.kind == 1 and is_error_exit) {
            // Errdefer — only on error paths
            try processFreesInStatement(ctx, state, entry.stmt_idx);
        }
    }
}
```

### 6.6 Composite Name Tracking

For pointers within structs (e.g., `container.ptr`), the analyzer uses composite name\_ids. The interner creates a combined name: `intern("container") + "." + intern("ptr")` → a new interned composite string.

```zig
fn compositeNameId(interner: *StringInterner, base_id: u32, field_id: u32) u32 {
    const base_str = interner.get(base_id);
    const field_str = interner.get(field_id);
    // Build "base.field" and intern it
    var buf: [128]u8 = undefined;
    var pos: usize = 0;
    var i: usize = 0;
    while (i < base_str.len and pos < 127) : (i += 1) { buf[pos] = base_str[i]; pos += 1; }
    if (pos < 127) { buf[pos] = '.'; pos += 1; }
    i = 0;
    while (i < field_str.len and pos < 127) : (i += 1) { buf[pos] = field_str[i]; pos += 1; }
    return interner.intern(buf[0..pos]);
}
```

### 6.7 Ownership Transfer Whitelist

Certain function calls are known to NOT take ownership:

| Function | Behavior |
|---|---|
| `arena_free` | Frees the pointer (not a transfer) |
| `arena_reset` | Frees all — mark all tracked as `freed` |
| `arena_destroy` | Frees all — mark all tracked as `freed` |
| `std.debug.print` | Read-only — no transfer |
| Everything else | Conservative: mark as `transferred` |

---

## 7. Analyzer Pipeline

### 7.1 Execution Order

```
[Type Resolution complete]
    │
    ▼
[Pass 6: SignatureAnalyzer]   ── per function declaration
    │                             Validates C89 compatibility of signatures
    ▼
[Pass 7: NullPointerAnalyzer] ── per function body
    │                             Flow-sensitive null tracking
    ▼
[Pass 8: LifetimeAnalyzer]    ── per function body
    │                             Provenance tracking for dangling pointers
    ▼
[Pass 9: DoubleFreeAnalyzer]  ── per function body
    │                             Arena allocation state tracking
    ▼
[LIR Lowering]
```

### 7.2 Per-Function Reset

The `scratch` arena is reset between each function to avoid accumulation:

```zig
fn runAllAnalyzers(ctx: *AnalyzerContext, module_root: u32) !void {
    const decls = ctx.store.getExtraChildren(ctx.store.nodes.items[module_root].payload);
    var i: usize = 0;
    while (i < decls.len) : (i += 1) {
        const decl = ctx.store.nodes.items[decls[i]];
        if (decl.kind != .fn_decl) continue;
        if (decl.child_1 == 0) continue; // extern — no body

        ctx.current_fn_name = ctx.store.fn_protos.items[decl.payload].name_id;

        // Each analyzer uses scratch arena, reset between functions
        try runSignatureAnalyzer(ctx, decls[i]);
        ctx.allocator.reset();

        try runNullAnalyzer(ctx, decl.child_1);
        ctx.allocator.reset();

        try runLifetimeAnalyzer(ctx, decl, decl.child_1);
        ctx.allocator.reset();

        try runDoubleFreeAnalyzer(ctx, decl.child_1);
        ctx.allocator.reset();
    }
}
```

### 7.3 CLI Flags

| Flag | Effect |
|---|---|
| `--no-null-check` | Skip NullPointerAnalyzer |
| `--no-lifetime-check` | Skip LifetimeAnalyzer |
| `--no-leak-check` | Skip DoubleFreeAnalyzer |
| `--warn-all` | Enable all optional warnings (including INFO-level) |
| `--warn-error` | Treat all warnings as errors |

---

## 8. Diagnostic Messages Reference

### 8.1 Errors (Compilation Fails)

| Code | Analyzer | Message |
|---|---|---|
| 2004 | NullPointer | definite null pointer dereference |
| 2005 | DoubleFree | double free of pointer `'name'` |
| 2010 | Signature | `void` not allowed as parameter type |
| 2011 | Signature | incomplete type `'name'` in function signature |
| 2012 | Signature | `anytype` not supported in Z98 |
| 2013 | Signature | opaque types not supported |
| 2020 | Lifetime | returning pointer to local variable `'name'` |
| 2021 | Lifetime | returning address of function parameter `'name'` |

### 8.2 Warnings (Compilation Continues)

| Code | Analyzer | Message |
|---|---|---|
| 6001 | NullPointer | dereference of uninitialized pointer `'name'` |
| 6002 | NullPointer | potential null pointer dereference of `'name'` |
| 6005 | DoubleFree | memory leak: `'name'` not freed (allocated at `file:line`) |
| 6006 | DoubleFree | freeing untracked pointer `'name'` |
| 6010 | Lifetime | returning pointer to local via variable `'name'` |
| 6011 | Lifetime | returning slice of local array `'name'` |

### 8.3 Info (Optional)

| Code | Analyzer | Message |
|---|---|---|
| 7001 | DoubleFree | pointer `'name'` transferred to function `'fn'` — receiver responsible |
| 7010 | Signature | return type exceeds 64 bytes; may cause issues on MSVC 6.0 |

---

## 9. Extensibility

### 9.1 Adding New Analyzers

Each analyzer is a standalone function `fn(ctx: *AnalyzerContext, ...) !void`. Adding a new analyzer:

1. Define the analysis function.
2. Add it to `runAllAnalyzers` in the pipeline.
3. Add a CLI disable flag.
4. Allocate new diagnostic codes in the appropriate range.

### 9.2 Future Analyzers

| Analyzer | Purpose | Complexity | Priority |
|---|---|---|---|
| **BoundsCheckAnalyzer** | Prove array/slice accesses are within bounds at compile time | Medium | High |
| **UnusedVariableAnalyzer** | Warn on declared-but-never-read variables | Low | Medium |
| **UnreachableCodeAnalyzer** | Detect code after `return`/`break`/`unreachable` | Low | Medium |
| **ConstPropagationAnalyzer** | Detect variables that could be `const` | Low | Low |
| **OverflowAnalyzer** | Detect integer overflow in constant expressions | Medium | Low |
| **UseAfterFreeAnalyzer** | Detect reads/writes after `arena_free` | High | Post-self-hosting |
| **AliasAnalyzer** | Track pointer aliasing for more precise analysis | High | Post-self-hosting |

### 9.3 Inter-Procedural Analysis

After self-hosting, the analyzers can be extended to use function summaries — compact descriptions of a function's behavior (what it allocates, frees, returns). These summaries are computed once per function and reused at call sites:

```zig
pub const FunctionSummary = struct {
    returns_local_addr: bool,      // Returns address of a local
    frees_param_n: [8]bool,        // Frees the Nth parameter
    allocates_return: bool,        // Return value is arena-allocated
    pure: bool,                    // No side effects
};
```

This is an extension point — not needed for self-hosting, but the architecture supports it cleanly.
