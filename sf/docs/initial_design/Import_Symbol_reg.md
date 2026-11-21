# Import Resolution & Symbol Registration Design Specification

**Version:** 1.1 (Enriched)  
**Component:** Module discovery, on‑demand parsing, topological import resolution, top‑level symbol registration, type stub creation  
**Parent Document:** `DESIGN.md v3.0` (Sections 2.2–2.3, 4, 6.2–6.4, 7.1–7.2), `TYPE_SYSTEM.md` (Sections 2.4, 3.1, 6.1), `AST_PARSER.md` (Sections 5.3, 5.6)  
**Supersedes:** Bootstrap ad‑hoc global symbol table + linear import scanning

---

## 0. Scope & Philosophy

This document specifies **Pipeline Steps 2 & 3**: Import Resolution and Symbol Registration. It replaces the bootstrap's monolithic, globally‑scoped symbol collection with a deterministic, per‑module architecture that:

- Discovers imports on‑demand during parsing
- Builds a directed module dependency graph
- Topologically sorts modules via Kahn's algorithm
- Registers top‑level symbols in isolated per‑module tables
- Creates immutable `unresolved_name` type stubs for forward references
- Constructs the type dependency graph for Kahn's layout resolution

**Core Principles:**

1. **Strict Phase Separation:** Import discovery happens during parsing. Module ordering happens after all parsing completes. Symbol registration happens in topological order. No phase mutates AST or resolves types yet.
2. **Deterministic Discovery:** Import paths are resolved, sorted, and assigned sequential `ModuleId`s. No hash‑iteration leakage; no filesystem‑order dependence.
3. **Per‑Module Isolation:** Each module owns its `SymbolTable` (global scope only). Cross‑module references are resolved via module ID + symbol lookup during later passes.
4. **Memory‑Bounded Parsing:** Each module uses its own `module` arena. Token arena is reset after parsing. AST and symbol tables persist until post‑emission.
5. **Recovery Over Crash:** Missing files, circular imports, and duplicate symbols produce structured diagnostics. Failed modules are skipped; compilation continues to collect maximum errors.

---

## 1. Module Graph & Data Structures

The module registry lives in the `permanent` arena and tracks all parsed/queued modules.

```zig
pub const ModuleState = enum(u8) {
    pending,      // discovered, not yet parsed
    parsing,      // currently being lexed/parsed
    parsed,       // AST built, imports collected
    resolved,     // topologically ordered, ready for symbol registration
    failed,       // missing file, syntax error, or import cycle
};

pub const ModuleEntry = struct {
    id: u32,                          // sequential assignment (0 = entry module)
    path_id: u32,                     // interned source path (absolute, normalized)
    state: ModuleState,
    ast_root: u32,                    // index of module_root node (0 if failed)
    import_count: u32,
    imports_start: u32,               // index into ModuleRegistry.import_edges
    symbol_table: *SymbolTable,       // per‑module global scope (allocated in module arena)
    type_offset: u32,                 // starting TypeId for this module's types (reserved range)
};

pub const ModuleRegistry = struct {
    modules: ArrayList(ModuleEntry),          // permanent arena
    import_edges: ArrayList(u32),             // flattened adjacency list (module_id → imported_module_id)
    path_to_id: U32ToU32Map,                  // interned path_id → module_id (fast lookup)
    resolver: *ModuleResolver,
    diag: *DiagnosticCollector,
    alloc: *Allocator,
    next_id: u32 = 0,
};
```

**Search Order (unchanged from bootstrap):**

1. Directory of the importing file
2. Directories specified via `-I` flags (in CLI order)
3. Default `lib/` directory relative to compiler executable

The `ModuleResolver` normalizes paths (e.g., `foo/../bar.zig` → `bar.zig`), resolves relative paths against the importing module's directory, and caches file contents in the `permanent` arena. All path strings are interned.

**Determinism Guarantee:** When multiple `-I` directories contain a module, the first match in CLI order is used. The search order is fixed and deterministic.

---

## 2. On‑Demand Parsing & Queue Management

Imports are discovered during parsing via `@import("path")` nodes. The parser records them, and they are queued for resolution.

### 2.1 Import Discovery During Parsing

When the parser encounters an `import_expr` node:

```zig
fn parseImportExpr(p: *Parser) !u32 {
    const tok = p.expect(.string_literal) catch return error.UnexpectedToken;
    const path_id = p.store.string_values.items[tok.value.string_id];
    
    // Queue the import for later resolution
    const imported_mod_id = try p.ctx.module_reg.resolveImport(path_id, p.current_module_id);
    try p.ctx.import_queue.enqueue(imported_mod_id);
    
    // Record edge in import_edges for current module
    try p.ctx.module_reg.addImportEdge(p.current_module_id, imported_mod_id);
    
    // Return an import_expr node (its type is module_type)
    return p.store.addNode(.import_expr, 0, tok.span_start, tok.span_end, 0, 0, 0, path_id);
}
```

**Important:** The parser does **not** wait for the imported module to be parsed. It continues parsing the current module while the import is queued.

### 2.2 Import Resolution Loop

```zig
pub const ImportQueue = struct {
    pending: ArrayList(u32),          // module_ids awaiting parsing
    allocator: *Allocator,
    diag: *DiagnosticCollector,

    pub fn enqueue(self: *ImportQueue, module_id: u32) !void {
        // Check for duplicates (linear scan – small queue)
        var i: usize = 0;
        while (i < self.pending.items.len) : (i += 1) {
            if (self.pending.items[i] == module_id) return;
        }
        try self.pending.append(module_id);
    }
};

pub fn resolveImports(reg: *ModuleRegistry, queue: *ImportQueue) !void {
    while (queue.pending.items.len > 0) {
        const mod_id = queue.pending.pop().?;
        const entry = &reg.modules.items[mod_id];
        
        if (entry.state != .pending) continue; // already parsed or failed
        
        entry.state = .parsing;
        
        // Load file content via ModuleResolver
        const path = reg.resolver.getPath(entry.path_id);
        const content = reg.resolver.loadFile(path) catch |err| {
            entry.state = .failed;
            try reg.diag.add(.error, .ERR_FILE_NOT_FOUND,
                Span{ .file_id = 0, .byte_start = 0, .byte_end = 0 },
                "file not found");
            continue;
        };
        
        // Parse module using a fresh module arena
        var module_arena = try ArenaAllocator.init(reg.alloc);
        defer module_arena.deinit(); // token arena freed after parsing; AST persists
        
        const ast_root = try parseModule(reg, mod_id, content, &module_arena);
        entry.ast_root = ast_root;
        entry.state = .parsed;
        
        // Queue newly discovered imports (recorded in import_edges during parsing)
        const start = entry.imports_start;
        const end = start + entry.import_count;
        var i: usize = start;
        while (i < end) : (i += 1) {
            const imported_id = reg.import_edges.items[i];
            if (reg.modules.items[imported_id].state == .pending) {
                try queue.enqueue(imported_id);
            }
        }
    }
}
```

### 2.3 Arena Strategy

| Arena | Lifetime | Contents |
|-------|----------|----------|
| `permanent` | Entire compilation | `ModuleRegistry`, `ModuleEntry` metadata, interned paths, file contents |
| `module` (per module) | Until C89 emission | `AstStore` (nodes, extra_children), `SymbolTable`, module‑local string interning |
| `scratch` | Reset per phase | `ImportQueue.pending`, parser stacks, temporary buffers |

**Token Arena Reset:** Tokens are stored in a separate arena within the parser that is **reset immediately after parsing completes**. Only the AST persists.

---

## 3. Topological Import Resolution (Kahn's Algorithm)

After all reachable modules are parsed, the import graph is topologically sorted to determine compilation order.

### 3.1 Algorithm

```zig
pub fn sortModules(reg: *ModuleRegistry) !void {
    const mod_count = reg.modules.items.len;
    var in_degree = try reg.alloc.alloc(u32, mod_count);
    defer reg.alloc.free(in_degree);
    // Zero-fill
    var i: usize = 0;
    while (i < mod_count) : (i += 1) { in_degree[i] = 0; }

    // Compute in-degrees from import edges
    i = 0;
    while (i < mod_count) : (i += 1) {
        const entry = reg.modules.items[i];
        if (entry.state == .failed) continue;
        const start = entry.imports_start;
        const end = start + entry.import_count;
        var j: usize = start;
        while (j < end) : (j += 1) {
            const target = reg.import_edges.items[j];
            if (target < mod_count and reg.modules.items[target].state != .failed) {
                in_degree[target] += 1;
            }
        }
    }

    // Seed worklist with modules having in_degree == 0
    var worklist = ArrayList(u32).init(reg.alloc);
    defer worklist.deinit();
    i = 0;
    while (i < mod_count) : (i += 1) {
        if (reg.modules.items[i].state != .failed and in_degree[i] == 0) {
            try worklist.append(@intCast(u32, i));
        }
    }

    // Sort worklist for determinism (module_id order)
    sortU32(worklist.items);

    var sorted_count: u32 = 0;
    while (worklist.items.len > 0) {
        const id = worklist.pop().?;
        if (reg.modules.items[id].state == .failed) continue;
        reg.modules.items[id].state = .resolved;
        sorted_count += 1;

        // Decrease in-degree of modules that import `id`
        i = 0;
        while (i < mod_count) : (i += 1) {
            const entry = reg.modules.items[i];
            if (entry.state == .failed) continue;
            const start = entry.imports_start;
            const end = start + entry.import_count;
            var j: usize = start;
            while (j < end) : (j += 1) {
                if (reg.import_edges.items[j] == id) {
                    in_degree[i] -= 1;
                    if (in_degree[i] == 0) {
                        try worklist.append(@intCast(u32, i));
                    }
                }
            }
        }
    }

    // Cycle detection
    if (sorted_count < mod_count) {
        i = 0;
        while (i < mod_count) : (i += 1) {
            if (reg.modules.items[i].state != .failed and in_degree[i] > 0) {
                try reg.diag.add(.error, .ERR_CIRCULAR_IMPORT,
                    Span{ .file_id = 0, .byte_start = 0, .byte_end = 0 },
                    "circular import detected");
                reg.modules.items[i].state = .failed;
            }
        }
    }
}
```

### 3.2 Circular Import Handling

Circular imports between modules are **rejected** at this stage. However, cross‑module pointer references (e.g., `*OtherModule.Node`) are allowed because they do **not** create an import cycle—the module only needs to know that `OtherModule.Node` exists as a type stub, which is registered during symbol registration. The actual type layout is resolved later.

---

## 4. Symbol Registration Architecture

Registration iterates top‑level declarations in **topological module order**. It populates per‑module global scopes and creates type stubs.

### 4.1 Symbol Table Structure (Aligned with TYPE_SYSTEM.md Section 6.1)

```zig
pub const SymbolTable = struct {
    scopes: ArrayList(Scope),   // only global scope (index 0) used in Pass 3
    allocator: *Allocator,

    pub const Scope = struct {
        parent: u32,            // 0 for global
        depth: u32,
        symbols: ArrayList(Symbol),
    };

    pub fn init(alloc: *Allocator) !SymbolTable {
        var self = SymbolTable{ .scopes = ArrayList(Scope).init(alloc), .allocator = alloc };
        try self.scopes.append(.{ .parent = 0, .depth = 0, .symbols = ArrayList(Symbol).init(alloc) });
        return self;
    }

    pub fn insert(self: *SymbolTable, sym: Symbol) !bool {
        const scope = &self.scopes.items[0];
        var i: usize = 0;
        while (i < scope.symbols.items.len) : (i += 1) {
            if (scope.symbols.items[i].name_id == sym.name_id) return false;
        }
        try scope.symbols.append(sym);
        return true;
    }
};

pub const SymbolKind = enum(u8) {
    global,      // top-level var/const
    function,    // top-level fn
    type_alias,  // const T = struct/enum/union
    module,      // @import result (registered automatically)
    test,        // test block (special)
};

pub const Symbol = struct {
    name_id: u32,
    type_id: TypeId,        // 0 during Pass 3, filled in Pass 5
    kind: SymbolKind,
    flags: u16,             // bit0=is_pub, bit1=is_extern, bit2=is_export, bit3=is_const
    decl_node: u32,         // AST node index (for var_decl, fn_decl, etc.)
    module_id: u32,
    scope_depth: u32,       // 0 for global
};
```

### 4.2 Registration Dispatch

```zig
pub fn registerModuleSymbols(ctx: *SemanticContext, module_id: u32) !void {
    const entry = &ctx.module_reg.modules.items[module_id];
    if (entry.state != .resolved or entry.ast_root == 0) return;

    const store = entry.ast_store;
    const root = store.nodes.items[entry.ast_root];
    const decls = store.getExtraChildren(root.payload);

    var i: usize = 0;
    while (i < decls.len) : (i += 1) {
        try registerDecl(ctx, module_id, decls[i]);
    }
}

fn registerDecl(ctx: *SemanticContext, mod_id: u32, decl_idx: u32) !void {
    const store = ctx.module_reg.modules.items[mod_id].ast_store;
    const node = store.nodes.items[decl_idx];
    switch (node.kind) {
        .var_decl => try registerVarDecl(ctx, mod_id, decl_idx, node),
        .fn_decl => try registerFnDecl(ctx, mod_id, decl_idx, node),
        .test_decl => try registerTestDecl(ctx, mod_id, decl_idx, node),
        .struct_decl, .enum_decl, .union_decl => try registerTypeDecl(ctx, mod_id, decl_idx, node),
        .error_set_decl => try registerErrorSetDecl(ctx, mod_id, decl_idx, node),
        .import_expr => { /* already handled in Pass 2 */ },
        else => {},
    }
}
```

### 4.3 Value Declaration Registration

```zig
fn registerVarDecl(ctx: *SemanticContext, mod_id: u32, decl_idx: u32, node: AstNode) !void {
    const store = ctx.module_reg.modules.items[mod_id].ast_store;
    const name_id = store.identifiers.items[node.payload];
    const is_const = (node.flags & 1) != 0;
    
    const sym = Symbol{
        .name_id = name_id,
        .type_id = 0,
        .kind = .global,
        .flags = node.flags, // pub, extern, export, const
        .decl_node = decl_idx,
        .module_id = mod_id,
        .scope_depth = 0,
    };
    
    if (!try ctx.symbol_tables[mod_id].insert(sym)) {
        try ctx.diag.add(.error, .ERR_DUPLICATE_SYMBOL,
            nodeSpan(store, decl_idx),
            "duplicate top-level declaration");
        // Continue; first declaration retained
    }
}

fn registerFnDecl(ctx: *SemanticContext, mod_id: u32, decl_idx: u32, node: AstNode) !void {
    const store = ctx.module_reg.modules.items[mod_id].ast_store;
    const proto = store.fn_protos.items[node.payload];
    const name_id = proto.name_id;
    
    const sym = Symbol{
        .name_id = name_id,
        .type_id = 0,
        .kind = .function,
        .flags = node.flags,
        .decl_node = decl_idx,
        .module_id = mod_id,
        .scope_depth = 0,
    };
    
    if (!try ctx.symbol_tables[mod_id].insert(sym)) {
        try ctx.diag.add(.error, .ERR_DUPLICATE_SYMBOL,
            nodeSpan(store, decl_idx),
            "duplicate function declaration");
    }
}
```

### 4.4 Type Declaration Registration & Stub Creation

```zig
fn registerTypeDecl(ctx: *SemanticContext, mod_id: u32, decl_idx: u32, node: AstNode) !void {
    const store = ctx.module_reg.modules.items[mod_id].ast_store;
    const name_id = store.identifiers.items[node.payload];
    const kind = switch (node.kind) {
        .struct_decl => .struct_type,
        .enum_decl => .enum_type,
        .union_decl => if ((node.flags & 1) != 0) .tagged_union_type else .union_type,
        else => unreachable,
    };
    
    // Register named type stub in TypeRegistry
    const tid = try ctx.type_reg.registerNamedType(mod_id, name_id, kind);
    
    // Register as type_alias symbol
    const sym = Symbol{
        .name_id = name_id,
        .type_id = TYPE_TYPE,
        .kind = .type_alias,
        .flags = node.flags,
        .decl_node = decl_idx,
        .module_id = mod_id,
        .scope_depth = 0,
    };
    _ = try ctx.symbol_tables[mod_id].insert(sym);
    
    // Build dependency graph edges for this type
    try addTypeDependencies(ctx, tid, node, mod_id);
}
```

### 4.5 Dependency Graph Construction

```zig
fn addTypeDependencies(ctx: *SemanticContext, tid: TypeId, node: AstNode, mod_id: u32) !void {
    const store = ctx.module_reg.modules.items[mod_id].ast_store;
    const children = store.getExtraChildren(node.payload);
    
    var i: usize = 0;
    while (i < children.len) : (i += 1) {
        const field_node = store.nodes.items[children[i]];
        if (field_node.kind != .field_decl) continue;
        
        const type_expr = field_node.child_0;
        if (type_expr == 0) continue;
        
        // Resolve the type expression to a TypeId (may be unresolved_name)
        const field_tid = try resolveTypeExprStub(ctx, type_expr, mod_id);
        if (field_tid == 0) continue;
        
        const field_ty = ctx.type_reg.types.items[field_tid];
        if (isValueDependency(field_ty.kind)) {
            try ctx.dep_graph.addEdge(field_tid, tid);
        }
    }
}

fn isValueDependency(kind: TypeKind) bool {
    return switch (kind) {
        .struct_type, .union_type, .tagged_union_type, .enum_type,
        .array_type, .optional_type, .error_union_type, .tuple_type,
        .unresolved_name => true,
        else => false,
    };
}
```

**Dependency Rules (Aligned with TYPE_SYSTEM.md 3.1):**

| Field Type | Adds Edge? |
|---|---|
| Struct field of type `T` (by value) | `T → struct` |
| Struct field of `*T` / `[]T` | No |
| Tagged union variant payload `T` (by value) | `T → union` |
| Tagged union variant payload `*T` | No |
| Optional `?T` / Error Union `!T` | `T → type` |
| Array `[N]T` | `T → array` |
| Enum member | No |

---

## 5. Cross‑Module Visibility & Qualified Lookup

### 5.1 Visibility Flags

| Modifier | Flag Bits | Export Behavior |
|---|---|---|
| `pub` | `bit0` | Visible to importing modules; emitted in `.h` |
| (default) | none | Private to module; `static` in `.c` |
| `extern` | `bit1` | Defined elsewhere; `extern` in `.h` |
| `export` | `bit2` | C‑linkage; `extern "C"` in `.h` |
| `const` | `bit3` | Immutable (for `var_decl`) |

### 5.2 Qualified Lookup (Deferred to Pass 5)

When semantic analysis encounters `module.Symbol`:

1. Look up `module` in current scope → must resolve to `SymbolKind.module` with `module_id`.
2. Look up `Symbol` in target module's `SymbolTable` (global scope only).
3. If `sym.flags & 0x1 == 0` (not `pub`), emit `ERR_VISIBILITY_VIOLATION`.
4. Return symbol for further type resolution.

Chained access (`A.B.C`) is resolved iteratively.

---

## 6. Error Handling & Recovery

| Error Condition | Recovery Action |
|---|---|
| Missing import file | Mark module `.failed`, emit `ERR_FILE_NOT_FOUND`, skip |
| Circular import graph | Mark cyclic modules `.failed`, emit `ERR_CIRCULAR_IMPORT`, continue with acyclic subset |
| Duplicate top‑level symbol | Emit `ERR_DUPLICATE_SYMBOL`, skip second declaration |
| Invalid `pub`/`extern` combination | Emit `ERR_INVALID_DECL_MODIFIER`, strip invalid flag |
| Type expression references unknown name | Create `unresolved_name` stub, add dependency edge |
| Syntax error in top‑level decl | AST contains `AstKind.err` node; skip registration |

**Diagnostic Formatting:**

```
src/math.zig:12:5: error[E3001]: duplicate top-level declaration 'add'
pub fn add(a: i32, b: i32) i32 { ... }
         ^~~
note: first declared at src/math.zig:8:5
```

---

## 7. Z98 Constraints & Guarantees

| Constraint | Enforcement |
|---|---|
| **<16 MB Peak RAM** | `module` arena per file; token arena reset post‑parse; `import_edges` flat ArrayList |
| **Deterministic Order** | Import paths sorted lexicographically before enqueue; `sortU32` on worklist; sequential `ModuleId` |
| **No Unbounded Recursion** | Iterative queue processing; Kahn's algorithm is loop‑based |
| **Immutable AST** | Registration reads only; never mutates `AstStore` |
| **No Global Aggregates** | `ModuleRegistry` initialized via `pub fn init()` and passed explicitly |

---

## 8. Testing Strategy

| Test Layer | Input | Verified Property |
|---|---|---|
| **Unit: Path Resolution** | `foo.zig`, `../bar.zig`, `-I lib/` | Correct `file_id`, deterministic ordering |
| **Unit: Kahn's Sort** | A→B→C, D→E, F→G (cycle) | Correct order, cycle detected |
| **Unit: Symbol Registration** | `pub const X = 1; fn Y() {} struct Z {}` | Correct `SymbolKind`, `flags`, stubs |
| **Unit: Dependency Graph** | `struct A { b: B }`, `struct B { a: *A }` | Edge `B→A` added, no edge `A→B` |
| **Integration: Multi‑Module** | `main.zig` → `math.zig` → `utils.zig` | All parsed, sorted, registered |
| **Integration: Visibility** | `pub fn exposed()`, `fn hidden()` | `.h` contains `exposed`, `.c` contains `static hidden` |
| **Memory Gate** | 50‑module project | Peak < 16 MB |
| **Determinism** | Compile same project 10x | Identical `ModuleId` assignment, symbol order |

---

## Appendix A: Core Data Structures (Consolidated)

```zig
pub const ModuleEntry = struct {
    id: u32,
    path_id: u32,
    state: ModuleState,
    ast_root: u32,
    import_count: u32,
    imports_start: u32,
    symbol_table: *SymbolTable,
    type_offset: u32,
};

pub const ModuleRegistry = struct {
    modules: ArrayList(ModuleEntry),
    import_edges: ArrayList(u32),
    path_to_id: U32ToU32Map,
    resolver: *ModuleResolver,
    diag: *DiagnosticCollector,
    alloc: *Allocator,
    next_id: u32,
};
```

---

## Appendix B: Registration Loop Pseudocode

```zig
pub fn runImportAndSymbolRegistration(ctx: *CompilerContext) !void {
    // 1. Parse entry module (triggers on-demand import discovery)
    try parseModule(ctx, ctx.entry_path_id);

    // 2. Drain import queue
    try resolveImports(ctx.module_reg, ctx.import_queue);

    // 3. Topological sort
    try sortModules(ctx.module_reg);

    // 4. Register symbols in topological order
    var i: usize = 0;
    while (i < ctx.module_reg.modules.items.len) : (i += 1) {
        const mod = ctx.module_reg.modules.items[i];
        if (mod.state == .resolved) {
            try registerModuleSymbols(ctx, mod.id);
        }
    }

    // 5. Finalize dependency graph for type resolution (Pass 4)
    try ctx.dep_graph.finalize();
}
```

This document provides a complete, constraint‑aware architecture for import resolution and symbol registration. It guarantees deterministic module ordering, memory‑bounded parsing, clean per‑module isolation, and seamless handoff to type resolution—ensuring `zig1` handles multi‑module programs robustly while remaining fully compatible with Z98's 1998‑era toolchain targets.
