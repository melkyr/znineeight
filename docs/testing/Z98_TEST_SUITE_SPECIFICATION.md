# Z98 Test Suite Specification

This document provides an extensive specification of the Z98 compiler test suite. It documents what is being tested and how, using pseudocode to describe the test logic. This serves as a reference for implementing `zig1`.

---

## 1. Core Infrastructure & Memory Management

### 1.1 Arena Allocation (Batch 1, 9)
**Goal**: Verify deterministic, leak-free memory management with strict alignment and overflow protection.

- **Alignment**:
  ```pseudocode
  create arena(1KB)
  for i in 1..10:
    p = arena.alloc(rand(1, 100))
    assert (p % 8) == 0
  ```
- **Hard Limit Protection**:
  ```pseudocode
  create arena with 16MB limit
  arena.alloc(17MB)
  assert process_aborts_with("FATAL: Memory limit exceeded")
  ```
- **Reset and Reuse**:
  ```pseudocode
  create arena
  p1 = arena.alloc(100)
  arena.reset()
  p2 = arena.alloc(100)
  assert p1 == p2
  ```

### 1.2 Dynamic Arrays (Batch 1)
**Goal**: Verify safe growth and copy semantics for POD and non-POD types.

- **Growth Heuristics**:
  ```pseudocode
  arr = DynamicArray<i32>(arena, 0)
  for i in 1..100:
    arr.append(i)
  assert arr.length == 100
  assert arr.capacity >= 100
  ```

---

## 2. Lexical Analysis (Batch 1, 2)

### 2.1 Numeric Literals
**Goal**: Verify precise parsing of integers and floats with Z98-specific syntax.

- **Range Ambiguity**:
  ```pseudocode
  lexer.init("0..10")
  assert lexer.next().type == TOKEN_INTEGER(0)
  assert lexer.next().type == TOKEN_RANGE("..")
  assert lexer.next().type == TOKEN_INTEGER(10)
  ```
- **Underscores and Bases**:
  ```pseudocode
  lexer.init("1_000_000 0x123_abc 0b101_010")
  assert lexer.next().int_value == 1000000
  assert lexer.next().int_value == 0x123abc
  assert lexer.next().int_value == 42
  ```

### 2.2 Comments and Character Handling
- **Nested Block Comments**:
  ```pseudocode
  lexer.init("/* outer /* inner */ outer */ +")
  assert lexer.next().type == TOKEN_PLUS
  ```
- **Unicode in Literals**:
  ```pseudocode
  lexer.init("\"UTF-8: \u2713\"")
  assert lexer.next().string_content == "UTF-8: \u2713"
  ```

---

## 3. Parsing & AST Construction (Batch 2, 46, 58, 61, 63)

### 3.1 Operator Precedence & Associativity
**Goal**: Ensure the parser builds the correctly weighted AST tree.

- **Arithmetic and Logical**:
  ```pseudocode
  parser.init("a + b * c == d or e")
  ast = parser.parse()
  assert ast.type == OR
  assert ast.left.type == EQUAL_EQUAL
  assert ast.left.left.type == PLUS
  ```

### 3.2 Control Flow Bracelessness
- **Normalized Blocks**:
  ```pseudocode
  parser.init("if (c) return;")
  ast = parser.parse()
  assert ast.type == NODE_IF
  assert ast.then_branch.type == NODE_BLOCK
  assert ast.then_branch.statements[0].type == NODE_RETURN
  ```

---

## 4. Type System & Checking (Batch 3, 6, 38, 45, 47, 74, 80)

### 4.1 Type Inference & Implicit Rules
- **Constant Folding**:
  ```pseudocode
  type_checker.init("const x = 1 + 2 * 3;")
  ast = type_checker.check()
  assert ast.initializer.is_constant == true
  assert ast.initializer.int_value == 7
  ```
- **Pointer Coercion**:
  ```pseudocode
  type_checker.init("var p: *void = @ptrCast(*i32, x);")
  assert type_checker.check() == SUCCESS
  ```

### 4.2 Slices (Batch 40, 66)
**Goal**: Verify slice mechanics and ABI compatibility.

- **Slicing Syntax**:
  ```pseudocode
  type_checker.init("var arr: [5]i32; var s = arr[1..4];")
  ast = type_checker.check()
  assert ast.s.resolved_type == []i32
  assert ast.s.base_ptr == &arr[1]
  assert ast.s.len == 3
  ```

### 4.3 Tagged Unions (Batch 65, 69, 80, 9b)
- **Naked Tag Coercion**:
  ```pseudocode
  type_checker.init("const U = union(enum) { A, B }; var u: U = .A;")
  assert type_checker.check() == SUCCESS
  ```
- **Switch Payload Capture**:
  ```pseudocode
  type_checker.init("switch (u) { .A => | val | { ... } }")
  type_checker.check()
  assert symbol("val").type == U.A_type
  ```

---

## 5. Static Analyzers (Batch 5, 7, 75, 252, 253)

### 5.1 Double Free Detection
- **Path-Awareness**:
  ```pseudocode
  analyzer.init("if (c) p.free(); else p.free(); p.free();")
  assert analyzer.check() == ERR_DOUBLE_FREE
  ```
- **Loop Uncertainty**:
  ```pseudocode
  analyzer.init("while (c) { p.free(); }")
  assert analyzer.check() == WARN_POTENTIAL_DOUBLE_FREE // because of 2nd iteration
  ```

### 5.2 Null Pointer Analysis
- **Guard Resolution**:
  ```pseudocode
  analyzer.init("if (p != null) { p.* = 1; }")
  assert analyzer.check() == SUCCESS // p is known SAFE inside if
  ```

---

## 6. Code Generation & AST Lifting (Batch 26-31, 44, 55, 65)

### 6.1 Control-Flow Lifting
**Goal**: Ensure Zig's expression-based features are safely hoisted for C89.

- **If-Expression Lifting**:
  ```pseudocode
  lifter.init("var x = if (c) f() else g();")
  lifter.lift()
  assert root.statements[0].type == NODE_VAR_DECL("__tmp_1")
  assert root.statements[1].type == NODE_IF(c, {__tmp_1 = f()}, {__tmp_1 = g()})
  assert root.statements[2].type == NODE_ASSIGNMENT(x, "__tmp_1")
  ```

### 6.2 C89 Compatibility Patterns
- **Two-Pass Block Emission**:
  ```pseudocode
  emitter.init("{ var x = 1; f(); var y = 2; }")
  emitter.emit()
  assert output_starts_with("{ int x; int y; x = 1; f(); y = 2; }")
  ```

---

## 7. Multi-Module System (Batch 33, 34, 35, 73)

### 7.1 Import Resolution & Topological Sorting
- **Circular Imports**:
  ```pseudocode
  fileA: "@import(\"B.zig\")"
  fileB: "@import(\"A.zig\")"
  assert compiler.topological_sort([A, B]) == [B, A] // or [A, B], ensuring no infinite loop
  ```

### 7.2 Cross-Module Visibility
- **Pub Enforcement**:
  ```pseudocode
  fileA: "fn f() {}"
  fileB: "@import(\"A.zig\").f()"
  assert type_checker.check(B) == ERR_SYMBOL_NOT_PUBLIC
  ```

---

## 8. C89 Compliance Validation (Batch 17)

### 8.1 MSVC 6.0 Restrictions
- **Identifier Length**:
  ```pseudocode
  validator.init("const a_very_long_name_exceeding_31_chars = 1;")
  assert validator.check_msvc6() == false // Warning or Error
  ```
- **C++ Comment Rejection**:
  ```pseudocode
  validator.init("int x; // comment")
  assert validator.check_msvc6() == false
  ```

---

## 9. Test Batch Inventory (Detailed Coverage)

| Batch | Component | Focus Areas |
|-------|-----------|-------------|
| [1](../../tdocs/tests/batch_details_1.md) |Infrastructure|Arena Allocator, Dynamic Array, Symbol Table|
| [2-3](../../tdocs/tests/batch_details_2.md) |Lexer/Type|AST nodes, Basic type inference, C89 integer compatibility|
| [4](../../tdocs/tests/batch_details_4.md) |Safety|Token stability, C89 rejection of try/catch/slice|
| [5](../../tdocs/tests/batch_details_5.md) |Analyzer|Double free, memory leaks, uninitialized free|
| [6](../../tdocs/tests/batch_details_6.md) |Type System|Struct declarations, member access, initializer validation|
| [7](../../tdocs/tests/batch_details_7.md) |Error Handling|Detection of error functions, try/catch/orelse cataloguing|
| [8](../../tdocs/tests/batch_details_8.md) |Comptime|Rejection of generics, anytype, type params|
| [9](../../tdocs/tests/batch_details_9.md) |Platform|Platform-specific IO, File, Alloc, Module derivation|
| [10](../../tdocs/tests/batch_details_10.md) |Mangler|Simple/Generic mangling, keyword collision, determinism|
| [11](../../tdocs/tests/batch_details_11.md) |Imports|Modular parsing, symbol lookup across files|
| [12-16](../../tdocs/tests/batch_details_12.md) |Parser|Expression precedence, Statements, Declarations|
| [17](../../tdocs/tests/batch_details_17.md) |Validation|C89/MSVC 6.0 strictness checks|
| [18](../../tdocs/tests/batch_details_18.md) |Switch|Switch expressions and statement lowering|
| [20](../../tdocs/tests/batch_details_20.md) |Casts|@ptrCast, @intCast, @floatCast validation|
| [21](../../tdocs/tests/batch_details_21.md) |Builtins|@sizeOf, @alignOf, @offsetOf constant folding|
| [25-27](../../tdocs/tests/batch_details_25.md) |Codegen|Local/Global variables, String literals|
| [28](../../tdocs/tests/batch_details_28.md) |Call Sites|Resolution, Mutual recursion, Indirect call rejection|
| [29-31](../../tdocs/tests/batch_details_29.md) |Codegen|Binary/Unary ops, Member access, Array indexing|
| [32](../../tdocs/tests/batch_details_32.md) |End-to-End|Hello World, Prime Sieve (full pipeline)|
| [33-35](../../tdocs/tests/batch_details_33.md) |Multi-Module|Circular imports, Private visibility, Include paths|
| [36-37](../../tdocs/tests/batch_details_36.md) |Pointers|Multi-level pointers (**T), Many-item pointers ([*]T)|
| [38](../../tdocs/tests/batch_details_38.md) |Func Pointers|Signature matching, coercion, indirect calls|
| [39](../../tdocs/tests/batch_details_39.md) |Defer|LIFO execution, Return/Break/Continue interaction|
| [40](../../tdocs/tests/batch_details_40.md) |Slices|Indexing, .len, Array-to-slice coercion, slicing syntax|
| [41-42](../../tdocs/tests/batch_details_41.md) |For Loops|Array/Slice/Range iteration, Captures, Mutability|
| [43](../../tdocs/tests/batch_details_43.md) |Switch|Noreturn prongs, divergent control flow|
| [44](../../tdocs/tests/batch_details_44.md) |If/Print|Braceless if-expr, std.debug.print lowering|
| [45-46](../../tdocs/tests/batch_details_45.md) |Error Union|!T representation, Try/Catch lifting (revised)|
| [47](../../tdocs/tests/batch_details_47.md) |Optionals|?T, null, orelse, if-capture unwrapping|
| [48-50](../../tdocs/tests/batch_details_48.md) |Recursion|Recursive structs/slices, multi-module recursion|
| [51](../../tdocs/tests/batch_details_51.md) |Unions|Tagged union captures, nested anonymous structs|
| [53](../../tdocs/tests/batch_details_53.md) |Metadata|Transitively reachable types, post-order dependency traversal|
| [54-55](../../tdocs/tests/batch_details_54.md) |AST/Lifter|Deep cloning, Control-flow expression hoisting|
| [56-57](../../tdocs/tests/batch_details_56.md) |Advanced|Union/Slice lifting, Anonymous aggregate emission|
| [58, 61](../../tdocs/tests/batch_details_58.md) |Braceless|Braceless if/while/for normalization|
| [63-65](../../tdocs/tests/batch_details_63.md) |Tagged Unions|Naked tags, Implicit enums, Field-wise assignment|
| [66-68](../../tdocs/tests/batch_details_66.md) |Slices/Strings|Private nested slices, String literal to ManyPtr coercion|
| [70-71](../../tdocs/tests/batch_details_70.md) |Unreachable|Dead code elimination, Error union recursion|
| [73](../../tdocs/tests/batch_details_73.md) |Recursion|Value dependency cycles, Pointer dependency forward-decls|
| [74-75](../../tdocs/tests/batch_details_74.md) |Initialization|Tagged union nested struct init, Field-level leak tracking|
| [80](../../tdocs/tests/batch_details_80.md) |Complex Expr|Tagged union array decomposition, Nested switch/if expr|
| [_bugs](../../tdocs/tests/batch_details__bugs.md) |Regressions|String split, For-ptr-to-array, Nested switch lifter|
