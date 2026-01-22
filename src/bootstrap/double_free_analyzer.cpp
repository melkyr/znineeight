#include "double_free_analyzer.hpp"
#include "utils.hpp"

DoubleFreeAnalyzer::DoubleFreeAnalyzer(CompilationUnit& unit)
    : unit_(unit) {
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
    }
}

void DoubleFreeAnalyzer::visitAssignment(ASTAssignmentNode* node) {
    visit(node->rvalue);
}

void DoubleFreeAnalyzer::visitFunctionCall(ASTFunctionCallNode* node) {
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
