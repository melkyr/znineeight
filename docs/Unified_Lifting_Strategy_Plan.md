# Unified Lifting Mechanism Plan

This plan is designed for your **Windows 98 / 16MB RAM / MSVC 6.0** constraints. The goal is to unify lifting without increasing memory pressure or stack usage.

---

## Part 1: Understanding the Current Problem

### Current State
You have **5 separate lifting functions** that duplicate ~80% of their logic:

| Function | Lines | Duplicates |
| :--- | :--- | :--- |
| `emitTryExpr` | ~60 | Block, indent, defer, temp var, assignment |
| `emitCatchExpr` | ~50 | Block, indent, defer, temp var, assignment |
| `emitOrelseExpr` | ~50 | Block, indent, defer, temp var, assignment |
| `emitIfExpr` | ~70 | Block, indent, defer, temp var, assignment |
| `emitSwitchExpr` | ~100 | Block, indent, defer, temp var, assignment |

**Total**: ~330 lines of duplicated lifting logic.

### Core Issues
1. **Manual State Management**: `indent()`, `dedent()`, `defer_stack_.append/pop` are error-prone.
2. **Inconsistent Nesting**: `try` can't nest in `catch`, `if` can't nest in `try` operand.
3. **Assignment Limitations**: Only `NODE_IDENTIFIER` lvalues trigger lifting.
4. **Missing Coverage**: `emitBlockWithAssignment` omits `NODE_ORELSE_EXPR`.

---

## Part 2: The Unified Architecture

### Concept: `LiftContext`
Create a single structure that manages the lifting lifecycle. All lifting functions will delegate to a central `emitLiftedExpression` function.

```cpp
// Pseudocode: LiftContext (stack-only, ~16 bytes)
struct LiftContext {
    C89Emitter* emitter;
    const char* target_var;      // NULL if side-effects only
    Type* result_type;           // Type of the expression being lifted
    int label_id;                // For defer scope tracking
    bool needs_temp;             // True if we need a temp variable
    const char* temp_var;        // Name of temp var (e.g., "__try_res")
    bool emits_block;            // True if we wrap in { }
    
    // Constructor: Setup state
    __forceinline LiftContext(C89Emitter* e, const char* target, Type* type, int label)
        : emitter(e), target_var(target), result_type(type), label_id(label),
          needs_temp(false), temp_var(NULL), emits_block(true) {}
    
    // Destructor: Cleanup state (RAII)
    __forceinline ~LiftContext() {
        // Automatically dedent and pop defer stack if needed
        if (emits_block) {
            emitter->defer_stack_.pop_back();
            emitter->dedent();
            emitter->writeIndent();
            emitter->writeString("}");
        }
    }
    
    // Begin the lifting block
    __forceinline void begin() {
        if (emits_block) {
            emitter->writeIndent();
            emitter->writeString("{\n");
            emitter->indent();
            
            DeferScope* scope = (DeferScope*)emitter->arena_.alloc(sizeof(DeferScope));
            new (scope) DeferScope(emitter->arena_, label_id);
            emitter->defer_stack_.append(scope);
        }
    }
    
    // Create a temp variable if needed
    const char* createTempVar(const char* prefix) {
        if (!needs_temp && target_var) {
            needs_temp = true;
            temp_var = emitter->var_alloc_.generate(prefix);
            emitter->writeIndent();
            emitter->emitType(result_type, temp_var);
            emitter->writeString(" = ");
        }
        return temp_var;
    }
    
    // Assign to target if we have one
    __forceinline void assignToTarget(const char* value_expr) {
        if (target_var) {
            emitter->writeIndent();
            emitter->writeString(target_var);
            emitter->writeString(" = ");
            emitter->writeString(value_expr);
            emitter->writeString(";\n");
        }
    }
};
```

---

## Part 3: Step-by-Step Refactoring Plan

### Phase 1: Infrastructure (Week 1)
**Goal**: Add the `LiftContext` helper without changing existing lifting functions.

#### Task 1.1: Add `LiftContext` to `codegen.cpp`
```cpp
// Add this class inside codegen.cpp (private to compilation unit)
struct LiftContext {
    C89Emitter* emitter;
    const char* target_var;
    Type* result_type;
    int label_id;
    bool opened;
    
    __forceinline LiftContext(C89Emitter* e, const char* target, Type* type, int label)
        : emitter(e), target_var(target), result_type(type), label_id(label), opened(false) {}
    
    __forceinline void open() {
        if (opened) return;
        opened = true;
        emitter->writeIndent();
        emitter->writeString("{\n");
        emitter->indent();
        
        DeferScope* scope = (DeferScope*)emitter->arena_.alloc(sizeof(DeferScope));
        new (scope) DeferScope(emitter->arena_, label_id);
        emitter->defer_stack_.append(scope);
    }
    
    __forceinline void close() {
        if (!opened) return;
        opened = false;
        emitter->defer_stack_.pop_back();
        emitter->dedent();
        emitter->writeIndent();
        emitter->writeString("}");
    }
    
    __forceinline ~LiftContext() {
        close();
    }
};
```

#### Task 1.2: Add Recursion Depth Guard
```cpp
// Add to C89Emitter members in codegen.hpp
int lifting_depth_;
static const int MAX_LIFTING_DEPTH = 50;

// In C89Emitter constructor
: lifting_depth_(0) { ... }

// In emitLiftedExpression (new function)
void C89Emitter::emitLiftedExpression(const ASTNode* node, const char* target_var, int label_id) {
    lifting_depth_++;
    if (lifting_depth_ > MAX_LIFTING_DEPTH) {
        error_handler_.report(ERR_STACK_OVERFLOW, node->loc, "Lifting depth exceeded");
        lifting_depth_--;
        return;
    }
    
    // ... actual lifting logic ...
    
    lifting_depth_--;
}
```

**Memory Impact**: +4 bytes per `C89Emitter` instance (stack member).

---

### Phase 2: Centralize Lifting Logic (Week 2)
**Goal**: Create `emitLiftedExpression` that handles all construct types.

#### Task 2.1: Create the Unified Dispatcher
```cpp
// Pseudocode: emitLiftedExpression
void C89Emitter::emitLiftedExpression(const ASTNode* node, const char* target_var, int label_id) {
    if (!node) return;
    
    LiftContext ctx(this, target_var, node->resolved_type, label_id);
    ctx.open();
    
    switch (node->type) {
        case NODE_TRY_EXPR:
            emitLiftedTryExpr(node, &ctx);
            break;
        case NODE_CATCH_EXPR:
            emitLiftedCatchExpr(node, &ctx);
            break;
        case NODE_ORELSE_EXPR:
            emitLiftedOrelseExpr(node, &ctx);
            break;
        case NODE_IF_EXPR:
            emitLiftedIfExpr(node, &ctx);
            break;
        case NODE_SWITCH_EXPR:
            emitLiftedSwitchExpr(node, &ctx);
            break;
        case NODE_BLOCK_STMT:
            emitBlockWithAssignment(&node->as.block_stmt, target_var, label_id);
            ctx.opened = false; // Block handles its own close
            break;
        default:
            // Simple expression, no lifting needed
            if (target_var) {
                writeIndent();
                writeString(target_var);
                writeString(" = ");
                emitExpression(node);
                writeString(";\n");
            } else {
                emitExpression(node);
            }
            ctx.opened = false; // No block was opened
            break;
    }
}
```

#### Task 2.2: Refactor `emitTryExpr` to Use Context
```cpp
// Pseudocode: emitLiftedTryExpr
void C89Emitter::emitLiftedTryExpr(const ASTNode* node, LiftContext* ctx) {
    const ASTTryExprNode& try_node = node->as.try_expr;
    Type* inner_type = try_node.expression->resolved_type;
    
    // Create temp var for the try result
    const char* temp_var = var_alloc_.generate("__try_res");
    writeIndent();
    emitType(inner_type, temp_var);
    writeString(" = ");
    emitExpression(try_node.expression);
    writeString(";\n");
    
    // Error check
    writeIndent();
    writeString("if (");
    writeString(temp_var);
    writeString(".is_error) {\n");
    indent();
    
    // Emit defers and return
    emitDefersForScopeExit(-1);
    writeIndent();
    if (current_fn_ret_type_->kind == TYPE_ERROR_UNION) {
        writeString("return ");
        writeString(temp_var);
        writeString(";\n");
    } else {
        writeString("return;\n");
    }
    
    dedent();
    writeIndent();
    writeString("}\n");
    
    // Assign payload to target
    if (ctx->target_var) {
        writeIndent();
        writeString(ctx->target_var);
        writeString(" = ");
        if (inner_type->as.error_union.payload->kind != TYPE_VOID) {
            writeString(temp_var);
            writeString(".data.payload");
        } else {
            writeString("0");
        }
        writeString(";\n");
    }
    
    // ctx->close() called automatically by destructor
}
```

**Memory Impact**: `LiftContext` is 20 bytes on stack (5 pointers/ints). Negligible.

---

### Phase 3: Fix Nesting Support (Week 3)
**Goal**: Ensure all lifting functions can call `emitLiftedExpression` recursively.

#### Task 3.1: Update Nesting Matrix
Current limitations (from design doc):

| Outer \ Inner | `if` | `switch` | `try` | `catch` | `orelse` |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **`try` operand** | ✗ | ✗ | ✗ | ✗ | ✗ |
| **`catch` fallback** | ✓ | ✓ | ✗ | ✗ | ✗ |

**Fix**: All inner expressions should call `emitLiftedExpression` instead of `emitExpression`.

```cpp
// Pseudocode: emitLiftedCatchExpr
void C89Emitter::emitLiftedCatchExpr(const ASTNode* node, LiftContext* ctx) {
    const ASTCatchExprNode* catch_node = node->as.catch_expr;
    Type* inner_type = catch_node->payload->resolved_type;
    
    const char* temp_var = var_alloc_.generate("__catch_res");
    writeIndent();
    emitType(inner_type, temp_var);
    writeString(" = ");
    emitExpression(catch_node->payload);  // Payload should NOT be lifted
    writeString(";\n");
    
    writeIndent();
    writeString("if (");
    writeString(temp_var);
    writeString(".is_error) {\n");
    indent();
    
    // Error capture
    if (catch_node->error_name) {
        writeIndent();
        writeString("int ");
        writeString(catch_node->error_name);
        writeString(" = ");
        writeString(temp_var);
        writeString(".err;\n");
    }
    
    // Fallback: Use emitLiftedExpression for full nesting support
    if (ctx->target_var) {
        emitLiftedExpression(catch_node->else_expr, ctx->target_var, ctx->label_id);
    } else {
        emitLiftedExpression(catch_node->else_expr, NULL, ctx->label_id);
    }
    
    dedent();
    writeIndent();
    writeString("} else {\n");
    indent();
    
    if (ctx->target_var) {
        writeIndent();
        writeString(ctx->target_var);
        writeString(" = ");
        writeString(temp_var);
        writeString(".data.payload;\n");
    }
    
    dedent();
    writeIndent();
    writeString("}\n");
}
```

#### Task 3.2: Fix `emitBlockWithAssignment`
```cpp
// Pseudocode: Update the last-statement handling
if (i == node->statements->length() - 1 && target_var &&
    stmt->type != NODE_EXPRESSION_STMT &&
    stmt->type != NODE_IF_STMT && stmt->type != NODE_WHILE_STMT &&
    stmt->type != NODE_FOR_STMT && stmt->type != NODE_RETURN_STMT &&
    stmt->type != NODE_BREAK_STMT && stmt->type != NODE_CONTINUE_STMT &&
    stmt->type != NODE_UNREACHABLE) {
    
    // OLD: Manual switch for each type
    // NEW: Unified call
    emitLiftedExpression(stmt, target_var, label_id);
    
} else {
    emitStatement(stmt);
}
```

**Benefit**: Now `NODE_ORELSE_EXPR` is automatically supported (was missing before).

---

### Phase 4: Assignment Target Unification (Week 4)
**Goal**: Support non-identifier lvalues (e.g., `s.x = try foo()`).

#### Task 4.1: Create Temp for Complex Lvalues
```cpp
// Pseudocode: emitStatement NODE_ASSIGNMENT case
case NODE_ASSIGNMENT: {
    const ASTNode* lvalue = node->as.assignment->lvalue;
    const ASTNode* rvalue = node->as.assignment->rvalue;
    
    // Check if rvalue needs lifting
    bool needs_lifting = (rvalue->type == NODE_TRY_EXPR ||
                          rvalue->type == NODE_CATCH_EXPR ||
                          rvalue->type == NODE_ORELSE_EXPR ||
                          rvalue->type == NODE_IF_EXPR ||
                          rvalue->type == NODE_SWITCH_EXPR);
    
    if (needs_lifting) {
        if (lvalue->type == NODE_IDENTIFIER && lvalue->as.identifier.symbol) {
            // Simple case: direct lifting
            const char* target = var_alloc_.allocate(lvalue->as.identifier.symbol);
            emitLiftedExpression(rvalue, target, -1);
        } else {
            // Complex lvalue: use temp var
            const char* temp = var_alloc_.generate("__assign_tmp");
            emitLiftedExpression(rvalue, temp, -1);
            
            // Then assign temp to lvalue
            writeIndent();
            emitExpression(lvalue);
            writeString(" = ");
            writeString(temp);
            writeString(";\n");
        }
    } else {
        // No lifting needed
        writeIndent();
        emitExpression(node);
        writeString(";\n");
    }
    break;
}
```

**Memory Impact**: +1 temp variable per complex assignment (allocated in `var_alloc_`, freed per function).

---

### Phase 5: Cleanup and Deduplication (Week 5)
**Goal**: Remove old functions, update all call sites.

#### Task 5.1: Update Call Sites
| Old Function | New Call |
| :--- | :--- |
| `emitTryExpr(node, target)` | `emitLiftedExpression(node, target, label_id)` |
| `emitCatchExpr(node, target)` | `emitLiftedExpression(node, target, label_id)` |
| `emitOrelseExpr(node, target)` | `emitLiftedExpression(node, target, label_id)` |
| `emitIfExpr(node, target)` | `emitLiftedExpression(node, target, label_id)` |
| `emitSwitchExpr(node, target)` | `emitLiftedExpression(node, target, label_id)` |

#### Task 5.2: Remove Old Functions
```cpp
// Delete these from codegen.cpp:
// - emitTryExpr (keep emitLiftedTryExpr as private helper)
// - emitCatchExpr (keep emitLiftedCatchExpr as private helper)
// - emitOrelseExpr (keep emitLiftedOrelseExpr as private helper)
// - emitIfExpr (keep emitLiftedIfExpr as private helper)
// - emitSwitchExpr (keep emitLiftedSwitchExpr as private helper)
```

#### Task 5.3: Update `emitExpression`
```cpp
// In emitExpression switch, remove lifting cases:
case NODE_SWITCH_EXPR:
    // OLD: writeString("/* error: switch expression used in unsupported context */");
    // NEW: This should never be called for lifting contexts
    writeString("/* error: switch must be lifted */");
    break;
```

---

## Part 4: Memory and Stack Analysis

### Stack Usage Per Lift
| Component | Size | Notes |
| :--- | :--- | :--- |
| `LiftContext` | 20 bytes | 5 ints/pointers on stack |
| `DeferScope*` | 4 bytes | Pointer in context |
| Recursion Guard | 4 bytes | `lifting_depth_` member |
| **Total Per Lift** | **~28 bytes** | Negligible for 1MB stack |

### Heap (Arena) Usage
| Component | Size | Notes |
| :--- | :--- | :--- |
| `DeferScope` | ~32 bytes | Allocated per lifted block |
| Temp Var Names | ~16 bytes | From `var_alloc_` (reset per fn) |
| **Total Per Function** | **~500 bytes** | Well within 16MB limit |

### Code Size Impact
| Change | Before | After | Delta |
| :--- | :--- | :--- | :--- |
| Lifting Functions | ~330 lines | ~200 lines | **-130 lines** |
| `LiftContext` Class | 0 | ~40 lines | +40 lines |
| **Net** | | | **-90 lines** |

**Result**: Smaller `.exe` size, which is better for instruction cache on old hardware.

---

## Part 5: Testing Strategy

### Phase 1 Tests (Infrastructure)
```zig
// Test 1: Basic lifting still works
const x = try foo();
const y = if (a) 1 else 2;
const z = switch (b) { 1 => 10, else => 20 };
```

### Phase 2 Tests (Nesting)
```zig
// Test 2: Nested lifting
const x = try (if (a) foo() else bar());
const y = (try foo()) catch |err| (if (err) 1 else 2);
```

### Phase 3 Tests (Complex Lvalues)
```zig
// Test 3: Non-identifier lvalues
struct { x: i32 } s;
s.x = try foo();
array[0] = if (a) 1 else 2;
```

### Phase 4 Tests (Return with Lifting)
```zig
// Test 4: Return expressions
return try foo();
return if (a) 1 else 2;
```

---

## Part 6: MSVC 6.0 Compatibility Notes

### Compiler Flags
```
/O1          ; Optimize for size (critical for W98)
/Oy          ; Omit frame pointer (saves stack)
/GX-         ; Disable exceptions (no overhead)
/GR-         ; Disable RTTI (no vtable bloat)
/W4          ; High warning level
```

### Code Patterns to Avoid
```cpp
// BAD: Virtual functions (vtable overhead)
struct LiftContext { virtual ~LiftContext() {} };

// GOOD: Plain struct with inline destructor
struct LiftContext { __forceinline ~LiftContext() {} };

// BAD: STL containers (heap fragmentation)
std::vector<const char*> targets;

// GOOD: DynamicArray with arena
DynamicArray<const char*> targets(arena_);

// BAD: Exception handling
try { ... } catch (...) { ... }

// GOOD: Error codes and early returns
if (!node) return;
```

## Summary

This plan gives you:
1. **Unified lifting logic** (90 lines less code)
2. **Consistent nesting support** (all constructs can nest in all others)
3. **Complex lvalue support** (struct members, array elements)
4. **RAII safety** (no indent/defer desync)
5. **Zero memory overhead** (stack-only `LiftContext`, 28 bytes per lift)
6. **MSVC 6.0 compatible** (no exceptions, no RTTI, `__forceinline`)

Start with **Phase 1** this week. Add the `LiftContext` struct but don't change any existing functions. Run your test suite to ensure the infrastructure doesn't break anything. Then proceed to Phase 2.
