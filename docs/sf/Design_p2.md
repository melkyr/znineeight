> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation.

# Z98 Self-Hosted Compiler Design Specification

**Version:** 3.0 — Final  
**Stage:** `zig1` — written in Z98, compiled by `zig0`, targeting C89 output  
**Predecessors:** Bootstrap DESIGN.md (v1.2), Language\_Spec\_Z98.md, Caveats\_and\_Workarounds.md  
**Reference Programs:** eval.zig (Lisp interpreter), mud.zig (MUD server), game\_of\_life.zig, mandelbrot.zig  

---

## 0. How to Read This Document

This specification is the **single authoritative design** for the self-hosted Z98 compiler (`zig1`). It supersedes the exploratory notes in earlier drafts and consolidates all decisions previously scattered across the bootstrap DESIGN.md, the caveats document, and the language specification.

Every section is structured as: **what** the component does, **why** this approach was chosen, **how** it works (pseudocode in Z98), **Z98 constraints** (workarounds for `zig0`), and **extensibility hooks** (how this component can be upgraded after `zig1` achieves self-hosting).

**Extensibility Philosophy**: `zig1` is deliberately minimal — it compiles the Z98 subset. But the architecture is designed so that after self-hosting is achieved, features like `comptime` evaluation, generics, method syntax, and richer type inference can be added incrementally without rewriting the core pipeline. Each section documents the specific extension points.

---

## 1. Design Goals and Constraints

### 1.1 What Must Change from the Bootstrap

The bootstrap compiler (`zig0`) succeeded by being minimal and monolithic. These were correct trade-offs for a C++98 bootstrap, but they introduce brittleness at scale:

| Bootstrap (`zig0`) Trait | Problem at Scale | Self-Hosted (`zig1`) Replacement |
|---|---|---|
| Monolithic `CompilationUnit` with global arena | OOM on large projects, no per-module cleanup | Per-module pipeline with allocator injection |
| Recursive Pratt expression parser | Stack overflow on deeply nested expressions | Iterative precedence climbing (bounded recursion) |
| Mutable `TYPE_PLACEHOLDER` with in-place mutation | Snapshot/iterator invalidation bugs, fragile cross-module refresh | Immutable types + dependency graph + Kahn's algorithm |
| Ad-hoc control-flow lifting during codegen | Lifting and emission entangled; hard to debug or extend | Explicit AST → LIR lowering pass, then trivial LIR → C89 emission |
| Two-tier error handling (`abort` vs `recover`) | Inconsistent; some errors crash, others are collected | Unified `DiagnosticCollector`, no aborts except OOM/ICE |
| `DynamicArray` with pointer-chasing AST children | Cache misses during traversal; fragile iterator stability | Flat `AstNode` array with `u32` index children |
| No comptime, no generics support internally | Compiler can't use its own advanced features | Extensible pass architecture with comptime hooks |

### 1.2 What Must Not Change

These properties carry forward unchanged:

- **C89 output**: Generated code compiles under `cl /Za` (MSVC 6.0), `gcc -std=c89 -pedantic` (MinGW 3.x), and OpenWatcom `wcc386`. OpenWatcom also uses `__int64` for 64-bit integers; its preprocessor differences from MSVC are minor and handled by `zig_compat.h`.
- **Win9x target**: 32-bit little-endian, 4-byte pointers, `kernel32.dll`-only runtime.
- **<16 MB peak RAM**: Enforced via allocator wrappers with configurable hard limits.
- **Separate compilation model**: Each `.zig` module produces one `.c` and one `.h` file.
- **Deterministic builds**: Seeded hashers, stable topological sorting, no global mutable state.
- **Arena allocation**: Both the compiler's own memory and the generated runtime use arena patterns.

### 1.3 Invariants

1. Every component receives its allocator explicitly via its `init` function. No global allocator.
2. The AST is immutable after parsing. Semantic passes build side-tables; they never mutate AST nodes.
3. Types are immutable once resolved. During Kahn's algorithm, a type transitions from `unresolved` → `resolving` → `resolved` exactly once. After this transition, the type is never modified.
4. No unbounded recursion. Expression parsing recurses at most O(precedence levels) ≈ 12 deep. AST traversals and LIR lowering use explicit stacks.
5. No `abort()` in library code. Only out-of-memory or internal compiler errors (ICE) trigger a panic.

---

## 2. Compilation Pipeline

The self-hosted compiler executes the following sequential pipeline. Each pass has a defined input, output, and arena lifetime.

```
Source Files
    │
    ▼
[1. Lexing + Parsing]     ── on-demand per module as imports are discovered
    │                         Token Arena reset after each module's AST is built
    ▼
[2. Import Resolution]    ── recursive discovery: parse triggers @import parsing
    │                         After ALL modules parsed, topological sort (Kahn's)
    ▼
[3. Symbol Registration]  ── register all top-level names + type stubs (unresolved_name)
    │                         Builds the type dependency graph
    ▼
[4. Type Resolution]      ── Kahn's algorithm over dependency graph
    │                         Resolves all type layouts (size, alignment, fields)
    ▼
[5. Semantic Analysis]    ── constraint checking, coercion insertion, comptime eval
    │                         Produces side-tables; never mutates AST
    ▼
[6. AST → LIR Lowering]  ── control-flow lifting, defer expansion, temp injection
    │                         Per-function, produces basic blocks
    ▼
[7. LIR Optimization]    ── constant folding, dead code elimination (optional)
    │                         Extension point for future optimization passes
    ▼
[8. LIR → C89 Emission]  ── deterministic walk, buffered output
    │                         Per-module: produces .c + .h files
    ▼
.c / .h / zig_special_types.h / zig_runtime.{h,c} / build scripts
```

### 2.1 Arena Lifetimes

```zig
pub const CompilerAlloc = struct {
    permanent: *ArenaAllocator,  // Types, interned strings, module graph, TypeRegistry
    module: *ArenaAllocator,     // AST nodes, tokens, per-module symbol tables
    scratch: *ArenaAllocator,    // Temporary buffers within a single pass
};
```

- **`permanent`**: Lives for the entire compilation. Stores the `TypeRegistry`, `StringInterner`, module dependency graph, all resolved `Type` objects, and copies of source spans needed for diagnostics.
- **`module`**: Holds the `AstStore`, token stream, and per-module symbol tables. NOT reset until all diagnostics have been printed — because diagnostic spans reference AST source positions stored in this arena. Reset after the module's `.c`/`.h` files are emitted AND all diagnostics referencing this module are flushed.
- **`scratch`**: Used within a single pass (e.g., the type resolution worklist, LIR lowering temporaries). Reset before each new pass begins.

**Memory Budget**: A custom allocator wrapper tracks peak usage across all arenas and panics if a configurable limit (default `--max-mem=16M`, adjustable via CLI) is exceeded.

**Z98 Constraint**: Global aggregate constants cannot be used for the allocator hierarchy. Use `pub var` and initialize in a dedicated `initCompilerAlloc()` function called at the start of `main`.

**Extensibility**: The three-arena hierarchy is sufficient for single-threaded compilation. When parallel module analysis is added, each worker thread receives its own `module` and `scratch` arenas, with the `permanent` arena protected by a mutex or made lock-free via thread-local staging buffers.

### 2.2 Import Resolution: On-Demand Discovery

Import resolution follows the bootstrap's model: parsing triggers import discovery.

1. Parse the entry module (`main.zig`). During parsing, `@import("foo.zig")` nodes are recorded.
2. For each unresolved import, lex and parse the target module (using its own token arena, which is reset after parsing completes).
3. Repeat until all transitive imports are discovered.
4. After ALL modules are parsed, topologically sort the module graph using Kahn's algorithm. Circular imports are allowed only for cross-module pointer types; direct value-type cycles (a struct field of type `OtherModule.S` without indirection) are rejected as circular dependencies.

**Search Order** (unchanged from bootstrap):
1. Directory of the importing file.
2. Directories specified via `-I` flags (in order given).
3. Default `lib/` directory relative to the compiler executable.

### 2.3 Critical Z98 Patterns the Compiler Must Handle

The following analysis is derived from real Z98 programs and defines the "hardest paths" the self-hosted compiler must get right. If `zig1` can compile eval.zig (a Lisp interpreter with TCO, closures, dual-arena memory, and 7 levels of nested tagged-union switches), it can compile itself.

#### Pattern 1: Deeply Nested Tagged Union Switch with Payload Capture

This is the single most important code pattern in Z98. The Lisp evaluator's `eval` function contains switch-on-tagged-union nesting up to 7 levels deep:

```zig
switch (curr_expr.*) {
    .Cons => |data| {
        switch (data.car.*) {
            .Symbol => |name| {
                switch (cdr.*) {
                    .Cons => |c_data| {
                        switch (c_data.cdr.*) {
                            .Cons => |r_data| { /* ... */ },
```

**Compiler implication**: LIR lowering for tagged union switch must extract the tag field, emit a `switch_br`, and for each prong with a payload capture, extract the payload from the union. Must handle arbitrary nesting depth without stack overflow in the lowering pass.

#### Pattern 2: Manual TCO via `while(true)` + `continue`

```zig
while (true) {
    switch (curr_expr.*) {
        // ... deep inside:
        curr_expr = then_expr;
        continue;  // must jump to while(true) header, not inner switch
```

**Compiler implication**: `continue` targeting the outermost loop from deep inside nested switches. Defer expansion must NOT insert defers on `continue` paths within the main loop unless defers were declared within that iteration.

#### Pattern 3: Pervasive `@intCast` and `@ptrCast`

Every sample uses explicit casts on almost every cross-type assignment. These are among the most frequently emitted constructs.

| Builtin | C89 Emission | Frequency |
|---|---|---|
| `@intCast(T, v)` | `(T)(v)` or `__bootstrap_T_from_U(v)` (checked) | Very High |
| `@ptrCast(T, v)` | `(T)(v)` | High |
| `@sizeOf(T)` | Compile-time constant | High |
| `@alignOf(T)` | Compile-time constant | Medium |
| `@intToFloat(T, v)` | `(T)(v)` | Medium |
| `@intToPtr(T, v)` | `(T)(v)` | Low |
| `@ptrToInt(v)` | `(unsigned int)(v)` | Low |

#### Pattern 4: `extern "c"` Declarations and C Interop

```zig
extern "c" fn plat_socket_init() i32;
extern "c" fn plat_send(sock: i32, buf: [*]const u8, len: i32) i32;
extern fn __bootstrap_print(s: [*]const c_char) void;
```

C89 emitter must NOT mangle extern names. Must handle `null` passed to pointer parameters. Must support both `extern "c"` and bare `extern`. Must support `extern` variables (e.g., `extern var zig_default_arena: *Arena`).

#### Pattern 5: Global `var` with Runtime `init()` for Aggregate Arrays

```zig
var rooms: [2]Room = undefined;
fn initRooms() void {
    rooms[0] = Room { .desc = "...", .north = @intCast(u8, 1), ... };
}
```

C89 has NO compound literals. Struct literal assignment must decompose into field-by-field assignment. Only `var_decl` with all fields in order can use positional initializer.

#### Pattern 6: Slice Creation from Raw Memory

```zig
const args_mem = try sand_mod.sand_alloc(temp_sand, arg_count * @sizeOf(*value_mod.Value), @alignOf(*value_mod.Value));
const args = @ptrCast([*]*value_mod.Value, args_mem)[0..arg_count];
```

Chains `@ptrCast` (produces many-item pointer) with slicing `[0..N]` (produces slice struct). LIR must lower to: cast + slice struct construction.

#### Pattern 7: Anonymous Tagged Union Initializers (Three Syntactic Forms)

```zig
return .Look;                           // naked tag
return .{ .Go = @intCast(u8, 0) };     // anonymous struct init
set(s_grid, 1, 0, Cell{ .Alive = {} }); // qualified init
grid[i] = Cell.Dead;                    // qualified enum-style
```

All four forms must resolve to the same C89 output. Deferred coercion must handle all variants.

#### Pattern 8: `switch` as Expression with Complex Prong Bodies

```zig
return switch (cmd) {
    .Look => { const room = rooms[player.room_id]; return room.desc; },
    .Go => |dir| { /* statements */ return rooms[player.room_id].desc; },
    .Quit => "Goodbye!\r\n",
    else => "Error\r\n",
};
```

Mixed prong types: some are single expressions, some are blocks with inner `return`. Inner `return` is a function return, not a switch-expression yield.

### 2.4 Self-Hosted Compiler: What Must Be Written

| Component | Approx. Lines | Key Patterns | Notes |
|---|---|---|---|
| `lexer.zig` | ~600 | `while` loops, `switch` on `u8`, slice indexing | Straightforward port |
| `token.zig` | ~200 | Enum definition, struct | TokenKind enum, Token struct |
| `parser.zig` | ~2500 | Precedence climbing, deep `switch`, `try` | Most complex parse logic |
| `ast.zig` | ~500 | Packed struct, enum, ArrayList | AstNode, AstKind, AstStore |
| `type_registry.zig` | ~1000 | Concrete hash maps, arena alloc, tagged unions | Core type storage |
| `type_resolver.zig` | ~700 | Kahn's algorithm, iterative worklist | Dependency resolution |
| `symbol_table.zig` | ~500 | Scope stack, hash map lookup | Hierarchical scoping |
| `semantic.zig` | ~1500 | Iterative AST visitor, coercion table | Constraint checking |
| `comptime_eval.zig` | ~400 | Integer arithmetic, comparison | Constant folding for builtins |
| `lir.zig` | ~400 | Tagged union for instructions, basic block | LIR data structures |
| `lower.zig` | ~2200 | Nested switch lowering, defer, TCO | Hardest implementation work |
| `c89_emit.zig` | ~2200 | Buffered writer, mangling, type emission | All C89 output |
| `c89_types.zig` | ~600 | Special type structs, topological emission | Slices, optionals, error unions, tagged unions |
| `diagnostics.zig` | ~400 | Span tracking, error formatting | Source line printing |
| `source_manager.zig` | ~200 | File ID tracking, offset→line/col | Referenced by diagnostics |
| `string_interner.zig` | ~200 | FNV-1a hash, open addressing | Arena-backed |
| `main.zig` | ~500 | CLI parsing, pipeline orchestration, arena init | Entry point |
| **Total** | **~14,600** | | |

---

## 3. Lexer

### 3.1 Token Structure

```zig
pub const Token = struct {
    kind: TokenKind,      // u16 enum
    span_start: u32,      // byte offset in source (supports files up to 4 GB)
    span_len: u16,        // length in bytes (max 65535; sufficient for any single token
                          // including multi-line string literals up to 64 KB)
    value: TokenValue,    // payload union for literals
};

pub const TokenValue = union {
    int_val: u64,
    float_val: f64,
    string_id: u32,       // index into StringInterner
    none: void,
};
```

Token is 16 bytes. Four tokens fit in one 64-byte cache line.

### 3.2 TokenKind Enum (Complete)

This is the contract between the lexer and the parser. Every token the lexer can produce is listed here.

```zig
pub const TokenKind = enum(u16) {
    // === Literals ===
    integer_literal,      // 123, 0xFF, 0b1010, 0o77
    float_literal,        // 3.14, 1.0e-5
    string_literal,       // "hello"
    char_literal,         // 'a'

    // === Identifier and builtins ===
    identifier,           // foo, bar_baz, _underscore
    builtin_identifier,   // @sizeOf, @intCast, @import, etc.

    // === Single-character tokens ===
    lparen,               // (
    rparen,               // )
    lbracket,             // [
    rbracket,             // ]
    lbrace,               // {
    rbrace,               // }
    semicolon,            // ;
    colon,                // :
    comma,                // ,
    dot,                  // .
    at_sign,              // @  (used before builtin names)
    underscore,           // _  (discard pattern)
    question_mark,        // ?  (optional type prefix)
    bang,                 // !  (error union prefix / boolean not)

    // === Arithmetic operators ===
    plus,                 // +
    minus,                // -
    star,                 // *
    slash,                // /
    percent,              // %

    // === Bitwise operators ===
    ampersand,            // &  (also address-of)
    pipe,                 // |  (also capture delimiter)
    caret,                // ^
    tilde,                // ~  (bitwise not)

    // === Shift operators ===
    shl,                  // <<
    shr,                  // >>

    // === Comparison operators ===
    eq_eq,                // ==
    bang_eq,              // !=
    less,                 // <
    less_eq,              // <=
    greater,              // >
    greater_eq,           // >=

    // === Assignment operators ===
    eq,                   // =
    plus_eq,              // +=
    minus_eq,             // -=
    star_eq,              // *=
    slash_eq,             // /=
    percent_eq,           // %=
    ampersand_eq,         // &=
    pipe_eq,              // |=
    caret_eq,             // ^=
    shl_eq,               // <<=
    shr_eq,               // >>=

    // === Dots and ranges ===
    dot_dot,              // ..   (exclusive range)
    dot_dot_dot,          // ...  (inclusive range)
    dot_lbrace,           // .{   (anonymous literal)
    dot_star,             // .*   (dereference)

    // === Fat arrow ===
    fat_arrow,            // =>   (switch prong separator)

    // === Keywords: declarations ===
    kw_const,
    kw_var,
    kw_fn,
    kw_pub,
    kw_extern,
    kw_export,
    kw_test,

    // === Keywords: types ===
    kw_struct,
    kw_enum,
    kw_union,

    // === Keywords: control flow ===
    kw_if,
    kw_else,
    kw_while,
    kw_for,
    kw_switch,
    kw_return,
    kw_break,
    kw_continue,
    kw_defer,
    kw_errdefer,

    // === Keywords: error handling ===
    kw_try,
    kw_catch,
    kw_orelse,
    kw_error,             // error.TagName

    // === Keywords: boolean / logical ===
    kw_and,
    kw_or,
    kw_true,
    kw_false,

    // === Keywords: special values ===
    kw_null,
    kw_undefined,
    kw_unreachable,

    // === Keywords: type names (recognized as keywords for faster dispatch) ===
    kw_void,
    kw_bool,
    kw_noreturn,
    kw_c_char,

    // === Special ===
    eof,
    err_token,            // unrecognized character (error recovery)

    // === Reserved for extensibility ===
    // After self-hosting, new keywords can be added here:
    // kw_comptime, kw_inline, kw_noinline, kw_anytype, kw_anyerror,
    // kw_usingnamespace, kw_opaque, kw_asm, kw_linksection,
};
```

**Note on type-name keywords**: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`, `u64`, `isize`, `usize`, `f32`, `f64` are lexed as `identifier` tokens and resolved to primitive types during semantic analysis. They are not keywords because treating them as keywords would add 14 token kinds with no parsing benefit. `c_char`, `void`, `bool`, and `noreturn` ARE keywords because they are used in type-expression parsing to disambiguate from identifiers.

### 3.3 Lexer Scanning Logic (Key Cases)

```zig
pub fn nextToken(self: *Lexer) Token {
    self.skipWhitespaceAndComments();
    if (self.isAtEnd()) return self.makeToken(.eof);

    const c = self.advance();
    return switch (c) {
        // Single-character tokens
        '(' => self.makeToken(.lparen),
        ')' => self.makeToken(.rparen),
        '[' => self.makeToken(.lbracket),
        ']' => self.makeToken(.rbracket),
        '{' => self.makeToken(.lbrace),
        '}' => self.makeToken(.rbrace),
        ';' => self.makeToken(.semicolon),
        ':' => self.makeToken(.colon),
        ',' => self.makeToken(.comma),
        '~' => self.makeToken(.tilde),
        '?' => self.makeToken(.question_mark),

        // Dot: . / .. / ... / .{ / .*
        '.' => {
            if (self.match('.')) {
                if (self.match('.')) return self.makeToken(.dot_dot_dot);
                return self.makeToken(.dot_dot);
            }
            if (self.match('{')) return self.makeToken(.dot_lbrace);
            if (self.match('*')) return self.makeToken(.dot_star);
            return self.makeToken(.dot);
        },

        // Operators with = variants
        '+' => if (self.match('=')) self.makeToken(.plus_eq) else self.makeToken(.plus),
        '-' => if (self.match('=')) self.makeToken(.minus_eq) else self.makeToken(.minus),
        '*' => if (self.match('=')) self.makeToken(.star_eq) else self.makeToken(.star),
        '/' => if (self.match('=')) self.makeToken(.slash_eq) else self.makeToken(.slash),
        '%' => if (self.match('=')) self.makeToken(.percent_eq) else self.makeToken(.percent),
        '^' => if (self.match('=')) self.makeToken(.caret_eq) else self.makeToken(.caret),

        // Compound: & / &= , | / |= , = / == , ! / != , < / <= / << / <<= , > / >= / >> / >>=
        '&' => if (self.match('=')) self.makeToken(.ampersand_eq) else self.makeToken(.ampersand),
        '|' => if (self.match('=')) self.makeToken(.pipe_eq) else self.makeToken(.pipe),
        '=' => {
            if (self.match('=')) return self.makeToken(.eq_eq);
            if (self.match('>')) return self.makeToken(.fat_arrow);
            return self.makeToken(.eq);
        },
        '!' => if (self.match('=')) self.makeToken(.bang_eq) else self.makeToken(.bang),
        '<' => {
            if (self.match('<')) {
                if (self.match('=')) return self.makeToken(.shl_eq);
                return self.makeToken(.shl);
            }
            if (self.match('=')) return self.makeToken(.less_eq);
            return self.makeToken(.less);
        },
        '>' => {
            if (self.match('>')) {
                if (self.match('=')) return self.makeToken(.shr_eq);
                return self.makeToken(.shr);
            }
            if (self.match('=')) return self.makeToken(.greater_eq);
            return self.makeToken(.greater);
        },

        // String and char literals
        '"' => self.scanString(),
        '\'' => self.scanChar(),

        // Builtin identifier: @name
        '@' => {
            if (self.isAlpha(self.peek())) {
                return self.scanBuiltinIdentifier();
            }
            return self.makeToken(.at_sign);
        },

        // Identifiers and keywords
        else => {
            if (self.isAlpha(c) or c == '_') return self.scanIdentifierOrKeyword(c);
            if (self.isDigit(c)) return self.scanNumber(c);
            return self.makeErrorToken();
        },
    };
}
```

**Keyword vs Identifier**: After scanning an identifier, look it up in a keyword table (linear scan of ~35 entries, or a perfect hash for speed). If found, return the keyword token kind; otherwise return `.identifier`. The keyword table includes all `kw_*` entries from the TokenKind enum.

**Extensibility**: New keywords (e.g., `comptime`, `inline`) are added to both the `TokenKind` enum and the keyword table. No other lexer changes required.

### 3.4 String Interning

All identifier and string literal content is interned into a global `StringInterner` allocated from the `permanent` arena.

```zig
pub const StringInterner = struct {
    buckets: []u32,                    // hash → index into entries (0 = empty)
    entries: ArrayList(InternEntry),
    allocator: *Allocator,

    pub const InternEntry = struct {
        text: []const u8,
        hash: u32,
        next: u32,                     // chaining for hash collisions
    };

    pub fn intern(self: *StringInterner, text: []const u8) u32 {
        const hash = fnv1a(text);
        const bucket = hash % @intCast(u32, self.buckets.len);
        var idx = self.buckets[bucket];
        while (idx != 0) {
            const entry = self.entries.items[idx];
            if (entry.hash == hash and mem_eql(entry.text, text)) return idx;
            idx = entry.next;
        }
        // Not found: insert new entry
        const new_idx = @intCast(u32, self.entries.items.len);
        const copied_text = self.copyToArena(text);
        try self.entries.append(.{ .text = copied_text, .hash = hash, .next = self.buckets[bucket] });
        self.buckets[bucket] = new_idx;
        return new_idx;
    }

    pub fn get(self: *StringInterner, id: u32) []const u8 {
        return self.entries.items[id].text;
    }

    fn fnv1a(data: []const u8) u32 {
        var h: u32 = 2166136261;
        var i: usize = 0;
        while (i < data.len) {
            h ^= @intCast(u32, data[i]);
            h *%= 16777619;
            i += 1;
        }
        return h;
    }
};
```

**Z98 Constraint**: The `StringInterner` must be declared as `pub var` and initialized via an `init` function at startup, not as a global constant.

---

## 4. Parser Architecture

### 4.1 Design Decision: Why Precedence Climbing

| Algorithm | Recursion Depth | Z98 Keyword Handling | Complexity |
|---|---|---|---|
| **Pratt (Recursive)** | O(expression depth) — unbounded | Natural | Moderate |
| **Shunting-Yard (Dijkstra)** | Zero (fully iterative) | Awkward for `try`, `catch`, `orelse`, `if`-expr | High for Z98 |
| **Precedence Climbing** | O(precedence levels) ≈ 12 — bounded | Natural | Low-moderate |

**Decision: Precedence Climbing.** Z98 has expression-level keywords (`try expr`, `expr catch |err| fallback`, `expr orelse fallback`) that are right-associative with complex substructure. In Shunting-Yard, each requires special casing that recreates recursive descent. Precedence Climbing keeps the iterative binary loop but delegates atoms to small recursive helpers, bounding recursion to ~12 levels. Used by GCC and Clang for the same reasons.

**Extensibility**: New operators or expression-level keywords (e.g., a hypothetical `async`/`await`) are added by inserting a row in the precedence table and a case in `parsePrimary` or the infix dispatch. No structural changes to the algorithm.

### 4.2 Precedence Table

```zig
pub const Prec = enum(u8) {
    none        = 0,
    assignment  = 1,   // =, +=, -=, etc.          (right-assoc)
    prec_orelse = 2,   // orelse                    (right-assoc)
    prec_catch  = 3,   // catch                     (right-assoc)
    bool_or     = 4,   // or
    bool_and    = 5,   // and
    comparison  = 6,   // ==, !=, <, <=, >, >=
    bit_or      = 7,   // |
    bit_xor     = 8,   // ^
    bit_and     = 9,   // &
    shift       = 10,  // <<, >>
    additive    = 11,  // +, -
    multiply    = 12,  // *, /, %
    prefix      = 13,  // !, -, &, try              (parsed as atoms)
    postfix     = 14,  // .field, [index], (args)    (parsed in postfix chain)

    pub fn toInt(self: Prec) u8 {
        return @intCast(u8, @enumToInt(self));
    }

    pub fn fromInt(val: u8) Prec {
        return @intToEnum(Prec, val);
    }
};
```

**Z98 Constraint**: If `zig0` does not support `@enumToInt` / `@intToEnum`, replace with manual `toInt()` and `fromInt()` helper functions that use a switch or direct cast. The enum names avoid `@"..."` quoted-identifier syntax which may not be supported by `zig0`.

```zig
pub const OpInfo = struct {
    prec: Prec,
    right_assoc: bool,
};

fn getInfixInfo(kind: TokenKind) ?OpInfo {
    return switch (kind) {
        .eq, .plus_eq, .minus_eq, .star_eq, .slash_eq, .percent_eq,
        .shl_eq, .shr_eq, .ampersand_eq, .pipe_eq, .caret_eq,
        => OpInfo{ .prec = .assignment, .right_assoc = true },

        .kw_orelse => OpInfo{ .prec = .prec_orelse, .right_assoc = true },
        .kw_catch  => OpInfo{ .prec = .prec_catch,  .right_assoc = true },

        .kw_or  => OpInfo{ .prec = .bool_or,  .right_assoc = false },
        .kw_and => OpInfo{ .prec = .bool_and, .right_assoc = false },

        .eq_eq, .bang_eq, .less, .less_eq, .greater, .greater_eq,
        => OpInfo{ .prec = .comparison, .right_assoc = false },

        .pipe  => OpInfo{ .prec = .bit_or,  .right_assoc = false },
        .caret => OpInfo{ .prec = .bit_xor, .right_assoc = false },
        .ampersand => OpInfo{ .prec = .bit_and, .right_assoc = false },
        .shl, .shr => OpInfo{ .prec = .shift, .right_assoc = false },
        .plus, .minus => OpInfo{ .prec = .additive, .right_assoc = false },
        .star, .slash, .percent => OpInfo{ .prec = .multiply, .right_assoc = false },
        else => null,
    };
}
```

### 4.3 Precedence Climbing: Core Algorithm

```zig
/// Parse an expression with minimum precedence `min_prec`.
/// Iterative for the binary loop; recursive only for:
///   1. parsePrimary (atoms)
///   2. RHS of binary ops (one call per operator, bounded by precedence levels)
///
/// Note: parsePostfixChain is called on every primary, including the RHS of
/// binary operators (via the recursive call to parseExprPrec). This correctly
/// handles cases like `a + b.field` — the recursive call parses `b` as a
/// primary, then its postfix chain `.field`, returning `b.field` as the RHS.
fn parseExprPrec(self: *Parser, min_prec: Prec) !u32 {
    var lhs = try self.parsePrimary();
    lhs = try self.parsePostfixChain(lhs);

    while (true) {
        const tok = self.peek();
        const info_opt = getInfixInfo(tok.kind);
        if (info_opt == null) break;
        const info = info_opt.?;

        if (info.prec.toInt() < min_prec.toInt()) break;

        self.advance(); // consume the operator

        const next_min = if (info.right_assoc)
            info.prec
        else
            Prec.fromInt(info.prec.toInt() + 1);

        // Special RHS handling for expression-keyword operators
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

### 4.4 Primary Expression Parsing

```zig
fn parsePrimary(self: *Parser) !u32 {
    const tok = self.peek();
    return switch (tok.kind) {
        // Literals
        .integer_literal => self.parseLiteral(.int_literal),
        .float_literal   => self.parseLiteral(.float_literal),
        .string_literal  => self.parseLiteral(.string_literal),
        .char_literal    => self.parseLiteral(.char_literal),
        .kw_true, .kw_false => self.parseLiteral(.bool_literal),
        .kw_null         => self.parseLiteral(.null_literal),
        .kw_undefined    => self.parseLiteral(.undefined_literal),
        .kw_unreachable  => self.parseLiteral(.unreachable_expr),

        // Identifiers
        .identifier      => self.parseIdentifier(),
        .builtin_identifier => self.parseBuiltinCall(),

        // error.TagName
        .kw_error        => self.parseErrorLiteral(),

        // Prefix operators
        .minus           => self.parsePrefixUnary(.negate),
        .bang            => self.parsePrefixUnary(.bool_not),
        .ampersand       => self.parsePrefixUnary(.address_of),

        // try expr (prefix keyword)
        .kw_try          => self.parseTryExpr(),

        // Grouping
        .lparen          => self.parseGroupedExpr(),

        // Aggregate literals
        .dot_lbrace      => self.parseAnonymousLiteral(),
        .dot             => self.parseEnumLiteral(),

        // Control-flow expressions
        .kw_if           => self.parseIfExpr(),
        .kw_switch       => self.parseSwitchExpr(),

        else => {
            try self.addDiagnostic(.err, tok, "expected expression");
            return error.UnexpectedToken;
        },
    };
}
```

### 4.5 Postfix Chain

```zig
fn parsePostfixChain(self: *Parser, base: u32) !u32 {
    var node = base;
    while (true) {
        node = switch (self.peek().kind) {
            .dot => blk: {
                self.advance();
                if (self.peek().kind == .star) {
                    self.advance();
                    break :blk try self.store.addUnary(.deref, node);
                }
                // Supports .field and .0 .1 (tuple index)
                break :blk try self.store.addFieldAccess(node, try self.expectIdentifierOrNumber());
            },
            .lbracket => try self.parseIndexOrSlice(node),
            .lparen   => try self.parseFnCall(node),
            else => break,
        };
    }
    return node;
}
```

### 4.6 Statement and Declaration Parsing

```zig
fn parseStatement(self: *Parser) !u32 {
    return switch (self.peek().kind) {
        .kw_const, .kw_var => self.parseVarDecl(),
        .kw_pub            => self.parsePubDecl(),
        .kw_fn             => self.parseFnDecl(),
        .kw_if             => self.parseIfStmt(),
        .kw_while          => self.parseWhileStmt(),
        .kw_for            => self.parseForStmt(),
        .kw_switch         => self.parseSwitchStmt(),
        .kw_return         => self.parseReturn(),
        .kw_break          => self.parseBreak(),
        .kw_continue       => self.parseContinue(),
        .kw_defer          => self.parseDefer(),
        .kw_errdefer       => self.parseErrdefer(),
        .kw_test           => self.parseTestDecl(),
        .lbrace            => self.parseBlock(),
        .identifier => blk: {
            if (self.peekN(1).kind == .colon) break :blk self.parseLabeledStmt();
            break :blk self.parseExprStmt();
        },
        else => self.parseExprStmt(),
    };
}
```

### 4.7 Error Recovery

On encountering an unexpected token:
1. Record a diagnostic with the current span.
2. Emit an `AstKind.err` node (allows continued traversal).
3. Skip tokens until a synchronization point: `;`, `}`, `fn`, `const`, `var`, `pub`, `test`, `eof`.
4. Resume normal parsing.

---

## 5. AST Representation

### 5.1 Design: Flat, Index-Based, Cache-Friendly

```zig
pub const AstNode = packed struct {
    kind: AstKind,        // u8
    flags: u8,            // node-specific flags (is_pub, is_const, has_capture, etc.)
    span_start: u32,      // byte offset in source file
    span_end: u32,        // byte offset of node end
    child_0: u32,         // primary child (0 = no child)
    child_1: u32,         // secondary child
    child_2: u32,         // tertiary child
    payload: u32,         // index into type-specific payload array
};
// Total: 24 bytes. Two nodes per 64-byte cache line.
```

### 5.2 Variable-Length Child Lists

Nodes with more than three children (function call arguments, switch prongs, block statements, struct fields) use the `extra_children` array. The `payload` field stores a `(start_index, count)` pair packed into a `u32`:

```zig
// Encoding: payload = (start << 16) | count
// Supports up to 65535 extra children and 65535 start positions
// For larger lists, use a two-level indirection via the extra_children array

pub const AstStore = struct {
    nodes: ArrayList(AstNode),
    extra_children: ArrayList(u32),    // flat array of child node indices
    identifiers: ArrayList(u32),       // interned string IDs
    int_values: ArrayList(u64),
    float_values: ArrayList(f64),
    string_values: ArrayList(u32),
    fn_protos: ArrayList(FnProto),
    allocator: *Allocator,

    /// Add a variable-length child list. Returns the packed payload value.
    pub fn addExtraChildren(self: *AstStore, children: []const u32) !u32 {
        const start = @intCast(u16, self.extra_children.items.len);
        var i: usize = 0;
        while (i < children.len) {
            try self.extra_children.append(children[i]);
            i += 1;
        }
        const count = @intCast(u16, children.len);
        return (@intCast(u32, start) << 16) | @intCast(u32, count);
    }

    /// Retrieve a variable-length child list from a packed payload.
    pub fn getExtraChildren(self: *AstStore, payload: u32) []const u32 {
        const start = @intCast(usize, payload >> 16);
        const count = @intCast(usize, payload & 0xFFFF);
        return self.extra_children.items[start .. start + count];
    }
};
```

### 5.3 Node Kinds (Complete for Z98)

```zig
pub const AstKind = enum(u8) {
    // === Error recovery ===
    err,

    // === Declarations ===
    var_decl,           // const/var; child_0=type_expr, child_1=init_expr, payload=name_id
    fn_decl,            // child_0=body_block, payload→FnProto (params, return type)
    struct_decl,        // payload→extra_children (field list)
    enum_decl,          // child_0=backing_type (or 0), payload→extra_children (members)
    union_decl,         // child_0=tag_type (or 0 for bare), payload→extra_children (variants)
    field_decl,         // child_0=type_expr, child_1=default_value, payload=name_id
    param_decl,         // child_0=type_expr, payload=name_id
    test_decl,          // child_0=body_block, payload=name_string_id

    // === Literals ===
    int_literal,        // payload→int_values index
    float_literal,      // payload→float_values index
    string_literal,     // payload→string_values index
    char_literal,       // payload→int_values index (codepoint)
    bool_literal,       // flags bit 0 = value
    null_literal,
    undefined_literal,
    unreachable_expr,
    enum_literal,       // .MemberName; payload=name_id
    error_literal,      // error.TagName; payload=name_id
    tuple_literal,      // .{ a, b, c }; payload→extra_children
    struct_init,        // .{ .x = 1, .y = 2 }; payload→extra_children (field_init nodes)
    field_init,         // .name = expr; child_0=expr, payload=name_id

    // === Expressions ===
    ident_expr,         // payload=interned string ID
    field_access,       // child_0=base, payload=field_name_id
    index_access,       // child_0=base, child_1=index_expr
    slice_expr,         // child_0=base, child_1=start, child_2=end
    deref,              // child_0=base (expr.*)
    address_of,         // child_0=operand (&expr)
    fn_call,            // child_0=callee, payload→extra_children (args)
    builtin_call,       // child_0..child_2=args, payload=builtin_name_id, flags=arg_count

    // === Binary operators ===
    add, sub, mul, div, mod_op,
    bit_and, bit_or, bit_xor, shl, shr,
    bool_and, bool_or,
    cmp_eq, cmp_ne, cmp_lt, cmp_le, cmp_gt, cmp_ge,
    assign, add_assign, sub_assign, mul_assign, div_assign, mod_assign,
    shl_assign, shr_assign, and_assign, xor_assign, or_assign,

    // === Unary operators ===
    negate, bool_not,

    // === Error/Optional handling ===
    try_expr,           // child_0=operand
    catch_expr,         // child_0=lhs, child_1=fallback, child_2=capture (or 0)
    orelse_expr,        // child_0=lhs, child_1=fallback

    // === Control flow ===
    if_stmt,            // child_0=cond, child_1=then_body, child_2=else_body
    if_expr,            // child_0=cond, child_1=then_expr, child_2=else_expr
    if_capture,         // child_0=cond, child_1=then_body, child_2=else_body, payload=capture_name
    while_stmt,         // child_0=cond, child_1=body, child_2=continue_expr (or 0)
    while_capture,      // while (opt) |val|; child_0=cond, child_1=body, payload=capture_name
    for_stmt,           // child_0=iterable, child_1=body, payload→captures (item, opt index)
    switch_expr,        // child_0=condition, payload→extra_children (prong list)
    switch_prong,       // child_0=body; payload→extra_children (pattern values); flags=has_capture
    block,              // payload→extra_children (statement list)
    return_stmt,        // child_0=value (or 0 for void)
    break_stmt,         // payload=label_id (0 = unlabeled)
    continue_stmt,      // payload=label_id (0 = unlabeled)
    defer_stmt,         // child_0=deferred_statement
    errdefer_stmt,      // child_0=deferred_statement

    // === Type expressions ===
    ptr_type,           // child_0=pointee_type; flags bit 0 = is_const
    many_ptr_type,      // child_0=pointee_type; flags bit 0 = is_const
    array_type,         // child_0=elem_type, child_1=size_expr
    slice_type,         // child_0=elem_type; flags bit 0 = is_const
    optional_type,      // child_0=payload_type
    error_union_type,   // child_0=payload_type, child_1=error_set (or 0 for anonymous)
    fn_type,            // payload→FnProto
    error_set_decl,     // payload→extra_children (member name IDs)

    // === Module-level ===
    import_expr,        // payload=path_string_id
    module_root,        // payload→extra_children (top-level decls)

    // === Captures ===
    payload_capture,    // payload=name_id; flags bit 0 = has_index_capture

    // === Ranges ===
    range_exclusive,    // child_0=start, child_1=end (start..end)
    range_inclusive,     // child_0=start, child_1=end (start...end)

    // === Labels ===
    labeled_stmt,       // child_0=inner_stmt (while/for), payload=label_name_id
};
```

### 5.4 Iterative AST Traversal

```zig
fn visitAst(alloc: *Allocator, store: *AstStore, root: u32, visitor: *Visitor) !void {
    var stack = ArrayList(u32).init(alloc);
    defer stack.deinit();
    try stack.append(root);
    while (stack.items.len > 0) {
        const idx = stack.pop().?;
        if (idx == 0) continue;
        const node = store.nodes.items[idx];
        try visitor.visit(node, idx);
        // Push children in reverse order for natural traversal
        if (node.child_2 != 0) try stack.append(node.child_2);
        if (node.child_1 != 0) try stack.append(node.child_1);
        if (node.child_0 != 0) try stack.append(node.child_0);
        // Push extra_children for nodes that have them
        if (nodeHasExtraChildren(node.kind)) {
            const children = store.getExtraChildren(node.payload);
            var i: usize = children.len;
            while (i > 0) {
                i -= 1;
                try stack.append(children[i]);
            }
        }
    }
}
```

---

## 6. Type System

### 6.1 Immutable Types with Registry

Types are allocated once, stored in a `TypeRegistry`, and identified by `TypeId` (a `u32` index). After Kahn's algorithm completes, every type is in the `resolved` state and is never modified.

```zig
pub const TypeId = u32;

pub const TypeKind = enum(u8) {
    // Primitives
    void_type, bool_type, noreturn_type,
    i8_type, i16_type, i32_type, i64_type,
    u8_type, u16_type, u32_type, u64_type,
    isize_type, usize_type,
    c_char_type,
    f32_type, f64_type,

    // Compound
    ptr_type,              // *T, *const T
    many_ptr_type,         // [*]T, [*]const T
    array_type,            // [N]T
    slice_type,            // []T, []const T
    optional_type,         // ?T
    error_union_type,      // E!T
    error_set_type,        // error { A, B, ... }
    fn_type,               // fn(P1, P2, ...) R
    struct_type,
    enum_type,
    union_type,            // bare union
    tagged_union_type,     // union(enum)
    tuple_type,            // struct { T1, T2, ... }

    // Resolution states
    unresolved_name,       // forward reference: name known, layout unknown
    type_type,             // the type of types (for `const T = struct { ... }`)
    module_type,           // pseudo-type for @import results

    // Reserved for extensibility
    // comptime_int, comptime_float, anytype_type, anyerror_type,
    // opaque_type, vector_type,
};

pub const Type = struct {
    kind: TypeKind,
    state: u8,             // 0=unresolved, 1=resolving, 2=resolved
    size: u32,             // bytes (computed during resolution)
    alignment: u32,        // bytes
    name_id: u32,          // interned string ID for canonical name
    c_name_id: u32,        // interned string ID for mangled C name
    module_id: u32,        // defining module
    payload_idx: u32,      // index into the kind-specific payload array
};
```

### 6.2 TypeRegistry and Hash Map Strategy

**Critical Design Decision**: Z98 has no generics. `zig0` cannot instantiate `AutoHashMap(K, V)` with arbitrary key/value types. The self-hosted compiler uses **concrete, hand-specialized hash maps** for each use case.

```zig
pub const TypeRegistry = struct {
    types: ArrayList(Type),
    interner: *StringInterner,
    allocator: *Allocator,

    // Kind-specific payload arrays (parallel to types via Type.payload_idx)
    ptr_payloads: ArrayList(PtrPayload),
    array_payloads: ArrayList(ArrayPayload),
    slice_payloads: ArrayList(SlicePayload),
    optional_payloads: ArrayList(OptionalPayload),
    error_union_payloads: ArrayList(EUPayload),
    struct_payloads: ArrayList(StructPayload),
    enum_payloads: ArrayList(EnumPayload),
    union_payloads: ArrayList(UnionPayload),
    fn_payloads: ArrayList(FnPayload),
    tuple_payloads: ArrayList(TuplePayload),

    // Deduplication caches — concrete hash maps, NOT generic AutoHashMap
    ptr_cache: U64ToU32Map,         // key = (base_tid << 1) | is_const
    slice_cache: U64ToU32Map,       // key = (elem_tid << 1) | is_const
    optional_cache: U32ToU32Map,    // key = payload_tid
    array_cache: U64ToU32Map,       // key = (elem_tid << 32) | length

    // Named type lookup
    name_cache: U64ToU32Map,        // key = (module_id << 32) | name_hash → TypeId
};
```

**Concrete Hash Map Implementation**:

```zig
/// A simple open-addressing hash map from u32 → u32.
/// No generics required. Arena-allocated.
pub const U32ToU32Map = struct {
    keys: []u32,
    values: []u32,
    occupied: []bool,
    capacity: u32,
    count: u32,
    allocator: *Allocator,

    pub fn get(self: *U32ToU32Map, key: u32) ?u32 {
        var idx = key % self.capacity;
        var probes: u32 = 0;
        while (probes < self.capacity) {
            if (!self.occupied[idx]) return null;
            if (self.keys[idx] == key) return self.values[idx];
            idx = (idx + 1) % self.capacity;
            probes += 1;
        }
        return null;
    }

    pub fn put(self: *U32ToU32Map, key: u32, value: u32) !void {
        if (self.count * 4 >= self.capacity * 3) try self.grow(); // 75% load
        var idx = key % self.capacity;
        while (self.occupied[idx] and self.keys[idx] != key) {
            idx = (idx + 1) % self.capacity;
        }
        self.keys[idx] = key;
        self.values[idx] = value;
        if (!self.occupied[idx]) { self.occupied[idx] = true; self.count += 1; }
    }
};

/// u64 → u32 map (same structure, wider keys).
pub const U64ToU32Map = struct {
    keys: []u64,
    values: []u32,
    occupied: []bool,
    capacity: u32,
    count: u32,
    allocator: *Allocator,
    // ... same get/put logic with u64 keys
};
```

**Extensibility**: After self-hosting, when `comptime` is available, these concrete maps can be replaced by a single generic `HashMap(K, V, hashFn, eqlFn)`. The concrete maps serve as the bootstrap-compatible implementation.

### 6.3 Type Resolution: Kahn's Algorithm

Forward references produce `TypeKind.unresolved_name` entries. This is NOT the bootstrap's mutable placeholder — it is an immutable stub that records only the name and defining module. Resolution proceeds via Kahn's topological sort over a dependency graph.

**Dependency Graph Construction** (during Symbol Registration, pass 3):
- For each struct field of type `T`, add edge `T → this_struct`.
- For `*T` or `[]T`, the pointer/slice can be resolved immediately (size is always 4 bytes), so only add an edge if `T` is used by value.
- Self-referential types via pointer (`struct Node { next: *Node }`) do NOT create a cycle because `*Node` resolves without knowing `Node`'s size.
- Direct value recursion (`struct Bad { inner: Bad }`) creates a cycle and is detected as `in_degree > 0` after the algorithm completes.

```zig
pub const TypeResolver = struct {
    registry: *TypeRegistry,
    // Dependency graph: for each TypeId, list of TypeIds that depend on it
    dependents: ArrayList(DepEntry),  // flat array of (source, target) pairs
    in_degree: []u32,                 // indexed by TypeId
    worklist: ArrayList(TypeId),
    diag: *DiagnosticCollector,
    allocator: *Allocator,

    pub fn resolve(self: *TypeResolver) !void {
        // 1. Seed worklist: types with in_degree == 0
        var tid: u32 = 0;
        while (tid < @intCast(u32, self.registry.types.items.len)) : (tid += 1) {
            if (self.in_degree[tid] == 0) try self.worklist.append(tid);
        }

        var resolved_count: u32 = 0;
        // 2. Process
        while (self.worklist.items.len > 0) {
            const id = self.worklist.pop().?;
            try self.resolveTypeLayout(id);
            self.registry.types.items[id].state = 2; // resolved
            resolved_count += 1;

            // Decrease dependents' in-degree
            var i: usize = 0;
            while (i < self.dependents.items.len) : (i += 1) {
                if (self.dependents.items[i].source == id) {
                    const dep = self.dependents.items[i].target;
                    self.in_degree[dep] -= 1;
                    if (self.in_degree[dep] == 0) try self.worklist.append(dep);
                }
            }
        }

        // 3. Cycle detection
        if (resolved_count < @intCast(u32, self.registry.types.items.len)) {
            tid = 0;
            while (tid < @intCast(u32, self.registry.types.items.len)) : (tid += 1) {
                if (self.in_degree[tid] > 0) {
                    try self.diag.add(.{ .level = 0, .span = self.registry.spanOf(tid),
                        .message = "circular type dependency (infinite size)" });
                }
            }
        }
    }
};
```

### 6.4 Type Coercion Rules

| From | To | Kind | Implementation |
|---|---|---|---|
| `T` | `?T` | Implicit | Wrap in optional struct |
| `null` | `?T` | Implicit | Zero-init optional struct |
| `*T` | `?*T` | Implicit | Wrap non-null pointer in optional |
| `T` | `E!T` | Implicit | Wrap in error union (success) |
| `error.X` | `E!T` | Implicit | Wrap in error union (error) |
| `[N]T` | `[]T` | Implicit | Synthetic slice `arr[0..N]` |
| `[N]T` | `[*]T` | Implicit | Address of first element |
| `[]T` | `[*]T` | Implicit | Access `.ptr` field |
| `*const [N]u8` (string lit) | `[]const u8` | Implicit | Synthetic slice |
| `*const [N]u8` (string lit) | `[*]const u8` | Implicit | Pointer to first element |
| `*const [N]u8` (string lit) | `*const u8` | Implicit | Pointer to first element |
| `*T` | `*const T` | Implicit | Const-qualify |
| `[]T` | `[]const T` | Implicit | Const-qualify |
| `[*]T` | `[*]const T` | Implicit | Const-qualify |
| `i8` → `i16` → `i32` → `i64` | Widening | Implicit | C cast |
| `u8` → `u16` → `u32` → `u64` | Widening | Implicit | C cast |
| `f32` → `f64` | Widening | Implicit | C cast |
| Any narrowing | — | Explicit | Requires `@intCast` / `@floatCast` |
| `*T` → `*U` | — | Explicit | Requires `@ptrCast` |
| Integer → Pointer | — | Explicit | Requires `@intToPtr` |
| Pointer → Integer | — | Explicit | Requires `@ptrToInt` |

**No implicit coercion between `i32` and `usize`**. This is Z98-specific strictness.

---

## 7. Semantic Analysis

Semantic analysis is a series of read-only passes over the AST that build side-tables. They never mutate AST nodes.

### 7.1 Pass Pipeline

1. **Symbol Table Build**: Single pass per module. Creates scoped symbol entries for all declarations.
2. **Type Resolution**: Kahn's algorithm (Section 6.3).
3. **Comptime Evaluation**: Evaluates `@sizeOf`, `@alignOf`, constant expressions. Produces a `ComptimeValueTable` mapping AST node indices to computed values.
4. **Constraint Checking**: Verifies assignment compatibility, call signatures, return types, switch exhaustiveness.
5. **Coercion Insertion**: Produces a `CoercionTable` mapping AST node indices to required coercion operations.
6. **Liveness and Safety** (optional): Dangling pointer, null analysis, double-free detection.

### 7.2 Symbol Table

```zig
pub const SymbolTable = struct {
    scopes: ArrayList(Scope),
    current_scope: u32,
    allocator: *Allocator,

    pub const Scope = struct {
        parent: u32,
        symbols: ArrayList(Symbol),  // linear scan; scopes are typically small
    };

    pub const Symbol = struct {
        name_id: u32,
        type_id: TypeId,
        kind: u8,      // 0=local, 1=param, 2=global, 3=function, 4=type_alias, 5=module
        flags: u16,    // is_const, is_pub, is_mutable, is_exported, is_extern
        decl_node: u32,
        scope_level: u32,
    };

    pub fn lookup(self: *SymbolTable, name_id: u32) ?*Symbol {
        var scope_idx = self.current_scope;
        while (true) {
            const scope = &self.scopes.items[scope_idx];
            var i: usize = 0;
            while (i < scope.symbols.items.len) : (i += 1) {
                if (scope.symbols.items[i].name_id == name_id) {
                    return &scope.symbols.items[i];
                }
            }
            if (scope_idx == 0) break;
            scope_idx = scope.parent;
        }
        return null;
    }
};
```

### 7.3 Comptime Evaluation

The self-hosted compiler requires comptime evaluation for:
- `@sizeOf(T)` — resolves to a `u32` constant after type resolution.
- `@alignOf(T)` — resolves to a `u32` constant.
- `@intCast(T, <literal>)` — folds to the cast value when the operand is a constant.
- Integer arithmetic on compile-time-known values (array sizes: `WIDTH * HEIGHT`).
- Boolean constant folding for `if`/`switch` on constants.

```zig
pub const ComptimeEval = struct {
    value_table: U32ToU64Map,   // AST node index → computed u64 value
    registry: *TypeRegistry,
    interner: *StringInterner,

    pub fn evaluate(self: *ComptimeEval, store: *AstStore, node_idx: u32) ?u64 {
        const node = store.nodes.items[node_idx];
        return switch (node.kind) {
            .int_literal => store.int_values.items[node.payload],
            .bool_literal => if (node.flags & 1 != 0) @intCast(u64, 1) else 0,
            .builtin_call => self.evalBuiltin(store, node),
            .add => self.evalBinOp(store, node, .add),
            .sub => self.evalBinOp(store, node, .sub),
            .mul => self.evalBinOp(store, node, .mul),
            .div => self.evalBinOp(store, node, .div),
            .mod_op => self.evalBinOp(store, node, .mod_op),
            .ident_expr => self.evalIdent(store, node),  // resolve const declarations
            else => null,  // not comptime-evaluable
        };
    }

    fn evalBuiltin(self: *ComptimeEval, store: *AstStore, node: AstNode) ?u64 {
        const name = self.interner.get(node.payload);
        if (mem_eql(name, "sizeOf")) {
            const type_id = self.resolveTypeArg(store, node.child_0);
            if (type_id) |tid| return @intCast(u64, self.registry.types.items[tid].size);
        }
        if (mem_eql(name, "alignOf")) {
            const type_id = self.resolveTypeArg(store, node.child_0);
            if (type_id) |tid| return @intCast(u64, self.registry.types.items[tid].alignment);
        }
        return null;
    }
};
```

**Extensibility**: This is the seed of full `comptime` support. After self-hosting, this evaluator can be extended to handle arbitrary expressions, `comptime` blocks, `comptime` function parameters, and compile-time code generation. The `ComptimeEval` struct is designed to be replaceable with a full interpreter that shares the type system and AST infrastructure.

### 7.4 `@import` Semantics

`@import("foo.zig")` returns a value of `module_type`. The module pseudo-type has no size or alignment. It exists only in the symbol table to enable qualified access:

```zig
// When the parser encounters: const foo = @import("foo.zig");
// Symbol table gets: { name="foo", type=module_type, kind=module, module_ref=<module_id> }
//
// When the type checker encounters: foo.SomeType or foo.someFunction
// It looks up "foo" → module symbol → switches to the target module's symbol table
// to resolve "SomeType" or "someFunction".
```

Cross-module resolution is on-demand: when `module.Symbol` is accessed, the type checker looks up the target module's symbol table. If the target module hasn't been type-checked yet but has been parsed and had symbols registered, forward references via pointers or function signatures are allowed. Value-type access to an unresolved module triggers an error.

### 7.5 `std.debug.print` Decomposition

`std.debug.print` is a compiler intrinsic, not a real function call. The semantic analysis pass detects it and decomposes it into a series of runtime helper calls.

```zig
// Source:
std.debug.print("x = {d}, name = {s}\n", .{x, name});

// After decomposition (conceptual):
__bootstrap_print("x = ");
__bootstrap_print_i32(x);
__bootstrap_print(", name = ");
__bootstrap_print_str(name);
__bootstrap_print("\n");
```

**Implementation**:
1. The parser produces a normal `fn_call` node for `std.debug.print`.
2. During semantic analysis, the call is recognized as the print intrinsic.
3. A side-table entry (`PrintDecomposition`) is created that stores: the parsed format string segments, the tuple argument node indices, and the resolved types of each argument.
4. During LIR lowering, the `fn_call` is expanded into a sequence of `call` instructions to the appropriate `__bootstrap_print_*` helpers based on the format specifier and argument type.

| Format Specifier | Argument Type | C89 Helper |
|---|---|---|
| `{}` (default) | `i32`, `u32`, `i64`, `u64` | `__bootstrap_print_int` |
| `{}` (default) | `bool` | `__bootstrap_print_bool` |
| `{}` (default) | `[]const u8` | `__bootstrap_print_str` |
| `{d}` | integer types | `__bootstrap_print_int` |
| `{x}` | integer types | `__bootstrap_print_hex` |
| `{c}` | `u8` | `__bootstrap_print_char` |
| `{s}` | `[]const u8`, `[*]const u8` | `__bootstrap_print_str` |

### 7.6 Constraint Checking

The constraint checker verifies:

- **Assignment compatibility**: LHS type is compatible with RHS type (directly or via coercion).
- **Call signature matching**: Argument count and types match parameter types.
- **Return type compatibility**: Returned value matches the function's return type.
- **Switch exhaustiveness**: All enum variants or ranges are covered (or `else` is present).
- **Break/continue validity**: Only inside loops; not inside `defer`/`errdefer` blocks.
- **Const enforcement**: Cannot assign to `const` variables or `*const T` dereferences.
- **C89 feature compliance**: Rejects constructs not supported in the Z98 subset.

### 7.7 Coercion Table

Coercions are recorded as a side-table, NOT as AST mutations:

```zig
pub const CoercionKind = enum(u8) {
    none,
    wrap_optional,          // T → ?T
    wrap_error_success,     // T → !T (success)
    wrap_error_err,         // error.X → !T (error)
    unwrap_optional,        // if-capture: ?T → T
    array_to_slice,         // [N]T → []T
    array_to_many_ptr,      // [N]T → [*]T
    slice_to_many_ptr,      // []T → [*]T
    string_to_slice,        // *const [N]u8 → []const u8
    string_to_many_ptr,     // *const [N]u8 → [*]const u8
    string_to_ptr,          // *const [N]u8 → *const u8
    ptr_to_optional_ptr,    // *T → ?*T
    const_qualify,          // *T → *const T, []T → []const T
    int_widen,              // i8 → i32, etc.
    float_widen,            // f32 → f64
};

pub const CoercionTable = struct {
    entries: ArrayList(CoercionEntry),
    /// Lookup by AST node index. Returns the coercion to apply.
    pub fn get(self: *CoercionTable, node_idx: u32) ?CoercionEntry { ... }
};

pub const CoercionEntry = struct {
    node_idx: u32,
    kind: CoercionKind,
    target_type: TypeId,
};
```

### 7.8 Diagnostic Collector

```zig
pub const Diagnostic = struct {
    level: u8,            // 0=error, 1=warning, 2=info
    file_id: u32,
    span_start: u32,
    span_end: u32,
    message: []const u8,
};

pub const DiagnosticCollector = struct {
    diagnostics: ArrayList(Diagnostic),
    allocator: *Allocator,

    pub fn hasErrors(self: *DiagnosticCollector) bool {
        var i: usize = 0;
        while (i < self.diagnostics.items.len) : (i += 1) {
            if (self.diagnostics.items[i].level == 0) return true;
        }
        return false;
    }
};
```

### 7.9 Source Manager

```zig
pub const SourceManager = struct {
    files: ArrayList(SourceFile),

    pub const SourceFile = struct {
        filename: []const u8,
        content: []const u8,
        line_offsets: ArrayList(u32),   // byte offset of each line start
    };

    pub fn getLocation(self: *SourceManager, file_id: u32, offset: u32) Location {
        const file = self.files.items[file_id];
        // Binary search line_offsets to find line number
        var lo: usize = 0;
        var hi: usize = file.line_offsets.items.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (file.line_offsets.items[mid] <= offset) lo = mid + 1 else hi = mid;
        }
        const line = @intCast(u32, lo);
        const col = offset - file.line_offsets.items[line - 1];
        return .{ .file_id = file_id, .line = line, .col = col };
    }
};
```

---

## 8. LIR (Linear Intermediate Representation)

### 8.1 Why a Separate IR

The bootstrap performs control-flow lifting during codegen, coupling semantics and emission. The self-hosted compiler separates these: AST → LIR handles all transformations; LIR → C89 is a trivial walk.

### 8.2 LIR Structure

```zig
pub const LirFunction = struct {
    name_id: u32,
    return_type: TypeId,
    params: ArrayList(LirParam),
    blocks: ArrayList(BasicBlock),
    hoisted_temps: ArrayList(TempDecl),
    is_extern: bool,
    is_pub: bool,
};

pub const LirParam = struct {
    name_id: u32,
    type_id: TypeId,
};

pub const TempDecl = struct {
    temp_id: u32,
    type_id: TypeId,
};

pub const BasicBlock = struct {
    id: u32,
    insts: ArrayList(LirInst),
    is_terminated: bool,
};

pub const SwitchCase = struct {
    value: i64,         // case constant value
    target_bb: u32,     // basic block to jump to
};

pub const LirInst = union(enum) {
    // === Declarations ===
    decl_temp: struct { temp: u32, type_id: TypeId },
    decl_local: struct { name_id: u32, type_id: TypeId, temp: u32 },

    // === Assignments ===
    assign: struct { dst: u32, src: u32 },
    assign_field: struct { base: u32, field_id: u32, src: u32 },
    assign_index: struct { base: u32, index: u32, src: u32 },

    // === Control flow ===
    jump: u32,
    branch: struct { cond: u32, then_bb: u32, else_bb: u32 },
    switch_br: struct { cond: u32, cases_start: u32, cases_count: u32, else_bb: u32 },
    loop_header: u32,      // marks start of a loop (for continue target tracking)
    ret: u32,
    ret_void: void,
    label: u32,            // labeled break/continue target

    // === Expressions ===
    binary: struct { op: u8, lhs: u32, rhs: u32, result: u32 },
    unary: struct { op: u8, operand: u32, result: u32 },
    call: struct { callee: u32, args_start: u32, args_count: u32, result: u32 },
    load_field: struct { base: u32, field_id: u32, result: u32 },
    store_field: struct { base: u32, field_id: u32, value: u32 },
    load_index: struct { base: u32, index: u32, result: u32 },
    load: struct { ptr: u32, result: u32 },
    store: struct { ptr: u32, value: u32 },
    addr_of: struct { operand: u32, result: u32 },

    // === Coercions (explicit) ===
    wrap_optional: struct { value: u32, result: u32, type_id: TypeId },
    unwrap_optional: struct { value: u32, result: u32 },
    check_optional: struct { value: u32, result: u32 },        // result = has_value flag
    wrap_error_ok: struct { value: u32, result: u32, type_id: TypeId },
    wrap_error_err: struct { value: u32, result: u32, type_id: TypeId },
    unwrap_error_payload: struct { value: u32, result: u32 },
    unwrap_error_code: struct { value: u32, result: u32 },
    check_error: struct { value: u32, result: u32 },           // result = is_error flag
    make_slice: struct { ptr: u32, len: u32, result: u32, type_id: TypeId },
    int_cast: struct { value: u32, target: TypeId, result: u32, is_checked: bool },
    float_cast: struct { value: u32, target: TypeId, result: u32 },
    ptr_cast: struct { value: u32, target: TypeId, result: u32 },
    int_to_float: struct { value: u32, target: TypeId, result: u32 },
    ptr_to_int: struct { value: u32, result: u32 },
    int_to_ptr: struct { value: u32, target: TypeId, result: u32 },

    // === Literals ===
    int_const: struct { value: u64, result: u32 },
    float_const: struct { value: f64, result: u32 },
    string_const: struct { string_id: u32, result: u32 },
    null_const: struct { result: u32 },
    bool_const: struct { value: u8, result: u32 },
    undefined_const: struct { result: u32, type_id: TypeId },

    // === Locals ===
    load_local: struct { name_id: u32, result: u32 },
    store_local: struct { name_id: u32, value: u32 },
    load_global: struct { name_id: u32, result: u32 },
    store_global: struct { name_id: u32, value: u32 },

    // === Print intrinsic (lowered from std.debug.print) ===
    print_str: struct { string_id: u32 },
    print_val: struct { value: u32, type_id: TypeId, fmt: u8 },

    // === No-op (replaces removed instructions) ===
    nop: void,
};
```

**Note**: `switch_br` stores `cases_start` and `cases_count` as indices into a separate `ArrayList(SwitchCase)` on the `LirFunction`, avoiding variable-length data inside the union.

### 8.3 Lowering: Key Transformations

#### 8.3.1 `if`-Expression Lifting

```
// var x = if (c) a else b;
decl_temp(__tmp_0, T)
branch(c, bb_then, bb_else)
bb_then: assign(__tmp_0, <eval a>); jump(bb_join)
bb_else: assign(__tmp_0, <eval b>); jump(bb_join)
bb_join: store_local(x, __tmp_0)
```

#### 8.3.2 `try` Expression

```
// const val = try mightFail();
call(mightFail, [], __eu_tmp)
check_error(__eu_tmp, __is_err)
branch(__is_err, bb_propagate, bb_ok)
bb_propagate: unwrap_error_code(__eu_tmp, __err); [expand errdefers]; ret_error(__err)
bb_ok: unwrap_error_payload(__eu_tmp, val)
```

#### 8.3.3 Tagged Union Switch with Payload Capture

```
// switch (expr.*) { .Cons => |data| { ... }, .Nil => return x, else => error }
load_field(expr, .tag, __tag)
switch_br(__tag, [(Cons, bb_cons), (Nil, bb_nil)], else: bb_default)
bb_cons:
  load_field(expr, .payload.Cons, __payload)
  // __payload is the captured `data` — bind it as a local
  // ... lower body ...
bb_nil: ret(x)
bb_default: wrap_error_err(...)
```

#### 8.3.4 `for` Loop over Slice

```zig
// for (slice) |item, idx| { body }
```

LIR:
```
load_field(slice, .ptr, __ptr)
load_field(slice, .len, __len)
int_const(0, __idx)
jump(bb_cond)

bb_cond:
  binary(lt, __idx, __len, __cmp)
  branch(__cmp, bb_body, bb_exit)

bb_body:
  load_index(__ptr, __idx, item)     // item = ptr[idx]
  // ... lower body ...
  // continue expression:
  binary(add, __idx, int_const(1), __idx)
  jump(bb_cond)

bb_exit:
```

#### 8.3.5 `for` Loop over Range

```zig
// for (0..10) |i| { body }
```

LIR:
```
int_const(0, __i)
int_const(10, __end)
jump(bb_cond)

bb_cond:
  binary(lt, __i, __end, __cmp)
  branch(__cmp, bb_body, bb_exit)

bb_body:
  // i = __i (bind as local)
  // ... lower body ...
  binary(add, __i, int_const(1), __i)
  jump(bb_cond)

bb_exit:
```

#### 8.3.6 Struct Literal Assignment (C89 Decomposition)

C89 has NO compound literals. Struct literal in assignment position → field-by-field:
```
// rooms[0] = Room { .desc = "...", .north = 1 };
assign_field(rooms[0], .desc, string_const("..."))
assign_field(rooms[0], .north, int_const(1))
```

Exception: `var_decl` with all fields in declaration order may use C89 positional initializer.

#### 8.3.7 Defer and Errdefer Expansion

```zig
pub const DeferAction = struct {
    kind: u8,           // 0=normal, 1=errdefer
    ast_node: u32,      // the deferred statement's AST node
    scope_depth: u32,
};
```

At each scope exit (return, break, continue, block end):
1. Walk defer stack top-down to the target scope depth.
2. For `kind=0` (normal defer): always emit.
3. For `kind=1` (errdefer): emit only if exit is via error path (inside a `try` propagation or an explicit error return).
4. Then emit the exit instruction (`ret`, `jump`).

`continue` inside `while(true)` (TCO pattern): defers declared OUTSIDE the loop are not expanded on `continue`. Only defers declared within the current iteration scope are expanded.

#### 8.3.8 Temporary Hoisting

After lowering, collect all `decl_temp` and `decl_local` instructions, move to `hoisted_temps`. Skip entries where `type_id` resolves to `void`.

---

## 9. C89 Code Generation

### 9.1 Emitter Architecture

The emitter walks LIR functions in basic-block order and writes C89 text through a 4 KB buffered writer.

```zig
pub const C89Emitter = struct {
    writer: BufferedWriter,
    indent: u32,
    registry: *TypeRegistry,
    interner: *StringInterner,
    mangler: *NameMangler,
    switch_cases: *ArrayList(SwitchCase),
    call_args: *ArrayList(u32),
};
```

### 9.2 Type Emission

#### 9.2.1 Special Type Structs

| Z98 Type | C89 Struct | Notes |
|---|---|---|
| `[]T` | `typedef struct { T* ptr; unsigned int len; } Slice_T;` | |
| `?T` | `typedef struct { T value; int has_value; } Opt_T;` | |
| `?*T` (at extern boundary) | `T*` | NULL-allowed raw pointer |
| `!T` | `typedef struct { union { T payload; int err; } data; int is_error; } EU_T;` | |
| `!void` | `typedef struct { int err; int is_error; } EU_void;` | No payload union member |
| `union(enum)` all-void | `typedef struct { int tag; } TU_Name;` | No payload union |
| `union(enum)` with payloads | `typedef struct { int tag; union { ... } payload; } TU_Name;` | |
| `union` (bare) | `typedef union { ... } U_Name;` | |
| `enum(T)` | `typedef T E_Name; #define E_Name_Member N` | |

Slice helpers are emitted as `static` functions (not `static inline` — C89 has no `inline`).

Self-referential types require a forward declaration: `typedef struct zS_Value zS_Value;` before the struct body.

#### 9.2.2 Topological Emission Order

Types are emitted to `zig_special_types.h` in dependency order: if `Slice_Node` references `Node`, then `Node`'s typedef appears first. The `MetadataPreparationPass` transitively walks all types reachable from public signatures.

#### 9.2.3 Function Pointer Typedefs

Each unique function signature used in `@ptrCast` gets a typedef:
```c
typedef EU_pValue (*FP_builtin)(Slice_pValue, Sand*);
```

### 9.3 Extern Handling

- `extern "c"` and bare `extern` function names: emitted verbatim (no mangling).
- `extern` variables: `extern T name;` in headers.
- Parameter type mapping: `[*]const u8` → `const unsigned char*`, `c_char` → `char`, `?*T` at boundary → `T*`.
- `null` to pointer param: emit `((T*)0)` with the correct target type.

### 9.4 Name Mangling

FNV-1a-based, deterministic. Two modes:

- **Standard**: `z<Kind>_<Hash>_<Name>` — hash derived from module path.
- **Test**: `z<Kind>_<Counter>_<Name>` — global counter for stable regression tests.

Rules: C89 keywords prefixed `z_`. All identifiers truncated to 31 chars. User `__`-prefixed identifiers mangled to `z___user_...`. Compiler temps (`__tmp_`, `__return_`, `__bootstrap_`) bypass mangling.

### 9.5 Struct Literal Emission

For `var_decl` with initializer (all fields, declaration order): positional initializer.
```c
Room r = {"desc", 1, 0, 0, 0};
```

For assignment to existing variable or indexed element: field-by-field.
```c
rooms[0].desc = "desc";
rooms[0].north = 1;
```

C89 has NO compound literals `(Type){...}`. Never emit them.

### 9.6 Separate Compilation Output

Per module `foo.zig`:
- `foo.c` — implementations, `static` for non-pub symbols.
- `foo.h` — public typedefs, extern function prototypes, include guards.

Global outputs:
- `zig_special_types.h` — all slice/optional/error-union/tagged-union typedefs.
- `zig_compat.h` — platform detection, `__int64`, `bool`/`true`/`false` definitions.
- `zig_runtime.h` / `zig_runtime.c` — arena allocator, panic handler, checked conversions.
- `build_target.bat` / `build_target.sh` — build scripts.

### 9.7 MSVC 6.0 / OpenWatcom / MinGW Compatibility

- `__int64` for `i64`/`u64` (MSVC and OpenWatcom).
- Manual `bool`/`true`/`false` if absent.
- String literals split at 2048 chars.
- Identifiers truncated to 31 chars.
- All declarations at top of `{}` blocks (enforced by LIR hoisting).
- Comments: `/* ... */` only (no `//`).
- No trailing commas in enums or initializers.
- No mixed declarations and code.
- No `inline` keyword.
- Void pointer arithmetic: `((char*)ptr + offset)`.
- Empty struct/union: add `char _dummy;` member.

---

## 10. Module Graph and Import Resolution

Modules are topologically sorted using Kahn's algorithm over the import graph. This guarantees that when a module enters type checking, all of its dependencies are already resolved.

**Circular import handling**: Circular imports between modules are supported ONLY for cross-module pointer types (e.g., `*OtherModule.Node`). A "direct value-type cycle" — where a struct field is of type `OtherModule.S` (not behind a pointer or slice) — is rejected as a circular dependency because it would require infinite size. The Kahn's algorithm cycle detection catches this.

---

## 11. Z98-Specific Implementation Constraints

These constraints apply to the code of `zig1` itself (compiled by `zig0`).

| Limitation | Workaround | Notes |
|---|---|---|
| No pointer captures (`if (opt) \|*p\|`) | `if (slot != null) { var p = &slot.value; }` | |
| No `.?` operator | `.value` after null check, or `orelse return error.X` | |
| Global aggregate constants may fail | `pub var` with `init()` at startup | Used for keyword table, precedence table |
| Strict type coercion (`i32` ↔ `usize`) | `@intCast` everywhere | Very common in zig1 code |
| Switch expressions require `else` | Always include `else => unreachable` | |
| `std.debug.print` requires tuple | `std.debug.print("msg", .{})` | |
| No method syntax | Free functions: `foo(self, ...)` | |
| No generics / `comptime` params / `anytype` | Concrete hash maps, manual specialization | See Section 6.2 |
| No `anyerror` | Explicit error sets | |
| `@enumToInt`/`@intToEnum` may not work | Manual `toInt()`/`fromInt()` helpers | See Section 4.2 |
| `*[N]T` emits incorrectly | Use `[]T` for function args | Bootstrap codegen bug |
| Optional field order bugs | Unwrap before extern calls | Bootstrap codegen bug |
| No `//` comments in generated C | Emitter uses `/* */` only | C89 strictness |
| `const X = union(enum) { ... };` | Allowed — named via `const` | Not an anonymous aggregate |
| Slices of fn ptrs | Supported via `@ptrCast` | See eval.zig `.Builtin` pattern |

---

## 12. Testing Strategy

### 12.1 Differential Testing (Development Phase)

Before `zig1` is complete enough to self-host, use `zig0` as the oracle:

1. Compile a test program with `zig0` → `expected.c`
2. Compile the same test program with `zig1` (partial pipeline) → `actual.c`
3. `diff expected.c actual.c`

Both compilers must support `--dump-ast`, `--dump-types`, `--dump-lir` flags for intermediate comparison.

### 12.2 Reference Program Suite

These programs serve as integration test targets:

| Program | Tests | Difficulty |
|---|---|---|
| mandelbrot.zig | Float arithmetic, extern C, `@intToFloat`, arrays | Easy |
| game\_of\_life.zig | Tagged unions, switch, `extern "c"`, `@intCast` | Medium |
| mud.zig | Sockets, structs, global var init, slices, `null` | Medium |
| eval.zig | 7-level switch nesting, TCO, dual-arena, closures, `try`, error unions | Hard |
| **zig1 itself** | All of the above + hash maps, iterative traversal, buffered I/O | Hardest |

**Pass criterion**: Generated C89 compiles without warnings under `gcc -std=c89 -pedantic -Wall` AND `cl /Za /W3`, and the resulting binary produces expected output.

### 12.3 Bootstrap Identity Test

```
zig0 compiles zig1.zig → zig1.exe
zig1.exe compiles zig1.zig → zig2.exe
fc /b zig1.exe zig2.exe  →  files must be identical
```

### 12.4 Memory Regression Gate

Compile `zig1.zig` with `zig1.exe` and verify peak memory stays under 16 MB. Use the allocator wrapper's peak tracking. Abort the test if the limit is exceeded.

### 12.5 Determinism Test

Compile any test program twice. The generated `.c` and `.h` files must be byte-identical. This verifies no hash-order or pointer-address leakage.

---

## 13. Migration Path

### Phase 1: Lexer and Parser
Implement `lexer.zig`, `token.zig`, `parser.zig`, `ast.zig`. Verify with `--dump-ast` flag: parse reference programs and compare AST structure against `zig0`'s output (add `--dump-ast` to `zig0` if not present).

### Phase 2: Type System
Implement `type_registry.zig`, `type_resolver.zig`, `string_interner.zig`, concrete hash maps. Verify with `--dump-types`: resolve type graphs of multi-module programs and compare layouts.

### Phase 3: Semantic Analysis
Implement `semantic.zig`, `comptime_eval.zig`, `symbol_table.zig`, `source_manager.zig`, `diagnostics.zig`. Verify: run diagnostic suite against known-good and known-bad programs.

### Phase 4: LIR Lowering
Implement `lir.zig`, `lower.zig`. Verify with `--dump-lir`: lower test programs and inspect LIR output for correctness.

### Phase 5: C89 Emitter
Implement `c89_emit.zig`, `c89_types.zig`. Verify: differential test against `zig0`'s C89 output for all reference programs.

### Phase 5.5: Reference Program Validation
Compile ALL four reference programs through `zig1`. Verify generated C89 compiles and runs correctly on all target toolchains (MinGW, MSVC 6.0, OpenWatcom).

### Phase 6: Self-Hosting
Compile `zig1.zig` with `zig0` → `zig1.exe`. Compile `zig1.zig` with `zig1.exe` → `zig2.exe`. Verify: `fc /b zig1.exe zig2.exe`.

---

## 14. Extensibility Architecture

After `zig1` achieves self-hosting, it becomes its own compiler. This section documents the designed-in extension points for each future feature.

### 14.1 Adding `comptime` Evaluation

**Current state**: `ComptimeEval` (Section 7.3) handles `@sizeOf`, `@alignOf`, and constant folding for integer arithmetic.

**Extension path**:
1. Add `kw_comptime` to `TokenKind` and parse `comptime` blocks/parameters.
2. Extend `ComptimeEval` into a full AST interpreter that can evaluate arbitrary expressions, including function calls, at compile time.
3. Add `comptime_int` and `comptime_float` to `TypeKind` for arbitrary-precision compile-time numbers.
4. The LIR lowering pass skips `comptime` blocks entirely — their results are folded into constants before lowering begins.

### 14.2 Adding Generics

**Current state**: Concrete hash maps (`U32ToU32Map`, `U64ToU32Map`) are manually specialized.

**Extension path**:
1. Add `anytype` as a parameter modifier in the parser.
2. During semantic analysis, when a generic function is called with concrete types, monomorphize: clone the function's AST, substitute concrete types for `anytype` parameters, and type-check the clone.
3. Each monomorphization gets a unique mangled name and is lowered/emitted separately.
4. Replace the concrete hash maps with a single `HashMap(K, V)` generic, instantiated at each call site via monomorphization.

### 14.3 Adding Method Syntax

**Current state**: All functions are free functions. `foo(self, ...)` style.

**Extension path**:
1. During parsing, detect `self` or `Self` as the first parameter.
2. During semantic analysis, register methods on the type's namespace.
3. When `expr.method(args)` is encountered and `expr` is a struct type with a method named `method`, rewrite as `Type.method(expr, args)` — a simple AST transformation before lowering.

### 14.4 Adding More Optimization Passes

**Current state**: LIR optimization (pipeline step 7) is a no-op.

**Extension path**: Each optimization is a function `fn optimize(func: *LirFunction) void` that transforms LIR in-place:
1. **Constant folding**: Replace `binary(add, const_3, const_5, result)` with `int_const(8, result)`.
2. **Dead code elimination**: Remove assignments to temps that are never read.
3. **Copy propagation**: Replace `assign(a, b); use(a)` with `use(b)`.
4. **Basic block merging**: Merge blocks connected by unconditional jumps.

### 14.5 Adding New Backends

**Current state**: C89 is the only backend.

**Extension path**: The LIR is backend-agnostic. A new backend (e.g., direct x86 assembly, LLVM IR, or a different C standard) implements the same interface: `fn emit(func: *LirFunction, writer: *Writer) void`. The `main.zig` CLI selects the backend via a `--backend=c89|x86|llvm` flag.

### 14.6 Adding Parallel Compilation

**Current state**: Single-threaded sequential pipeline.

**Extension path**: After modules are topologically sorted, independent modules (those with no mutual dependencies) can be lowered and emitted in parallel. Each worker thread gets its own `module` and `scratch` arenas. The `permanent` arena is read-only during lowering/emission (all types are resolved by then).

---

## Appendix A: Glossary

| Term | Definition |
|---|---|
| `zig0` | Bootstrap compiler, written in C++98 |
| `zig1` | Self-hosted compiler, written in Z98, compiled by `zig0` |
| `zig2` | `zig1` compiled by itself; must be byte-identical to `zig1` |
| Z98 | Restricted Zig subset targeting C89 and Win9x |
| LIR | Linear Intermediate Representation; three-address code with basic blocks |
| Precedence Climbing | Expression parsing: iterative binary loop with bounded recursion for atoms |
| Kahn's Algorithm | Topological sort via in-degree counting |
| Arena | Region-based allocator; free everything at once |
| Hoisting | Moving C89 variable declarations to block top |
| PAL | Platform Abstraction Layer; all system calls go through this |
| TCO | Tail Call Optimization; implemented manually via `while(true)` + `continue` |
| Monomorphization | Creating a concrete copy of a generic function for specific types |
| Compound literal | C99 feature `(Type){...}` — NOT available in C89 |
| ICE | Internal Compiler Error; triggers panic |
