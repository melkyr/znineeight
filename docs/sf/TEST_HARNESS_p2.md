> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project.

# Z98 Self-Hosted Compiler Test Harness

**Version:** 1.0  
**Component:** Test framework, differential testing, integration suite, verification gates  
**Parent Document:** DESIGN.md v3.0  

---

## 1. Testing Philosophy

The self-hosted compiler has a single ultimate correctness criterion: **the bootstrap identity test** (`fc /b zig1.exe zig2.exe`). Every other test exists to catch bugs before they cascade into self-hosting failure.

Testing is organized in layers, from fastest/cheapest to slowest/most expensive:

```
Layer 1: Unit Tests           ~2 seconds    Per-component, in-process
Layer 2: AST Comparison       ~5 seconds    Parse + dump + diff against oracle
Layer 3: C89 Output Diff      ~15 seconds   Full pipeline, diff generated C against zig0
Layer 4: Compile & Run         ~30 seconds   Generated C → native binary → verify output
Layer 5: Memory Gate           ~10 seconds   Peak memory tracking during compilation
Layer 6: Determinism Check     ~5 seconds    Compile twice, diff outputs
Layer 7: Self-Hosting          ~2 minutes    zig0→zig1→zig2, binary comparison
```

### 1.1 Constraints

- All test code is written in Z98 (compiled by `zig0`).
- Tests must run within the 16 MB memory budget.
- Tests are batched to avoid arena fragmentation (following the bootstrap's batch architecture).
- No external test framework dependencies — the harness is self-contained.

---

## 2. Test Framework Core

### 2.1 Assertion Primitives

```zig
const TestResult = struct {
    passed: u32,
    failed: u32,
    skipped: u32,
};

var global_result: TestResult = .{ .passed = 0, .failed = 0, .skipped = 0 };

fn assert_true(condition: bool, msg: []const u8, file: []const u8, line: u32) void {
    if (condition) {
        global_result.passed += 1;
    } else {
        global_result.failed += 1;
        std.debug.print("FAIL: {s} at {s}:{d}\n", .{ msg, file, line });
    }
}

fn assert_eq_u32(expected: u32, actual: u32, msg: []const u8) void {
    if (expected == actual) {
        global_result.passed += 1;
    } else {
        global_result.failed += 1;
        std.debug.print("FAIL: {s}: expected {d}, got {d}\n", .{ msg, expected, actual });
    }
}

fn assert_eq_str(expected: []const u8, actual: []const u8, msg: []const u8) void {
    if (util.mem_eql(expected, actual)) {
        global_result.passed += 1;
    } else {
        global_result.failed += 1;
        std.debug.print("FAIL: {s}: expected '{s}', got '{s}'\n", .{ msg, expected, actual });
    }
}

fn assert_node_kind(store: *AstStore, idx: u32, expected: AstKind, msg: []const u8) void {
    if (idx == 0) {
        global_result.failed += 1;
        std.debug.print("FAIL: {s}: node is null\n", .{msg});
        return;
    }
    assert_eq_u32(@enumToInt(expected), @enumToInt(store.nodes.items[idx].kind), msg);
}
```

### 2.2 Test Batch Runner

Each batch is a separate compilation unit that tests one component. Batches are run sequentially by a shell script.

```zig
pub fn main() !void {
    std.debug.print("=== Lexer Tests ===\n", .{});
    test_lexer_integers();
    test_lexer_strings();
    test_lexer_operators();
    test_lexer_keywords();
    test_lexer_multichar_ops();
    test_lexer_comments();
    test_lexer_error_recovery();

    std.debug.print("\nResults: {d} passed, {d} failed, {d} skipped\n", .{
        global_result.passed, global_result.failed, global_result.skipped,
    });

    if (global_result.failed > 0) {
        // Exit with error code for the runner script
        return error.TestsFailed;
    }
}
```

### 2.3 Test Helper: Parse String to AST

```zig
fn parseTestSource(source: []const u8) TestParseResult {
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    var interner = StringInterner.init(&arena.allocator);
    var diag = DiagnosticCollector.init(&arena.allocator);

    // Lex
    var tokens = ArrayList(Token).init(&arena.allocator);
    var lexer = Lexer.init(source);
    while (true) {
        const tok = lexer.nextToken();
        tokens.append(tok) catch unreachable;
        if (tok.kind == .eof) break;
    }

    // Parse
    var store = AstStore.init(&arena.allocator);
    var parser = Parser.init(tokens.items, &store, &interner, &diag, &arena.allocator);
    const root = parser.parseModule() catch 0;

    return .{
        .store = store,
        .interner = interner,
        .diag = diag,
        .root = root,
        .arena = arena,
    };
}

const TestParseResult = struct {
    store: AstStore,
    interner: StringInterner,
    diag: DiagnosticCollector,
    root: u32,
    arena: ArenaAllocator,

    pub fn deinit(self: *TestParseResult) void {
        self.arena.deinit();
    }
};
```

---

## 3. Layer 1: Unit Tests

### 3.1 Lexer Tests

| Test | Input | Verified Property |
|---|---|---|
| `test_integer_decimal` | `"42"` | `.integer_literal`, value=42 |
| `test_integer_hex` | `"0xFF"` | `.integer_literal`, value=255 |
| `test_integer_binary` | `"0b1010"` | `.integer_literal`, value=10 |
| `test_integer_octal` | `"0o77"` | `.integer_literal`, value=63 |
| `test_integer_underscore` | `"1_000_000"` | `.integer_literal`, value=1000000 |
| `test_float_basic` | `"3.14"` | `.float_literal`, value≈3.14 |
| `test_float_scientific` | `"1.0e-5"` | `.float_literal` |
| `test_string_basic` | `"\"hello\""` | `.string_literal`, content="hello" |
| `test_string_escape` | `"\"a\\nb\""` | `.string_literal`, contains newline |
| `test_char_basic` | `"'a'"` | `.char_literal`, value=97 |
| `test_char_escape` | `"'\\n'"` | `.char_literal`, value=10 |
| `test_dot_variants` | `". .. ... .{ .*"` | `.dot`, `.dot_dot`, `.dot_dot_dot`, `.dot_lbrace`, `.dot_star` |
| `test_shift_ops` | `"<< >> <<= >>="` | `.shl`, `.shr`, `.shl_eq`, `.shr_eq` |
| `test_fat_arrow` | `"=>"` | `.fat_arrow` |
| `test_all_keywords` | one token per keyword | Correct `.kw_*` kind for each |
| `test_builtin_ident` | `"@sizeOf"` | `.builtin_identifier` |
| `test_line_comment` | `"42 // comment\n43"` | Two integer tokens, comment skipped |
| `test_block_comment` | `"42 /* nested /* inner */ outer */ 43"` | Two integer tokens, nested comments handled |
| `test_unrecognized` | `"42 $ 43"` | `.integer_literal`, `.err_token`, `.integer_literal` |

### 3.2 Parser Tests: Expressions

| Test | Input | Verified AST Structure |
|---|---|---|
| `test_int_literal` | `"42"` | Root is `.int_literal`, value=42 |
| `test_binary_add` | `"1 + 2"` | `.add` with `.int_literal` children |
| `test_precedence` | `"1 + 2 * 3"` | `.add(1, .mul(2, 3))` |
| `test_left_assoc` | `"10 - 4 - 2"` | `.sub(.sub(10, 4), 2)` |
| `test_right_assoc_orelse` | `"a orelse b orelse c"` | `.orelse_expr(a, .orelse_expr(b, c))` |
| `test_right_assoc_catch` | `"a catch b catch c"` | `.catch_expr(a, .catch_expr(b, c))` |
| `test_assignment` | `"x = 42"` | `.assign(ident(x), 42)` |
| `test_compound_assign` | `"x += 1"` | `.add_assign(ident(x), 1)` |
| `test_unary_negate` | `"-x"` | `.negate(ident(x))` |
| `test_unary_chain` | `"!!x"` | `.bool_not(.bool_not(ident(x)))` |
| `test_address_of` | `"&x"` | `.address_of(ident(x))` |
| `test_deref` | `"p.*"` | `.deref(ident(p))` |
| `test_field_access` | `"s.field"` | `.field_access(ident(s), "field")` |
| `test_index_access` | `"arr[0]"` | `.index_access(ident(arr), 0)` |
| `test_slice` | `"arr[1..5]"` | `.slice_expr(ident(arr), 1, 5)` |
| `test_fn_call_no_args` | `"foo()"` | `.fn_call(ident(foo), [])` |
| `test_fn_call_args` | `"add(1, 2)"` | `.fn_call(ident(add), [1, 2])` |
| `test_chained_postfix` | `"a.b[0].c()"` | Correct nesting of field/index/call |
| `test_try_expr` | `"try foo()"` | `.try_expr(.fn_call(foo, []))` |
| `test_catch_with_capture` | `"x catch \|e\| 0"` | `.catch_expr(x, 0, capture(e))` |
| `test_builtin_sizeof` | `"@sizeOf(i32)"` | `.builtin_call`, name="sizeOf", 1 arg |
| `test_builtin_intcast` | `"@intCast(u8, x)"` | `.builtin_call`, name="intCast", 2 args |
| `test_if_expr` | `"if (c) a else b"` | `.if_expr(ident(c), ident(a), ident(b))` |
| `test_switch_expr` | `"switch (x) { 1 => a, else => b }"` | `.switch_expr` with 2 prongs |
| `test_enum_literal` | `".Alive"` | `.enum_literal`, name="Alive" |
| `test_anon_struct_init` | `".{ .x = 1 }"` | `.struct_init(0, [field_init(x, 1)])` |
| `test_tuple_literal` | `".{ 1, 2, 3 }"` | `.tuple_literal([1, 2, 3])` |
| `test_error_literal` | `"error.Bad"` | `.error_literal`, name="Bad" |
| `test_range_exclusive` | `"0..10"` | `.range_exclusive(0, 10)` |
| `test_range_inclusive` | `"1...5"` | `.range_inclusive(1, 5)` |

### 3.3 Parser Tests: Statements and Declarations

| Test | Input | Verified Property |
|---|---|---|
| `test_var_decl` | `"var x: i32 = 42;"` | `.var_decl`, name="x", has type + init |
| `test_const_decl` | `"const pi = 3.14;"` | `.var_decl`, is_const=true |
| `test_fn_decl` | `"fn add(a: i32, b: i32) i32 { return a; }"` | `.fn_decl`, 2 params, return type, body |
| `test_pub_fn` | `"pub fn foo() void {}"` | `.fn_decl`, is_pub=true |
| `test_extern_fn` | `"extern fn bar() i32;"` | `.fn_decl`, is_extern=true, no body |
| `test_if_stmt` | `"if (x) { a; } else { b; }"` | `.if_stmt`, both branches |
| `test_if_capture` | `"if (opt) \|val\| { use(val); }"` | `.if_capture`, capture name |
| `test_while_stmt` | `"while (cond) { body; }"` | `.while_stmt` |
| `test_while_continue` | `"while (i < 10) : (i += 1) {}"` | `.while_stmt`, child_2=continue expr |
| `test_while_capture` | `"while (opt) \|val\| {}"` | `.while_capture` |
| `test_for_slice` | `"for (arr) \|item\| {}"` | `.for_stmt` |
| `test_for_range` | `"for (0..10) \|i\| {}"` | `.for_stmt`, iterable is `.range_exclusive` |
| `test_for_index` | `"for (arr) \|item, idx\| {}"` | `.for_stmt`, has_index_capture |
| `test_switch_stmt` | `"switch (x) { 1 => f(), else => g() }"` | Parsed as expr wrapped in `.expr_stmt` |
| `test_return_void` | `"return;"` | `.return_stmt`, no child |
| `test_return_value` | `"return 42;"` | `.return_stmt`, child_0=42 |
| `test_defer` | `"defer cleanup();"` | `.defer_stmt` |
| `test_errdefer` | `"errdefer rollback();"` | `.errdefer_stmt` |
| `test_break` | `"break;"` | `.break_stmt`, no label |
| `test_break_label` | `"break :outer;"` | `.break_stmt`, label="outer" |
| `test_continue` | `"continue;"` | `.continue_stmt` |
| `test_labeled_while` | `"outer: while (true) {}"` | `.labeled_stmt` wrapping `.while_stmt` |
| `test_block` | `"{ a; b; c; }"` | `.block` with 3 statement children |
| `test_struct_decl` | `"struct { x: i32, y: f32 }"` | `.struct_decl` with 2 `.field_decl` |
| `test_enum_decl` | `"enum { Red, Green, Blue }"` | `.enum_decl` with 3 members |
| `test_enum_backing` | `"enum(u8) { A = 1, B = 2 }"` | `.enum_decl`, backing type present |
| `test_union_bare` | `"union { a: i32, b: f32 }"` | `.union_decl`, is_tagged=false |
| `test_union_tagged` | `"union(enum) { Nil, Int: i64 }"` | `.union_decl`, is_tagged=true |
| `test_import` | `"@import(\"std.zig\")"` | `.import_expr` |

### 3.4 Parser Tests: Type Expressions

| Test | Input | Verified AST |
|---|---|---|
| `test_type_prim` | `"i32"` | `.ident_expr`, name="i32" |
| `test_type_ptr` | `"*i32"` | `.ptr_type(ident(i32))` |
| `test_type_const_ptr` | `"*const u8"` | `.ptr_type(ident(u8))`, is_const=true |
| `test_type_many_ptr` | `"[*]u8"` | `.many_ptr_type(ident(u8))` |
| `test_type_slice` | `"[]u8"` | `.slice_type(ident(u8))` |
| `test_type_const_slice` | `"[]const u8"` | `.slice_type(ident(u8))`, is_const=true |
| `test_type_array` | `"[10]u8"` | `.array_type(ident(u8), int(10))` |
| `test_type_optional` | `"?i32"` | `.optional_type(ident(i32))` |
| `test_type_error_union` | `"!i32"` | `.error_union_type(ident(i32))` |
| `test_type_fn_ptr` | `"fn(i32, i32) void"` | `.fn_type`, 2 params, void return |
| `test_type_qualified` | `"std.debug.PrintOptions"` | Nested `.field_access` chain |
| `test_type_error_set` | `"error { Bad, Worse }"` | `.error_set_decl` with 2 members |
| `test_type_multi_ptr_const` | `"[*]const u8"` | `.many_ptr_type`, is_const=true |

### 3.5 Parser Tests: Error Recovery

| Test | Input | Verified Behavior |
|---|---|---|
| `test_missing_semicolon` | `"var x: i32 = 42 var y: i32 = 0;"` | Error diagnostic added; second decl still parsed |
| `test_unexpected_token` | `"fn foo( { }"` | Error node emitted; parser synchronizes to `}` |
| `test_multiple_errors` | Several broken decls | Multiple diagnostics collected, not just first |

### 3.6 Type System Unit Tests

| Test | Verified Property |
|---|---|
| `test_primitive_registration` | All primitives pre-registered at init with correct sizes |
| `test_ptr_dedup` | `*i32` created twice returns same TypeId |
| `test_slice_dedup` | `[]u8` created twice returns same TypeId |
| `test_optional_dedup` | `?i32` created twice returns same TypeId |
| `test_struct_layout` | Struct with `i32, u8, f64` has correct size + alignment |
| `test_tagged_union_layout` | `union(enum) { A: i32, B: f64 }` has correct tag + payload size |
| `test_self_referential` | `struct Node { next: *Node }` resolves without cycle error |
| `test_cycle_detection` | `struct Bad { inner: Bad }` produces circular dependency error |
| `test_cross_module_ptr` | `*OtherModule.Node` resolves through module boundary |

### 3.7 Comptime Evaluation Tests

| Test | Input | Expected |
|---|---|---|
| `test_sizeof_i32` | `@sizeOf(i32)` | 4 |
| `test_sizeof_ptr` | `@sizeOf(*i32)` | 4 |
| `test_sizeof_slice` | `@sizeOf([]u8)` | 8 (ptr + len) |
| `test_alignof_i32` | `@alignOf(i32)` | 4 |
| `test_const_fold_add` | `3 + 5` | 8 |
| `test_const_fold_mul` | `WIDTH * HEIGHT` (constants) | Correct product |
| `test_intcast_literal` | `@intCast(u8, 255)` | 255 |

---

## 4. Layer 2: AST Comparison (Differential Testing)

Both `zig0` and `zig1` support a `--dump-ast` flag that outputs a canonical text representation of the AST.

### 4.1 Canonical AST Format

```
(module_root
  (fn_decl "main" pub=true
    (params
      (param_decl "argc" (ident_expr "i32"))
    )
    (return_type (ident_expr "void"))
    (block
      (expr_stmt (fn_call (ident_expr "print") (string_literal "hello")))
    )
  )
)
```

### 4.2 Diff Strategy

```bash
#!/bin/sh
# ast_diff_test.sh <source.zig>
SOURCE=$1
./zig0 --dump-ast "$SOURCE" > /tmp/ast_zig0.txt
./zig1 --dump-ast "$SOURCE" > /tmp/ast_zig1.txt
diff /tmp/ast_zig0.txt /tmp/ast_zig1.txt
if [ $? -ne 0 ]; then
    echo "FAIL: AST mismatch for $SOURCE"
    exit 1
fi
echo "PASS: AST matches for $SOURCE"
```

### 4.3 Test Inputs

Run against every reference program and the compiler's own source:
- `mandelbrot.zig`
- `game_of_life.zig`
- `mud.zig`
- `eval.zig` (all modules: `value.zig`, `env.zig`, `util.zig`, `sand.zig`, `deep_copy.zig`)
- Every `zig1` source file

---

## 5. Layer 3: C89 Output Diff

### 5.1 Strategy

Compile a test program through both `zig0` and `zig1` pipelines and diff the generated `.c` and `.h` files.

```bash
#!/bin/sh
# c89_diff_test.sh <source.zig>
SOURCE=$1
mkdir -p /tmp/zig0_out /tmp/zig1_out
./zig0 "$SOURCE" -o /tmp/zig0_out/
./zig1 "$SOURCE" -o /tmp/zig1_out/

for f in /tmp/zig0_out/*.c /tmp/zig0_out/*.h; do
    base=$(basename "$f")
    diff "$f" "/tmp/zig1_out/$base"
    if [ $? -ne 0 ]; then
        echo "FAIL: C89 mismatch for $base"
        exit 1
    fi
done
echo "PASS: C89 output matches for $SOURCE"
```

### 5.2 Lenient Matching Mode

For cases where output is structurally identical but whitespace or temp variable numbering differs:

```bash
# Normalize: strip whitespace, replace __tmp_N with __tmp_#
normalize() {
    sed 's/[[:space:]]//g; s/__tmp_[0-9]*/__tmp_#/g' "$1"
}
```

---

## 6. Layer 4: Compile & Run

### 6.1 End-to-End Verification

```bash
#!/bin/sh
# e2e_test.sh <source.zig> <expected_output>
SOURCE=$1
EXPECTED=$2

# Compile with zig1
./zig1 "$SOURCE" -o /tmp/e2e_out/
cd /tmp/e2e_out/

# Build with GCC (C89 mode)
sh build_target.sh
if [ $? -ne 0 ]; then echo "FAIL: C compilation failed"; exit 1; fi

# Run and capture output
./target > /tmp/actual_output.txt 2>&1

# Compare
diff "$EXPECTED" /tmp/actual_output.txt
if [ $? -ne 0 ]; then echo "FAIL: runtime output mismatch"; exit 1; fi
echo "PASS: $SOURCE"
```

### 6.2 Reference Program Expected Outputs

| Program | Expected Output (summary) |
|---|---|
| `mandelbrot.zig` | 24 lines of ASCII art (deterministic) |
| `game_of_life.zig` | 100 generations of glider pattern (deterministic with clear) |
| `mud.zig` | "MUD server listening on port 4000" (startup verification) |
| `eval.zig` | REPL responds correctly to `(+ 1 2)` → `3` |

### 6.3 Cross-Toolchain Verification

The same generated C89 must compile on all three target toolchains:

```bash
# GCC/MinGW
gcc -std=c89 -pedantic -Wall -Werror -o target *.c

# MSVC 6.0 (on Windows 98 VM)
cl /Za /W3 /WX /Fe:target.exe *.c

# OpenWatcom
wcc386 /za /we *.c
wlink system nt file *.obj name target.exe
```

---

## 7. Layer 5: Memory Gate

### 7.1 Peak Memory Tracking

The compiler's allocator wrapper tracks peak usage:

```zig
pub const TrackingAllocator = struct {
    inner: *Allocator,
    current_bytes: usize,
    peak_bytes: usize,

    pub fn alloc(self: *TrackingAllocator, size: usize) ![]u8 {
        const result = try self.inner.alloc(size);
        self.current_bytes += size;
        if (self.current_bytes > self.peak_bytes) {
            self.peak_bytes = self.current_bytes;
        }
        return result;
    }

    pub fn getPeak(self: *TrackingAllocator) usize {
        return self.peak_bytes;
    }
};
```

### 7.2 Memory Gate Test

```bash
#!/bin/sh
# memory_gate.sh
# Compile zig1's own source and verify peak memory
./zig1 --max-mem=16M --print-peak-mem lib/main.zig -o /tmp/mem_test/
PEAK=$(cat /tmp/mem_test/peak_mem.txt)
if [ "$PEAK" -gt 16777216 ]; then
    echo "FAIL: peak memory ${PEAK} exceeds 16MB"
    exit 1
fi
echo "PASS: peak memory ${PEAK} bytes"
```

---

## 8. Layer 6: Determinism Check

Compile the same source twice with the same flags. All output files must be byte-identical.

```bash
#!/bin/sh
# determinism_test.sh <source.zig>
SOURCE=$1
./zig1 "$SOURCE" -o /tmp/det_a/
./zig1 "$SOURCE" -o /tmp/det_b/

for f in /tmp/det_a/*; do
    base=$(basename "$f")
    cmp -s "$f" "/tmp/det_b/$base"
    if [ $? -ne 0 ]; then
        echo "FAIL: non-deterministic output for $base"
        exit 1
    fi
done
echo "PASS: deterministic output for $SOURCE"
```

This catches: hash-order leakage, pointer-address-dependent output, timestamp embedding, uninitialized memory in output buffers.

---

## 9. Layer 7: Bootstrap Identity Test

```bash
#!/bin/sh
# bootstrap_test.sh

# Stage 1: zig0 compiles zig1 source → zig1.exe
./zig0 lib/main.zig -o /tmp/stage1/
cd /tmp/stage1/ && sh build_target.sh
cp target.exe /tmp/zig1.exe

# Stage 2: zig1 compiles zig1 source → zig2.exe
/tmp/zig1.exe lib/main.zig -o /tmp/stage2/
cd /tmp/stage2/ && sh build_target.sh
cp target.exe /tmp/zig2.exe

# Compare
cmp -s /tmp/zig1.exe /tmp/zig2.exe
if [ $? -ne 0 ]; then
    echo "FAIL: zig1.exe and zig2.exe differ"
    echo "Self-hosting NOT achieved"
    exit 1
fi
echo "PASS: Self-hosting achieved — zig1.exe == zig2.exe"
```

---

## 10. Debug Dump Flags

Both `zig0` and `zig1` support these flags for intermediate inspection:

| Flag | Output | Used By |
|---|---|---|
| `--dump-tokens` | One token per line: `kind span_start span_len [value]` | Layer 2 |
| `--dump-ast` | S-expression canonical format | Layer 2 |
| `--dump-types` | Type registry: `TypeId kind size align name c_name` | Layer 3 |
| `--dump-lir` | Basic blocks with instructions | Layer 3 |
| `--dump-coercions` | Coercion table entries | Debugging |
| `--print-peak-mem` | Write peak bytes to `peak_mem.txt` | Layer 5 |
| `--test-mode` | Deterministic mangling (`z<Kind>_<Counter>_<n>`) | All layers |

---

## 11. Test Execution Scripts

### 11.1 Master Runner

```bash
#!/bin/sh
# run_all_tests.sh
set -e
PASS=0
FAIL=0

run_batch() {
    echo "--- $1 ---"
    if ./$1; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAILED: $1"
    fi
}

# Layer 1: Unit tests
run_batch test_lexer
run_batch test_parser_expr
run_batch test_parser_stmt
run_batch test_parser_types
run_batch test_parser_recovery
run_batch test_type_registry
run_batch test_type_resolver
run_batch test_comptime_eval
run_batch test_semantic
run_batch test_lir_lower
run_batch test_c89_emit

# Layer 2: AST comparison
for f in tests/reference/*.zig; do
    sh scripts/ast_diff_test.sh "$f" && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
done

# Layer 3: C89 output diff
for f in tests/reference/*.zig; do
    sh scripts/c89_diff_test.sh "$f" && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
done

# Layer 4: Compile & run
for f in tests/e2e/*.zig; do
    expected="${f%.zig}.expected"
    sh scripts/e2e_test.sh "$f" "$expected" && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
done

# Layer 5: Memory gate
sh scripts/memory_gate.sh && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# Layer 6: Determinism
for f in tests/reference/*.zig; do
    sh scripts/determinism_test.sh "$f" && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
done

# Layer 7: Bootstrap identity (only if all previous pass)
if [ $FAIL -eq 0 ]; then
    sh scripts/bootstrap_test.sh && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
fi

echo ""
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "=========================================="
exit $FAIL
```

### 11.2 Per-Phase Test Runner (Development)

During development, run only the tests relevant to the current phase:

```bash
#!/bin/sh
# test_phase.sh <phase_number>
case $1 in
    1) # Lexer + Parser
        ./test_lexer && ./test_parser_expr && ./test_parser_stmt && ./test_parser_types
        for f in tests/reference/*.zig; do sh scripts/ast_diff_test.sh "$f"; done
        ;;
    2) # Type System
        ./test_type_registry && ./test_type_resolver
        ;;
    3) # Semantic Analysis
        ./test_comptime_eval && ./test_semantic
        ;;
    4) # LIR Lowering
        ./test_lir_lower
        ;;
    5) # C89 Emitter
        ./test_c89_emit
        for f in tests/reference/*.zig; do sh scripts/c89_diff_test.sh "$f"; done
        for f in tests/e2e/*.zig; do sh scripts/e2e_test.sh "$f" "${f%.zig}.expected"; done
        ;;
    6) # Self-hosting
        sh scripts/memory_gate.sh
        sh scripts/determinism_test.sh lib/main.zig
        sh scripts/bootstrap_test.sh
        ;;
esac
```

---

## 12. Test File Organization

```
tests/
├── unit/
│   ├── test_lexer.zig
│   ├── test_parser_expr.zig
│   ├── test_parser_stmt.zig
│   ├── test_parser_types.zig
│   ├── test_parser_recovery.zig
│   ├── test_type_registry.zig
│   ├── test_type_resolver.zig
│   ├── test_comptime_eval.zig
│   ├── test_semantic.zig
│   ├── test_lir_lower.zig
│   └── test_c89_emit.zig
├── reference/                    # Known-good Z98 programs
│   ├── mandelbrot.zig
│   ├── game_of_life.zig
│   ├── mud.zig
│   └── eval/
│       ├── eval.zig
│       ├── value.zig
│       ├── env.zig
│       ├── util.zig
│       ├── sand.zig
│       └── deep_copy.zig
├── e2e/                          # End-to-end with expected output
│   ├── hello.zig
│   ├── hello.expected
│   ├── fibonacci.zig
│   ├── fibonacci.expected
│   ├── error_handling.zig
│   ├── error_handling.expected
│   ├── tagged_union.zig
│   └── tagged_union.expected
├── negative/                     # Expected-to-fail programs
│   ├── circular_type.zig         # Should produce "circular dependency" error
│   ├── type_mismatch.zig         # Should produce type error
│   ├── break_outside_loop.zig    # Should produce "break outside loop" error
│   └── missing_else.zig          # Should produce "switch requires else" error
└── scripts/
    ├── ast_diff_test.sh
    ├── c89_diff_test.sh
    ├── e2e_test.sh
    ├── memory_gate.sh
    ├── determinism_test.sh
    ├── bootstrap_test.sh
    ├── run_all_tests.sh
    └── test_phase.sh
```
