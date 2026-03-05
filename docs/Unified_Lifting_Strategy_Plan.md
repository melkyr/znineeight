# Unified Control-Flow Lifting Strategy
## Design Document — Milestone 8 (Z98 Bootstrap Compiler)

**Version**: 1.1
**Target**: Windows 98 / 16MB RAM / MSVC 6.0 / C++98  
**Author**: Compiler Team  
**Status**: Updated for Implementation Completeness (Task 232)

---

## 1. Executive Summary

This document defines the **unified lifting strategy** for transforming expression-valued control-flow constructs (`if`, `switch`, `try`, `catch`, `orelse`) into statement-form equivalents compatible with C89 code generation.

### Core Principle
> **Lift early, emit simply**: Transform the AST after type checking so the C89 emitter never sees nested control-flow expressions.

---

## 2. Architecture Overview

### 2.1 Pipeline Position
```
Parsing → Name Resolution → Type Checking → [LIFTING PASS] → C89 Codegen → Output
                              ↑
                    AST transformed in-place
```

### 2.2 Context Management (Parent Tracking)
To make informed decisions about when to lift, the lifter maintains a `parent_stack_` of `ASTNode*` during its post-order traversal. This is managed via the `ParentGuard` RAII helper.

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
In standard C89, control-flow constructs like `if` and `switch` are only valid as statements. Therefore, **any control-flow expression must be lifted** regardless of its immediate syntactic parent, unless it is a root node (which is always safe).

The `needsLifting` logic uses `skipParens()` to resolve the real semantic parent by climbing the `parent_stack_`.

```cpp
bool needsLifting(const ASTNode* node, const ASTNode* parent) {
    if (!isControlFlowExpr(node->type)) return false;
    if (!parent) return false; // Root is safe

    // Climb parent_stack_ to find real semantic parent
    const ASTNode* effective_parent = skipParens(parent);
    if (!effective_parent) return false;

    // C89 simplification: Lift everything.
    return true;
}
```

### 3.3 Semantic Parent Resolution (`skipParens`)
Parentheses (`NODE_PAREN_EXPR`) do not change the semantic context. The lifter uses the `parent_stack_` to look past them to find the "effective" parent (e.g., a function call, assignment, or return statement).

---

## 4. Implementation Details (C++98 Compatible)

### 4.1 Parent Tracking Infrastructure
**File**: `ast_lifter.hpp`

```cpp
class ControlFlowLifter {
    // ...
    DynamicArray<ASTNode*> parent_stack_;
    
    struct ParentGuard {
        ControlFlowLifter& lifter_;
        ParentGuard(ControlFlowLifter& l, ASTNode* node) : lifter_(l) {
            lifter_.parent_stack_.append(node);
        }
        ~ParentGuard() { lifter_.parent_stack_.pop_back(); }
    };

    const ASTNode* skipParens(const ASTNode* parent);
};
```

### 4.2 Updated Traversal Pattern
The `transformNode` method uses `ParentGuard` to ensure the stack is updated as it recurses.

```cpp
void ControlFlowLifter::transformNode(ASTNode** node_slot, ASTNode* parent) {
    ASTNode* node = *node_slot;
    if (!node) return;

    {
        ParentGuard pguard(*this, node);
        // ... transform children first ...
    }

    if (needsLifting(node, parent)) {
        liftNode(node_slot, parent, getPrefixForType(node->type));
    }
}
```

---

## 6. Codegen Contract

### 6.1 Post-Lifting AST Guarantees
After `ControlFlowLifter::lift()`:
1. ✅ No `NODE_IF_EXPR`, `NODE_SWITCH_EXPR`, etc. appear nested in expressions.
2. ✅ All control-flow expressions are replaced by `NODE_IDENTIFIER` referencing a temp var.
3. ✅ Temp var declarations are inserted at the top of their enclosing block (preserving C89 compliance).
4. ✅ Semantic info (`resolved_type`) is preserved.

---

## 11. Appendix: Quick Reference

### Temp Name Format
```
__tmp_if_<counter>      // if expressions
__tmp_switch_<counter>  // switch expressions
__tmp_try_<counter>     // try expressions
__tmp_catch_<counter>   // catch expressions
__tmp_orelse_<counter>  // orelse expressions
```
