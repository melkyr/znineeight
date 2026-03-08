# Unified Control-Flow Lifting Strategy
## Design Document — Milestone 8 (Z98 Bootstrap Compiler)

**Version**: 1.1
**Target**: Windows 98 / 16MB RAM / MSVC 6.0 / C++98  
**Author**: Compiler Team  
**Status**: Implemented (Task 232)

---

## 1. Executive Summary

This document defines the **unified lifting strategy** for transforming expression-valued control-flow constructs (`if`, `switch`, `try`, `catch`, `orelse`) into statement-form equivalents compatible with C89 code generation.

### Core Principle
> **Lift early, emit simply**: Transform the AST after type checking so the C89 emitter never sees nested control-flow expressions.

### Why AST-Based (Not Codegen-Based)?
| Criterion | AST Pass | Codegen Pass | Winner |
|-----------|----------|--------------|--------|
| Matches existing `TypeChecker::visit()` patterns | ✅ | ❌ | AST |
| Simpler emitter logic | ✅ | ❌ | AST |
| Easier to test/debug | ✅ | ❌ | AST |
| Lower stack risk during emission | ✅ | ❌ | AST |
| Memory predictability | ✅ | ⚠️ | AST |
| RAII state management | ✅ (adapted) | ✅ | Tie |

**Decision**: AST-based lifting with RAII state management adapted from the codegen document's `LiftContext`. This strategy is now FULLY IMPLEMENTED as of Task 237.

---

## 2. Architecture Overview

### 2.1 Pipeline Position
```
Parsing → Name Resolution → Type Checking → [LIFTING PASS] → C89 Codegen → Output
                              ↑
                    AST transformed in-place
```

### 2.2 High-Level Flow
```cpp
void CompilationUnit::performFullPipeline() {
    // ... earlier phases ...

    TypeChecker checker(*this);
    checker.check(ast_root_);  // Types resolved, placeholders handled

    // NEW: Unified lifting pass
    ControlFlowLifter lifter(getArena());
    lifter.lift(this);  // Transforms AST in-place

    // Codegen now sees only lifted AST
    C89Emitter emitter(*this);
    emitter.emit();
}
```

### 2.3 Context Management (Parent Tracking)
To make informed decisions about when to lift, the lifter maintains a `parent_stack_` of `ASTNode*` during its post-order traversal. This is managed via the `ParentGuard` RAII helper, allowing the lifter to resolve semantic parents across nested parentheses.

### 2.4 Key Components
```
ast_lifter.hpp/cpp          # Main lifting logic
ast_utils.hpp/cpp           # Cloning, child traversal helpers
type_checker.hpp (extended) # Optional: lifting flags on ASTNode
codegen.cpp (simplified)    # Emitter assumes lifted AST
```

---

## 3. Lifting Semantics

### 3.1 What Gets Lifted?
| Node Type | Example | Lifted Form |
|-----------|---------|-------------|
| `NODE_IF_EXPR` | `x = if (a) 1 else 2;` | `__tmp_if_1 = if (...) {...}; x = __tmp_if_1;` |
| `NODE_SWITCH_EXPR` | `f(switch (x) {...})` | `__tmp_sw_1 = switch (...) {...}; f(__tmp_sw_1);` |
| `NODE_TRY_EXPR` | `s.field = try foo();` | `__tmp_try_1 = try foo(); s.field = __tmp_try_1;` |
| `NODE_CATCH_EXPR` | `a + (b catch |e| 0)` | `__tmp_cat_1 = b catch...; a + __tmp_cat_1;` |
| `NODE_ORELSE_EXPR` | `opt orelse default` | `__tmp_or_1 = opt orelse...; use __tmp_or_1;` |

### 3.2 When Is Lifting Required?
In standard C89, control-flow constructs like `if` and `switch` are only valid as statements. Therefore, **any control-flow expression must be lifted** regardless of its syntactic context, unless it is a root node (which is always safe). This simplification ensures the C89 code generator never encounters unlifted control flow.

The `needsLifting` logic uses `skipParens()` to resolve the real semantic parent by climbing the `parent_stack_`.

```cpp
bool needsLifting(const ASTNode* node, const ASTNode* parent) {
    if (!isControlFlowExpr(node->type)) return false;
    if (!parent) return false; // Root is safe

    // Climb parent_stack_ to find real semantic parent (skipping NODE_PAREN_EXPR)
    const ASTNode* effective_parent = skipParens(parent);
    if (!effective_parent) return false;

    // C89 simplification: Lift everything to ensure generator robustness.
    // This includes NODE_RETURN_STMT and NODE_ASSIGNMENT RHS.
    return true;
}
```

### 3.3 Complex Lvalue Handling
For assignments like `s.x = try foo()`, lifting uses a temporary:

```
Original:  s.x = try foo();
Lifted:    __tmp_assign_1 = try foo();
           s.x = __tmp_assign_1;
```

This ensures the lvalue (`s.x`) is evaluated *after* the potentially-failing `try`.

---

## 4. Implementation Details (C++98 Compatible)

### 4.1 AST Child Traversal Helpers
**File**: `ast_utils.hpp`

```cpp
// Uniform visitor for cloning/traversal
struct ChildVisitor {
    virtual void visitChild(ASTNode** child_slot) = 0;
};

// Iterate all children of any node type
void forEachChild(ASTNode* node, ChildVisitor& visitor) {
    if (!node) return;
    switch (node->type) {
        case NODE_BINARY_OP:
            visitor.visitChild(&node->as.binary_op->left);
            visitor.visitChild(&node->as.binary_op->right);
            break;
        case NODE_BLOCK_STMT:
            if (node->as.block_stmt.statements) {
                for (size_t i = 0; i < node->as.block_stmt.statements->length(); ++i) {
                    visitor.visitChild(&(*node->as.block_stmt.statements)[i]);
                }
            }
            break;
        // ... handle all node types with children ...
        default: break; // No children
    }
}
```

### 4.2 Deep Clone with Semantic Sharing
**File**: `ast_utils.cpp`

```cpp
ASTNode* cloneASTNode(ASTNode* node, ArenaAllocator* arena) {
    if (!node) return NULL;

    // Shallow copy structure (semantic pointers shared via memcpy)
    ASTNode* copy = (ASTNode*)arena->alloc(sizeof(ASTNode));
    plat_memcpy(copy, node, sizeof(ASTNode));

    // Recursively clone children via uniform helper
    struct CloneVisitor : ChildVisitor {
        ArenaAllocator* arena;
        void visitChild(ASTNode** child_slot) override {
            *child_slot = cloneASTNode(*child_slot, arena);
        }
    };
    CloneVisitor visitor = {arena};
    forEachChild(node, visitor);

    return copy;
}
```

**Critical**: `resolved_type`, `symbol`, and `Type*` pointers are *shared*, not cloned.

### 4.3 ControlFlowLifter Class
**File**: `ast_lifter.hpp`

```cpp
class ControlFlowLifter {
private:
    ArenaAllocator* arena_;
    StringInterner* interner_;
    ErrorHandler* error_handler_;
    int tmp_counter_;
    int depth_;
    const int MAX_LIFTING_DEPTH;

    DynamicArray<ASTNode*> stmt_stack_;     // Statement ancestors
    DynamicArray<ASTBlockStmtNode*> block_stack_; // Enclosing blocks
    DynamicArray<ASTNode*> parent_stack_;   // Stack of ancestors for context
    
public:
    ControlFlowLifter(ArenaAllocator* arena, StringInterner* interner, ErrorHandler* error_handler);
    void lift(CompilationUnit* unit);  // Entry point

private:
    // Core traversal: post-order with slot-based replacement
    void transformNode(ASTNode** node_slot, ASTNode* parent);

    // Decision logic
    bool needsLifting(ASTNode* node, ASTNode* parent);
    const ASTNode* skipParens(const ASTNode* parent);

    // Lifting primitives
    void liftNode(ASTNode** node_slot, ASTNode* parent, const char* prefix);
    const char* generateTempName(const char* prefix);

    // RAII guards for context stacks
    struct StmtGuard {
        ControlFlowLifter& lifter_;
        StmtGuard(ControlFlowLifter& l, ASTNode* stmt);
        ~StmtGuard();
    };

    struct BlockGuard {
        ControlFlowLifter& lifter_;
        BlockGuard(ControlFlowLifter& l, ASTBlockStmtNode* block);
        ~BlockGuard();
    };

    struct ParentGuard {
        ControlFlowLifter& lifter_;
        ParentGuard(ControlFlowLifter& l, ASTNode* node);
        ~ParentGuard();
    };
};
```

### 4.4 Slot-Based Traversal Pattern
**File**: `ast_lifter.cpp`

```cpp
void ControlFlowLifter::transformNode(ASTNode** node_slot, ASTNode* parent) {
    ASTNode* node = *node_slot;
    if (!node) return;

    {
        ParentGuard pguard(*this, node);

        // Identify if this node is a statement or a block to manage context stacks.
        // (Detailed logic in ast_lifter.cpp manages StmtGuard and BlockGuard)

        // Post-order: transform children first
        struct TransformVisitor : ChildVisitor {
            ControlFlowLifter* lifter;
            ASTNode* current_node;
            TransformVisitor(ControlFlowLifter* l, ASTNode* n) : lifter(l), current_node(n) {}
            void visitChild(ASTNode** child_slot) {
                lifter->transformNode(child_slot, current_node);
            }
        };
        TransformVisitor visitor(this, node);
        forEachChild(node, visitor);
    }

    // Now decide if THIS node needs lifting
    if (needsLifting(node, parent)) {
        liftNode(node_slot, parent, getPrefixForType(node->type));
    }
}
```

**Why slots?**: `*node_slot = new_node` directly replaces the pointer in the parent—no fragile `child_idx` tracking.

### 4.5 Unified liftNode Primitive
```cpp
void ControlFlowLifter::liftNode(ASTNode** node_slot, const ASTNode* parent, const char* prefix) {
    ASTNode* node = *node_slot;

    // 1. Generate unique, interned temp name
    const char* temp_name = generateTempName(prefix);

    // 2. Clone node (children already transformed)
    ASTNode* init_expr = cloneASTNode(node, arena_);

    // 3. Create variable declaration
    ASTVarDeclNode* var_decl = createVarDecl(
        temp_name,
        node->resolved_type,  // Share type pointer
        init_expr,
        true  // is_const: temps are immutable
    );
    var_decl->loc = node->loc;

    // 4. Insert at TOP of current block (scope correctness)
    ASTBlockStmtNode* current_block = block_stack_.back();
    if (current_block && current_block->statements) {
        current_block->statements->insert(0, (ASTNode*)var_decl);
    }

    // 5. Create identifier to replace original node
    ASTNode* ident = createIdentifierNode(temp_name, node->loc);
    ident->resolved_type = node->resolved_type;

    // 6. Replace via slot
    *node_slot = ident;
}

const char* ControlFlowLifter::getPrefixForType(NodeType type) {
    switch (type) {
        case NODE_IF_EXPR:    return "__tmp_if";
        case NODE_SWITCH_EXPR: return "__tmp_switch";
        case NODE_TRY_EXPR:   return "__tmp_try";
        case NODE_CATCH_EXPR: return "__tmp_catch";
        case NODE_ORELSE_EXPR: return "__tmp_orelse";
        default: return "__tmp";
    }
}
```

### 4.6 Complex Lvalue Support
```cpp
// Special handling in transformNode for NODE_ASSIGNMENT rvalue:
if (parent && parent->type == NODE_ASSIGNMENT) {
    ASTAssignmentNode* assign = parent->as.assignment;
    if (node == assign->rvalue && needsLifting(node, parent)) {
        if (assign->lvalue->type == NODE_IDENTIFIER) {
            // Direct lift: temp becomes the identifier's target
            liftNode(node_slot, parent, getPrefixForType(node->type));
        } else {
            // Complex lvalue: lift to temp, then assign temp to lvalue
            const char* temp_name = generateTempName("__assign_tmp");
            ASTNode* init_expr = cloneASTNode(node, arena_);

            // Create temp decl
            ASTVarDeclNode* var_decl = createVarDecl(temp_name, node->resolved_type, init_expr, true);
            block_stack_.back()->statements->insert(0, (ASTNode*)var_decl);

            // Create assignment: lvalue = temp
            ASTNode* temp_ident = createIdentifierNode(temp_name, node->loc);
            temp_ident->resolved_type = node->resolved_type;

            // Replace rvalue slot with temp identifier
            *node_slot = temp_ident;
        }
    }
}
```

---

## 5. Memory & Performance Analysis

### 5.1 Memory Budget (16MB Peak)
| Component | Estimated Usage | Notes |
|-----------|----------------|-------|
| Arena overhead | ~2 MB | Alignment, bookkeeping |
| Original AST | ~4 MB | Typical medium program |
| Cloned nodes (lifting) | ~3 MB | Post-order: only lifted nodes cloned |
| Temp var names | ~0.5 MB | Interned strings, reset per module |
| Type system | ~3 MB | Shared `Type*` pointers, not cloned |
| Symbol tables | ~2 MB | Shared across passes |
| **Peak estimate** | **~14.5 MB** | Under 16MB limit with margin |

### 5.2 Memory Tracking Hooks
**File**: `platform.hpp` (extended)

```cpp
struct MemoryTracker {
    size_t peak_bytes;
    size_t current_bytes;
    ArenaAllocator* arena;

    void* trackAlloc(size_t size) {
        current_bytes += size;
        if (current_bytes > peak_bytes) peak_bytes = current_bytes;
        // CRITICAL: Abort if we exceed budget
        if (peak_bytes > 16 * 1024 * 1024) {
            plat_printf("FATAL: Memory limit exceeded (%u bytes)\n", peak_bytes);
            plat_abort();
        }
        return arena->alloc(size);
    }

    size_t getPeakBytes() const { return peak_bytes; }
};
```

### 5.3 Stack Usage
| Component | Size | Notes |
|-----------|------|-------|
| `LiftContext` | 16 bytes | 4 pointers on 32-bit target |
| Recursion depth | ~200 frames | Guarded by `MAX_VISIT_DEPTH` |
| RAII guards | 8-12 bytes each | Stack-only, no heap |
| **Total per lift** | **~28 bytes** | Negligible for 1MB stack |

---

## 6. Codegen Contract

### 6.1 Post-Lifting AST Guarantees
After `ControlFlowLifter::lift()`:
1. ✅ No `NODE_IF_EXPR`, `NODE_SWITCH_EXPR`, etc. appear nested in expressions
2. ✅ All control-flow expressions are replaced by `NODE_IDENTIFIER` referencing a temp var
3. ✅ Temp var declarations are inserted at the top of their enclosing block
4. ✅ `resolved_type` pointers are preserved (shared, not cloned)
5. ✅ Temp names are unique and interned (`__tmp_if_1`, `__tmp_try_2`, ...)

### 6.2 Simplified Emitter Logic
**File**: `codegen.cpp` (post-lifting)

```cpp
// OLD: Complex lifting logic in emitExpression
case NODE_IF_EXPR:
    if (in_expression_context) {
        // Manual temp var, block emission, defer handling...
    }
    break;

// NEW: Assume AST is already lifted
case NODE_IF_EXPR:
    // This should never happen post-lifting!
    error_handler_.report(ERR_INTERNAL, node->loc, "Unlifted if expression reached codegen");
    break;

case NODE_IDENTIFIER:
    // Simple: just emit the identifier
    writeString(node->as.identifier.name);
    break;
```

### 6.3 Target Variable Handling
The emitter still accepts a `target_var` parameter for clarity:

```cpp
void C89Emitter::emitExpression(const ASTNode* node, const char* target_var) {
    if (!node) return;

    switch (node->type) {
        case NODE_IDENTIFIER:
            if (target_var) {
                writeIndent();
                writeString(target_var);
                writeString(" = ");
                writeString(node->as.identifier.name);
                writeString(";\n");
            } else {
                // Standalone identifier (side-effects only)
                writeIndent();
                writeString(node->as.identifier.name);
                writeString(";\n");
            }
            break;
        // ... other cases ...
    }
}
```

---

## 7. Testing Strategy

### 7.1 Unit Tests (ast_lifter_test.cpp)
```cpp
// Test 1: Basic cloning preserves semantics
TEST(ClonePreservesTypes) {
    ASTNode* original = parseExpr("if (a) 1 else 2");
    original->resolved_type = get_g_type_i32();

    ASTNode* clone = cloneASTNode(original, &test_arena);

    ASSERT(clone->resolved_type == original->resolved_type);  // Shared, not copied
    ASSERT(clone != original);  // Different struct
    ASSERT(clone->as.if_expr.then_expr != original->as.if_expr.then_expr);  // Cloned child
}

// Test 2: needsLifting decisions
TEST(NeedsLiftingMatrix) {
    ASSERT(!needsLifting(if_node, expression_stmt_parent));  // Safe
    ASSERT(needsLifting(if_node, binary_op_parent));         // Unsafe
    ASSERT(needsLifting(try_node, function_call_arg));       // Unsafe
}

// Test 3: Temp var scoping
TEST(TempVarInsertedAtBlockTop) {
    // foo(try bar()) → { __tmp_try_1 = try bar(); foo(__tmp_try_1); }
    ASTNode* lifted = liftTestProgram("foo(try bar())");
    ASTBlockStmtNode* block = findEnclosingBlock(lifted);
    ASSERT(block->statements->at(0)->type == NODE_VAR_DECL);  // Temp first
}
```

### 7.2 Integration Tests (lifting_tests.zig)
```zig
// Test 1: Basic lifting
const x = try foo();
const y = if (a) 1 else 2;

// Test 2: Nested lifting
const z = try (if (b) bar() else baz());
const w = (try foo()) catch |err| (if (err) 1 else 2);

// Test 3: Complex lvalues
struct { x: i32 } s;
s.x = try compute();
array[try getIndex()] = if (cond) a else b;

// Test 4: Return with lifting
fn getValue() !i32 {
    return try fetch();  // Lifted to temp, then return temp
}

// Test 5: Defer interaction
fn withDefer() !void {
    defer cleanup();
    const x = try operation();  // Defer must run on error path
}
```

### 7.3 Memory Verification Test
```cpp
TEST(LiftingMemoryBudget) {
    ArenaAllocator arena(16 * 1024 * 1024);  // 16MB limit
    CompilationUnit unit(&arena, ...);

    parseTestProgram("deeply_nested_control_flow.zig", &unit);
    size_t before_lift = arena.getUsedBytes();

    TypeChecker checker(unit);
    checker.check(unit.getASTRoot());
    size_t after_typecheck = arena.getUsedBytes();

    ControlFlowLifter lifter(&arena);
    lifter.lift(&unit);

    size_t after_lift = arena.getUsedBytes();
    size_t peak = arena.getPeakBytes();

    ASSERT(peak < 16 * 1024 * 1024, "Exceeded 16MB memory limit");
    ASSERT((after_lift - after_typecheck) < (after_typecheck - before_lift) * 2,
           "Lifting shouldn't more than double memory usage");
}
```

---

## 8. MSVC 6.0 Compatibility

### 8.1 Required Compiler Flags
```
/O1          ; Optimize for size (critical for W98)
/Oy          ; Omit frame pointer (saves stack)
/GX-         ; Disable exceptions (no overhead)
/GR-         ; Disable RTTI (no vtable bloat)
/W4          ; High warning level
/Za          ; Strict C++98 mode (disable MS extensions)
```

### 8.2 Code Patterns to Enforce
```cpp
// ✅ GOOD: Plain struct, inline destructor
struct LiftContext {
    __forceinline ~LiftContext() { cleanup(); }
};

// ❌ BAD: Virtual functions (vtable overhead)
// struct LiftContext { virtual ~LiftContext() {} };

// ✅ GOOD: Arena allocation, no new/delete
ASTNode* node = (ASTNode*)arena->alloc(sizeof(ASTNode));

// ❌ BAD: STL containers
// std::vector<ASTNode*> children;

// ✅ GOOD: DynamicArray with arena
DynamicArray<ASTNode*> children(arena);

// ✅ GOOD: plat_* functions, not std::*
plat_memcpy(dest, src, size);  // Not std::memcpy

// ❌ BAD: Exception handling
// try { ... } catch (...) { ... }

// ✅ GOOD: Error codes and early returns
if (!node) return;
```

### 8.3 Build System Integration
```cmake
# CMakeLists.txt excerpt
if (MSVC AND MSVC_VERSION LESS 1300)  # MSVC 6.0 = version 1200
    add_definitions(-D_CRT_SECURE_NO_DEPRECATE)
    add_definitions(-D_HAS_AUTO_PTR_EXT=0)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /Za /EHsc- /O1 /Oy")
endif()

# Add compile test target for lifting
add_executable(compile_test_lifter
    src/ast_lifter.cpp
    src/ast_utils.cpp
    test/lifting_basic.cpp
)
target_compile_options(compile_test_lifter PRIVATE /W4 /WX)
```

---

## 9. Implementation Timeline

### Week 1: Foundation
- [ ] Task 228.5: AST Child Access Helpers
- [ ] Task 229: AST Cloning Utilities
- [ ] Task 229.5: Memory Tracking Hooks

### Week 2: Infrastructure
- [ ] Task 230: ControlFlowLifter Skeleton
- [ ] Task 230.5: Slot-Based Traversal Pattern

### Week 3: Lifting Logic
- [x] Task 232: Context-Aware `needsLifting()`
- [x] Task 233: Unified `liftNode()` Primitive
- [x] Task 233.5: Complex Lvalue Support (Evaluates RHS before LHS)

### Week 4: Integration
- [x] Task 237: Hook into Pipeline + Simplify Emitter
- [ ] Task 237.5: Memory Verification Gate

### Week 5: Polish
- [ ] Task 238: Comprehensive Test Suite
- [ ] Task 240: MSVC 6.0 Compatibility Gate
- [ ] Documentation updates (`C89_Codegen.md`, `AST_Parser.md`)

---

## 10. Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Memory blowup during cloning | Memory tracking hooks with hard 16MB abort |
| Stack overflow from deep nesting | `MAX_VISIT_DEPTH` guard (200 frames) |
| Semantic info corruption in clones | Share `resolved_type`/`symbol` pointers; only clone structure |
| MSVC 6.0 compilation failures | Dedicated compile test target with strict flags |
| Lifter breaks existing tests | Run full test suite after each task; add lifting-specific tests |

---

## 11. Appendix: Quick Reference

### Temp Name Format
```
__tmp_if_<counter>      // if expressions
__tmp_switch_<counter>  // switch expressions
__tmp_try_<counter>     // try expressions
__tmp_catch_<counter>   // catch expressions
__tmp_orelse_<counter>  // orelse expressions
__tmp_assign_<counter>  // complex lvalue assignments
```

### Key Functions
```cpp
// Clone AST node (shares semantic info)
ASTNode* cloneASTNode(ASTNode* node, ArenaAllocator* arena);

// Traverse children uniformly
void forEachChild(ASTNode* node, ChildVisitor& visitor);

// Decide if node needs lifting
bool needsLifting(const ASTNode* node, const ASTNode* parent);

// Lift a single node to temp var
void liftNode(ASTNode** node_slot, const ASTNode* parent, const char* prefix);

// Entry point: lift entire compilation unit
void ControlFlowLifter::lift(CompilationUnit* unit);
```

### Debug Helpers
Verbose logging can be enabled via the `--debug-lifter` command-line flag. This provides a detailed trace of all lifting transformations, including:
- Which nodes are being lifted and their source locations.
- Generated temporary variable names and their types.
- Symbol registration events for temporary variables.
- Post-transformation AST integrity checks.

Additionally, `SymbolTable::dumpSymbols()` can be called at any point to inspect the state of the symbol table across all active scopes.

---
