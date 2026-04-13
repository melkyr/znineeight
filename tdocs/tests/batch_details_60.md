# Z98 Test Batch 60 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 24 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_clone_basic`
- **Implementation Source**: `tests/unit/ast_clone_test.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `cloned not equals null` is satisfied
  2. Validate that `cloned not equals original` is satisfied
  3. Assert that `cloned.type` matches `original.type`
  4. Assert that `cloned.as.integer_literal.value` matches `original.as.integer_literal.value`
  ```

### `test_clone_binary_op`
- **Implementation Source**: `tests/unit/ast_clone_test.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `cloned not equals null` is satisfied
  2. Validate that `cloned not equals bin_op` is satisfied
  3. Assert that `cloned.type` matches `NODE_BINARY_OP`
  4. Validate that `cloned.as.binary_op not equals bin_op.as.binary_op` is satisfied
  5. Validate that `cloned.as.binary_op.left not equals left` is satisfied
  6. Validate that `cloned.as.binary_op.right not equals right` is satisfied
  7. Assert that `cloned.as.binary_op.left.type` matches `NODE_INTEGER_LITERAL`
  8. Assert that `cloned.as.binary_op.left.as.integer_literal.value` matches `10`
  9. Assert that `cloned.as.binary_op.right.as.integer_literal.value` matches `20`
  ```

### `test_clone_range`
- **Implementation Source**: `tests/unit/ast_clone_test.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `cloned not equals null` is satisfied
  2. Validate that `cloned not equals range_node` is satisfied
  3. Assert that `cloned.type` matches `NODE_RANGE`
  4. Validate that `cloned.as.range not equals range_node.as.range` is satisfied
  5. Validate that `cloned.as.range.start not equals start` is satisfied
  6. Validate that `cloned.as.range.end not equals end` is satisfied
  7. Assert that `cloned.as.range.start.type` matches `NODE_INTEGER_LITERAL`
  8. Assert that `cloned.as.range.start.as.integer_literal.value` matches `1`
  9. Assert that `cloned.as.range.end.as.integer_literal.value` matches `10`
  10. Validate that `cloned.as.range.is_inclusive` is satisfied
  ```

### `test_clone_switch_stmt`
- **Implementation Source**: `tests/unit/ast_clone_test.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `cloned not equals null` is satisfied
  2. Validate that `cloned not equals sw_node` is satisfied
  3. Assert that `cloned.type` matches `NODE_SWITCH_STMT`
  4. Validate that `cloned.as.switch_stmt not equals sw_node.as.switch_stmt` is satisfied
  5. Validate that `cloned.as.switch_stmt.expression not equals cond` is satisfied
  6. Validate that `cloned.as.switch_stmt.prongs not equals sw_node.as.switch_stmt.prongs` is satisfied
  7. Assert that `cloned.as.switch_stmt.prongs.length` matches `1`
  8. Validate that `cloned_prong not equals prong` is satisfied
  9. Assert that `cloned_prong.items.length` matches `1`
  10. Assert that `*cloned_prong.items` matches `5`
  11. Assert that `cloned_prong.body.as.integer_literal.value` matches `42`
  ```

### `test_traversal_binary_op`
- **Implementation Source**: `tests/unit/ast_traversal_test.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `visitor.count` matches `2`
  ```

### `test_traversal_block`
- **Implementation Source**: `tests/unit/ast_traversal_test.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `visitor.count` matches `3`
  ```

### `test_traversal_range`
- **Implementation Source**: `tests/unit/ast_traversal_test.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `visitor.count` matches `2`
  ```

### `test_traversal_switch_stmt`
- **Implementation Source**: `tests/unit/ast_traversal_test.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `visitor.count` matches `3`
  ```

### `test_Parser_SwitchStatement_Basic`
- **Implementation Source**: `tests/unit/parser_switch_stmt_test.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
switch (x) { 1 => { foo(); }, else => { bar(); } }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_SWITCH_STMT` matches `node.type`
  3. Assert that `NODE_IDENTIFIER` matches `switch_node.expression.type`
  4. Assert that `2` matches `switch_node.prongs.length`
  5. Validate that `!prong1.is_else` is satisfied
  6. Assert that `1` matches `prong1.items.length`
  7. Assert that `NODE_INTEGER_LITERAL` matches `*prong1.items)[0].type`
  8. Assert that `NODE_BLOCK_STMT` matches `prong1.body.type`
  9. Validate that `prong2.is_else` is satisfied
  10. Assert that `NODE_BLOCK_STMT` matches `prong2.body.type`
  ```

### `test_Parser_Switch_InclusiveRange`
- **Implementation Source**: `tests/unit/parser_switch_stmt_test.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
switch (x) { 1...10 => {}, else => {}, }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_SWITCH_STMT` matches `node.type`
  3. Assert that `1` matches `prong1.items.length`
  4. Assert that `NODE_RANGE` matches `item.type`
  5. Validate that `item.as.range.is_inclusive` is satisfied
  6. Assert that `u64` matches `item.as.range.start.as.integer_literal.value`
  7. Assert that `u64` matches `item.as.range.end.as.integer_literal.value`
  ```

### `test_Parser_Switch_ExclusiveRange`
- **Implementation Source**: `tests/unit/parser_switch_stmt_test.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
switch (x) { 1..10 => {}, else => {}, }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_SWITCH_STMT` matches `node.type`
  3. Assert that `NODE_RANGE` matches `item.type`
  4. Validate that `!item.as.range.is_inclusive` is satisfied
  5. Assert that `u64` matches `item.as.range.start.as.integer_literal.value`
  6. Assert that `u64` matches `item.as.range.end.as.integer_literal.value`
  ```

### `test_Parser_Switch_MixedItems`
- **Implementation Source**: `tests/unit/parser_switch_stmt_test.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
switch (x) { 1, 3...5, 10 => {}, else => {}, }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `3` matches `prong1.items.length`
  3. Assert that `NODE_INTEGER_LITERAL` matches `*prong1.items)[0].type`
  4. Assert that `NODE_RANGE` matches `*prong1.items)[1].type`
  5. Assert that `NODE_INTEGER_LITERAL` matches `*prong1.items)[2].type`
  ```

### `test_Parser_Switch_ExpressionContext`
- **Implementation Source**: `tests/unit/parser_switch_stmt_test.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
var x = switch (y) { else => 42 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_VAR_DECL` matches `node.type`
  3. Validate that `init not equals null` is satisfied
  4. Assert that `NODE_SWITCH_EXPR` matches `init.type`
  ```

### `test_RangeSwitch_InclusiveBasic`
- **Implementation Source**: `tests/integration/range_switch_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis, Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: i32) void { switch (x) { 1...3 => {}, else => {}, } }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  2. Validate that `output.find("switch"` is satisfied
  ```

### `test_RangeSwitch_ExclusiveBasic`
- **Implementation Source**: `tests/integration/range_switch_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: i32) void { switch (x) { 1..3 => {}, else => {}, } }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  ```

### `test_RangeSwitch_MixedItems`
- **Implementation Source**: `tests/integration/range_switch_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: i32) void { switch (x) { 1, 3...5, 10 => {}, else => {}, } }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  ```

### `test_RangeSwitch_ErrorNonConstant`
- **Implementation Source**: `tests/integration/range_switch_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: i32, y: i32) void { switch (x) { 1...y => {}, else => {}, } }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `unit.getErrorHandler` is satisfied
  2. Assert that `unit.getErrorHandler` matches `ERR_NONCONSTANT_RANGE`
  ```

### `test_RangeSwitch_ErrorTooLarge`
- **Implementation Source**: `tests/integration/range_switch_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: i32) void { switch (x) { 1...2000 => {}, else => {}, } }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `unit.getErrorHandler` is satisfied
  2. Assert that `unit.getErrorHandler` matches `ERR_RANGE_TOO_LARGE`
  ```

### `test_RangeSwitch_ErrorEmpty`
- **Implementation Source**: `tests/integration/range_switch_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: i32) void { switch (x) { 5...3 => {}, else => {}, } }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `unit.getErrorHandler` is satisfied
  2. Assert that `unit.getErrorHandler` matches `ERR_INVALID_RANGE`
  ```

### `test_RangeSwitch_EnumRange`
- **Implementation Source**: `tests/integration/range_switch_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: i32) i32 {
    return switch (x) {
        1...2 => 1,
        else => 0,
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  ```

### `test_RangeSwitch_NestedControl`
- **Implementation Source**: `tests/integration/range_switch_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: i32, y: bool) void {
    switch (x) {
        1...5 => {
            if (y) return;
        },
        else => {},
    }
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  2. Assert that `sw.type` matches `NODE_SWITCH_STMT`
  3. Assert that `prong_body.type` matches `NODE_BLOCK_STMT`
  4. Validate that `prong_body.as.block_stmt.statements.length` is satisfied
  ```

### `test_RangeSwitch_NegativeValues`
- **Implementation Source**: `tests/integration/range_switch_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: i32) void { switch (x) { -5...5 => {}, else => {}, } }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  ```

### `test_RangeSwitch_ExclusiveEmpty`
- **Implementation Source**: `tests/integration/range_switch_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: i32) void { switch (x) { 1..1 => {}, else => {}, } }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `unit.getErrorHandler` is satisfied
  2. Assert that `unit.getErrorHandler` matches `ERR_INVALID_RANGE`
  ```

### `test_RangeSwitch_EnumActualRange`
- **Implementation Source**: `tests/integration/range_switch_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const Color = enum { Red, Green, Blue };
fn foo(c: Color) i32 {
    return switch (c) {
        Color.Red...Color.Green => 1,
        Color.Blue => 2,
        else => 0,
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `unit.getErrorHandler` is false
  ```
