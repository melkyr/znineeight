#include "double_free_analyzer.hpp"
#include "utils.hpp"
#include "type_system.hpp"

DoubleFreeAnalyzer::DoubleFreeAnalyzer(CompilationUnit& unit)
    : unit_(unit), tracked_pointers_(unit.getArena()), deferred_actions_(unit.getArena()), current_scope_depth_(0) {
}

void DoubleFreeAnalyzer::analyze(ASTNode* root) {
    if (!root) return;
    visit(root);
}

void DoubleFreeAnalyzer::visit(ASTNode* node) {
    if (!node) return;

    switch (node->type) {
        case NODE_BLOCK_STMT:
            visitBlockStmt(node);
            break;
        case NODE_FN_DECL:
            visitFnDecl(node);
            break;
        case NODE_VAR_DECL:
            visitVarDecl(node);
            break;
        case NODE_ASSIGNMENT:
            visitAssignment(node);
            break;
        case NODE_FUNCTION_CALL:
            visitFunctionCall(node);
            break;
        case NODE_DEFER_STMT:
            visitDeferStmt(node);
            break;
        case NODE_ERRDEFER_STMT:
            visitErrdeferStmt(node);
            break;
        case NODE_IF_STMT:
            visitIfStmt(node);
            break;
        case NODE_WHILE_STMT:
            visitWhileStmt(node);
            break;
        case NODE_FOR_STMT:
            visitForStmt(node);
            break;
        case NODE_RETURN_STMT:
            visitReturnStmt(node);
            break;
        case NODE_EXPRESSION_STMT:
            visit(node->as.expression_stmt.expression);
            break;
        default:
            // For now, no-op for other node types
            break;
    }
}

void DoubleFreeAnalyzer::visitBlockStmt(ASTNode* node) {
    ASTBlockStmtNode& block = node->as.block_stmt;
    current_scope_depth_++;
    if (block.statements) {
        for (size_t i = 0; i < block.statements->length(); ++i) {
            visit((*block.statements)[i]);
        }
    }

    // Phase 6: Execute defers for THIS scope (LIFO)
    while (deferred_actions_.length() > 0 && deferred_actions_.back().scope_depth == current_scope_depth_) {
        DeferredAction action = deferred_actions_.back();
        deferred_actions_.pop_back();
        visit(action.statement);
    }

    // Phase 5: Check for leaks at scope exit
    size_t i = 0;
    while (i < tracked_pointers_.length()) {
        if (tracked_pointers_[i].scope_depth == current_scope_depth_) {
            if (tracked_pointers_[i].state == ALLOC_STATE_ALLOCATED) {
                char* msg = (char*)unit_.getArena().alloc(256);
                char* p = msg;
                size_t rem = 256;
                safe_append(p, rem, "Memory leak: '");
                safe_append(p, rem, tracked_pointers_[i].name);
                safe_append(p, rem, "' not freed");
                unit_.getErrorHandler().reportWarning(WARN_MEMORY_LEAK, node->loc, msg, unit_.getArena());
            }
            // Remove by swapping with last
            tracked_pointers_[i] = tracked_pointers_[tracked_pointers_.length() - 1];
            tracked_pointers_.pop_back();
            // Don't increment i, check the new element at i
        } else {
            i++;
        }
    }

    current_scope_depth_--;
}

void DoubleFreeAnalyzer::visitFnDecl(ASTNode* node) {
    ASTFnDeclNode* fn = node->as.fn_decl;
    // Phase 3: Clear tracked pointers for each function
    tracked_pointers_.clear();
    deferred_actions_.clear();
    current_scope_depth_ = 0;
    if (fn->body) {
        visit(fn->body);
    }
}

void DoubleFreeAnalyzer::visitVarDecl(ASTNode* node) {
    ASTVarDeclNode* var = node->as.var_decl;
    // Phase 4: Track all pointer variables
    if (node->resolved_type && node->resolved_type->kind == TYPE_POINTER) {
        TrackedPointer tp;
        tp.name = var->name;
        tp.scope_depth = current_scope_depth_;
        if (var->initializer && isArenaAllocCall(var->initializer)) {
            tp.state = ALLOC_STATE_ALLOCATED;
        } else {
            tp.state = ALLOC_STATE_UNINITIALIZED;
        }
        tracked_pointers_.append(tp);
    }

    if (var->initializer) {
        visit(var->initializer);
    }
}

void DoubleFreeAnalyzer::visitAssignment(ASTNode* node) {
    ASTAssignmentNode* assign = node->as.assignment;
    visit(assign->rvalue);
    if (isArenaAllocCall(assign->rvalue)) {
        const char* var_name = extractVariableName(assign->lvalue);
        if (var_name) {
            TrackedPointer* tp = findTrackedPointer(var_name);
            if (tp) {
                tp->state = ALLOC_STATE_ALLOCATED;
            } else {
                TrackedPointer new_tp;
                new_tp.name = var_name;
                new_tp.state = ALLOC_STATE_ALLOCATED;
                new_tp.scope_depth = current_scope_depth_;
                tracked_pointers_.append(new_tp);
            }
        }
    }
}

void DoubleFreeAnalyzer::visitFunctionCall(ASTNode* node) {
    ASTFunctionCallNode* call = node->as.function_call;
    if (isArenaFreeCall(call)) {
        if (call->args && call->args->length() > 0) {
            const char* var_name = extractVariableName((*call->args)[0]);
            if (var_name) {
                TrackedPointer* tp = findTrackedPointer(var_name);
                if (tp) {
                    switch (tp->state) {
                        case ALLOC_STATE_FREED: {
                            // Double free detected!
                            char* msg = (char*)unit_.getArena().alloc(256);
                            char* p = msg;
                            size_t rem = 256;
                            safe_append(p, rem, "Double free of pointer '");
                            safe_append(p, rem, var_name);
                            safe_append(p, rem, "'");
                            unit_.getErrorHandler().report(ERR_DOUBLE_FREE, node->loc, msg, unit_.getArena());
                            break;
                        }
                        case ALLOC_STATE_ALLOCATED:
                            tp->state = ALLOC_STATE_FREED;
                            break;
                        case ALLOC_STATE_UNINITIALIZED: {
                            char* msg = (char*)unit_.getArena().alloc(256);
                            char* p = msg;
                            size_t rem = 256;
                            safe_append(p, rem, "Freeing uninitialized pointer '");
                            safe_append(p, rem, var_name);
                            safe_append(p, rem, "'");
                            unit_.getErrorHandler().reportWarning(WARN_FREE_UNALLOCATED, node->loc, msg);
                            break;
                        }
                    }
                }
            }
        }
    }

    // Visit arguments
    if (call->args) {
        for (size_t i = 0; i < call->args->length(); ++i) {
            visit((*call->args)[i]);
        }
    }
}

void DoubleFreeAnalyzer::visitDeferStmt(ASTNode* node) {
    ASTDeferStmtNode& defer = node->as.defer_stmt;
    if (defer.statement) {
        DeferredAction action;
        action.statement = defer.statement;
        action.scope_depth = current_scope_depth_;
        deferred_actions_.append(action);
    }
}

void DoubleFreeAnalyzer::visitErrdeferStmt(ASTNode* node) {
    ASTErrDeferStmtNode& errdefer = node->as.errdefer_stmt;
    if (errdefer.statement) {
        DeferredAction action;
        action.statement = errdefer.statement;
        action.scope_depth = current_scope_depth_;
        deferred_actions_.append(action);
    }
}

void DoubleFreeAnalyzer::visitIfStmt(ASTNode* node) {
    ASTIfStmtNode* if_stmt = node->as.if_stmt;
    visit(if_stmt->condition);
    if (if_stmt->then_block) visit(if_stmt->then_block);
    if (if_stmt->else_block) visit(if_stmt->else_block);
}

void DoubleFreeAnalyzer::visitWhileStmt(ASTNode* node) {
    ASTWhileStmtNode& while_stmt = node->as.while_stmt;
    visit(while_stmt.condition);
    if (while_stmt.body) visit(while_stmt.body);
}

void DoubleFreeAnalyzer::visitForStmt(ASTNode* node) {
    ASTForStmtNode* for_stmt = node->as.for_stmt;
    // For loop components
    if (for_stmt->iterable_expr) visit(for_stmt->iterable_expr);
    if (for_stmt->body) visit(for_stmt->body);
}

void DoubleFreeAnalyzer::visitReturnStmt(ASTNode* node) {
    // Phase 6: Execute all defers (LIFO)
    // NOTE: In a simple path-blind visitor, executing defers here and then at block exit
    // would cause double execution. We rely on block exit for now.
    // In a more complex analyzer, we would stop visiting after return.

    ASTReturnStmtNode& ret = node->as.return_stmt;
    if (ret.expression) {
        visit(ret.expression);
    }
}

bool DoubleFreeAnalyzer::isArenaAllocCall(ASTNode* node) {
    if (!node || node->type != NODE_FUNCTION_CALL) return false;
    ASTFunctionCallNode* call = node->as.function_call;
    if (call->callee->type != NODE_IDENTIFIER) return false;
    return strings_equal(call->callee->as.identifier.name, "arena_alloc");
}

bool DoubleFreeAnalyzer::isArenaFreeCall(ASTFunctionCallNode* call) {
    if (!call || call->callee->type != NODE_IDENTIFIER) return false;
    return strings_equal(call->callee->as.identifier.name, "arena_free");
}

TrackedPointer* DoubleFreeAnalyzer::findTrackedPointer(const char* name) {
    for (size_t i = 0; i < tracked_pointers_.length(); ++i) {
        if (strings_equal(tracked_pointers_[i].name, name)) {
            return &tracked_pointers_[i];
        }
    }
    return NULL;
}

const char* DoubleFreeAnalyzer::extractVariableName(ASTNode* node) {
    if (!node) return NULL;
    if (node->type == NODE_IDENTIFIER) {
        return node->as.identifier.name;
    }
    return NULL;
}
