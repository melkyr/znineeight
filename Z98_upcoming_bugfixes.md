## 🎯 Priority Patches (Implement in This Order)

### Issue 3: `main` Function Return Type (Quick Win - Fix C Compilation Errors)

**File:** `codegen.cpp`

**Patch 1: `emitFnDecl` - Force C signature for `main`**
```cpp
// Around line 550, in emitFnDecl:
/* Special handling for the main entry point */
if (plat_strcmp(node->name, "main") == 0 && node->is_pub) {
    // CRITICAL: C89 main MUST return int, regardless of Zig return type
    writeString("int main(int argc, char* argv[])");
    is_main_function_ = true;
    // Force internal tracking to void to avoid error-union wrapping confusion
    current_fn_ret_type_ = get_g_type_void();
} else if (plat_strcmp(node->name, "__bootstrap_print") == 0 || /* ... existing runtime checks ... */) {
    // ... existing code ...
}
```

**Patch 2: `emitReturn` - Handle `main` specially**
```cpp
// Around line 1580, in emitReturn:
writeIndent();
if (node->expression) {
    if (is_main_function_) {
        // For main: evaluate expression for side effects, then return 0/1
        writeString("{
");
        {
            IndentScope scope_indent(*this);
            writeIndent();
            writeString("(void)(");
            emitExpression(node->expression);
            writeString(");
");
            writeIndent();
            writeString("return 0; /* Success */
");
        }
        writeIndent();
        writeString("}
");
    } else {
        writeString("return ");
        emitExpression(node->expression);
        writeString(";
");
    }
} else {
    if (is_main_function_) {
        writeString("return 0;
");
    } else {
        writeString("return;
");
    }
}
```

**Patch 3: `emitBlock` - Add implicit `return 0` for `main`**
```cpp
// In emitBlock, after the existing implicit-return logic for Error!void:
/* Task: Fix #2 - Implicit return for Error!void and main */
if (label_id == -1 && defer_stack_.length() == 1) {
    if (current_fn_ret_type_ && current_fn_ret_type_->kind == TYPE_ERROR_UNION &&
        current_fn_ret_type_->as.error_union.payload->kind == TYPE_VOID) {
        // ... existing Error!void handling ...
    } else if (is_main_function_) {
        // CRITICAL: main must always return an int in C89
        writeIndent();
        writeString("return 0;
");
    }
}
```

---

### Issue 2: Placeholder Name Preservation (Critical for Multi-Module Types)

**File:** `type_checker.cpp`

**Patch: `finalizePlaceholder` - Unconditionally restore names**
```cpp
// Replace the entire finalizePlaceholder function (around line 1050) with:
void TypeChecker::finalizePlaceholder(Type* placeholder, Type* resolved) {
    if (!placeholder || !resolved) return;
    
    // Save original metadata BEFORE any mutation
    const char* original_name = placeholder->as.placeholder.name;
    Module* original_module = placeholder->as.placeholder.module;
    DependentNode* dependents_head = placeholder->dependents_head;
    
    // Mutate in place (existing logic)
    if (placeholder != resolved) {
        placeholder->kind = resolved->kind;
        placeholder->size = resolved->size;
        placeholder->alignment = resolved->alignment;
        placeholder->owner_module = resolved->owner_module;
        if (resolved->c_name) {
            placeholder->c_name = resolved->c_name;
        }
        placeholder->as = resolved->as;
    }
    
    // CRITICAL FIX: Unconditionally restore the name for ALL nominal types
    // This prevents anonymous types in generated C code which cause compilation errors
    switch (placeholder->kind) {
        case TYPE_STRUCT:
        case TYPE_UNION:
            placeholder->as.struct_details.name = original_name;
            break;
        case TYPE_TAGGED_UNION:
            placeholder->as.tagged_union.name = original_name;
            break;
        case TYPE_ENUM:
            placeholder->as.enum_details.name = original_name;
            break;
        case TYPE_ERROR_SET:
            placeholder->as.error_set.name = original_name;
            break;
        default:
            break;
    }
    
    // Preserve module ownership for cross-module consistency
    if (original_module && !placeholder->owner_module) {
        placeholder->owner_module = original_module;
    }
    
    // Process dependents (existing logic)
    while (dependents_head) {
        DependentNode* current = dependents_head;
        dependents_head = dependents_head->next;
        refreshLayout(current->type);
    }
}
```

---

### Issue 1: Cross-Module Type Identity (Most Complex - Essential for Imports)

**File 1: `type_checker.cpp` - Update `areTypesCompatible`**

```cpp
// At the START of areTypesCompatible (after the initial pointer check):
bool TypeChecker::areTypesCompatible(Type* expected, Type* actual) {
    if (expected == actual) {
        return true;
    }
    if (!expected || !actual) {
        return false;
    }
    
    // NEW: For nominal types, use structural equality via name + module
    if ((expected->kind == TYPE_STRUCT && actual->kind == TYPE_STRUCT) ||
        (expected->kind == TYPE_UNION && actual->kind == TYPE_UNION) ||
        (expected->kind == TYPE_ENUM && actual->kind == TYPE_ENUM) ||
        (expected->kind == TYPE_TAGGED_UNION && actual->kind == TYPE_TAGGED_UNION)) {
        
        const char* exp_name = (expected->kind == TYPE_ENUM) ? 
            expected->as.enum_details.name : expected->as.struct_details.name;
        const char* act_name = (actual->kind == TYPE_ENUM) ? 
            actual->as.enum_details.name : actual->as.struct_details.name;
            
        if (exp_name && act_name && plat_strcmp(exp_name, act_name) == 0) {
            // Names match - for bootstrap, accept as compatible
            // (In production, you'd also verify module compatibility)
            return true;
        }
    }
    
    // ... rest of existing function ...
```

**File 2: `type_registry.cpp` - Add structural check to `insert`**

```cpp
// Add this helper function to type_registry.cpp:
static bool areTypesStructurallyEqual(Type* a, Type* b) {
    if (a == b) return true;
    if (!a || !b || a->kind != b->kind) return false;
    
    // For nominal types, compare names
    if (a->kind == TYPE_STRUCT || a->kind == TYPE_UNION || 
        a->kind == TYPE_ENUM || a->kind == TYPE_TAGGED_UNION) {
        const char* a_name = (a->kind == TYPE_ENUM) ? 
            a->as.enum_details.name : a->as.struct_details.name;
        const char* b_name = (b->kind == TYPE_ENUM) ? 
            b->as.enum_details.name : b->as.struct_details.name;
        return (a_name && b_name && plat_strcmp(a_name, b_name) == 0);
    }
    
    // For composite types, recurse (simplified for bootstrap)
    if (a->kind == TYPE_POINTER) {
        return a->as.pointer.is_const == b->as.pointer.is_const &&
               a->as.pointer.is_many == b->as.pointer.is_many &&
               areTypesStructurallyEqual(a->as.pointer.base, b->as.pointer.base);
    }
    if (a->kind == TYPE_OPTIONAL) {
        return areTypesStructurallyEqual(a->as.optional.payload, b->as.optional.payload);
    }
    // ... add other cases as needed ...
    
    return false;
}

// Then update TypeRegistry::insert:
TypeRegistry::InsertStatus TypeRegistry::insert(Module* owner, const char* name, Type* type_ptr, bool verify_structure) {
    u32 h = hash(owner, name);
    Entry* entry = buckets[h];
    while (entry) {
        if (sameModule(entry->owner, owner) && strings_equal(entry->name, name)) {
            if (entry->type_ptr == type_ptr) {
                return DUPLICATE;
            }
            // NEW: If structure matches, accept as same type (critical for cross-module imports)
            if (verify_structure && areTypesStructurallyEqual(entry->type_ptr, type_ptr)) {
                return DUPLICATE; // Treat as successful registration of existing type
            }
            return MISMATCH;
        }
        entry = entry->next;
    }
    // ... rest of existing insert logic ...
}
```

---

### Issue 4: C89 Declaration Order / Expression Lifting

**File:** `codegen.cpp`

**Step 1: Add member variables to `C89Emitter` class (`codegen.hpp`)**
```cpp
// In class C89Emitter, add:
DynamicArray<const char*> lifted_temp_names_;  // Names of lifted temporaries
DynamicArray<Type*> lifted_temp_types_;        // Their types
```

**Step 2: Add helper to collect lifted temporaries**
```cpp
// Add to codegen.cpp:
void C89Emitter::collectLiftedTemporaries(const ASTNode* node) {
    if (!node) return;
    
    // Recursively walk expressions that may need lifting
    switch (node->type) {
        case NODE_TRY_EXPR:
        case NODE_CATCH_EXPR:
        case NODE_ORELSE_EXPR: {
            // These expressions get lifted to temporaries in C
            const char* temp_name = var_alloc_.generate("__lifted_tmp");
            lifted_temp_names_.append(temp_name);
            lifted_temp_types_.append(node->resolved_type);
            break;
        }
        case NODE_IF_EXPR:
            collectLiftedTemporaries(node->as.if_expr->then_expr);
            collectLiftedTemporaries(node->as.if_expr->else_expr);
            break;
        case NODE_SWITCH_EXPR:
            if (node->as.switch_expr->prongs) {
                for (size_t i = 0; i < node->as.switch_expr->prongs->length(); ++i) {
                    collectLiftedTemporaries((*node->as.switch_expr->prongs)[i]->body);
                }
            }
            break;
        // Add other expression types as needed
        default:
            break;
    }
}
```

**Step 3: Modify `emitBlock` to use two-pass lifting**
```cpp
// Replace the emitBlock function with this enhanced version:
void C89Emitter::emitBlock(const ASTBlockStmtNode* node, int label_id) {
    if (!node) return;
    writeString("{
");
    {
        IndentScope scope_indent(*this);
        DeferScopeGuard defer_guard(*this, label_id);
        DeferScope* scope = defer_stack_.back();
        
        // NEW: Clear lifted temporaries for this block
        lifted_temp_names_.clear();
        lifted_temp_types_.clear();
        
        /* Pass 1: Local declarations (existing) */
        for (size_t i = 0; i < node->statements->length(); ++i) {
            ASTNode* stmt = (*node->statements)[i];
            if (stmt->type == NODE_VAR_DECL) {
                emitLocalVarDecl(stmt, false);
            }
        }
        
        /* NEW Pass 1.5: Collect lifted temporaries by analyzing statements */
        for (size_t i = 0; i < node->statements->length(); ++i) {
            ASTNode* stmt = (*node->statements)[i];
            if (stmt->type != NODE_VAR_DECL && 
                stmt->type != NODE_DEFER_STMT && 
                stmt->type != NODE_ERRDEFER_STMT) {
                collectLiftedTemporaries(stmt);
            }
        }
        
        /* NEW Pass 1.6: Emit lifted temporary declarations at TOP of block (C89 requirement) */
        for (size_t i = 0; i < lifted_temp_names_.length(); ++i) {
            writeIndent();
            emitType(lifted_temp_types_[i], lifted_temp_names_[i]);
            writeString(";
");
        }
        
        /* Pass 2: Statements (existing) */
        bool exits = false;
        for (size_t i = 0; i < node->statements->length(); ++i) {
            ASTNode* stmt = (*node->statements)[i];
            if (stmt->type == NODE_VAR_DECL) {
                emitLocalVarDecl(stmt, true);
                if (allPathsExit(stmt)) { exits = true; break; }
            } else if (stmt->type == NODE_DEFER_STMT) {
                scope->defers.append((ASTDeferStmtNode*)&stmt->as.defer_stmt);
            } else if (stmt->type == NODE_ERRDEFER_STMT) {
                scope->defers.append((ASTDeferStmtNode*)&stmt->as.errdefer_stmt);
            } else {
                emitStatement(stmt);
                if (allPathsExit(stmt)) { exits = true; break; }
            }
        }
        
        /* Emit defers and implicit return (existing) */
        if (!exits) {
            for (int i = (int)scope->defers.length() - 1; i >= 0; --i) {
                emitStatement(scope->defers[i]->statement);
            }
            // ... existing implicit return logic ...
        }
    }
    writeIndent();
    writeString("}");
}
```

---

### Issue 5: TypeRegistry Structural Interning (Supports Issue 1)

**File:** `type_registry.hpp`
```cpp
// Add declaration:
bool areTypesStructurallyEqual(Type* a, Type* b);
```

**File:** `type_registry.cpp`
```cpp
// The implementation is already provided in the Issue 1 patch above.
// Just ensure it's declared in the header and defined in the .cpp.
```

---
