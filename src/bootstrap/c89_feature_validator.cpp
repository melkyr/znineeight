#include "c89_feature_validator.hpp"
#include "ast.hpp"
#include "compilation_unit.hpp"
#include <cstdlib> // For abort()

C89FeatureValidator::C89FeatureValidator(CompilationUnit& unit) : unit(unit) {}

void C89FeatureValidator::validate(ASTNode* node) {
    visit(node);
}

void C89FeatureValidator::fatalError(SourceLocation location, const char* message) {
    unit.getErrorHandler().report(ERR_SYNTAX_ERROR, location, message);
    unit.getErrorHandler().printErrors();
    abort();
}

void C89FeatureValidator::visit(ASTNode* node) {
    if (!node) {
        return;
    }

    switch (node->type) {
        case NODE_ARRAY_TYPE:
            visitArrayType(node);
            break;
        case NODE_TRY_EXPR:
            visitTryExpr(node);
            break;
        case NODE_CATCH_EXPR:
            visitCatchExpr(node);
            break;
        case NODE_ORELSE_EXPR:
            visitOrelseExpr(node);
            break;

        // --- Recursive traversal for other node types ---
        case NODE_BINARY_OP:
            visit(node->as.binary_op->left);
            visit(node->as.binary_op->right);
            break;
        case NODE_UNARY_OP:
            visit(node->as.unary_op.operand);
            break;
        case NODE_FUNCTION_CALL:
            visit(node->as.function_call->callee);
            for (size_t i = 0; i < node->as.function_call->args->length(); ++i) {
                visit((*node->as.function_call->args)[i]);
            }
            break;
        case NODE_BLOCK_STMT:
            for (size_t i = 0; i < node->as.block_stmt.statements->length(); ++i) {
                visit((*node->as.block_stmt.statements)[i]);
            }
            break;
        case NODE_IF_STMT:
            visit(node->as.if_stmt->condition);
            visit(node->as.if_stmt->then_block);
            if (node->as.if_stmt->else_block) {
                visit(node->as.if_stmt->else_block);
            }
            break;
        case NODE_WHILE_STMT:
            visit(node->as.while_stmt.condition);
            visit(node->as.while_stmt.body);
            break;
        case NODE_RETURN_STMT:
            if (node->as.return_stmt.expression) {
                visit(node->as.return_stmt.expression);
            }
            break;
        case NODE_VAR_DECL:
            visit(node->as.var_decl->type);
            if (node->as.var_decl->initializer) {
                visit(node->as.var_decl->initializer);
            }
            break;
        case NODE_ASSIGNMENT:
            visit(node->as.assignment->lvalue);
            visit(node->as.assignment->rvalue);
            break;
        case NODE_COMPOUND_ASSIGNMENT:
            visit(node->as.compound_assignment->lvalue);
            visit(node->as.compound_assignment->rvalue);
            break;
        case NODE_FN_DECL:
            for (size_t i = 0; i < node->as.fn_decl->params->length(); ++i) {
                visit((*node->as.fn_decl->params)[i]->type);
            }
            if (node->as.fn_decl->return_type) {
                visit(node->as.fn_decl->return_type);
            }
            visit(node->as.fn_decl->body);
            break;
        case NODE_POINTER_TYPE:
            visit(node->as.pointer_type.base);
            break;
        case NODE_EXPRESSION_STMT:
            visit(node->as.expression_stmt.expression);
            break;
        default:
            // No action needed for literals, identifiers, etc.
            break;
    }
}

void C89FeatureValidator::visitArrayType(ASTNode* node) {
    if (node->as.array_type.size == NULL) {
        fatalError(node->loc, "Slices are not supported for C89 compatibility.");
    }
    visit(node->as.array_type.element_type);
}

void C89FeatureValidator::visitTryExpr(ASTNode* node) {
    fatalError(node->loc, "'try' expressions are not supported for C89 compatibility.");
}

void C89FeatureValidator::visitCatchExpr(ASTNode* node) {
    fatalError(node->loc, "'catch' expressions are not supported for C89 compatibility.");
}

void C89FeatureValidator::visitOrelseExpr(ASTNode* node) {
    fatalError(node->loc, "'orelse' expressions are not supported for C89 compatibility.");
}
