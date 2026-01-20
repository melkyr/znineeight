#include "double_free_analyzer.hpp"
#include "error_handler.hpp"
#include "utils.hpp"
#include <cstring>
#include <new>

DeferStack::DeferStack(ArenaAllocator& arena) : arena_(arena), stack_(arena) {}

void DeferStack::pushScope() {
    void* mem = arena_.alloc(sizeof(DynamicArray<ASTNode*>));
    DynamicArray<ASTNode*>* new_scope = new (mem) DynamicArray<ASTNode*>(arena_);
    stack_.append(new_scope);
}

void DeferStack::popScope(DoubleFreeAnalyzer& analyzer) {
    if (stack_.length() == 0) return;
    DynamicArray<ASTNode*>* current_scope = stack_[stack_.length() - 1];

    // Execute defers in reverse order
    for (int i = (int)current_scope->length() - 1; i >= 0; --i) {
        analyzer.visit((*current_scope)[i]);
    }

    stack_.pop_back();
}

void DeferStack::defer(ASTNode* action) {
    if (stack_.length() == 0) pushScope();
    stack_[stack_.length() - 1]->append(action);
}

DoubleFreeAnalyzer::DoubleFreeAnalyzer(CompilationUnit& unit)
    : unit_(unit), defer_stack_(unit.getArena()), current_scope_(NULL) {}

void DoubleFreeAnalyzer::analyze(ASTNode* root) {
    visit(root);
}

void DoubleFreeAnalyzer::visit(ASTNode* node) {
    if (!node) return;

    switch (node->type) {
        case NODE_FN_DECL: visitFnDecl(node->as.fn_decl); break;
        case NODE_BLOCK_STMT: visitBlock(&node->as.block_stmt); break;
        case NODE_VAR_DECL: visitVarDecl(node->as.var_decl); break;
        case NODE_ASSIGNMENT: visitAssignment(node->as.assignment); break;
        case NODE_IF_STMT: visitIfStmt(node->as.if_stmt); break;
        case NODE_WHILE_STMT: visitWhileStmt(&node->as.while_stmt); break;
        case NODE_FOR_STMT: visitForStmt(node->as.for_stmt); break;
        case NODE_FUNCTION_CALL: visitFunctionCall(node->as.function_call); break;
        case NODE_DEFER_STMT: visitDeferStmt(&node->as.defer_stmt); break;
        case NODE_ERRDEFER_STMT: visitErrDeferStmt(&node->as.errdefer_stmt); break;
        case NODE_EXPRESSION_STMT: visit(node->as.expression_stmt.expression); break;
        case NODE_MEMBER_ACCESS: visit(node->as.member_access->object); break;
        default: break;
    }
}

void DoubleFreeAnalyzer::visitFnDecl(ASTFnDeclNode* node) {
    pushScope();
    defer_stack_.pushScope();

    visit(node->body);

    defer_stack_.popScope(*this);

    // Check for memory leaks
    for (size_t i = 0; i < current_scope_->pointers.length(); ++i) {
        if (current_scope_->pointers[i].state == AS_ALLOCATED) {
            char msg[256];
            char* current = msg;
            size_t remaining = 256;
            safe_append(current, remaining, "Potential memory leak: pointer '");
            safe_append(current, remaining, current_scope_->pointers[i].name);
            safe_append(current, remaining, "' allocated but not freed");
            unit_.getErrorHandler().reportWarning(WARN_MEMORY_LEAK, current_scope_->pointers[i].last_action_loc, msg);
        }
    }

    popScope();
}

void DoubleFreeAnalyzer::visitBlock(ASTBlockStmtNode* node) {
    pushScope();
    defer_stack_.pushScope();

    if (node->statements) {
        for (size_t i = 0; i < node->statements->length(); ++i) {
            visit((*node->statements)[i]);
        }
    }

    defer_stack_.popScope(*this);
    popScope();
}

void DoubleFreeAnalyzer::visitVarDecl(ASTVarDeclNode* node) {
    if (node->initializer) {
        visit(node->initializer);

        if (node->initializer->type == NODE_FUNCTION_CALL) {
            const char* funcName = NULL;
            ASTNode* callee = node->initializer->as.function_call->callee;
            if (callee->type == NODE_IDENTIFIER) funcName = callee->as.identifier.name;
            else if (callee->type == NODE_MEMBER_ACCESS) funcName = callee->as.member_access->member_name;

            if (funcName && isAllocationFunction(funcName)) {
                setState(node->name, AS_ALLOCATED, node->initializer->loc);
                return;
            }
        }
    }
}

void DoubleFreeAnalyzer::visitAssignment(ASTAssignmentNode* node) {
    visit(node->rvalue);

    const char* varName = NULL;
    if (node->lvalue->type == NODE_IDENTIFIER) {
        varName = node->lvalue->as.identifier.name;
    }

    if (varName) {
        if (node->rvalue->type == NODE_FUNCTION_CALL) {
            const char* funcName = NULL;
            ASTNode* callee = node->rvalue->as.function_call->callee;
            if (callee->type == NODE_IDENTIFIER) funcName = callee->as.identifier.name;
            else if (callee->type == NODE_MEMBER_ACCESS) funcName = callee->as.member_access->member_name;

            if (funcName && isAllocationFunction(funcName)) {
                setState(varName, AS_ALLOCATED, node->rvalue->loc);
                return;
            }
        }

        // Handle pointer aliasing p = q
        if (node->rvalue->type == NODE_IDENTIFIER) {
            AllocationState src_state = getState(node->rvalue->as.identifier.name);
            setState(varName, src_state, node->rvalue->loc);
        }
    }
}

void DoubleFreeAnalyzer::visitIfStmt(ASTIfStmtNode* node) {
    visit(node->condition);

    // Create new scopes for branches to simulate path divergence
    pushScope();
    visit(node->then_block);
    ScopeState* then_scope = current_scope_;
    popScope();

    ScopeState* else_scope = NULL;
    if (node->else_block) {
        pushScope();
        visit(node->else_block);
        else_scope = current_scope_;
        popScope();
    }

    // Merge states back into current_scope_
    for (size_t i = 0; i < then_scope->pointers.length(); ++i) {
        const char* name = then_scope->pointers[i].name;
        AllocationState s1 = then_scope->pointers[i].state;
        AllocationState s2 = AS_UNKNOWN;

        if (else_scope) {
            bool found = false;
            for (size_t j = 0; j < else_scope->pointers.length(); ++j) {
                if (strcmp(else_scope->pointers[j].name, name) == 0) {
                    s2 = else_scope->pointers[j].state;
                    found = true;
                    break;
                }
            }
            if (!found) s2 = getState(name);
        } else {
            s2 = getState(name);
        }

        setState(name, mergeStates(s1, s2), then_scope->pointers[i].last_action_loc);
    }

    if (else_scope) {
        for (size_t i = 0; i < else_scope->pointers.length(); ++i) {
            const char* name = else_scope->pointers[i].name;
            bool handled = false;
            for (size_t j = 0; j < then_scope->pointers.length(); ++j) {
                if (strcmp(then_scope->pointers[j].name, name) == 0) {
                    handled = true;
                    break;
                }
            }
            if (handled) continue;

            AllocationState s1 = getState(name);
            AllocationState s2 = else_scope->pointers[i].state;
            setState(name, mergeStates(s1, s2), else_scope->pointers[i].last_action_loc);
        }
    }
}

void DoubleFreeAnalyzer::visitWhileStmt(ASTWhileStmtNode* node) {
    visit(node->condition);
    pushScope();
    visit(node->body);
    ScopeState* loop_scope = current_scope_;
    popScope();

    for (size_t i = 0; i < loop_scope->pointers.length(); ++i) {
        setState(loop_scope->pointers[i].name, AS_UNKNOWN, loop_scope->pointers[i].last_action_loc);
    }
}

void DoubleFreeAnalyzer::visitForStmt(ASTForStmtNode* node) {
    visit(node->iterable_expr);
    pushScope();
    visit(node->body);
    ScopeState* loop_scope = current_scope_;
    popScope();

    for (size_t i = 0; i < loop_scope->pointers.length(); ++i) {
        setState(loop_scope->pointers[i].name, AS_UNKNOWN, loop_scope->pointers[i].last_action_loc);
    }
}

void DoubleFreeAnalyzer::visitFunctionCall(ASTFunctionCallNode* node) {
    const char* funcName = NULL;
    ASTNode* callee = node->callee;
    if (callee->type == NODE_IDENTIFIER) funcName = callee->as.identifier.name;
    else if (callee->type == NODE_MEMBER_ACCESS) funcName = callee->as.member_access->member_name;

    if (!funcName) return;

    if (isDeallocationFunction(funcName) || isBannedFunction(funcName)) {
        if (node->args && node->args->length() > 0) {
            ASTNode* arg = (*node->args)[0];
            if (arg->type == NODE_IDENTIFIER) {
                const char* varName = arg->as.identifier.name;
                AllocationState state = getState(varName);

                if (state == AS_FREED) {
                    unit_.getErrorHandler().report(ERR_DOUBLE_FREE, node->callee->loc, "Double free detected");
                } else if (state == AS_ALLOCATED) {
                    setState(varName, AS_FREED, node->callee->loc);
                } else if (state == AS_UNKNOWN) {
                    unit_.getErrorHandler().reportWarning(WARN_POTENTIAL_DOUBLE_FREE, node->callee->loc, "Potential double free detected");
                    setState(varName, AS_FREED, node->callee->loc);
                } else if (state == AS_NOT_ALLOCATED) {
                    unit_.getErrorHandler().reportWarning(WARN_FREE_UNALLOCATED, node->callee->loc, "Freeing unallocated pointer");
                    setState(varName, AS_FREED, node->callee->loc);
                }
            }
        }
    }
}

void DoubleFreeAnalyzer::visitDeferStmt(ASTDeferStmtNode* node) {
    defer_stack_.defer(node->statement);
}

void DoubleFreeAnalyzer::visitErrDeferStmt(ASTErrDeferStmtNode* node) {
    defer_stack_.defer(node->statement);
}

void DoubleFreeAnalyzer::pushScope() {
    void* mem = unit_.getArena().alloc(sizeof(ScopeState));
    current_scope_ = new (mem) ScopeState(unit_.getArena(), current_scope_);
}

void DoubleFreeAnalyzer::popScope() {
    if (current_scope_) {
        current_scope_ = current_scope_->parent;
    }
}

void DoubleFreeAnalyzer::setState(const char* name, AllocationState state, SourceLocation loc) {
    if (!current_scope_) return;

    for (size_t i = 0; i < current_scope_->pointers.length(); ++i) {
        if (strcmp(current_scope_->pointers[i].name, name) == 0) {
            current_scope_->pointers[i].state = state;
            current_scope_->pointers[i].last_action_loc = loc;
            return;
        }
    }

    TrackedPointer tp;
    tp.name = name;
    tp.state = state;
    tp.last_action_loc = loc;
    current_scope_->pointers.append(tp);
}

AllocationState DoubleFreeAnalyzer::getState(const char* name, SourceLocation* last_loc) {
    ScopeState* s = current_scope_;
    while (s) {
        for (size_t i = 0; i < s->pointers.length(); ++i) {
            if (strcmp(s->pointers[i].name, name) == 0) {
                if (last_loc) *last_loc = s->pointers[i].last_action_loc;
                return s->pointers[i].state;
            }
        }
        s = s->parent;
    }
    return AS_NOT_ALLOCATED;
}

bool DoubleFreeAnalyzer::isAllocationFunction(const char* name) {
    return strcmp(name, "arena_alloc") == 0 ||
           strcmp(name, "pool_alloc") == 0 ||
           strcmp(name, "safe_malloc") == 0 ||
           strcmp(name, "allocate_buffer") == 0 ||
           strcmp(name, "malloc") == 0 ||
           strcmp(name, "calloc") == 0 ||
           strcmp(name, "realloc") == 0;
}

bool DoubleFreeAnalyzer::isDeallocationFunction(const char* name) {
    return strcmp(name, "arena_free") == 0 ||
           strcmp(name, "pool_free") == 0 ||
           strcmp(name, "safe_free") == 0 ||
           strcmp(name, "release_buffer") == 0 ||
           strcmp(name, "free") == 0;
}

bool DoubleFreeAnalyzer::isBannedFunction(const char* name) {
    return strcmp(name, "malloc") == 0 ||
           strcmp(name, "calloc") == 0 ||
           strcmp(name, "realloc") == 0 ||
           strcmp(name, "free") == 0;
}

AllocationState DoubleFreeAnalyzer::mergeStates(AllocationState s1, AllocationState s2) {
    if (s1 == s2) return s1;
    return AS_UNKNOWN;
}
