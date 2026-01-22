#include "double_free_analyzer.hpp"
#include "utils.hpp"

DoubleFreeAnalyzer::DoubleFreeAnalyzer(CompilationUnit& unit)
    : unit_(unit), tracked_pointers_(unit.getArena()) {
}

void DoubleFreeAnalyzer::analyze(ASTNode* root) {
    if (!root) return;
    visit(root);
}

void DoubleFreeAnalyzer::visit(ASTNode* node) {
    if (!node) return;

    switch (node->type) {
        case NODE_BLOCK_STMT:
            visitBlockStmt(&node->as.block_stmt);
            break;
        case NODE_FN_DECL:
            visitFnDecl(node->as.fn_decl);
            break;
        case NODE_VAR_DECL:
            visitVarDecl(node->as.var_decl);
            break;
        case NODE_ASSIGNMENT:
            visitAssignment(node->as.assignment);
            break;
        case NODE_FUNCTION_CALL:
            visitFunctionCall(node->as.function_call);
            break;
        case NODE_DEFER_STMT:
            visitDeferStmt(&node->as.defer_stmt);
            break;
        case NODE_ERRDEFER_STMT:
            visitErrdeferStmt(&node->as.errdefer_stmt);
            break;
        case NODE_IF_STMT:
            visitIfStmt(node->as.if_stmt);
            break;
        case NODE_WHILE_STMT:
            visitWhileStmt(&node->as.while_stmt);
            break;
        case NODE_FOR_STMT:
            visitForStmt(node->as.for_stmt);
            break;
        case NODE_RETURN_STMT:
            visitReturnStmt(&node->as.return_stmt);
            break;
        default:
            // For now, no-op for other node types
            break;
    }
}

void DoubleFreeAnalyzer::visitBlockStmt(ASTBlockStmtNode* node) {
    if (!node->statements) return;
    for (size_t i = 0; i < node->statements->length(); ++i) {
        visit((*node->statements)[i]);
    }
}

void DoubleFreeAnalyzer::visitFnDecl(ASTFnDeclNode* node) {
    if (node->body) {
        visit(node->body);
    }
}

void DoubleFreeAnalyzer::visitVarDecl(ASTVarDeclNode* node) {
    if (node->initializer) {
        visit(node->initializer);
        if (isArenaAllocCall(node->initializer)) {
            TrackedPointer tp;
            tp.name = node->name;
            tp.allocated = true;
            tp.freed = false;
            tracked_pointers_.append(tp);
        }
    }
}

void DoubleFreeAnalyzer::visitAssignment(ASTAssignmentNode* node) {
    visit(node->rvalue);
    if (isArenaAllocCall(node->rvalue)) {
        const char* var_name = extractVariableName(node->lvalue);
        if (var_name) {
            TrackedPointer* tp = findTrackedPointer(var_name);
            if (tp) {
                tp->allocated = true;
                tp->freed = false;
            } else {
                TrackedPointer new_tp;
                new_tp.name = var_name;
                new_tp.allocated = true;
                new_tp.freed = false;
                tracked_pointers_.append(new_tp);
            }
        }
    }
}

void DoubleFreeAnalyzer::visitFunctionCall(ASTFunctionCallNode* node) {
    if (isArenaFreeCall(node)) {
        if (node->args && node->args->length() > 0) {
            const char* var_name = extractVariableName((*node->args)[0]);
            if (var_name) {
                TrackedPointer* tp = findTrackedPointer(var_name);
                if (tp) {
                    tp->freed = true;
                }
            }
        }
    }

    // Visit arguments
    if (node->args) {
        for (size_t i = 0; i < node->args->length(); ++i) {
            visit((*node->args)[i]);
        }
    }
}

void DoubleFreeAnalyzer::visitDeferStmt(ASTDeferStmtNode* node) {
    if (node->statement) {
        visit(node->statement);
    }
}

void DoubleFreeAnalyzer::visitErrdeferStmt(ASTErrDeferStmtNode* node) {
    if (node->statement) {
        visit(node->statement);
    }
}

void DoubleFreeAnalyzer::visitIfStmt(ASTIfStmtNode* node) {
    visit(node->condition);
    if (node->then_block) visit(node->then_block);
    if (node->else_block) visit(node->else_block);
}

void DoubleFreeAnalyzer::visitWhileStmt(ASTWhileStmtNode* node) {
    visit(node->condition);
    if (node->body) visit(node->body);
}

void DoubleFreeAnalyzer::visitForStmt(ASTForStmtNode* node) {
    // For loop components
    if (node->iterable_expr) visit(node->iterable_expr);
    if (node->body) visit(node->body);
}

void DoubleFreeAnalyzer::visitReturnStmt(ASTReturnStmtNode* node) {
    if (node->expression) {
        visit(node->expression);
    }
}

bool DoubleFreeAnalyzer::isArenaAllocCall(ASTNode* node) {
    if (!node || node->type != NODE_FUNCTION_CALL) return false;
    ASTFunctionCallNode* call = node->as.function_call;
    if (call->callee->type != NODE_IDENTIFIER) return false;
    return strcmp(call->callee->as.identifier.name, "arena_alloc") == 0;
}

bool DoubleFreeAnalyzer::isArenaFreeCall(ASTFunctionCallNode* call) {
    if (!call || call->callee->type != NODE_IDENTIFIER) return false;
    return strcmp(call->callee->as.identifier.name, "arena_free") == 0;
}

TrackedPointer* DoubleFreeAnalyzer::findTrackedPointer(const char* name) {
    for (size_t i = 0; i < tracked_pointers_.length(); ++i) {
        if (strcmp(tracked_pointers_[i].name, name) == 0) {
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
    // Handle other cases like member access if needed later
    return NULL;
}
